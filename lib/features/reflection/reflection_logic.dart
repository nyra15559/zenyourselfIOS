// [UPDATED] lib/features/reflection/reflection_logic.dart (Stand: 2025-11-19, v6.8.5a)
// ZenYourself — ReflectionLogic (Controller & Handler)
// PANDA-REFLECT-12.9 → v6.8.5a (Full-Session-Mode + lokale Session-ID)
//
// Änderungen ggü. v6.8.4:
// • Neu: _sessionId + startNewSession() – lokale Session-Kennung pro Reflexionslauf.
// • Neu: _ensureSessionId() + Payload-Erweiterung (session_id/local_session_id) für Meta & MemoryService.
// • Fix: Memory-Proposal-Aktionen ("Einsicht übernehmen" / "Später entscheiden") nur, wenn Vorschläge vorliegen.
//
// v6.8.5a (2025-11-19):
// • _ensureSessionId() jetzt auch in send(), handleAction() und completeClosureWithMood() → konsistente local_session_id.
// • Fix: Bei geblocktem Send (Send-Gap) wird der Typing-Indicator sofort wieder deaktiviert.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

// Guidance-DTOs
import '../../services/guidance/dtos.dart' as gdt;

// Guidance-Service
import '../../services/guidance_service.dart';

// Memory
import '../../core/memory/memory_service.dart';

// (optional) API-Service für Stimmungs-Klassifizierung; defensiv genutzt
import '../../services/core/api_service.dart' as api;

// (optional) Kutsche 3 Helper-Mappers für Timeline-Topic (falls vorhanden)
import '../../services/guidance/helper_mappers.dart' as hm;

const Duration _kNetTimeout = Duration(seconds: 18);
const Duration _kTypingGuard = Duration(seconds: 12); // Fallback, falls etwas hängt

const int _kMaxHistoryTurns = 20;  // ≈ Anzahl Nachrichten (User+Assistant) pro Session in Payload
const double _kTrimFraction = 0.2; // 20 % der ältesten Einträge kappen, wenn Cap überschritten ist
const int _kTrimMin = 2;           // mindestens 2 Einträge entfernen, falls getrimmt wird

// --------------------------- UI Events (für View) -----------------------------
enum UIEventKind {
  appendUser,
  insertTypingPlaceholder,
  removeTypingPlaceholder,
  scrollToEnd,
  openDualMoodPicker,        // → BottomSheet mit Kopf/Körper 0–4 anzeigen
}

class UIEvent {
  final UIEventKind kind;
  final String? text;        // optional: Title/Hint (z. B. für Picker)
  final Duration? delay;
  const UIEvent._(this.kind, {this.text, this.delay});

  factory UIEvent.appendUser(String text) =>
      UIEvent._(UIEventKind.appendUser, text: text);
  factory UIEvent.insertTyping() =>
      const UIEvent._(UIEventKind.insertTypingPlaceholder);
  factory UIEvent.removeTyping() =>
      const UIEvent._(UIEventKind.removeTypingPlaceholder);
  factory UIEvent.scrollToEnd([Duration delay = const Duration(milliseconds: 200)]) =>
      UIEvent._(UIEventKind.scrollToEnd, delay: delay);
  factory UIEvent.openDualMoodPicker([String title = 'Wähle Kopf & Körper']) =>
      UIEvent._(UIEventKind.openDualMoodPicker, text: title);
}

// --------------------------- Public VM ---------------------------------------

class ReflectionVM {
  final String mirror;
  final String question;
  final List<String> answerChips; // max 3, min 2
  final List<String> talkLines;   // ≤2
  final String? helperSuggestion; // 0–1 Satz
  final bool risk;
  final bool allowClosure;
  final bool moodPrompt;
  final String? hopeText;
  final List<String> topicChips;

  const ReflectionVM({
    required this.mirror,
    required this.question,
    required this.answerChips,
    required this.talkLines,
    required this.helperSuggestion,
    required this.risk,
    required this.allowClosure,
    required this.moodPrompt,
    required this.hopeText,
    required this.topicChips,
  });

  bool get hasQuestion => question.trim().isNotEmpty;

  ReflectionVM copyWith({
    String? mirror,
    String? question,
    List<String>? answerChips,
    List<String>? talkLines,
    String? helperSuggestion,
    bool? risk,
    bool? allowClosure,
    bool? moodPrompt,
    String? hopeText,
    List<String>? topicChips,
  }) {
    return ReflectionVM(
      mirror: mirror ?? this.mirror,
      question: question ?? this.question,
      answerChips: answerChips ?? this.answerChips,
      talkLines: talkLines ?? this.talkLines,
      helperSuggestion: helperSuggestion ?? this.helperSuggestion,
      risk: risk ?? this.risk,
      allowClosure: allowClosure ?? this.allowClosure,
      moodPrompt: moodPrompt ?? this.moodPrompt,
      hopeText: hopeText ?? this.hopeText,
      topicChips: topicChips ?? this.topicChips,
    );
  }
}

// --------------------------- Actions (public model) --------------------------

class AvailableAction {
  final String id;     // 'topic_switch', 'essence', 'example', 'abort', 'memory_proposal'
  final String label;  // UI-Text
  final String? note;  // Zusatzinfo (z. B. Auszug)
  const AvailableAction({required this.id, required this.label, this.note});

  AvailableAction copyWith({String? label, String? note}) =>
      AvailableAction(id: id, label: label ?? this.label, note: note ?? this.note);
}

// --------- Private Structs ---------------------------------------------------

class _MemPrep {
  final bool consent;
  final Map<String, dynamic>? memories;
  const _MemPrep({required this.consent, required this.memories});
}

// --------------------------- Controller --------------------------------------

class ReflectionController extends ChangeNotifier {
  ReflectionController({
    Duration sendMinGap = const Duration(milliseconds: 420),
  }) : _sendMinGap = sendMinGap {
    // Consent/Active best-effort asynchron initialisieren
    Future.microtask(() async {
      try { await MemoryService.instance.warmup(); } catch (_) {}
      await _refreshConsentAndActive();
      notifyListeners();
    });
  }

  // ---------------- Public (readonly) state ----------------------------------

  bool get loading => _loading;
  ReflectionVM? get vm => _vm;
  gdt.ReflectionSession? get session => _apiSession;
  String? get bridgeText => _bridgeText;
  bool get memoryConsent => _memoryConsent;
  bool get memoryActive => _memoryActive;

  bool get hasSeenIntroThisSession => _hasSeenIntroThisSession;
  int get roundCount => (_apiSession?.turnIndex ?? 0);
  bool get canShowIntro => !_hasSeenIntroThisSession && roundCount == 0 && _vm == null;

  List<String> get facetQueue => List.unmodifiable(_facetQueue);
  String? get activeFacet => _activeFacet;
  String? get topicPin => _topicPin;
  List<AvailableAction> get availableActions => List.unmodifiable(_availableActions);
  bool get inSkillFlow => _inSkillFlow;

  // History (read-only view für UI/Diagnostics)
  List<gdt.HistoryTurn> get history => List.unmodifiable(_history);

  // Signal an die View, ob UI den Mood-Picker anbieten soll
  bool get shouldPromptMood => _vm?.moodPrompt == true;

  // Memory-Proposals (Kutsche 4)
  bool get hasMemoryProposal => _insightProposals.isNotEmpty;
  List<Map<String, dynamic>> get memoryProposals =>
      List.unmodifiable(_insightProposals);

  // ---------------- UI Event Sink (optional) ----------------------------------

  void attachUiEventSink(void Function(UIEvent e) sink) => _uiEventSink = sink;
  void detachUiEventSink() => _uiEventSink = null;

  // ---------------- Private state --------------------------------------------

  final Duration _sendMinGap;

  bool _loading = false;
  gdt.ReflectionSession? _apiSession; // Session vom Server (für nextTurn*)
  ReflectionVM? _vm;
  String? _bridgeText;

  // Lokale Session-ID (Client-Perspektive, unabhängig von thread_id des Workers)
  String? _sessionId;

  // Thread-ID (aus Provider – dynamisch gelesen)
  String? _threadId;

  DateTime? _lastSendAt;
  Timer? _pendingSend;
  bool _actionUsedInThisSession = false;

  bool _memoryConsent = false;     // User-Consent (Privacy)
  bool _memoryActive = true;       // Lokaler Memory-Toggle/Status
  bool _lastClientMemoryFlag = false; // wird pro Call gesetzt (consent && active)

  bool _hasSeenIntroThisSession = false;

  final List<String> _facetQueue = <String>[];
  String? _activeFacet;
  String? _topicPin;
  final List<AvailableAction> _availableActions = <AvailableAction>[];
  bool _inSkillFlow = false;

  bool _typingActive = false;
  Timer? _typingGuardTimer;

  void Function(UIEvent e)? _uiEventSink;

  // History buffer (User/Assistant/System) — nur in-memory, pro Session
  final List<gdt.HistoryTurn> _history = <gdt.HistoryTurn>[];

  // Mood-Prompt Guard (pro TurnIndex nur 1× öffnen)
  int? _lastMoodPromptAtTurn;

  // Memory-Proposal Buffer (sanitisierte Maps mit key 'line' usw.)
  final List<Map<String, dynamic>> _insightProposals = <Map<String, dynamic>>[];

  // ---------------- Init / Bridge / Thread-ID --------------------------------

  /// Liest die aktuelle Thread-ID aus einem beliebigen Provider-Objekt, das ein `id`-Feld hat.
  void wireSessionFromContext(BuildContext context) {
    try {
      final obj = context.read<Object?>();
      final dyn = obj as dynamic;
      final id = dyn?.id?.toString();
      if (id != null && id.trim().isNotEmpty) {
        _threadId = id.trim();
      }
    } catch (_) {/* ignore */}
  }

  Future<void> prefetchBridge() async {
    try {
      final recall = await MemoryService.instance.recall(limit: 6);
      await _refreshConsentAndActive();
      _bridgeText = _composeBridgeText(recall);
      notifyListeners();
    } catch (_) {/* never throw */}
  }

  /// Extern aufrufbar, wenn Privacy/Mem-Switch umgelegt wurde:
  /// • erzwingt neue thread_id (lokal leeren → App liefert neu)
  /// • setzt History & Session zurück
  void onPrivacyOrMemoryToggleChanged({bool? consent, bool? active, String? newThreadId}) {
    if (consent != null) _memoryConsent = consent;
    if (active != null) _memoryActive = active;

    _apiSession = null;
    _vm = null;
    _history.clear();
    _facetQueue.clear();
    _activeFacet = null;
    _topicPin = null;
    _availableActions.clear();
    _inSkillFlow = false;
    _hasSeenIntroThisSession = false;
    _lastMoodPromptAtTurn = null;

    _insightProposals.clear();
    _sessionId = null;

    // neue Thread-ID erzwingen: lokal leeren oder explizit setzen
    _threadId = (newThreadId != null && newThreadId.trim().isNotEmpty) ? newThreadId.trim() : null;

    notifyListeners();
  }

  void setMemoryConsent(bool consent) {
    _memoryConsent = consent;
    notifyListeners();
  }

  void setMemoryActive(bool active) {
    _memoryActive = active;
    notifyListeners();
  }

  /// (Legacy) Setzt eine bereits vorhandene API-Session (z. B. nach Navigation).
  void adoptApiSession(gdt.ReflectionSession session) {
    _apiSession = session;
    notifyListeners();
  }

  void markIntroSeen() {
    _hasSeenIntroThisSession = true;
  }

  /// Startet eine komplett neue Reflexions-Session (Client-Seite).
  /// Wird z.B. beim Öffnen des Screens aufgerufen.
  void startNewSession() {
    reset();
    _ensureSessionId();
  }

  void reset() {
    _debounceCancel();
    _stopTypingGuard();
    _emitTypingOff();
    _loading = false;
    _apiSession = null;
    _vm = null;
    _bridgeText = null;
    _actionUsedInThisSession = false;
    _threadId = null;
    _sessionId = null;

    _facetQueue.clear();
    _activeFacet = null;
    _topicPin = null;
    _availableActions.clear();
    _inSkillFlow = false;

    _hasSeenIntroThisSession = false;
    _lastMoodPromptAtTurn = null;

    _history.clear();
    _insightProposals.clear();

    notifyListeners();
  }

  // ---------------- Sending ---------------------------------------------------

  /// Einfache öffentliche API, die Start/Next intern entscheidet.
  Future<void> sendUser(String text, {bool fromVoice = false, BuildContext? context}) async {
    _ensureSessionId();
    if (_apiSession == null) {
      await start(text, fromVoice: fromVoice, context: context);
    } else {
      await send(text, context: context);
    }
  }

  Future<void> start(String text, {bool fromVoice = false, BuildContext? context}) async {
    if (context != null) wireSessionFromContext(context);

    _ensureSessionId();

    _debounceCancel();
    if (!_gateSendNow()) return;

    text = _sanitizeInput(text);
    if (text.isEmpty) return;

    _localEchoBeforeCall(text);
    _appendUserToHistory(text);

    _hasSeenIntroThisSession = true;

    // Memories + Flag vorbereiten (consent && active)
    final _MemPrep mem = await _prepareMemForCall(userText: text);

    _setLoading(true);
    try {
      final svc = GuidanceService.instance;
      final meta = _buildMeta(); // enthält aktuelles _lastClientMemoryFlag
      gdt.ReflectionTurn turn;

      try {
        final dyn = svc as dynamic;
        turn = await (dyn.startSessionFull(
          text: text,
          session: null,
          locale: 'de',
          tz: 'Europe/Zurich',
          memories: mem.memories,
          memoryConsent: mem.consent,
          meta: meta,
          clientContext: {
            'mode': fromVoice ? 'voice' : 'text',
            'source': 'reflection_logic',
            if (_threadId != null) 'thread_id': _threadId,
          },
        ) as Future<gdt.ReflectionTurn>).timeout(_kNetTimeout);
      } catch (_) {
        turn = await svc
            .startSessionFull(
              text: text,
              session: null,
              locale: 'de',
              tz: 'Europe/Zurich',
              memories: mem.memories,
              memoryConsent: mem.consent,
              meta: meta,
              clientContext: {
                'mode': fromVoice ? 'voice' : 'text',
                'source': 'reflection_logic',
                if (_threadId != null) 'thread_id': _threadId,
              },
            )
            .timeout(_kNetTimeout);
      }

      _apiSession = _coerceSession(turn);
      _appendAssistantToHistory(turn);

      _vm = _buildVM(turn);
      _actionUsedInThisSession = false;

      // Kutsche 4: Memory-Proposals aus Turn übernehmen
      _ingestMemoryProposalsFromTurn(turn);

      _updateFacetsFromTurn(turn);
      _recomputeAvailableActions();

      _emitScrollToEnd(const Duration(milliseconds: 160));
      _maybeTriggerMoodPromptUI();

      // ---- After-Turn-Hook (Timeline + Memory) – fire & forget --------------
      Future<void>(() async {
        try { await _afterTurnBookkeeping(turn, lastUserText: text); } catch (_) {}
      });
    } catch (_) {
      _vm = const ReflectionVM(
        mirror: 'Ich höre dich. Ich bleibe bei dir.',
        question: '',
        answerChips: <String>[],
        talkLines: <String>[],
        helperSuggestion: null,
        risk: false,
        allowClosure: false,
        moodPrompt: false,
        hopeText: null,
        topicChips: <String>[],
      );
      _insightProposals.clear();
      _recomputeAvailableActions();
    } finally {
      _emitTypingOff();
      _setLoading(false);
    }
  }

  Future<void> send(String text, {BuildContext? context}) async {
    if (context != null && _threadId == null) {
      wireSessionFromContext(context);
    }
    _ensureSessionId();
    _emitTypingOn();
    _pendingSend?.cancel();
    _pendingSend = Timer(const Duration(milliseconds: 220), () async {
      await _sendNow(text);
    });
  }

  Future<void> _sendNow(String text) async {
    if (!_gateSendNow()) {
      _emitTypingOff(); // Fix: bei geblocktem Send Typing sofort deaktivieren
      return;
    }

    text = _sanitizeInput(text);
    if (text.isEmpty && _apiSession == null) return;

    if (_apiSession == null) {
      await start(text);
      return;
    }

    // Memories + Flag vorbereiten (consent && active)
    final _MemPrep mem = await _prepareMemForCall(userText: text);

    _setLoading(true);
    try {
      _localEchoBeforeCall(text);
      _appendUserToHistory(text);

      final svc = GuidanceService.instance;
      gdt.ReflectionTurn turn;

      try {
        final dyn = svc as dynamic;
        turn = await (dyn.nextTurnFull(
          session: _apiSession!,
          text: text,
          locale: 'de',
          tz: 'Europe/Zurich',
          history: _history, // typed History
          memories: mem.memories,
          memoryConsent: mem.consent,
          meta: _buildMeta(),
          clientContext: {
            'mode': 'text',
            'source': 'reflection_logic',
            if (_threadId != null) 'thread_id': _threadId,
          },
        ) as Future<gdt.ReflectionTurn>).timeout(_kNetTimeout);
      } catch (_) {
        turn = await GuidanceService.instance
            .nextTurnFull(
              session: _apiSession!,
              text: text,
              locale: 'de',
              tz: 'Europe/Zurich',
              history: _history, // typed History (wird intern ggf. gemappt)
              memories: mem.memories,
              memoryConsent: mem.consent,
              meta: _buildMeta(),
              clientContext: {
                'mode': 'text',
                'source': 'reflection_logic',
                if (_threadId != null) 'thread_id': _threadId,
              },
            )
            .timeout(_kNetTimeout);
      }

      _apiSession = _coerceSession(turn);
      _appendAssistantToHistory(turn);

      _vm = _buildVM(turn);
      _inSkillFlow = false;

      // Kutsche 4: Memory-Proposals aus Turn übernehmen
      _ingestMemoryProposalsFromTurn(turn);

      _updateFacetsFromTurn(turn);
      _recomputeAvailableActions();

      _emitScrollToEnd(const Duration(milliseconds: 160));
      _maybeTriggerMoodPromptUI();

      // ---- After-Turn-Hook (Timeline + Memory) – fire & forget --------------
      Future<void>(() async {
        try { await _afterTurnBookkeeping(turn, lastUserText: text); } catch (_) {}
      });
    } catch (_) {/* keep old vm */} finally {
      _emitTypingOff();
      _setLoading(false);
    }
  }

  // ---------------- Actions ---------------------------------------------------

  Future<void> handleAction(gdt.UserAction action) async {
    if (_apiSession == null) return;
    if (_actionUsedInThisSession) return;
    _ensureSessionId();
    if (!_gateSendNow()) return;

    _emitTypingOn();

    _setLoading(true);
    try {
      final svc = GuidanceService.instance;
      gdt.ReflectionTurn turn;

      try {
        final dyn = svc as dynamic;
        final Future<gdt.ReflectionTurn>? fut = dyn.nextTurnAction?.call(
          session: _apiSession!,
          action: action,
          locale: 'de',
          tz: 'Europe/Zurich',
          meta: _buildMeta(),
        );
        if (fut != null) {
          turn = await fut.timeout(_kNetTimeout);
        } else {
          try {
            turn = await (dyn.nextTurnFull(
              session: _apiSession!,
              text: '',
              locale: 'de',
              tz: 'Europe/Zurich',
              history: _history,
              memories: (await _prepareMemForCall(userText: '')).memories,
              memoryConsent: _memoryConsent,
              meta: _buildMeta(),
              clientContext: {
                'mode': 'action',
                'source': 'reflection_logic',
                if (_threadId != null) 'thread_id': _threadId,
              },
            ) as Future<gdt.ReflectionTurn>).timeout(_kNetTimeout);
          } catch (_) {
            turn = await svc
                .nextTurnFull(
                  session: _apiSession!,
                  text: '',
                  locale: 'de',
                  tz: 'Europe/Zurich',
                  memories: (await _prepareMemForCall(userText: '')).memories,
                  memoryConsent: _memoryConsent,
                  meta: _buildMeta(),
                  clientContext: {
                    'mode': 'action',
                    'source': 'reflection_logic',
                    if (_threadId != null) 'thread_id': _threadId,
                  },
                )
                .timeout(_kNetTimeout);
          }
        }
      } catch (_) {
        turn = await svc
            .nextTurnFull(
              session: _apiSession!,
              text: '',
              locale: 'de',
              tz: 'Europe/Zurich',
              memories: (await _prepareMemForCall(userText: '')).memories,
              memoryConsent: _memoryConsent,
              meta: _buildMeta(),
              clientContext: {
                'mode': 'action',
                'source': 'reflection_logic',
                if (_threadId != null) 'thread_id': _threadId,
              },
            )
            .timeout(_kNetTimeout);
      }

      _apiSession = _coerceSession(turn);
      _appendAssistantToHistory(turn);

      _vm = _buildVM(turn);
      _actionUsedInThisSession = true;

      // Kutsche 4: Memory-Proposals aus Turn übernehmen
      _ingestMemoryProposalsFromTurn(turn);

      _updateFacetsFromTurn(turn);
      _recomputeAvailableActions();

      _emitScrollToEnd(const Duration(milliseconds: 160));
      _maybeTriggerMoodPromptUI();

      // ---- After-Turn-Hook (Timeline + Memory) – fire & forget --------------
      Future<void>(() async {
        try { await _afterTurnBookkeeping(turn, lastUserText: null); } catch (_) {}
      });
    } catch (_) {/* ignore */} finally {
      _emitTypingOff();
      _setLoading(false);
    }
  }

  // ---------- High-level Router ----------------------------------------------

  static const String _ACT_TOPIC_SWITCH = 'topic_switch';
  static const String _ACT_ESSENCE = 'essence';
  static const String _ACT_EXAMPLE = 'example';
  static const String _ACT_ABORT = 'abort';

  // Kutsche 4 – Memory-Proposal Actions (intern genutzt)
  static const String _ACT_MEMORY_PROPOSAL = 'memory_proposal';
  static const String _ACT_MEMORY_PROPOSAL_LATER = 'memory_proposal_later';

  Future<void> runAction(String id, {String? note}) async {
    if (id == _ACT_MEMORY_PROPOSAL) {
      await saveMemoryProposal();
      return;
    } else if (id == _ACT_MEMORY_PROPOSAL_LATER) {
      skipMemoryProposal();
      return;
    }

    if (id == _ACT_TOPIC_SWITCH) {
      if (_activeFacet != null) {
        _facetQueue.add(_activeFacet!);
      }
      String? nextFacet;
      if (_facetQueue.isNotEmpty) {
        nextFacet = _facetQueue.removeAt(0);
      }
      _activeFacet = nextFacet;
      if ((_activeFacet ?? '').trim().isNotEmpty) {
        _topicPin = _activeFacet;
        note = (_activeFacet ?? '').trim();
      }
      _inSkillFlow = false;
    } else if (id == _ACT_ESSENCE || id == _ACT_EXAMPLE) {
      _inSkillFlow = true;
      if ((note ?? '').trim().isEmpty) {
        note = _topicPin ?? _activeFacet ?? (vm?.topicChips.isNotEmpty == true ? vm!.topicChips.first : null);
      }
    } else if (id == _ACT_ABORT) {
      _inSkillFlow = false;
      _activeFacet = null;
    }

    final ua = _toUserAction(id, note: note);
    await handleAction(ua);
  }

  Future<bool> tryVoiceTrigger(String utterance) async {
    final u = _sanitizeInput(utterance).toLowerCase();
    bool hasAny(String s) => u.contains(s);

    if (hasAny('abbrechen') || hasAny('stop') || hasAny('stopp') || hasAny('halt') || hasAny('zurück')) {
      await runAction(_ACT_ABORT);
      return true;
    }

    if (hasAny('thema wechseln') ||
        (hasAny('wechsel') && hasAny('thema')) ||
        hasAny('anderes thema') ||
        hasAny('topic wechseln')) {
      await runAction(_ACT_TOPIC_SWITCH);
      return true;
    }

    if (hasAny('essenz') ||
        hasAny('kernaussage') ||
        hasAny('kern') ||
        hasAny('zusammenfassung') ||
        hasAny('essence')) {
      await runAction(_ACT_ESSENCE);
      return true;
    }

    if (hasAny('beispiel') ||
        hasAny('sample') ||
        hasAny('zeige ein beispiel') ||
        hasAny('gib mir ein beispiel')) {
      await runAction(_ACT_EXAMPLE);
      return true;
    }

    return false;
  }

  // ---------------- Mood / Closure -------------------------------------------

  void _maybeTriggerMoodPromptUI() {
    if (_vm?.moodPrompt == true && _apiSession?.turnIndex != null) {
      final idx = _apiSession!.turnIndex!;
      if (_lastMoodPromptAtTurn != idx) {
        _lastMoodPromptAtTurn = idx;
        _uiEventSink?.call(UIEvent.openDualMoodPicker('Wähle Kopf & Körper'));
      }
    }
  }

  Future<void> completeClosureWithMood(int mental, int physical, {DateTime? when}) async {
    // Robust: MemoryService.saveMoodEntry mit beliebiger Signatur
    try {
      final ms = (MemoryService.instance as dynamic);
      final ts = when ?? DateTime.now();
      try {
        // bevorzugt: positional (ts, mental, physical)
        await ms.saveMoodEntry(ts, mental.clamp(0, 4), physical.clamp(0, 4));
      } catch (_) {
        try {
          // named: when/ts + mental/physical
          await ms.saveMoodEntry(
            when: ts,
            ts: ts,
            mental: mental.clamp(0, 4),
            physical: physical.clamp(0, 4),
          );
        } catch (_) {
          // minimal: separate Setter/Save-Pfade ignorieren leise
        }
      }
    } catch (_) {/* ignore */}

    if (_apiSession == null) return;

    _ensureSessionId();
    _emitTypingOn();
    _setLoading(true);
    try {
      final svc = GuidanceService.instance;
      final _MemPrep mem = await _prepareMemForCall(userText: '');
      gdt.ReflectionTurn turn;

      try {
        // Soft-Closure über nextTurnFull ohne User-Text
        turn = await svc
            .nextTurnFull(
              session: _apiSession!,
              text: '',
              locale: 'de',
              tz: 'Europe/Zurich',
              history: _history,
              memories: mem.memories,
              memoryConsent: mem.consent,
              meta: _buildMeta(),
              clientContext: {
                'mode': 'closure',
                'source': 'reflection_logic',
                if (_threadId != null) 'thread_id': _threadId,
              },
            )
            .timeout(_kNetTimeout);
      } catch (_) {
        // Bei Fehler: VM/State nicht überschreiben
        return;
      }

      _apiSession = _coerceSession(turn);
      _appendAssistantToHistory(turn);

      _vm = _buildVM(turn);
      _updateFacetsFromTurn(turn);
      _recomputeAvailableActions();

      _emitScrollToEnd(const Duration(milliseconds: 160));

      // After-Turn-Hook auch beim Abschluss (Timeline + Memory)
      Future<void>(() async {
        try { await _afterTurnBookkeeping(turn, lastUserText: null); } catch (_) {}
      });
    } finally {
      _emitTypingOff();
      _setLoading(false);
    }
  }

  // ---------------- Hybrid Note ----------------------------------------------

  String composeHybridNote({required String typed, String? transcript}) {
    final t = _sanitizeInput(typed);
    final stt = _sanitizeInput(transcript ?? '');
    if (t.isEmpty && stt.isEmpty) return '';
    if (t.isEmpty) return stt;
    if (stt.isEmpty) return t;

    if (_isSubsequence(stt, t)) return t;
    if (_isSubsequence(t, stt)) return stt;

    final joined = '$t\n$stt'.trim();
    return _cap(joined, 800);
  }

  // ---------------- Helpers: VM-Bau ------------------------------------------

  ReflectionVM _buildVM(gdt.ReflectionTurn t) {
    final mirror = _cap((t.mirror ?? '').trim(), 640);

    // Frage defensiv auslesen: primaryQuestion > (dynamic)question > ''
    String q = '';
    final pq = (t.primaryQuestion ?? '').toString().trim();
    if (pq.isNotEmpty) {
      q = pq;
    } else {
      try {
        final dynQ = (t as dynamic).question?.toString().trim();
        if ((dynQ ?? '').isNotEmpty) q = dynQ!;
      } catch (_) {/* ignore */}
    }

    final talk = (t.talk ?? const <String>[])
        .map((e) => (e).trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();

    final baseChips = (t.answerHelpers ?? const <String>[])
        .map(_sanitizeHelper)
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
    final chips = _ensureMinTwoChips(baseChips, q: q);

    final helperSuggestion = (t.helperSuggestion ?? '').trim().isEmpty
        ? null
        : t.helperSuggestion!.trim();

    // --- Risk alias-safe (riskFlag + riskLevel/risk_level + risk)
    final String rf = (t.riskFlag ?? '').toString().toLowerCase().trim();
    String rl = '';
    bool rbool = false;
    try {
      final dyn = t as dynamic;
      rl = (dyn.riskLevel ?? dyn.risk_level ?? '').toString().toLowerCase().trim();
      rbool = (dyn.risk == true);
    } catch (_) {/* ignore */}
    final bool risk = (rf == 'crisis' || rf == 'support') ||
        rl == 'mild' || rl == 'high' || rbool;

    final allowClosure =
        ((t.flow?.recommendEnd ?? false) == true) || ((t.flow?.moodPrompt ?? false) == true);
    final moodPrompt = (t.flow?.moodPrompt ?? false) == true;

    final hopeText = _extractHopeText(t);

    final topicChips = <String>{
      ...((t.topicSuggestions ?? const <String>[])
          .map((s) => (s).toString().trim())
          .where((s) => s.isNotEmpty)),
      ...(((t.analysis?.topicSuggestions) ?? const <String>[])
          .map((s) => (s).toString().trim())
          .where((s) => s.isNotEmpty)),
    }.toList();

    return ReflectionVM(
      mirror: mirror,
      question: q,
      answerChips: chips,
      talkLines: talk,
      helperSuggestion: helperSuggestion,
      risk: risk,
      allowClosure: allowClosure,
      moodPrompt: moodPrompt,
      hopeText: hopeText,
      topicChips: topicChips,
    );
  }

  // ---------------- Interna ---------------------------------------------------

  gdt.ReflectionSession _coerceSession(gdt.ReflectionTurn t) => t.session;

  String _sanitizeInput(String s) {
    var x = (s).trim();
    if (x.isEmpty) return '';
    x = _cap(x, 800);
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  void _ensureSessionId() {
    if (_sessionId != null && _sessionId!.trim().isNotEmpty) return;
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
  }

  bool _gateSendNow() {
    final now = DateTime.now();
    if (_lastSendAt == null) {
      _lastSendAt = now;
      return true;
    }
    final dt = now.difference(_lastSendAt!);
    if (dt >= _sendMinGap) {
      _lastSendAt = now;
      return true;
    }
    return false;
  }

  void _debounceCancel() {
    _pendingSend?.cancel();
    _pendingSend = null;
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  // --- S1.1/S2.1: Local Echo & Typing Helpers --------------------------------

  void _localEchoBeforeCall(String text) {
    _emitAppendUser(text);
    notifyListeners();
    _emitScrollToEnd(const Duration(milliseconds: 200));
    _emitTypingOn();
  }

  void _emitAppendUser(String text) =>
      _uiEventSink?.call(UIEvent.appendUser(text));

  void _emitTypingOn() {
    final wasActive = _typingActive;
    _typingActive = true;
    if (!wasActive) {
      _uiEventSink?.call(UIEvent.insertTyping());
    }
    _startTypingGuard();
  }

  void _emitTypingOff() {
    if (!_typingActive) {
      _stopTypingGuard();
      return;
    }
    _typingActive = false;
    _stopTypingGuard();
    _uiEventSink?.call(UIEvent.removeTyping());
  }

  void _startTypingGuard() {
    _typingGuardTimer?.cancel();
    _typingGuardTimer = Timer(_kTypingGuard, () {
      _emitTypingOff();
      notifyListeners();
    });
  }

  void _stopTypingGuard() {
    _typingGuardTimer?.cancel();
    _typingGuardTimer = null;
  }

  void _emitScrollToEnd(Duration delay) =>
    _uiEventSink?.call(UIEvent.scrollToEnd(delay));

  String _sanitizeHelper(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'[?؟]+$'), '');
    s = s.replaceAll(RegExp(r'\s*[:：.。…]+\s*$'), '').trim();
    if (s.length > 72) s = '${s.substring(0, 72).trimRight()}…';
    s = '$s… ';
    return s;
  }

  List<String> _ensureMinTwoChips(List<String> chips, {required String q}) {
    if (chips.length >= 2) return chips.take(3).toList();
    final List<String> out = List<String>.from(chips);
    final fallback =
        (q.trim().isNotEmpty) ? 'Wichtig ist mir außerdem … ' : 'Noch etwas dazu … ';
    out.add(fallback);
    return out.take(3).toList();
  }

  bool _isSubsequence(String a, String b) {
    final aa = a.toLowerCase();
    final bb = b.toLowerCase();
    return bb.contains(aa) ||
        aa.split(RegExp(r'\s+')).every((w) => w.isEmpty || bb.contains(w));
  }

  String _cap(String s, int maxChars) {
    if (s.length <= maxChars) return s;
    final cut = s.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    final base = (lastSpace >= 40 ? cut.substring(0, lastSpace) : cut).trimRight();
    return '$base…';
  }

  Map<String, dynamic> _buildMeta() {
    final bool reopen = (_vm?.allowClosure == true);
    // meta.flags.client_memory = dynamisch gemäß letztem Prep
    return {
      'ui': {
        'controller': 'reflection_logic',
        'version': 'v6.8.5a',
      },
      'memory': {
        'bridge': _bridgeText,
      },
      'flags': {
        'client_memory': _lastClientMemoryFlag, // *** dynamisch ***
        'reopen': reopen,                       // *** Closure-Recovery ***
      },
      'thread': {
        if (_threadId != null) 'id': _threadId,
        if (_sessionId != null) 'session_id': _sessionId,
        if (_apiSession?.turnIndex != null) 'turn_index': _apiSession!.turnIndex,
      },
      'intro': {
        'has_seen_intro_this_session': _hasSeenIntroThisSession,
        'round_count': roundCount,
      },
      'client': {
        'source': 'reflection_logic',
        if (_inSkillFlow) 'skill': 'on',
      },
      'tz': 'Europe/Zurich',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String? _composeBridgeText(dynamic recall) {
    if (recall == null) return null;
    final tokens = <String>[];

    void addToken(String? s) {
      final t = (s ?? '').trim();
      if (t.isEmpty) return;
      final key = t.toLowerCase();
      if (!tokens.any((x) => x.toLowerCase() == key)) tokens.add(t);
    }

    if (recall is List) {
      for (final it in recall) {
        if (it is String) {
          addToken(it);
        } else if (it is Map) {
          addToken((it['topic'] ?? it['tag'] ?? '').toString());
          final facets =
              (it['facets'] as List?)?.map((e) => e?.toString() ?? '').toList() ??
                  const [];
          if (facets.isNotEmpty) addToken(facets.first);
          final line = (it['line'] ?? it['hint'] ?? '').toString();
          if (line.isNotEmpty && tokens.length < 2) addToken(line);
        }
      }
    }

    if (tokens.isEmpty) return null;
    final t1 = tokens[0];
    final t2 = tokens.length >= 2 ? tokens[1] : null;

    final body =
        t2 == null ? 'Ich erinnere mich an **$t1**.' : 'Ich erinnere mich an **$t1** und **$t2**.';
    return '$body Falls das heute noch mitschwingt – magst du dort anknüpfen?';
  }

  String? _extractHopeText(gdt.ReflectionTurn t) {
    try {
      final dyn = t as dynamic;
      final d = dyn.hopeText?.toString().trim();
      if ((d ?? '').isNotEmpty) return d!;
    } catch (_) {/* ignore */}
    try {
      final dyn = t as dynamic;
      final cand = (dyn.hope ?? dyn.hope_text)?.toString().trim();
      if ((cand ?? '').isNotEmpty) return cand!;
    } catch (_) {/* ignore */}

    try {
      final seq = (t as dynamic).speechSequence as List?;
      if (seq != null) {
        for (final e in seq) {
          if (e is Map) {
            final type = (e['type'] ?? '').toString().toLowerCase().trim();
            final txt = (e['text'] ?? '').toString().trim();
            if (type == 'hope' && txt.isNotEmpty) return txt;
          } else {
            try {
              final type = (e as dynamic).type?.toString().toLowerCase().trim();
              final txt = (e as dynamic).text?.toString().trim();
              if (type == 'hope' && (txt ?? '').isNotEmpty) return txt!;
            } catch (_) {/* ignore */}
          }
        }
      }
    } catch (_) {/* ignore */}

    try {
      final a = t.analysis;
      final adyn = a as dynamic;
      final hope = adyn?.hope?.toString().trim();
      if ((hope ?? '').isNotEmpty) return hope!;
      final sum = adyn?.summary?.toString().trim();
      if ((sum ?? '').isNotEmpty && sum!.length <= 160) return sum;
    } catch (_) {/* ignore */}

    return null;
  }

  // ---------------- Facets / Topics / Actions --------------------------------

  void _updateFacetsFromTurn(gdt.ReflectionTurn t) {
    final nextFacets = <String>[];

    try {
      final a = t.analysis;
      final adyn = a as dynamic;
      final lf = (adyn?.facets as List?) ?? const <dynamic>[];
      for (final e in lf) {
        final s = (e ?? '').toString().trim();
        if (s.isNotEmpty) nextFacets.add(s);
      }
    } catch (_) {/* ignore */}

    try {
      final dyn = t as dynamic;
      final u = dyn.understanding;
      final lf = (u?.facets as List?) ?? const <dynamic>[];
      for (final e in lf) {
        final s = (e ?? '').toString().trim();
        if (s.isNotEmpty) nextFacets.add(s);
      }
    } catch (_) {/* ignore */}

    final seen = <String>{};
    final unique = <String>[];
    for (final f in nextFacets) {
      final k = f.toLowerCase();
      if (seen.add(k)) unique.add(f);
    }

    _facetQueue
      ..clear()
      ..addAll(unique);

    if (_vm?.allowClosure != true) {
      if (_activeFacet != null &&
          unique.any((e) => e.toLowerCase() == _activeFacet!.toLowerCase())) {
        // keep current
      } else {
        _activeFacet = unique.isNotEmpty ? unique.first : null;
        if (_facetQueue.isNotEmpty) {
          if (_facetQueue.first.toLowerCase() == _activeFacet!.toLowerCase()) {
            _facetQueue.removeAt(0);
          }
        }
      }
    }

    String? pin;
    try {
      final a = t.analysis;
      final adyn = a as dynamic;
      final topic = adyn?.topic?.toString().trim();
      if ((topic ?? '').isNotEmpty) pin = topic;
      final topicsDyn = (adyn?.topics as List?) ?? const <dynamic>[];
      if (pin == null && topicsDyn.isNotEmpty) {
        final s = (topicsDyn.first ?? '').toString().trim();
        if (s.isNotEmpty) pin = s;
      }
    } catch (_) {/* ignore */}

    if (pin == null) {
      try {
        final dyn = t as dynamic;
        final utopic = (dyn.understanding?.topic ?? '').toString().trim();
        if (utopic.isNotEmpty) pin = utopic;
      } catch (_) {/* ignore */}
    }

    if (pin == null && (vm?.topicChips.isNotEmpty ?? false)) {
      pin = vm!.topicChips.first;
    }

    if ((pin ?? '').trim().isNotEmpty) {
      _topicPin = pin!.trim();
    }
  }

  void _recomputeAvailableActions() {
    _availableActions.clear();

    // Kutsche 4 – Memory-Proposal zuerst signalisieren (falls vorhanden)
    if (_insightProposals.isNotEmpty) {
      final first = _insightProposals.first;
      final note = _excerpt((first['line'] ?? '').toString(), 36);
      _availableActions.add(AvailableAction(
        id: _ACT_MEMORY_PROPOSAL,
        label: 'Einsicht übernehmen',
        note: note.isEmpty ? null : '„$note”',
      ));

      _availableActions.add(const AvailableAction(
        id: _ACT_MEMORY_PROPOSAL_LATER,
        label: 'Später entscheiden',
      ));
    }

    // Nur wenn wir nicht in der Closure-Phase sind, weitere Actions anbieten
    if (_vm?.allowClosure != true) {
      if (_facetQueue.length > 1 ||
          (_facetQueue.isNotEmpty && _activeFacet != null)) {
        _availableActions.add(AvailableAction(
          id: _ACT_TOPIC_SWITCH,
          label: 'Anderes Thema',
          note: _activeFacet,
        ));
      }

      final pin = _topicPin;
      if (pin != null && pin.trim().isNotEmpty) {
        _availableActions.add(AvailableAction(
          id: _ACT_ESSENCE,
          label: 'Kernaussage dazu',
          note: pin,
        ));
        _availableActions.add(AvailableAction(
          id: _ACT_EXAMPLE,
          label: 'Beispiel dazu',
          note: pin,
        ));
      }
    }

    if (_inSkillFlow) {
      _availableActions.add(const AvailableAction(
        id: _ACT_ABORT,
        label: 'Zurück zur Reflexion',
      ));
    }

    notifyListeners();
  }

  // --------- Memory-Proposals (Kutsche 4) ------------------------------------

  void _ingestMemoryProposalsFromTurn(gdt.ReflectionTurn turn) {
    _insightProposals.clear();
    try {
      final dyn = turn as dynamic;
      final raw = dyn.memoriesToSave ?? dyn.memories_to_save;
      if (raw is List) {
        for (final it in raw) {
          if (it is Map) {
            final line = (it['line'] ?? it['hint'] ?? '').toString().trim();
            if (line.isEmpty) continue;
            _insightProposals.add(<String, dynamic>{
              'line': line,
              if (it['topic'] != null) 'topic': it['topic'],
              if (it['kind'] != null) 'kind': it['kind'],
            });
          }
        }
      }
    } catch (_) {/* ignore */}
  }

  Future<void> saveMemoryProposal() async {
    if (_insightProposals.isEmpty) return;
    final toSave = List<Map<String, dynamic>>.from(_insightProposals);
    _insightProposals.clear();
    _recomputeAvailableActions();

    try {
      final ms = MemoryService.instance as dynamic;
      await ms.saveFromWorker?.call({'memories_to_save': toSave});
    } catch (_) {/* ignore */}
  }

  void skipMemoryProposal() {
    _insightProposals.clear();
    _recomputeAvailableActions();
  }

  // --------- History + Memory bridge ----------------------------------------

  Future<void> _refreshConsentAndActive() async {
    try {
      final ms = MemoryService.instance as dynamic;
      dynamic c = ms.memoryConsent ?? ms.shareEnabled ?? ms.consent;
      dynamic a = ms.memoryActive ?? ms.isActive ?? ms.active;
      if (c is Future) c = await c;
      if (a is Future) a = await a;
      if (c is bool) _memoryConsent = c;
      if (a is bool) _memoryActive = a;
    } catch (_) {/* keep defaults */}
    _lastClientMemoryFlag = _memoryConsent && _memoryActive;
  }

  Future<_MemPrep> _prepareMemForCall({required String userText}) async {
    await _refreshConsentAndActive();
    if (!_memoryConsent || !_memoryActive) {
      _lastClientMemoryFlag = false;
      return const _MemPrep(consent: false, memories: null);
    }
    try {
      final ms = MemoryService.instance as dynamic;
      final res = await (ms.buildContextMemories?.call(
            userText: userText,
            history: _history,
          ) ??
          ms.buildContextMemories(
            userText: userText,
            history: _history,
          ));
      Map<String, dynamic>? memMap;
      if (res is Map<String, dynamic>) memMap = res;
      _lastClientMemoryFlag = true;
      return _MemPrep(consent: true, memories: memMap);
    } catch (_) {
      _lastClientMemoryFlag = true;
      return const _MemPrep(consent: true, memories: null);
    }
  }

  void _appendUserToHistory(String text) {
    final cleaned = _cap(_sanitizeInput(text), 800);
    if (cleaned.isEmpty) return;

    // History-Eintrag
    _history.add(
      gdt.HistoryTurn(
        role: 'user',
        text: cleaned,
      ),
    );
    _trimHistoryIfNeeded();

    // Fire & forget ins MemoryService loggen
    _logTurnToMemory(
      role: 'user',
      text: cleaned,
      extra: {
        'mode': 'text',
        'source': 'reflection_logic',
      },
    );
  }

  void _appendAssistantToHistory(gdt.ReflectionTurn turn) {
    // Volltext für Verlauf: Mirror + Frage + Hope + Talk-Linien
    final buffer = StringBuffer();

    final mirror = (turn.mirror ?? '').toString().trim();
    if (mirror.isNotEmpty) {
      buffer.writeln(mirror);
    }

    // Frage (primaryQuestion > question)
    String q = '';
    final pq = (turn.primaryQuestion ?? '').toString().trim();
    if (pq.isNotEmpty) {
      q = pq;
    } else {
      try {
        final dynQ = (turn as dynamic).question?.toString().trim();
        if ((dynQ ?? '').isNotEmpty) q = dynQ!;
      } catch (_) {/* ignore */}
    }
    if (q.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln(q);
    }

    // Hope-Text (falls vorhanden)
    final hope = _extractHopeText(turn);
    if (hope != null && hope.trim().isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln(hope.trim());
    }

    // Talk-Linien (max. 2)
    final talkLines = (turn.talk ?? const <String>[])
        .map((e) => (e).toString().trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();

    if (talkLines.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      for (final line in talkLines) {
        buffer.writeln(line);
      }
    }

    final fullText = _cap(buffer.toString().trim(), 800);
    if (fullText.isEmpty) return;

    // History-Eintrag
    _history.add(
      gdt.HistoryTurn(
        role: 'assistant',
        text: fullText,
      ),
    );
    _trimHistoryIfNeeded();

    // Fire & forget ins MemoryService loggen – inkl. Talk & Hope im Payload
    _logTurnToMemory(
      role: 'assistant',
      text: fullText,
      extra: {
        if (talkLines.isNotEmpty) 'talk': talkLines,
        if (hope != null && hope.trim().isNotEmpty) 'hope': hope.trim(),
        'source': 'reflection_logic',
      },
    );
  }

  void _trimHistoryIfNeeded() {
    if (_history.length <= _kMaxHistoryTurns) return;

    final int len = _history.length;
    final int rawRemove = (len * _kTrimFraction).floor();
    final int removeCount = rawRemove < _kTrimMin ? _kTrimMin : rawRemove;

    if (removeCount >= len) {
      // Sicherstellen, dass nicht alles verschwindet
      _history.removeRange(0, len - 1);
    } else {
      _history.removeRange(0, removeCount);
    }
  }

  /// Schreibt einen Turn (user/assistant) tolerant in den MemoryService.
  /// Nutzt saveUserTurn / savePandaTurn, falls vorhanden.
  void _logTurnToMemory({
    required String role,
    required String text,
    Map<String, dynamic>? extra,
  }) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    // Fire & forget, damit der UI-Thread nicht blockiert
    Future<void>(() async {
      try {
        final dyn = MemoryService.instance as dynamic;
        final payload = <String, dynamic>{
          'screen': 'reflection',
          'role': role,
          'ts': DateTime.now().toUtc().toIso8601String(),
          if (_threadId != null) 'thread_id': _threadId,
          if (_apiSession?.id != null) 'session_id': _apiSession!.id,
          if (_sessionId != null) 'local_session_id': _sessionId,
          if (extra != null) ...extra,
        };

        if (role == 'user') {
          await dyn.saveUserTurn?.call(cleaned, payload);
        } else {
          await dyn.savePandaTurn?.call(cleaned, payload);
        }
      } catch (_) {
        // bewusst still – Memory darf niemals den Flow brechen
      }
    });
  }

  Future<void> _afterTurnBookkeeping(gdt.ReflectionTurn turn, {String? lastUserText}) async {
    try {
      final ms = MemoryService.instance as dynamic;

      // 1) Roh-Worker-Daten (memories_to_save, context_memories, session …)
      //    an den MemoryService geben – best-effort, ohne den Flow zu brechen.
      try {
        final payload = Map<String, dynamic>.from(turn.toJson());
        if (turn.metaClientMemory != null) {
          payload['meta'] = {
            'flags': {'client_memory': turn.metaClientMemory}
          };
        }
        await ms.saveFromWorker?.call(payload);
      } catch (_) {
        // Fehler beim Speichern sind ok – dürfen die Reflexion nie abbrechen.
      }

      // 2) Nachgelagerte Auswertung (Timeline, Insights, Marker …)
      await ms.afterReflectionTurn?.call(
        turn,
        lastUserText: lastUserText,
      );
    } catch (_) {/* ignore */}
  }

  // --------- Misc helpers ----------------------------------------------------

  String _excerpt(String s, int maxChars) {
    final t = s.trim();
    if (t.length <= maxChars) return t;
    final cut = t.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > 12) {
      return '${cut.substring(0, lastSpace).trimRight()}…';
    }
    return '$cut…';
  }

  gdt.UserAction _toUserAction(String id, {String? note}) {
    // DTO: const UserAction({required this.type, this.actionType = ActionType.unknown, this.note});
    return gdt.UserAction(
      type: id,
      note: note,
    );
  }
}
