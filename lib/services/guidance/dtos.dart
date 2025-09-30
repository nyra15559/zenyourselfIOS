// lib/services/guidance/dtos.dart
//
// DTOs & Value-Types für Guidance-Service (standalone, ohne Api-Abhängigkeit)
// - Keine externen Abhängigkeiten
// - Defensive Defaults (tolerante fromMaybe-Factories)
// - Snake_case-Shims für UI-/API-Kompatibilität
// - v12.2-Alignment: bevorzugte Felder für answer_helpers, talk[], flow.mood_prompt
//
// Mini-Checkliste (Pflichtenheft A/5):
// [x] ReflectionTurn.answerHelpers vorhanden (Default [])
// [x] ReflectionFlow.moodPrompt / recommendEnd enthalten
// [x] Tolerantes snake_case/legacy-Parsing (incl. Aliasse)
// [x] Helpers: geordnete Deduplizierung, max 3, keine Fragen („?“)
// [x] Session passthrough robust (id/turn/max_turns Aliasse)

/// ───────────────────────────────────────────────────────────────────────────
/// AnalyzeResult
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
/// ReflectionTurn — Kernantwort eines Workers
/// ───────────────────────────────────────────────────────────────────────────
class ReflectionTurn {
  final String outputText;          // Primärtext (Frage/Prompt)
  final String? mirror;             // Empathische Spiegelung (optional)
  final List<String> context;       // Hinweise/Aspekte
  final List<String> followups;     // kleine Nachfragen (KEINE Chips)
  final List<String> answerHelpers; // v12.2: Echte Worker-Chips (Satzstarter)
  final ReflectionFlow? flow;       // Flow-Metadaten/Flags
  final ReflectionSession session;  // Session-Metadaten (immer vorhanden)
  final List<String> tags;          // Schulen/Tags
  final String riskFlag;            // 'none' | 'support' | 'crisis'
  final List<String> questions;     // gelieferte Fragen (roh)
  final List<String> talk;          // talk-Zeilen

  const ReflectionTurn({
    required this.outputText,
    required this.mirror,
    required this.context,
    required this.followups,
    required this.answerHelpers,
    required this.flow,
    required this.session,
    required this.tags,
    required this.riskFlag,
    this.questions = const [],
    this.talk = const [],
  });

  // Fallback-Fehlertext-Kopie, damit dtos.dart unabhängig bleibt
  static const String kErrorHintFallback =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';

  // UI-/API-Shims (snake_case bewusst beibehalten)
  // ignore: non_constant_identifier_names
  String get output_text => outputText;

  /// 'high' | 'mild' | 'none' (abgeleitet aus riskFlag)
  // ignore: non_constant_identifier_names
  String get risk_level =>
      (riskFlag == 'crisis') ? 'high' : (riskFlag == 'support' ? 'mild' : 'none');

  /// true, wenn Unterstützung/Alarm signalisiert ist
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
      'flow': flow?.toJson() ??
          const ReflectionFlow(recommendEnd: false, suggestBreak: false).toJson(),
      'session': session.toJson(),
      if (tags.isNotEmpty) 'tags': tags,
      'risk_level': risk_level,
      if (questions.isNotEmpty) 'questions': questions,
      if (talk.isNotEmpty) 'talk': talk,
    };
    return map;
  }

  /// Tolerantes Einlesen (Map oder null). Defensive Defaults, keine Throws.
  static ReflectionTurn? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);

    // kleine lokale Helper
    List<String> asStringList(dynamic x) {
      if (x == null) return const <String>[];
      if (x is List) {
        return x
            .where((e) => e != null)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (x is String) {
        final s = x.trim();
        if (s.isEmpty) return const <String>[];
        // tolerant splitten (Zeilen, Bulletpoints, Semikolons, Gedankenstriche)
        final parts = s
            .split(RegExp(r'\n+|[•\-–—]\s+|;\s+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return parts.isEmpty ? <String>[s] : parts;
      }
      return const <String>[];
    }

    // output / question(s)
    final outputText = (m['output_text'] ??
            m['outputText'] ??
            m['question'] ??
            m['primary_question'] ??
            '')
        .toString()
        .trim();

    // Fragen: mehrere mögliche Keys tolerieren
    final questions = <String>[
      ...asStringList(m['questions']),
      ...asStringList(m['qs']),
      ...asStringList(m['multi_questions']),
    ];

    // simple lists
    final context = asStringList(m['context']);
    final followups = asStringList(m['followups']);
    final talk = asStringList(m['talk']);
    final tags = asStringList(m['tags']);

    // *** Chips aus verschiedenen Feldern tolerant einsammeln (geordnet deduplizieren, max 3)
    final _helpersRaw = <String>[
      ...asStringList(m['answer_helpers']),
      ...asStringList(m['answer_scaffolds']),
      ...asStringList(m['answer_templates']),
      ...asStringList(m['helpers']),
      ...asStringList(m['chips']),
      ...asStringList(m['answers']),
      // gelegentlich verschachtelt in flow/ui
      ...asStringList((m['flow'] as Map?)?['answer_helpers']),
      ...asStringList((m['flow'] as Map?)?['helpers']),
      ...asStringList((m['ui'] as Map?)?['answer_helpers']),
      ...asStringList((m['ui'] as Map?)?['chips']),
    ]
        // echte Fragen rausfiltern
        .where((s) => s.isNotEmpty && !s.endsWith('?'))
        // sanfte Normalisierung: Doppelpunkte/Abschluss-Punkte weg
        .map((s) => s.replaceAll(RegExp(r'\s*[:：]\s*$'), '').replaceAll(RegExp(r'[.。]+$'), '').trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final seen = <String>{};
    final orderedDeduped = <String>[];
    for (final h in _helpersRaw) {
      final k = h.toLowerCase();
      if (seen.add(k)) orderedDeduped.add(h);
      if (orderedDeduped.length >= 3) break;
    }
    final answerHelpers = orderedDeduped;

    // risk
    final rl = (m['risk_level'] ?? m['risk'] ?? 'none').toString().toLowerCase().trim();
    final riskFlag = (rl == 'high' || rl == 'crisis')
        ? 'crisis'
        : (rl == 'mild' || rl == 'support')
            ? 'support'
            : 'none';

    return ReflectionTurn(
      outputText: outputText.isEmpty ? kErrorHintFallback : outputText,
      mirror: (m['mirror']?.toString().trim().isEmpty ?? true) ? null : m['mirror'].toString(),
      context: context,
      followups: followups,
      answerHelpers: answerHelpers, // <- jetzt Teil des DTOs
      flow: ReflectionFlow.fromMaybe(m['flow']),
      session: ReflectionSession.fromMaybe(m['session']) ??
          const ReflectionSession(threadId: '', turnIndex: 0, maxTurns: 3),
      tags: tags,
      riskFlag: riskFlag,
      questions: questions,
      talk: talk,
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
    return ReflectionFlow(
      recommendEnd: m['recommend_end'] == true || m['end'] == true,
      suggestBreak: m['suggest_break'] == true || m['break'] == true,
      riskNotice: m['risk_notice']?.toString(),
      sessionTurn: (m['session_turn'] is num) ? (m['session_turn'] as num).toInt() : null,
      talkOnly: m['talk_only'] == true,
      allowReflect: m['allow_reflect'] != false,
      moodPrompt: m['mood_prompt'] == true || m['moodPrompt'] == true,
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

  static ReflectionSession? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final id = (m['id'] ?? m['thread_id'] ?? m['threadId'] ?? '').toString();
    final turn = (m['turn'] is num)
        ? (m['turn'] as num).toInt()
        : (m['turn_index'] is num)
            ? (m['turn_index'] as num).toInt()
            : (m['turnIndex'] is num)
                ? (m['turnIndex'] as num).toInt()
                : 0;
    final max = (m['max_turns'] is num)
        ? (m['max_turns'] as num).toInt()
        : (m['maxTurns'] is num)
            ? (m['maxTurns'] as num).toInt()
            : 3;
    return ReflectionSession(threadId: id, turnIndex: turn, maxTurns: max);
  }
}

/// ───────────────────────────────────────────────────────────────────────────
/// Weitere Value-Types
/// ───────────────────────────────────────────────────────────────────────────
class JourneyInsights {
  final List<String> insights; // 3–6 Beobachtungen oder Fehlerhinweis
  final String question;       // Leitfrage oder Lade-/Fehlerhinweis

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
  final String text;       // Rohtext (PII wird serverseitig/heuristisch reduziert)

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

/// ───────────────────────────────────────────────────────────────────────────
/// Platzhalter-/Hilfstypen
/// ───────────────────────────────────────────────────────────────────────────
class Analysis {
  final Object? sorc;
  final List<Object?> levers;
  final String? mirror;
  final String? question;
  final String? riskLevel;

  const Analysis({this.sorc, required this.levers, this.mirror, this.question, this.riskLevel});

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

  const MiniChallenge({required this.id, required this.title, required this.steps});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'steps': steps};

  static MiniChallenge? fromMaybe(dynamic v) {
    if (v is Map<String, dynamic>) {
      final steps = ((v['steps'] as List?) ?? const []).map((e) => e.toString()).toList();
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
