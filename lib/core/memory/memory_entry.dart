// [BASELINE] lib/core/memory/memory_entry.dart — v6.6.0 (2025-11-08)
// MERGE SIGNAL: kompatibel zu v6.4.x; erweitert um tags/canon + robustere Parser
//
// MemoryEntry & MemoryFact — DTOs fürs lokale Kontext-Gedächtnis (snake_case, defensiv)
// -------------------------------------------------------------------------------------
// Rückwärtskompatibel zu v6.3.x/6.4.x. Neues in v6.6.0 (non-breaking):
// • MemoryFact erweitert um: tags[List<String>] und canon[String].
// • fromMap() toleranter: Aliasse active_facet/topic_pin, score/insight_score/confidence.
// • toMap() bleibt snake_case-kompatibel; DateTimes immer ISO-UTC.
// • Kleinere Robustheits-Verbesserungen (Parsing/Bounds).
//
// Entry Kompatibilität (v1 → v2):
// • sessionId                ⇆  id / session_id
// • createdAt (ISO-UTC)      ⇆  created_at / ts
// • contextFacets[List<Facet>] ⇆  context_facets / facets[List<String>]
// • insightScore[Map|num]    ⇆  insight_score
// • mood{mental,physical}    ⇆  Strings/Nums; Aliasse: icon/body/somatic
// • summary / nextHint       ⇆  summary / next_hint

import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/insight_models.dart';

@immutable
class MemoryEntry {
  final String sessionId;
  final DateTime createdAt;
  final List<Facet> contextFacets;
  final InsightScore? insightScore;
  final MoodPair? mood;
  final String? summary;
  final String? nextHint;

  const MemoryEntry({
    required this.sessionId,
    required this.createdAt,
    required this.contextFacets,
    this.insightScore,
    this.mood,
    this.summary,
    this.nextHint,
  });

  MemoryEntry copyWith({
    String? sessionId,
    DateTime? createdAt,
    List<Facet>? contextFacets,
    InsightScore? insightScore,
    MoodPair? mood,
    String? summary,
    String? nextHint,
  }) {
    return MemoryEntry(
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      contextFacets: contextFacets != null
          ? List<Facet>.unmodifiable(List<Facet>.from(contextFacets))
          : List<Facet>.unmodifiable(List<Facet>.from(this.contextFacets)),
      insightScore: insightScore ?? this.insightScore,
      mood: mood ?? this.mood,
      summary: summary ?? this.summary,
      nextHint: nextHint ?? this.nextHint,
    );
  }

  // ---------- Helpers ---------------------------------------------------------

  static String _asString(dynamic x) => (x == null) ? '' : x.toString();

  static int _asMood(dynamic x, {int fallback = 2}) {
    if (x is num) return x.clamp(0, 4).toInt();
    final s = _asString(x).trim();
    final n = int.tryParse(s);
    return (n == null) ? fallback : n.clamp(0, 4).toInt();
  }

  static DateTime _asDateTimeUtc(dynamic x) {
    final s = _asString(x).trim();
    final dt = DateTime.tryParse(s);
    return (dt ?? DateTime.now()).toUtc();
  }

  // ---------- (De-)Serialisierung (Entry) ------------------------------------

  factory MemoryEntry.fromMap(Map<String, dynamic> m) {
    final sidRaw = m['sessionId'] ?? m['session_id'] ?? m['id'];
    final sid = _asString(sidRaw).trim();

    final createdRaw = m['createdAt'] ?? m['created_at'] ?? m['ts'];
    final createdAt = _asDateTimeUtc(createdRaw);

    final facets = <Facet>[];
    final cfRaw = m['contextFacets'] ?? m['context_facets'] ?? m['facets'];
    if (cfRaw is List) {
      for (final e in cfRaw) {
        if (e is Map) {
          try {
            facets.add(Facet.fromMap(Map<String, dynamic>.from(e)));
          } catch (_) {/* ignore */}
        } else {
          final s = _asString(e).trim();
          if (s.isNotEmpty) facets.add(Facet(key: s, label: s));
        }
      }
    }

    InsightScore? insightScore;
    final rawInsight = m['insightScore'] ?? m['insight_score'];
    if (rawInsight is Map) {
      try {
        insightScore = InsightScore.fromMap(Map<String, dynamic>.from(rawInsight));
      } catch (_) {/* ignore */}
    } else if (rawInsight is num) {
      insightScore = InsightScore(rawInsight.toDouble());
    } else if (rawInsight is String) {
      final n = double.tryParse(rawInsight);
      if (n != null) insightScore = InsightScore(n);
    }

    MoodPair? mood;
    final rawMood = m['mood'];
    if (rawMood is Map) {
      final mm = Map<String, dynamic>.from(rawMood);
      mood = MoodPair(
        mental: _asMood(mm['mental'] ?? mm['icon']),
        physical: _asMood(mm['physical'] ?? mm['body'] ?? mm['somatic']),
      );
    }

    final summaryRaw = m['summary'];
    final nextHintRaw = m['nextHint'] ?? m['next_hint'];
    final summary = _asString(summaryRaw).trim();
    final nextHint = _asString(nextHintRaw).trim();

    final sessionId =
        sid.isNotEmpty ? sid : 'local_${DateTime.now().millisecondsSinceEpoch}';

    return MemoryEntry(
      sessionId: sessionId,
      createdAt: createdAt,
      contextFacets: List<Facet>.unmodifiable(facets),
      insightScore: insightScore,
      mood: mood,
      summary: summary.isEmpty ? null : summary,
      nextHint: nextHint.isEmpty ? null : nextHint,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'session_id': sessionId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'context_facets': contextFacets.map((f) => f.toMap()).toList(),
        'insight_score': insightScore?.toMap(),
        'mood': mood?.toMap(),
        'summary': summary,
        'next_hint': nextHint,
      };

  String toJson() => jsonEncode(toMap());
  factory MemoryEntry.fromJson(String json) =>
      MemoryEntry.fromMap(jsonDecode(json) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MemoryEntry &&
        other.sessionId == sessionId &&
        other.createdAt == createdAt &&
        listEquals(other.contextFacets, contextFacets) &&
        other.insightScore == insightScore &&
        other.mood == mood &&
        other.summary == summary &&
        other.nextHint == nextHint;
  }

  @override
  int get hashCode => Object.hash(
        sessionId,
        createdAt,
        Object.hashAll(contextFacets),
        insightScore,
        mood,
        summary,
        nextHint,
      );

  @override
  String toString() =>
      'MemoryEntry(sessionId:$sessionId, createdAt:$createdAt, facets:${contextFacets.length})';
}

// ============================================================================
// MemoryFact / FactType — u. a. für „insight“-Fakten (Worker → memories_to_save)
// ============================================================================

enum FactType { identity, topic, facet, insight, name, mood, custom }

FactType _parseFactType(dynamic x, {FactType fallback = FactType.custom}) {
  final s = (x ?? '').toString().trim().toLowerCase();
  switch (s) {
    case 'identity':
      return FactType.identity;
    case 'topic':
      return FactType.topic;
    case 'facet':
      return FactType.facet;
    case 'insight':
      return FactType.insight;
    case 'name':
      return FactType.name;
    case 'mood':
      return FactType.mood;
    case 'custom':
      return FactType.custom;
    default:
      return fallback;
  }
}

String _factTypeToWire(FactType t) {
  switch (t) {
    case FactType.identity:
      return 'identity';
    case FactType.topic:
      return 'topic';
    case FactType.facet:
      return 'facet';
    case FactType.insight:
      return 'insight';
    case FactType.name:
      return 'name';
    case FactType.mood:
      return 'mood';
    case FactType.custom:
      return 'custom';
  }
}

@immutable
class MemoryFact {
  final String id;
  final FactType type;
  final String? sessionId;
  final String? topic;       // Thema/Kategorie
  final String? line;        // Kurzsatz/Hinweis (Badge/Hint)
  final double? score;       // Stärke/Confidence/Insight 0..1
  final String? activeFacet; // aktives Facettenlabel (Bridge/Pin)
  final String? topicPin;    // Topic-Pin/Schlüsselwort
  final String? canon;       // kanonische/vereinheitlichte Form
  final List<String>? tags;  // max ~5, kurze Marker
  final DateTime createdAt;

  const MemoryFact({
    required this.id,
    required this.type,
    required this.createdAt,
    this.sessionId,
    this.topic,
    this.line,
    this.score,
    this.activeFacet,
    this.topicPin,
    this.canon,
    this.tags,
  });

  MemoryFact copyWith({
    String? id,
    FactType? type,
    String? sessionId,
    String? topic,
    String? line,
    double? score,
    String? activeFacet,
    String? topicPin,
    String? canon,
    List<String>? tags,
    DateTime? createdAt,
  }) {
    return MemoryFact(
      id: id ?? this.id,
      type: type ?? this.type,
      sessionId: sessionId ?? this.sessionId,
      topic: topic ?? this.topic,
      line: line ?? this.line,
      score: score ?? this.score,
      activeFacet: activeFacet ?? this.activeFacet,
      topicPin: topicPin ?? this.topicPin,
      canon: canon ?? this.canon,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static DateTime _dt(dynamic x) {
    final s = (x ?? '').toString().trim();
    final dt = DateTime.tryParse(s);
    return (dt ?? DateTime.now()).toUtc();
  }

  static double? _asDouble(dynamic x) {
    if (x == null) return null;
    if (x is num) return x.toDouble();
    final d = double.tryParse(x.toString().replaceAll(',', '.'));
    return d;
  }

  static List<String>? _asTags(dynamic v) {
    if (v == null) return null;
    final out = <String>[];
    if (v is List) {
      for (final it in v) {
        final s = (it ?? '').toString().trim();
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
        if (out.length >= 5) break;
      }
    } else if (v is String) {
      final s = v.trim();
      if (s.isNotEmpty) {
        final parts = s.split(RegExp(r'\s*,\s*'));
        for (final p in parts) {
          final t = p.trim();
          if (t.isNotEmpty && !out.contains(t)) out.add(t);
          if (out.length >= 5) break;
        }
      }
    }
    return out.isEmpty ? null : out;
  }

  factory MemoryFact.fromMap(Map<String, dynamic> m) {
    final type = _parseFactType(m['type']);
    final id = (m['id'] ?? m['key'] ?? '').toString().trim();
    final sid = (m['session_id'] ?? m['sessionId'] ?? '').toString().trim();

    final topic =
        (m['topic'] ?? m['label'] ?? m['category'] ?? '').toString().trim();
    final line = (m['line'] ??
            m['text'] ??
            m['hint'] ??
            m['summary'] ??
            m['title'] ??
            '')
        .toString()
        .trim();

    final score =
        _asDouble(m['score'] ?? m['insight_score'] ?? m['confidence']);
    final af = (m['active_facet'] ?? m['activeFacet'] ?? m['facet'] ?? '')
        .toString()
        .trim();
    final pin =
        (m['topic_pin'] ?? m['topicPin'] ?? m['pin'] ?? '').toString().trim();
    final canon = (m['canon'] ?? '').toString().trim();
    final tags = _asTags(m['tags']);

    final ts = _dt(m['created_at'] ?? m['ts']);

    return MemoryFact(
      id: id.isEmpty ? 'f_${ts.millisecondsSinceEpoch}' : id,
      type: type,
      sessionId: sid.isEmpty ? null : sid,
      topic: topic.isEmpty ? null : topic,
      line: line.isEmpty ? null : line,
      score: score,
      activeFacet: af.isEmpty ? null : af,
      topicPin: pin.isEmpty ? null : pin,
      canon: canon.isEmpty ? null : canon,
      tags: tags,
      createdAt: ts,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'type': _factTypeToWire(type),
        if (sessionId != null && sessionId!.isNotEmpty) 'session_id': sessionId,
        if (topic != null && topic!.isNotEmpty) 'topic': topic,
        if (line != null && line!.isNotEmpty) 'line': line,
        if (score != null) 'score': score,
        if (activeFacet != null && activeFacet!.isNotEmpty)
          'active_facet': activeFacet,
        if (topicPin != null && topicPin!.isNotEmpty) 'topic_pin': topicPin,
        if (canon != null && canon!.isNotEmpty) 'canon': canon,
        if (tags != null && tags!.isNotEmpty) 'tags': List<String>.from(tags!),
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  String toJson() => jsonEncode(toMap());
  factory MemoryFact.fromJson(String json) =>
      MemoryFact.fromMap(jsonDecode(json) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MemoryFact &&
        other.id == id &&
        other.type == type &&
        other.sessionId == sessionId &&
        other.topic == topic &&
        other.line == line &&
        other.score == score &&
        other.activeFacet == activeFacet &&
        other.topicPin == topicPin &&
        listEquals(other.tags, tags) &&
        other.canon == canon &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        sessionId,
        topic,
        line,
        score,
        activeFacet,
        topicPin,
        canon,
        Object.hashAll(tags ?? const <String>[]),
        createdAt,
      );

  @override
  String toString() =>
      'MemoryFact(${_factTypeToWire(type)} id:$id topic:$topic facet:$activeFacet pin:$topicPin canon:$canon tags:${tags?.length ?? 0})';
}
