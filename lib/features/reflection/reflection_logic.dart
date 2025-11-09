// [PATCHED] lib/features/reflection/reflection_logic.dart (Stand: 2025-11-08)
// ZenYourself — ReflectionLogic (Controller & Handler)
// PANDA-REFLECT-12.9 → v6.8.3b (Patched 2025-11-08b)
// -----------------------------------------------------------------------------
// Änderungen ggü. deiner letzten Fassung (Build-Fix):
// • MemoryService-Aufrufe robust über `dynamic` + Fallbacks (keine Compile-Fehler
//   bei abweichenden Signaturen):
//     - saveMoodEntry(...) → versucht (ts, mental, physical) und named (when/ts).
//     - saveTimelineMarker(...) → versucht named/positional Varianten.
//     - saveInsight(...) → optional, falls vorhanden.
// • Entfernt: statischer Zugriff auf ApiService.classifyMood (fehlte).
// • Sonst unverändert: UIEvents inkl. openDualMoodPicker, After-Turn Timeline,
//   Facets/Actions, Bridge/Meta, History-Trim.
//
// Hinweis: Wenn dein reflection_screen.dart den neuen UIEvent nicht handelt,
// füge dort in der switch(e.kind) einen Case hinzu (Snippet unten).
// -----------------------------------------------------------------------------

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

  // History (read-only view for UI/diagnostics)
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

  // Memory-Proposal Buffer (sanitizte Maps mit key 'line' usw.)
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
    if (_apiSession == null) {
      await start(text, fromVoice: fromVoice, context: context);
    } else {
      await send(text, context: context);
    }
  }

  Future<void> start(String text, {bool fromVoice = false, BuildContext? context}) async {
    if (context != null) wireSessionFromContext(context);

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

      // ---- After-Turn-Hook (Timeline) – fire & forget -----------------------
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
    _emitTypingOn();
    _pendingSend?.cancel();
    _pendingSend = Timer(const Duration(milliseconds: 220), () async {
      await _sendNow(text);
    });
  }

  Future<void> _sendNow(String text) async {
    if (!_gateSendNow()) return;

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

      // ---- After-Turn-Hook (Timeline) – fire & forget -----------------------
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

      // ---- After-Turn-Hook (Timeline) – fire & forget -----------------------
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
          await ms.saveMoodEntry(when: ts, ts: ts, mental: mental.clamp(0, 4), physical: physical.clamp(0, 4));
        } catch (_) {
          // minimal: separate Setter/Save-Pfade ignorieren leise
        }
      }
    } catch (_) {/* ignore */}

    if (_apiSession == null) return;

    _emitTypingOn();
    _setLoading(true);
    try {
      final svc = GuidanceService.instance;
      gdt.ReflectionTurn turn;

      try {
        final dyn = svc as dynamic;
        turn = await (dyn.closureFull(
          session: _apiSession!,
          locale: 'de',
          tz: 'Europe/Zurich',
          meta: _buildMeta(),
        ) as Future<gdt.ReflectionTurn>).timeout(_kNetTimeout);
      } catch (_) {
        // Fallback: nextTurnFull ohne Text als "soft close"
        turn = await svc
            .nextTurnFull(
              session: _apiSession!,
              text: '',
              locale: 'de',
              tz: 'Europe/Zurich',
              history: _history,
              memories: (await _prepareMemForCall(userText: '')).memories,
              memoryConsent: _memoryConsent,
              meta: _buildMeta(),
              clientContext: {
                'mode': 'closure',
                'source': 'reflection_logic',
                if (_threadId != null) 'thread_id': _threadId,
              },
            )
            .timeout(_kNetTimeout);
      }

      _apiSession = _coerceSession(turn);
      _appendAssistantToHistory(turn);

      _vm = _buildVM(turn);
      _updateFacetsFromTurn(turn);
      _recomputeAvailableActions();

      _emitScrollToEnd(const Duration(milliseconds: 160));
    } catch (_) {/* ignore */} finally {
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
        'version': 'v6.8.3b',
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
      // Zusätzlich: „Später“ als direkte Action anbieten
      _availableActions.add(const AvailableAction(
        id: _ACT_MEMORY_PROPOSAL_LATER,
        label: 'Später',
      ));
    }

    _availableActions.add(const AvailableAction(
      id: _ACT_TOPIC_SWITCH,
      label: 'Thema wechseln',
    ));

    if (!_inSkillFlow) {
      _availableActions.add(const AvailableAction(
        id: _ACT_ESSENCE,
        label: 'Essenz',
      ));
      _availableActions.add(const AvailableAction(
        id: _ACT_EXAMPLE,
        label: 'Beispiel',
      ));
    } else {
      _availableActions.add(const AvailableAction(
        id: _ACT_ABORT,
        label: 'Abbrechen',
      ));
    }

    notifyListeners();
  }

  // ---------------- Wire helpers ---------------------------------------------

  gdt.UserAction _toUserAction(String type, {String? note}) {
    return gdt.UserAction(type: type, note: (note ?? '').trim().isEmpty ? null : note!.trim());
  }

  @override
  void dispose() {
    _debounceCancel();
    _stopTypingGuard();
    super.dispose();
  }

  // ---------------- History Buffer -------------------------------------------

  void _appendUserToHistory(String text) {
    _history.add(gdt.HistoryTurn(role: 'user', text: text));
    _trimHistoryIfNeeded();
  }

  void _appendAssistantToHistory(gdt.ReflectionTurn turn) {
    // Bevorzugt 'output_text'; fallback: Mirror + Frage
    final pieces = <String>[];
    try {
      final dyn = turn as dynamic;
      final txt = dyn.outputText?.toString().trim();
      if ((txt ?? '').isNotEmpty) {
        pieces.add(txt!);
      }
    } catch (_) {/* ignore */}
    if (pieces.isEmpty) {
      final m = (turn.mirror ?? '').trim();
      if (m.isNotEmpty) pieces.add(m);
      final pq = (turn.primaryQuestion ?? '').toString().trim();
      if (pq.isNotEmpty) {
        pieces.add(pq);
      } else {
        try {
          final q = (turn as dynamic).question?.toString().trim();
          if ((q ?? '').isNotEmpty) pieces.add(q!);
        } catch (_) {/* ignore */}
      }
    }
    final payload = pieces.join('\n').trim();
    if (payload.isNotEmpty) {
      _history.add(gdt.HistoryTurn(role: 'assistant', text: _cap(payload, 800)));
      _trimHistoryIfNeeded();
    }
  }

  void _trimHistoryIfNeeded() {
    if (_history.length <= _kMaxHistoryTurns) return;
    final toRemove = _trimCount(_history.length);
    if (toRemove <= 0) return;
    _history.removeRange(0, toRemove);
  }

  int _trimCount(int len) {
    final want = (len - _kMaxHistoryTurns);
    if (want <= 0) return 0;
    final frac = (len * _kTrimFraction).round();
    final n = (frac < _kTrimMin) ? _kTrimMin : frac;
    return n.clamp(1, want);
  }

  // ---------------- Consent/Active & Memories --------------------------------

  Future<void> _refreshConsentAndActive() async {
    // Consent (shareEnabled)
    try {
      bool v = _memoryConsent;
      final dyn = MemoryService.instance as dynamic;
      final val = dyn.shareEnabled;
      if (val is bool) v = val;
      else if (val is Future<bool>) v = await val;
      else if (val is Function) {
        final r = val();
        if (r is bool) v = r; else if (r is Future<bool>) v = await r;
      }
      _memoryConsent = v;
    } catch (_) {/* keep */}

    // Active (memoryActive / isActive / bridgeActive) — tolerant
    try {
      bool a = _memoryActive;
      final dyn = MemoryService.instance as dynamic;

      bool _coerceBool(dynamic v) {
        if (v is bool) return v;
        if (v is Future) return false; // handled below
        return v == true;
      }

      dynamic x = dyn.memoryActive;
      if (x is Future) { x = await x; }
      if (x == null) {
        x = dyn.isActive;
        if (x is Future) { x = await x; }
      }
      if (x == null) {
        x = dyn.bridgeActive;
        if (x is Future) { x = await x; }
      }
      if (x is Function) {
        final r = x();
        x = (r is Future) ? await r : r;
      }
      if (x != null) a = _coerceBool(x);

      _memoryActive = a;
    } catch (_) {/* keep */}
  }

  Future<_MemPrep> _prepareMemForCall({required String userText}) async {
    await _refreshConsentAndActive();
    final bool flag = _memoryConsent && _memoryActive;
    _lastClientMemoryFlag = flag;

    if (!flag) return const _MemPrep(null, false);

    try {
      final built = await MemoryService.instance.buildContextMemories(consent: true);
      if (built is Map<String, dynamic>) {
        return _MemPrep(built, true);
      }
    } catch (_) {/* ignore */}
    return const _MemPrep(null, true); // Consent ja, aber kein Bundle → null senden ist ok
  }

  // ========================= After-Turn Bookkeeping ===========================

  /// Speichert Timeline-Marker nach einem regulären Turn (kein Mood/Closure).
  /// - Topic: bevorzugt via HelperMappers.timelineTopic(turn, hint), sonst Fallback.
  /// - Mood: bevorzugt via ApiService.classifyMood(userText) (instanz/dyn), sonst Heuristik.
  Future<void> _afterTurnBookkeeping(gdt.ReflectionTurn turn, {String? lastUserText}) async {
    try {
      // 1) Guard – NICHT doppeln während aktiver Mood-/Closure-Phase
      final flow = turn.flow;
      final bool isMoodPhase = (flow?.moodPrompt ?? false) == true;
      final bool isClosurePhase = (flow?.recommendEnd ?? false) == true;
      if (isMoodPhase || isClosurePhase) return;

      // 2) Topic ermitteln (Helper-Mappers bevorzugt)
      String topic = '';
      try {
        topic = (hm.HelperMappers.timelineTopic(turn, hint: _topicPin) ?? '').trim();
      } catch (_) {/* ignore */}
      if (topic.isEmpty) {
        final String? rawTopic =
            _extractTopicFromTags(turn) ??
            _extractTopicFromAnalysis(turn) ??
            (_topicPin?.trim().isNotEmpty == true ? _topicPin!.trim() : null);
        topic = _normalizeTopic(rawTopic ?? '');
      }
      if (topic.isEmpty) return; // Ohne Topic kein Marker

      // 3) Mood bestimmen (0–4)
      int mood = 2; // neutral
      final src = (lastUserText ?? '').trim();
      if (src.isNotEmpty) {
        final viaApi = await _classifyMoodViaApi(src);
        mood = (viaApi ?? _classifyMoodHeuristic(src)).clamp(0, 4);
      }

      // 4) Persistieren (robust, Fehler schlucken)
      try {
        final ms = (MemoryService.instance as dynamic);
        final now = DateTime.now();
        try {
          // named-Variante
          await ms.saveTimelineMarker(ts: now, topic: topic, mood: mood);
        } catch (_) {
          try {
            // alternative Namen
            await ms.saveTimelineMarker(when: now, topic: topic, mood: mood);
          } catch (_) {
            try {
              // positional Fallback
              await ms.saveTimelineMarker(now, topic, mood);
            } catch (_) {/* ignore */}
          }
        }
      } catch (_) {/* ignore */}
    } catch (_) {/* never throw */}
  }

  String? _extractTopicFromTags(gdt.ReflectionTurn t) {
    try {
      final dyn = t as dynamic;
      final tags = dyn.tags;
      if (tags is List) {
        for (final raw in tags) {
          final s = raw?.toString() ?? '';
          final m = RegExp(r'^\s*topic\s*:\s*(.+)\s*$', caseSensitive: false).firstMatch(s);
          if (m != null) {
            final val = m.group(1)?.trim();
            if ((val ?? '').isNotEmpty) return val;
          }
        }
      } else if (tags is Map) {
        final v = tags['topic']?.toString().trim();
        if ((v ?? '').isNotEmpty) return v;
      }
    } catch (_) {/* ignore */}
    return null;
  }

  String? _extractTopicFromAnalysis(gdt.ReflectionTurn t) {
    try {
      final a = t.analysis;
      final adyn = a as dynamic;
      final topic = adyn?.topic?.toString().trim();
      if ((topic ?? '').isNotEmpty) return topic;
      final topics = (adyn?.topics as List?) ?? const <dynamic>[];
      if (topics.isNotEmpty) {
        final s = (topics.first ?? '').toString().trim();
        if (s.isNotEmpty) return s;
      }
    } catch (_) {/* ignore */}
    try {
      final dyn = t as dynamic;
      final utopic = dyn.understanding?.topic?.toString().trim();
      if ((utopic ?? '').isNotEmpty) return utopic;
    } catch (_) {/* ignore */}
    return null;
  }

  Future<int?> _classifyMoodViaApi(String text) async {
    try {
      // bevorzugt: ApiService.instance.classifyMood(text) — dyn tolerant
      final dyn = api.ApiService.instance as dynamic;
      final res = await dyn.classifyMood?.call(text);
      if (res is int) return res.clamp(0, 4);
      if (res is Map && res['mood'] is int) return (res['mood'] as int).clamp(0, 4);
    } catch (_) {/* ignore */}
    return null;
  }

  int _classifyMoodHeuristic(String text) {
    final t = text.toLowerCase();

    final neg4 = ['verzweifelt', 'panik', 'hoffnungslos', 'suizid', 'suizidal', 'katastrophe'];
    final neg3 = ['sehr schlecht', 'schlimm', 'ängstlich', 'angst', 'heftig', 'weh', 'traurig', 'depressiv'];
    final neg2 = ['nicht gut', 'müde', 'erschöpft', 'überfordert', 'gestresst', 'stress', 'nervös', 'unsicher'];
    final pos4 = ['großartig', 'fantastisch', 'super', 'wunderbar', 'glücklich', 'sehr gut'];
    final pos3 = ['gut', 'besser', 'ruhig', 'entspannt', 'zufrieden', 'okay', 'ok', 'geht'];

    bool any(List<String> xs) => xs.any((w) => t.contains(w));

    if (any(neg4)) return 0;
    if (any(neg3)) return 1;
    if (any(neg2)) return 1;
    if (any(pos4)) return 4;
    if (any(pos3)) return 3;

    // einfache Emoji-/Smiley-Heuristik
    final hasSad = RegExp(r'(:\(|😞|😢|😭|💔)').hasMatch(text);
    final hasHappy = RegExp(r'(:\)|😊|🙂|😁|🥰|💚|💖)').hasMatch(text);
    if (hasSad && !hasHappy) return 1;
    if (hasHappy && !hasSad) return 3;

    return 2; // neutral
  }

  // ========================= Kutsche 4: Memory-Proposal =======================

  void _ingestMemoryProposalsFromTurn(gdt.ReflectionTurn t) {
    final proposals = <Map<String, dynamic>>[];

    try {
      final dyn = t as dynamic;
      final arr = dyn.memoriesToSave ?? dyn.memories_to_save;
      if (arr is List) {
        for (final it in arr) {
          if (it is Map) {
            final m = Map<String, dynamic>.from(it);
            final s = _sanitizeInsightProposal(m);
            if ((s['line'] ?? '').toString().trim().isNotEmpty) proposals.add(s);
          } else if (it is String) {
            final s = _sanitizeInsightProposal({'line': it});
            if ((s['line'] ?? '').toString().trim().isNotEmpty) proposals.add(s);
          }
        }
      }
    } catch (_) {/* ignore */}

    _insightProposals
      ..clear()
      ..addAll(proposals);

    _recomputeAvailableActions();
  }

  Map<String, dynamic> _sanitizeInsightProposal(Map<String, dynamic> inMap) {
    final m = Map<String, dynamic>.from(inMap);
    String line = ((m['line'] ?? m['value'] ?? '')).toString().trim();
    if (line.length > 240) line = line.substring(0, 240);
    m['line'] = line;

    String _clip(String? s, int n) {
      final x = (s ?? '').trim();
      return (x.length <= n) ? x : x.substring(0, n);
    }

    if (m.containsKey('topic')) m['topic'] = _clip(m['topic']?.toString(), 64);
    if (m.containsKey('activeFacet')) m['activeFacet'] = _clip(m['activeFacet']?.toString(), 64);
    if (m.containsKey('active_facet')) {
      m['activeFacet'] = _clip(m['active_facet']?.toString(), 64); m.remove('active_facet');
    }
    if (m.containsKey('topicPin')) m['topicPin'] = _clip(m['topicPin']?.toString(), 64);
    if (m.containsKey('topic_pin')) {
      m['topicPin'] = _clip(m['topic_pin']?.toString(), 64); m.remove('topic_pin');
    }

    final sc = m['score'];
    if (sc is num) {
      double s = sc.toDouble();
      if (!s.isNaN) {
        if (s < 0) s = 0; if (s > 1) s = 1;
        m['score'] = double.parse(s.toStringAsFixed(3));
      } else {
        m.remove('score');
      }
    } else if (sc != null) {
      m.remove('score');
    }

    // tags: max 5 strings, je ≤32
    final tags = <String>[];
    final rawTags = m['tags'];
    if (rawTags is List) {
      for (final it in rawTags) {
        final s = (it?.toString() ?? '').trim();
        if (s.isEmpty) continue;
        final clip = (s.length <= 32) ? s : s.substring(0, 32);
        if (!tags.contains(clip)) tags.add(clip);
        if (tags.length >= 5) break;
      }
    } else if (rawTags is String) {
      final s = rawTags.trim();
      if (s.isNotEmpty) tags.add(s.length <= 32 ? s : s.substring(0, 32));
    }
    if (tags.isNotEmpty) m['tags'] = tags; else m.remove('tags');

    return m;
  }

  String _excerpt(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1).trimRight()}…';
  }

  /// Public-API für die View: „Speichern“ gedrückt.
  Future<void> saveMemoryProposal({int index = 0}) async {
    if (_insightProposals.isEmpty) return;
    final i = index.clamp(0, _insightProposals.length - 1);
    final m = _insightProposals[i];

    try {
      final ms = (MemoryService.instance as dynamic);
      await ms.saveInsight?.call(
        line: (m['line'] ?? '').toString().trim(),
        score: (m['score'] is num) ? (m['score'] as num).toDouble() : null,
        topic: (m['topic'] ?? '').toString().trim().isEmpty ? null : m['topic'].toString().trim(),
        activeFacet: (m['activeFacet'] ?? '').toString().trim().isEmpty ? null : m['activeFacet'].toString().trim(),
        topicPin: (m['topicPin'] ?? '').toString().trim().isEmpty ? null : m['topicPin'].toString().trim(),
        tags: (m['tags'] is List) ? List<String>.from((m['tags'] as List).map((e) => e.toString())) : null,
        canon: (m['canon'] ?? '').toString().trim().isEmpty ? null : m['canon'].toString().trim(),
      );
    } catch (_) {/* ignore */}

    // optional: kleines Ack-Event ins Memory loggen
    try {
      final dyn = MemoryService.instance as dynamic;
      await dyn.saveAck?.call({
        'kind': 'insight_saved',
        'line': (m['line'] ?? '').toString().trim(),
        'ts': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {/* ignore */}

    _insightProposals.clear();
    _recomputeAvailableActions();

    // Kurzer, warmer Acknowledge-Ton in der UI; keine Frage, kein Worker-Call
    if (_vm != null) {
      _vm = _vm!.copyWith(helperSuggestion: 'Gespeichert – ich halte diese kleine Einsicht für dich fest.');
      notifyListeners();
      _emitScrollToEnd(const Duration(milliseconds: 120));
    }
  }

  /// Public-API für die View: „Später“ gedrückt.
  void skipMemoryProposal() {
    if (_insightProposals.isEmpty) return;
    _insightProposals.clear();
    _recomputeAvailableActions();

    // Sanftes, kurzes Ack – ohne Folgefrage/Turn
    if (_vm != null) {
      _vm = _vm!.copyWith(helperSuggestion: 'Alles klar – wir können das später jederzeit aufnehmen.');
      notifyListeners();
      _emitScrollToEnd(const Duration(milliseconds: 120));
    }
  }

  // ---------------- Topic-Normalisierung (Fallback für Kutsche 3) ------------

  /// Normalisiert Topics auf ≤3 Worte, Kleinbuchstaben, Trim; entfernt Punkte/Ellipsen.
  String _normalizeTopic(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    t = t.replaceAll(RegExp(r'[.。…]+$'), '').trim();
    // Zerlegen und auf 3 Tokens begrenzen
    final parts = t.split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
    final keep = parts.take(3).map((e) => e.toLowerCase()).toList();
    return keep.join(' ').trim();
  }
}

class _MemPrep {
  final Map<String, dynamic>? memories;
  final bool consent;
  const _MemPrep(this.memories, this.consent);
}
