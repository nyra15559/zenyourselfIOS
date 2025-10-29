// [BASELINE] lib/core/memory/memory_entry.dart — v6.3.1 (Stand: 29.10.2025)
//
// MemoryEntry — DTO für lokales Kontext-Gedächtnis (snake_case-Maps, defensiv)
// -----------------------------------------------------------------------------
// Kompatibilität (v1 → v2):
// • sessionId                ⇆  id / session_id
// • createdAt (ISO-UTC)      ⇆  created_at / ts
// • contextFacets[List<Facet>] ⇆  context_facets / facets[List<String>]
// • insightScore[Map|num]    ⇆  insight_score
// • mood{mental,physical}    ⇆  Strings/Nums; Aliasse: icon/body/somatic
// • summary / nextHint       ⇆  summary / next_hint
//
// Hinweise:
// • toMap() gibt NUR snake_case-Schlüssel zurück (v2 Standard).
// • fromMap() akzeptiert v1/v2/“schmale” Maps (line/ack) und normalisiert defensiv.
// • toJson()/fromJson() sind Convenience-Wrapper für (De-)Serialisierung.

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

  // ---------- Copy ------------------------------------------------------------

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
    // Unterstützt ISO-Strings und Fallback auf now()
    final s = _asString(x).trim();
    final dt = DateTime.tryParse(s);
    return (dt ?? DateTime.now()).toUtc();
  }

  // ---------- (De-)Serialisierung --------------------------------------------

  factory MemoryEntry.fromMap(Map<String, dynamic> m) {
    // sessionId (Aliases)
    final sidRaw = m['sessionId'] ?? m['session_id'] ?? m['id'];
    final sid = _asString(sidRaw).trim();

    // createdAt (Aliases: created_at / ts)
    final createdRaw = m['createdAt'] ?? m['created_at'] ?? m['ts'];
    final createdAt = _asDateTimeUtc(createdRaw);

    // contextFacets: bevorzugt List<Map>, Fallback List<String>
    final facets = <Facet>[];
    final cfRaw = m['contextFacets'] ?? m['context_facets'] ?? m['facets'];
    if (cfRaw is List) {
      for (final e in cfRaw) {
        if (e is Map) {
          try {
            facets.add(Facet.fromMap(Map<String, dynamic>.from(e)));
          } catch (_) {
            // defektes Einzelelement ignorieren
          }
        } else {
          final s = _asString(e).trim();
          if (s.isNotEmpty) {
            facets.add(Facet(key: s, label: s));
          }
        }
      }
    }

    // insightScore: Map (v2) oder num/String (v1)
    InsightScore? insightScore;
    final rawInsight = m['insightScore'] ?? m['insight_score'];
    if (rawInsight is Map) {
      try {
        insightScore =
            InsightScore.fromMap(Map<String, dynamic>.from(rawInsight));
      } catch (_) {/* ignore */}
    } else if (rawInsight is num) {
      insightScore = InsightScore(rawInsight.toDouble());
    } else if (rawInsight is String) {
      final n = double.tryParse(rawInsight);
      if (n != null) insightScore = InsightScore(n);
    }

    // mood: akzeptiere Map mit int/num/String und Aliasse
    MoodPair? mood;
    final rawMood = m['mood'];
    if (rawMood is Map) {
      final mm = Map<String, dynamic>.from(rawMood);
      mood = MoodPair(
        mental: _asMood(mm['mental'] ?? mm['icon']),
        physical: _asMood(mm['physical'] ?? mm['body'] ?? mm['somatic']),
      );
    }

    // summary / nextHint (Aliasse)
    final summaryRaw = m['summary'];
    final nextHintRaw = m['nextHint'] ?? m['next_hint'];

    final summary = _asString(summaryRaw).trim();
    final nextHint = _asString(nextHintRaw).trim();

    // Session-Fallback
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
        // v2: ausschließlich snake_case Keys zurückgeben
        'session_id': sessionId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'context_facets': contextFacets.map((f) => f.toMap()).toList(),
        'insight_score': insightScore?.toMap(),
        'mood': mood?.toMap(),
        'summary': summary,
        'next_hint': nextHint,
      };

  /// JSON-Convenience
  String toJson() => jsonEncode(toMap());
  factory MemoryEntry.fromJson(String json) =>
      MemoryEntry.fromMap(jsonDecode(json) as Map<String, dynamic>);

  // ---------- Equality / Hash / Debug ----------------------------------------

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
