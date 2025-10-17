// lib/models/reflect_response.dart
/* ignore_for_file: non_constant_identifier_names */

import 'dart:convert';

class ReflectResponse {
  final String outputText;
  final String? mirror;
  final List<String> context;
  final List<String> followups;
  final ReflectFlow? flow;
  final ReflectSession? session;
  final List<String> tags;
  final String riskFlag;
  final List<String> questions;
  final List<String> talk;

  const ReflectResponse({
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

  // — UI-Shims (snake_case bewusst) —
  // ignore: non_constant_identifier_names
  String get output_text => outputText;
  // ignore: non_constant_identifier_names
  String get risk_level =>
      (riskFlag == 'crisis') ? 'high' : (riskFlag == 'support' ? 'mild' : 'none');

  bool get risk => riskFlag == 'support' || riskFlag == 'crisis';
  bool get recommendEnd => flow?.recommendEnd == true;
  bool get suggestBreak => flow?.suggestBreak == true;
  bool get canReflect => flow?.allowReflect != false;
  bool get isTalkOnly => flow?.talkOnly == true;

  Map<String, dynamic> toJson() => {
        'output_text': outputText,
        if (mirror != null && mirror!.trim().isNotEmpty) 'mirror': mirror,
        if (context.isNotEmpty) 'context': context,
        if (followups.isNotEmpty) 'followups': followups,
        if (flow != null) 'flow': flow!.toJson(),
        if (session != null) 'session': session!.toJson(),
        if (tags.isNotEmpty) 'tags': tags,
        'risk_level': risk_level,
        if (questions.isNotEmpty) 'questions': questions,
        if (talk.isNotEmpty) 'talk': talk,
      };

  String toJsonString({bool pretty = false}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson())
             : jsonEncode(toJson());

  ReflectResponse copyWith({
    String? outputText,
    String? mirror,
    List<String>? context,
    List<String>? followups,
    ReflectFlow? flow,
    ReflectSession? session,
    List<String>? tags,
    String? riskFlag,
    List<String>? questions,
    List<String>? talk,
  }) {
    return ReflectResponse(
      outputText: outputText ?? this.outputText,
      mirror: mirror ?? this.mirror,
      context: context ?? this.context,
      followups: followups ?? this.followups,
      flow: flow ?? this.flow,
      session: session ?? this.session,
      tags: tags ?? this.tags,
      riskFlag: riskFlag ?? this.riskFlag,
      questions: questions ?? this.questions,
      talk: talk ?? this.talk,
    );
  }

  @override
  String toString() => 'ReflectResponse(${toJson()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReflectResponse &&
          other.outputText == outputText &&
          other.mirror == mirror &&
          _listEq(other.context, context) &&
          _listEq(other.followups, followups) &&
          other.flow == flow &&
          other.session == session &&
          _listEq(other.tags, tags) &&
          other.riskFlag == riskFlag &&
          _listEq(other.questions, questions) &&
          _listEq(other.talk, talk));

  @override
  int get hashCode =>
      outputText.hashCode ^
      (mirror?.hashCode ?? 0) ^
      _listHash(context) ^
      _listHash(followups) ^
      (flow?.hashCode ?? 0) ^
      (session?.hashCode ?? 0) ^
      _listHash(tags) ^
      riskFlag.hashCode ^
      _listHash(questions) ^
      _listHash(talk);

  // — Factories (tolerant) —
  factory ReflectResponse.fromJsonAny(dynamic jsonLike) {
    if (jsonLike is ReflectResponse) return jsonLike;
    try {
      if (jsonLike is String) {
        final obj = jsonDecode(jsonLike);
        if (obj is Map<String, dynamic>) return ReflectResponse.fromMap(obj);
        if (obj is Map) return ReflectResponse.fromMap(obj.cast<String, dynamic>());
        final txt = jsonLike.toString().trim();
        return ReflectResponse(
          outputText: txt.isEmpty ? '…' : txt,
          mirror: null,
          context: const [],
          followups: const [],
          flow: const ReflectFlow(recommendEnd: false, suggestBreak: false),
          session: null,
          tags: const [],
          riskFlag: 'none',
          questions: const [],
          talk: const [],
        );
      } else if (jsonLike is Map<String, dynamic>) {
        return ReflectResponse.fromMap(jsonLike);
      } else if (jsonLike is Map) {
        return ReflectResponse.fromMap(jsonLike.cast<String, dynamic>());
      }
    } catch (_) {}
    return const ReflectResponse(
      outputText:
          'ZenYourself konnte gerade keine Frage laden. Bitte prüfe kurz deine Internetverbindung.',
      mirror: null,
      context: [],
      followups: [],
      flow: ReflectFlow(recommendEnd: false, suggestBreak: false),
      session: null,
      tags: [],
      riskFlag: 'none',
      questions: [],
      talk: [],
    );
  }

  factory ReflectResponse.fromMap(Map<String, dynamic> map) {
    // 1) Fragen sammeln
    final qsList = _parseStringList(
      map['questions'] ?? map['multi_questions'] ?? map['qs'],
    );
    final altList = _parseStringList(
      map['alt'] ??
          map['alt_question'] ??
          map['alternatives'] ??
          map['alternative'] ??
          map['secondary_question'] ??
          map['secondary'] ??
          map['options'],
    );
    final allQs = _dedupeStrings([...qsList, ...altList]);

    // 2) Primärtext-Kandidaten
    final fromChoices = _contentFromChoices(map['choices']);
    final candidatesRaw = <String?>[
      _asString(map['primary']),
      _asString(map['primary_question']),
      _asString(map['lead']),
      _asString(map['lead_question']),
      _asString(map['output_text']),
      _asString(map['question']),
      if (_isNotEmpty(fromChoices)) fromChoices!.trim(),
      _asString(map['content']),
      _asString(map['raw']),
    ];
    final candidates = candidatesRaw
        .where((s) => _isNotEmpty(s))
        .map((s) => s!.trim())
        .toList(growable: false);

    final joinedQuestions = _normalizeQuestions(allQs);
    final primaryRaw = candidates.isNotEmpty ? candidates.first : '';
    final primary = joinedQuestions.isNotEmpty ? joinedQuestions : primaryRaw;
    final output = primary.trim().isEmpty ? _errorHint : _ensureQuestionMark(primary.trim());

    // 3) Mirror
    final mirrorRaw = _asString(map['mirror']) ?? _asString(map['empathy']);
    final String? mirror = _isNotEmpty(mirrorRaw) ? mirrorRaw!.trim() : null;

    // 4) Kontext / Followups / Talk
    final ctxDyn = (map['context'] as List?) ??
                   (map['contexts'] as List?) ??
                   (map['hints'] as List?) ??
                   const [];
    final flwDyn = (map['followups'] as List?) ??
                   (map['follow_up'] as List?) ??
                   (map['followup_questions'] as List?) ??
                   const [];
    final talkDyn = (map['talk'] as List?) ?? const [];

    final ctx  = ctxDyn .map((e) => e?.toString().trim() ?? '')
                        .where((s) => s.isNotEmpty).take(4).toList(growable: false);
    final flw  = flwDyn .map((e) => e?.toString().trim() ?? '')
                        .where((s) => s.isNotEmpty).take(4).toList(growable: false);
    final talk = talkDyn.map((e) => e?.toString().trim() ?? '')
                        .where((s) => s.isNotEmpty).take(2).toList(growable: false);

    // 5) Flow
    final flowJson = (map['flow'] as Map?) ?? const {};
    final flow = ReflectFlow.fromMap(flowJson.cast<String, dynamic>());

    // 6) Session
    final sessionJson = (map['session'] as Map?) ?? const {};
    final session = ReflectSession.fromMap(sessionJson.cast<String, dynamic>());

    // 7) Tags/Schulen
    final schoolsDyn = (map['schools'] as List?) ??
                       (map['therapeutic_schools'] as List?) ??
                       (map['approaches'] as List?) ??
                       const [];
    final normalizedSchools = _normalizeSchools(_parseStringList(schoolsDyn));
    final workerTags = _parseStringList(map['tags']);
    final tags = _dedupeStrings([...workerTags, ...normalizedSchools]);

    // 8) Risiko
    final riskLevelRoot = (_asString(map['risk_level']) ??
                           _asString(map['risk_flag']) ??
                           _asString(map['risk']) ??
                           'none')
        .toLowerCase()
        .trim();

    final riskFlag = (riskLevelRoot == 'high' || riskLevelRoot == 'crisis')
        ? 'crisis'
        : (riskLevelRoot == 'mild' ? 'support' : 'none');

    return ReflectResponse(
      outputText: output,
      mirror: mirror,
      context: ctx,
      followups: flw,
      flow: flow,
      session: session,
      tags: tags,
      riskFlag: riskFlag,
      questions: allQs,
      talk: talk,
    );
  }
}

class ReflectFlow {
  final bool recommendEnd;
  final bool suggestBreak;
  final String? riskNotice;
  final int? sessionTurn;
  final bool talkOnly;
  final bool allowReflect;

  const ReflectFlow({
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
        if (riskNotice != null && riskNotice!.trim().isNotEmpty) 'risk_notice': riskNotice,
        if (sessionTurn != null) 'session_turn': sessionTurn,
        if (talkOnly) 'talk_only': true,
        'allow_reflect': allowReflect,
      };

  factory ReflectFlow.fromMap(Map<String, dynamic> map) {
    if (map.isEmpty) {
      return const ReflectFlow(recommendEnd: false, suggestBreak: false);
    }
    final recommendEnd = (map['recommend_end'] == true) || (map['end'] == true);
    final suggestBreak = (map['suggest_break'] == true) || (map['break'] == true);
    final riskNotice = _asString(map['risk_notice']);
    final sessionTurn = (map['session_turn'] is num) ? (map['session_turn'] as num).toInt() : null;
    final talkOnly = map['talk_only'] == true;
    final allowReflect = map['allow_reflect'] != false;
    return ReflectFlow(
      recommendEnd: recommendEnd,
      suggestBreak: suggestBreak,
      riskNotice: _isNotEmpty(riskNotice) ? riskNotice : null,
      sessionTurn: sessionTurn,
      talkOnly: talkOnly,
      allowReflect: allowReflect,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReflectFlow &&
          other.recommendEnd == recommendEnd &&
          other.suggestBreak == suggestBreak &&
          other.riskNotice == riskNotice &&
          other.sessionTurn == sessionTurn &&
          other.talkOnly == talkOnly &&
          other.allowReflect == allowReflect);

  @override
  int get hashCode =>
      (recommendEnd ? 1 : 0) ^
      (suggestBreak ? 2 : 0) ^
      (riskNotice?.hashCode ?? 0) ^
      (sessionTurn ?? -1) ^
      (talkOnly ? 4 : 0) ^
      (allowReflect ? 8 : 0);
}

class ReflectSession {
  final String threadId;
  final int turnIndex;
  final int maxTurns;

  const ReflectSession({
    required this.threadId,
    required this.turnIndex,
    required this.maxTurns,
  });

  Map<String, dynamic> toJson() => {
        'id': threadId,
        'turn': turnIndex,
        'max_turns': maxTurns,
      };

  factory ReflectSession.fromMap(Map<String, dynamic> map) {
    if (map.isEmpty) {
      return const ReflectSession(threadId: '', turnIndex: 0, maxTurns: 3);
    }
    final id = _asString(map['id']) ?? _asString(map['thread_id']) ?? '';
    final turn = (map['turn'] is num)
        ? (map['turn'] as num).toInt()
        : (map['turn_index'] is num)
            ? (map['turn_index'] as num).toInt()
            : 0;
    final max = (map['max_turns'] is num) ? (map['max_turns'] as num).toInt() : 3;
    return ReflectSession(
      threadId: id,
      turnIndex: turn,
      maxTurns: max,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReflectSession &&
          other.threadId == threadId &&
          other.turnIndex == turnIndex &&
          other.maxTurns == maxTurns);

  @override
  int get hashCode => threadId.hashCode ^ turnIndex.hashCode ^ maxTurns.hashCode;
}

// — Utils (privat) —
const String _errorHint =
    'ZenYourself hat die Blümchen nicht gefunden. Bitte prüfe kurz deine Internetverbindung.';

bool _isNotEmpty(String? s) => s != null && s.trim().isNotEmpty;

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

List<String> _parseStringList(dynamic v) {
  if (v == null) return const <String>[];
  if (v is List) {
    return v
        .map((e) => _asString(e) ?? '')
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
        .toList(growable: false);
    return parts.isEmpty ? <String>[s] : parts;
  }
  return const <String>[];
}

String _ensureQuestionMark(String s) => s.endsWith('?') ? s : '$s?';

List<String> _dedupeStrings(List<String> items) {
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

String? _contentFromChoices(dynamic choicesDyn) {
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

String _normalizeQuestions(List<String> qs) {
  for (final q in qs) {
    final t = q.trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}

int _listHash(List<dynamic> xs) {
  var h = 0;
  for (final x in xs) {
    h = 0x1fffffff & (h + x.hashCode);
    h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
    h ^= (h >> 6);
  }
  h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
  h ^= (h >> 11);
  h = 0x1fffffff & (h + ((0x00003fff & h) << 15));
  return h;
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const Map<String, String> _schoolAliases = {
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

List<String> _normalizeSchools(List<String> raw) {
  if (raw.isEmpty) return const <String>[];
  final out = <String>{};
  for (final r in raw) {
    final s = r.trim();
    if (s.isEmpty) continue;
    final k = s.toLowerCase();
    final alias = _schoolAliases[k];
    if (alias != null) {
      out.add(alias);
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
      out.add(s.length <= 40 ? s : '${s.substring(0, 39)}…');
    }
  }
  return out.toList(growable: false);
}
