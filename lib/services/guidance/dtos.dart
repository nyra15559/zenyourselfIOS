//[BASELINE] lib/services/guidance/dtos.dart (Stand: 29.10.)
// lib/services/guidance/dtos.dart
//
// DTOs & Value-Types für Guidance-Service (standalone, ohne Api-Abhängigkeit)
// ────────────────────────────────────────────────────────────────────────────
// • Keine externen Abhängigkeiten
// • Defensive Defaults (tolerante fromMaybe-Factories)
// • Snake_case-Shims für UI-/API-Kompatibilität
// • v12.5-Alignment: bevorzugte Felder für answer_helpers, talk[],
//   flow.mood_prompt; optional helper_suggestion (tolerant gelesen & serialisiert)
// • v6.2.1: UserAction {type, note}, topic_suggestions (Top-Level),
//   analysis (TurnAnalysis: summary/topic/insight_score/topic_suggestions)
// • v6.2.2: Enums für Actions (ActionType) + Wire-Feld 'action_type' (optional),
//   volle Abwärtskompatibilität via 'type' (String) beibehalten.
// • v6.3.1: Kleinere Robustheits-Updates, Session-Snake-Case-Shims in toJson
// • v6.3.2: Mehr Toleranz beim Einlesen (ui/flow.helper_suggestion, smalltalk_reply,
//           Session-Int aus String; Flow: mood { prompt: true }; risk: 'level')
// • v6.3.3: String→Liste-Split verbessert („;“ auch ohne Leerraum), optional
//           speech_sequence (für Hope-Kompat) tolerant mitgeführt
// • v6.4.1: **Neue Felder** für Plan-Punkt 8
//   – memories_to_save[] (tolerant als List<dynamic>)
//   – understanding { topic_shift } (tolerant gelesen + in toJson geführt)
//   – closure{ mood_intro.text, hope_reply, closure_prompt, mode?, reason?, tone? } DTO
//   – insight_score weiterhin in TurnAnalysis (Top-Level passthrough möglich)
//
// Mini-Checkliste (Pflichtenheft A/5):
// [x] ReflectionTurn.answerHelpers vorhanden (Default [])
// [x] ReflectionFlow.moodPrompt / recommendEnd enthalten
// [x] Tolerantes snake_case/legacy-Parsing (inkl. Aliasse & verschachtelte Felder)
// [x] Helpers: geordnete Deduplizierung, max 3, keine Fragen („?“)
// [x] Session passthrough robust (id/turn/max_turns Aliasse)
// [x] helper_suggestion als optionales Feld vorhanden (DTO ↔ JSON)
// [x] UserAction DTO vorhanden (String+Enum, rückwärtskompatibel)
// [x] topic_suggestions + analysis vorhanden, tolerant gelesen
// [x] memories_to_save[] vorhanden, tolerant
// [x] understanding.topic_shift vorhanden, tolerant
// [x] ClosureData DTO vorhanden

/// ───────────────────────────────────────────────────────────────────────────
/// AnalyzeResult (Legacy – optional genutzt)
/// ───────────────────────────────────────────────────────────────────────────
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
        const Analysis(
          sorc: null,
          levers: [],
          mirror: null,
          question: null,
          riskLevel: null,
        );
    final challenge = MiniChallenge.fromMaybe(json['challenge']);
    return AnalyzeResult(analysis: analysis, challenge: challenge);
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// ActionType Enum (v6.2.2)
/// ───────────────────────────────────────────────────────────────────────────
enum ActionType {
  reflectionLink,
  journalLink,
  storyLink,
  save,
  skip,
  changeTopic,
  unknown,
}

extension ActionTypeWire on ActionType {
  String get wire {
    switch (this) {
      case ActionType.reflectionLink:
        return 'reflection_link';
      case ActionType.journalLink:
        return 'journal_link';
      case ActionType.storyLink:
        return 'story_link';
      case ActionType.save:
        return 'save';
      case ActionType.skip:
        return 'skip';
      case ActionType.changeTopic:
        return 'change_topic';
      case ActionType.unknown:
        return 'unknown';
    }
  }

  static ActionType parse(dynamic v) {
    final s = v?.toString().toLowerCase().trim() ?? '';
    switch (s) {
      case 'reflection_link':
      case 'reflectionlink':
        return ActionType.reflectionLink;
      case 'journal_link':
      case 'journallink':
        return ActionType.journalLink;
      case 'story_link':
      case 'storylink':
        return ActionType.storyLink;
      case 'save':
        return ActionType.save;
      case 'skip':
        return ActionType.skip;
      case 'change_topic':
      case 'change-topic':
      case 'changetopic':
      case 'change':
        return ActionType.changeTopic;
      default:
        return ActionType.unknown;
    }
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// UserAction — vom UI gesendete Aktion (v6.2.2-enum + Backcompat)
/// ───────────────────────────────────────────────────────────────────────────
class UserAction {
  /// Wire-String für Rückwärtskompatibilität (z. B. "journal_link")
  final String type;

  /// Optionales Enum (neu v6.2.2). Tolerant aus type/action/action_type geparst.
  final ActionType actionType;

  /// Freitext-Notiz (optional, kurz halten)
  final String? note;

  const UserAction({
    required this.type,
    this.actionType = ActionType.unknown,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        // Beides mitsenden: 'type' (Legacy) + 'action_type' (Enum-Wire)
        'type': type,
        'action_type': actionType.wire,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      };

  static UserAction? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final rawType =
        (m['type'] ?? m['action'] ?? m['action_type'] ?? '').toString().trim();
    if (rawType.isEmpty) return null;
    final enumType =
        ActionTypeWire.parse(m['action_type'] ?? m['type'] ?? m['action']);
    final note = (m['note'] ?? m['text'] ?? m['message'])?.toString();
    return UserAction(
      type: rawType,
      actionType: enumType,
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    );
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// TurnAnalysis — strukturierte Analyse der Worker-Antwort (Phase 4)
/// ───────────────────────────────────────────────────────────────────────────
class TurnAnalysis {
  final String? summary; // kurze Zusammenfassung / Kernbeobachtung
  final String? topic; // erkannter Schwerpunkt (z. B. "Arbeit", "Familie")
  final double? insightScore; // 0..1 (optional)
  final List<String> topicSuggestions; // Themenvorschläge / Redirect-Ideen

  const TurnAnalysis({
    this.summary,
    this.topic,
    this.insightScore,
    this.topicSuggestions = const <String>[],
  });

  Map<String, dynamic> toJson() => {
        if ((summary ?? '').trim().isNotEmpty) 'summary': summary!.trim(),
        if ((topic ?? '').trim().isNotEmpty) 'topic': topic!.trim(),
        if (insightScore != null) 'insight_score': insightScore,
        if (topicSuggestions.isNotEmpty) 'topic_suggestions': topicSuggestions,
      };

  static TurnAnalysis? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);

    double? asDouble(dynamic x) {
      if (x is num) return x.toDouble();
      final s = x?.toString();
      if (s == null) return null;
      return double.tryParse(s);
    }

    final summary = m['summary']?.toString();
    final topic = (m['topic'] ?? m['focus'] ?? m['theme'])?.toString();
    final insight = asDouble(m['insight_score'] ?? m['insightScore']);
    final topics = _strings([
      m['topic_suggestions'],
      m['topicSuggestions'],
      m['topics'],
      m['redirect_suggestions'],
    ]);

    // sanfte Deduplizierung (stabile Reihenfolge)
    final dedup = _orderedDedup(topics);

    return TurnAnalysis(
      summary: (summary?.trim().isEmpty ?? true) ? null : summary!.trim(),
      topic: (topic?.trim().isEmpty ?? true) ? null : topic!.trim(),
      insightScore: insight,
      topicSuggestions: dedup,
    );
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// ClosureData — DTO für closure_full-Antworten (Plan-Punkt 8)
/// ───────────────────────────────────────────────────────────────────────────
class ClosureData {
  final String moodIntroText; // closure.mood_intro.text
  final String hopeReply; // closure.hope_reply
  final String closurePrompt; // closure.closure_prompt

  /// Optionale Meta-Felder (können vom Worker kommen)
  final String? mode; // z. B. "user_end" | "panda_end"
  final String? reason; // z. B. "insight_high" | "fatigue"
  final String? tone; // z. B. "hope" | "ritual" | "insight" | "light"

  const ClosureData({
    required this.moodIntroText,
    required this.hopeReply,
    required this.closurePrompt,
    this.mode,
    this.reason,
    this.tone,
  });

  Map<String, dynamic> toJson() => {
        'mood_intro': {'text': moodIntroText},
        'hope_reply': hopeReply,
        'closure_prompt': closurePrompt,
        if ((mode ?? '').trim().isNotEmpty) 'mode': mode!.trim(),
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
        if ((tone ?? '').trim().isNotEmpty) 'tone': tone!.trim(),
      };

  static ClosureData? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    Map<String, dynamic>? mm(dynamic x) => _asMap(x);

    final closure =
        mm(m['closure']) ?? m; // sowohl Top-Level als auch verschachtelt
    final moodIntro = mm(closure['mood_intro']) ?? const <String, dynamic>{};

    final text = (moodIntro['text'] ?? '').toString();
    final hope = (closure['hope_reply'] ?? '').toString();
    final prompt = (closure['closure_prompt'] ?? '').toString();

    if (text.isEmpty && hope.isEmpty && prompt.isEmpty) return null;

    return ClosureData(
      moodIntroText: text,
      hopeReply: hope,
      closurePrompt: prompt,
      mode: closure['mode']?.toString(),
      reason: closure['reason']?.toString(),
      tone: closure['tone']?.toString(),
    );
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// ReflectionTurn — Kernantwort eines Workers
/// ───────────────────────────────────────────────────────────────────────────
class ReflectionTurn {
  final String outputText; // Primärtext (Frage/Prompt)
  final String? mirror; // Empathische Spiegelung (optional)
  final List<String> context; // Hinweise/Aspekte (robust als Liste geführt)
  final List<String> followups; // kleine Nachfragen (KEINE Chips)
  final List<String> answerHelpers; // v12.2+: Echte Worker-Chips (Satzstarter)

  /// Optional: sanfter 0–1-Satz direkt unter der Leitfrage (Worker-Feld)
  final String? helperSuggestion;

  final ReflectionFlow? flow; // Flow-Metadaten/Flags
  final ReflectionSession session; // Session-Metadaten (immer vorhanden)
  final List<String> tags; // Themen/Tags
  final String riskFlag; // 'none' | 'support' | 'crisis'
  final List<String> questions; // gelieferte Fragen (roh)
  final List<String> talk; // talk-Zeilen

  /// NEU/optional: vollständige Sprecher-Sequenz (z. B. für Hope-Kompat)
  final List<dynamic> speechSequence;

  /// NEU: strukturierte Analyse + optionale Top-Level-Topic-Vorschläge
  final TurnAnalysis? analysis;
  final List<String> topicSuggestions;

  /// NEU (Plan-Punkt 8): Vorschläge, was lokal gespeichert werden könnte
  /// (vom Worker geliefert; App entscheidet nach Consent).
  final List<dynamic> memoriesToSave;

  /// NEU (Plan-Punkt 8): Hinweis des Workers auf Themenwechsel.
  final String? understandingTopicShift;

  const ReflectionTurn({
    required this.outputText,
    required this.mirror,
    required this.context,
    required this.followups,
    required this.answerHelpers,
    this.helperSuggestion,
    required this.flow,
    required this.session,
    required this.tags,
    required this.riskFlag,
    this.questions = const [],
    this.talk = const [],
    this.speechSequence = const <dynamic>[],
    this.analysis,
    this.topicSuggestions = const <String>[],
    this.memoriesToSave = const <dynamic>[],
    this.understandingTopicShift,
  });

  // Fallback-Fehlertext-Kopie, damit dtos.dart unabhängig bleibt
  static const String kErrorHintFallback =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';

  /// 'high' | 'mild' | 'none' (abgeleitet aus riskFlag)
  // ignore: non_constant_identifier_names
  String get risk_level => (riskFlag == 'crisis')
      ? 'high'
      : (riskFlag == 'support' ? 'mild' : 'none');

  /// true, wenn Unterstützung/Alarm signalisiert ist (Legacy-Shim)
  bool get risk => riskFlag == 'support' || riskFlag == 'crisis';

  /// Primäre Frage (falls vorhanden) mit garantiertem Fragezeichen.
  String? get primaryQuestion {
    if (questions.isNotEmpty) {
      final q = questions.first.trim();
      if (q.isNotEmpty) return q.endsWith('?') ? q : '$q?';
    }
    final t = outputText.trim();
    if (t.isNotEmpty && t.endsWith('?') && t != kErrorHintFallback) return t;
    return null;
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      if (outputText.trim() != kErrorHintFallback) 'output_text': outputText,
      if (primaryQuestion != null) 'question': primaryQuestion,
      if (mirror != null) 'mirror': mirror,
      if (context.isNotEmpty) 'context': context,
      if (followups.isNotEmpty) 'followups': followups,
      if (answerHelpers.isNotEmpty) 'answer_helpers': answerHelpers,
      if ((helperSuggestion ?? '').trim().isNotEmpty)
        'helper_suggestion': helperSuggestion!.trim(),
      'flow': flow?.toJson() ??
          const ReflectionFlow(recommendEnd: false, suggestBreak: false)
              .toJson(),
      'session': session.toJson(),
      if (tags.isNotEmpty) 'tags': tags,
      'risk_level': risk_level,
      if (risk) 'risk': true, // Legacy-Flag zusätzlich
      if (questions.isNotEmpty) 'questions': questions,
      if (talk.isNotEmpty) 'talk': talk,
      if (speechSequence.isNotEmpty)
        'speech_sequence': List<dynamic>.from(speechSequence),
      if (analysis != null) 'analysis': analysis!.toJson(),
      if (topicSuggestions.isNotEmpty) 'topic_suggestions': topicSuggestions,
      if (memoriesToSave.isNotEmpty)
        'memories_to_save': List<dynamic>.from(memoriesToSave),
    };

    // understanding.topic_shift nur senden, wenn vorhanden
    if ((understandingTopicShift ?? '').trim().isNotEmpty) {
      map['understanding'] = {
        'topic_shift': understandingTopicShift!.trim(),
      };
    }

    return map;
  }

  /// Tolerantes Einlesen (Map oder null). Defensive Defaults, keine Throws.
  static ReflectionTurn? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);

    Map<String, dynamic>? asMap(dynamic x) => _asMap(x);

    // evtl. verschachtelte Teilbäume
    final primary = asMap(m['primary']);
    final flowMap = asMap(m['flow']);
    final uiMap = asMap(m['ui']);

    // output / question(s)
    final outputText = (m['output_text'] ??
            m['outputText'] ??
            m['question'] ??
            m['primary_question'] ??
            _pickString(primary, const ['output_text', 'text', 'question']) ??
            _pickString(flowMap, const ['output_text', 'text', 'question']) ??
            '')
        .toString()
        .trim();

    // Fragen: mehrere mögliche Keys + verschachtelt
    final questions = _strings([
      m['questions'],
      m['qs'],
      m['multi_questions'],
      primary?['questions'],
      flowMap?['questions'],
    ]);

    // simple lists
    final context = _strings([m['context']]);
    final followups = _strings([m['followups']]);
    final talk = _strings([
      m['talk'],
      primary?['talk'],
      flowMap?['talk'],
      m['smalltalk_reply'], // v6.3.2+: tolerant
    ]);
    final tags = _strings([m['tags'], primary?['tags'], flowMap?['tags']]);

    // Chips aus verschiedenen Feldern tolerant einsammeln (geordnet deduplizieren, max 3)
    final helpersRaw = _strings(
      [
        m['answer_helpers'],
        m['answer_scaffolds'],
        m['answer_templates'],
        m['helpers'],
        m['chips'],
        m['answers'],
        asMap(m['ui'])?['answer_helpers'],
        asMap(m['ui'])?['chips'],
        flowMap?['answer_helpers'],
        flowMap?['helpers'],
        primary?['answer_helpers'],
        primary?['helpers'],
        // Optionen (selten)
        asMap(m['ui'])?['options'],
        flowMap?['options'],
        primary?['options'],
      ],
    )
        // echte Fragen rausfiltern
        .where((s) => s.isNotEmpty && !s.endsWith('?'))
        // sanfte Normalisierung: Doppelpunkte/Abschluss-Punkte weg
        .map((s) => s
            .replaceAll(RegExp(r'\s*[:：]\s*$'), '')
            .replaceAll(RegExp(r'[.。]+$'), '')
            .trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final answerHelpers = _orderedDedup(helpersRaw).take(3).toList();

    // helper_suggestion (tolerant; auch verschachtelt lesen)
    String? helperSuggestion() {
      final top =
          (m['helper_suggestion'] ?? m['helperSuggestion'])?.toString().trim();
      if ((top ?? '').isNotEmpty) return top;
      final fromPrimary =
          _pickString(primary, const ['helper_suggestion', 'helperSuggestion']);
      if ((fromPrimary ?? '').trim().isNotEmpty) return fromPrimary!.trim();
      final fromFlow =
          _pickString(flowMap, const ['helper_suggestion', 'helperSuggestion']);
      if ((fromFlow ?? '').trim().isNotEmpty) return fromFlow!.trim();
      final fromUi =
          _pickString(uiMap, const ['helper_suggestion', 'helperSuggestion']);
      if ((fromUi ?? '').trim().isNotEmpty) return fromUi!.trim();
      return null;
    }

    // risk: erlaubt bool 'risk' (→ support) ODER level-Strings / risk_flag
    String riskFlagFrom(
        dynamic levelDyn, dynamic riskDyn, dynamic riskFlagDyn) {
      // bool risk=true → 'support'
      if (riskDyn == true) return 'support';
      // direkte Flag-Übernahme (worker kann 'crisis'/'support' senden)
      final rf = riskFlagDyn?.toString().toLowerCase().trim();
      if (rf == 'crisis' || rf == 'support' || rf == 'none') return rf!;
      // Legacy/Level akzeptieren
      final levelCandidate = levelDyn ?? m['level'];
      final rl =
          (levelCandidate ?? riskDyn ?? 'none').toString().toLowerCase().trim();
      if (rl == 'high' || rl == 'crisis') return 'crisis';
      if (rl == 'mild' || rl == 'support' || rl == 'true') return 'support';
      return 'none';
    }

    final riskFlag = riskFlagFrom(m['risk_level'], m['risk'], m['risk_flag']);

    // analysis + topic_suggestions (Top-Level + innerhalb analysis)
    final turnAnalysis = TurnAnalysis.fromMaybe(m['analysis']);
    final topLevelTopicSugs =
        _strings([m['topic_suggestions'], m['topicSuggestions'], m['topics']]);

    // kombinieren & deduplizieren (stabile Reihenfolge)
    final allTopicSugs = <String>[
      ...topLevelTopicSugs,
      if (turnAnalysis != null) ...turnAnalysis.topicSuggestions,
    ];
    final tsDedup = _orderedDedup(allTopicSugs);

    // speech_sequence (optional)
    final speechSequence =
        _listDyn(m['speech_sequence'] ?? m['speechSequence']);

    // memories_to_save (Plan-Punkt 8) — tolerant sammeln (Top-Level & plan{})
    final memoriesToSave = _listDyn(
      m['memories_to_save'] ??
          m['memoriesToSave'] ??
          asMap(m['plan'])?['memories_to_save'] ??
          asMap(m['plan'])?['memoriesToSave'],
    );

    // understanding.topic_shift (Plan-Punkt 8)
    String? understandingTopicShift() {
      final u = asMap(m['understanding']) ?? const <String, dynamic>{};
      final s = (u['topic_shift'] ?? u['topicShift'] ?? u['shift'])
          ?.toString()
          .trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return ReflectionTurn(
      outputText: outputText.isEmpty ? kErrorHintFallback : outputText,
      mirror: (m['mirror']?.toString().trim().isNotEmpty ?? false)
          ? m['mirror'].toString()
          : _pickString(primary, const ['mirror']) ??
              _pickString(flowMap, const ['mirror']),
      context: context,
      followups: followups,
      answerHelpers: answerHelpers,
      helperSuggestion: helperSuggestion(),
      flow: ReflectionFlow.fromMaybe(m['flow']) ??
          ReflectionFlow.fromMaybe(primary?['flow']),
      session: ReflectionSession.fromMaybe(m['session']) ??
          ReflectionSession.fromMaybe(primary?['session']) ??
          const ReflectionSession(threadId: '', turnIndex: 0, maxTurns: 3),
      tags: tags,
      riskFlag: riskFlag,
      questions: questions,
      talk: talk,
      speechSequence: speechSequence,
      analysis: turnAnalysis,
      topicSuggestions: tsDedup,
      memoriesToSave: memoriesToSave,
      understandingTopicShift: understandingTopicShift(),
    );
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// ReflectionFlow
/// ───────────────────────────────────────────────────────────────────────────
class ReflectionFlow {
  final bool recommendEnd;
  final bool suggestBreak;
  final String? riskNotice;
  final int? sessionTurn;
  final bool talkOnly;
  final bool allowReflect;

  /// Optionaler Hinweis des Workers, dass jetzt explizit die Stimmung
  /// abgefragt werden darf/soll (UI-Gate).
  final bool moodPrompt;

  const ReflectionFlow({
    required this.recommendEnd,
    required this.suggestBreak,
    this.riskNotice,
    this.sessionTurn,
    this.talkOnly = false,
    this.allowReflect = true,
    this.moodPrompt = false,
  });

  Map<String, dynamic> toJson() => {
        'recommend_end': recommendEnd,
        'suggest_break': suggestBreak,
        if (riskNotice != null) 'risk_notice': riskNotice,
        if (sessionTurn != null) 'session_turn': sessionTurn,
        if (talkOnly) 'talk_only': true,
        'allow_reflect': allowReflect,
        if (moodPrompt) 'mood_prompt': true,
      };

  /// Tolerante Factory, falls der Worker (oder ein Fallback) eine Flow-Map liefert.
  static ReflectionFlow? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);

    // v6.3.2+: verschachteltes mood.prompt erkennen
    bool moodPromptNested() {
      final mood = _asMap(m['mood']);
      if (mood == null) return false;
      final p = mood['prompt'];
      if (p is bool) return p;
      if (p is String) {
        final s = p.trim().toLowerCase();
        return s == 'true' || s == '1' || s == 'yes' || s == 'y';
      }
      return false;
    }

    int? asInt(dynamic x) {
      if (x is num) return x.toInt();
      if (x is String) return int.tryParse(x.trim());
      return null;
    }

    return ReflectionFlow(
      recommendEnd: m['recommend_end'] == true || m['end'] == true,
      suggestBreak: m['suggest_break'] == true || m['break'] == true,
      riskNotice: m['risk_notice']?.toString(),
      sessionTurn: asInt(m['session_turn']),
      talkOnly: m['talk_only'] == true,
      allowReflect: m['allow_reflect'] != false,
      moodPrompt: m['mood_prompt'] == true ||
          m['moodPrompt'] == true ||
          moodPromptNested(),
    );
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// ReflectionSession
/// ───────────────────────────────────────────────────────────────────────────
class ReflectionSession {
  final String threadId;
  final int turnIndex;
  final int maxTurns;

  const ReflectionSession({
    required this.threadId,
    required this.turnIndex,
    required this.maxTurns,
  });

  ReflectionSession copyWith(
          {String? threadId, int? turnIndex, int? maxTurns}) =>
      ReflectionSession(
        threadId: threadId ?? this.threadId,
        turnIndex: turnIndex ?? this.turnIndex,
        maxTurns: maxTurns ?? this.maxTurns,
      );

  Map<String, dynamic> toJson() => {
        // Wichtig: 'id' + 'turn' für Kompatibilität (reflection_screen / guidance_service)
        // Zusätzlich snake_case Shims für robustes Passthrough (v6.3.1)
        'id': threadId,
        'thread_id': threadId,
        'turn': turnIndex,
        'turn_index': turnIndex,
        'max_turns': maxTurns,
      };

  static ReflectionSession? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);

    int _intOf(dynamic x, int fallback) {
      if (x is num) return x.toInt();
      if (x is String) {
        final p = int.tryParse(x.trim());
        if (p != null) return p;
      }
      return fallback;
    }

    final id = (m['id'] ?? m['thread_id'] ?? m['threadId'] ?? '').toString();
    final turn = _intOf(
      m['turn'] ?? m['turn_index'] ?? m['turnIndex'],
      0,
    );
    final max = _intOf(
      m['max_turns'] ?? m['maxTurns'],
      3,
    );
    return ReflectionSession(threadId: id, turnIndex: turn, maxTurns: max);
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// Weitere Value-Types
/// ───────────────────────────────────────────────────────────────────────────
class JourneyInsights {
  final List<String> insights; // 3–6 Beobachtungen oder Fehlerhinweis
  final String question; // Leitfrage oder Lade-/Fehlerhinweis

  const JourneyInsights({required this.insights, required this.question});

  Map<String, dynamic> toJson() => {
        'insights': insights,
        'question': question,
      };

  static JourneyInsights? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final insights = _strings([m['insights']]);
    final q = (m['question'] ?? '').toString();
    if (insights.isEmpty && q.trim().isEmpty) return null;
    return JourneyInsights(insights: insights, question: q);
  }
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
      bullets: bulletsDyn
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      coreIdea: (json['core_idea'] ?? '').toString(),
      moodHint: json['mood_hint']?.toString(),
      nextSteps: nsDyn
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      source: (json['source'] ?? 'server').toString(),
    );
  }
}

class JourneyEntry {
  final String dateIso; // YYYY-MM-DD
  final String? moodLabel; // z. B. "Gut" | null
  final String text; // Rohtext (PII wird serverseitig/heuristisch reduziert)

  const JourneyEntry(
      {required this.dateIso, required this.text, this.moodLabel});
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

  const StoryResult({
    required this.id,
    required this.title,
    required this.body,
    this.audioUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        if (audioUrl != null) 'audio_url': audioUrl,
      };

  static StoryResult? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final id = (m['id'] ?? '').toString();
    final title = (m['title'] ?? '').toString();
    final body = (m['story'] ?? m['body'] ?? '').toString();
    final audio = (m['audio'] ?? m['audio_url'])?.toString();
    if (id.isEmpty && title.isEmpty && body.isEmpty) return null;
    return StoryResult(
      id: id,
      title: title,
      body: body,
      audioUrl: (audio?.trim().isEmpty ?? true) ? null : audio!.trim(),
    );
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// Platzhalter-/Hilfstypen (Legacy)
// ───────────────────────────────────────────────────────────────────────────
class Analysis {
  final Object? sorc;
  final List<Object?> levers;
  final String? mirror;
  final String? question;
  final String? riskLevel;

  const Analysis({
    this.sorc,
    required this.levers,
    this.mirror,
    this.question,
    this.riskLevel,
  });

  Map<String, dynamic> toJson() => {
        'sorc': sorc,
        'levers': levers,
        'mirror': mirror,
        'question': question,
        'riskLevel': riskLevel,
      };

  static Analysis? fromMaybe(dynamic v) {
    if (v is Map<String, dynamic>) {
      return Analysis(
        sorc: v['sorc'],
        levers: ((v['levers'] as List?) ?? const []).toList(),
        mirror: v['mirror']?.toString(),
        question: v['question']?.toString(),
        riskLevel: v['riskLevel']?.toString(),
      );
    }
    return null;
  }
}

class MiniChallenge {
  final String id;
  final String title;
  final List<String> steps;

  const MiniChallenge({
    required this.id,
    required this.title,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'steps': steps};

  static MiniChallenge? fromMaybe(dynamic v) {
    if (v is Map<String, dynamic>) {
      final steps =
          ((v['steps'] as List?) ?? const []).map((e) => e.toString()).toList();
      return MiniChallenge(
        id: (v['id'] ?? '').toString(),
        title: (v['title'] ?? '').toString(),
        steps: steps,
      );
    }
    return null;
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// Kleine String-Extension
/// ───────────────────────────────────────────────────────────────────────────
extension IfEmptyX on String {
  String ifEmpty(String Function() alt) => isEmpty ? alt() : this;
}

/// ───────────────────────────────────────────────────────────────────────────
/// Interne, wiederverwendbare Parse-Helfer (keine Abhängigkeiten)
// ───────────────────────────────────────────────────────────────────────────

/// Führt mehrere dynamische Quellen zusammen und gibt eine getrimmte Liste
/// nicht-leerer Strings zurück. Unterstützt:
///  - List<dynamic>
///  - String (mit tolerantem Split auf Zeilen / Bulletpoints / Semikolons / Gedankenstriche)
///  - null (ignoriert)
List<String> _strings(dynamic many) {
  final out = <String>[];

  void addOne(dynamic x) {
    if (x == null) return;
    if (x is List) {
      for (final e in x) {
        addOne(e);
      }
      return;
    }
    final v = x.toString().trim();
    if (v.isEmpty) return;
    // tolerant splitten (Zeilen, Bulletpoints, Semikolons – auch ohne Leerraum)
    final parts = v
        .split(RegExp(r'\r?\n+|[•\-–—]\s+|\s*;\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      out.add(v);
    } else {
      out.addAll(parts);
    }
  }

  addOne(many);
  return out;
}

/// Stabile Deduplizierung (erster Treffer gewinnt).
List<String> _orderedDedup(Iterable<String> src) {
  final seen = <String>{};
  final dedup = <String>[];
  for (final s in src) {
    final k = s.toLowerCase();
    if (seen.add(k)) dedup.add(s.trim());
  }
  return dedup;
}

Map<String, dynamic>? _asMap(dynamic x) {
  return (x is Map<String, dynamic>)
      ? x
      : (x is Map)
          ? Map<String, dynamic>.from(x)
          : null;
}

/// Erstes nicht-leeres Stringfeld aus einer Map anhand mehrerer Keys holen.
String? _pickString(Map<String, dynamic>? mm, List<String> keys) {
  if (mm == null) return null;
  for (final k in keys) {
    final v = mm[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

List<dynamic> _listDyn(dynamic v) {
  if (v is List) return List<dynamic>.from(v);
  return const <dynamic>[];
}
