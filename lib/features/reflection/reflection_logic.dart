// [BASELINE] lib/features/reflection/reflection_logic.dart
// ZenYourself — ReflectionLogic (Controller & Handler)
// v12.1.3-baseline · 2025-10-29 · Europe/Zurich
// -----------------------------------------------------------------------------
// Aufgaben (FilePlan 6.2.x + v6.3):
// • Controller-Klasse (kein UI; ChangeNotifier)
// • Start/Senden-Flow (Full-Endpunkte; Memories/Consent durchreichen)
// • Action-Flow (Rate-Limit 1×/Session; Fallback tolerant)
// • Hybrid-Note (typed + transcript, defensiv, gekappt)
// • Debounce/Rate-Limit (min Gap zwischen Sends; sanft, ohne Exceptions)
// • VM-Bau: answer_helpers-only, mind. 2 Chips, Talk≤2, Risk/Flow-Flags
// -----------------------------------------------------------------------------
// Leitlinien:
// • Keine UI-Logik; reine Orchestrierung + State. View rendert nur 'vm'.
// • Niemals Exceptions nach außen werfen (defensiv, timeouts).
// • Analyzer-clean; keine Abhängigkeit von Screen/Widgets.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../services/guidance/dtos.dart'
    show ReflectionTurn, ReflectionSession, UserAction;
import '../../services/guidance_service.dart';
import '../../core/memory/memory_service.dart';

const Duration _kNetTimeout = Duration(seconds: 18);

/// Öffentliche, render-fertige Sicht auf den aktuellen Turn.
/// (Die View greift *nur* auf diese Felder zu – keine DTO-Abhängigkeit nötig.)
class ReflectionVM {
  final String mirror;               // Empathische Spiegelung (gekürzt)
  final String question;             // Leitfrage (mit Fragezeichen)
  final List<String> answerChips;    // max 3, min 2 (sanft ergänzt)
  final List<String> talkLines;      // kleine Talk-Zeilen (≤2)
  final String? helperSuggestion;    // 0–1 Satz unter der Frage
  final bool risk;                   // true ⇒ CH-Risk-Actions einblenden
  final bool allowClosure;           // Worker signalisiert Abschluss/Mood
  final bool moodPrompt;             // Mood explizit fragen
  final String? hopeText;            // kurzer, hoffnungsvoller Slot (optional)
  final List<String> topicChips;     // Themen/Redirect-Ideen (optional)

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

/// Controller & Orchestrator (kein UI).
/// Verantwortlich für: Start/Weiter-Flow, Action-Flow, Debounce/Rate-Limit.
class ReflectionController extends ChangeNotifier {
  ReflectionController({
    Duration sendMinGap = const Duration(milliseconds: 420),
  }) : _sendMinGap = sendMinGap;

  // ---------------- Public (readonly) state ----------------------------------

  bool get loading => _loading;
  ReflectionVM? get vm => _vm;
  ReflectionSession? get session => _session;
  String? get bridgeText => _bridgeText; // für Bridge-Bubble (optional)

  /// Optional: vom UI gesetzte Memories (werden an Full-Endpunkte durchgereicht).
  dynamic get memories => _memories;

  /// Optional: Einwilligung, Memories an den Worker zu senden (Default: false).
  bool get memoryConsent => _memoryConsent;

  // ---------------- Private state --------------------------------------------

  final Duration _sendMinGap;

  bool _loading = false;
  ReflectionSession? _session;
  ReflectionVM? _vm;
  String? _bridgeText;

  // Debounce/Rate-Limit
  DateTime? _lastSendAt;
  Timer? _pendingSend;
  bool _actionUsedInThisSession = false;

  // v6.3.0: optionale Memory-Weitergabe
  dynamic _memories;
  bool _memoryConsent = false;

  // ---------------- Init / Bridge --------------------------------------------

  /// Optional vorab: Bridge-Recall laden (best effort, UI bleibt frei).
  Future<void> prefetchBridge() async {
    try {
      final recall = await MemoryService.instance.recall(limit: 6);
      _bridgeText = _composeBridgeText(recall);
      notifyListeners();
    } catch (_) {/* never throw */}
  }

  /// Setzt die Einwilligung zur Memory-Weitergabe (persistiert NICHT).
  void setMemoryConsent(bool consent) {
    _memoryConsent = consent;
    // kein notify nötig; wirkt bei nächstem Send
  }

  /// Übergibt (oder löscht via `null`) optionale Memories für den nächsten Turn/Start.
  void setMemories(dynamic memories) {
    _memories = memories;
  }

  // ---------------- Sending ---------------------------------------------------

  /// Startet *neue* Session mit [text].
  /// [fromVoice] setzt clientContext.mode: 'voice'|'text'.
  Future<void> start(String text, {bool fromVoice = false}) async {
    _debounceCancel(); // sauberer Neustart
    if (!_gateSendNow()) return; // min-gap
    text = _sanitizeInput(text);
    if (text.isEmpty) return;

    _setLoading(true);
    try {
      final turn = await GuidanceService.instance
          .startSessionFull(
            text: text,
            locale: 'de',
            tz: 'Europe/Zurich',
            memories: _memories,
            memoryConsent: _memoryConsent,
            clientContext: {
              'mode': fromVoice ? 'voice' : 'text',
              'source': 'reflection_screen',
            },
          )
          .timeout(_kNetTimeout);

      _session = _coerceSession(turn);
      _vm = _buildVM(turn);
      _actionUsedInThisSession = false; // neue Session ⇒ Action-Rate-Limit reset
    } catch (_) {
      // sanfter Fallback-VM
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
    } finally {
      _setLoading(false);
    }
  }

  /// Setzt Session fort mit [text]. Falls keine Session existiert → start().
  Future<void> send(String text) async {
    // Debounce: sammelt schnelle Mehrfach-Events ein und sendet *einmal*.
    _pendingSend?.cancel();
    _pendingSend = Timer(const Duration(milliseconds: 220), () async {
      await _sendNow(text);
    });
  }

  Future<void> _sendNow(String text) async {
    if (!_gateSendNow()) return; // min-gap
    text = _sanitizeInput(text);
    if (text.isEmpty && _session == null) return;

    _setLoading(true);
    try {
      if (_session == null) {
        await start(text);
        return;
      }

      final turn = await GuidanceService.instance
          .nextTurnFull(
            session: _session!,
            text: text,
            locale: 'de',
            tz: 'Europe/Zurich',
            memories: _memories,               // v6.3.0: optional aktualisierte Memories
            memoryConsent: _memoryConsent,     // v6.3.0: Consent mitgeben (tolerant)
            clientContext: const {'mode': 'text', 'source': 'reflection_screen'},
          )
          .timeout(_kNetTimeout);

      _session = _coerceSession(turn);
      _vm = _buildVM(turn);
    } catch (_) {/* ignore, keep old vm */}
    finally {
      _setLoading(false);
    }
  }

  // ---------------- Actions ---------------------------------------------------

  /// Führt eine User-Action aus (z. B. "journal_link", "story_link", "save"...).
  /// Rate-Limit: max 1 Action pro Session (laut Plan).
  Future<void> handleAction(UserAction action) async {
    if (_session == null) return;
    if (_actionUsedInThisSession) return; // Rate-Limit (1×/Session)

    // Debounce: verhindere Double-Taps.
    if (!_gateSendNow()) return;

    _setLoading(true);
    try {
      final svc = GuidanceService.instance;

      // Tolerant: Falls GuidanceService bereits eine Action-Methode hat, nutze sie.
      // Sonst fallback auf normalen nextTurnFull (Server darf Action aus "messages" / context lesen).
      ReflectionTurn turn;
      try {
        // ignore: avoid_dynamic_calls
        final dyn = svc as dynamic;
        final Future<ReflectionTurn>? fut = dyn.nextTurnAction?.call(
          session: _session!,
          action: action,
          locale: 'de',
          tz: 'Europe/Zurich',
        );
        if (fut != null) {
          turn = await fut.timeout(_kNetTimeout);
        } else {
          // Fallback: minimaler "Action-Stich" via nextTurnFull ohne Text.
          turn = await svc
              .nextTurnFull(
                session: _session!,
                text: '',
                locale: 'de',
                tz: 'Europe/Zurich',
                memories: _memories,
                memoryConsent: _memoryConsent,
                clientContext: const {'mode': 'text', 'source': 'reflection_screen'},
              )
              .timeout(_kNetTimeout);
        }
      } catch (_) {
        // Fallback: minimaler "Action-Stich" via nextTurnFull ohne Text.
        turn = await svc
            .nextTurnFull(
              session: _session!,
              text: '',
              locale: 'de',
              tz: 'Europe/Zurich',
              memories: _memories,
              memoryConsent: _memoryConsent,
              clientContext: const {'mode': 'text', 'source': 'reflection_screen'},
            )
            .timeout(_kNetTimeout);
      }

      _session = _coerceSession(turn);
      _vm = _buildVM(turn);
      _actionUsedInThisSession = true;
    } catch (_) {/* ignore */}
    finally {
      _setLoading(false);
    }
  }

  // ---------------- Hybrid Note ----------------------------------------------

  /// Kombiniert typisierten Text und optionales STT-Transkript zu einer
  /// robusten „Hybrid-Note“ (gekürzt, ohne Dopplungen).
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
    final q = (t.primaryQuestion ?? '').trim();
    final talk =
        t.talk.take(2).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // answerChips (aus Worker), sanft normalisieren + mind. 2 Chips sicherstellen
    final baseChips = t.answerHelpers
        .map(_sanitizeHelper)
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
    final chips = _ensureMinTwoChips(baseChips, q: q);

    final helperSuggestion = (t.helperSuggestion ?? '').trim().isEmpty
        ? null
        : t.helperSuggestion!.trim();

    final risk = t.risk; // abgeleitet aus riskFlag
    final allowClosure =
        (t.flow?.recommendEnd == true) || (t.flow?.moodPrompt == true);
    final moodPrompt = (t.flow?.moodPrompt == true);

    // Hope-Text: bevorzugt aus analysis.summary; sonst nichts.
    final hopeText = (t.analysis?.summary?.trim().isNotEmpty ?? false)
        ? t.analysis!.summary!.trim()
        : null;

    final topicChips = <String>[
      ...t.topicSuggestions,
      ...(t.analysis?.topicSuggestions ?? const <String>[]),
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();

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
    // Hartes Limit spiegelt UI – defensiv hier nochmal:
    x = _cap(x, 800);
    // Kompakte Whitespaces
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  // Min-Gap Gate (Rate-Limit für Sends/Actions)
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
    // (Silent drop – View darf gerne eine sanfte Haptik/Toast übernehmen)
  }

  void _debounceCancel() {
    _pendingSend?.cancel();
    _pendingSend = null;
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  String _sanitizeHelper(String raw) {
    // 1) Trim
    var s = raw.trim();
    if (s.isEmpty) return '';
    // 2) Keine Fragen als Chips
    s = s.replaceAll(RegExp(r'[?？]+$'), '');
    // 3) Endzeichen (Doppelpunkt, Punkt, Ellipsis, Spaces) entfernen
    s = s.replaceAll(RegExp(r'\s*[:：.。…]+\s*$'), '').trim();
    // 4) Max-Länge
    if (s.length > 72) s = '${s.substring(0, 72).trimRight()}…';
    // 5) Exakt ein Ellipsis + Space als Satzstarter-Feeling
    s = '$s… ';
    return s;
  }

  List<String> _ensureMinTwoChips(List<String> chips, {required String q}) {
    if (chips.length >= 2) return chips.take(3).toList();
    final List<String> out = List<String>.from(chips);
    // Neutraler, universeller Zusatz-Starter basierend auf der Leitfrage
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

  @override
  void dispose() {
    _debounceCancel();
    super.dispose();
  }
}
