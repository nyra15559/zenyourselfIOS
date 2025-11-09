// [PATCHED] lib/core/memory/memory_mapper.dart — v6.4.6 (09.11.2025)
// MERGE SIGNAL: Fix für InsightFact (keine Getter 'type'/'line') via Kompatibilitäts-Adapter,
// Namenskonflikt behoben (Alias-Import), robuste Sanitizer/Walker, dedupe & Hint sicher.
//
// MemoryMapper — toleranter Worker→MemoryEntry-Merger + Facts-Extractor
// --------------------------------------------------------------------------------

import 'dart:convert' show jsonDecode;

import '../models/insight_models.dart' as im; // Facet, InsightScore, MoodPair, InsightFact/MemoryFact
import 'memory_entry.dart' show MemoryEntry;  // nur MemoryEntry, um Konflikte zu vermeiden

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

  static String _sanitizeText(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Entferne umschließende Anführungszeichen (", ', „ “ ‚ ‘) wenn symmetrisch
    if (t.length >= 2) {
      final start = t.codeUnitAt(0);
      final end = t.codeUnitAt(t.length - 1);
      bool isQuotedPair(int a, int b) {
        const pairs = [
          [0x22, 0x22], // "
          [0x27, 0x27], // '
          [0x201E, 0x201C], // „ “
          [0x201A, 0x2019], // ‚ ‘
          [0x201C, 0x201D], // “ ”
        ];
        for (final p in pairs) {
          if (a == p[0] && b == p[1]) return true;
        }
        return false;
      }
      if (isQuotedPair(start, end)) {
        t = t.substring(1, t.length - 1).trim();
      }
    }
    return t;
  }

  static String _stringAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      if (v is String && v.trim().isNotEmpty) return _sanitizeText(v);
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
            .map((e) => _sanitizeText(e.toString()))
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }

      if (v is String) {
        final s = _sanitizeText(v);
        if (s.isEmpty) continue;
        final parts = s
            .split(RegExp(r'\r?\n+|[•\-–—]\s+|\s*;\s*|\s*,\s+'))
            .map((e) => _sanitizeText(e))
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

  static List<im.Facet> _facetsAt(dynamic raw, List<List<String>> paths) {
    for (final p in paths) {
      final v = _walk(raw, p);
      if (v is List && v.isNotEmpty) {
        final out = <im.Facet>[];
        for (final e in v) {
          try {
            out.add(im.Facet.fromWorker(e)); // tolerant: Map | String | DTO
          } catch (_) {/* ignore */}
        }
        if (out.isNotEmpty) return _dedupeFacets(out);
      }
    }
    return const <im.Facet>[];
  }

  static List<im.Facet> _facetsFromLabels(List<String> labels) {
    if (labels.isEmpty) return const <im.Facet>[];
    final raw = <im.Facet>[];
    for (final l in labels) {
      final label0 = _sanitizeText(l);
      if (label0.isEmpty) continue;

      // optional „key:label“-Syntax
      String key = label0.toLowerCase();
      String label = label0;
      final colon = label0.indexOf(':');
      if (colon > 0 && colon < label0.length - 1) {
        key = _sanitizeText(label0.substring(0, colon)).toLowerCase();
        label = _sanitizeText(label0.substring(colon + 1));
        if (label.isEmpty) label = label0;
      }

      raw.add(im.Facet(key: key, label: label, hits: 1));
    }
    return _dedupeFacets(raw);
  }

  static List<im.Facet> _dedupeFacets(List<im.Facet> list) {
    if (list.isEmpty) return const <im.Facet>[];
    final byKey = <String, im.Facet>{};
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
        byKey[k] = im.Facet(key: k, label: betterLabel, hits: sumHits);
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
      ['meta', 'threadId'],
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
        ? im.InsightScore(insightVal.toDouble(), baseline: baseline?.toDouble())
        : null;

    final moodMap = _mapAt(raw, const [
      ['mood'],
      ['closure', 'mood'],
      ['context', 'mood'],
      ['flow', 'mood'],
    ]);
    final mood = (moodMap != null) ? im.MoodPair.fromWorker(moodMap) : null;

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
  // Kompatibilitäts-Adapter für InsightFact/MemoryFact
  // (decken alte und neue Feldnamen ab, ohne Modelldatei zu ändern)
  // ───────────────────────────────────────────────────────────────────────────

  static String _factType(im.MemoryFact f, {String or = 'insight'}) {
    final d = f as dynamic;
    try {
      final v = d.type;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = d.kind;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = d.factType;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return or;
  }

  static String _factTopic(im.MemoryFact f, {String or = ''}) {
    final d = f as dynamic;
    try {
      final v = d.topic;
      if (v is String) return v.trim();
    } catch (_) {}
    try {
      final v = d.subject;
      if (v is String) return v.trim();
    } catch (_) {}
    return or;
  }

  static String _factLine(im.MemoryFact f, {String or = ''}) {
    final d = f as dynamic;
    try {
      final v = d.line;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = d.text;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = d.value;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return or;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Public API — Facts & Bridge
  // ───────────────────────────────────────────────────────────────────────────

  static List<im.MemoryFact> factsFromWorker(dynamic turn) {
    // Akzeptiere mehrere Pfade; frühere/alternative Einbettungen eingeschlossen.
    final candidates = <List<String>>[
      ['memories_to_save'],
      ['primary', 'memories_to_save'],
      ['flow', 'memories_to_save'],
      ['reflection', 'memories_to_save'],
      ['closure', 'memories_to_save'],
      ['context', 'memories_to_save'],
      ['analysis', 'memories_to_save'],
      ['ui', 'memories_to_save'],
      ['data', 'memories_to_save'],
      ['response', 'memories_to_save'],
    ];

    final out = <im.MemoryFact>[];
    for (final p in candidates) {
      final v = _walk(turn, p);
      if (v is List) {
        for (final e in v) {
          try {
            // Fälle:
            // 1) Map direkt: {type?, topic?, line?/text?, ...}
            // 2) Wrapper: {fact:{...}, type?}  → merge
            // 3) String: "kurzer Aha-Satz"
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              final inner = _asMap(m['fact']);
              if (inner != null) {
                final merged = <String, dynamic>{...inner, ...m};
                merged.remove('fact');
                merged['type'] = merged['type'] ?? m['type'] ?? 'insight';
                if (merged['topic'] is String) {
                  merged['topic'] = _sanitizeText(merged['topic']);
                }
                // toleranter Feldname für Text:
                if (merged['line'] is String) {
                  merged['line'] = _sanitizeText(merged['line']);
                } else if (merged['text'] is String) {
                  merged['line'] = _sanitizeText(merged['text']);
                } else if (merged['value'] is String) {
                  merged['line'] = _sanitizeText(merged['value']);
                }
                out.add(im.MemoryFact.fromMap(merged));
              } else {
                m['type'] = m['type'] ?? 'insight';
                if (m['topic'] is String) {
                  m['topic'] = _sanitizeText(m['topic']);
                }
                if (m['line'] is String) {
                  m['line'] = _sanitizeText(m['line']);
                } else if (m['text'] is String) {
                  m['line'] = _sanitizeText(m['text']);
                } else if (m['value'] is String) {
                  m['line'] = _sanitizeText(m['value']);
                }
                out.add(im.MemoryFact.fromMap(m));
              }
            } else if (e is String) {
              final line = _sanitizeText(e);
              if (line.isNotEmpty) {
                out.add(im.MemoryFact.fromMap({
                  'type': 'insight',
                  'line': line,
                }));
              }
            }
          } catch (_) {
            // tolerant: invalide Einträge ignorieren
          }
        }
      }
    }

    // Simple Dedupe nach (type, topic, line/text), case-insensitiv — typsicher
    final seen = <String>{};
    final deduped = <im.MemoryFact>[];

    String _lowerStrOr(Object? v, String or) {
      if (v is String) return v.toLowerCase();
      return or;
    }

    for (final f in out) {
      final kType = _lowerStrOr(_factType(f), 'insight');
      final kTopic = _lowerStrOr(_factTopic(f), '');
      final kLine = _lowerStrOr(_factLine(f), '');
      final k = '$kType::$kTopic::$kLine';
      if (k.replaceAll(':', '').trim().isEmpty) {
        // Wenn praktisch leer, einfach übernehmen (z. B. nur score/tags)
        deduped.add(f);
        continue;
      }
      if (seen.add(k)) deduped.add(f);
    }
    return deduped;
  }

  /// Kurzer Bridge-Satz für UI/Worker-Kontext (nutzt die Adapter).
  static String? buildContextHint({
    List<im.MemoryFact> facts = const [],
    String? activeFacet,
    String? topicPin,
    int maxLen = 180,
  }) {
    final tokens = <String>[];

    bool hasInsensitive(List<String> list, String s) =>
        list.any((x) => x.toLowerCase() == s.toLowerCase());

    void push(String? s) {
      final t = _sanitizeText((s ?? '').trim());
      if (t.isEmpty) return;
      if (!hasInsensitive(tokens, t)) tokens.add(t);
    }

    // Priorität: aktive Facette → Topic-Pin → (Fact.topic → Fact.line/text)
    push(activeFacet);
    push(topicPin);

    for (final f in facts) {
      if (tokens.length >= 2) break;
      final topic = _factTopic(f);
      if (topic.isNotEmpty) push(topic);
      if (tokens.length >= 2) break;
      final line = _factLine(f);
      if (line.isNotEmpty) push(line);
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
    var cut = t.substring(0, maxLen).trimRight();
    if (cut.endsWith('**')) {
      cut = cut.substring(0, cut.length - 2).trimRight();
    }
    return '$cut…';
  }
}
