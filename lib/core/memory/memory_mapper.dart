// lib/core/memory/memory_mapper.dart
//
// MemoryMapper — tolerant Worker→MemoryEntry
// -----------------------------------------
// • Robust gegenüber variierenden Worker-Schemata
// • Deduped Facets (case-insensitive by key)
// • Liefert null, wenn kein relevantes Signal vorhanden ist
//
// Signalquellen: facets | insight_score | mood | summary | next_hint

import '../models/insight_models.dart';
import 'memory_entry.dart';

class MemoryMapper {
  static List _list(dynamic x) => (x is List) ? x : const [];
  static Map<String, dynamic> _map(dynamic x) =>
      (x is Map) ? Map<String, dynamic>.from(x) : <String, dynamic>{};

  static dynamic _walk(dynamic cur, List<String> path) {
    var v = cur;
    for (final k in path) {
      if (v is Map) {
        v = (v)[k];
      } else {
        try {
          final j = (v as dynamic).toJson?.call();
          v = (j is Map) ? j[k] : null;
        } catch (_) {
          v = null;
        }
      }
      if (v == null) break;
    }
    return v;
  }

  static String _stringAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is num) return v.toString();
    }
    return '';
  }

  static num? _numAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      if (v is num) return v;
      if (v is String) {
        final n = num.tryParse(v.trim());
        if (n != null) return n;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _mapAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      if (v is Map) return Map<String, dynamic>.from(v);
    }
    return null;
  }

  static List<Facet> _facetsAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      if (v is List) {
        final out = <Facet>[];
        for (final e in v) {
          out.add(Facet.fromWorker(e));
        }
        // dedupe (case-insensitive by key)
        final seen = <String>{};
        final deduped = <Facet>[];
        for (final f in out) {
          if (seen.add(f.key.toLowerCase())) deduped.add(f);
        }
        return deduped;
      }
    }
    return const <Facet>[];
  }

  /// Baut einen MemoryEntry aus einer Worker-Response.
  /// Gibt null zurück, wenn kein relevantes Signal vorhanden ist.
  static MemoryEntry? fromWorker(dynamic raw) {
    if (raw == null) return null;

    final sessionId = _stringAt(raw, const [
      ['session', 'id'],
      ['session', 'thread_id'],
      ['thread_id'],
      ['sessionId'],
      ['id'],
    ]);

    final facets = _facetsAt(raw, const [
      ['understanding', 'facets'],
      ['facets'],
      ['context', 'facets'],
    ]);

    final insightVal = _numAt(raw, const [
      ['insight_score'],
      ['understanding', 'insight_score'],
      ['insight', 'score'],
    ]);
    final baseline = _numAt(raw, const [
      ['insight_baseline'],
      ['insight', 'baseline'],
    ]);
    final insight = (insightVal != null)
        ? InsightScore(insightVal.toDouble(), baseline: baseline?.toDouble())
        : null;

    final moodMap = _mapAt(raw, const [
      ['mood'],
      ['closure', 'mood'],
    ]);
    final mood = (moodMap != null) ? MoodPair.fromWorker(moodMap) : null;

    final summary = _stringAt(raw, const [
      ['summary'],
      ['understanding', 'summary'],
      ['closure', 'hope_reply'],
      ['closure', 'text'],
    ]);
    final nextHint = _stringAt(raw, const [
      ['next_hint'],
      ['closure', 'closure_prompt'],
      ['flow', 'next_hint'],
    ]);

    final hasSignal = facets.isNotEmpty ||
        insight != null ||
        mood != null ||
        summary.isNotEmpty ||
        nextHint.isNotEmpty;
    if (!hasSignal) return null;

    return MemoryEntry(
      sessionId: sessionId.isNotEmpty
          ? sessionId
          : 'local_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now().toUtc(),
      contextFacets: facets,
      insightScore: insight,
      mood: mood,
      summary: summary.isNotEmpty ? summary : null,
      nextHint: nextHint.isNotEmpty ? nextHint : null,
    );
  }
}
