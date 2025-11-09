// [PATCHED] lib/services/guidance/dtos.dart (Stand: 2025-11-09, v7.1.6+insight.2+timeline.1)
// DTOs & Value-Types für Guidance-Service (standalone, ohne Api-Abhängigkeit)
// ────────────────────────────────────────────────────────────────────────────
// MERGE SIGNAL — v7.1.6 (insight.2+timeline.1)
// • Compile-Fix: Keine static Member in Extensions. Parser als Top-Level-Funktionen:
//   parseToneType(), parseStage(), parseActionType(). Aufrufer angepasst.
// • Sonst unverändert: Snake/camel-Aliasse, TimelineMarker & InsightFact, Persona-Sanitizer.
//
// Rückwärtskompatibel zu v6.x & v7.1.x — keine Breaking Changes.
// ────────────────────────────────────────────────────────────────────────────

library guidance_dtos;

// ────────────────────────────────────────────────────────────────────────────
// Enums – Tone & Stage
// ────────────────────────────────────────────────────────────────────────────
enum ToneType { neutral, calm, hope, gentle, insight, ritual, light, crisis, unknown }
extension ToneTypeWire on ToneType {
  String get wire {
    switch (this) {
      case ToneType.neutral: return 'neutral';
      case ToneType.calm:    return 'calm';
      case ToneType.hope:    return 'hope';
      case ToneType.gentle:  return 'gentle';
      case ToneType.insight: return 'insight';
      case ToneType.ritual:  return 'ritual';
      case ToneType.light:   return 'light';
      case ToneType.crisis:  return 'crisis';
      case ToneType.unknown: return 'unknown';
    }
  }
}
ToneType parseToneType(dynamic v) {
  final s = v?.toString().toLowerCase().trim() ?? '';
  switch (s) {
    case 'neutral': return ToneType.neutral;
    case 'calm':    return ToneType.calm;
    case 'hope':    return ToneType.hope;
    case 'gentle':  return ToneType.gentle;
    case 'insight': return ToneType.insight;
    case 'ritual':  return ToneType.ritual;
    case 'light':   return ToneType.light;
    case 'crisis':  return ToneType.crisis;
    default:        return ToneType.unknown;
  }
}

enum Stage { intro, clarify, hypothesize, deepen, bridge, closure, redirect, unknown }
extension StageWire on Stage {
  String get wire {
    switch (this) {
      case Stage.intro:       return 'intro';
      case Stage.clarify:     return 'clarify';
      case Stage.hypothesize: return 'hypothesize';
      case Stage.deepen:      return 'deepen';
      case Stage.bridge:      return 'bridge';
      case Stage.closure:     return 'closure';
      case Stage.redirect:    return 'redirect';
      case Stage.unknown:     return 'unknown';
    }
  }
}
Stage parseStage(dynamic v) {
  final s = v?.toString().toLowerCase().trim() ?? '';
  switch (s) {
    case 'intro':        return Stage.intro;
    case 'clarify':      return Stage.clarify;
    case 'hypothesize':
    case 'hypothesis':   return Stage.hypothesize;
    case 'deepen':       return Stage.deepen;
    case 'bridge':       return Stage.bridge;
    case 'closure':
    case 'close':        return Stage.closure;
    case 'redirect':
    case 'topic_shift':  return Stage.redirect;
    default:             return Stage.unknown;
  }
}

// ────────────────────────────────────────────────────────────────────────────
/* V7.1: HistoryTurn — typisierte Chat-Historie ohne Heuristik */
// ────────────────────────────────────────────────────────────────────────────
class HistoryTurn {
  final String role; // 'user' | 'assistant' | 'system' (optional)
  final String text;

  const HistoryTurn({required this.role, required this.text});

  Map<String, String> toMessageJson() => {
        'role': role.trim(),
        'content': text,
      };

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
      };

  static HistoryTurn? fromMaybe(dynamic v) {
    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      final role = (m['role'] ?? '').toString();
      final text = (m['text'] ?? m['content'] ?? '').toString();
      if (role.trim().isEmpty && text.trim().isEmpty) return null;
      return HistoryTurn(role: role, text: text);
    }
    return null;
  }
}


// ────────────────────────────────────────────────────────────────────────────
/* V7.1 (+compat): NextTurnFullRequest — Request-Envelope für /next_turn_full */
// ────────────────────────────────────────────────────────────────────────────
class NextTurnFullRequest {
  final String sessionId;                 // = ReflectionSession.threadId
  final String userText;                  // aktueller User-Text (kann leer sein bei Actions)
  final List<HistoryTurn> history;        // verlustfrei, ohne Heuristik

  /// Kompakter Memory-Context (kuratiert). Darf Map<String,dynamic> ODER List<dynamic> sein.
  /// Wird in toJson() nach {context:{memories:…}} serialisiert.
  final dynamic contextMemories;

  final bool? metaClientMemory;           // meta.flags.client_memory

  const NextTurnFullRequest({
    required this.sessionId,
    required this.userText,
    this.history = const <HistoryTurn>[],
    this.contextMemories,
    this.metaClientMemory,
  });

  Map<String, dynamic> toJson() {
    final hist = history.map((h) => h.toMessageJson()).toList();
    final map = <String, dynamic>{
      'session': {'id': sessionId, 'thread_id': sessionId},
      'user_text': userText,
      if (hist.isNotEmpty) 'history': hist,
    };

    if (contextMemories != null) {
      if (contextMemories is Map) {
        map['context'] = {'memories': Map<String, dynamic>.from(contextMemories as Map)};
      } else if (contextMemories is List && (contextMemories as List).isNotEmpty) {
        map['context'] = {'memories': List<dynamic>.from(contextMemories as List)};
      }
    }

    if (metaClientMemory != null) {
      map['meta'] = {
        'flags': {'client_memory': metaClientMemory}
      };
    }
    return map;
  }

  static NextTurnFullRequest fromParts({
    required String sessionId,
    required String userText,
    List<HistoryTurn>? history,
    dynamic contextMemories, // Map<String,dynamic> ODER List<dynamic>
    bool? metaClientMemory,
  }) {
    return NextTurnFullRequest(
      sessionId: sessionId,
      userText: userText,
      history: history ?? const <HistoryTurn>[],
      contextMemories: contextMemories,
      metaClientMemory: metaClientMemory,
    );
  }
}


// ────────────────────────────────────────────────────────────────────────────
// V7 A1: SpeechMeta – Meta-Infos über Tonalität, Thema, Safety, Vertrauen
// ────────────────────────────────────────────────────────────────────────────
class SpeechMeta {
  final ToneType tone;
  final String? topic;
  final String? safety;      // z. B. 'none' | 'mild' | 'high'
  final double? confidence;  // 0..1

  const SpeechMeta({
    this.tone = ToneType.unknown,
    this.topic,
    this.safety,
    this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'tone': tone.wire,
        if ((topic ?? '').trim().isNotEmpty) 'topic': topic!.trim(),
        if ((safety ?? '').trim().isNotEmpty) 'safety': safety!.trim(),
        if (confidence != null) 'confidence': confidence,
      };

  static SpeechMeta? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    double? asDouble(dynamic x) {
      if (x is num) return x.toDouble();
      if (x is String) return double.tryParse(x.trim());
      return null;
    }
    String? nz(dynamic x) {
      final s = x?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }
    return SpeechMeta(
      tone: parseToneType(m['tone']),
      topic: nz(m['topic']),
      safety: nz(m['safety']),
      confidence: asDouble(m['confidence']),
    );
  }
}


// ────────────────────────────────────────────────────────────────────────────
// V7 A1: Facets – Facet-Queue & aktives Facet
// ────────────────────────────────────────────────────────────────────────────
class Facets {
  final String? active;         // aktuelles Facet (z. B. "Essenz", "Beispiel")
  final List<String> queue;     // weitere geplante Facets (FIFO)

  const Facets({this.active, this.queue = const <String>[]});

  Map<String, dynamic> toJson() => {
        if ((active ?? '').trim().isNotEmpty) 'active': active!.trim(),
        if (queue.isNotEmpty) 'queue': queue,
      };

  static Facets? fromMaybe(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      final q = _strings(v);
      return Facets(active: q.isEmpty ? null : q.first, queue: q.skip(1).toList());
    }
    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      final a = (m['active'] ?? m['current'])?.toString();
      final q = _strings([m['queue'], m['list']]);
      if ((a == null || a.trim().isEmpty) && q.isEmpty) return null;
      return Facets(active: (a?.trim().isEmpty ?? true) ? null : a!.trim(), queue: q);
    }
    return null;
  }
}


// ────────────────────────────────────────────────────────────────────────────
// V7 A1: SkillCard & SkillBlock – Kartenbasierte Skills mit Stage
// ────────────────────────────────────────────────────────────────────────────
class SkillCard {
  final String id;            // stabile ID
  final String title;         // Überschrift der Karte
  final String body;          // kurzer Text / Anleitung
  final Stage stage;          // Phase (clarify/bridge/closure ...)
  final List<String> helpers; // Satzstarter / Chips (max 3 empfohlen)

  const SkillCard({
    required this.id,
    required this.title,
    required this.body,
    required this.stage,
    this.helpers = const <String>[],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'stage': stage.wire,
        if (helpers.isNotEmpty) 'helpers': helpers,
      };

  static SkillCard? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final id = (m['id'] ?? m['key'] ?? '').toString().trim();
    final title = (m['title'] ?? m['headline'] ?? '').toString().trim();
    final body = (m['body'] ?? m['text'] ?? '').toString().trim();
    final stage = parseStage(m['stage']);
    final helpers = _orderedDedup(_strings([m['helpers'], m['chips'], m['answers']])).take(3).toList();
    if (id.isEmpty && title.isEmpty && body.isEmpty) return null;
    return SkillCard(
      id: id.ifEmpty(() => 'card_${title.hashCode}_${body.hashCode}'),
      title: title.ifEmpty(() => '—'),
      body: body.ifEmpty(() => ''),
      stage: stage,
      helpers: helpers,
    );
  }
}

class SkillBlock {
  final String kind;           // z. B. 'dream_reflection' | 'decision_support'
  final Stage stage;
  final List<SkillCard> cards;

  const SkillBlock({required this.kind, required this.stage, this.cards = const <SkillCard>[]});

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'stage': stage.wire,
        if (cards.isNotEmpty) 'cards': cards.map((c) => c.toJson()).toList(),
      };

  static SkillBlock? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final kind = (m['kind'] ?? m['type'] ?? 'skill').toString().trim();
    final stage = parseStage(m['stage']);
    final listDyn = (m['cards'] is List) ? (m['cards'] as List) : (m['card'] is Map ? [m['card']] : const []);
    final cards = <SkillCard>[];
    for (final e in listDyn) {
      final c = SkillCard.fromMaybe(e);
      if (c != null) cards.add(c);
    }
    return SkillBlock(kind: kind.ifEmpty(() => 'skill'), stage: stage, cards: cards);
  }
}


// ────────────────────────────────────────────────────────────────────────────
// Legacy/Analysis (beibehalten für Backcompat)
// ────────────────────────────────────────────────────────────────────────────
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


// ────────────────────────────────────────────────────────────────────────────
// ActionType & UserAction (mit Enum-Backcompat)
// ────────────────────────────────────────────────────────────────────────────
enum ActionType { reflectionLink, journalLink, storyLink, save, skip, changeTopic, unknown }
extension ActionTypeWire on ActionType {
  String get wire {
    switch (this) {
      case ActionType.reflectionLink: return 'reflection_link';
      case ActionType.journalLink:    return 'journal_link';
      case ActionType.storyLink:      return 'story_link';
      case ActionType.save:           return 'save';
      case ActionType.skip:           return 'skip';
      case ActionType.changeTopic:    return 'change_topic';
      case ActionType.unknown:        return 'unknown';
    }
  }
}
ActionType parseActionType(dynamic v) {
  final s = v?.toString().toLowerCase().trim() ?? '';
  switch (s) {
    case 'reflection_link':
    case 'reflectionlink': return ActionType.reflectionLink;
    case 'journal_link':
    case 'journallink':    return ActionType.journalLink;
    case 'story_link':
    case 'storylink':      return ActionType.storyLink;
    case 'save':           return ActionType.save;
    case 'skip':           return ActionType.skip;
    case 'change_topic':
    case 'change-topic':
    case 'changetopic':
    case 'change':         return ActionType.changeTopic;
    default:               return ActionType.unknown;
  }
}

class UserAction {
  final String type;                 // Legacy Wire (z. B. "journal_link")
  final ActionType actionType;       // Enum (neu)
  final String? note;                // optional

  const UserAction({required this.type, this.actionType = ActionType.unknown, this.note});

  Map<String, dynamic> toJson() => {
        'type': type,
        'action_type': actionType.wire,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      };

  static UserAction? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final rawType = (m['type'] ?? m['action'] ?? m['action_type'] ?? '').toString().trim();
    if (rawType.isEmpty) return null;
    final enumType = parseActionType(m['action_type'] ?? m['type'] ?? m['action']);
    final note = (m['note'] ?? m['text'] ?? m['message'])?.toString();
    return UserAction(
      type: rawType,
      actionType: enumType,
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    );
  }
}


// ────────────────────────────────────────────────────────────────────────────
// TurnAnalysis & ClosureData
// ────────────────────────────────────────────────────────────────────────────
class TurnAnalysis {
  final String? summary;
  final String? topic;
  final double? insightScore;               // 0..1 (optional)
  final List<String> topicSuggestions;

  const TurnAnalysis({this.summary, this.topic, this.insightScore, this.topicSuggestions = const <String>[]});

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
      return (s == null) ? null : double.tryParse(s);
    }
    final summary = m['summary']?.toString();
    final topic = (m['topic'] ?? m['focus'] ?? m['theme'])?.toString();
    final insight = asDouble(m['insight_score'] ?? m['insightScore']);
    final topics = _orderedDedup(_strings([m['topic_suggestions'], m['topicSuggestions'], m['topics'], m['redirect_suggestions']]));
    return TurnAnalysis(
      summary: (summary?.trim().isEmpty ?? true) ? null : summary!.trim(),
      topic: (topic?.trim().isEmpty ?? true) ? null : topic!.trim(),
      insightScore: insight,
      topicSuggestions: topics,
    );
  }
}

class ClosureData {
  final String moodIntroText;
  final String hopeReply;
  final String closurePrompt;
  final String? mode;
  final String? reason;
  final String? tone;

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
    final closure = mm(m['closure']) ?? m;
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


// ────────────────────────────────────────────────────────────────────────────
// ReflectionTurn – Kernantwort inkl. V7-Feldern
// ────────────────────────────────────────────────────────────────────────────
class ReflectionTurn {
  final String outputText;
  final String? mirror;
  final List<String> context;
  final List<String> followups;
  final List<String> answerHelpers;
  final String? helperSuggestion;

  final ReflectionFlow? flow;
  final ReflectionSession session;
  final List<String> tags;
  final String riskFlag;
  final List<String> questions;
  final List<String> talk;

  final List<dynamic> speechSequence;
  final TurnAnalysis? analysis;
  final List<String> topicSuggestions;

  final List<dynamic> memoriesToSave;
  final String? understandingTopicShift;

  final bool? metaClientMemory;
  final List<dynamic> contextMemories;

  // ── NEU (v7.1.3): understanding.tags separat verfügbar
  final List<String> understandingTags;

  // ── V7 A1: neue Felder
  final SpeechMeta? speechMeta;
  final SkillBlock? skill;                 // strukturierter Block
  final List<SkillCard> skillCards;        // flache Kartenliste (falls ohne Block)
  final Facets? facets;                    // Facet-Queue/Active
  final String? topicPin;                  // UI-Pin / Thema
  final List<String> availableActions;     // Worker-Aktionen (snake_case)

  // ── S4.1: Smalltalk separat
  final String? smalltalkReply;

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
    this.metaClientMemory,
    this.contextMemories = const <dynamic>[],
    // v7.1.3
    this.understandingTags = const <String>[],
    // V7
    this.speechMeta,
    this.skill,
    this.skillCards = const <SkillCard>[],
    this.facets,
    this.topicPin,
    this.availableActions = const <String>[],
    // S4.1
    this.smalltalkReply,
  });

  static const String kErrorHintFallback =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';

  // ignore: non_constant_identifier_names
  String get risk_level => (riskFlag == 'crisis') ? 'high' : (riskFlag == 'support' ? 'mild' : 'none');
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
      if (answerHelpers.isNotEmpty) 'answer_helpers': answerHelpers,
      if ((helperSuggestion ?? '').trim().isNotEmpty) 'helper_suggestion': helperSuggestion!.trim(),
      'flow': flow?.toJson() ?? const ReflectionFlow(recommendEnd: false, suggestBreak: false).toJson(),
      'session': session.toJson(),
      if (tags.isNotEmpty) 'tags': tags,
      'risk_level': risk_level,
      if (risk) 'risk': true,
      if (questions.isNotEmpty) 'questions': questions,
      if (talk.isNotEmpty) 'talk': talk,
      if (speechSequence.isNotEmpty) 'speech_sequence': List<dynamic>.from(speechSequence),
      if (analysis != null) 'analysis': analysis!.toJson(),
      if (topicSuggestions.isNotEmpty) 'topic_suggestions': topicSuggestions,
      if (memoriesToSave.isNotEmpty) 'memories_to_save': List<dynamic>.from(memoriesToSave),
      if (contextMemories.isNotEmpty) 'context_memories': List<dynamic>.from(contextMemories),
      // V7
      if (speechMeta != null) 'speech_meta': speechMeta!.toJson(),
      if (skill != null) 'skill': skill!.toJson(),
      if (skillCards.isNotEmpty) 'skill_cards': skillCards.map((c) => c.toJson()).toList(),
      if (facets != null) 'facets': facets!.toJson(),
      if ((topicPin ?? '').trim().isNotEmpty) 'topic_pin': topicPin!.trim(),
      if (availableActions.isNotEmpty) 'available_actions': availableActions,
      // S4.1
      if ((smalltalkReply ?? '').trim().isNotEmpty) 'smalltalk_reply': smalltalkReply!.trim(),
    };

    // understanding.{topic_shift,tags} zurückschreiben, wenn vorhanden
    final hasShift = (understandingTopicShift ?? '').trim().isNotEmpty;
    final hasUTags = understandingTags.isNotEmpty;
    if (hasShift || hasUTags) {
      final u = <String, dynamic>{};
      if (hasShift) u['topic_shift'] = understandingTopicShift!.trim();
      if (hasUTags) u['tags'] = understandingTags;
      map['understanding'] = u;
    }
    return map;
  }

  static ReflectionTurn? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    Map<String, dynamic>? asMap(dynamic x) => _asMap(x);

    final primary = asMap(m['primary']);
    final flowMap = asMap(m['flow']);
    final uiMap   = asMap(m['ui']);
    final understandingMap = asMap(m['understanding']) ?? const <String, dynamic>{};

    final outputText = (m['output_text'] ?? m['outputText'] ?? m['question'] ?? m['primary_question']
          ?? _pickString(primary, const ['output_text', 'text', 'question'])
          ?? _pickString(flowMap, const ['output_text', 'text', 'question']) ?? '')
        .toString().trim();

    final questions = _strings([m['questions'], m['qs'], m['multi_questions'], primary?['questions'], flowMap?['questions']]);
    final context = _strings([m['context']]);

    final contextObj = asMap(m['context']);
    final cmem = _ensureListDyn(contextObj?['memories']);

    final followups = _strings([m['followups']]);

    // S4.1: smalltalk_reply separat parsen (inkl. Aliasse & verschachtelt)
    String? parseSmalltalk() {
      String? pick(Map<String, dynamic>? mm) =>
          _pickString(mm, const ['smalltalk_reply', 'smalltalk', 'smalltalkReply']);
      final s = (m['smalltalk_reply'] ?? m['smalltalk'] ?? m['smalltalkReply']
                ?? pick(primary) ?? pick(flowMap))?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }
    final smalltalk = parseSmalltalk();
    final smalltalkSan = (smalltalk == null) ? null : _sanitizePersona(smalltalk);

    // talk ohne Doppelung aus smalltalk_reply, Persona-Sanitizer anwenden
    final talk = _sanitizePersonaList(_strings([
      m['talk'], primary?['talk'], flowMap?['talk'],
    ]).where((t) => t.trim().isNotEmpty).toList());

    // understanding.tags optional dazumergen (Quelle für Marker)
    final uTags = _orderedDedup(_strings([understandingMap['tags']]));
    final tagsTop = _strings([m['tags'], primary?['tags'], flowMap?['tags']]);
    final tags = _orderedDedup(<String>[...tagsTop, ...uTags]);

    final helpersRaw = _strings([
      m['answer_helpers'], m['answer_scaffolds'], m['answer_templates'],
      m['helpers'], m['chips'], m['answers'],
      asMap(m['ui'])?['answer_helpers'], asMap(m['ui'])?['chips'],
      flowMap?['answer_helpers'], flowMap?['helpers'],
      primary?['answer_helpers'], primary?['helpers'],
      asMap(m['ui'])?['options'], flowMap?['options'], primary?['options'],
    ]).where((s) => s.isNotEmpty && !s.endsWith('?'))
     .map((s) => s.replaceAll(RegExp(r'\s*[:：]\s*$'), '').replaceAll(RegExp(r'[.。]+$'), '').trim())
     .where((s) => s.isNotEmpty).toList();

    final answerHelpers = _orderedDedup(helpersRaw).take(3).toList();

    String? helperSuggestion() {
      final top = (m['helper_suggestion'] ?? m['helperSuggestion'])?.toString().trim();
      if ((top ?? '').isNotEmpty) return top;
      final fromPrimary = _pickString(primary, const ['helper_suggestion', 'helperSuggestion']);
      if ((fromPrimary ?? '').trim().isNotEmpty) return fromPrimary!.trim();
      final fromFlow = _pickString(flowMap, const ['helper_suggestion', 'helperSuggestion']);
      if ((fromFlow ?? '').trim().isNotEmpty) return fromFlow!.trim();
      final fromUi = _pickString(uiMap, const ['helper_suggestion', 'helperSuggestion']);
      if ((fromUi ?? '').trim().isNotEmpty) return fromUi!.trim();
      return null;
    }

    String riskFlagFrom(dynamic levelDyn, dynamic riskDyn, dynamic riskFlagDyn) {
      if (riskDyn == true) return 'support';
      final rf = riskFlagDyn?.toString().toLowerCase().trim();
      if (rf == 'crisis' || rf == 'support' || rf == 'none') return rf!;
      final levelCandidate = levelDyn ?? m['level'];
      final rl = (levelCandidate ?? riskDyn ?? 'none').toString().toLowerCase().trim();
      if (rl == 'high' || rl == 'crisis') return 'crisis';
      if (rl == 'mild' || rl == 'support' || rl == 'true') return 'support';
      return 'none';
    }

    final riskFlag = riskFlagFrom(m['risk_level'], m['risk'], m['risk_flag']);

    final turnAnalysis = TurnAnalysis.fromMaybe(m['analysis']);
    final topLevelTopicSugs = _strings([m['topic_suggestions'], m['topicSuggestions'], m['topics']]);
    final tsDedup = _orderedDedup(<String>[...topLevelTopicSugs, if (turnAnalysis != null) ...turnAnalysis.topicSuggestions]);

    final speechSequence = _listDyn(m['speech_sequence'] ?? m['speechSequence']);

    final memoriesToSave = _listDyn(
      m['memories_to_save'] ?? m['memoriesToSave'] ?? asMap(m['plan'])?['memories_to_save'] ?? asMap(m['plan'])?['memoriesToSave'],
    );

    String? understandingTopicShift() {
      final u = understandingMap;
      final s = (u['topic_shift'] ?? u['topicShift'] ?? u['shift'])?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    bool? metaClientMemory() {
      final meta = asMap(m['meta']);
      final flags = asMap(meta?['flags']);
      final raw = flags?['client_memory'] ?? flags?['clientMemory'];
      return _parseBoolOrNull(raw);
    }

    // V7: neue Felder parsen
    final speechMeta = SpeechMeta.fromMaybe(m['speech_meta'] ?? m['speechMeta']);
    final skill = SkillBlock.fromMaybe(m['skill'] ?? m['skill_block'] ?? m['skillBlock']);
    final skillCards = <SkillCard>[];
    final cardsAny = (m['skill_cards'] is List)
        ? m['skill_cards']
        : (m['cards'] is List ? m['cards'] : const []);
    if (cardsAny is List) {
      for (final e in cardsAny) {
        final c = SkillCard.fromMaybe(e);
        if (c != null) skillCards.add(c);
      }
    }
    final facets = Facets.fromMaybe(m['facets'] ?? m['facet_queue'] ?? m['facetQueue']);
    final topicPin = (m['topic_pin'] ?? m['topicPin'])?.toString().trim();
    final availableActions = _orderedDedup(_strings([m['available_actions'], m['actions']]));

    return ReflectionTurn(
      outputText: outputText.isEmpty ? kErrorHintFallback : outputText,
      mirror: (m['mirror']?.toString().trim().isNotEmpty ?? false)
          ? m['mirror'].toString()
          : _pickString(primary, const ['mirror']) ?? _pickString(flowMap, const ['mirror']),
      context: context,
      followups: followups,
      answerHelpers: answerHelpers,
      helperSuggestion: helperSuggestion(),
      flow: ReflectionFlow.fromMaybe(m['flow']) ?? ReflectionFlow.fromMaybe(primary?['flow']),
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
      metaClientMemory: metaClientMemory(),
      contextMemories: cmem,
      // v7.1.3
      understandingTags: uTags,
      // V7
      speechMeta: speechMeta,
      skill: skill,
      skillCards: skillCards,
      facets: facets,
      topicPin: (topicPin == null || topicPin.isEmpty) ? null : topicPin,
      availableActions: availableActions,
      // S4.1
      smalltalkReply: smalltalkSan,
    );
  }
}


// ────────────────────────────────────────────────────────────────────────────
class ReflectionFlow {
  final bool recommendEnd;
  final bool suggestBreak;
  final String? riskNotice;
  final int? sessionTurn;
  final bool talkOnly;
  final bool allowReflect;
  final bool moodPrompt;
  final double? insightScore;

  const ReflectionFlow({
    required this.recommendEnd,
    required this.suggestBreak,
    this.riskNotice,
    this.sessionTurn,
    this.talkOnly = false,
    this.allowReflect = true,
    this.moodPrompt = false,
    this.insightScore,
  });

  Map<String, dynamic> toJson() => {
        'recommend_end': recommendEnd,
        'suggest_break': suggestBreak,
        if (riskNotice != null) 'risk_notice': riskNotice,
        if (sessionTurn != null) 'session_turn': sessionTurn,
        if (talkOnly) 'talk_only': true,
        'allow_reflect': allowReflect,
        if (moodPrompt) 'mood_prompt': true,
        if (insightScore != null) 'insight_score': insightScore,
      };

  static ReflectionFlow? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);

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

    double? asDouble(dynamic x) {
      if (x is num) return x.toDouble();
      if (x is String) return double.tryParse(x.trim());
      return null;
    }

    return ReflectionFlow(
      recommendEnd: m['recommend_end'] == true || m['end'] == true,
      suggestBreak: m['suggest_break'] == true || m['break'] == true,
      riskNotice: m['risk_notice']?.toString(),
      sessionTurn: asInt(m['session_turn']),
      talkOnly: m['talk_only'] == true,
      allowReflect: m['allow_reflect'] != false,
      moodPrompt: m['mood_prompt'] == true || m['moodPrompt'] == true || moodPromptNested(),
      insightScore: asDouble(m['insight_score'] ?? m['insightScore']),
    );
  }
}

class ReflectionSession {
  final String threadId;
  final int turnIndex;
  final int maxTurns;

  const ReflectionSession({required this.threadId, required this.turnIndex, required this.maxTurns});

  ReflectionSession copyWith({String? threadId, int? turnIndex, int? maxTurns}) =>
      ReflectionSession(threadId: threadId ?? this.threadId, turnIndex: turnIndex ?? this.turnIndex, maxTurns: maxTurns ?? this.maxTurns);

  Map<String, dynamic> toJson() => {
        'id': threadId,
        'thread_id': threadId,
        'turn': turnIndex,
        'turn_index': turnIndex,
        'max_turns': maxTurns,
      };

  static ReflectionSession? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    int _intOf(dynamic x, int fb) {
      if (x is num) return x.toInt();
      if (x is String) {
        final p = int.tryParse(x.trim());
        if (p != null) return p;
      }
      return fb;
    }
    final id = (m['id'] ?? m['thread_id'] ?? m['threadId'] ?? '').toString();
    final turn = _intOf(m['turn'] ?? m['turn_index'] ?? m['turnIndex'], 0);
    final max = _intOf(m['max_turns'] ?? m['maxTurns'], 3);
    return ReflectionSession(threadId: id, turnIndex: turn, maxTurns: max);
  }
}


// ────────────────────────────────────────────────────────────────────────────
// Weitere Value-Types (unverändert)
// ────────────────────────────────────────────────────────────────────────────
class JourneyInsights {
  final List<String> insights;
  final String question;
  const JourneyInsights({required this.insights, required this.question});
  Map<String, dynamic> toJson() => {'insights': insights, 'question': question};
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
  final String? moodLabel;
  final String text;
  const JourneyEntry({required this.dateIso, required this.text, this.moodLabel});
}

class MoodResponse { final bool saved; const MoodResponse({required this.saved}); }

class StoryResult {
  final String id;
  final String title;
  final String body;
  final String? audioUrl;
  const StoryResult({required this.id, required this.title, required this.body, this.audioUrl});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body, if (audioUrl != null) 'audio_url': audioUrl};
  static StoryResult? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final id = (m['id'] ?? '').toString();
    final title = (m['title'] ?? '').toString();
    final body = (m['story'] ?? m['body'] ?? '').toString();
    final audio = (m['audio'] ?? m['audio_url'])?.toString();
    if (id.isEmpty && title.isEmpty && body.isEmpty) return null;
    return StoryResult(id: id, title: title, body: body, audioUrl: (audio?.trim().isEmpty ?? true) ? null : audio!.trim());
  }
}

class Analysis {
  final Object? sorc;
  final List<Object?> levers;
  final String? mirror;
  final String? question;
  final String? riskLevel;
  const Analysis({this.sorc, required this.levers, this.mirror, this.question, this.riskLevel});
  Map<String, dynamic> toJson() => {'sorc': sorc, 'levers': levers, 'mirror': mirror, 'question': question, 'riskLevel': riskLevel};
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
      return MiniChallenge(id: (v['id'] ?? '').toString(), title: (v['title'] ?? '').toString(), steps: steps);
    }
    return null;
  }
}


// ────────────────────────────────────────────────────────────────────────────
// Kleine String-Extension
// ────────────────────────────────────────────────────────────────────────────
extension IfEmptyX on String {
  String ifEmpty(String Function() alt) => isEmpty ? alt() : this;
}


// ────────────────────────────────────────────────────────────────────────────
// Interne, wiederverwendbare Parse-Helfer (keine Abhängigkeiten)
// ────────────────────────────────────────────────────────────────────────────
List<String> _strings(dynamic many) {
  final out = <String>[];
  void addOne(dynamic x) {
    if (x == null) return;
    if (x is List) { for (final e in x) { addOne(e); } return; }
    final v = x.toString().trim();
    if (v.isEmpty) return;
    final parts = v.split(RegExp(r'\r?\n+|[•\-–—]\s+|\s*;\s*'))
        .map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) { out.add(v); } else { out.addAll(parts); }
  }
  addOne(many);
  return out;
}

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
  return (x is Map<String, dynamic>) ? x : (x is Map) ? Map<String, dynamic>.from(x) : null;
}

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

List<dynamic> _listDyn(dynamic v) => (v is List) ? List<dynamic>.from(v) : const <dynamic>[];

List<dynamic> _ensureListDyn(dynamic v) {
  if (v == null) return const <dynamic>[];
  if (v is List) return List<dynamic>.from(v);
  return <dynamic>[v];
}

bool? _parseBoolOrNull(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
  if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
  return null;
}


// ────────────────────────────────────────────────────────────────────────────
// P3-S11.1 — Persona-Sanitizer: Panda-Welt ohne See (nur Bambus/Licht/Laternen/Tee)
// Greift ausschließlich bei Panda-Persona-Texten (smalltalk_reply, talk).
// Nutzertexte/Mirror bleiben unverändert.
// ────────────────────────────────────────────────────────────────────────────
String _sanitizePersona(String s) {
  if (s.isEmpty) return s;
  var out = s;

  // Ziel: „See“-Welt → Bambus/Licht/Laternen/Tee
  final repl = <RegExp, String>{
    RegExp(r'\ban (dem|einem)\s+see\b', caseSensitive: false): 'im Bambushain',
    RegExp(r'\bam\s+see\b', caseSensitive: false): 'im Bambushain',
    RegExp(r'\bseeufer\b', caseSensitive: false): 'Bambushain',
    RegExp(r'\bsee[-\s]*weg\b', caseSensitive: false): 'Laternenpfad',
    RegExp(r'\bseeluft\b', caseSensitive: false): 'ruhige Luft zwischen Bambus',
    RegExp(r'\bsee\b', caseSensitive: false): 'Bambus',
    RegExp(r'\bufer\b', caseSensitive: false): 'Bambushain',
  };

  repl.forEach((rx, val) => out = out.replaceAll(rx, val));
  out = out.replaceAll(RegExp(r'\s{2,}'), ' ').replaceAll(' ,', ',').trim();
  return out;
}

List<String> _sanitizePersonaList(List<String> v) =>
    v.map(_sanitizePersona).where((e) => e.trim().isNotEmpty).toList();


// ────────────────────────────────────────────────────────────────────────────
/* OPTIONAL: TimelineMarker (Mini-DTO) — v7.1.4+timeline.1 (2025-11-08)
 * Zweck: Einheitliche, leichte Struktur für Timeline-Punkte (Client-seitig).
 * Felder sind defensiv & tolerant (siehe fromMaybe). */
// ────────────────────────────────────────────────────────────────────────────
class TimelineMarker {
  /// ISO-Datum (YYYY-MM-DD). Falls in fromMaybe ein ISO-Datetime reinkommt,
  /// wird auf YYYY-MM-DD gekürzt.
  final String dateIso;

  /// Kurzer Topic/Text (UI kürzt bei Bedarf; Hilfsfunktion topicShort()).
  final String? topic;

  /// Optionales Stimmungsetikett (z. B. „Ruhig“, „Gestresst“).
  final String? moodLabel;

  /// Freie Tags (z. B. ['reflection','name','sleep']).
  final List<String> tags;

  /// Quelle (frei, z. B. 'reflection' | 'journal' | 'story').
  final String? source;

  /// Einzeilige Zusammenfassung (optional).
  final String? summary;

  const TimelineMarker({
    required this.dateIso,
    this.topic,
    this.moodLabel,
    this.tags = const <String>[],
    this.source,
    this.summary,
  });

  /// JSON-Serialisierung (leichtgewichtig)
  Map<String, dynamic> toJson() => {
        'date': dateIso,
        if ((topic ?? '').trim().isNotEmpty) 'topic': topic!.trim(),
        if ((moodLabel ?? '').trim().isNotEmpty) 'mood_label': moodLabel!.trim(),
        if (tags.isNotEmpty) 'tags': tags,
        if ((source ?? '').trim().isNotEmpty) 'source': source!.trim(),
        if ((summary ?? '').trim().isNotEmpty) 'summary': summary!.trim(),
      };

  /// Tolerantes Parsing:
  /// akzeptiert {date|dateIso|ts|timestamp}, kürzt ISO-Datetime auf YYYY-MM-DD,
  /// liest topic/title/text, mood_label/mood, tags/list, source, summary.
  static TimelineMarker? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);

    String _pickDate(dynamic x) {
      final raw = (x ?? '').toString().trim();
      if (raw.isEmpty) return '';
      // Kürzen, falls ISO-Datetime übergeben wurde (YYYY-MM-DDTHH:mm:ssZ)
      if (raw.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw)) {
        return raw.substring(0, 10);
      }
      return raw;
    }

    String _getDate() {
      final cands = [
        m['date'],
        m['dateIso'],
        m['date_iso'],
        m['ts'],
        m['timestamp'],
      ];
      for (final c in cands) {
        final d = _pickDate(c);
        if (d.isNotEmpty) return d;
      }
      return '';
    }

    String? _nz(dynamic x) {
      final s = x?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    final dateIso = _getDate();
    if (dateIso.isEmpty) return null;

    final topic = _nz(m['topic'] ?? m['title'] ?? m['text']);
    final mood = _nz(m['mood_label'] ?? m['mood']);
    final source = _nz(m['source']);
    final summary = _nz(m['summary'] ?? m['one_liner'] ?? m['caption']);

    final tags = _orderedDedup(_strings([m['tags'], m['labels'], m['list']]));

    return TimelineMarker(
      dateIso: dateIso,
      topic: topic,
      moodLabel: mood,
      tags: tags,
      source: source,
      summary: summary,
    );
  }

  /// UI-Helfer: Thema kompakt (Default 24 Zeichen, Ellipse)
  String topicShort([int max = 24]) {
    final t = (topic ?? '').trim();
    if (t.length <= max) return t;
    if (max <= 1) return '…';
    return '${t.substring(0, max - 1)}…';
  }

  /// A11y-Label für Screen-Reader („<Datum>: <Topic>, Stimmung: <Label>“)
  String a11yLabel() {
    final t = (topic ?? 'Notiz').trim();
    final m = (moodLabel ?? '').trim();
    return m.isEmpty ? '$dateIso: $t' : '$dateIso: $t, Stimmung: $m';
  }
}


// ────────────────────────────────────────────────────────────────────────────
/* OPTIONAL: InsightFact (Mini-DTO) — v7.1.4+insight.1 (2025-11-08)
 * Zweck: Einheitliche, leichte Struktur für Aha-Fakten („Atomic Facts“).
 * Felder (tolerant): topic, fact/value/text, since (YYYY-MM-DD), confidence (0..1),
 * tags[], source?, id?  – rein clientseitig für UI/Storage/Exports; Server optional. */
// ────────────────────────────────────────────────────────────────────────────
class InsightFact {
  /// Stabiles (optional) – wenn nicht vorhanden, kann UI einen Hash bilden.
  final String? id;

  /// Thema/Kategorie des Fakts (z. B. „Schlaf“, „Rücken“, „Wasser tut gut“).
  final String? topic;

  /// Der eigentliche Aha-Fakt – kurze, klare Formulierung.
  final String fact;

  /// ISO-Datum (YYYY-MM-DD), wann erkannt/gespeichert.
  final String? since;

  /// Vertrauensgrad 0..1 (optional).
  final double? confidence;

  /// Freie Tags (z. B. ['insight','selfcare']).
  final List<String> tags;

  /// Quelle/Herkunft (frei, z. B. 'reflection' | 'journal' | 'import').
  final String? source;

  const InsightFact({
    this.id,
    this.topic,
    required this.fact,
    this.since,
    this.confidence,
    this.tags = const <String>[],
    this.source,
  });

  Map<String, dynamic> toJson() => {
        if ((id ?? '').trim().isNotEmpty) 'id': id!.trim(),
        if ((topic ?? '').trim().isNotEmpty) 'topic': topic!.trim(),
        'fact': fact,
        if ((since ?? '').trim().isNotEmpty) 'since': since!.trim(),
        if (confidence != null) 'confidence': confidence,
        if (tags.isNotEmpty) 'tags': tags,
        if ((source ?? '').trim().isNotEmpty) 'source': source!.trim(),
      };

  static InsightFact? fromMaybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);

    String _isoDate(dynamic x) {
      final raw = (x ?? '').toString().trim();
      if (raw.isEmpty) return '';
      // Falls ISO-Datetime → auf YYYY-MM-DD kürzen
      if (raw.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw)) {
        return raw.substring(0, 10);
      }
      // einfache Fallbacks (z. B. '2025/11/08' oder '08.11.2025' nicht konvertieren)
      return raw;
    }

    double? _asDouble(dynamic x) {
      if (x is num) return x.toDouble();
      if (x is String) return double.tryParse(x.trim());
      return null;
    }

    String? _nz(dynamic x) {
      final s = x?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    final id = _nz(m['id'] ?? m['key'] ?? m['uid']);
    final topic = _nz(m['topic'] ?? m['category']);
    final fact = _nz(m['fact'] ?? m['value'] ?? m['text'] ?? m['statement']) ?? '';
    final since = _nz(_isoDate(m['since'] ?? m['date'] ?? m['dateIso'] ?? m['date_iso'] ?? m['ts'] ?? m['timestamp']));
    final confidence = _asDouble(m['confidence'] ?? m['score']);
    final source = _nz(m['source'] ?? m['origin']);
    final tags = _orderedDedup(_strings([m['tags'], m['labels']]));

    if (fact.isEmpty) return null;

    return InsightFact(
      id: id,
      topic: topic,
      fact: fact,
      since: (since?.isEmpty ?? true) ? null : since,
      confidence: confidence,
      tags: tags,
      source: source,
    );
  }

  /// Hilfsparser für Listen- oder Einzelstrukturen.
  static List<InsightFact> listFromMaybe(dynamic v) {
    final out = <InsightFact>[];
    if (v == null) return out;
    if (v is List) {
      for (final e in v) {
        final f = InsightFact.fromMaybe(e);
        if (f != null) out.add(f);
      }
      return out;
    }
    final single = InsightFact.fromMaybe(v);
    if (single != null) out.add(single);
    return out;
  }
}
