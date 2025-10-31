// [BASELINE] lib/core/memory/memory_mapper.dart — v6.4.2 (31.10.2025)
//
// MemoryMapper — toleranter Worker→MemoryEntry-Merger + Facts-Extractor
// --------------------------------------------------------------------
// Neu (v6.4.2):
// • factsFromWorker(turn): extrahiert/normalisiert memories_to_save[*] → List<MemoryFact> (default type=insight).
// • buildContextHint(..., activeFacet, topicPin): kurzer Bridge-Satz (priorisiert Pins).
//
// Bestehende fromWorker(...) bleibt unverändert nutzbar (rückwärtskompatibel).

import 'dart:convert' show jsonDecode;

import '../models/insight_models.dart';
import 'memory_entry.dart';

class MemoryMapper {
  MemoryMapper._();

  // ───────────────────────────────────────────────────────────────────────────
  // Low-level helpers
  // ───────────────────────────────────────────────────────────────────────────

  static Map<String, dynamic>? _asMap(dynamic x) {
    if (x == null) return null;
    if (x is Map) return Map<String, dynamic>.from(x);
    try {
      final j = (x as dynamic).toJson?.call();
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
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

  static dynamic _walk(dynamic cur, List<String> path) {
    var v = cur;
    for (final k in path) {
      if (v == null) return null;
      if (v is Map) {
        v = v[k];
        continue;
      }
      final as = _asMap(v);
      if (as != null) {
        v = as[k];
        continue;
      }
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
            .split(RegExp(r'\r?\n+|[•\-–—]\s+|\s*;\s*|\s*,\s+'))
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
          } catch (_) {/* ignore */}
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
        final betterLabel =
            (f.label.trim().length > prev.label.trim().length) ? f.label : prev.label;
        byKey[k] = Facet(key: k, label: betterLabel, hits: sumHits);
      }
    }
    return byKey.values.toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Public API — MemoryEntry
  // ───────────────────────────────────────────────────────────────────────────

  static MemoryEntry? fromWorker(dynamic raw) {
    if (raw == null) return null;

    final sessionId = _stringAt(raw, const [
      ['session', 'id'],
      ['session', 'thread_id'],
      ['session', 'threadId'],
      ['thread_id'],
      ['threadId'],
      ['round', 'id'],
      ['roundId'],
      ['turn', 'session', 'id'],
      ['data', 'session', 'id'],
      ['response', 'session', 'id'],
      ['meta', 'session_id'],
      ['meta', 'thread_id'],
      ['sessionId'],
      ['id'],
    ]);

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
      ['context', 'hint', 'facets'],
      ['context', 'hint', 'recent_facets'],
      ['context_hint', 'facets'],
      ['context_hint', 'hint', 'facets'],
      ['ui', 'facets'],
    ]);

    if (facets.isEmpty) {
      final topicLabels = _stringListAt(raw, const [
        ['topics'],
        ['topic_suggestions'],
        ['topicSuggestions'],
        ['analysis', 'topic_suggestions'],
        ['analysis', 'recent_topics'],
        ['understanding', 'topics'],
        ['flow', 'topics'],
        ['ui', 'topics'],
        ['context', 'memories', 'recent_topics'],
        ['context', 'memories', 'hint', 'topics'],
        ['context', 'memories', 'hint', 'recent_topics'],
        ['context', 'hint', 'topics'],
        ['context_hint', 'topics'],
        ['context_hint', 'last_themes'],
      ]);

      final facetKeys = _stringListAt(raw, const [
        ['context_hint', 'recent_facets'],
      ]);

      final asLabels = <String>[
        ...topicLabels,
        ...facetKeys,
      ];

      facets = _facetsFromLabels(asLabels);
    }

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

    final moodMap = _mapAt(raw, const [
      ['mood'],
      ['closure', 'mood'],
      ['context', 'mood'],
      ['flow', 'mood'],
    ]);
    final mood = (moodMap != null) ? MoodPair.fromWorker(moodMap) : null;

    final summary = _stringAt(raw, const [
      ['summary'],
      ['understanding', 'summary'],
      ['analysis', 'summary'],
      ['closure', 'hope_reply'],
      ['closure', 'text'],
      ['flow', 'hope'],
      ['hope'],
      ['ui', 'hope'],
    ]);

    final nextHint = _stringAt(raw, const [
      ['next_hint'],
      ['flow', 'next_hint'],
      ['closure', 'closure_prompt'],
      ['context', 'next_hint'],
      ['analysis', 'next_hint'],
      ['ui', 'next_hint'],
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

  // ───────────────────────────────────────────────────────────────────────────
  // Public API — Facts & Bridge
  // ───────────────────────────────────────────────────────────────────────────

  static List<MemoryFact> factsFromWorker(dynamic turn) {
    final candidates = <List<String>>[
      ['memories_to_save'],
      ['primary', 'memories_to_save'],
      ['flow', 'memories_to_save'],
      ['reflection', 'memories_to_save'],
      ['closure', 'memories_to_save'],
    ];

    final out = <MemoryFact>[];
    for (final p in candidates) {
      final v = _walk(turn, p);
      if (v is List) {
        for (final e in v) {
          try {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              m['type'] = m['type'] ?? 'insight';
              out.add(MemoryFact.fromMap(m));
            } else if (e is String) {
              out.add(MemoryFact.fromMap({
                'type': 'insight',
                'line': e,
              }));
            }
          } catch (_) {/* ignore */}
        }
      }
    }

    // simple Dedupe nach (topic,line)
    final seen = <String>{};
    final deduped = <MemoryFact>[];
    for (final f in out) {
      final k =
          '${(f.topic ?? '').toLowerCase()}::${(f.line ?? '').toLowerCase()}';
      if (k.trim().isEmpty) {
        deduped.add(f);
        continue;
      }
      if (seen.add(k)) deduped.add(f);
    }
    return deduped;
  }

  /// Kurzer Bridge-Satz für UI/Worker-Kontext.
  static String? buildContextHint({
    List<MemoryFact> facts = const [],
    String? activeFacet,
    String? topicPin,
    int maxLen = 180,
  }) {
    final tokens = <String>[];

    void push(String? s) {
      final t = (s ?? '').trim();
      if (t.isEmpty) return;
      if (!tokens.any((x) => x.toLowerCase() == t.toLowerCase())) {
        tokens.add(t);
      }
    }

    push(activeFacet);
    push(topicPin);

    for (final f in facts) {
      if (tokens.length >= 2) break;
      push(f.topic);
      if (tokens.length >= 2) break;
      push(f.line);
    }

    if (tokens.isEmpty) return null;

    final t1 = tokens[0];
    final t2 = tokens.length >= 2 ? tokens[1] : null;
    final body = t2 == null
        ? 'Ich erinnere mich an **$t1**.'
        : 'Ich erinnere mich an **$t1** und **$t2**.';
    final res =
        '$body Falls das heute noch mitschwingt – magst du dort anknüpfen?';
    return _cap(res, maxLen);
  }

  static String _cap(String s, int maxLen) {
    final t = s.trim();
    if (t.length <= maxLen) return t;
    return '${t.substring(0, maxLen).trimRight()}…';
  }
}
