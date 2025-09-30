// lib/services/guidance_service.dart
//
// ZenYourself — Guidance / Coaching Service (PANDA-REFLECT-12.2)
// Facade über core/ApiService mit UI-freundlicher Normalisierung
// -----------------------------------------------------------------------------
// Checkliste / Ziele dieses Moduls
// ✅ UI erhält NUR "answer_helpers" (max 3, sanitisiert). Fallback intern aus
//    followups, wenn helpers leer sind. UI selbst sieht keine followups.
// ✅ Frage wird unterdrückt, wenn flow.mood_prompt/recommend_end aktiv.
// ✅ Ruhige Bubbles – Service erzwingt nichts; liefert nur Worker-Daten.
// ✅ Fester Footer-Disclaimer wird immer durchgereicht.
// ✅ Risk-Mapping: {none|mild|high}; risk = true bei mild/high.
// ✅ Session passthrough (threadId/turnIndex usw. bleiben erhalten).
// ✅ Sanfte Fallbacks auf ältere Worker (v12.1 / legacy keys).
// ✅ Keine Breaking Changes an Journal/Provider; reiner UI-Service.
// -----------------------------------------------------------------------------

library guidance_service;

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

// *** WICHTIG: korrekte relative Imports, weil diese Datei in lib/services/ liegt ***
import 'core/api_service.dart';
import 'guidance/dtos.dart';

typedef Json = Map<String, dynamic>;

class GuidanceService {
  GuidanceService._();
  static final GuidanceService instance = GuidanceService._();

  /// Einheitlicher Offline-/Fehlertext.
  static const String kOfflineError =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';

  /// Footer-Disclaimer (UI blendet diesen unten permanent ein).
  static const String kFooterDisclaimer =
      'Dies ist keine Therapie, sondern eine mentale Begleitungs-App.';

  /// Kurzer Transport-/Fehlerhinweis (durchgereicht aus ApiService).
  String get errorHint => ApiService.errorHint;

  // ---------------------------------------------------------------------------
  // HTTP/Worker-Setup
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

  // ---------------------------------------------------------------------------
  // Health
  // ---------------------------------------------------------------------------
  Future<bool> health() => ApiService.instance.healthCheck();

  // ---------------------------------------------------------------------------
  // Reflect / Session
  // ---------------------------------------------------------------------------

  /// Legacy-Start (Kompatibilität für ältere Call-Sites).
  Future<Json> startSession({
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    Map<String, dynamic>? clientContext,
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

  /// Start einer v12-Reflexionsrunde.
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

  /// Fortsetzung einer bestehenden Reflexion.
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

  /// Fallback-Shim für alte Call-Sites, die `reflectFull` aufrufen.
  /// Ruft intern `nextTurnFull` auf.
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
      // Disclaimer ergänzen, ohne Struktur zu verändern
      return {
        ...res,
        'disclaimer': kFooterDisclaimer,
      };
    } on NoSuchMethodError {
      // Sanfter Fallback für sehr alte Builds
      return <String, dynamic>{
        'flow': {
          'recommend_end': true,
          'mood_prompt': true,
        },
        if (session != null) 'session': session.toJson(),
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
  // Helpers (Sanitizer / Normalisierung)
  // ---------------------------------------------------------------------------

  /// Extrahiert und säubert Antwort-Chips (max 3) – bevorzugt `answer_helpers`,
  /// Fallback auf `followups`, wenn leer/fehlend (nur intern, UI sieht followups nicht).
  List<String> _extractAnswerHelpers(ReflectionTurn t) {
    final List<String> primary = t.answerHelpers;
    final List<String> legacy = t.followups;
    final List<String> candidates = primary.isNotEmpty ? primary : legacy;

    final out = <String>[];
    for (final f in candidates) {
      final cleaned = _cleanChip(f);
      if (cleaned.isNotEmpty) out.add(cleaned);
      if (out.length >= 3) break;
    }
    return out;
  }

  String _cleanChip(String s) {
    var x = s.trim();
    // En-dash, Minus, Bullet, Whitespace
    x = x.replaceAll(RegExp(r'^[\u2013\-\u2022\s]+'), '');
    // Anführungen (Deutsch/Franz/Single/Double) — KEIN raw string wegen '
    x = x.replaceAll(RegExp("^[\\u201E\"'\\u203A\\u2039\\u00AB\\u00BB]+"), '');
    // Satz-Endzeichen
    x = x.replaceAll(RegExp(r'\s*[\?\!\.]+$'), '');
    // Innenräume normalisieren
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Länge weich begrenzen
    if (x.length > 72) x = x.substring(0, 72).trimRight() + '...';
    return x;
  }

  /// Entfernt Instruktionssätze aus dem Mirror (z. B. Chip-Hinweis).
  String? _cleanMirror(String? mirror) {
    if (mirror == null) return null;
    var text = mirror.trim();

    // ASCII/Unicode-sichere Patterns (keine raw-Strings mit Apostroph)
    final patterns = <RegExp>[
      RegExp(r'^\s*Unten\s+findest\s+du\s+Antwort[-\s]?Chips.*$', caseSensitive: false, multiLine: true),
      RegExp(r'^\s*Unter\s+dem\s+Eingabefeld\s+findest\s+du\s+Antwort.*$', caseSensitive: false, multiLine: true),
      RegExp(r'^\s*Waehle\s+einen\s+Antwort[-\s]?Chip.*$', caseSensitive: false, multiLine: true),
      RegExp(r'you\s+can\s+use\s+the\s+answer\s+chips.*', caseSensitive: false, dotAll: true),
      RegExp("below\\s+you'll\\s+find\\s+answer\\s+chips.*", caseSensitive: false, dotAll: true),
      // Deutsche Variante ohne Umlaut (saetz statt sätz), Bindestrich optional
      RegExp(r'antworte\s+in\s+\d+\s*-?\s*\d+\s*saetz', caseSensitive: false, dotAll: true),
    ];
    for (final p in patterns) {
      text = text.replaceAll(p, '').trim();
    }

    // Mehrere Leerzeilen normalisieren
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    // Kein Mirror, wenn es eigentlich eine reine Frage ist
    if (text.endsWith('?')) return null;

    return text.isEmpty ? null : text;
  }

  // ---------------------------------------------------------------------------
  // Normalisierung -> UI-freundliches JSON
  // ---------------------------------------------------------------------------
  Json _turnToJson(ReflectionTurn t) {
    final ReflectionFlow flow = t.flow ??
        const ReflectionFlow(
          recommendEnd: false,
          suggestBreak: false,
        );
    final Map<String, dynamic> flowMap = flow.toJson();

    final bool shouldPromptMood =
        (flowMap['mood_prompt'] == true) || (flow.recommendEnd == true);

    // kompatibel auch wenn outputText non-nullable ist
    final String output = t.outputText;
    final bool outputIsOk =
        output.trim().isNotEmpty && output != ApiService.errorHint;

    // Risk-Mapping
    String riskLevelOut;
    switch (t.riskFlag) {
      case 'crisis':
        riskLevelOut = 'high';
        break;
      case 'support':
        riskLevelOut = 'mild';
        break;
      default:
        riskLevelOut = 'none';
    }

    final List<String> answerHelpersOut = _extractAnswerHelpers(t);
    final String? cleanedMirror = _cleanMirror(t.mirror);

    // kein Control-Flow im Map-Literal -> maximal kompatibel
    final map = <String, dynamic>{
      'session': t.session.toJson(),
      'risk_level': riskLevelOut,
      'risk': riskLevelOut == 'high' || riskLevelOut == 'mild',
      'flow': flowMap,
      'disclaimer': kFooterDisclaimer,
    };

    if (cleanedMirror != null) {
      map['mirror'] = cleanedMirror;
    }
    if (!shouldPromptMood && t.primaryQuestion != null) {
      map['question'] = t.primaryQuestion;
    }
    if (answerHelpersOut.isNotEmpty) {
      map['answer_helpers'] = answerHelpersOut;
    }
    if (outputIsOk) {
      map['output_text'] = output;
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

    return map;
  }
}
