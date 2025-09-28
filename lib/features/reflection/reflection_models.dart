// lib/features/reflection/reflection_models.dart
// Part: Modelle/Typen/Utils (library: reflection_screen)
// -----------------------------------------------------------------------------
// v3.13 — Worker v12.2 Alignment
// - Frage optional (0–1): liest 'question' ODER 'output_text'.
// - Answer-Chips: liest 'answer_helpers' (Fallback: 'followups').
// - risk: mappt 'risk_level' (!= "none") → true; Fallback: 'risk' bool.
// - toMap: schreibt zusätzlich 'answer_helpers' für Kompatibilität.
// - Sanitizer/Heuristik/Closure-Gate unverändert.
// -----------------------------------------------------------------------------

part of reflection_screen;

/// Konfigurierbare Heuristik für den Fallback (wenn der Worker keinen Abschluss
/// signalisiert, aber der Nutzer "wirklich reflektiert" hat).
const int kMinAnswersForMoodFallback = 2; // frühester Mood-Zeitpunkt
const int kMaxAnswersForMoodFallback = 3; // spätestens nach so vielen Antworten

typedef JsonMap = Map<String, dynamic>;

// =============================================================================
// Panda Step
// =============================================================================

class _PandaStep {
  final String mirror;
  final String question;

  /// Answer-Chips (Satzstarter; keine Fragen)
  final List<String> followups;
  final List<String> talkLines;
  final bool risk;

  String? answer;

  _PandaStep({
    required this.mirror,
    required this.question,
    List<String> followups = const [],
    List<String> talkLines = const [],
    this.risk = false,
    String? answer,
  })  : followups = _sanitizeFollowups(followups),
        talkLines = _sanitizeTalk(talkLines),
        answer = _trimOrNull(answer);

  /// Talk-only Schritt (keine Frage/Antwort erwartet).
  factory _PandaStep.talkOnly({
    required String mirror,
    List<String> talkLines = const [],
    bool risk = false,
  }) =>
      _PandaStep(
        mirror: mirror,
        question: '',
        talkLines: talkLines,
        followups: const [],
        risk: risk,
      );

  bool get hasAnswer => (answer ?? '').trim().isNotEmpty;
  bool get expectsAnswer => question.trim().isNotEmpty;

  _PandaStep deepClone() => _PandaStep(
        mirror: mirror,
        question: question,
        followups: List<String>.from(followups),
        talkLines: List<String>.from(talkLines),
        risk: risk,
        answer: answer,
      );

  _PandaStep copyWith({
    String? mirror,
    String? question,
    List<String>? followups,
    List<String>? talkLines,
    bool? risk,
    String? answer,
  }) {
    final step = _PandaStep(
      mirror: mirror ?? this.mirror,
      question: question ?? this.question,
      followups: followups ?? List<String>.from(this.followups),
      talkLines: talkLines ?? List<String>.from(this.talkLines),
      risk: risk ?? this.risk,
      answer: this.answer,
    );
    if (answer != null) step.answer = _trimOrNull(answer);
    return step;
  }

  JsonMap toMap() => <String, dynamic>{
        'mirror': mirror,
        'question': question,
        // Bewusst beide Keys für Abwärts-/Aufwärtskompatibilität:
        'followups': List<String>.from(followups),
        'answer_helpers': List<String>.from(followups),
        'talk': List<String>.from(talkLines),
        'risk': risk,
        'answer': hasAnswer ? answer!.trim() : null,
      };

  static _PandaStep fromMap(JsonMap m) {
    final talk = (m['talk'] is List)
        ? (m['talk'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    // Worker v12.2 liefert answer_helpers; ältere Pfade evtl. followups.
    final fuSrc = (m['answer_helpers'] is List)
        ? (m['answer_helpers'] as List)
        : (m['followups'] is List ? (m['followups'] as List) : const <dynamic>[]);
    final fu = fuSrc.map((e) => e.toString()).toList();

    // Frage kann in 'question' oder 'output_text' stehen (optional).
    final qRaw = _asString(m['question']).trim();
    final q = qRaw.isNotEmpty ? qRaw : _asString(m['output_text']).trim();

    // risk: akzeptiere bool oder risk_level-String.
    final rl = _asString(m['risk_level']).toLowerCase();
    final risk = (m['risk'] == true) || (rl.isNotEmpty && rl != 'none');

    return _PandaStep(
      mirror: _asString(m['mirror']),
      question: q,
      followups: fu,
      talkLines: talk,
      risk: risk,
      answer: _asNullableTrimmedString(m['answer']),
    );
  }

  @override
  String toString() {
    final a = hasAnswer ? 'yes' : 'no';
    return '_PandaStep(mirror:${mirror.length}c, '
        'question:"${_ellipsis(question, 40)}", '
        'followups:${followups.length}, talk:${talkLines.length}, '
        'risk:$risk, hasAnswer:$a)';
  }

  @override
  int get hashCode => Object.hash(
        mirror,
        question,
        risk,
        Object.hashAll(talkLines),
        Object.hashAll(followups),
        (answer ?? ''),
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _PandaStep) return false;
    return mirror == other.mirror &&
        question == other.question &&
        risk == other.risk &&
        _listEquals(talkLines, other.talkLines) &&
        _listEquals(followups, other.followups) &&
        (answer ?? '') == (other.answer ?? '');
  }

  // ---- intern ---------------------------------------------------------------
  static List<String> _sanitizeTalk(List<String> input) {
    if (input.isEmpty) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final raw in input) {
      final t = raw.toString().trim();
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (seen.add(key)) out.add(t);
      if (out.length >= 2) break; // max. 2 Talk-Zeilen
    }
    return out;
  }

  static List<String> _sanitizeFollowups(List<String> input) {
    if (input.isEmpty) return const <String>[];
    final out = <String>[];
    final seen = <String>{};

    String clean(String raw) {
      var s = raw.toString().trim();
      if (s.isEmpty) return '';
      s = s.replaceAll(RegExp(r'^[„“"»«]+|[„“"»«]+$'), '');
      s = s.replaceAll(RegExp(r'[?？.。!！]+$'), ''); // '…' bleibt bewusst stehen
      s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (s.length > 72) s = '${s.substring(0, 72).trimRight()}…';
      return s;
    }

    for (final raw in input) {
      final t = clean(raw);
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (seen.add(key)) out.add(t);
      if (out.length >= 3) break;
    }
    return out;
  }

  static String? _trimOrNull(String? s) {
    final t = (s ?? '').trim();
    return t.isEmpty ? null : t;
  }
}

// =============================================================================
// Round Model
// =============================================================================

class ReflectionRound {
  final String id;
  final DateTime ts;
  final String mode;
  String userInput;
  final List<_PandaStep> steps;

  String? entryId;
  int? moodScore;
  String? moodLabel;
  String? moodIntro; // optionaler Worker-Text für Mood-Phase

  bool allowClosure;

  ReflectionRound({
    required this.id,
    required this.ts,
    required this.mode,
    required this.userInput,
    List<_PandaStep>? steps,
    this.entryId,
    this.moodScore,
    this.moodLabel,
    this.moodIntro,
    this.allowClosure = false,
  })  : assert(id.isNotEmpty),
        assert(mode == 'text' || mode == 'voice'),
        steps = steps ?? <_PandaStep>[];

  // ---- Fortschritt / Status --------------------------------------------------
  bool get hasPendingQuestion {
    if (steps.isEmpty) return false;
    final last = steps.last;
    return last.expectsAnswer && !last.hasAnswer;
  }

  bool get answered => steps.any((s) => s.hasAnswer);
  bool get hasMood => moodScore != null;
  bool get isComplete => answered && hasMood;
  int get answersCount => steps.where((s) => s.hasAnswer).length;
  int get questionsCount => steps.where((s) => s.question.trim().isNotEmpty).length;
  int get reflectionDepth => answersCount;

  bool get readyForMood {
    if (!answered) return false;
    if (allowClosure) return !hasPendingQuestion;

    final a = answersCount;
    final noOpenQ = !hasPendingQuestion;
    final lastIsTalkOnly = steps.isNotEmpty && !steps.last.expectsAnswer;

    if (a >= kMinAnswersForMoodFallback && a < kMaxAnswersForMoodFallback) {
      return noOpenQ && lastIsTalkOnly;
    }
    if (a >= kMaxAnswersForMoodFallback) {
      return noOpenQ;
    }
    return false;
  }

  bool get wantsFollowup {
    if (readyForMood) return false;
    if (hasPendingQuestion) return false;
    return answered && answersCount < kMaxAnswersForMoodFallback;
  }

  Set<String> get normalizedQuestions {
    final out = <String>{};
    for (final s in steps) {
      final q = s.question.trim();
      if (q.isNotEmpty) out.add(normalizeForCompare(q));
    }
    return out;
  }

  bool shouldAppendStep(_PandaStep step) {
    final normQ = normalizeForCompare(step.question.trim());
    if (normQ.isEmpty) return true;
    return !normalizedQuestions.contains(normQ);
  }

  String? get latestAnswer {
    for (int i = steps.length - 1; i >= 0; i--) {
      final a = (steps[i].answer ?? '').trim();
      if (a.isNotEmpty) return a;
    }
    return null;
  }

  String get firstQuestion => steps.isEmpty ? '' : steps.first.question.trim();

  void addStep(_PandaStep step) => steps.add(step);

  // ---- (De-)Serialisierung ---------------------------------------------------
  JsonMap toMap() => <String, dynamic>{
        'id': id,
        'ts': ts.toIso8601String(),
        'mode': mode,
        'userInput': userInput,
        'entryId': entryId,
        'moodScore': moodScore,
        'moodLabel': moodLabel,
        'moodIntro': moodIntro,
        'allowClosure': allowClosure,
        'steps': steps.map((s) => s.toMap()).toList(),
      };

  static ReflectionRound fromMap(JsonMap m) {
    final rawSteps =
        (m['steps'] is List) ? (m['steps'] as List) : const <dynamic>[];
    final parsedSteps = <_PandaStep>[];
    for (final e in rawSteps) {
      if (e is Map) {
        parsedSteps.add(_PandaStep.fromMap(Map<String, dynamic>.from(e)));
      }
    }

    return ReflectionRound(
      id: _asString(m['id']),
      ts: DateTime.tryParse(_asString(m['ts'])) ?? DateTime.now(),
      mode: _asString(m['mode'], fallback: 'text'),
      userInput: _asString(m['userInput']),
      steps: parsedSteps,
      entryId: _asNullableTrimmedString(m['entryId']),
      moodScore: (m['moodScore'] is int) ? m['moodScore'] as int : null,
      moodLabel: _asNullableTrimmedString(m['moodLabel']),
      moodIntro: _asNullableTrimmedString(m['moodIntro']),
      allowClosure: m['allowClosure'] == true,
    );
  }

  ReflectionRound copyWith({
    String? id,
    DateTime? ts,
    String? mode,
    String? userInput,
    List<_PandaStep>? steps,
    String? entryId,
    int? moodScore,
    String? moodLabel,
    String? moodIntro,
    bool? allowClosure,
  }) {
    return ReflectionRound(
      id: id ?? this.id,
      ts: ts ?? this.ts,
      mode: mode ?? this.mode,
      userInput: userInput ?? this.userInput,
      steps: steps ?? List<_PandaStep>.from(this.steps),
      entryId: entryId ?? this.entryId,
      moodScore: moodScore ?? this.moodScore,
      moodLabel: moodLabel ?? this.moodLabel,
      moodIntro: moodIntro ?? this.moodIntro,
      allowClosure: allowClosure ?? this.allowClosure,
    );
  }

  ReflectionRound deepClone() {
    return ReflectionRound(
      id: id,
      ts: ts,
      mode: mode,
      userInput: userInput,
      steps: steps.map((s) => s.deepClone()).toList(),
      entryId: entryId,
      moodScore: moodScore,
      moodLabel: moodLabel,
      moodIntro: moodIntro,
      allowClosure: allowClosure,
    );
  }

  @override
  String toString() =>
      'ReflectionRound(id:$id, steps:${steps.length}, '
      'answers:$answersCount, pending:$hasPendingQuestion, '
      'readyForMood:$readyForMood, wantsFollowup:$wantsFollowup, '
      'mood:$moodLabel/$moodScore, moodIntro:$moodIntro, allowClosure:$allowClosure)';

  @override
  int get hashCode => Object.hash(
        id,
        ts,
        mode,
        userInput,
        entryId,
        moodScore,
        moodLabel,
        moodIntro,
        allowClosure,
        Object.hashAll(steps),
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReflectionRound) return false;
    return id == other.id &&
        ts == other.ts &&
        mode == other.mode &&
        userInput == other.userInput &&
        entryId == other.entryId &&
        moodScore == other.moodScore &&
        moodLabel == other.moodLabel &&
        moodIntro == other.moodIntro &&
        allowClosure == other.allowClosure &&
        _listEquals(steps, other.steps);
  }
}

// =============================================================================
// Shared Normalizer & Utils
// =============================================================================

String normalizeForCompare(String s) {
  final lower = s.toLowerCase();
  return lower.replaceAll(RegExp(r'[^a-z0-9\u00C0-\u017F]+'), '');
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final ai = a[i];
    final bi = b[i];
    if (ai is _PandaStep && bi is _PandaStep) {
      if (ai != bi) return false;
    } else {
      if (ai != bi) return false;
    }
  }
  return true;
}

String _asString(dynamic v, {String fallback = ''}) {
  if (v is String) return v;
  if (v == null) return fallback;
  return v.toString();
}

String? _asNullableTrimmedString(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String _ellipsis(String s, int max) {
  final t = s.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max - 1)}…';
}
