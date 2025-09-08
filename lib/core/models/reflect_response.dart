// lib/core/models/reflect_response.dart
//
// ReflectResponse — robuster Parser für Worker-Antworten (/reflect, /reflect_full)
// - Toleriert:
//   • text/plain → {output_text}
//   • { raw }, { choices: [...] }, { question }, { primary }, {questions[]} …
/*  Ziel:
    - Ein schlankes, Service-unabhängiges Modell
    - Saubere Getter für "primaryQuestion", "mirror", "flow", "session", "riskFlag"
    - Keine Abhängigkeit auf GuidanceService-Typen (vermeidet Zyklen)
*/

class ReflectFlowDTO {
  final bool recommendEnd;
  final bool suggestBreak;
  final String? riskNotice;
  final int? sessionTurn;

  const ReflectFlowDTO({
    required this.recommendEnd,
    required this.suggestBreak,
    this.riskNotice,
    this.sessionTurn,
  });

  factory ReflectFlowDTO.from(Map data) {
    final f = (data['flow'] is Map) ? (data['flow'] as Map) : data;
    return ReflectFlowDTO(
      recommendEnd: _asBool(f['recommend_end']) || _asBool(f['end']),
      suggestBreak: _asBool(f['suggest_break']) || _asBool(f['break']),
      riskNotice: _asString(f['risk_notice']),
      sessionTurn: _asInt(f['session_turn']),
    );
  }

  Map<String, dynamic> toJson() => {
        'recommend_end': recommendEnd,
        'suggest_break': suggestBreak,
        if (riskNotice != null) 'risk_notice': riskNotice,
        if (sessionTurn != null) 'session_turn': sessionTurn,
      };
}

class ReflectSessionDTO {
  final String id;
  final int turn;
  final int? maxTurns;

  const ReflectSessionDTO({required this.id, required this.turn, this.maxTurns});

  factory ReflectSessionDTO.from(Map data) {
    final s = (data['session'] is Map) ? (data['session'] as Map) : data;
    return ReflectSessionDTO(
      id: _asString(s['id']) ?? _asString(s['thread_id']) ?? '',
      turn: _asInt(s['turn']) ?? _asInt(s['turn_index']) ?? 0,
      maxTurns: _asInt(s['max_turns']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'turn': turn,
        if (maxTurns != null) 'max_turns': maxTurns,
      };
}

class ReflectResponse {
  // Rohfelder (optional)
  final String? outputText;     // output_text/question/primary… (rohe Kandidaten)
  final String? mirror;         // mirror/empathy
  final List<String> questions; // questions/qs/multi_questions/alt…
  final List<String> context;   // context/contexts/hints
  final List<String> followups; // followups/follow_up/…
  final List<String> tags;      // tags + normalisierte Schulen
  final String riskFlag;        // "none" | "support" | "crisis" (heuristisch)
  final ReflectFlowDTO flow;
  final ReflectSessionDTO session;

  const ReflectResponse({
    required this.outputText,
    required this.mirror,
    required this.questions,
    required this.context,
    required this.followups,
    required this.tags,
    required this.riskFlag,
    required this.flow,
    required this.session,
  });

  /// Convenience: primäre Leitfrage (für UI)
  String get primaryQuestion {
    final qJoined = _normalizeQuestions(questions);
    if (qJoined.isNotEmpty) return qJoined;
    final p = (outputText ?? '').trim();
    return p.isNotEmpty ? (p.endsWith('?') ? p : '$p?') : '';
  }

  bool get recommendEnd => flow.recommendEnd;
  bool get suggestBreak => flow.suggestBreak;
  bool get isRisk => riskFlag == 'support' || riskFlag == 'crisis';

  Map<String, dynamic> toJson() => {
        'primary': primaryQuestion,
        if (mirror != null) 'mirror': mirror,
        if (questions.isNotEmpty) 'questions': questions,
        if (context.isNotEmpty) 'context': context,
        if (followups.isNotEmpty) 'followups': followups,
        if (tags.isNotEmpty) 'tags': tags,
        'risk_flag': riskFlag,
        'flow': flow.toJson(),
        'session': session.toJson(),
      };

  // ----------------------
  // Factorys / Parser
  // ----------------------

  /// Akzeptiert JSON-Map **oder** plain-String (text/plain).
  factory ReflectResponse.fromAny(dynamic any) {
    if (any is String) {
      final text = any.trim();
      return ReflectResponse._fromLoose(
        data: const {},
        textOnly: text.isEmpty ? null : text,
      );
    }
    if (any is Map) {
      return ReflectResponse._fromLoose(data: any);
    }
    // Fallback: leer
    return ReflectResponse._fromLoose(data: const {});
  }

  factory ReflectResponse._fromLoose({required Map data, String? textOnly}) {
    // choices → content extrahieren (OpenAI-ähnliche Antworten)
    String? fromChoices = _contentFromChoices(data['choices']);

    // Primär-Kandidaten
    final candidates = <String?>[
      textOnly,
      _asString(data['primary']),
      _asString(data['primary_question']),
      _asString(data['lead']),
      _asString(data['lead_question']),
      _asString(data['output_text']),
      _asString(data['question']),
      fromChoices,
      _asString(data['content']),
      _asString(data['raw']),
    ].where((s) => s != null && s.trim().isNotEmpty).toList();

    final primary = candidates.isNotEmpty ? candidates.first!.trim() : null;

    // Fragen-Listen
    final qs = _parseStringList(
      data['questions'] ??
          data['qs'] ??
          data['multi_questions'],
    );
    final alt = _parseStringList(
      data['alt'] ??
          data['alt_question'] ??
          data['alternatives'] ??
          data['alternative'] ??
          data['secondary_question'] ??
          data['secondary'] ??
          data['options'],
    );
    final allQs = _dedupe([...qs, ...alt]);

    // Mirror
    final mirror = _asString(data['mirror']) ?? _asString(data['empathy']);

    // Kontext / Followups
    final ctx = _parseStringList(data['context'] ?? data['contexts'] ?? data['hints']);
    final flw = _parseStringList(
      data['followups'] ?? data['follow_up'] ?? data['followup_questions'],
    );

    // Flow / Session
    final flow = ReflectFlowDTO.from((data['flow'] is Map) ? data : {'flow': data['flow']});
    final session = ReflectSessionDTO.from((data['session'] is Map) ? data : {'session': data['session']});

    // Schulen/Tags
    final schools = _normalizeSchools(_parseStringList(
      data['schools'] ?? data['therapeutic_schools'] ?? data['approaches'],
    ));
    final tags = _dedupe([..._parseStringList(data['tags']), ...schools]);

    // Risiko
    final riskBool = _asBool(data['risk']);
    final riskLevelRoot = (_asString(data['risk_level']) ??
            _asString(data['risk_flag']) ??
            _asString(data['risk']))
        ?.toLowerCase()
        .trim();

    final riskFlag = riskBool
        ? 'support'
        : (flow.riskNotice != null
            ? 'support'
            : (riskLevelRoot == 'high' || riskLevelRoot == 'crisis' ? 'crisis' : 'none'));

    return ReflectResponse(
      outputText: primary,
      mirror: (mirror?.trim().isEmpty ?? true) ? null : mirror!.trim(),
      questions: allQs,
      context: ctx,
      followups: flw,
      tags: tags,
      riskFlag: riskFlag,
      flow: flow,
      session: session,
    );
  }
}

// ----------------------
// Parser-Helfer (intern)
// ----------------------

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  try { return v.toString(); } catch (_) { return null; }
}

int? _asInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
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
        .split(RegExp(r'\n+|[•\-]\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? <String>[s] : parts;
  }
  return const <String>[];
}

String _normalizeQuestions(List<String> qs) {
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
  return clean.first; // UI nutzt vorrangig die erste
}

List<String> _dedupe(List<String> items) {
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

/// OpenAI-artige Antworten: {choices:[{message:{content:"..."}]}] oder {choices:[{text:"..."}]}
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

// Therapeutische Schulen → normalisierte Top-Labels
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
    if (_schoolAliases.containsKey(k)) {
      out.add(_schoolAliases[k]!);
      continue;
    }
    if (k.contains('kvt') || k.contains('cognitive') || k.contains('behavior')) {
      out.add('CBT/KVT');
    } else if (k.contains('act')) out.add('ACT');
    else if (k.contains('dbt')) out.add('DBT');
    else if (k.contains('schema')) out.add('Schematherapie');
    else if (k.contains('system')) out.add('Systemisch');
    else if (k.contains('dynam')) out.add('Psychodynamisch');
    else if (k.contains('human') || k.contains('client') || k.contains('person')) out.add('Humanistisch');
    else if (k.contains('solution')) out.add('Lösungsfokussiert');
    else if (k.contains('motiv')) out.add('Motivational Interviewing');
    else if (k.contains('mindful') || k.contains('achtsam') || k.contains('mbct')) out.add('Achtsamkeit');
  }
  return out.toList(growable: false);
}
