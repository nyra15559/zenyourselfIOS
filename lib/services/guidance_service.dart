// [BASELINE] lib/services/guidance_service.dart (Stand: 2025-11-04, v6.4.12)
// ZenYourself — Guidance / Coaching Service
// -----------------------------------------------------------------------------
// Änderungen v6.4.12 (Async-Fix for Client-Memory Bridge):
// • _prepareMemories(...) auf async umgestellt → Future<Map<String,dynamic>?>
// • Alle Aufrufer (startSessionFull/reflectFull/nextTurnFull) verwenden 'await'.
// -----------------------------------------------------------------------------
// v6.4.11 (Client-Memory Bridge / Name-Injection):
// • Consent-Automat: memoryConsent → bool (Default: MemoryService.shareEnabled)
// • Bei Consent: meta.flags.client_memory = true wird in JEDEM Call gesetzt.
// • Name-Injection: erkennt im User-Text „ich heiße/ich heisse/mein Name ist/ich bin …“
//   und ergänzt on-the-fly context.memories.identity.name (nur bei Consent).
// • Kleine Memories: Wenn keine Memories übergeben wurden, werden bei Consent
//   kompakte Client-Memories via MemoryService.buildContextMemories(consent:true)
//   gemerged (Hardcap liegt im ApiService).
// -----------------------------------------------------------------------------
// v6.4.10 (Context-Carryover / Next-Turn-Fassade):
// • Neue Fassade nextTurnFull(...): ruft ApiService.sendNextTurnFull(...) auf
//   (Fallback → ApiService.nextTurnFull), um die /next_turn_full-Route zu nutzen.
// • History-Durchreichung: Signatur akzeptiert List<HistoryTurn>; 1:1-Mapping
//   nach {role, content} (keine Heuristik).
// • Deprecation: jegliche interne Nutzung von reflect_full entfernt/markiert.
// -----------------------------------------------------------------------------
// v6.4.9 (S3.3 Round/Session Guards):
// • Meta wird *immer* an ApiService weitergereicht (auch im typed Fallback).
// • intro.round_count wird aus der Session autoritativ gesetzt (Guard).
// • meta.session_hint enthält thread_id/id/turn_index für Observability.
// • nextTurnAction(..., {meta}) → optionales meta weiterleitbar.
// • Normalized-JSON ergänzt: round_count, thread_id (Convenience).
// -----------------------------------------------------------------------------
// S4.2 — Smalltalk Pass-through:
// • smalltalk_reply aus ReflectionTurn wird in _turnToJson() ins Normalized-JSON
//   übernommen (Key: 'smalltalk_reply'); keine Doppelung mit 'talk'.
// -----------------------------------------------------------------------------
// Vorherige Notes:
// • memoryConsent-Handling (nullable→bool); Journey/Story stabile IDs via FNV.
// -----------------------------------------------------------------------------

library guidance_service;

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'core/api_service.dart';
import 'guidance/dtos.dart';
import '../core/memory/memory_service.dart' as mem;

typedef Json = Map<String, dynamic>;

class GuidanceService {
  GuidanceService._();
  static final GuidanceService instance = GuidanceService._();

  static const String kOfflineError =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';
  static const String kFooterDisclaimer =
      'Dies ist keine Therapie, sondern eine mentale Begleitungs-App.';

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
  // 1) Typed API — Proxys auf ApiService.*
  // ===========================================================================

  Future<ReflectionTurn> startSessionFull({
    required String text,
    ReflectionSession? session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    dynamic memories,
    bool? memoryConsent, // Guidance: nullable
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
    Map<String, dynamic>? meta,
  }) async {
    // 1) Consent bestimmen
    final bool consent =
        memoryConsent ?? mem.MemoryService.instance.shareEnabled;

    // 2) Meta anreichern + client_memory-Flag setzen (bei Consent)
    Map<String, dynamic>? m = _attachIntroAndSessionMeta(meta, session);
    m = _withClientMemoryFlag(m, consent);

    // 3) Memories vorbereiten (Name-Injection + kleine Memories)
    final mems = await _prepareMemories(
      incoming: memories,
      consent: consent,
      userText: text,
    );

    final svc = ApiService.instance;
    try {
      final dyn = svc as dynamic;
      final Future<ReflectionTurn>? fut = dyn.startSessionFull?.call(
        text: text,
        session: session,
        locale: locale,
        tz: tz,
        maxTurns: maxTurns,
        history: history,
        memories: mems,
        memoryConsent: consent, // <- bool
        userAction: userAction,
        clientContext: clientContext,
        meta: m,
      );
      if (fut != null) return await fut;
    } catch (_) {/* ignore */}
    // Typed Fallback
    try {
      final dyn2 = svc as dynamic;
      final Future<ReflectionTurn>? fut2 = dyn2.startSessionFull?.call(
        text: text,
        session: session,
        locale: locale,
        tz: tz,
        maxTurns: maxTurns,
        history: history,
        memories: mems,
        memoryConsent: consent,
        userAction: userAction,
        clientContext: clientContext,
        meta: m,
      );
      if (fut2 != null) return await fut2;
    } catch (_) {/* ignore */}
    return ApiService.instance.startSessionFull(
      text: text,
      session: session,
      locale: locale,
      tz: tz,
      maxTurns: maxTurns,
      history: history,
      memories: mems,
      memoryConsent: consent, // <- bool
      userAction: userAction,
      clientContext: clientContext,
    );
  }

  /// @deprecated: Bitte `startSessionFull` / `nextTurnFull` verwenden.
  Future<ReflectionTurn> reflectFull({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories,
    bool? memoryConsent, // Guidance: nullable
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
    Map<String, dynamic>? meta,
  }) async {
    final bool consent =
        memoryConsent ?? mem.MemoryService.instance.shareEnabled;

    Map<String, dynamic>? m = _attachIntroAndSessionMeta(meta, session);
    m = _withClientMemoryFlag(m, consent);

    final mems = await _prepareMemories(
      incoming: memories,
      consent: consent,
      userText: text,
    );

    final svc = ApiService.instance;
    try {
      final dyn = svc as dynamic;
      final Future<ReflectionTurn>? fut = dyn.reflectFull?.call(
        text: text,
        session: session,
        locale: locale,
        tz: tz,
        history: history,
        memories: mems,
        memoryConsent: consent, // <- bool
        userAction: userAction,
        clientContext: clientContext,
        meta: m,
      );
      if (fut != null) return await fut;
    } catch (_) {/* ignore */}
    try {
      final dyn2 = svc as dynamic;
      final Future<ReflectionTurn>? fut2 = dyn2.reflectFull?.call(
        text: text,
        session: session,
        locale: locale,
        tz: tz,
        history: history,
        memories: mems,
        memoryConsent: consent,
        userAction: userAction,
        clientContext: clientContext,
        meta: m,
      );
      if (fut2 != null) return await fut2;
    } catch (_) {/* ignore */}
    return ApiService.instance.reflectFull(
      text: text,
      session: session,
      locale: locale,
      tz: tz,
      history: history,
      memories: mems,
      memoryConsent: consent, // <- bool
      userAction: userAction,
      clientContext: clientContext,
    );
  }

  /// Neue Fassade für den Full-Turn über /next_turn_full.
  /// History-Durchreichung: erwartet `List<HistoryTurn>` und mappt 1:1.
  Future<ReflectionTurn> nextTurnFull({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<HistoryTurn>? history, // <-- NEU: typed History
    dynamic memories,
    bool? memoryConsent, // Guidance: nullable
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
    Map<String, dynamic>? meta,
  }) async {
    final bool consent =
        memoryConsent ?? mem.MemoryService.instance.shareEnabled;

    Map<String, dynamic>? m = _attachIntroAndSessionMeta(meta, session);
    m = _withClientMemoryFlag(m, consent);

    final List<Map<String, String>>? messages =
        _historyToMessages(history); // verlustfrei, keine Heuristik

    final mems = await _prepareMemories(
      incoming: memories,
      consent: consent,
      userText: text,
    );

    final svc = ApiService.instance;

    // Primär: neue öffentliche API sendNextTurnFull(...)
    try {
      final dyn = svc as dynamic;
      final Future<ReflectionTurn>? fut = dyn.sendNextTurnFull?.call(
        session: session,
        text: text,
        locale: locale,
        tz: tz,
        history: messages,
        memories: mems,
        memoryConsent: consent,
        userAction: userAction,
        clientContext: clientContext,
        meta: m,
      );
      if (fut != null) return await fut;
    } catch (_) {/* ignore */}

    // Fallback: ältere API nextTurnFull(...)
    try {
      final dyn2 = svc as dynamic;
      final Future<ReflectionTurn>? fut2 = dyn2.nextTurnFull?.call(
        session: session,
        text: text,
        locale: locale,
        tz: tz,
        history: messages,
        memories: mems,
        memoryConsent: consent,
        userAction: userAction,
        clientContext: clientContext,
        meta: m,
      );
      if (fut2 != null) return await fut2;
    } catch (_) {/* ignore */}

    // Statisch typisierter Fallback (falls dyn nicht verfügbar)
    return ApiService.instance.nextTurnFull(
      session: session,
      text: text,
      locale: locale,
      tz: tz,
      history: messages,
      memories: mems,
      memoryConsent: consent,
      userAction: userAction,
      clientContext: clientContext,
    );
  }

  Future<ReflectionTurn> nextTurnAction({
    required ReflectionSession session,
    required UserAction action,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    Map<String, dynamic>? meta, // S3.3: meta optional
  }) async {
    Map<String, dynamic>? m = _attachIntroAndSessionMeta(meta, session);
    // Auch bei Aktionen das Flag setzen (wenn Consent aktiv ist)
    m = _withClientMemoryFlag(
      m,
      mem.MemoryService.instance.shareEnabled,
    );

    final svc = ApiService.instance;
    try {
      final dyn = svc as dynamic;
      final Future<ReflectionTurn>? fut = dyn.nextTurnAction?.call(
        session: session,
        action: action,
        locale: locale,
        tz: tz,
        meta: m,
      );
      if (fut != null) return await fut;
    } catch (_) {/* ignore */}
    // Fallback: emuliere „leeren“ Next-Turn (meta via dyn versuchen)
    try {
      final dyn2 = svc as dynamic;
      final Future<ReflectionTurn>? fut2 = dyn2.nextTurnFull?.call(
        session: session,
        text: '',
        locale: locale,
        tz: tz,
        meta: m,
      );
      if (fut2 != null) return await fut2;
    } catch (_) {/* ignore */}
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

  // ---------------------------------------------------------------------------
  // Closure / Mood-Intro
  // ---------------------------------------------------------------------------
  Future<Json> closureFull({
    required ReflectionSession? session,
    required String answer,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    Map<String, dynamic>? meta,
  }) async {
    // S3.3: Meta inkl. round_count/session_hint
    Map<String, dynamic>? m = _attachIntroAndSessionMeta(meta, session);
    // Bei Consent ebenfalls das client_memory-Flag setzen (observability/stabil)
    m = _withClientMemoryFlag(
      m,
      mem.MemoryService.instance.shareEnabled,
    );

    try {
      Map<String, dynamic> res;
      try {
        final dyn = ApiService.instance as dynamic;
        final Future<Map<String, dynamic>>? fut = dyn.closureFull?.call(
          session: session,
          answer: answer,
          locale: locale,
          tz: tz,
          meta: m,
        );
        res = fut != null
            ? await fut
            : await ApiService.instance.closureFull(
                session: session, answer: answer, locale: locale, tz: tz);
      } on NoSuchMethodError {
        res = await ApiService.instance.closureFull(
            session: session, answer: answer, locale: locale, tz: tz);
      }

      final norm = _normalizeClosureResponse(res);
      final risk = _normalizeRisk(res);

      return {
        ...norm,
        ...risk,
        'disclaimer': kFooterDisclaimer,
      };
    } catch (_) {
      return <String, dynamic>{
        'flow': {'recommend_end': true, 'mood_prompt': true},
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
  // Story — liefert StoryResult (mit required id, stabil via FNV)
  // ---------------------------------------------------------------------------
  Future<StoryResult> story({
    required List<String> entryIds,
    List<String>? topics,
    bool useServerIfAvailable = true,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    String? titleHint,
  }) async {
    try {
      final r = await ApiService.instance.story(
        entryIds: entryIds,
        topics: topics,
        useServerIfAvailable: useServerIfAvailable,
      );
      // Ersetze/vereinheitliche ID stabil:
      final stableId = _makeStoryId(r.title, r.body, entryIds);
      if (r.id == stableId) return r;
      return StoryResult(
        id: stableId,
        title: r.title,
        body: r.body,
        audioUrl: r.audioUrl,
      );
    } catch (_) {
      // Ruhiger Offline-/Fehler-Fallback
      final title = 'Ein stiller Blick';
      final body =
          'Innehalten ohne Druck. Ein kleiner realer Schritt wird sichtbar. Zeit hat keine Eile.';
      return StoryResult(
        id: _makeStoryId(title, body, entryIds),
        title: title,
        body: body,
        audioUrl: null,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Journey — normalisiert auf leichtes Json (entryIds-Signatur beibehalten)
  // ---------------------------------------------------------------------------
  Future<Json> journey({
    required List<String> entryIds,
    String tz = 'Europe/Zurich',
    String horizon = '7d',
    String locale = 'de',
  }) async {
    Map<String, dynamic> res;

    // Versuche dynamisch (falls ApiService künftig eine entryIds-Variante hat)
    try {
      final dyn = ApiService.instance as dynamic;
      res = await dyn.journey?.call(
            entryIds: entryIds,
            tz: tz,
            horizon: horizon,
            locale: locale,
          ) ??
          <String, dynamic>{};
      if (res.isEmpty) {
        res = await dyn.journey?.call(
              entryIds: entryIds,
              tz: tz,
              horizon: horizon,
            ) ??
            <String, dynamic>{};
      }
    } catch (_) {
      res = const <String, dynamic>{};
    }

    if (res.isEmpty) {
      return <String, dynamic>{
        'insights': const <String>[
          'Kleine Schwankungen sind normal – dein Tempo darf ruhig bleiben.',
        ],
        'question': 'Was nimmst du aus den letzten Tagen am ehesten mit?',
        'language': locale,
        'meta': const <String, dynamic>{'engine': 'journey'},
      };
    }

    return _normalizeJourney(res, locale: locale);
  }

  // ===========================================================================
  // 2) NORMALIZED-API (Convenience) — UI-freundliche Jsons
  // ===========================================================================

  Future<Json> startSession({
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    Map<String, dynamic>? clientContext,
    dynamic memories,
    bool? memoryConsent, // nullable
    UserAction? userAction,
    Map<String, dynamic>? meta,
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
    dynamic memories,
    bool? memoryConsent, // nullable
    Map<String, dynamic>? clientContext,
    UserAction? userAction,
    Map<String, dynamic>? meta,
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

  /// @deprecated: Bitte `nextTurnFull` mit HistoryTurn verwenden.
  Future<Json> reflectNormalized({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories,
    bool? memoryConsent, // nullable
    Map<String, dynamic>? clientContext,
    UserAction? userAction,
    Map<String, dynamic>? meta,
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

  Future<Json> nextTurnNormalized({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories,
    bool? memoryConsent, // nullable
    Map<String, dynamic>? clientContext,
    UserAction? userAction,
    Map<String, dynamic>? meta,
  }) async {
    // Normalized-Variante bleibt auf Map-History für abwärtskompatible Call-Sites.
    final t = await nextTurnFull(
      session: session,
      text: text,
      locale: locale,
      tz: tz,
      // Falls hier noch Map-History verwendet wird, heben wir sie unverändert durch:
      history: _mapsToHistoryTurns(history),
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
    Map<String, dynamic>? meta,
  }) async {
    final t = await nextTurnAction(
      session: session,
      action: action,
      locale: locale,
      tz: tz,
      meta: meta,
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

  // ===========================================================================
  // Memory-Helpers (UI only)
  // ===========================================================================
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
      bool matchesHint(String s) =>
          hint.isEmpty ? true : s.toLowerCase().contains(hint);

      for (final it in items) {
        final t = topicOf(it).trim();
        if (t.isEmpty || !matchesHint(t)) continue;
        final key = t.toLowerCase();
        if (!out.any((e) => e.toLowerCase() == key)) out.add(t);
        if (out.length >= limit) break;
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

  // ===========================================================================
  // Normalisierung / Helfer
  // ===========================================================================

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
        'mood_intro': {'text': (moodIntro['text'] ?? '').toString()},
        'hope_reply': (closure['hope_reply'] ?? '').toString(),
        'closure_prompt': (closure['closure_prompt'] ?? '').toString(),
      },
    };
  }

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

  List<String> _sanitizeAnswerHelpers(List<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final e in raw) {
      var x = e.trim();
      if (x.isEmpty) continue;
      // leichte Säuberung (keine Generierung)
      x = x.replaceAll(RegExp(r'^[0-9]+[.)]\s+'), '');
      x = x.replaceAll(RegExp(r'^[\u2013\-\u2022\s]+'), '');
      x = x.replaceAll(RegExp('^[„“"\'»«]+'), '');
      x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
      final key = x.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(x);
      if (out.length >= 3) break;
    }
    return out;
  }

  String _forInsert(String s) {
    var x = s.trim();
    x = x.replaceAll(RegExp(r'\s*[:：]\s*$'), '');
    x = x.replaceAll(RegExp(r'[…\u2026]+$'), '');
    x = x.replaceAll(RegExp(r'\s*[?!.\u2026]+$'), '');
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  Json _turnToJson(ReflectionTurn t) {
    final ReflectionFlow flow =
        t.flow ?? const ReflectionFlow(recommendEnd: false, suggestBreak: false);

    final flowJson = flow.toJson();
    final sessMap = t.session.toJson();
    final threadId = (sessMap['thread_id'] ?? sessMap['id'] ?? '').toString();
    final int round = _safeRoundFromSession(t.session);

    final map = <String, dynamic>{
      'session': sessMap,
      'flow': {
        ...flowJson,
        'mood_prompt': flow.moodPrompt == true || flow.recommendEnd == true,
        'recommend_end': flow.recommendEnd == true,
      },
      'risk_level': switch (t.riskFlag) {
        'crisis' => 'high',
        'support' => 'mild',
        _ => 'none',
      },
      'risk': (t.riskFlag == 'crisis' || t.riskFlag == 'support'),
      'disclaimer': kFooterDisclaimer,
      // S3.3: Convenience
      'round_count': round,
      'thread_id': threadId,
    };

    // Mirror säubern
    final mirror = (t.mirror ?? '').trim();
    if (mirror.isNotEmpty && !mirror.endsWith('?')) {
      final cleaned = _cleanMirror(mirror);
      if (cleaned != null && cleaned.isNotEmpty) {
        map['mirror'] = cleaned;
      }
    }

    // Frage nur anzeigen, wenn kein Mood-Prompt
    final ask = (t.primaryQuestion ?? '').trim();
    final shouldPromptMood =
        (map['flow']['mood_prompt'] == true) || (map['flow']['recommend_end'] == true);
    if (ask.isNotEmpty && !shouldPromptMood) {
      map['question'] = ask.endsWith('?') ? ask : '$ask?';
    }

    // Chips 1:1 (max 3), ohne lokale Defaults
    final ah = _sanitizeAnswerHelpers(t.answerHelpers);
    if (ah.isNotEmpty) {
      map['answer_helpers'] = ah;
      map['answer_helpers_insert'] = ah.map(_forInsert).toList(growable: false);
    }

    if (t.outputText.trim().isNotEmpty && t.outputText != ApiService.errorHint) {
      map['output_text'] = t.outputText;
    }
    if (t.talk.isNotEmpty) map['talk'] = t.talk;
    if ((t.smalltalkReply ?? '').trim().isNotEmpty) {
      map['smalltalk_reply'] = t.smalltalkReply!.trim();
    }
    if (t.tags.isNotEmpty) map['tags'] = t.tags;
    if (t.context.isNotEmpty) map['context'] = t.context;

    final hs = (t.helperSuggestion ?? '').trim();
    if (hs.isNotEmpty) map['helper_suggestion'] = hs;

    if (t.analysis != null) map['analysis'] = t.analysis!.toJson();
    if (t.topicSuggestions.isNotEmpty) {
      map['topic_suggestions'] = t.topicSuggestions;
    }

    // UI-Hinweise für Chips
    final sturn = (sessMap['turn_index'] ?? sessMap['turn'] ?? 0).toString();
    final seed = ah.join('|');
    final chipSetId = '$threadId:$sturn:${_fnv1a32(seed).toRadixString(16)}';

    map['ui'] = {
      'chips': {
        'insert_only': true,
        'auto_send': false,
        'persist_until': 'user_interaction',
        'place': 'composer_only',
        'type': _inferChipType(t.primaryQuestion, t.tags),
        'set_id': chipSetId,
        'reset_suggestion': shouldPromptMood,
      },
    };

    // insight_score bevorzugt aus TurnAnalysis
    final double? insightFromAnalysis = t.analysis?.insightScore;
    final dynamic maybeInsightInFlow = flowJson['insight_score'];
    if (insightFromAnalysis != null) {
      map['insight_score'] = insightFromAnalysis;
    } else if (maybeInsightInFlow is num) {
      map['insight_score'] = maybeInsightInFlow;
    }

    return map;
  }

  // Mirror-Cleaner
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

  // ===========================================================================
  // S3.3 — Meta/Session Helpers
  // ===========================================================================
  int _safeRoundFromSession(ReflectionSession? s) {
    if (s == null) return 0;
    try {
      final j = s.toJson();
      final v = j['turn_index'] ?? j['turn'] ?? 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Map<String, dynamic> _sessionHintMap(ReflectionSession? s) {
    if (s == null) return const {'turn_index': 0};
    try {
      final j = s.toJson();
      return {
        'thread_id': (j['thread_id'] ?? j['id'] ?? '').toString(),
        'id': (j['id'] ?? j['thread_id'] ?? '').toString(),
        'turn_index': j['turn_index'] ?? j['turn'] ?? 0,
      };
    } catch (_) {
      return const {'turn_index': 0};
    }
  }

  Map<String, dynamic>? _attachIntroAndSessionMeta(
      Map<String, dynamic>? meta, ReflectionSession? session) {
    final round = _safeRoundFromSession(session);
    final out = <String, dynamic>{};
    if (meta != null) {
      // defensive copy
      out.addAll(Map<String, dynamic>.from(meta));
    }
    // intro.round_count (autoritativer Wert)
    final intro = Map<String, dynamic>.from(
        (out['intro'] is Map ? out['intro'] as Map : const <String, dynamic>{}));
    intro['round_count'] = round;
    out['intro'] = intro;

    // session_hint (thread/id/turn)
    out['session_hint'] = _sessionHintMap(session);

    return out;
  }

  // ---------------------------------------------------------------------------
  // Consent/Memory Helpers
  // ---------------------------------------------------------------------------

  /// Setzt bei aktivem Consent das Flag meta.flags.client_memory = true.
  Map<String, dynamic>? _withClientMemoryFlag(
      Map<String, dynamic>? meta, bool consent) {
    if (!consent) return meta;
    final out =
        meta != null ? Map<String, dynamic>.from(meta) : <String, dynamic>{};
    final flags = Map<String, dynamic>.from(
        out['flags'] is Map ? out['flags'] as Map : const <String, dynamic>{});
    flags['client_memory'] = true;
    out['flags'] = flags;
    return out;
  }

  /// Bereitet Memories für den Call auf:
  /// - Wenn kein Consent → null (nichts senden).
  /// - Merge vorhandener Memories (Map/toJson).
  /// - Falls leer: kleine Client-Memories vom MemoryService.
  /// - Name-Injection aus userText (wenn erkennbar).
  Future<Map<String, dynamic>?> _prepareMemories({
    required dynamic incoming,
    required bool consent,
    String? userText,
  }) async {
    if (!consent) return null;

    final Map<String, dynamic> out = <String, dynamic>{};

    void mergeIn(dynamic src) {
      if (src == null) return;
      if (src is Map) {
        out.addAll(Map<String, dynamic>.from(src));
        return;
      }
      try {
        final m = (src as dynamic).toJson?.call();
        if (m is Map) out.addAll(Map<String, dynamic>.from(m));
      } catch (_) {/* ignore */}
    }

    mergeIn(incoming);

    // Leichte Memories als Fallback, wenn noch leer
    if (out.isEmpty) {
      try {
        final built = await mem.MemoryService.instance
            .buildContextMemories(consent: true);
        if (built is Map<String, dynamic>) {
          out.addAll(built);
        }
      } catch (_) {/* ignore */}
    }

    // Name-Injection
    if (userText != null && userText.trim().isNotEmpty) {
      final name = _extractDeclaredName(userText);
      if (name != null && name.trim().isNotEmpty) {
        final id = Map<String, dynamic>.from(
            out['identity'] is Map ? out['identity'] as Map : const {});
        id['name'] = name.trim();
        out['identity'] = id;
      }
    }

    return out.isEmpty ? null : out;
  }

  /// Extrahiert deklarierte Namen aus deutschen Mustern.
  /// Robust gegen einfache Satzzeichen, erlaubt 1–3 Wörter.
  String? _extractDeclaredName(String text) {
    final t = text.trim();

    // Häufige Phrasen: ich heiße | ich heisse | mein Name ist | ich bin
    final patterns = <RegExp>[
      RegExp(
          r'\b(?:ich\s+hei(?:s|ß)e|mein\s+name\s+ist|ich\s+bin)\s+([A-ZÄÖÜ][a-zäöüß]+(?:\s+[A-ZÄÖÜ][a-zäöüß]+){0,2}|[a-zäöüß]+(?:\s+[a-zäöüß]+){0,2})\b'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(t);
      if (m != null && m.groupCount >= 1) {
        var cand = (m.group(1) ?? '').trim();
        // Satzzeichen/Anhänge säubern
        cand = cand.replaceAll(RegExp(r'[.,;:!?]+$'), '').trim();

        // Simple Stopliste (vermeide „ich bin müde/traurig/krank“
        const stops = {
          'müde',
          'traurig',
          'glücklich',
          'wütend',
          'krank',
          'zuhause',
          'unterwegs',
          'ok',
          'okay'
        };
        if (stops.contains(cand.toLowerCase())) continue;

        // Name auf Wortgrenzen begrenzen (max 3 Wörter)
        final parts =
            cand.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
        if (parts.isEmpty) continue;
        if (parts.length > 3) {
          cand = parts.take(3).join(' ');
        }
        // Minimal-Heuristik: erstes Wort ≥ 2 Zeichen
        if (parts.first.length < 2) continue;

        return cand;
      }
    }
    return null;
  }

  // ===========================================================================
  // History Mapping
  // ===========================================================================
  /// Verlustfreies Mapping von HistoryTurn → {role, content} für das API.
  List<Map<String, String>>? _historyToMessages(List<HistoryTurn>? history) {
    if (history == null) return null;
    final out = <Map<String, String>>[];
    for (final h in history) {
      try {
        // Bevorzugt typisierte Felder
        final role = h.role.trim();
        final text = h.text.trim();
        if (role.isEmpty && text.isEmpty) continue;
        out.add({'role': role, 'content': text});
      } catch (_) {
        // Dynamische Fallbacks (tolerant)
        try {
          final dyn = h as dynamic;
          final role = (dyn.role ?? dyn['role'] ?? '').toString().trim();
          final text = (dyn.text ??
                  dyn['text'] ??
                  dyn.content ??
                  dyn['content'] ??
                  '')
              .toString()
              .trim();
          if (role.isEmpty && text.isEmpty) continue;
          out.add({'role': role, 'content': text});
        } catch (_) {
          continue;
        }
      }
    }
    return out;
  }

  /// Für Normalized-Fallbacks (alte Call-Sites mit Map-History).
  List<HistoryTurn>? _mapsToHistoryTurns(List<Map<String, String>>? maps) {
    if (maps == null) return null;
    return maps.map((m) {
      final role = (m['role'] ?? '').toString();
      final content = (m['content'] ?? m['text'] ?? '').toString();
      return HistoryTurn(role: role, text: content);
    }).toList();
  }
}

// -----------------------------------------------------------------------------
// Hash/IDs & Normalizer
// -----------------------------------------------------------------------------
int _fnv1a32(String s) {
  const int FNV_PRIME = 0x01000193;
  int hash = 0x811C9DC5;
  for (final cu in s.codeUnits) {
    hash ^= cu;
    hash = (hash * FNV_PRIME) & 0xFFFFFFFF;
  }
  return hash;
}

String _makeStoryId(String title, String body, List<String> entryIds) {
  final seed = '$title|$body|${entryIds.join(",")}';
  final h = _fnv1a32(seed).toRadixString(16);
  return 'story-$h';
}

// -----------------------------------------------------------------------------
// Story/Journey Normalizer
// -----------------------------------------------------------------------------
Map<String, dynamic> _normalizeStoryMap(Map<String, dynamic> src) {
  String _s(dynamic v) => (v ?? '').toString().trim();
  List<String> _ls(dynamic v) => (v is List)
      ? v
          .where((e) => e != null)
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .cast<String>()
          .toList()
      : <String>[];

  final title =
      _s(src['title']).isNotEmpty ? _s(src['title']) : 'Ein stiller Blick';
  final rawBody =
      _s(src['body']).isNotEmpty ? _s(src['body']) : _s(src['story']);
  final body = rawBody.isNotEmpty
      ? rawBody
      : 'Innehalten ohne Druck. Ein kleiner realer Schritt wird sichtbar. Zeit hat keine Eile';

  final themes = _ls(src['themes']);
  final safety = _s(src['safety_notes']);

  return <String, dynamic>{
    'title': title,
    'body': body,
    'themes': themes,
    'safety_notes': safety,
    'meta': src['meta'] is Map<String, dynamic>
        ? src['meta']
        : const <String, dynamic>{'engine': 'story'},
    'output_text': body,
  };
}

Json _normalizeJourney(Map<String, dynamic> src, {String locale = 'de'}) {
  String _s(dynamic v) => (v ?? '').toString().trim();
  List<String> _ls(dynamic v) => (v is List)
      ? v
          .where((e) => e != null)
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .cast<String>()
          .toList()
      : <String>[];

  final insights = _ls(src['insights']);
  final q = _s(src['question']).isNotEmpty
      ? _s(src['question'])
      : 'Was nimmst du aus den letzten Tagen am ehesten mit?';

  return <String, dynamic>{
    'insights': insights.isNotEmpty
        ? insights
        : const <String>[
            'Kleine Schwankungen sind normal – dein Tempo darf ruhig bleiben.'
          ],
    'question': q,
    'language': _s(src['language']).isNotEmpty ? _s(src['language']) : locale,
    'meta': src['meta'] is Map<String, dynamic>
        ? src['meta']
        : const <String, dynamic>{'engine': 'journey'},
  };
}
