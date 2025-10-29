//[BASELINE] lib/services/guidance_service.dart (Stand: 29.10.)
// lib/services/guidance_service.dart
//
// ZenYourself — Guidance / Coaching Service (PANDA-REFLECT-12.7 → v6.4.1)
// -----------------------------------------------------------------------------
// Fassade über core/ApiService mit *zwei* stabilen Ebenen:
// 1) Typed-API (Primary): liefert ReflectionTurn (für Controller/VM)
// 2) Normalized-API (Convenience): liefert UI-freundliches Json
//
// Neu (v6.4.1):
// • Kleine Robustheitsverbesserungen beim Risk-Normalizer und Chip-Handling.
// • Präzisere Telemetrie-Flags in _buildMeta() (optional).
// • Kommentare/Docs aufgeräumt.
// • **Signaturen** für start/reflect/next inkl. `memories` + `memoryConsent`,
//   und automatische Übergabe von `context.memories` bei Consent, falls der
//   Caller keine Memories explizit übergibt (Phase 1 — On-Device).
//
// v6.4.0:
// • Voller `meta`-Support in start/next/reflect/closure — wird an ApiService
//   durchgereicht, *rückwärtskompatibel* via dyn-call + Fallback ohne `meta`.
//
// v6.3.x (zur Einordnung):
// • Alle "Full"-Aufrufe können optional `memories` (dynamic) + `memoryConsent` (bool)
//   durchreichen. Der ApiService verpackt dies als `context.memories{...}` (snake_case)
//   und setzt `memory_consent: true|false`. Tolerant gegenüber Map/DTO/String.
// • recallTopics(): nutzt topicHint bereits für das Ranking im Memory-Recall.
// • Normalized-JSON enthält (falls vorhanden) auch `analysis` inkl. `insight_score`,
//   sowie optionale `topic_suggestions`. `insight_score` kommt aus TurnAnalysis.
// • Keine PII im Logging; nur knappe Debug-Hinweise.
// • Garantien: mind. 2 Answer-Chips (sanfter Fallback), ruhiger Mirror,
//   Risk-Mapping {none|mild|high}, Session passthrough.
//
// -----------------------------------------------------------------------------

library guidance_service;

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'core/api_service.dart';
import 'guidance/dtos.dart';

// Memory-Fassade (für UI-Bridge/Hope & optionalen Debug-Hinweis)
import '../core/memory/memory_service.dart' as mem;

typedef Json = Map<String, dynamic>;

class GuidanceService {
  GuidanceService._();
  static final GuidanceService instance = GuidanceService._();

  static const String kOfflineError =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';
  static const String kFooterDisclaimer =
      'Dies ist keine Therapie, sondern eine mentale Begleitungs-App.';

  // Sanfter, universeller Fallback-Text für Chips
  static const String _kFallbackChipSeed = 'Wichtig ist mir außerdem';
  static const String _kFallbackChipSeedAlt = 'Ich mag klein anfangen';

  String get errorHint => ApiService.errorHint;

  // ---------------------------------------------------------------------------
  // HTTP / Worker
  // ---------------------------------------------------------------------------
  void configureHttp({
    HttpInvoker? invoker,
    String? baseUrl,
    Duration? timeout,
  }) {
    ApiService.instance.configureHttp(
      invoker: invoker,
      baseUrl: baseUrl,
      timeout: timeout,
    );
    if (kDebugMode) {
      debugPrint('[GuidanceService] HTTP configured '
          '(base=${baseUrl ?? '-'}, timeout=${timeout?.inSeconds}s)');
    }
  }

  /// Bequeme Worker-Konfiguration (Wrapper um ApiService.configureForWorker).
  void configureForWorker({
    required String baseUrl,
    String? appToken,
    Duration timeout = const Duration(seconds: 25),
  }) {
    ApiService.instance.configureForWorker(
      baseUrl: baseUrl,
      appToken: appToken,
      timeout: timeout,
    );
    if (kDebugMode) {
      debugPrint('[GuidanceService] Worker configured '
          '(base=$baseUrl, token=${appToken == null ? 'none' : '***'}, timeout=${timeout.inSeconds}s)');
    }
  }

  Future<bool> health() => ApiService.instance.healthCheck();

  // ===========================================================================
  // Intern: Memories best-effort beschaffen, wenn Consent==true
  // ===========================================================================
  Future<dynamic> _autoMemoriesIfConsent({
    required bool consent,
    dynamic provided,
  }) async {
    if (!consent) return provided;
    if (provided != null) return provided;
    try {
      final map =
          await mem.MemoryService.instance.buildContextMemories(consent: true);
      // Nur zurückgeben, wenn tatsächlich Inhalte vorhanden sind
      if (map is Map && map.isNotEmpty) return map;
    } catch (_) {/* nie blockieren */}
    return provided;
  }

  // ===========================================================================
  // 1) TYPED-API (Primary) — liefert ReflectionTurn (kompatibel zu Controller)
  // ===========================================================================

  Future<ReflectionTurn> startSessionFull({
    required String text,
    ReflectionSession? session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    dynamic memories, // optional
    bool memoryConsent = false, // optional
    UserAction? userAction, // optional
    Map<String, dynamic>? clientContext,
    Map<String, dynamic>? meta, // ✅ neu (rückwärtskompatibel)
  }) async {
    final svc = ApiService.instance;

    // On-Device Memories nur dann automatisch anreichern, wenn Consent==true
    final autoMem = await _autoMemoriesIfConsent(
        consent: memoryConsent, provided: memories);

    try {
      // Neuer ApiService mit `meta`?
      final dyn = svc as dynamic;
      final Future<ReflectionTurn>? fut = dyn.startSessionFull?.call(
        text: text,
        session: session,
        locale: locale,
        tz: tz,
        maxTurns: maxTurns,
        history: history,
        memories: autoMem,
        memoryConsent: memoryConsent,
        userAction: userAction,
        clientContext: clientContext,
        meta: meta, // <—
      );
      if (fut != null) return await fut;
    } catch (_) {/* fall back */}
    // Fallback ohne `meta`
    return ApiService.instance.startSessionFull(
      text: text,
      session: session,
      locale: locale,
      tz: tz,
      maxTurns: maxTurns,
      history: history,
      memories: autoMem,
      memoryConsent: memoryConsent,
      userAction: userAction,
      clientContext: clientContext,
    );
  }

  Future<ReflectionTurn> reflectFull({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories, // optional
    bool memoryConsent = false, // optional
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
    Map<String, dynamic>? meta, // ✅ neu
  }) async {
    final svc = ApiService.instance;
    final autoMem = await _autoMemoriesIfConsent(
        consent: memoryConsent, provided: memories);

    try {
      final dyn = svc as dynamic;
      final Future<ReflectionTurn>? fut = dyn.reflectFull?.call(
        text: text,
        session: session,
        locale: locale,
        tz: tz,
        history: history,
        memories: autoMem,
        memoryConsent: memoryConsent,
        userAction: userAction,
        clientContext: clientContext,
        meta: meta,
      );
      if (fut != null) return await fut;
    } catch (_) {/* fall back */}
    return ApiService.instance.reflectFull(
      text: text,
      session: session,
      locale: locale,
      tz: tz,
      history: history,
      memories: autoMem,
      memoryConsent: memoryConsent,
      userAction: userAction,
      clientContext: clientContext,
    );
  }

  Future<ReflectionTurn> nextTurnFull({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories, // optional
    bool? memoryConsent, // optional
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
    Map<String, dynamic>? meta, // ✅ neu
  }) async {
    final svc = ApiService.instance;
    final consent = memoryConsent ?? false;
    final autoMem =
        await _autoMemoriesIfConsent(consent: consent, provided: memories);

    try {
      final dyn = svc as dynamic;
      final Future<ReflectionTurn>? fut = dyn.nextTurnFull?.call(
        session: session,
        text: text,
        locale: locale,
        tz: tz,
        history: history,
        memories: autoMem,
        memoryConsent: memoryConsent,
        userAction: userAction,
        clientContext: clientContext,
        meta: meta,
      );
      if (fut != null) return await fut;
    } catch (_) {/* fall back */}
    return ApiService.instance.nextTurnFull(
      session: session,
      text: text,
      locale: locale,
      tz: tz,
      history: history,
      memories: autoMem,
      memoryConsent: memoryConsent,
      userAction: userAction,
      clientContext: clientContext,
    );
  }

  Future<ReflectionTurn> nextTurnAction({
    required ReflectionSession session,
    required UserAction action,
    String locale = 'de',
    String tz = 'Europe/Zurich',
  }) async {
    final svc = ApiService.instance;
    try {
      final dyn = svc as dynamic;
      final Future<ReflectionTurn>? fut = dyn.nextTurnAction?.call(
        session: session,
        action: action,
        locale: locale,
        tz: tz,
      );
      if (fut != null) return await fut;
    } catch (_) {/* fallback unten */}
    return ApiService.instance.nextTurnFull(
      session: session,
      text: '',
      locale: locale,
      tz: tz,
    );
  }

  Future<ReflectionTurn> talk({
    required ReflectionSession session,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) {
    return ApiService.instance.talk(
      session: session,
      userText: userText,
      locale: locale,
      tz: tz,
      history: history,
      userAction: userAction,
      clientContext: clientContext,
    );
  }

  // ===========================================================================
  // 2) NORMALIZED-API (Convenience) — liefert UI-freundliches Json
  // ===========================================================================

  Future<Json> startSession({
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    Map<String, dynamic>? clientContext,
    dynamic memories, // optional
    bool memoryConsent = false, // optional
    UserAction? userAction, // optional
    Map<String, dynamic>? meta, // ✅ neu
  }) async {
    final t = await startSessionFull(
      text: text,
      session: null,
      locale: locale,
      tz: tz,
      maxTurns: maxTurns,
      history: history,
      clientContext: clientContext,
      memories: memories,
      memoryConsent: memoryConsent,
      userAction: userAction,
      meta: meta,
    );
    return _turnToJson(t);
  }

  Future<Json> startSessionNormalized({
    required String text,
    ReflectionSession? session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    dynamic memories, // optional
    bool memoryConsent = false, // optional
    Map<String, dynamic>? clientContext,
    UserAction? userAction,
    Map<String, dynamic>? meta, // ✅ neu
  }) async {
    final t = await startSessionFull(
      text: text,
      session: session,
      locale: locale,
      tz: tz,
      maxTurns: maxTurns,
      history: history,
      memories: memories,
      memoryConsent: memoryConsent,
      clientContext: clientContext,
      userAction: userAction,
      meta: meta,
    );
    return _turnToJson(t);
  }

  Future<Json> nextTurnNormalized({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories, // optional
    bool? memoryConsent, // optional
    Map<String, dynamic>? clientContext,
    UserAction? userAction,
    Map<String, dynamic>? meta, // ✅ neu
  }) async {
    final t = await nextTurnFull(
      session: session,
      text: text,
      locale: locale,
      tz: tz,
      history: history,
      memories: memories,
      memoryConsent: memoryConsent,
      clientContext: clientContext,
      userAction: userAction,
      meta: meta,
    );
    return _turnToJson(t);
  }

  Future<Json> reflectNormalized({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories, // optional
    bool memoryConsent = false, // optional
    Map<String, dynamic>? clientContext,
    UserAction? userAction,
    Map<String, dynamic>? meta, // ✅ neu
  }) async {
    final t = await reflectFull(
      session: session,
      text: text,
      locale: locale,
      tz: tz,
      history: history,
      memories: memories,
      memoryConsent: memoryConsent,
      clientContext: clientContext,
      userAction: userAction,
      meta: meta,
    );
    return _turnToJson(t);
  }

  Future<Json> nextTurnActionNormalized({
    required ReflectionSession session,
    required UserAction action,
    String locale = 'de',
    String tz = 'Europe/Zurich',
  }) async {
    final t = await nextTurnAction(
      session: session,
      action: action,
      locale: locale,
      tz: tz,
    );
    return _turnToJson(t);
  }

  Future<Json> talkNormalized({
    required ReflectionSession session,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    Map<String, dynamic>? clientContext,
    UserAction? userAction,
  }) async {
    final t = await talk(
      session: session,
      userText: userText,
      locale: locale,
      tz: tz,
      history: history,
      clientContext: clientContext,
      userAction: userAction,
    );
    return _turnToJson(t);
  }

  // ---------------------------------------------------------------------------
  // Closure / Mood-Intro (liefert Json; typed ist hier nicht nötig)
  // ---------------------------------------------------------------------------
  Future<Json> closureFull({
    required ReflectionSession? session,
    required String answer,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    Map<String, dynamic>? meta, // ✅ neu
  }) async {
    try {
      // Neuer ApiService mit `meta`?
      Map<String, dynamic> res;
      try {
        final dyn = ApiService.instance as dynamic;
        // Hinweis: Einige ApiService-Versionen akzeptieren (noch) keine memories in closureFull.
        // Wir geben nur `meta` mit, Memories werden bereits im Turn verarbeitet.
        final Future<Map<String, dynamic>>? fut = dyn.closureFull?.call(
          session: session,
          answer: answer,
          locale: locale,
          tz: tz,
          meta: meta,
        );
        if (fut != null) {
          res = await fut;
        } else {
          // Fallback ohne meta
          res = await ApiService.instance.closureFull(
            session: session,
            answer: answer,
            locale: locale,
            tz: tz,
          );
        }
      } on NoSuchMethodError {
        res = await ApiService.instance.closureFull(
          session: session,
          answer: answer,
          locale: locale,
          tz: tz,
        );
      }

      final norm = _normalizeClosureResponse(res);
      final risk = _normalizeRisk(res);

      return {
        ...norm,
        ...risk, // garantiert: risk_level + risk
        'disclaimer': kFooterDisclaimer,
      };
    } on NoSuchMethodError {
      return <String, dynamic>{
        'flow': {
          'recommend_end': true,
          'mood_prompt': true,
        },
        if (session != null) 'session': session.toJson(),
        'closure': {
          'mood_intro': {'text': ''},
          'hope_reply': '',
          'closure_prompt': '',
        },
        ..._normalizeRisk(null),
        'disclaimer': kFooterDisclaimer,
      };
    } catch (_) {
      return <String, dynamic>{
        'flow': {
          'recommend_end': true,
          'mood_prompt': true,
        },
        if (session != null) 'session': session.toJson(),
        'closure': {
          'mood_intro': {'text': ''},
          'hope_reply': '',
          'closure_prompt': '',
        },
        ..._normalizeRisk(null),
        'disclaimer': kFooterDisclaimer,
      };
    }
  }

  // ---------------------------------------------------------------------------
  // Story & Mood
  // ---------------------------------------------------------------------------
  Future<StoryResult> story({
    required List<String> entryIds,
    List<String>? topics,
    bool useServerIfAvailable = true,
  }) =>
      ApiService.instance.story(
        entryIds: entryIds,
        topics: topics,
        useServerIfAvailable: useServerIfAvailable,
      );

  Future<bool> mood({
    required String sessionId,
    required String moodIdOrValue,
    int? helpfulness1to5,
  }) async {
    final res = await ApiService.instance.mood(
      entryId: sessionId,
      icon: int.tryParse(moodIdOrValue) ?? 0,
      note: helpfulness1to5 == null ? null : 'helpfulness=$helpfulness1to5',
      useServerIfAvailable: true,
    );
    return res.saved;
  }

  // ---------------------------------------------------------------------------
  // Memory-Recall (UI-Fassade) — Phase 1
  // ---------------------------------------------------------------------------

  Future<List<String>> recallTopics({int limit = 6, String? topicHint}) async {
    try {
      final items = await mem.MemoryService.instance
          .recall(limit: limit, topicHint: topicHint);

      final out = <String>[];
      String topicOf(dynamic it) {
        if (it is Map) {
          final m = Map<String, dynamic>.from(it);
          return (m['topic'] ?? m['tag'] ?? '').toString();
        }
        try {
          final m = (it as dynamic).toJson?.call();
          if (m is Map) return (m['topic'] ?? m['tag'] ?? '').toString();
        } catch (_) {}
        try {
          final t = (it as dynamic).topic;
          if (t != null) return t.toString();
        } catch (_) {}
        return it?.toString() ?? '';
      }

      final hint = (topicHint ?? '').trim().toLowerCase();
      bool matchesHint(String s) {
        if (hint.isEmpty) return true;
        final t = s.toLowerCase();
        return t.contains(hint);
      }

      for (final it in items) {
        final t = topicOf(it).trim();
        if (t.isEmpty) continue;
        if (!matchesHint(t)) continue;
        final key = t.toLowerCase();
        if (!out.any((e) => e.toLowerCase() == key)) {
          out.add(t);
          if (out.length >= limit) break;
        }
      }
      return out;
    } catch (_) {
      return <String>[];
    }
  }

  Future<Json?> contextHint({
    int maxFacets = 3,
    int maxTags = 5,
    int maxAgeDays = 14,
  }) async {
    try {
      final hint = mem.MemoryService.instance.buildContextHint(
        maxFacets: maxFacets,
        maxTags: maxTags,
        maxAgeDays: maxAgeDays,
      );
      if (hint == null) return null;

      List<String>? asList(dynamic v) {
        if (v == null) return null;
        if (v is List) {
          return v
              .where((e) => e != null)
              .map((e) => e.toString())
              .where((s) => s.trim().isNotEmpty)
              .toList();
        }
        return null;
      }

      final facets = asList((hint as dynamic).facets);
      final tags = asList((hint as dynamic).tags);
      final topics = asList((hint as dynamic).topics);

      final out = <String, dynamic>{};
      if (facets != null && facets.isNotEmpty) out['recent_facets'] = facets;
      if (tags != null && tags.isNotEmpty) out['recent_tags'] = tags;
      if (topics != null && topics.isNotEmpty) out['last_themes'] = topics;
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Home/Starter-Chips: bewusst leer (nur „Background“)
  // ---------------------------------------------------------------------------
  Future<List<String>> recentTopics({int limit = 6}) async => <String>[];
  Future<List<String>> recentHelpers({int limit = 3}) async => <String>[];

  // ===========================================================================
  // Helpers (Sanitizer / Normalisierung)
  // ===========================================================================

  /// Extrahiert & säubert Answer-Chips (max. 3). Fallback auf followups.
  /// **Mindestens 2 Chips**: bei 0 → 2 Defaults, bei 1 → 1 Default ergänzen.
  List<String> _extractAnswerHelpers(ReflectionTurn t) {
    final primary = t.answerHelpers;
    final legacy = t.followups;
    final candidates = primary.isNotEmpty ? primary : legacy;

    final seen = <String>{};
    final out = <String>[];
    for (final f in candidates) {
      final cleaned = _cleanChipForDisplay(f);
      if (cleaned.isEmpty) continue;
      final key = cleaned.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(cleaned);
      if (out.length >= 3) break;
    }

    if (out.isEmpty) {
      out.add(_cleanChipForDisplay(_kFallbackChipSeed));
      out.add(_cleanChipForDisplay(_kFallbackChipSeedAlt));
    } else if (out.length == 1) {
      out.add(_cleanChipForDisplay(_kFallbackChipSeed));
    }
    return out;
  }

  /// Anzeige-Variante (Bubble/Chips).
  String _cleanChipForDisplay(String s) {
    var x = s.trim();
    x = x.replaceAll(RegExp(r'^[0-9]+[.)]\s+'), '');
    x = x.replaceAll(RegExp(r'^[\u2013\-\u2022\s]+'), '');
    x = x.replaceAll(RegExp('^[„“"\'»«]+'), '');
    x = x.replaceAll(RegExp(r'\s*[:：]\s*$'), ''); // trailing ':' entfernen
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    x = x.replaceAll(RegExp(r'\s*[?!]+$'), '');
    if (x.length > 72) x = '${x.substring(0, 72).trimRight()}…';
    if (!x.endsWith('…')) x = '$x…';
    return x.trim();
  }

  /// Einfüge-Variante (Textfeld, Insert-only).
  String _cleanChipForInsert(String s) {
    var x = s.trim();
    x = x.replaceAll(RegExp(r'^[0-9]+[.)]\s+'), '');
    x = x.replaceAll(RegExp(r'^[\u2013\-\u2022\s]+'), '');
    x = x.replaceAll(RegExp('^[„“"\'»«]+'), '');
    x = x.replaceAll(RegExp(r'\s*[:：]\s*$'), '');
    x = x.replaceAll(RegExp(r'[…]+$'), '');
    x = x.replaceAll(RegExp(r'\s*[?!.\u2026]+$'), '');
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  /// Entfernt Instruktions-Sätze aus dem Mirror (und reine Fragen).
  String? _cleanMirror(String? mirror) {
    if (mirror == null) return null;
    var text = mirror.trim();

    final patterns = <RegExp>[
      RegExp(r'^\s*Unten\s+findest\s+du\s+Antwort[-\s]?Chips.*$',
          caseSensitive: false, multiLine: true),
      RegExp(r'^\s*Unter\s+dem\s+Eingabefeld\s+findest\s+du\s+Antwort.*$',
          caseSensitive: false, multiLine: true),
      RegExp(r'^\s*Wähle\s+einen\s+Antwort[-\s]?Chip.*$',
          caseSensitive: false, multiLine: true),
      RegExp(r'you\s+can\s+use\s+the\s+answer\s+chips.*',
          caseSensitive: false, dotAll: true),
      RegExp(r"below\s+you'll\s+find\s+answer\s+chips.*",
          caseSensitive: false, dotAll: true),
      RegExp(r'antworte\s+in\s+\d+\s*(?:bis|–|-)\s*\d+\s*sätz',
          caseSensitive: false, dotAll: true),
    ];
    for (final p in patterns) {
      text = text.replaceAll(p, '').trim();
    }

    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (text.endsWith('?')) return null; // reine Frage ≠ Mirror
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> _normalizeClosureResponse(Map<String, dynamic> src) {
    Map<String, dynamic> m(dynamic x) => (x is Map<String, dynamic>)
        ? x
        : (x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{});

    final flow = m(src['flow']);
    final closure = m(src['closure']);
    final moodIntro = m(closure['mood_intro']);

    return {
      ...src,
      'flow': {
        ...flow,
        'mood_prompt':
            flow['mood_prompt'] == true || flow['recommend_end'] == true,
        'recommend_end': flow['recommend_end'] == true,
      },
      'closure': {
        ...closure,
        'mood_intro': {
          'text': (moodIntro['text'] ?? '').toString(),
        },
        'hope_reply': (closure['hope_reply'] ?? '').toString(),
        'closure_prompt': (closure['closure_prompt'] ?? '').toString(),
      },
    };
  }

  /// Risk immer verfügbar machen (risk_level + risk).
  Map<String, dynamic> _normalizeRisk(dynamic src) {
    String asStr(dynamic v) => (v ?? '').toString().trim().toLowerCase();

    String level = 'none';
    bool risk = false;

    if (src is Map) {
      final s = Map<String, dynamic>.from(src);
      final lvl = asStr(s['risk_level']);
      final legacyLvl = asStr(s['level']); // manche Server
      final flag = asStr(s['risk_flag']); // support|crisis
      final boolFlag = s['risk'] == true;

      // vorrangig Strings mappen
      String mapLevel(String x) {
        if (x == 'high' || x == 'crisis') return 'high';
        if (x == 'mild' || x == 'support' || x == 'true') return 'mild';
        return 'none';
      }

      final candidate =
          lvl.isNotEmpty ? lvl : (legacyLvl.isNotEmpty ? legacyLvl : flag);
      level = mapLevel(candidate);

      if (level == 'none' && boolFlag) level = 'mild'; // konservativ
      risk = level == 'high' || level == 'mild' || boolFlag;
    }

    return {'risk_level': level, 'risk': risk};
  }

  // ---------------------------------------------------------------------------
  // Normalisierung → UI-freundliches JSON
  // ---------------------------------------------------------------------------
  Json _turnToJson(ReflectionTurn t) {
    final ReflectionFlow flow = t.flow ??
        const ReflectionFlow(recommendEnd: false, suggestBreak: false);

    final flowJson = flow.toJson();
    final flowOut = <String, dynamic>{
      ...flowJson,
      'mood_prompt':
          (flowJson['mood_prompt'] == true) || (flow.recommendEnd == true),
      'recommend_end': flow.recommendEnd == true,
    };

    final bool shouldPromptMood =
        (flowOut['mood_prompt'] == true) || (flow.recommendEnd == true);

    // Risk-Mapping
    final String riskLevelOut = switch (t.riskFlag) {
      'crisis' => 'high',
      'support' => 'mild',
      _ => 'none',
    };
    final bool riskBool = (riskLevelOut == 'high' || riskLevelOut == 'mild');

    // Mirror (gereinigt)
    final String? cleanedMirror = _cleanMirror(t.mirror);

    // Primäre Frage (DTO-Getter sichert '?')
    final String? primaryQuestion = t.primaryQuestion;

    // Facetten/Tags
    final List<String> facets =
        t.tags.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // Chips (Display & Insert) — mind. 2 sicherstellen
    final List<String> answerHelpersDisplay = _extractAnswerHelpers(t);
    final List<String> answerHelpersInsert = answerHelpersDisplay
        .map(_cleanChipForInsert)
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    // Chip-Typ nur als Stil-Hinweis
    final String chipType = _inferChipType(primaryQuestion, t.tags);

    // Stabile Chip-Set-ID (inkl. finaler Display-Chips)
    final sessMap = t.session.toJson();
    final sid = (sessMap['thread_id'] ?? sessMap['id'] ?? '').toString();
    final sturn = (sessMap['turn_index'] ?? sessMap['turn'] ?? 0).toString();
    final seed = answerHelpersDisplay.join('|');
    final chipSetId = '$sid:$sturn:${_fnv1a32(seed).toRadixString(16)}';

    final map = <String, dynamic>{
      'session': t.session.toJson(),
      'risk_level': riskLevelOut,
      'risk': riskBool,
      'flow': flowOut,
      'disclaimer': kFooterDisclaimer,
      'understanding': {
        'facets': facets,
      },
      'ui': {
        'chips': {
          'insert_only': true,
          'auto_send': false,
          'persist_until': 'user_interaction',
          'place': 'composer_only',
          'type': chipType,
          'set_id': chipSetId,
          'reset_suggestion': shouldPromptMood,
        },
      },
    };

    // insight_score bevorzugt aus TurnAnalysis (Fallback: evtl. aus flow)
    final double? insightFromAnalysis = t.analysis?.insightScore;
    final dynamic maybeInsightInFlow = flowJson['insight_score'];
    if (insightFromAnalysis != null) {
      map['insight_score'] = insightFromAnalysis;
    } else if (maybeInsightInFlow is num) {
      map['insight_score'] = maybeInsightInFlow;
    }

    if (cleanedMirror != null) {
      map['mirror'] = cleanedMirror;
    }
    if (!shouldPromptMood && (primaryQuestion?.trim().isNotEmpty ?? false)) {
      map['question'] = primaryQuestion;
    }
    if (answerHelpersDisplay.isNotEmpty) {
      map['answer_helpers'] = answerHelpersDisplay;
      map['answer_helpers_insert'] = answerHelpersInsert;
      map['chip_set_id'] = chipSetId;
    }
    if (t.outputText.trim().isNotEmpty &&
        t.outputText != ApiService.errorHint) {
      map['output_text'] = t.outputText;
    }
    if (t.talk.isNotEmpty) {
      map['talk'] = t.talk;
    }
    if (t.tags.isNotEmpty) {
      map['tags'] = t.tags;
    }
    if (t.context.isNotEmpty) {
      map['context'] = t.context;
    }
    final hs = (t.helperSuggestion ?? '').trim();
    if (hs.isNotEmpty) {
      map['helper_suggestion'] = hs;
    }

    // TurnAnalysis + topic_suggestions (optional)
    if (t.analysis != null) {
      map['analysis'] = t.analysis!.toJson();
    }
    if (t.topicSuggestions.isNotEmpty) {
      map['topic_suggestions'] = t.topicSuggestions;
    }

    return map;
  }

  // Nur Stil-Hinweis
  String _inferChipType(String? question, List<String> tags) {
    final q = (question ?? '').toLowerCase();
    if (q.contains('kleine option') ||
        (q.contains('kurz') && q.contains('ausprobieren'))) {
      return 'tips';
    }
    if (tags.any((t) =>
        t.toLowerCase().contains('tip') || t.toLowerCase().contains('übung'))) {
      return 'tips';
    }
    return 'reflect';
  }
}

/// Stabiler 32-bit FNV-1a Hash (plattform-/buildunabhängig für Telemetrie/IDs).
int _fnv1a32(String s) {
  const int FNV_PRIME = 0x01000193;
  int hash = 0x811C9DC5;
  for (final cu in s.codeUnits) {
    hash ^= cu;
    hash = (hash * FNV_PRIME) & 0xFFFFFFFF;
  }
  return hash;
}
