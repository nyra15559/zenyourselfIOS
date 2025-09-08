// lib/services/guidance_service.dart
//
// ZenYourself — Guidance/Coaching Service
// Aligned with Zen Panda Worker v9.2.3 (JSON contracts, ReflectionScreen compat)
// ---------------------------------------------------------------------------
// Endpoints (Cloudflare Worker):
//   GET  /health          → { ok: true } | 200 "ok"
//   POST /reflect         → { output_text, question, questions[], mirror?, talk[], context[], flow{}, session{}, tags[], risk_level }
//   POST /reflect_full    → wie /reflect (angereichert; kompatibel für Pro-Analyse)
//   POST /story           → { title, story, ... }
//   POST /journey         → { insights[], question }
//   POST /mood            → { saved: true }
//
// Highlights:
// - Session-API: startSession / continueSession / talk (intent="talk")
// - Robustes Parsing (primary/question/choices/text/plain; tolerant ggü. Alt-Feldern)
// - PII-Redaktion (E-Mail, Tel, URL, IBAN, Card), sanftes Ellipsis
// - Backoff & Timeout zentral konfigurierbar; Health-Check-Helper
// - Offline-Heuristiken: Emotion, Mood (0..4), Tags, Strukturierung
// - ReflectionScreen-Compat: Getter-Shims (output_text, risk_level, risk), toJson() Maps
//
// Anmerkung:
// - Klassen Analysis/MiniChallenge/Question/ReflectionEntry werden im Projekt erwartet.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/question.dart';
import '../data/reflection_entry.dart';

// ------------------------------------------------------------
// Typalias für injizierbaren HTTP-Invoker (siehe ApiClient.call)
// ------------------------------------------------------------
typedef HttpInvoker = Future<Map<String, dynamic>> Function(
  String path,
  Map<String, dynamic> body,
);

// ===========================================================================
//  Core Service (Singleton, intern)
// ===========================================================================
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final _rand = Random();
  final _uuid = const Uuid();

  HttpInvoker? _http;
  String? _baseUrl; // optional für Logging/Debug
  Duration _timeout = const Duration(seconds: 25);

  // Branding-Texte fürs UI
  static const String _brand = 'ZenYourself';
  static const String loadingHint = '$_brand zählt die Blümchen …';
  static const String errorHint =
      '$_brand hat die Blümchen nicht gefunden. Bitte prüfe kurz deine Internetverbindung.';

  // ---------------- Config ----------------

  /// Setzt einen fertigen Invoker (z. B. ApiClient.call aus services/api_client.dart).
  void configureHttp({HttpInvoker? invoker, String? baseUrl, Duration? timeout}) {
    _http = invoker;
    _baseUrl = baseUrl ?? _baseUrl;
    if (timeout != null) _timeout = timeout;
  }

  /// Convenience: Direkt per Worker-Basisurl + Token verdrahten (optional).
  void configureForWorker({
    required String baseUrl,
    required String appToken,
    Duration timeout = const Duration(seconds: 25),
  }) {
    _baseUrl = baseUrl;
    _timeout = timeout;

    _http = (String path, Map<String, dynamic> body) async {
      final uri = Uri.parse(baseUrl + path);
      final headers = <String, String>{
        'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept':
            'application/json, application/problem+json;q=0.95, text/plain;q=0.9, */*;q=0.8',
      };

      final res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);

      if (res.statusCode >= 400) {
        throw Exception('Worker ${res.statusCode}: ${res.body}');
      }

      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('application/json')) {
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

  static String _decodeBody(http.Response res) {
    try {
      return utf8.decode(res.bodyBytes);
    } catch (_) {
      return res.body.toString();
    }
  }

  // ---------------- Health ----------------

  /// Health-Check (optional; true = erreichbar/ok).
  Future<bool> healthCheck() async {
    if (_baseUrl == null) return false;
    try {
      final uri = Uri.parse('$_baseUrl/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode >= 400) return false;
      if (res.body.trim().toLowerCase() == 'ok') return true;
      if ((res.headers['content-type'] ?? '').contains('json')) {
        final json = jsonDecode(res.body);
        if (json is Map && (json['ok'] == true || json['status'] == 'ok')) return true;
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

  Future<ReflectionSession> endSession(ReflectionSession s) async => s;

  Future<ReflectionTurn> _reflectStep({
    required String text,
    required ReflectionSession session,
    required String locale,
    required String tz,
    required List<Map<String, String>> history,
  }) async {
    if (_http == null) return _errorTurn(session);

    final payload = <String, dynamic>{
      'text': text,
      'messages': history, // darf leer sein
      'locale': locale,
      'tz': tz,
      'session': {
        'id': session.threadId,
        'turn': session.turnIndex,
        'max_turns': session.maxTurns,
      },
    };

    // sanfter Backoff
    const retries = [420, 900, 1800];
    for (int i = 0; i < retries.length; i++) {
      try {
        final json = await _http!('/reflect', payload).timeout(_timeout);
        return _turnFromReflectAny(json, session);
      } catch (_) {
        if (i < retries.length - 1) {
          await Future.delayed(Duration(milliseconds: retries[i]));
          continue;
        }
      }
    }
    return _errorTurn(session);
  }

  // ---- Talk-only (intent="talk") -----------------------------------------
  Future<ReflectionTurn> talk({
    required ReflectionSession session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    String? userText,
    List<Map<String, String>>? history,
  }) async {
    if (_http == null) {
      return ReflectionTurn(
        outputText: '',
        mirror: null,
        context: const [],
        followups: const [],
        flow: const ReflectionFlow(recommendEnd: false, suggestBreak: false, talkOnly: true, allowReflect: true),
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

    final payload = <String, dynamic>{
      'text': (userText ?? '').trim(),
      'messages': history ?? const [],
      'locale': locale,
      'tz': tz,
      'intent': 'talk',
      'session': {
        'id': session.threadId,
        'turn': session.turnIndex,
        'max_turns': session.maxTurns,
      },
    };

    try {
      final json = await _http!('/reflect', payload).timeout(_timeout);
      // Worker liefert talk-only Felder
      final sTurn = _turnFromReflectJson(json, session);
      return sTurn;
    } catch (_) {
      return ReflectionTurn(
        outputText: '',
        mirror: null,
        context: const [],
        followups: const [],
        flow: const ReflectionFlow(recommendEnd: false, suggestBreak: false, talkOnly: true, allowReflect: true),
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
        flow: const ReflectionFlow(recommendEnd: false, suggestBreak: false),
        session: session,
        tags: const [],
        riskFlag: 'none',
        questions: const [],
      );

  // =======================================================================
  //  analyze() → /reflect_full (tieferes JSON)
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
        question: errorHint,
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
    };

    try {
      final json = await _http!('/reflect_full', payload).timeout(_timeout);

      final qsList = _parseStringList(
        json['questions'] ?? json['qs'] ?? json['multi_questions'],
      );
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
  //  Legacy-Kompat: aiReflect() (nutzt intern _reflectStep)
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

    final userText = messages
            .lastWhereOrNull((m) => (m['role'] ?? '') == 'user')?['content'] ??
        (messages.isNotEmpty ? (messages.last['content'] ?? '') : '');

    final turn = await _reflectStep(
      text: (userText ?? '').trim(),
      session: ReflectionSession(threadId: _uuid.v4(), turnIndex: 0, maxTurns: 3),
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
  //  mood() — optionaler Best-Effort Call
  // =======================================================================
  Future<MoodResponse> mood({
    required String entryId,
    required int icon,
    String? note,
    bool useServerIfAvailable = true,
  }) async {
    if (useServerIfAvailable && _http != null) {
      try {
        await _http!('/mood', {
          'entry_id': entryId,
          'mood': {'icon': icon, if (note != null && note.trim().isNotEmpty) 'note': note},
        });
      } catch (_) {/* ignore */}
    }
    return const MoodResponse(saved: true);
  }

  // =======================================================================
  //  story() — Worker /story
  // =======================================================================
  Future<StoryResult> story({
    required List<String> entryIds,
    List<String>? topics,
    bool useServerIfAvailable = true,
  }) async {
    if (_http != null && useServerIfAvailable) {
      const retries = [500, 1500, 3000];
      for (int i = 0; i < retries.length; i++) {
        try {
          final nowDate = DateTime.now().toUtc().toIso8601String().split('T').first;
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
                'tags': const <String>[],
              }
            ],
            'locale': 'de',
            'tz': 'Europe/Zurich',
          };

          final json = await _http!('/story', payload).timeout(_timeout);
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
          if (i < retries.length - 1) {
            await Future.delayed(Duration(milliseconds: retries[i]));
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

  // =======================================================================
  //  journey() — Worker /journey
  // =======================================================================
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
                return {'date': e.dateIso, 'mood': e.moodLabel ?? '', 'text': red.substring(0, end)};
              })
              .toList(growable: false),
          'horizon': horizon,
        };

        final json = await _http!('/journey', payload).timeout(_timeout);
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
          question: question.isNotEmpty ? question : insights.first,
        );
      } catch (_) {
        // unten Fallback
      }
    }

    return const JourneyInsights(
      insights: <String>['ZenYourself konnte keine Insights laden.'],
      question: loadingHint,
    );
  }

  // =======================================================================
  //  Lokal: Gedanken strukturieren, Emotion/Mood, Tags
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
    final moodHint = _composeMoodHint(emo, score);

    final nextSteps = _nextStepsForLever(lever);

    return StructuredThoughtResult(
      bullets: bullets,
      coreIdea: core.ifEmpty(() => _neatEllipsis(sanitized, 120)),
      moodHint: moodHint,
      nextSteps: nextSteps,
      source: 'offline',
    );
  }

  Future<Question> fetchGuidingQuestion({String? contextText, bool followUp = false}) async {
    final ctx = (contextText ?? '').trim();

    if (_http != null) {
      try {
        final json = await _http!('/reflect_full', {
          'text': ctx.isEmpty ? 'kurze Reflexion' : ctx,
          'locale': 'de',
          'tz': 'Europe/Zurich',
          'session': {'id': _uuid.v4(), 'turn': 0, 'max_turns': 1},
        }).timeout(_timeout);

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

  Future<String> summarizeReflection(ReflectionEntry entry) async {
    final raw = _bestEffortContent(entry);
    if (raw.isEmpty) return '';
    final red = _redactPII(raw);
    final bullets = _bulletsFromText(red, maxItems: 3);
    final emo = detectEmotionSync(red);
    final mood = classifyMoodSync(red);
    final tail = _composeMoodHint(emo, mood);
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

  // ---------- Offline-Heuristik: Emotion/Mood ----------
  String? detectEmotionSync(String text) {
    final t = text.toLowerCase();
    if (_any(t, ['wut', 'zorn', 'ärger', 'sauer', 'genervt'])) return 'wütend';
    if (_any(t, ['traurig', 'trauer', 'leer', 'niedergeschlagen', 'weinen'])) return 'traurig';
    if (_any(t, ['stress', 'gestresst', 'nervös', 'überforder', 'panik'])) return 'gestresst';
    if (_any(t, ['ruhig', 'entspannt', 'gelassen', 'friedlich'])) return 'ruhig';
    if (_any(t, ['glücklich', 'freu', 'dankbar', 'zufrieden', 'stolz'])) return 'glücklich';
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
    if (_any(t, ['glücklich', 'freu', 'dankbar', 'zufrieden', 'stolz'])) score += 2;

    return score.clamp(0, 4);
  }

  // =======================================================================
  //  Utilities
  // =======================================================================
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
    if (RegExp(r'^\[[^\]]+\]$').hasMatch(hint)) return q; // nur Masken → weglassen
    return '$q\n\n(Bezug: $hint)';
  }

  String _redactPII(String input) {
    var s = input;
    final email =
        RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false);
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

  String _bestEffortContent(ReflectionEntry entry) {
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
    if (_any(t, const ['gefüh', 'angst', 'wut', 'traur', 'überforder'])) return 'Gefühle';
    if (_any(t, const ['körper', 'schlaf', 'angespannt', 'atem', 'müde'])) return 'Körper';
    if (_any(t, const ['aufschieb', 'scroll', 'reaktion', 'streit', 'vermeid'])) return 'Verhalten';
    if (_any(t, const ['arbeit', 'chef', 'famil', 'uni', 'termin', 'druck'])) return 'Kontext';
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
      if (lever == 'Gedanken' && _any(t, const ['sollte', 'muss', 'immer', 'nie'])) score += 2;
      if (lever == 'Gefühle' && _any(t, const ['fühl', 'angst', 'wut', 'traur'])) score += 2;
      if (lever == 'Körper' && _any(t, const ['körper', 'müde', 'schlaf', 'atem'])) score += 2;
      if (lever == 'Verhalten' && _any(t, const ['aufschieb', 'start', 'beginnen', 'klein'])) score += 2;
      if (lever == 'Kontext' && _any(t, const ['arbeit', 'termin', 'chef', 'famil'])) score += 2;
      return score;
    }
    bullets.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
    return bullets.first;
  }

  List<String> _nextStepsForLever(String lever) {
    switch (lever) {
      case 'Gefühle':
        return const [
          '2-Minuten Atem: 4s ein, 6s aus – dreimal',
          'Benenne die Emotion leise („ich bemerke …“)',
          'Schreibe 3 Sätze: „Ich darf …“',
        ];
      case 'Körper':
        return const [
          'Kurz aufstehen, Schultern kreisen (30s)',
          'Ein Glas Wasser trinken',
          '90 Sekunden Blick aus dem Fenster',
        ];
      case 'Verhalten':
        return const [
          'Wähle den kleinstmöglichen ersten Schritt (≤2 Min.)',
          'Stell einen 5-Minuten-Timer und starte',
          'Lege das Handy in einen anderen Raum',
        ];
      case 'Kontext':
        return const [
          'Formuliere eine freundliche Bitte an eine Person',
          'Streiche heute eine Sache von der Liste',
          'Plane 10 ruhige Minuten zwischen Terminen',
        ];
      case 'Gedanken':
      default:
        return const [
          'Finde die „sollte“-Formulierung und ersetze sie durch „ich könnte …“',
          'Schreibe eine alternative, freundlichere Perspektive',
          'Frag dich: „Was wäre ein kleiner erster Schritt?“',
        ];
    }
  }

  String? _composeMoodHint(String? emotion, int? score) {
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

  String _estimateDepth(List<Map<String, String>> messages) {
    final u = messages
        .where((m) => m['role'] == 'user')
        .map((m) => (m['content'] ?? '').trim())
        .join('\n');
    final len = u.length;
    if (len > 800) return 'deep';
    if (len > 300) return 'medium';
    return 'light';
  }

  // ---------------- Reflect-Parsing ----------------
  ReflectionTurn _turnFromReflectAny(Map<String, dynamic> any, ReflectionSession session) {
    if (any.length == 1 && (any.containsKey('output_text') || any.containsKey('raw'))) {
      final text = (any['output_text'] ?? any['raw'] ?? '').toString();
      return ReflectionTurn(
        outputText: text.trim().isEmpty ? errorHint : text.trim(),
        mirror: null,
        context: const [],
        followups: const [],
        flow: const ReflectionFlow(recommendEnd: false, suggestBreak: false),
        session: session,
        tags: const [],
        riskFlag: 'none',
        questions: const [],
      );
    }
    return _turnFromReflectJson(any, session);
  }

  ReflectionTurn _turnFromReflectJson(Map<String, dynamic> json, ReflectionSession session) {
    // 1) Fragen + Alternativen
    final questionsList = _parseStringList(json['questions'] ?? json['multi_questions'] ?? json['qs']);
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

    // 2) Primary/Output
    final primaryRaw = _extractPrimary(json).trim();
    final joinedQuestions = _normalizeQuestions(allQs);
    final primary = joinedQuestions.isNotEmpty ? joinedQuestions : primaryRaw;
    final outputText = primary.ifEmpty(() => errorHint);

    // 3) Mirror
    final mirrorRaw = (json['mirror'] ?? json['empathy'] ?? '').toString().trim();
    final String? mirror = mirrorRaw.isEmpty ? null : mirrorRaw;

    // 4) Kontext
    final ctxDyn = (json['context'] as List?) ?? (json['contexts'] as List?) ?? (json['hints'] as List?) ?? const [];
    final ctx = ctxDyn.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).take(4).toList(growable: false);

    // 5) Followups (UI nutzt sie nicht mehr aktiv)
    final flwDyn = (json['followups'] as List?) ??
        (json['follow_up'] as List?) ??
        (json['followup_questions'] as List?) ??
        const [];
    final flw = flwDyn.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).take(4).toList(growable: false);

    // 6) Talk lines
    final talkDyn = (json['talk'] as List?) ?? const [];
    final talk = talkDyn.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).take(2).toList(growable: false);

    // 7) Flow
    final flowJson = (json['flow'] as Map?) ?? const {};
    final flow = ReflectionFlow(
      recommendEnd: (flowJson['recommend_end'] == true) || (flowJson['end'] == true),
      suggestBreak: (flowJson['suggest_break'] == true) || (flowJson['break'] == true),
      riskNotice: flowJson['risk_notice']?.toString(),
      sessionTurn: (flowJson['session_turn'] is num) ? (flowJson['session_turn'] as num).toInt() : session.turnIndex,
      talkOnly: flowJson['talk_only'] == true,
      allowReflect: flowJson['allow_reflect'] != false, // default: true
    );

    // 8) Session
    final sJson = (json['session'] as Map?) ?? const {};
    final s = session.copyWith(
      threadId: (sJson['id'] ?? sJson['thread_id'] ?? session.threadId).toString(),
      turnIndex: (sJson['turn'] is num)
          ? (sJson['turn'] as num).toInt()
          : (sJson['turn_index'] is num)
              ? (sJson['turn_index'] as num).toInt()
              : session.turnIndex,
      maxTurns: (sJson['max_turns'] is num)
          ? (sJson['max_turns'] as num).toInt()
          : session.maxTurns,
    );

    // 9) Tags/Schulen
    final schoolsDyn = (json['schools'] as List?) ??
        (json['therapeutic_schools'] as List?) ??
        (json['approaches'] as List?) ??
        const [];
    final normalizedSchools = _normalizeSchools(_parseStringList(schoolsDyn));
    final workerTags = _parseStringList(json['tags']);
    final tags = _dedupeStrings([...workerTags, ...normalizedSchools]);

    // 10) Risiko
    final riskLevelRoot =
        (json['risk_level'] ?? json['risk_flag'] ?? json['risk'] ?? 'none').toString().trim().toLowerCase();
    final riskFlag = (riskLevelRoot == 'high' || riskLevelRoot == 'crisis')
        ? 'crisis'
        : (riskLevelRoot == 'mild' ? 'support' : 'none');

    return ReflectionTurn(
      outputText: outputText,
      mirror: mirror,
      context: ctx,
      followups: flw,
      flow: flow,
      session: s,
      tags: tags,
      riskFlag: riskFlag,
      questions: allQs,
      talk: talk,
    );
  }

  // ---- Primary-Extraction & Utilities ----
  static String _extractPrimary(Map<String, dynamic> json) {
    final fromChoices = _contentFromChoices(json['choices']);
    final candidates = <String>[
      if (json['primary'] != null) json['primary'].toString(),
      if (json['primary_question'] != null) json['primary_question'].toString(),
      if (json['lead'] != null) json['lead'].toString(),
      if (json['lead_question'] != null) json['lead_question'].toString(),
      if (json['output_text'] != null) json['output_text'].toString(),
      if (json['question'] != null) json['question'].toString(),
      if (fromChoices != null && fromChoices.trim().isNotEmpty) fromChoices.trim(),
      if (json['content'] != null) json['content'].toString(),
      if (json['raw'] != null) json['raw'].toString(),
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).toList(growable: false);

    if (candidates.isEmpty) return '';
    final first = candidates.first;
    // Stelle sicher, dass am Ende genau ein Fragezeichen steht.
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
      return v.map((e) => e?.toString() ?? '').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(growable: false);
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return const <String>[];
      final parts = s
          .split(RegExp(r'\n+|[•\-]\s+'))
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
      } else if (k.contains('human') || k.contains('client') || k.contains('person')) {
        out.add('Humanistisch');
      } else if (k.contains('solution')) {
        out.add('Lösungsfokussiert');
      } else if (k.contains('motiv')) {
        out.add('Motivational Interviewing');
      } else if (k.contains('mindful') || k.contains('achtsam') || k.contains('mbct')) {
        out.add('Achtsamkeit');
      } else {
        out.add(_neatEllipsis(s, 40));
      }
    }
    return out.toList(growable: false);
  }
}

// ===========================================================================
//  Öffentliche Fassade (Singleton)
// ===========================================================================
class GuidanceService {
  GuidanceService._();
  static final GuidanceService instance = GuidanceService._();

  // Optional fürs UI
  String get loadingHint => ApiService.loadingHint;
  String get errorHint => ApiService.errorHint;

  void configureHttp({HttpInvoker? invoker, String? baseUrl, Duration? timeout}) =>
      ApiService.instance.configureHttp(invoker: invoker, baseUrl: baseUrl, timeout: timeout);

  void configureForWorker({required String baseUrl, required String appToken, Duration? timeout}) =>
      ApiService.instance.configureForWorker(baseUrl: baseUrl, appToken: appToken, timeout: timeout ?? const Duration(seconds: 25));

  Future<bool> healthCheck() => ApiService.instance.healthCheck();

  // ----- Session-API -----
  Future<ReflectionTurn> startSession({
    String? text,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
  }) =>
      ApiService.instance.startSession(
        text: text,
        userText: userText,
        locale: locale,
        tz: tz,
        maxTurns: maxTurns,
        history: history,
      );

  Future<ReflectionTurn> continueSession({
    required ReflectionSession session,
    String? text,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
  }) =>
      ApiService.instance.continueSession(
        session: session,
        text: text,
        userText: userText,
        locale: locale,
        tz: tz,
        history: history,
      );

  Future<ReflectionSession> endSession(ReflectionSession s) =>
      ApiService.instance.endSession(s);

  /// Bequem: Start oder Fortsetzen anhand [session].
  Future<ReflectionTurn> reflect({
    required String userText,
    ReflectionSession? session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    int maxTurns = 3,
  }) {
    if (session == null) {
      return startSession(
        userText: userText,
        locale: locale,
        tz: tz,
        maxTurns: maxTurns,
        history: history,
      );
    }
    return continueSession(
      session: session,
      userText: userText,
      locale: locale,
      tz: tz,
      history: history,
    );
  }

  /// Warmes Begleiten ohne neue Frage (intent="talk").
  Future<ReflectionTurn> talk({
    required ReflectionSession session,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
  }) =>
      ApiService.instance.talk(
        session: session,
        userText: userText,
        locale: locale,
        tz: tz,
        history: history,
      );

  // ----- Bestehende API -----
  Future<ReflectionAIResult> aiReflect({
    required List<Map<String, String>> messages,
    String model = 'gpt-4.1',
  }) =>
      ApiService.instance.aiReflect(messages: messages, model: model);

  Future<AnalyzeResult> analyze({
    required String mode,
    required String text,
    int? durationSec,
    List<int>? recentMoods,
    int? streak,
    bool useServerIfAvailable = true,
  }) =>
      ApiService.instance.analyze(
        mode: mode,
        text: text,
        durationSec: durationSec,
        recentMoods: recentMoods,
        useServerIfAvailable: useServerIfAvailable,
        streak: streak,
      );

  Future<MoodResponse> mood({
    required String entryId,
    required int icon,
    String? note,
    bool useServerIfAvailable = true,
  }) =>
      ApiService.instance.mood(
        entryId: entryId,
        icon: icon,
        note: note,
        useServerIfAvailable: useServerIfAvailable,
      );

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

  Future<JourneyInsights> journey({
    required List<JourneyEntry> entries,
    String horizon = '7d',
    bool useServerIfAvailable = true,
  }) =>
      ApiService.instance.journey(
        entries: entries,
        horizon: horizon,
        useServerIfAvailable: useServerIfAvailable,
      );

  Future<StructuredThoughtResult> structureThoughts(String input, {bool useServerIfAvailable = true}) =>
      ApiService.instance.structureThoughts(input, useServerIfAvailable: useServerIfAvailable);

  Future<Question> fetchGuidingQuestion({String? contextText, bool followUp = false}) =>
      ApiService.instance.fetchGuidingQuestion(contextText: contextText, followUp: followUp);

  Future<Question> fetchFollowUp({String? contextText}) =>
      ApiService.instance.fetchFollowUp(contextText: contextText);

  Future<String> summarizeReflection(ReflectionEntry entry) =>
      ApiService.instance.summarizeReflection(entry);

  Future<String?> detectEmotion(String text) => ApiService.instance.detectEmotion(text);
  Future<int?> classifyMood(String text) => ApiService.instance.classifyMood(text);
  Future<List<String>> suggestTags(String text) => ApiService.instance.suggestTags(text);
}

// ===========================================================================
//  DTOs / Ergebnisse
// ===========================================================================
class AnalyzeResult {
  final Analysis analysis;
  final MiniChallenge? challenge;
  const AnalyzeResult({required this.analysis, this.challenge});
  Map<String, dynamic> toJson() => {
        'analysis': analysis.toJson(),
        if (challenge != null) 'challenge': challenge!.toJson(),
      };
  factory AnalyzeResult.fromJson(Map<String, dynamic> json) {
    final analysis = Analysis.fromMaybe(json['analysis']) ??
        const Analysis(sorc: null, levers: [], mirror: null, question: null, riskLevel: null);
    final challenge = MiniChallenge.fromMaybe(json['challenge']);
    return AnalyzeResult(analysis: analysis, challenge: challenge);
  }
}

class ReflectionAIResult {
  final String reflection; // Hauptfrage ODER Fehlerhinweis
  final String depth;      // light | medium | deep
  final String riskFlag;   // none | support | crisis
  final List<String> tags; // z. B. ["Arbeit","Schlaf"]
  const ReflectionAIResult({
    required this.reflection,
    required this.depth,
    required this.riskFlag,
    required this.tags,
  });
}

class ReflectionTurn {
  final String outputText;          // UI-Primary (evtl. zusammengefasst)
  final String? mirror;             // 2–4 Sätze vom Worker
  final List<String> context;       // kurze Hinweise
  final List<String> followups;     // Mini-Fragen
  final ReflectionFlow? flow;       // recommend_end, suggest_break, risk_notice, allow_reflect, talk_only
  final ReflectionSession session;  // id/turn/max_turns
  final List<String> tags;          // inkl. Schulen/Linsen
  final String riskFlag;            // none | support | crisis
  final List<String> questions;     // alle gelieferten Fragen
  final List<String> talk;          // warmes Begleiten (intent=talk)

  const ReflectionTurn({
    required this.outputText,
    required this.mirror,
    required this.context,
    required this.followups,
    required this.flow,
    required this.session,
    required this.tags,
    required this.riskFlag,
    this.questions = const [],
    this.talk = const [],
  });

  // ---- Compat-Shims für ReflectionScreen.dynamic ---------------------------
  String get output_text => outputText;
  String get risk_level => (riskFlag == 'crisis')
      ? 'high'
      : (riskFlag == 'support' ? 'mild' : 'none');
  bool get risk => riskFlag == 'support' || riskFlag == 'crisis';

  bool get recommendEnd => flow?.recommendEnd == true;
  bool get suggestBreak => flow?.suggestBreak == true;
  bool get canReflect => flow?.allowReflect != false;
  bool get isTalkOnly => flow?.talkOnly == true;

  Map<String, dynamic> toJson() => {
        'output_text': outputText,
        if (mirror != null) 'mirror': mirror,
        if (context.isNotEmpty) 'context': context,
        if (followups.isNotEmpty) 'followups': followups,
        'flow': flow?.toJson() ?? const ReflectionFlow(recommendEnd:false, suggestBreak:false).toJson(),
        'session': session.toJson(),
        if (tags.isNotEmpty) 'tags': tags,
        'risk_level': risk_level,
        if (questions.isNotEmpty) 'questions': questions,
        if (talk.isNotEmpty) 'talk': talk,
      };
}

class ReflectionFlow {
  final bool recommendEnd;
  final bool suggestBreak;
  final String? riskNotice;
  final int? sessionTurn;
  final bool talkOnly;
  final bool allowReflect;
  const ReflectionFlow({
    required this.recommendEnd,
    required this.suggestBreak,
    this.riskNotice,
    this.sessionTurn,
    this.talkOnly = false,
    this.allowReflect = true,
  });

  Map<String, dynamic> toJson() => {
        'recommend_end': recommendEnd,
        'suggest_break': suggestBreak,
        if (riskNotice != null) 'risk_notice': riskNotice,
        if (sessionTurn != null) 'session_turn': sessionTurn,
        if (talkOnly) 'talk_only': true,
        'allow_reflect': allowReflect,
      };
}

class ReflectionSession {
  final String threadId;
  final int turnIndex;
  final int maxTurns;
  const ReflectionSession({
    required this.threadId,
    required this.turnIndex,
    required this.maxTurns,
  });

  ReflectionSession copyWith({String? threadId, int? turnIndex, int? maxTurns}) =>
      ReflectionSession(
        threadId: threadId ?? this.threadId,
        turnIndex: turnIndex ?? this.turnIndex,
        maxTurns: maxTurns ?? this.maxTurns,
      );

  Map<String, dynamic> toJson() => {
        'id': threadId,
        'turn': turnIndex,
        'max_turns': maxTurns,
      };
}

class JourneyInsights {
  final List<String> insights; // 3–6 Beobachtungen ODER Fehlerhinweis
  final String question;       // Leitfrage ODER Lade-/Fehlerhinweis
  const JourneyInsights({required this.insights, required this.question});
}

class StructuredThoughtResult {
  final List<String> bullets;
  final String coreIdea;
  final String? moodHint;
  final List<String> nextSteps;
  final String source; // 'server' | 'offline'
  const StructuredThoughtResult({
    required this.bullets,
    required this.coreIdea,
    required this.nextSteps,
    this.moodHint,
    this.source = 'server',
  });
  Map<String, dynamic> toJson() => {
        'bullets': bullets,
        'core_idea': coreIdea,
        if (moodHint != null) 'mood_hint': moodHint,
        'next_steps': nextSteps,
        'source': source,
      };
  factory StructuredThoughtResult.fromJson(Map<String, dynamic> json) {
    final bulletsDyn = (json['bullets'] as List?) ?? const [];
    final nsDyn = (json['next_steps'] as List?) ?? const [];
    return StructuredThoughtResult(
      bullets: bulletsDyn.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList(),
      coreIdea: (json['core_idea'] ?? '').toString(),
      moodHint: json['mood_hint']?.toString(),
      nextSteps: nsDyn.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList(),
      source: (json['source'] ?? 'server').toString(),
    );
  }
}

class JourneyEntry {
  final String dateIso;    // YYYY-MM-DD
  final String? moodLabel; // z. B. "Gut" | null
  final String text;       // Rohtext (wird PII-redacted gesendet)
  const JourneyEntry({required this.dateIso, required this.text, this.moodLabel});
}

class MoodResponse {
  final bool saved;
  const MoodResponse({required this.saved});
}

class StoryResult {
  final String id;
  final String title;
  final String body;
  final String? audioUrl;
  const StoryResult({required this.id, required this.title, required this.body, this.audioUrl});
}

// Kleine String-Extension
extension _IfEmpty on String {
  String ifEmpty(String Function() alt) => isEmpty ? alt() : this;
}
