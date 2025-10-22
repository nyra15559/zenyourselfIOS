// lib/core/memory/memory_entry.dart
//
// MemoryEntry (v2) — DTO für lokales Kontext-Gedächtnis.
// Felder:
// - sessionId: Thread/Session-ID (Fallback: früheres 'id')
// - createdAt: Zeitstempel
// - contextFacets: Liste semantischer Facetten (Facet)
// - insightScore: optional (0..1 oder frei), inkl. baseline möglich
// - mood: optional (0..4 mental/physical)
// - summary / nextHint: kurze Texte
//
// Abwärtskompatibilität:
// - liest alte Strukturen (id, facets:[String], insightScore:num, mood:{mental,physical} als String/num)

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
      contextFacets: contextFacets ?? List<Facet>.from(this.contextFacets),
      insightScore: insightScore ?? this.insightScore,
      mood: mood ?? this.mood,
      summary: summary ?? this.summary,
      nextHint: nextHint ?? this.nextHint,
    );
  }

  // ---------- (De-)Serialisierung -------------------------------------------

  factory MemoryEntry.fromMap(Map<String, dynamic> m) {
    // sessionId: akzeptiere altes 'id'
    final sid = (m['sessionId'] ?? m['id'] ?? '').toString();

    // createdAt
    final createdAt = DateTime.tryParse((m['createdAt'] ?? '').toString()) ??
        DateTime.now().toUtc();

    // contextFacets: akzeptiere neues 'contextFacets' (List<Map>) oder altes 'facets' (List<String>)
    final facets = <Facet>[];
    if (m['contextFacets'] is List) {
      for (final e in (m['contextFacets'] as List)) {
        if (e is Map) {
          facets.add(Facet.fromMap(Map<String, dynamic>.from(e)));
        } else {
          final s = e?.toString() ?? '';
          if (s.trim().isNotEmpty) {
            facets.add(Facet(key: s, label: s));
          }
        }
      }
    } else if (m['facets'] is List) {
      for (final e in (m['facets'] as List)) {
        final s = e?.toString() ?? '';
        if (s.trim().isNotEmpty) {
          facets.add(Facet(key: s, label: s));
        }
      }
    }

    // insightScore: akzeptiere Map (v2) oder num (v1)
    InsightScore? insightScore;
    final rawInsight = m['insightScore'];
    if (rawInsight is Map) {
      insightScore =
          InsightScore.fromMap(Map<String, dynamic>.from(rawInsight));
    } else if (rawInsight is num) {
      insightScore = InsightScore(rawInsight.toDouble());
    }

    // mood: akzeptiere Map mit int/num/String
    MoodPair? mood;
    if (m['mood'] is Map) {
      final mm = Map<String, dynamic>.from(m['mood'] as Map);
      int coerce(dynamic x) {
        if (x is num) return x.clamp(0, 4).toInt();
        final s = x?.toString() ?? '';
        final n = int.tryParse(s);
        return (n == null) ? 2 : n.clamp(0, 4);
      }
      mood = MoodPair(
        mental: coerce(mm['mental'] ?? mm['icon']),
        physical: coerce(mm['physical'] ?? mm['body'] ?? mm['somatic']),
      );
    }

    final summary =
        (m['summary']?.toString().trim().isEmpty ?? true) ? null : m['summary'].toString();
    final nextHint =
        (m['nextHint']?.toString().trim().isEmpty ?? true) ? null : m['nextHint'].toString();

    return MemoryEntry(
      sessionId: sid.isNotEmpty ? sid : 'local_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: createdAt.toUtc(),
      contextFacets: facets,
      insightScore: insightScore,
      mood: mood,
      summary: summary,
      nextHint: nextHint,
    );
  }

  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'contextFacets': contextFacets.map((f) => f.toMap()).toList(),
        'insightScore': insightScore?.toMap(),
        'mood': mood?.toMap(),
        'summary': summary,
        'nextHint': nextHint,
      };

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is MemoryEntry &&
          o.sessionId == sessionId &&
          o.createdAt == createdAt &&
          listEquals(o.contextFacets, contextFacets) &&
          o.insightScore == insightScore &&
          o.mood == mood &&
          o.summary == summary &&
          o.nextHint == nextHint);

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
}
