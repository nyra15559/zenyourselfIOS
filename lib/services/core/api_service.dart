// lib/services/core/api_service.dart
//
// ZenYourself — Core ApiService (server+offline, Samfring optional)
// -----------------------------------------------------------------------------
// - Einheitlicher HTTP/Retries/Fallbacks (_tryEndpoints / _postMaybe)
// - Zentrale Payload-Builder (_buildSessionMap / _basePayload)
// - Memory-Hooks & Byte-Kontext (best-effort, ohne await)
// - Light Contact-Tints (Header + Payload), Samfring=optional
// - Out-Soft-Gate: kleiner Start-Blocker; blockiert NIE Offline-Flows
// - Parser & Offline-Heuristiken bleiben erhalten (kompatibel)
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

// Wichtig: DTOs importieren – explizit nur die genutzten Typen
import '../guidance/dtos.dart'
    show
        AnalyzeResult,
        Analysis,
        JourneyEntry,
        JourneyInsights,
        MoodResponse,
        ReflectionFlow,
        ReflectionSession,
        ReflectionTurn,
        StoryResult,
        StructuredThoughtResult,
        IfEmptyX;

// ReflectionEntry & Co; hier VERMEIDEN wir den Typ Analysis aus diesem File:
import '../../data/reflection_entry.dart' as re hide Analysis;

import '../../models/question.dart';

// **Memory-Layer (Backend-only)**
import '../../core/memory/memory_service.dart';

typedef HttpInvoker = Future<Map<String, dynamic>> Function(
  String path,
  Map<String, dynamic> body,
);

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final _rand = Random.secure();
  final _uuid = const Uuid();

  HttpInvoker? _http;
  String? _baseUrl;
  Duration _timeout = const Duration(seconds: 25);

  // Outbound Soft-Gate (startet geschlossen, öffnet sich nach kurzem Delay)
  bool _outGateOpen = true; // standardmäßig offen – wird durch configure* kurz geschlossen
  bool _outGatePrimed = false;

  // Branding
  static const String _brand = 'ZenYourself';
  static const String _channel = 'app';
  static const String _samfring = 'optional';
  static const String loadingHint = '$_brand zählt die Blümchen …';

  // **Fester Fehlertext (fix)**
  static const String errorHint =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';

  // ---------------- Config ----------------
  void configureHttp({HttpInvoker? invoker, String? baseUrl, Duration? timeout}) {
    _http = invoker;
    if (baseUrl != null && baseUrl.trim().isNotEmpty) {
      _baseUrl = _normalizeBase(baseUrl);
    }
    if (timeout != null) _timeout = timeout;

    _primeMemory();       // ohne await
    _primeOutSoftGate();  // kleiner Start-Blocker (nicht-blockierend für Offline)
  }

  void configureForWorker({
    required String baseUrl,
    String? appToken,
    Duration timeout = const Duration(seconds: 25),
  }) {
    _baseUrl = _normalizeBase(baseUrl);
    _timeout = timeout;

    _primeMemory();       // ohne await
    _primeOutSoftGate();  // kleiner Start-Blocker

    // HttpInvoker-Adapter (light headers + Payload-Anreicherung)
    _http = (String path, Map<String, dynamic> body) async {
      final uri = _join(_baseUrl!, path);
      final headers = <String, String>{
        if (appToken != null && appToken.trim().isNotEmpty)
          'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept':
            'application/json, application/problem+json;q=0.95, text/plain;q=0.9, */*;q=0.8',
        // Light Contact-Tints + Samfring
        'X-App-Brand': _brand,
        'X-App-Channel': _channel,
        'X-Samfring': _samfring,
        // Out-Soft-Gate Anzeige (nur informativ)
        'X-Out-Gate': _outGateOpen ? 'open' : 'warmup',
      };

      // Payload sanft anreichern (falls Caller es nicht bereits gemacht hat)
      final enriched = Map<String, dynamic>.from(body);
      enriched.putIfAbsent('contact_tins', () => {
            'brand': _brand,
            'channel': _channel,
            'samfring': _samfring,
            'locale': (body['locale'] ?? 'de').toString(),
            'tz': (body['tz'] ?? 'Europe/Zurich').toString(),
          });

      // Byte-Kontext best-effort (ohne await)
      _appendByteContext(enriched);

      // kleiner Start-Blocker, aber NUR für Outbound
      if (!_outGateOpen && !_isHealthPath(path)) {
        final jitter = 90 + _rand.nextInt(90);
        await Future.delayed(Duration(milliseconds: jitter));
      }

      final res =
          await http.post(uri, headers: headers, body: jsonEncode(enriched)).timeout(_timeout);

      if (res.statusCode >= 400) {
        throw Exception('Worker ${res.statusCode}: ${res.body}');
      }

      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('json')) {
        try {
          final parsed = jsonDecode(res.body);
          if (parsed is Map<String, dynamic>) return parsed;
          return <String, dynamic>{'output_text': parsed.toString()};
        } catch (_) {
          return <String, dynamic>{'output_text': _decodeBody(res)};
        }
      }
      return <String, dynamic>{'output_text': _decodeBody(res)};
    };
  }

  void _primeOutSoftGate() {
    if (_outGatePrimed) return;
    _outGatePrimed = true;
    _outGateOpen = false;
    unawaited(() async {
      // sehr kurzer Warmup + Health-Ping (best-effort)
      final ms = 120 + _rand.nextInt(80);
      await Future.delayed(Duration(milliseconds: ms));
      unawaited(healthCheck());
      _outGateOpen = true;
    }());
  }

  // Memory-Service sanft berühren (init ohne await; falls vorhanden)
  void _primeMemory() {
    try {
      // Zugriff auf Singleton kann bereits initialisieren
      final _ = MemoryService.instance;
      // optional: vorhandene Warmup-Methoden nicht-blockierend aufrufen
      // (alles dynamic + try/catch → niemals Build/Runtime blockieren)
      // ignore: unused_local_variable
      dynamic dyn = _;
      unawaited(Future<void>(() async {
        try {
          // gängige Namen – falls nicht vorhanden → NoSuchMethod -> ignored
          // ignore: avoid_dynamic_calls
          await (dyn.warmup?.call());
        } catch (_) {}
        try {
          // ignore: avoid_dynamic_calls
          dyn.preload?.call();
        } catch (_) {}
      }));
    } catch (_) {
      // niemals blockieren
    }
  }

  static bool _isHealthPath(String path) {
    final p = path.trim().toLowerCase();
    return p == '/health' || p.endsWith('/health');
  }

  static String _normalizeBase(String base) {
    var b = base.trim();
    b = b.replaceAll(RegExp(r'/*$'), '');
    return b.isEmpty ? base : b;
  }

  static Uri _join(String base, String path) {
    final p = path.trim().isEmpty ? '' : (path.startsWith('/') ? path : '/$path');
    return Uri.parse('$base$p');
  }

  static String _decodeBody(http.Response res) {
    try {
      return utf8.decode(res.bodyBytes);
    } catch (_) {
      return res.body.toString();
    }
  }

  // ---------------- Health ----------------
  Future<bool> healthCheck() async {
    final base = _baseUrl;
    if (base == null || base.trim().isEmpty) return false;
    try {
      final uri = _join(base, '/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode >= 400) return false;
      final body = res.body.trim();
      if (body.toLowerCase() == 'ok') return true;
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('json')) {
        final json = jsonDecode(body);
        if (json is Map &&
            (json['ok'] == true ||
                json['status']?.toString().toLowerCase() == 'ok')) {
          return true;
        }
      }
      return true; // tolerant
    } catch (_) {
      return false;
    }
  }

  // =======================================================================
  //  SESSION-API
  // =======================================================================
  Future<ReflectionTurn> startSession({
    String? text,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
  }) async {
    final input = (text ?? userText ?? '').trim();
    final session = ReflectionSession(
      threadId: _uuid.v4(),
      turnIndex: 0,
      maxTurns: max(2, min(6, maxTurns)),
    );
    return _reflectStep(
      text: input,
      session: session,
      locale: locale,
      tz: tz,
      history: history ?? const [],
    );
  }

  Future<ReflectionTurn> startSessionFull({
    required String text,
    ReflectionSession? session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
  }) async {
    final s = session ??
        ReflectionSession(
          threadId: _uuid.v4(),
          turnIndex: 0,
          maxTurns: max(2, min(6, maxTurns)),
        );
    return _reflectFullStep(
      text: text.trim(),
      session: s,
      locale: locale,
      tz: tz,
      history: history ?? const [],
    );
  }

  Future<ReflectionTurn> continueSession({
    required ReflectionSession session,
    String? text,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
  }) async {
    final input = (text ?? userText ?? '').trim();
    final next = session.copyWith(turnIndex: session.turnIndex + 1);
    return _reflectStep(
      text: input,
      session: next,
      locale: locale,
      tz: tz,
      history: history ?? const [],
    );
  }

  Future<ReflectionTurn> nextTurnFull({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
  }) async {
    if (_http == null) return _errorTurn(session);
    final next = session.copyWith(turnIndex: session.turnIndex + 1);

    final payload = _basePayload(
      text: text.trim(),
      locale: locale,
      tz: tz,
      session: next,
      messages: history ?? const [],
    );

    // Fallback-Reihenfolge beibehalten
    final json = await _tryEndpoints(
      endpoints: const ['/next_turn_full', '/reflect_full', '/reflect'],
      payload: payload,
    );

    if (json == null) return _errorTurn(next);
    return _turnFromReflectAny(json, next);
  }

  Future<ReflectionTurn> nextTurn({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
  }) =>
      continueSession(
        session: session,
        text: text,
        locale: locale,
        tz: tz,
        history: history,
      );

  Future<ReflectionSession> endSession(ReflectionSession s) async => s;

  // ---------------- closure_full ----------------
  Future<Map<String, dynamic>> closureFull({
    required ReflectionSession? session,
    required String answer,
    String locale = 'de',
    String tz = 'Europe/Zurich',
  }) async {
    if (_http == null) {
      return _closureFallback(session);
    }

    final payload = <String, dynamic>{
      'answer': answer.trim(),
      'text': answer.trim(), // kompatibel zu Workern, die "text" erwarten
      'locale': locale,
      'tz': tz,
      'session': session == null ? null : _buildSessionMap(session),
    };
    _appendMemoryHints(payload);
    _appendContactTints(payload, locale: locale, tz: tz);
    _appendByteContext(payload);

    final json =
        await _postMaybe('/closure_full', payload, saveSource: 'closure_full');
    return json ?? _closureFallback(session);
  }

  Future<ReflectionTurn> _reflectStep({
    required String text,
    required ReflectionSession session,
    required String locale,
    required String tz,
    required List<Map<String, String>> history,
  }) async {
    if (_http == null) return _errorTurn(session);
    final payload = _basePayload(
      text: text,
      locale: locale,
      tz: tz,
      session: session,
      messages: history,
    );
    final json =
        await _tryEndpoints(endpoints: const ['/reflect'], payload: payload);
    if (json == null) return _errorTurn(session);
    return _turnFromReflectAny(json, session);
  }

  Future<ReflectionTurn> _reflectFullStep({
    required String text,
    required ReflectionSession session,
    required String locale,
    required String tz,
    required List<Map<String, String>> history,
  }) async {
    if (_http == null) return _errorTurn(session);
    final payload = _basePayload(
      text: text,
      locale: locale,
      tz: tz,
      session: session,
      messages: history,
    );
    final json = await _tryEndpoints(
      endpoints: const ['/reflect_full'],
      payload: payload,
    );
    if (json == null) return _errorTurn(session);
    return _turnFromReflectAny(json, session);
  }

  Future<ReflectionTurn> talk({
    required ReflectionSession session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    String? userText,
    List<Map<String, String>>? history,
  }) async {
    if (_http == null) {
      // Offline-Talk bleibt verfügbar (nicht blockieren)
      return ReflectionTurn(
        outputText: '',
        mirror: null,
        context: const [],
        followups: const [],
        answerHelpers: const [], // UI kann darauf hören
        helperSuggestion: null,
        flow: const ReflectionFlow(
          recommendEnd: false,
          suggestBreak: false,
          talkOnly: true,
          allowReflect: true,
        ),
        session: session,
        tags: const [],
        riskFlag: 'none',
        questions: const [],
        talk: const [
          'Das darf hier ganz in Ruhe Platz haben.',
          'Nimm dir einen Augenblick für das, was wichtig ist.'
        ],
      );
    }

    final payload = _basePayload(
      text: (userText ?? '').trim(),
      locale: locale,
      tz: tz,
      session: session,
      intent: 'talk',
      messages: history ?? const [],
    );

    try {
      final json = await _postMaybe('/reflect', payload, saveSource: 'reflect');
      if (json == null) throw Exception('no json');
      return _turnFromReflectJson(json, session);
    } catch (_) {
      // Sanfter Offline-Fallback (Out blockiert nie)
      return ReflectionTurn(
        outputText: '',
        mirror: null,
        context: const [],
        followups: const [],
        answerHelpers: const [],
        helperSuggestion: null,
        flow: const ReflectionFlow(
          recommendEnd: false,
          suggestBreak: false,
          talkOnly: true,
          allowReflect: true,
        ),
        session: session,
        tags: const [],
        riskFlag: 'none',
        questions: const [],
        talk: const ['Ich bin hier bei dir.'],
      );
    }
  }

  ReflectionTurn _errorTurn(ReflectionSession session) => ReflectionTurn(
        outputText: errorHint,
        mirror: null,
        context: const [],
        followups: const [],
        answerHelpers: const [],
        helperSuggestion: null,
        flow: const ReflectionFlow(recommendEnd: false, suggestBreak: false),
        session: session,
        tags: const [],
        riskFlag: 'none',
        questions: const [],
      );

  // =======================================================================
  //  analyze() → /reflect_full
  // =======================================================================
  Future<AnalyzeResult> analyze({
    required String mode, // 'voice'|'text'
    required String text,
    int? durationSec,
    List<int>? recentMoods,
    int? streak,
    bool useServerIfAvailable = true,
  }) async {
    if (_http == null) {
      const analysis = Analysis(
        sorc: null,
        levers: [],
        mirror: null,
        question: null,
        riskLevel: 'none',
      );
      return const AnalyzeResult(analysis: analysis, challenge: null);
    }

    final payload = <String, dynamic>{
      'text': text,
      'messages': [
        {'role': 'user', 'content': text}
      ],
      'locale': 'de',
      'tz': 'Europe/Zurich',
      'session': {'id': _uuid.v4(), 'turn': 0, 'max_turns': 3},
      if (durationSec != null) 'duration_sec': durationSec,
      if (recentMoods != null) 'recent_moods': recentMoods,
      if (streak != null) 'streak': streak,
      'mode': mode,
    };
    _appendMemoryHints(payload);
    _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
    _appendByteContext(payload);

    try {
      final json =
          await _postMaybe('/reflect_full', payload, saveSource: 'reflect_full');
      if (json == null) throw Exception('no json');

      final qsList = _parseStringList(
          json['questions'] ?? json['qs'] ?? json['multi_questions']);
      final joined = _normalizeQuestions(qsList);

      final rawPrimary = _extractPrimary(json).trim();
      final primary = joined.isNotEmpty ? joined : rawPrimary;

      final riskLevel = ((json['risk_level'] ?? json['risk'] ?? 'none')).toString();
      final mirrorRaw = (json['mirror'] ?? '').toString().trim();
      final String? mirror = mirrorRaw.isEmpty ? null : mirrorRaw;

      final analysis = Analysis(
        sorc: null,
        levers: const [],
        mirror: mirror,
        question: primary.isNotEmpty ? primary : errorHint,
        riskLevel: riskLevel,
      );

      return AnalyzeResult(analysis: analysis, challenge: null);
    } catch (_) {
      const analysis = Analysis(
        sorc: null,
        levers: [],
        mirror: null,
        question: errorHint,
        riskLevel: 'none',
      );
      return const AnalyzeResult(analysis: analysis, challenge: null);
    }
  }

  // =======================================================================
  //  Legacy-Kompat: aiReflect()
  // =======================================================================
  Future<ReflectionAIResult> aiReflect({
    required List<Map<String, String>> messages,
    String model = 'gpt-4.1',
  }) async {
    if (_http == null) {
      return const ReflectionAIResult(
        reflection: errorHint,
        depth: 'light',
        riskFlag: 'none',
        tags: <String>[],
      );
    }

    // Robust extrahieren: letzte User-Nachricht oder sonst letzte Nachricht
    String userText = '';
    final lastUser =
        messages.lastWhereOrNull((m) => (m['role'] ?? '') == 'user');
    if (lastUser != null && (lastUser['content'] ?? '').trim().isNotEmpty) {
      userText = lastUser['content']!.trim();
    } else if (messages.isNotEmpty &&
        (messages.last['content'] ?? '').trim().isNotEmpty) {
      userText = messages.last['content']!.trim();
    }

    final turn = await _reflectStep(
      text: userText,
      session:
          ReflectionSession(threadId: _uuid.v4(), turnIndex: 0, maxTurns: 3),
      locale: 'de',
      tz: 'Europe/Zurich',
      history: messages,
    );

    final depth = _estimateDepth(messages);
    final riskFlag = (turn.flow?.riskNotice != null) ? 'support' : 'none';

    return ReflectionAIResult(
      reflection: turn.outputText,
      depth: depth,
      riskFlag: riskFlag,
      tags: await suggestTags(turn.outputText),
    );
  }

  // =======================================================================
  //  mood() / story() / journey()
  // =======================================================================
  Future<MoodResponse> mood({
    required String entryId,
    required int icon,
    String? note,
    bool useServerIfAvailable = true,
  }) async {
    if (useServerIfAvailable && _http != null) {
      try {
        final payload = {
          'entry_id': entryId,
          'mood': {
            'icon': icon,
            if (note != null && note.trim().isNotEmpty) 'note': note,
          },
        };
        _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
        _appendByteContext(payload);
        await _postMaybe('/mood', payload);
      } catch (_) {/* ignore */}
    }
    return const MoodResponse(saved: true);
  }

  Future<StoryResult> story({
    required List<String> entryIds,
    List<String>? topics,
    bool useServerIfAvailable = true,
  }) async {
    if (_http != null && useServerIfAvailable) {
      const bases = [500, 1500, 3000];
      for (int i = 0; i < bases.length; i++) {
        try {
          final nowDate =
              DateTime.now().toUtc().toIso8601String().split('T').first;
          final mergedText = (topics != null && topics.isNotEmpty)
              ? topics.join(' · ')
              : (entryIds.isNotEmpty
                  ? 'Ausgewählte Einträge: ${entryIds.join(', ')}'
                  : '');

          final payload = <String, dynamic>{
            'entries': [
              {
                'date': nowDate,
                'text': mergedText,
                'mood': null,
                'tags': const <String>[]
              }
            ],
            'locale': 'de',
            'tz': 'Europe/Zurich',
          };
          _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
          _appendByteContext(payload);

          final json = await _postMaybe('/story', payload, saveSource: 'story')
              .timeout(_timeout);
          if (json == null) throw Exception('no json');

          final title = (json['title'] ?? 'Kurzgeschichte').toString();
          final body = (json['story'] ?? '').toString();
          if (body.trim().isEmpty) throw Exception('Leere Story erhalten');

          return StoryResult(
            id: 'story_${DateTime.now().millisecondsSinceEpoch}',
            title: title,
            body: body,
            audioUrl: null,
          );
        } catch (_) {
          if (i < bases.length - 1) {
            final jitter = _rand.nextInt(250);
            await Future.delayed(Duration(milliseconds: bases[i] + jitter));
            continue;
          }
        }
      }
    }
    return StoryResult(
      id: 'story_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Kurzgeschichte',
      body: errorHint,
      audioUrl: null,
    );
  }

  Future<JourneyInsights> journey({
    required List<JourneyEntry> entries,
    String horizon = '7d',
    bool useServerIfAvailable = true,
  }) async {
    if (_http != null && useServerIfAvailable) {
      try {
        final payload = <String, dynamic>{
          'entries': entries
              .map((e) {
                final red = _redactPII(e.text);
                final int end = red.length > 800 ? 800 : red.length;
                return {
                  'date': e.dateIso,
                  'mood': e.moodLabel ?? '',
                  'text': red.substring(0, end)
                };
              })
              .toList(growable: false),
          'horizon': horizon,
        };
        _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
        _appendByteContext(payload);

        final json =
            await _postMaybe('/journey', payload, saveSource: 'journey')
                .timeout(_timeout);
        if (json == null) throw Exception('no json');

        final insightsDyn = (json['insights'] as List?) ?? const [];
        final question = (json['question'] ?? '').toString();

        final insights = insightsDyn
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .take(6)
            .toList(growable: false);
        if (insights.isEmpty && question.isEmpty) {
          throw Exception('Leeres Journey-Result');
        }

        return JourneyInsights(
          insights: insights.isEmpty ? <String>[question] : insights,
          question: question.isNotEmpty
              ? question
              : (insights.isNotEmpty ? insights.first : loadingHint),
        );
      } catch (_) {/* fallback unten */}
    }

    return const JourneyInsights(
      insights: <String>['ZenYourself konnte keine Insights laden.'],
      question: loadingHint,
    );
  }

  // =======================================================================
  //  Lokal-Heuristiken / Utils
  // =======================================================================
  Future<StructuredThoughtResult> structureThoughts(String input,
      {bool useServerIfAvailable = true}) async {
    final raw = input.trim();
    await _delay(minMs: 220, maxMs: 360);
    final sanitized = _redactPII(raw);
    final lever = _pickLever(sanitized);

    final bullets = _bulletsFromText(sanitized, maxItems: 6);
    final core = _coreIdeaFrom(sanitized, bullets, lever);

    final emo = detectEmotionSync(sanitized);
    final score = classifyMoodSync(sanitized);
    final moodHint = _composeMood(emotion: emo, score: score);

    final nextSteps = _nextStepsForLever(lever);

    return StructuredThoughtResult(
      bullets: bullets,
      coreIdea: core.ifEmpty(() => _neatEllipsis(sanitized, 120)),
      moodHint: moodHint,
      nextSteps: nextSteps,
      source: 'offline',
    );
  }

  Future<Question> fetchGuidingQuestion(
      {String? contextText, bool followUp = false}) async {
    final ctx = (contextText ?? '').trim();

    if (_http != null) {
      try {
        final payload = {
          'text': ctx.isEmpty ? 'kurze Reflexion' : ctx,
          'locale': 'de',
          'tz': 'Europe/Zurich',
          'session': {'id': _uuid.v4(), 'turn': 0, 'max_turns': 1},
        };
        _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
        _appendByteContext(payload);

        final json = await _postMaybe('/reflect_full', payload, saveSource: 'reflect_full')
            .timeout(_timeout);

        if (json != null) {
          final primary = _extractPrimary(json).trim();
          if (primary.isNotEmpty) {
            final now = DateTime.now().toUtc();
            final qText = primary.endsWith('?') ? primary : '$primary?';
            return Question(
              id: 'q_${now.millisecondsSinceEpoch}_${qText.hashCode}',
              text: qText,
              isFollowUp: followUp,
              createdAt: now,
            );
          }
        }
      } catch (_) {/* offline fallback */}
    }

    final seeds = followUp
        ? const [
            'Magst du dort weitermachen, wo es gerade wichtig ist?',
            'Was war der kleinste hilfreiche Moment seit eben?',
            'Welcher Gedanke ist jetzt am lautesten – und welcher am leisesten?',
          ]
        : const [
            'Wenn du innehalten magst: Was ist dir gerade am wichtigsten?',
            'Worauf bist du heute sanft stolz?',
            'Was bräuchte jetzt ein wenig Raum?',
            'Welche Sorge oder Hoffnung meldet sich am stärksten?',
          ];

    final pick = seeds[_rand.nextInt(seeds.length)];
    final text = _personalize(pick.endsWith('?') ? pick : '$pick?', ctx);
    final now = DateTime.now().toUtc();
    return Question(
      id: 'q_${now.millisecondsSinceEpoch}_${text.hashCode}',
      text: text,
      isFollowUp: followUp,
      createdAt: now,
    );
  }

  Future<Question> fetchFollowUp({String? contextText}) =>
      fetchGuidingQuestion(contextText: contextText, followUp: true);

  Future<String> summarizeReflection(re.ReflectionEntry entry) async {
    final raw = _bestEffortContent(entry);
    if (raw.isEmpty) return '';
    final red = _redactPII(raw);
    final bullets = _bulletsFromText(red, maxItems: 3);
    final emo = detectEmotionSync(red);
    final mood = classifyMoodSync(red);
    final tail = _composeMood(emotion: emo, score: mood);
    final base = bullets.isNotEmpty ? bullets.first : _neatEllipsis(red, 140);
    return tail == null ? base : '$base — $tail';
  }

  Future<String?> detectEmotion(String text) async => detectEmotionSync(text);
  Future<int?> classifyMood(String text) async => classifyMoodSync(text);

  Future<List<String>> suggestTags(String text) async {
    final t = text.toLowerCase();
    final tags = <String>{};

    void maybe(String tag, List<String> keys) {
      if (_any(t, keys)) tags.add(tag);
    }

    maybe('Arbeit', ['arbeit', 'job', 'chef', 'meeting', 'projekt', 'kolleg']);
    maybe('Beziehung', ['partner', 'bezieh', 'freund', 'famil']);
    maybe('Schlaf', ['schlaf', 'müde', 'insomn', 'träum']);
    maybe('Stress', ['stress', 'überforder', 'nervös', 'druck']);
    maybe('Angst', ['angst', 'sorge', 'panik']);
    maybe('Wut', ['wut', 'ärger', 'sauer', 'genervt']);
    maybe('Traurigkeit', ['traurig', 'weinen', 'leer', 'melanch']);
    maybe('Dankbarkeit', ['dankbar', 'wertschätz', 'zufrieden', 'stolz']);
    maybe('Produktivität', ['aufschieb', 'prokrast', 'fokus', 'starten']);
    maybe('Gesundheit', ['körper', 'sport', 'beweg', 'schmerz']);

    if (tags.isEmpty) {
      final words = t
          .replaceAll(RegExp(r'[^a-zäöüß\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 5)
          .take(3)
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .toList();
      tags.addAll(words);
    }

    return tags.take(6).toList(growable: false);
  }

  // ---------- Offline-Heuristiken ----------
  String? detectEmotionSync(String text) {
    final t = text.toLowerCase();
    if (_any(t, ['wut', 'zorn', 'ärger', 'sauer', 'genervt'])) return 'wütend';
    if (_any(t, ['traurig', 'trauer', 'leer', 'niedergeschlagen', 'weinen'])) {
      return 'traurig';
    }
    if (_any(t, ['stress', 'gestresst', 'nervös', 'überforder', 'panik'])) {
      return 'gestresst';
    }
    if (_any(t, ['ruhig', 'entspannt', 'gelassen', 'friedlich'])) return 'ruhig';
    if (_any(t, ['glücklich', 'freu', 'dankbar', 'zufrieden', 'stolz'])) {
      return 'glücklich';
    }
    return null;
  }

  int classifyMoodSync(String text) {
    final t = text.toLowerCase();
    int score = 2; // neutral
    if (_any(t, ['wut', 'zorn', 'ärger', 'sauer'])) score -= 2;
    if (_any(t, ['traurig', 'weinen', 'leer'])) score -= 2;
    if (_any(t, ['stress', 'gestresst', 'überforder'])) score -= 1;
    if (_any(t, ['angst', 'sorge', 'panik'])) score -= 1;

    if (_any(t, ['ruhig', 'entspannt', 'gelassen'])) score += 1;
    if (_any(t, ['glücklich', 'freu', 'dankbar', 'zufrieden', 'stolz'])) {
      score += 2;
    }

    return score.clamp(0, 4);
  }

  Future<void> _delay({int minMs = 300, int maxMs = 420}) async {
    final span = maxMs - minMs;
    final jitter = span > 0 ? minMs + _rand.nextInt(span) : minMs;
    await Future.delayed(Duration(milliseconds: jitter));
  }

  bool _any(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  String _personalize(String q, String? ctx) {
    final raw = (ctx ?? '').trim();
    if (raw.isEmpty) return q;
    final firstLine =
        raw.split('\n').firstWhereOrNull((e) => e.trim().isNotEmpty) ?? raw;
    final sanitized = _redactPII(firstLine.trim());
    if (sanitized.isEmpty) return q;
    final hint = _neatEllipsis(sanitized, 90);
    if (RegExp(r'^\[[^\]]]+\]$').hasMatch(hint)) return q;
    return '$q\n\n(Bezug: $hint)';
  }

  String _redactPII(String input) {
    var s = input;
    final email = RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
        caseSensitive: false);
    s = s.replaceAll(email, '[E-Mail]');
    final phone = RegExp(r'(\+?\d[\d\s\-\(\)]{6,}\d)');
    s = s.replaceAll(phone, '[Telefon]');
    final url = RegExp(r'(https?:\/\/|www\.)\S+', caseSensitive: false);
    s = s.replaceAll(url, '[Link]');
    final iban = RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b');
    s = s.replaceAll(iban, '[IBAN]');
    final card = RegExp(r'\b(?:\d[ \-]*?){13,19}\b');
    s = s.replaceAll(card, '[Karte]');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  String _bestEffortContent(re.ReflectionEntry entry) {
    dynamic d = entry;
    String pick(dynamic Function(dynamic x) getter) {
      try {
        final v = getter(d);
        if (v is String && v.trim().isNotEmpty) return v.trim();
      } catch (_) {}
      return '';
    }
    return pick((x) => x.content)
        .ifEmpty(() => pick((x) => x.answer?.content))
        .ifEmpty(() => pick((x) => x.aiSummary))
        .ifEmpty(() => pick((x) => x.moodNote))
        .ifEmpty(() => '');
  }

  static String _neatEllipsis(String s, int maxChars) {
    if (s.length <= maxChars) return s;
    final cut = s.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    final safe = lastSpace > 40 ? cut.substring(0, lastSpace) : cut;
    return '${safe.trim()}…';
  }

  String _pickLever(String text) {
    final t = text.toLowerCase();
    if (_any(t, const ['gedanke', 'glaubens', 'sollte', 'muss'])) return 'Gedanken';
    if (_any(t, const ['gefüh', 'angst', 'wut', 'traur', 'überforder'])) {
      return 'Gefühle';
    }
    if (_any(t, const ['körper', 'schlaf', 'angespannt', 'atem', 'müde'])) {
      return 'Körper';
    }
    if (_any(t, const ['aufschieb', 'scroll', 'reaktion', 'streit', 'vermeid'])) {
      return 'Verhalten';
    }
    if (_any(t, const ['arbeit', 'chef', 'famil', 'uni', 'termin', 'druck'])) {
      return 'Kontext';
    }
    return 'Gedanken';
  }

  List<String> _bulletsFromText(String text, {int maxItems = 6}) {
    if (text.isEmpty) return const <String>[];
    final raw = text.replaceAll('\r', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = raw
        .split(RegExp(r'[\.!\?\n;:]+'))
        .map((s) => s.trim())
        .where((s) => s.length >= 3)
        .toList();
    final seen = <String>{};
    final out = <String>[];
    for (final p in parts) {
      final normalized = p.toLowerCase();
      if (seen.contains(normalized)) continue;
      seen.add(normalized);
      out.add(_neatEllipsis(p, 140));
      if (out.length >= maxItems) break;
    }
    if (out.isEmpty) out.add(_neatEllipsis(text, 140));
    return out;
  }

  String _coreIdeaFrom(String fullText, List<String> bullets, String lever) {
    if (bullets.isEmpty) return '';
    int scoreOf(String s) {
      int score = 0;
      final l = s.length;
      if (l >= 40 && l <= 140) score += 3;
      if (s.contains('?')) score += 2;
      if (s.contains('!')) score += 1;
      final t = s.toLowerCase();
      if (lever == 'Gedanken' &&
          _any(t, const ['sollte', 'muss', 'immer', 'nie'])) {
        score += 2;
      }
      if (lever == 'Gefühle' &&
          _any(t, const ['fühl', 'angst', 'wut', 'traur'])) {
        score += 2;
      }
      if (lever == 'Körper' &&
          _any(t, const ['körper', 'müde', 'schlaf', 'atem'])) {
        score += 2;
      }
      if (lever == 'Verhalten' &&
          _any(t, const ['aufschieb', 'start', 'beginnen', 'klein'])) {
        score += 2;
      }
      if (lever == 'Kontext' &&
          _any(t, const ['arbeit', 'termin', 'chef', 'famil'])) {
        score += 2;
      }
      return score;
    }
    bullets.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
    return bullets.first;
  }

  String? _composeMood({String? emotion, int? score}) {
    final String? label = (score == null) ? null : _labelFromScore(score);
    if (emotion == null && label == null) return null;
    if (emotion != null && label != null) return '$emotion · $label';
    return emotion ?? label;
  }

  String? _labelFromScore(int score) {
    switch (score) {
      case 0:
        return 'Sehr schlecht';
      case 1:
        return 'Schlecht';
      case 2:
        return 'Neutral';
      case 3:
        return 'Gut';
      case 4:
        return 'Sehr gut';
      default:
        return null;
    }
  }

  // ---------------- Reflect-Parsing ----------------
  ReflectionTurn _turnFromReflectAny(
      Map<String, dynamic> any, ReflectionSession session) {
    if (any.length == 1 &&
        (any.containsKey('output_text') || any.containsKey('raw'))) {
      final text = (any['output_text'] ?? any['raw'] ?? '').toString();
      return ReflectionTurn(
        outputText: text.trim().isNotEmpty ? text.trim() : errorHint,
        mirror: null,
        context: const [],
        followups: const [],
        answerHelpers: const [],
        helperSuggestion: null,
        flow: const ReflectionFlow(recommendEnd: false, suggestBreak: false),
        session: session,
        tags: const [],
        riskFlag: 'none',
        questions: const [],
      );
    }
    return _turnFromReflectJson(any, session);
  }

  ReflectionTurn _turnFromReflectJson(
      Map<String, dynamic> json, ReflectionSession session) {
    final questionsList = _parseStringList(
        json['questions'] ?? json['multi_questions'] ?? json['qs']);
    final altList = _parseStringList(
      json['alt'] ??
          json['alt_question'] ??
          json['alternatives'] ??
          json['alternative'] ??
          json['secondary_question'] ??
          json['secondary'] ??
          json['options'],
    );
    final allQs = _dedupeStrings([...questionsList, ...altList]);

    final primaryRaw = _extractPrimary(json).trim();
    final joinedQuestions = _normalizeQuestions(allQs);
    final primaryDisplay = joinedQuestions.isNotEmpty ? joinedQuestions : primaryRaw;
    final outputText = primaryDisplay.ifEmpty(() => errorHint);

    final firstQuestion = allQs.isNotEmpty
        ? _ensureQuestion(allQs.first)
        : (primaryRaw.isNotEmpty ? _ensureQuestion(primaryRaw) : '');

    final mirrorRaw =
        (json['mirror'] ?? json['empathy'] ?? '').toString().trim();
    final String? mirror = mirrorRaw.isEmpty ? null : mirrorRaw;

    final ctxDyn = (json['context'] as List?) ??
        (json['contexts'] as List?) ??
        (json['hints'] as List?) ??
        const [];
    final ctx = ctxDyn
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .take(4)
        .toList(growable: false);

    // ---- ANSWER HELPERS (aus Worker-Varianten einsammeln) --------------------
    final helpers = _readAnswerHelpers(json);

    // Followups: nur echte Followups aus dem JSON (nicht Chips duplizieren)
    final followups = _parseStringList(json['followups']);

    final talkDyn = (json['talk'] as List?) ?? const [];
    final talk = talkDyn
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: true);
    final smalltalk = (json['smalltalk_reply'] ?? '').toString().trim();
    if (smalltalk.isNotEmpty && talk.length < 2) {
      talk.add(smalltalk);
    }
    final talkLimited = talk.take(2).toList(growable: false);

    final flowJson = (json['flow'] as Map?) ?? const {};
    final flow = ReflectionFlow(
      recommendEnd:
          (flowJson['recommend_end'] == true) || (flowJson['end'] == true),
      suggestBreak:
          (flowJson['suggest_break'] == true) || (flowJson['break'] == true),
      riskNotice: flowJson['risk_notice']?.toString(),
      sessionTurn: (flowJson['session_turn'] is num)
          ? (flowJson['session_turn'] as num).toInt()
          : session.turnIndex,
      talkOnly: flowJson['talk_only'] == true,
      allowReflect: flowJson['allow_reflect'] != false,
      // PATCH: Mood-Prompt robust auch bei recommend_end / end
      moodPrompt: (flowJson['mood_prompt'] == true) ||
          (flowJson['recommend_end'] == true) ||
          (flowJson['end'] == true),
    );

    final sJson = (json['session'] as Map?) ?? const {};
    final s = session.copyWith(
      threadId: (sJson['id'] ?? sJson['thread_id'] ?? session.threadId)
          .toString(),
      turnIndex: (sJson['turn'] is num)
          ? (sJson['turn'] as num).toInt()
          : (sJson['turn_index'] is num)
              ? (sJson['turn_index'] as num).toInt()
              : session.turnIndex,
      maxTurns: (sJson['max_turns'] is num)
          ? (sJson['max_turns'] as num).toInt()
          : session.maxTurns,
    );

    final schoolsDyn = (json['schools'] as List?) ??
        (json['therapeutic_schools'] as List?) ??
        (json['approaches'] as List?) ??
        const [];
    final normalizedSchools = _normalizeSchools(_parseStringList(schoolsDyn));
    final workerTags = _parseStringList(json['tags']);
    final tags = _dedupeStrings([...workerTags, ...normalizedSchools]);

    final riskLevelRoot = (json['risk_level'] ??
            json['risk_flag'] ??
            json['risk'] ??
            'none')
        .toString()
        .trim()
        .toLowerCase();
    final riskFlag = (riskLevelRoot == 'high' || riskLevelRoot == 'crisis')
        ? 'crisis'
        : (riskLevelRoot == 'mild' ? 'support' : 'none');

    // ---- helperSuggestion (robust, mehrere Pfade) ---------------------------
    final helperSuggestion = _extractHelperSuggestion(json);

    return ReflectionTurn(
      outputText: outputText,
      mirror: mirror,
      context: ctx,
      followups: followups,
      answerHelpers: helpers, // ← Worker-Chips bleiben erhalten
      helperSuggestion: helperSuggestion, // ← NEU
      flow: flow,
      session: s,
      tags: tags,
      riskFlag: riskFlag,
      questions:
          allQs.isNotEmpty ? [firstQuestion, ...allQs.skip(1)] : const [],
      talk: talkLimited,
    );
  }

  // Liest answer-helpers aus verschiedenen möglichen Pfaden, normalisiert minimal.
  List<String> _readAnswerHelpers(Map<String, dynamic> json) {
    List<String> asList(dynamic v) => _parseStringList(v);

    // Top-Level & Aliase
    final top = <String>[
      ...asList(json['answer_helpers']),
      ...asList(json['answer_scaffolds']),
      ...asList(json['answer_templates']),
      ...asList(json['helpers']),
      ...asList(json['chips']),
      ...asList(json['answers']),
    ];

    // Verschachtelt unter flow / ui
    final flow = (json['flow'] as Map?) ?? const {};
    final ui = (json['ui'] as Map?) ?? const {};
    final nested = <String>[
      ...asList(flow['answer_helpers']),
      ...asList(flow['helpers']),
      ...asList(ui['answer_helpers']),
      ...asList(ui['chips']),
    ];

    // NICHT aufnehmen: echte Fragen (enden mit '?')
    final raw = [...top, ...nested]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.endsWith('?'))
        .toList();

    // Sanfte Normalisierung: Doppelpunkte am Ende weg
    final cleaned = raw
        .map((s) => s.replaceAll(RegExp(r'\s*[:：]\s*$'), '').trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Dedupe + Limit → **max 3** Chips
    return _dedupeStrings(cleaned).take(3).toList(growable: false);
  }

  // Liest helperSuggestion aus üblichen Feldern (Top-Level, flow, ui)
  String? _extractHelperSuggestion(Map<String, dynamic> json) {
    String pick(dynamic v) {
      if (v == null) return '';
      final s = v.toString().trim();
      return s.isNotEmpty ? s : '';
    }

    final flow = (json['flow'] as Map?) ?? const {};
    final ui = (json['ui'] as Map?) ?? const {};

    final candidates = <String>[
      pick(json['helper_suggestion']),
      pick(json['helperSuggestion']),
      pick(flow['helper_suggestion']),
      pick(flow['helperSuggestion']),
      pick(ui['helper_suggestion']),
      pick(ui['helperSuggestion']),
    ].where((s) => s.isNotEmpty).toList(growable: false);

    if (candidates.isEmpty) return null;
    // Sanft doppelte Punkte / Leerzeichen bereinigen
    final raw = candidates.first;
    final cleaned = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s*\.\s*\.\s*$'), '.')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String _extractPrimary(Map<String, dynamic> json) {
    final fromChoices = _contentFromChoices(json['choices']);
    final candidates = <String>[
      if (json['primary'] != null) json['primary'].toString(),
      if (json['primary_question'] != null)
        json['primary_question'].toString(),
      if (json['lead'] != null) json['lead'].toString(),
      if (json['lead_question'] != null) json['lead_question'].toString(),
      if (json['output_text'] != null) json['output_text'].toString(),
      if (json['question'] != null) json['question'].toString(),
      if (fromChoices != null && fromChoices.trim().isNotEmpty)
        fromChoices.trim(),
      if (json['content'] != null) json['content'].toString(),
      if (json['raw'] != null) json['raw'].toString(),
    ]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    if (candidates.isEmpty) return '';
    final first = candidates.first;
    return first.endsWith('?') ? first : '$first?';
  }

  static String? _contentFromChoices(dynamic choicesDyn) {
    if (choicesDyn is List && choicesDyn.isNotEmpty) {
      final first = choicesDyn.first;
      if (first is Map) {
        final msg = first['message'];
        if (msg is Map) {
          final content = msg['content'];
          if (content is String) return content;
          if (content != null) return content.toString();
        }
        final text = first['text'];
        if (text is String) return text;
        if (text != null) return text.toString();
      }
    }
    return null;
  }

  static List<String> _parseStringList(dynamic v) {
    if (v == null) return const <String>[];
    if (v is List) {
      final nonNull = v.where((e) => e != null).map((e) => e.toString());
      return nonNull
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return const <String>[];
      final parts = s
          .split(RegExp(r'\n+|[•\-–—]\s+|;\s+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return parts.isEmpty ? <String>[s] : parts;
    }
    return const <String>[];
  }

  static String _normalizeQuestions(List<String> qs) {
    if (qs.isEmpty) return '';
    final seen = <String>{};
    final clean = <String>[];
    for (final raw in qs) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      final key = s.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      clean.add(s.endsWith('?') ? s : '$s?');
    }
    if (clean.isEmpty) return '';
    if (clean.length == 1) return clean.first;
    return clean.map((e) => '– $e').join('\n');
  }

  static String _ensureQuestion(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return t.endsWith('?') ? t : '$t?';
  }

  static List<String> _dedupeStrings(List<String> items) {
    final out = <String>[];
    final seen = <String>{};
    for (final it in items) {
      final key = it.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(it.trim());
    }
    return out;
  }

  static const Map<String, String> _schoolAliases = {
    'cbt': 'CBT/KVT',
    'kvt': 'CBT/KVT',
    'kognitive verhaltenstherapie': 'CBT/KVT',
    'cognitive behavioral therapy': 'CBT/KVT',
    'act': 'ACT',
    'acceptance and commitment therapy': 'ACT',
    'dbt': 'DBT',
    'dialektisch-behaviorale therapie': 'DBT',
    'schema': 'Schematherapie',
    'schematherapie': 'Schematherapie',
    'schema therapy': 'Schematherapie',
    'systemic': 'Systemisch',
    'systemisch': 'Systemisch',
    'systemic therapy': 'Systemisch',
    'psychodynamic': 'Psychodynamisch',
    'psychodynamisch': 'Psychodynamisch',
    'tiefenpsychologisch': 'Psychodynamisch',
    'humanistic': 'Humanistisch',
    'humanistisch': 'Humanistisch',
    'client-centered': 'Humanistisch',
    'personzentriert': 'Humanistisch',
    'solution focused': 'Lösungsfokussiert',
    'lösungsfokussiert': 'Lösungsfokussiert',
    'sfbt': 'Lösungsfokussiert',
    'mi': 'Motivational Interviewing',
    'motivational interviewing': 'Motivational Interviewing',
    'mindfulness': 'Achtsamkeit',
    'achtsamkeit': 'Achtsamkeit',
    'mbct': 'Achtsamkeit',
  };

  static List<String> _normalizeSchools(List<String> raw) {
    if (raw.isEmpty) return const <String>[];
    final out = <String>{};
    for (final r in raw) {
      final s = r.trim();
      if (s.isEmpty) continue;
      final k = s.toLowerCase();
      if (_schoolAliases.containsKey(k)) {
        out.add(_schoolAliases[k]!);
        continue;
      }
      if (k.contains('kvt') || k.contains('cognitive') || k.contains('behavior')) {
        out.add('CBT/KVT');
      } else if (k.contains('act')) {
        out.add('ACT');
      } else if (k.contains('dbt')) {
        out.add('DBT');
      } else if (k.contains('schema')) {
        out.add('Schematherapie');
      } else if (k.contains('system')) {
        out.add('Systemisch');
      } else if (k.contains('dynam')) {
        out.add('Psychodynamisch');
      } else if (k.contains('human') ||
          k.contains('client') ||
          k.contains('person')) {
        out.add('Humanistisch');
      } else if (k.contains('solution')) {
        out.add('Lösungsfokussiert');
      } else if (k.contains('motiv')) {
        out.add('Motivational Interviewing');
      } else if (k.contains('mindful') ||
          k.contains('achtsam') ||
          k.contains('mbct')) {
        out.add('Achtsamkeit');
      } else {
        out.add(_neatEllipsis(s, 40));
      }
    }
    return out.toList(growable: false);
  }

  // --------- FEHLENDE HELFER (Build-Fehler) ---------------------------------

  String _estimateDepth(List<Map<String, String>> messages) {
    // sehr simple Heuristik: Länge der letzten User-Nachricht
    final lastUser =
        messages.lastWhereOrNull((m) => (m['role'] ?? '') == 'user');
    final txt = (lastUser?['content'] ?? '').trim();
    final len = txt.length;
    if (len >= 320) return 'deep';
    if (len >= 120) return 'medium';
    return 'light';
  }

  List<String> _nextStepsForLever(String lever) {
    switch (lever) {
      case 'Gedanken':
        return const [
          'Einen belastenden Gedanken notieren und eine alternative Sicht formulieren',
          'Belege sammeln: Was spricht dafür, was dagegen?',
          'Eine kleine, überprüfbare Annahme testen',
        ];
      case 'Gefühle':
        return const [
          '2 Minuten bewusst atmen (4–4–6)',
          'Benennen, ohne zu bewerten: „Ich fühle …“',
          'Einen sicheren, beruhigenden Mini-Schritt planen',
        ];
      case 'Körper':
        return const [
          'Kurz aufstehen und Schultern lockern',
          'Ein Glas Wasser trinken',
          '3× bewusst gähnen oder seufzen (Druck rausnehmen)',
        ];
      case 'Verhalten':
        return const [
          'Aufgabe in einen 2-Minuten-Start verwandeln',
          'Nächstes Hindernis benennen und eine Brücke bauen',
          'Einen freundlichen Check-in mit dir selbst terminieren',
        ];
      case 'Kontext':
      default:
        return const [
          'Eine beteiligte Person ansprechen (freundlich, konkret)',
          'Grenze formulieren: „Heute mache ich maximal …“',
          'Einen kleinen, realistischen nächsten Termin setzen',
        ];
    }
  }

  // ---------------- Memory Helpers (Backend-only) ----------------

  void _memorySave(Map<String, dynamic> json, String source) {
    try {
      unawaited(MemoryService.instance.saveFromWorker(json, source: source));
    } catch (_) {
      // Memory darf niemals die Hauptlogik stören
    }
  }

  void _appendMemoryHints(Map<String, dynamic> payload) {
    // Best-effort: falls MemoryService Hints liefern kann, mitschicken.
    try {
      final hint = MemoryService.instance.buildContextHint(
        maxFacets: 3,
        maxTags: 5,
        maxAgeDays: 14,
      );
      if (hint != null) {
        payload['context_hint'] = {
          if (hint.facets != null) 'recent_facets': hint.facets,
          if (hint.tags != null) 'recent_tags': hint.tags,
          if (hint.topics != null) 'last_themes': hint.topics,
        };
      }
    } catch (_) {
      // still: keine Abhängigkeit für Build
    }
  }

  void _appendContactTints(Map<String, dynamic> payload,
      {required String locale, required String tz}) {
    payload['contact_tins'] = {
      'brand': _brand,
      'channel': _channel,
      'samfring': _samfring,
      'locale': locale,
      'tz': tz,
    };
  }

  // Byte-Kontext (falls MemoryService das anbietet) → Base64, ohne await.
  void _appendByteContext(Map<String, dynamic> payload, {int maxBytes = 2048}) {
    try {
      // dynamic, damit das Projekt kompiliert selbst wenn es diese API noch nicht hat.
      // ignore: unused_local_variable
      final mem = MemoryService.instance;
      dynamic dyn = mem;
      List<int>? bytes;
      try {
        // bevorzugte Namen:
        // ignore: avoid_dynamic_calls
        bytes = dyn.tryGetByteContext?.call(maxBytes);
      } catch (_) {}
      try {
        bytes ??= // ignore: avoid_dynamic_calls
            dyn.exportByteContext?.call(maxBytes);
      } catch (_) {}
      try {
        bytes ??= // ignore: avoid_dynamic_calls
            dyn.byteContext?.call(maxBytes);
      } catch (_) {}

      if (bytes is List<int> && bytes.isNotEmpty) {
        final capped = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
        payload['context_bytes_b64'] = base64Encode(capped);
      }
    } catch (_) {
      // niemals blockieren
    }
  }

  // ========================== INTERNES DRY-UTILITY ===========================

  Map<String, dynamic> _buildSessionMap(ReflectionSession s) => {
        'id': s.threadId,
        'turn': s.turnIndex,
        'max_turns': s.maxTurns,
      };

  Map<String, dynamic> _basePayload({
    required String text,
    required String locale,
    required String tz,
    required ReflectionSession session,
    List<Map<String, String>> messages = const [],
    String? intent,
  }) {
    final payload = <String, dynamic>{
      'text': text,
      'messages': messages,
      'locale': locale,
      'tz': tz,
      'session': _buildSessionMap(session),
      if (intent != null) 'intent': intent,
    };
    _appendMemoryHints(payload);
    _appendContactTints(payload, locale: locale, tz: tz);
    _appendByteContext(payload);
    return payload;
  }

  /// Postet JSON; speichert Memory-Hook, wenn erfolgreich.
  Future<Map<String, dynamic>?> _postMaybe(
    String path,
    Map<String, dynamic> payload, {
    String? saveSource,
  }) async {
    if (_http == null) return null;

    // kleiner Start-Blocker direkt hier (falls nicht über Worker-Invoker gelaufen)
    if (!_outGateOpen && !_isHealthPath(path)) {
      final jitter = 90 + _rand.nextInt(90);
      await Future.delayed(Duration(milliseconds: jitter));
    }

    try {
      final json = await _http!(path, payload).timeout(_timeout);
      if (saveSource != null) _memorySave(json, saveSource);
      return json;
    } catch (_) {
      return null;
    }
  }

  /// Einheitlicher Retry mit sanftem Backoff.
  Future<Map<String, dynamic>?> _tryEndpoints({
    required List<String> endpoints,
    required Map<String, dynamic> payload,
  }) async {
    const bases = [420, 900, 1800];
    for (int i = 0; i < endpoints.length; i++) {
      final path = endpoints[i];
      final json = await _postMaybe(path, payload, saveSource: path.replaceFirst('/', ''));
      if (json != null) return json;

      // Wenn aktueller Endpoint failt, ggf. Backoff vor *nächster* Variante
      if (i < endpoints.length - 1) {
        final jitter = _rand.nextInt(180);
        await Future.delayed(Duration(milliseconds: bases[i.clamp(0, bases.length - 1)] + jitter));
      }
    }
    return null;
  }

  Map<String, dynamic> _closureFallback(ReflectionSession? session) => <String, dynamic>{
        'closure': {
          'mood_intro': {'text': ''},
        },
        'flow': {
          'recommend_end': true,
          'talk_only': false,
          'allow_reflect': true,
          'suggest_break': false,
          'mood_prompt': true,
        },
        if (session != null) 'session': _buildSessionMap(session),
      };
}

// ---------------- Kompat-Struktur nur für aiReflect() ----------------
class ReflectionAIResult {
  final String reflection;
  final String depth; // light | medium | deep
  final String riskFlag; // none | support | crisis
  final List<String> tags;
  const ReflectionAIResult({
    required this.reflection,
    required this.depth,
    required this.riskFlag,
    required this.tags,
  });
}
