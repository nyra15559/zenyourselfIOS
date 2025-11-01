// [BASELINE] lib/features/reflection/reflection_logic.dart (Stand: 31.10.)
// ZenYourself — ReflectionLogic (Controller & Handler)
// PANDA-REFLECT-12.7 → v6.6.3 (Facet-State + Voice-Router + Recovery + Typing Guard + Intro Guards)
// -----------------------------------------------------------------------------
// Merge-Signal / Handshake:
// • Bei jedem Call wird `meta.flags.client_memory:true` übergeben.
// • Bridge (Recall) wird als `meta.memory.bridge` mitgegeben.
// • Memories/Consent werden 1:1 als context.memories + memory_consent (Guidance/API).
// -----------------------------------------------------------------------------
// Aufgaben (FilePlan 6.2.x + v6.3 + v6.6):
// • Controller-Klasse (kein UI; ChangeNotifier)
// • Start/Senden-Flow (Full-Endpunkte; Memories/Consent durchreichen)
// • Action-Flow (Rate-Limit 1×/Session; Fallback tolerant)
// • Hybrid-Note (typed + transcript, defensiv, gekappt)
// • Debounce/Rate-Limit (min Gap zwischen Sends; sanft, ohne Exceptions)
// • VM-Bau: answer_helpers-only, mind. 2 Chips, Talk≤2, Risk/Flow-Flags, Hope
// • NEU: Facet-Router & SkillFlow (Essenz/Beispiel) vs. Standard
// • NEU: Voice-Trigger → identische Aktionen wie Buttons (availableActions)
// • NEU: Edgecases (Themenwechsel während aktiver Facet, Abbruch, Closure-Recovery)
// -----------------------------------------------------------------------------
// Leitlinien:
// • Keine UI-Logik; reine Orchestrierung + State. View rendert nur 'vm'.
// • Niemals Exceptions nach außen werfen (defensiv, timeouts).
// • Analyzer-clean; keine Abhängigkeit von Screen/Widgets.
// -----------------------------------------------------------------------------
// Resume-Marker: P0-S1.1-DONE  (Leer-nach-Senden Fix: Local Echo + Typing + Scroll)
// Resume-Marker: P0-S2.1-DONE  ("Panda tippt …" bei jedem Turn: setTyping(true) beim Senden, false bei Antwort/Timeout)
// Resume-Marker: P0-S3.2-DONE  (Intro-Guards: hasSeenIntroThisSession + roundCount → keine Doppel-Intro)

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import '../../services/guidance/dtos.dart'
    show ReflectionTurn, ReflectionSession, UserAction;
import '../../services/guidance_service.dart';
import '../../core/memory/memory_service.dart';

const Duration _kNetTimeout = Duration(seconds: 18);
const Duration _kTypingGuard = Duration(seconds: 12); // Fallback, falls etwas hängen bleibt

// --------------------------- UI Events (für View) -----------------------------
enum UIEventKind { appendUser, insertTypingPlaceholder, removeTypingPlaceholder, scrollToEnd }

class UIEvent {
  final UIEventKind kind;
  final String? text;
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
}

// --------------------------- Actions (public model) --------------------------

class AvailableAction {
  final String id;     // 'topic_switch', 'essence', 'example', 'abort'
  final String label;  // UI-Text
  final String? note;  // Zusatzinfo (z. B. Ziel-Facet)
  const AvailableAction({required this.id, required this.label, this.note});

  AvailableAction copyWith({String? label, String? note}) =>
      AvailableAction(id: id, label: label ?? this.label, note: note ?? this.note);
}

// --------------------------- Controller --------------------------------------

class ReflectionController extends ChangeNotifier {
  ReflectionController({
    Duration sendMinGap = const Duration(milliseconds: 420),
  }) : _sendMinGap = sendMinGap {
    // Consent best-effort asynchron initialisieren (Property ODER Methode unterstützt)
    Future.microtask(() async {
      try { await MemoryService.instance.warmup(); } catch (_) {}
      try {
        bool v = false;
        // ignore: avoid_dynamic_calls
        final dyn = MemoryService.instance as dynamic;
        final val = dyn.shareEnabled;
        if (val is bool) {
          v = val;
        } else if (val is Future<bool>) {
          v = await val;
        } else if (val is Function) {
          final res = val();
          if (res is bool) v = res; else if (res is Future<bool>) v = await res;
        }
        _memoryConsent = v;
        notifyListeners();
      } catch (_) {/* keep default=false */}
    });
  }

  // ---------------- Public (readonly) state ----------------------------------

  bool get loading => _loading;
  ReflectionVM? get vm => _vm;
  ReflectionSession? get session => _session;
  String? get bridgeText => _bridgeText;
  dynamic get memories => _memories;
  bool get memoryConsent => _memoryConsent;

  bool get hasSeenIntroThisSession => _hasSeenIntroThisSession;
  int get roundCount => (_session?.turnIndex ?? 0);
  bool get canShowIntro => !_hasSeenIntroThisSession && roundCount == 0 && _vm == null;

  UnmodifiableListView<String> get facetQueue => UnmodifiableListView(_facetQueue);
  String? get activeFacet => _activeFacet;
  String? get topicPin => _topicPin;
  UnmodifiableListView<AvailableAction> get availableActions => UnmodifiableListView(_availableActions);
  bool get inSkillFlow => _inSkillFlow;

  // ---------------- UI Event Sink (optional) ----------------------------------

  void attachUiEventSink(void Function(UIEvent e) sink) => _uiEventSink = sink;
  void detachUiEventSink() => _uiEventSink = null;

  // ---------------- Private state --------------------------------------------

  final Duration _sendMinGap;

  bool _loading = false;
  ReflectionSession? _session;
  ReflectionVM? _vm;
  String? _bridgeText;

  DateTime? _lastSendAt;
  Timer? _pendingSend;
  bool _actionUsedInThisSession = false;

  dynamic _memories;
  bool _memoryConsent = false;

  bool _hasSeenIntroThisSession = false;

  final List<String> _facetQueue = <String>[];
  String? _activeFacet;
  String? _topicPin;
  final List<AvailableAction> _availableActions = <AvailableAction>[];
  bool _inSkillFlow = false;

  bool _typingActive = false;
  Timer? _typingGuardTimer;

  void Function(UIEvent e)? _uiEventSink;

  // ---------------- Init / Bridge --------------------------------------------

  Future<void> prefetchBridge() async {
    try {
      final recall = await MemoryService.instance.recall(limit: 6);
      try {
        // ignore: avoid_dynamic_calls
        final dyn = MemoryService.instance as dynamic;
        final se = dyn.shareEnabled;
        if (se is bool) _memoryConsent = se;
        else if (se is Future<bool>) _memoryConsent = await se;
        else if (se is Function) {
          final res = se();
          if (res is bool) _memoryConsent = res;
          else if (res is Future<bool>) _memoryConsent = await res;
        }
      } catch (_) {}
      _bridgeText = _composeBridgeText(recall);
      notifyListeners();
    } catch (_) {/* never throw */}
  }

  void setMemoryConsent(bool consent) {
    _memoryConsent = consent;
  }

  void setMemories(dynamic memories) {
    _memories = memories;
  }

  void markIntroSeen() {
    _hasSeenIntroThisSession = true;
  }

  void reset() {
    _debounceCancel();
    _stopTypingGuard();
    _emitTypingOff();
    _loading = false;
    _session = null;
    _vm = null;
    _bridgeText = null;
    _actionUsedInThisSession = false;

    _facetQueue.clear();
    _activeFacet = null;
    _topicPin = null;
    _availableActions.clear();
    _inSkillFlow = false;

    _hasSeenIntroThisSession = false;

    notifyListeners();
  }

  // ---------------- Sending ---------------------------------------------------

  Future<void> start(String text, {bool fromVoice = false}) async {
    _debounceCancel();
    if (!_gateSendNow()) return;
    text = _sanitizeInput(text);
    if (text.isEmpty) return;

    _localEchoBeforeCall(text);
    _hasSeenIntroThisSession = true;

    _setLoading(true);
    try {
      final turn = await GuidanceService.instance
          .reflectFull(
            text: text,
            locale: 'de',
            tz: 'Europe/Zurich',
            memories: _memories,
            memoryConsent: _memoryConsent,
            meta: _buildMeta(mode: fromVoice ? 'voice' : 'text'),
            clientContext: {
              'mode': fromVoice ? 'voice' : 'text',
              'source': 'reflection_screen',
            },
          )
          .timeout(_kNetTimeout);

      _session = _coerceSession(turn);
      _vm = _buildVM(turn);
      _actionUsedInThisSession = false;
      _updateFacetsFromTurn(turn);
      _recomputeAvailableActions();
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
      _recomputeAvailableActions();
    } finally {
      _emitTypingOff();
      _setLoading(false);
    }
  }

  Future<void> send(String text) async {
    _emitTypingOn();
    _pendingSend?.cancel();
    _pendingSend = Timer(const Duration(milliseconds: 220), () async {
      await _sendNow(text);
    });
  }

  Future<void> _sendNow(String text) async {
    if (!_gateSendNow()) return;
    text = _sanitizeInput(text);
    if (text.isEmpty && _session == null) return;

    _setLoading(true);
    try {
      if (_session == null) {
        await start(text);
        return;
      }

      _localEchoBeforeCall(text);

      final turn = await GuidanceService.instance
          .nextTurnFull(
            session: _session!,
            text: text,
            locale: 'de',
            tz: 'Europe/Zurich',
            memories: _memories,
            memoryConsent: _memoryConsent,
            meta: _buildMeta(mode: 'text'),
            clientContext: const {'mode': 'text', 'source': 'reflection_screen'},
          )
          .timeout(_kNetTimeout);

      _session = _coerceSession(turn);
      _vm = _buildVM(turn);
      _inSkillFlow = false;
      _updateFacetsFromTurn(turn);
      _recomputeAvailableActions();
    } catch (_) {/* ignore, keep old vm */} finally {
      _emitTypingOff();
      _setLoading(false);
    }
  }

  // ---------------- Actions ---------------------------------------------------

  Future<void> handleAction(UserAction action) async {
    if (_session == null) return;
    if (_actionUsedInThisSession) return;
    if (!_gateSendNow()) return;

    _emitTypingOn();

    _setLoading(true);
    try {
      final svc = GuidanceService.instance;
      ReflectionTurn turn;

      try {
        // ignore: avoid_dynamic_calls
        final dyn = svc as dynamic;
        // ignore: avoid_dynamic_calls
        final Future<ReflectionTurn>? fut = dyn.nextTurnAction?.call(
          session: _session!,
          action: action,
          locale: 'de',
          tz: 'Europe/Zurich',
          meta: _buildMeta(mode: 'action'),
        );
        if (fut != null) {
          turn = await fut.timeout(_kNetTimeout);
        } else {
          turn = await svc
              .nextTurnFull(
                session: _session!,
                text: '',
                locale: 'de',
                tz: 'Europe/Zurich',
                memories: _memories,
                memoryConsent: _memoryConsent,
                meta: _buildMeta(mode: 'action-fallback'),
                clientContext: const {
                  'mode': 'text',
                  'source': 'reflection_screen'
                },
              )
              .timeout(_kNetTimeout);
        }
      } catch (_) {
        turn = await svc
            .nextTurnFull(
              session: _session!,
              text: '',
              locale: 'de',
              tz: 'Europe/Zurich',
              memories: _memories,
              memoryConsent: _memoryConsent,
              meta: _buildMeta(mode: 'action-fallback'),
              clientContext: const {'mode': 'text', 'source': 'reflection_screen'},
            )
            .timeout(_kNetTimeout);
      }

      _session = _coerceSession(turn);
      _vm = _buildVM(turn);
      _actionUsedInThisSession = true;

      _updateFacetsFromTurn(turn);
      _recomputeAvailableActions();
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

  Future<void> runAction(String id, {String? note}) async {
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

  ReflectionVM _buildVM(ReflectionTurn t) {
    final mirror = _cap((t.mirror ?? '').trim(), 640);
    final q = ((t.primaryQuestion ?? '') as String).trim().isNotEmpty
        ? (t.primaryQuestion ?? '').trim()
        : (t.question ?? '').trim();

    final talk = (t.talk ?? const <String>[])
        .map((e) => (e ?? '').trim())
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

    final String rf = (t.riskFlag ?? '').toLowerCase().trim();
    final bool risk = (rf == 'crisis' || rf == 'support') ||
        // ignore: avoid_dynamic_calls
        ((t as dynamic).risk == true);

    final allowClosure =
        (t.flow?.recommendEnd == true) || (t.flow?.moodPrompt == true);
    final moodPrompt = (t.flow?.moodPrompt == true);

    final hopeText = _extractHopeText(t);

    final topicChips = <String>{
      ...((t.topicSuggestions ?? const <String>[])
          .map((s) => (s ?? '').toString().trim())
          .where((s) => s.isNotEmpty)),
      ...(((t.analysis?.topicSuggestions) ?? const <String>[])
          .map((s) => (s ?? '').toString().trim())
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

  ReflectionSession _coerceSession(ReflectionTurn t) => t.session;

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
    s = s.replaceAll(RegExp(r'[?？]+$'), '');
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

  Map<String, dynamic> _buildMeta({String? mode}) {
    final bool reopen = (_vm?.allowClosure == true);

    return {
      'ui': {
        'controller': 'reflection_logic',
        'version': 'v6.6.3',
      },
      'memory': {
        'bridge': _bridgeText,
      },
      'flags': {
        'client_memory': true, // *** Merge-Signal / Handshake ***
        'reopen': reopen,      // *** Closure-Recovery ***
      },
      'intro': {
        'has_seen_intro_this_session': _hasSeenIntroThisSession,
        'round_count': roundCount,
      },
      'client': {
        'source': 'reflection_logic',
        if (mode != null) 'mode': mode,
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

  String? _extractHopeText(ReflectionTurn t) {
    try {
      final d = (t.hopeText ?? '').trim();
      if (d.isNotEmpty) return d;
    } catch (_) {/* ignore */}
    try {
      // ignore: avoid_dynamic_calls
      final dyn = t as dynamic;
      // ignore: avoid_dynamic_calls
      final cand = (dyn.hope ?? dyn.hope_text)?.toString().trim();
      if ((cand ?? '').isNotEmpty) return cand;
    } catch (_) {/* ignore */}

    try {
      // ignore: avoid_dynamic_calls
      final seq = (t as dynamic).speechSequence as List?;
      if (seq != null) {
        for (final e in seq) {
          if (e is Map) {
            final type = (e['type'] ?? '').toString().toLowerCase().trim();
            final txt = (e['text'] ?? '').toString().trim();
            if (type == 'hope' && txt.isNotEmpty) return txt;
          } else {
            try {
              // ignore: avoid_dynamic_calls
              final type = (e as dynamic).type?.toString().toLowerCase().trim();
              // ignore: avoid_dynamic_calls
              final txt = (e as dynamic).text?.toString().trim();
              if (type == 'hope' && (txt ?? '').isNotEmpty) return txt;
            } catch (_) {/* ignore */}
          }
        }
      }
    } catch (_) {/* ignore */}

    try {
      final a = t.analysis;
      // ignore: avoid_dynamic_calls
      final hope = (a?.hope ?? '').toString().trim();
      if (hope.isNotEmpty) return hope;
      final sum = (a?.summary ?? '').toString().trim();
      if (sum.isNotEmpty && sum.length <= 160) return sum;
    } catch (_) {/* ignore */}

    return null;
  }

  // ---------------- Facets / Topics / Actions --------------------------------

  void _updateFacetsFromTurn(ReflectionTurn t) {
    final nextFacets = <String>[];

    try {
      final a = t.analysis;
      final lf = (a?.facets ?? const <String>[]) as List?;
      if (lf != null) {
        for (final e in lf) {
          final s = (e ?? '').toString().trim();
          if (s.isNotEmpty) nextFacets.add(s);
        }
      }
    } catch (_) {/* ignore */}

    try {
      // ignore: avoid_dynamic_calls
      final dyn = t as dynamic;
      // ignore: avoid_dynamic_calls
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
        if (_activeFacet != null && _facetQueue.isNotEmpty) {
          if (_facetQueue.isNotEmpty &&
              _facetQueue.first.toLowerCase() == _activeFacet!.toLowerCase()) {
            _facetQueue.removeAt(0);
          }
        }
      }
    }

    String? pin;
    try {
      final a = t.analysis;
      final topic = (a?.topic ?? '').toString().trim();
      if (topic.isNotEmpty) pin = topic;
      if (pin == null && (a?.topics is List) && (a!.topics!.isNotEmpty)) {
        final s = (a.topics!.first ?? '').toString().trim();
        if (s.isNotEmpty) pin = s;
      }
    } catch (_) {/* ignore */}

    if (pin == null) {
      try {
        // ignore: avoid_dynamic_calls
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

  UserAction _toUserAction(String type, {String? note}) {
    return UserAction(type: type, note: (note ?? '').trim().isEmpty ? null : note!.trim());
  }

  @override
  void dispose() {
    _debounceCancel();
    _stopTypingGuard();
    super.dispose();
  }
}
