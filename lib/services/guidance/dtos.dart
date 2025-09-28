// lib/services/guidance/dtos.dart
//
// DTOs & Value-Types für Guidance-Service (standalone, ohne Api-Abhängigkeit)

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

// ——— Kern-Turn (eine Worker-Antwort) ———
class ReflectionTurn {
  final String outputText;
  final String? mirror;
  final List<String> context;
  final List<String> followups;
  final ReflectionFlow? flow;
  final ReflectionSession session;
  final List<String> tags;
  final String riskFlag; // none | support | crisis
  final List<String> questions;
  final List<String> talk;

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

  // Fallback-Fehlertext-Kopie, damit dtos.dart unabhängig bleibt
  static const String kErrorHintFallback =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';

  String get output_text => outputText;

  String get risk_level =>
      (riskFlag == 'crisis') ? 'high' : (riskFlag == 'support' ? 'mild' : 'none');

  bool get risk => riskFlag == 'support' || riskFlag == 'crisis';

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
}

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
      moodPrompt: m['mood_prompt'] == true,
    );
  }
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
  final String dateIso; // YYYY-MM-DD
  final String? moodLabel; // z. B. "Gut" | null
  final String text; // Rohtext (PII wird serverseitig/heuristisch reduziert)
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

// Platzhalter-Typen (falls später gebraucht)
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

// Kleine String-Extension
extension IfEmptyX on String {
  String ifEmpty(String Function() alt) => isEmpty ? alt() : this;
}
