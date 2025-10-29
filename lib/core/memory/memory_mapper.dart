// [BASELINE] lib/core/memory/memory_mapper.dart — v6.3.1 (Stand: 29.10.2025)
//
// MemoryMapper — toleranter Worker→MemoryEntry-Merger
// ----------------------------------------------------
// Ziele
// • Robust gegenüber variierenden Worker-Schemata (Map/DTO/JSON-String)
// • Deduplizierte Facets (case-insensitive by key) — Hits werden zusammengeführt
// • Liefert null, wenn *kein* relevantes Signal vorhanden ist
//
// Erfasste Signalquellen (inkl. neuer Hint-Pfade):
//   facets:
//     • facets | context_facets
//     • understanding.facets | analysis.context_facets | analysis.facets
//     • context.memories.facets | context.memories.context_facets
//     • context.memories.hint.facets | context.memories.hint.recent_facets
//   topics → Facet-Fallback:
//     • topics | topic_suggestions | analysis.topic_suggestions
//     • understanding.topics
//     • context.memories.recent_topics | context_hint.last_themes
//     • context_hint.recent_facets (als Keys; Label = Key)
//     • context.memories.hint.topics
//   insight_score:
//     • insight_score | understanding.insight_score | analysis.insight_score | flow.insight_score
//     • insight.score  (camel/legacy)
//     • insight_baseline | insight.baseline (optional)
//   mood:
//     • mood | closure.mood | context.mood
//   summary:
//     • summary | understanding.summary | analysis.summary
//     • closure.hope_reply | closure.text
//   next_hint:
//     • next_hint | flow.next_hint | closure.closure_prompt | context.next_hint
//
// Hinweise
// • Wir tolerieren Map-, DTO- und JSON-String-Eingaben.
// • Facet-Dedupe führt hits zusammen und bevorzugt das längere (informativere)
//   Label, falls mehrere Labels zu demselben Key auftauchen.

import 'dart:convert' show jsonDecode;

import '../models/insight_models.dart';
import 'memory_entry.dart';

class MemoryMapper {
  MemoryMapper._();

  // ───────────────────────────────────────────────────────────────────────────
  // Low-level helpers
  // ───────────────────────────────────────────────────────────────────────────

  /// Versucht, ein beliebiges Objekt in eine Map zu verwandeln.
  /// Unterstützt: Map, DTO via toJson(), JSON-String (nur wenn er wie ein Objekt aussieht).
  static Map<String, dynamic>? _asMap(dynamic x) {
    if (x == null) return null;
    if (x is Map) return Map<String, dynamic>.from(x);
    // DTO → toJson()
    try {
      final j = (x as dynamic).toJson?.call();
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    // JSON-String → Map
    if (x is String) {
      final s = x.trim();
      if (s.isNotEmpty && s.startsWith('{') && s.endsWith('}')) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Interner Pfad-Leser. Toleriert Map/DTO/JSON-String auf jedem Level.
  static dynamic _walk(dynamic cur, List<String> path) {
    var v = cur;
    for (final k in path) {
      if (v == null) return null;

      // Direkt als Map?
      if (v is Map) {
        v = v[k];
        continue;
      }

      // DTO → toJson()
      final as = _asMap(v);
      if (as != null) {
        v = as[k];
        continue;
      }

      // Fallback
      return null;
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
        final s = v.trim();
        if (s.isEmpty) continue;
        final n = num.tryParse(s);
        if (n != null) return n;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _mapAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      final m = _asMap(v);
      if (m != null) return m;
    }
    return null;
  }

  static List<String> _stringListAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      if (v == null) continue;

      if (v is List) {
        return v
            .where((e) => e != null)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }

      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) continue;
        final parts = s
            .split(RegExp(r'\r?\n+|[•\-–—]\s+|;\s+|,\s+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return parts.isEmpty ? <String>[s] : parts;
      }
    }
    return const <String>[];
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Facet helpers
  // ───────────────────────────────────────────────────────────────────────────

  static List<Facet> _facetsAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      if (v is List && v.isNotEmpty) {
        final out = <Facet>[];
        for (final e in v) {
          try {
            out.add(Facet.fromWorker(e)); // tolerant: Map | String | DTO
          } catch (_) {
            // einzelnes defektes Element ignorieren
          }
        }
        if (out.isNotEmpty) return _dedupeFacets(out);
      }
    }
    return const <Facet>[];
  }

  static List<Facet> _facetsFromLabels(List<String> labels) {
    if (labels.isEmpty) return const <Facet>[];
    final raw = <Facet>[];
    for (final l in labels) {
      final label = l.trim();
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      raw.add(Facet(key: key, label: label, hits: 1));
    }
    return _dedupeFacets(raw);
  }

  /// Dedupliziert Facets by key (case-insensitive), summiert hits und
  /// wählt das „informativere“ Label.
  static List<Facet> _dedupeFacets(List<Facet> list) {
    if (list.isEmpty) return const <Facet>[];
    final byKey = <String, Facet>{};
    for (final f in list) {
      final k = (f.key.isEmpty ? f.label : f.key).toLowerCase();
      final prev = byKey[k];
      if (prev == null) {
        byKey[k] = f;
      } else {
        final sumHits =
            (prev.hits <= 0 ? 1 : prev.hits) + (f.hits <= 0 ? 1 : f.hits);
        final betterLabel = (f.label.trim().length > prev.label.trim().length)
            ? f.label
            : prev.label;
        byKey[k] = Facet(key: k, label: betterLabel, hits: sumHits);
      }
    }
    return byKey.values.toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Public API
  // ───────────────────────────────────────────────────────────────────────────

  /// Baut einen MemoryEntry aus einer Worker-Response.
  /// Gibt null zurück, wenn kein relevantes Signal vorhanden ist.
  static MemoryEntry? fromWorker(dynamic raw) {
    if (raw == null) return null;

    // Session-ID (viele mögliche Aliasse)
    final sessionId = _stringAt(raw, const [
      ['session', 'id'],
      ['session', 'thread_id'],
      ['session', 'threadId'],
      ['thread_id'],
      ['threadId'],
      ['round', 'id'],
      ['roundId'],
      ['sessionId'],
      ['id'],
    ]);

    // Facets (mehrere mögliche Pfade)
    var facets = _facetsAt(raw, const [
      ['understanding', 'facets'],
      ['facets'],
      ['context', 'facets'],
      ['context_facets'],
      ['analysis', 'context_facets'],
      ['analysis', 'facets'],
      ['context', 'memories', 'facets'],
      ['context', 'memories', 'context_facets'],
      ['context', 'memories', 'hint', 'facets'],
      ['context', 'memories', 'hint', 'recent_facets'],
    ]);

    // Optionaler Fallback: Themenlisten (Labels) in Facets konvertieren
    if (facets.isEmpty) {
      final topicLabels = _stringListAt(raw, const [
        ['topics'],
        ['topic_suggestions'],
        ['topicSuggestions'],
        ['analysis', 'topic_suggestions'],
        ['understanding', 'topics'],
        ['context', 'memories', 'recent_topics'],
        ['context_hint', 'last_themes'],
        ['context', 'memories', 'hint', 'topics'],
      ]);

      // Falls nur „recent_facets“ (Keys) vorhanden sind, als Labels/Keys übernehmen
      final facetKeys = _stringListAt(raw, const [
        ['context_hint', 'recent_facets'],
      ]);

      final asLabels = <String>[
        ...topicLabels,
        ...facetKeys, // Label=Key
      ];

      facets = _facetsFromLabels(asLabels);
    }

    // Insight-Score (+Baseline optional)
    final insightVal = _numAt(raw, const [
      ['insight_score'],
      ['understanding', 'insight_score'],
      ['analysis', 'insight_score'],
      ['flow', 'insight_score'],
      ['insight', 'score'],
    ]);
    final baseline = _numAt(raw, const [
      ['insight_baseline'],
      ['insight', 'baseline'],
    ]);
    final insight = (insightVal != null)
        ? InsightScore(insightVal.toDouble(), baseline: baseline?.toDouble())
        : null;

    // Mood
    final moodMap = _mapAt(raw, const [
      ['mood'],
      ['closure', 'mood'],
      ['context', 'mood'],
    ]);
    final mood = (moodMap != null) ? MoodPair.fromWorker(moodMap) : null;

    // Summary
    final summary = _stringAt(raw, const [
      ['summary'],
      ['understanding', 'summary'],
      ['analysis', 'summary'],
      ['closure', 'hope_reply'],
      ['closure', 'text'],
    ]);

    // Next hint
    final nextHint = _stringAt(raw, const [
      ['next_hint'],
      ['flow', 'next_hint'],
      ['closure', 'closure_prompt'],
      ['context', 'next_hint'],
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
