// lib/models/reflection_models.dart
// v8 — Oxford-Zen (stable)
//
// Zweck:
//   Zentrale, stabile Modelle für Reflexions-Antworten des Workers/Services.
//   Kernobjekt: MirrorQuestion { mirror, question, followups[], risk, tags }.
//
// Designziele:
//   • Immutable, null-sicher, leicht zu serialisieren.
//   • Tolerant gegenüber variierender Server-Payload (Synonyme).
//   • Sanitizer (Trim, Dedupe, Wort-Limit für Frage ≤ 30).
//
// Contract (Server):
//   /reflect        → text/plain (nur die Frage)
//   /reflect_full   → JSON { mirror, question, followups[], risk, tags, talk?, risk_level?, flow?, session? }
//
// Lizenz: Internal / ZenYourself.

import 'dart:collection';
import 'package:meta/meta.dart';

/// Risiko-Level (vom Worker optional geliefert).
enum RiskLevel { none, low, medium, high }

extension RiskLevelX on RiskLevel {
  String get asString {
    switch (this) {
      case RiskLevel.none:
        return 'none';
      case RiskLevel.low:
        return 'low';
      case RiskLevel.medium:
        return 'medium';
      case RiskLevel.high:
        return 'high';
    }
  }

  static RiskLevel parse(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    switch (v) {
      case 'high':
        return RiskLevel.high;
      case 'medium':
        return RiskLevel.medium;
      case 'low':
        return RiskLevel.low;
      case '':
      case 'none':
      default:
        return RiskLevel.none;
    }
  }
}

/// Leichte Parse-Exception mit Feldhinweis.
@immutable
class ReflectionParseException implements FormatException {
  @override
  final String message;
  @override
  final dynamic source;
  @override
  final int? offset;

  const ReflectionParseException(this.message, [this.source, this.offset]);

  @override
  String toString() => 'ReflectionParseException: $message';

  @override
  String get name => 'ReflectionParseException';
}

/// Kernobjekt für UI/Journal.
/// Mirror (2–6 Sätze), genau 1 Leitfrage (≤ 30 Wörter), Followups (≤ 3), Risk, Tags, Talk, Flow, Session.
@immutable
class MirrorQuestion {
  final String mirror;
  final String question;
  final UnmodifiableListView<String> followups;
  final bool risk;
  final RiskLevel riskLevel;
  final UnmodifiableListView<String> tags;
  final UnmodifiableListView<String> talk;
  final Map<String, dynamic>? flow;
  final Object? session;
  final Map<String, dynamic> extra;

  static const int defaultQuestionWordLimit = 30;

  const MirrorQuestion._internal({
    required this.mirror,
    required this.question,
    required List<String> followups,
    required this.risk,
    required this.riskLevel,
    required List<String> tags,
    required List<String> talk,
    required this.flow,
    required this.session,
    required Map<String, dynamic> extra,
  })  : followups = UnmodifiableListView<String>(followups),
        tags = UnmodifiableListView<String>(tags),
        talk = UnmodifiableListView<String>(talk),
        extra = Map.unmodifiable(extra);

  /// Sicheres leeres Objekt.
  factory MirrorQuestion.empty() => MirrorQuestion._internal(
        mirror: '',
        question: '',
        followups: const [],
        risk: false,
        riskLevel: RiskLevel.none,
        tags: const [],
        talk: const [],
        flow: null,
        session: null,
        extra: const {},
      );

  /// Basic-Erzeuger (mit optionaler Sanitization).
  factory MirrorQuestion.basic({
    required String mirror,
    required String question,
    List<String>? followups,
    bool risk = false,
    RiskLevel riskLevel = RiskLevel.none,
    List<String>? tags,
    List<String>? talk,
    Map<String, dynamic>? flow,
    Object? session,
    bool sanitize = true,
    int wordLimit = defaultQuestionWordLimit,
  }) {
    final cleaned = sanitize
        ? _Sanitizer.normalizeAll(
            mirror: mirror,
            question: question,
            followups: followups,
            tags: tags,
            talk: talk,
            wordLimit: wordLimit,
          )
        : _Normalized(
            mirror: mirror.trim(),
            question: question.trim(),
            followups: _Sanitizer._cleanList(followups),
            tags: _Sanitizer._cleanList(tags),
            talk: _Sanitizer._cleanList(talk),
          );

    return MirrorQuestion._internal(
      mirror: cleaned.mirror,
      question: cleaned.question,
      followups: cleaned.followups,
      risk: risk,
      riskLevel: riskLevel,
      tags: cleaned.tags,
      talk: cleaned.talk,
      flow: flow == null ? null : Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(flow)),
      session: session,
      extra: const {},
    );
  }

  /// Tolerantes JSON-Parsing aus `/reflect_full`.
  factory MirrorQuestion.fromJson(Map<String, dynamic> json,
      {bool sanitize = true, int wordLimit = defaultQuestionWordLimit}) {
    if (json.isEmpty) return MirrorQuestion.empty();

    String pickString(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is String && v.trim().isNotEmpty) return v;
      }
      return '';
    }

    List<String> pickStringList(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is List) {
          return v
              .map((e) => e?.toString() ?? '')
              .where((e) => e.trim().isNotEmpty)
              .toList(growable: false);
        }
      }
      return const [];
    }

    Map<String, dynamic>? pickMap(String key) {
      final v = json[key];
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    // Mirror, Frage, Followups
    final rawMirror = pickString(const ['mirror', 'reflect_mirror', 'out_mirror']);
    String rawQuestion = pickString(const ['question', 'outputText', 'output_text']);
    final questionsList = pickStringList(const ['questions']);
    if (rawQuestion.isEmpty && questionsList.isNotEmpty) {
      rawQuestion = questionsList.first;
    }

    final rawFollowups = pickStringList(const [
      'followups',
      'follow_up',
      'followup',
      'followup_questions',
      'follow_up_questions',
    ]);

    // Talk, Tags, Risk
    final rawTalk = pickStringList(const ['talk', 'smalltalk', 'warm_talk']);
    final rawTags =
        pickStringList(const ['tags', 'labels', 'topics', 'categories', 'intents']);

    final rawRiskBool = json['risk'];
    final rawRiskLevel = pickString(const ['risk_level', 'riskLevel', 'severity']);

    final flow = pickMap('flow');
    final session = json['session'];

    // Sanitization
    final normalized = sanitize
        ? _Sanitizer.normalizeAll(
            mirror: rawMirror,
            question: rawQuestion,
            followups: rawFollowups,
            tags: rawTags,
            talk: rawTalk,
            wordLimit: wordLimit,
          )
        : _Normalized(
            mirror: rawMirror.trim(),
            question: rawQuestion.trim(),
            followups: _Sanitizer._cleanList(rawFollowups),
            tags: _Sanitizer._cleanList(rawTags),
            talk: _Sanitizer._cleanList(rawTalk),
          );

    // Risk ableiten
    final level = RiskLevelX.parse(rawRiskLevel);
    final bool risk = (rawRiskBool is bool && rawRiskBool) || level == RiskLevel.high;

    // Extras (Forward-Compat)
    final known = <String>{
      'mirror',
      'reflect_mirror',
      'out_mirror',
      'question',
      'outputText',
      'output_text',
      'questions',
      'followups',
      'follow_up',
      'followup',
      'followup_questions',
      'follow_up_questions',
      'talk',
      'smalltalk',
      'warm_talk',
      'tags',
      'labels',
      'topics',
      'categories',
      'intents',
      'risk',
      'risk_level',
      'riskLevel',
      'severity',
      'flow',
      'session',
    };

    final extras = <String, dynamic>{};
    json.forEach((k, v) {
      if (!known.contains(k)) extras[k] = v;
    });

    return MirrorQuestion._internal(
      mirror: normalized.mirror,
      question: normalized.question,
      followups: normalized.followups,
      risk: risk,
      riskLevel: level,
      tags: normalized.tags,
      talk: normalized.talk,
      flow: flow == null ? null : Map<String, dynamic>.unmodifiable(flow),
      session: session,
      extra: extras.isEmpty ? const {} : Map<String, dynamic>.unmodifiable(extras),
    );
  }

  /// Serialisiert in kanonischen v8-Key-Satz.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'mirror': mirror,
        'question': question,
        'followups': followups.toList(growable: false),
        'risk': risk,
        'risk_level': riskLevel.asString,
        if (tags.isNotEmpty) 'tags': tags.toList(growable: false),
        if (talk.isNotEmpty) 'talk': talk.toList(growable: false),
        if (flow != null) 'flow': flow,
        if (session != null) 'session': session,
        if (extra.isNotEmpty) 'extra': extra,
      };

  /// Defensive Normalisierung.
  MirrorQuestion normalized({int wordLimit = defaultQuestionWordLimit}) {
    final n = _Sanitizer.normalizeAll(
      mirror: mirror,
      question: question,
      followups: followups,
      tags: tags,
      talk: talk,
      wordLimit: wordLimit,
    );
    return copyWith(
      mirror: n.mirror,
      question: n.question,
      followups: n.followups,
      tags: n.tags,
      talk: n.talk,
    );
  }

  bool get hasQuestion => question.trim().isNotEmpty;
  bool get hasMirror => mirror.trim().isNotEmpty;

  MirrorQuestion copyWith({
    String? mirror,
    String? question,
    List<String>? followups,
    bool? risk,
    RiskLevel? riskLevel,
    List<String>? tags,
    List<String>? talk,
    Map<String, dynamic>? flow,
    Object? session,
    Map<String, dynamic>? extra,
  }) {
    return MirrorQuestion._internal(
      mirror: mirror ?? this.mirror,
      question: question ?? this.question,
      followups: followups ?? this.followups,
      risk: risk ?? this.risk,
      riskLevel: riskLevel ?? this.riskLevel,
      tags: tags ?? this.tags,
      talk: talk ?? this.talk,
      flow: flow ?? this.flow,
      session: session ?? this.session,
      extra: extra ?? this.extra,
    );
  }

  @override
  String toString() =>
      'MirrorQuestion(mirror:${mirror.isEmpty ? "∅" : "…"}, question:"$question", followups:${followups.length}, risk:$risk/${riskLevel.asString})';

  @override
  bool operator ==(Object other) {
    return other is MirrorQuestion &&
        other.mirror == mirror &&
        other.question == question &&
        _listEq(other.followups, followups) &&
        other.risk == risk &&
        other.riskLevel == riskLevel &&
        _listEq(other.tags, tags) &&
        _listEq(other.talk, talk) &&
        _mapEq(other.flow, flow) &&
        other.session == session;
  }

  @override
  int get hashCode =>
      mirror.hashCode ^
      question.hashCode ^
      _listHash(followups) ^
      risk.hashCode ^
      riskLevel.hashCode ^
      _listHash(tags) ^
      _listHash(talk) ^
      (flow?.hashCode ?? 0) ^
      (session?.hashCode ?? 0);

  // ---- kleine Hilfsvergleiche ----
  static bool _listEq(List a, List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _listHash(List list) {
    var h = 0;
    for (final e in list) {
      h = 0x1fffffff & (h + e.hashCode);
      h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
      h ^= (h >> 6);
    }
    h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
    h ^= (h >> 11);
    h = 0x1fffffff & (h + ((0x00003fff & h) << 15));
    return h;
  }

  static bool _mapEq(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

/// Vereinfachtes Modell für `/reflect` (nur Frage im Klartext).
@immutable
class ReflectQuestionOnly {
  final String question;
  const ReflectQuestionOnly(this.question);

  factory ReflectQuestionOnly.fromPlainText(String raw,
      {int wordLimit = MirrorQuestion.defaultQuestionWordLimit}) {
    final q = _Sanitizer._sanitizeQuestion(raw, wordLimit: wordLimit);
    return ReflectQuestionOnly(q);
  }

  Map<String, dynamic> toJson() => {'question': question};
  @override
  String toString() => 'ReflectQuestionOnly("$question")';
}

/// V8 State-Machine-Schritte (optional für UI-Flow).
enum ReflectionStage { intro, typingDraft, waitingAi, question, answering, gate }

extension ReflectionStageX on ReflectionStage {
  bool get isIntro => this == ReflectionStage.intro;
  bool get isTyping => this == ReflectionStage.typingDraft;
  bool get isWaitingAi => this == ReflectionStage.waitingAi;
  bool get isQuestion => this == ReflectionStage.question;
  bool get isAnswering => this == ReflectionStage.answering;
  bool get isGate => this == ReflectionStage.gate;

  ReflectionStage nextAfterAnswer() => ReflectionStage.gate;
  ReflectionStage nextAfterSend() => ReflectionStage.waitingAi;
}

/// Interne Normalisierungsstruktur.
class _Normalized {
  final String mirror;
  final String question;
  final List<String> followups;
  final List<String> tags;
  final List<String> talk;

  _Normalized({
    required this.mirror,
    required this.question,
    required this.followups,
    required this.tags,
    required this.talk,
  });
}

/// Text-Sanitizer: Trim, Space-Normalize, Dedupe, Wortlimit für Frage.
class _Sanitizer {
  static _Normalized normalizeAll({
    required String mirror,
    required String question,
    Iterable<String>? followups,
    Iterable<String>? tags,
    Iterable<String>? talk,
    int wordLimit = MirrorQuestion.defaultQuestionWordLimit,
  }) {
    final cleanMirror = _normalizeWhitespace(mirror);
    final cleanQuestion = _sanitizeQuestion(question, wordLimit: wordLimit);

    final fups = _cleanList(followups);
    final tgs = _cleanList(tags);
    final talkLines = _cleanList(talk);

    // Followups deduplizieren und Frage vermeiden
    final fupsDedup = _dedupePreserveOrder(
      fups.where((e) => _normCmp(e) != _normCmp(cleanQuestion)),
    ).take(3).toList(growable: false);

    // Talk auf max. 2 Zeilen
    final talkCap = talkLines.take(2).toList(growable: false);

    return _Normalized(
      mirror: cleanMirror,
      question: cleanQuestion,
      followups: fupsDedup,
      tags: _dedupePreserveOrder(tgs).toList(growable: false),
      talk: talkCap,
    );
  }

  static String _sanitizeQuestion(String raw, {int wordLimit = 30}) {
    var q = _normalizeWhitespace(raw);

    // Übliche Präfix-Schablonen neutralisieren
    q = q.replaceFirst(
      RegExp(
        r"""^\s*(im blick auf|bezogen auf|in bezug auf|im fokus|zum thema|thema|aspekt)\s*[:\-–—]?\s*(?:["'])?.+?(?:["'])?\s*[:,\-–—]?\s*""",
        caseSensitive: false,
      ),
      '',
    );

    // Ellipsen/Interpunktion glätten
    q = q
        .replaceAll(RegExp(r'\.{3,}'), '…')
        .replaceAll(RegExp(r'…{2,}'), '…')
        .replaceAllMapped(RegExp(r'\s+([?!.,;:])'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'([?!.,;:])(?!\s|$)'), (m) => '${m.group(1)} ');

    // Wortlimit
    q = _limitWords(q, wordLimit);

    // Fragezeichen anhängen, falls nötig
    if (!q.endsWith('?') && !q.endsWith('…')) q = '$q?';

    return q.trim();
  }

  static String _normalizeWhitespace(String s) =>
      s.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _limitWords(String s, int max) {
    final parts = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.length <= max) return s.trim();
    return '${parts.take(max).join(' ')}…';
  }

  static List<String> _cleanList(Iterable<String>? src) {
    if (src == null) return const [];
    return src
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .map(_normalizeWhitespace)
        .toList(growable: false);
  }

  static Iterable<String> _dedupePreserveOrder(Iterable<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final it in items) {
      final key = _normCmp(it);
      if (seen.add(key)) out.add(it);
    }
    return out;
  }

  static String _normCmp(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u00C0-\u017F]+'), '');
}
