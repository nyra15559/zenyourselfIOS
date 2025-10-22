// lib/services/guidance_service.dart
//
// ZenYourself — Guidance / Coaching Service (PANDA-REFLECT-12.6)
// -----------------------------------------------------------------------------
// Fassade über core/ApiService mit UI-freundlicher Normalisierung.
// Garantien / Verhalten:
// • UI erhält NUR answer_helpers (max. 3, sanitisiert). Interner Fallback auf
//   followups, aber diese werden NICHT an die UI zurückgereicht.
// • Mindestens 2 Answer-Chips: Liefert der Worker nur 1, ergänzt der Service
//   sanft einen zweiten generischen Starter („Wichtig ist mir außerdem“).
// • Zusätzlich answer_helpers_insert: Variante zum direkten Einfügen ins Textfeld
//   (ohne „…“, ohne Satzzeichen, ohne Auto-Send).
// • Chips sind Insert-only, persistieren bis User-Interaktion, werden NICHT
//   inline als Chat-Bubble gerendert (composer_only).
// • Frage wird unterdrückt, wenn flow.mood_prompt bzw. recommend_end aktiv ist.
// • Ruhiger Ton: Mirror wird von Instruktionssätzen befreit; reine Frage ≠ Mirror.
// • Risk-Mapping {none|mild|high}; risk=true bei mild/high.
// • Session passthrough; Legacy-Keys werden robust behandelt.
// • Footer-Disclaimer wird immer durchgereicht.
// • recentTopics()/recentHelpers(): liefern bewusst leere Listen
//   (Themenchips laufen „nur im Background“ / UI zeigt nichts).
//
// Hinweis: Dieser Service ruft NUR Methoden, die in ApiService vorhanden sind.
// Keine harte Abhängigkeit auf entfernte/optionale ApiService-Methoden.
//

library guidance_service;

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'core/api_service.dart';
import 'guidance/dtos.dart';

// Memory-Fassade (für UI-Bridge/Hope & optionalen Debug-Hint)
import '../core/memory/memory_service.dart' as mem;

typedef Json = Map<String, dynamic>;

class GuidanceService {
  GuidanceService._();
  static final GuidanceService instance = GuidanceService._();

  static const String kOfflineError =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';
  static const String kFooterDisclaimer =
      'Dies ist keine Therapie, sondern eine mentale Begleitungs-App.';

  // Sanfter, universeller Fallback-Text für den 2. Chip
  static const String _kFallbackChipSeed = 'Wichtig ist mir außerdem';

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

  Future<bool> health() => ApiService.instance.healthCheck();

  // ---------------------------------------------------------------------------
  // Reflect / Session
  // ---------------------------------------------------------------------------

  /// Legacy-Start (Kompatibilität).
  Future<Json> startSession({
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    Map<String, dynamic>? clientContext, // bleibt toleriert, derzeit ungenutzt
  }) async {
    final turn = await ApiService.instance.startSessionFull(
      text: text,
      session: null,
      locale: locale,
      tz: tz,
      maxTurns: maxTurns,
      history: history,
    );
    return _turnToJson(turn);
  }

  /// Start einer v12-Runde (voll).
  Future<Json> startSessionFull({
    required String text,
    ReflectionSession? session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
  }) async {
    final turn = await ApiService.instance.startSessionFull(
      text: text,
      session: session,
      locale: locale,
      tz: tz,
      maxTurns: maxTurns,
      history: history,
    );
    return _turnToJson(turn);
  }

  /// Fortsetzung (voll).
  Future<Json> nextTurnFull({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
  }) async {
    final turn = await ApiService.instance.nextTurnFull(
      session: session,
      text: text,
      locale: locale,
      tz: tz,
      history: history,
    );
    return _turnToJson(turn);
  }

  /// Shim für alte Call-Sites.
  Future<Json> reflectFull({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
  }) async {
    final turn = await ApiService.instance.nextTurnFull(
      session: session,
      text: text,
      locale: locale,
      tz: tz,
    );
    return _turnToJson(turn);
  }

  /// Smalltalk / „Ich will nur erzählen“ (talkOnly-Pfad).
  Future<Json> talk({
    required ReflectionSession session,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
  }) async {
    final turn = await ApiService.instance.talk(
      session: session,
      userText: userText,
      locale: locale,
      tz: tz,
      history: history,
    );
    return _turnToJson(turn);
  }

  // ---------------------------------------------------------------------------
  // Closure / Mood-Intro
  // ---------------------------------------------------------------------------
  Future<Json> closureFull({
    required ReflectionSession? session,
    required String answer,
    String locale = 'de',
    String tz = 'Europe/Zurich',
  }) async {
    try {
      final res = await ApiService.instance.closureFull(
        session: session,
        answer: answer,
        locale: locale,
        tz: tz,
      );
      final norm = _normalizeClosureResponse(res);
      return {
        ...norm,
        'disclaimer': kFooterDisclaimer,
      };
    } on NoSuchMethodError {
      // Sehr alte Builds: minimaler Fallback
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
        'disclaimer': kFooterDisclaimer,
      };
    } catch (_) {
      // Netz/Worker-Fehler: minimal
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

  /// Liefert deduplizierte Top-Themen aus dem lokalen Memory (für Bridge/Hope).
  /// *Kein* Einfluss auf den Worker — der `context_hint` wird bereits im ApiService
  /// automatisch mitgeschickt.
  Future<List<String>> recallTopics({int limit = 6, String? topicHint}) async {
    try {
      // Signatur-tolerant: nur limit übergeben; optional nachträglich filtern.
      final items = await mem.MemoryService.instance.recall(limit: limit);

      final out = <String>[];
      String topicOf(dynamic it) {
        // tolerant gegenüber Map, DTO, toJson()
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

  /// Optionaler Debug-/Telemetry-Helfer: Gibt den aktuellen Kontext-Hint
  /// (die kompakte Payload) so zurück, wie er an den Worker gesendet wird.
  /// Praktisch für Logs oder A/B-Checks – UI nutzt das nicht direkt.
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

      // tolerant: Feldnamen wie in MemoryContextHint (facets/tags/topics)
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

  /// Themen-Starter: aktuell leer lassen (UI zeigt nichts an).
  Future<List<String>> recentTopics({int limit = 6}) async => <String>[];

  /// Letzte Answer-Chips: aktuell leer lassen (UI optional).
  Future<List<String>> recentHelpers({int limit = 3}) async => <String>[];

  // ---------------------------------------------------------------------------
  // Helpers (Sanitizer / Normalisierung)
  // ---------------------------------------------------------------------------

  /// Extrahiert & säubert Answer-Chips (max. 3). Fallback auf followups (intern).
  /// ACHTUNG: Mindestens 2 Chips sicherstellen (Service-seitig).
  List<String> _extractAnswerHelpers(ReflectionTurn t) {
    final primary = t.answerHelpers;
    final legacy = t.followups;
    final candidates = primary.isNotEmpty ? primary : legacy;

    final out = <String>[];
    for (final f in candidates) {
      final cleaned = _cleanChipForDisplay(f);
      if (cleaned.isNotEmpty) out.add(cleaned);
      if (out.length >= 3) break;
    }

    if (out.length == 1) {
      // Sanfter zweiter Starter (Display-Variante mit „…“)
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
      RegExp(r'^\s*Unten\s+findest\s+du\s+Antwort[-\s]?Chips.*$', caseSensitive: false, multiLine: true),
      RegExp(r'^\s*Unter\s+dem\s+Eingabefeld\s+findest\s+du\s+Antwort.*$', caseSensitive: false, multiLine: true),
      RegExp(r'^\s*Wähle\s+einen\s+Antwort[-\s]?Chip.*$', caseSensitive: false, multiLine: true),
      RegExp(r'you\s+can\s+use\s+the\s+answer\s+chips.*', caseSensitive: false, dotAll: true),
      RegExp(r"below\s+you'll\s+find\s+answer\s+chips.*", caseSensitive: false, dotAll: true),
      RegExp(r'antworte\s+in\s+\d+\s*(?:bis|–|-)\s*\d+\s*sätz', caseSensitive: false, dotAll: true),
    ];
    for (final p in patterns) {
      text = text.replaceAll(p, '').trim();
    }

    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (text.endsWith('?')) return null; // reine Frage ≠ Mirror
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> _normalizeClosureResponse(Map<String, dynamic> src) {
    Map<String, dynamic> m(dynamic x) =>
        (x is Map<String, dynamic>) ? x : (x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{});

    final flow = m(src['flow']);
    final closure = m(src['closure']);
    final moodIntro = m(closure['mood_intro']);

    return {
      ...src,
      'flow': {
        ...flow,
        'mood_prompt': flow['mood_prompt'] == true || flow['recommend_end'] == true,
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

  // ---------------------------------------------------------------------------
  // Normalisierung → UI-freundliches JSON
  // ---------------------------------------------------------------------------
  Json _turnToJson(ReflectionTurn t) {
    final ReflectionFlow flow =
        t.flow ?? const ReflectionFlow(recommendEnd: false, suggestBreak: false);

    final flowJson = flow.toJson();
    final flowOut = <String, dynamic>{
      ...flowJson,
      'mood_prompt': (flowJson['mood_prompt'] == true) || (flow.recommendEnd == true),
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

    // Primäre Frage (falls vorhanden)
    final String? primaryQuestion =
        (t.questions.isNotEmpty) ? t.questions.first : null;

    // Facetten: wir nutzen t.tags als thematische Facetten
    final List<String> facets =
        t.tags.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // Chips (Display & Insert) — mind. 2 sicherstellen
    List<String> answerHelpersDisplay = _extractAnswerHelpers(t);
    List<String> answerHelpersInsert =
        answerHelpersDisplay.map(_cleanChipForInsert).where((e) => e.isNotEmpty).toList(growable: false);
    if (answerHelpersDisplay.length == 1) {
      // identischen Fallback in beide Varianten einfügen
      final fbDisplay = _cleanChipForDisplay(_kFallbackChipSeed);
      final fbInsert  = _cleanChipForInsert(_kFallbackChipSeed);
      answerHelpersDisplay = [...answerHelpersDisplay, fbDisplay];
      answerHelpersInsert  = [...answerHelpersInsert,  fbInsert];
    }

    // Chip-Typ nur als Stil-Hinweis
    final String chipType = _inferChipType(primaryQuestion, t.tags);

    // Stabile Chip-Set-ID (inkl. finaler Display-Chips)
    final sessMap = t.session.toJson();
    final sid = (sessMap['thread_id'] ?? sessMap['id'] ?? '').toString();
    final sturn = (sessMap['turn_index'] ?? sessMap['turn'] ?? 0).toString();
    final chipSetId = '$sid:$sturn:${answerHelpersDisplay.join("|").hashCode}';

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

    // insight_score (falls vorhanden)
    final dynamic maybeInsight = flowJson['insight_score'];
    if (maybeInsight is num) {
      map['insight_score'] = maybeInsight;
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
    if (t.outputText.trim().isNotEmpty && t.outputText != ApiService.errorHint) {
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
    // NEW: helper_suggestion aus Worker durchreichen (Screen zeigt sie nahe der Frage)
    final hs = (t.helperSuggestion ?? '').trim();
    if (hs.isNotEmpty) {
      map['helper_suggestion'] = hs;
    }

    return map;
  }

  // Nur Stil-Hinweis
  String _inferChipType(String? question, List<String> tags) {
    final q = (question ?? '').toLowerCase();
    if (q.contains('kleine option') || (q.contains('kurz') && q.contains('ausprobieren'))) {
      return 'tips';
    }
    if (tags.any((t) => t.toLowerCase().contains('tip') || t.toLowerCase().contains('übung'))) {
      return 'tips';
    }
    return 'reflect';
  }
}
