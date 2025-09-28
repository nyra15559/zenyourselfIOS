// lib/services/guidance_service.dart
//
// ZenYourself — Guidance / Coaching Service (PANDA-REFLECT-12.1)
// Facade über core/ApiService mit UI-freundlicher Normalisierung
// -----------------------------------------------------------------------------
// Ziele:
// 1) UI erhält NUR "answer_helpers" (hier aus Turn-Followups gemappt, bis Worker 12.1 helpers liefert)
// 2) Frage unterdrücken, wenn flow.mood_prompt/recommend_end aktiv
// 3) Ruhige Bubbles – Service erzwingt nichts, liefert nur Worker-Daten
// 4) Fester Footer-Disclaimer
// 5) Risk-Mapping mild/high → risk=true
// 6) Session passthrough
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

  /// Legacy-Start (Kompatibilität für ältere Call-Sites)
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

  /// Start einer v12-Reflexionsrunde
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

  /// Fortsetzung einer bestehenden Reflexion
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
  // Normalisierung → UI-freundliches JSON
  // ---------------------------------------------------------------------------
  Json _turnToJson(ReflectionTurn t) {
    final flow = t.flow ??
        const ReflectionFlow(
          recommendEnd: false,
          suggestBreak: false,
        );

    final flowMap = flow.toJson();
    final bool shouldPromptMood =
        (flowMap['mood_prompt'] == true) || (flow.recommendEnd == true);

    // `output_text` NICHT übernehmen, wenn es dem Fehlertext entspricht.
    final outputIsOk =
        t.outputText.trim().isNotEmpty && t.outputText != ApiService.errorHint;

    // Risk-Mapping: crisis→high, support→mild, sonst none
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

    // UI soll nur "answer_helpers" bekommen (hier aus followups gemappt).
    final List<String> answerHelpersOut =
        (t.followups is List<String>) ? List<String>.from(t.followups) : const [];

    return <String, dynamic>{
      if (t.mirror != null) 'mirror': t.mirror,
      if (!shouldPromptMood && t.primaryQuestion != null)
        'question': t.primaryQuestion,
      if (answerHelpersOut.isNotEmpty) 'answer_helpers': answerHelpersOut,
      if (outputIsOk) 'output_text': t.outputText,
      if (t.talk.isNotEmpty) 'talk': t.talk,
      if (t.tags.isNotEmpty) 'tags': t.tags,
      if (t.context.isNotEmpty) 'context': t.context,
      'session': t.session.toJson(),
      'risk_level': riskLevelOut,
      'risk': riskLevelOut == 'high' || riskLevelOut == 'mild',
      'flow': flowMap,
      'disclaimer': kFooterDisclaimer,
    };
  }
}
