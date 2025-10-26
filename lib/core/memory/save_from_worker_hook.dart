// lib/core/memory/save_from_worker_hook.dart
//
// SaveFromWorkerHook — Panda v1.2
// -----------------------------------------------------------------------------
// Kleiner, toleranter Sammel-Hook, der Worker-Antworten zentral an das lokale
// Memory weiterreicht. Zwei Pfade:
//   1) mergeFacts(...) — extrahiert „Fakten/Insights/Themen“ aus dem Turn
//   2) recordAcknowledge(...) — bestätigt Einsicht, aber nur bei Themen-Overlap
//
// Eigenschaften:
// • Zero-crash/tolerant: arbeitet defensiv mit dynamic + try/catch
// • Keine UI-Abhängigkeit, kein State: reine Utility-Funktionen
// • Themen-Overlap: vermeidet Memory-Spam (nur bei Schnittmenge)
// • Akzeptiert *jede* Turn-Form (Map oder typed), liest robust verschachtelte Felder
//
// Einbindung (Beispiel): … (gekürzt)

library save_from_worker_hook;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

// Lokaler Memory-Service (stellt i.d.R. MemoryStore bereit)
import 'memory_service.dart' as mem;

/// Öffentliche API des Hooks.
class SaveFromWorkerHook {
  SaveFromWorkerHook._();

  static Future<void> processTurn({
    required dynamic turn,
    String? userInput,
    bool debug = false,
  }) async {
    if (turn == null) return;

    final Map<String, dynamic> m = _coerceMap(turn);

    final session = _coerceSession(m);
    final flow    = _coerceFlow(m);
    final risk    = _riskLevel(m); // 'high' | 'mild' | 'none'

    final facts   = _extractFacts(m);
    final topicsW = _extractWorkerTopics(m);
    final score   = flow['insight_score'] is num ? (flow['insight_score'] as num).toDouble() : null;
    final bool insightFlag =
        _asBool(m['insight']) ||
        _asBool(_path(m, const ['understanding', 'insight'])) ||
        (score != null && score >= 0.60);

    final topicsU = await _topicsFromUserInput(userInput) ?? const <String>[];

    final overlap = _overlap(topicsU, topicsW);
    final hasOverlap = overlap.isNotEmpty;

    if (facts.isNotEmpty && hasOverlap) {
      await _callMergeFacts(
        facts: facts,
        topics: topicsW,
        session: session,
        risk: risk,
        debug: debug,
      );
    } else if (debug && kDebugMode) {
      debugPrint('[SaveFromWorkerHook] skip mergeFacts '
          '(facts=${facts.length}, overlap=$hasOverlap)');
    }

    if (insightFlag && hasOverlap) {
      await _callRecordAcknowledge(
        topics: overlap,
        session: session,
        debug: debug,
      );
    } else if (debug && kDebugMode) {
      debugPrint('[SaveFromWorkerHook] skip recordAcknowledge '
          '(insight=$insightFlag, overlap=$hasOverlap)');
    }
  }

  // -------- Interna: Calls (tolerant) ---------------------------------------

  static Future<void> _callMergeFacts({
    required List<String> facts,
    required List<String> topics,
    required Map<String, dynamic> session,
    required String risk,
    required bool debug,
  }) async {
    try {
      final svc = mem.MemoryService.instance;
      final storeDyn = (svc as dynamic).store ?? svc;

      try {
        await storeDyn.mergeFacts?.call(
          facts: facts,
          topics: topics,
          session: session,
          risk: risk,
          origin: 'reflection',
        );
        if (debug && kDebugMode) {
          debugPrint('[SaveFromWorkerHook] mergeFacts(facts:${facts.length}) ✓');
        }
        return;
      } catch (_) {
        await storeDyn.mergeFacts?.call(
          items: facts,
          topics: topics,
          session: session,
          origin: 'reflection',
        );
        if (debug && kDebugMode) {
          debugPrint('[SaveFromWorkerHook] mergeFacts(items:${facts.length}) ✓');
        }
      }
    } catch (e) {
      if (debug && kDebugMode) {
        debugPrint('[SaveFromWorkerHook] mergeFacts error: $e');
      }
    }
  }

  static Future<void> _callRecordAcknowledge({
    required List<String> topics,
    required Map<String, dynamic> session,
    required bool debug,
  }) async {
    try {
      final svc = mem.MemoryService.instance;
      final storeDyn = (svc as dynamic).store ?? svc;

      try {
        await storeDyn.recordAcknowledge?.call(
          topics: topics,
          session: session,
          origin: 'reflection',
        );
        if (debug && kDebugMode) {
          debugPrint('[SaveFromWorkerHook] recordAcknowledge(topics:${topics.length}) ✓');
        }
        return;
      } catch (_) {
        await storeDyn.recordAcknowledge?.call();
        if (debug && kDebugMode) {
          debugPrint('[SaveFromWorkerHook] recordAcknowledge() ✓ (fallback)');
        }
      }
    } catch (e) {
      if (debug && kDebugMode) {
        debugPrint('[SaveFromWorkerHook] recordAcknowledge error: $e');
      }
    }
  }

  // -------- Extractors / Coercers -------------------------------------------

  static Map<String, dynamic> _coerceMap(dynamic any) {
    if (any is Map<String, dynamic>) return any;
    if (any is Map) return Map<String, dynamic>.from(any);
    try {
      final j = (any as dynamic).toJson?.call();
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _coerceSession(Map<String, dynamic> m) {
    final raw = (m['session'] is Map) ? Map<String, dynamic>.from(m['session']) : <String, dynamic>{};
    final threadId = _firstNonEmpty([raw['thread_id'], raw['id'], raw['threadId']]);
    final turnIdx = _coerceInt(raw['turn_index'] ?? raw['turn'] ?? raw['turnIndex']) ?? 0;
    final maxTurns = _coerceInt(raw['max_turns'] ?? raw['maxTurns']) ?? 3;
    return {
      'thread_id': '$threadId',
      'turn_index': turnIdx,
      'max_turns': maxTurns,
    };
  }

  static Map<String, dynamic> _coerceFlow(Map<String, dynamic> m) {
    final f = (m['flow'] is Map) ? Map<String, dynamic>.from(m['flow']) : <String, dynamic>{};
    final recommendEnd = _asBool(f['recommend_end']);
    final moodPrompt   = _asBool(f['mood_prompt']) || recommendEnd || _asBool(_path(m, const ['mood','prompt']));
    final q = _firstNonEmpty([
      f['question'],
      _firstOfList(_asStringList(f['questions'])),
      _path(m, const ['question']),
    ]);
    final iscore = _coerceNum(f['insight_score']);
    return {
      'mood_prompt': moodPrompt,
      'recommend_end': recommendEnd,
      if ((q ?? '').toString().trim().isNotEmpty) 'question': (q as String).trim(),
      if (iscore != null) 'insight_score': iscore,
    };
  }

  static String _riskLevel(Map<String, dynamic> m) {
    final rl = _asString(m['risk_level']).toLowerCase();
    final legacy = _asString(m['level']).toLowerCase();
    if (rl == 'high' || rl == 'mild') return rl;
    if (legacy == 'high' || legacy == 'mild') return legacy;
    final flag = _asBool(m['risk']);
    return flag ? 'mild' : 'none';
  }

  static List<String> _extractFacts(Map<String, dynamic> m) {
    final out = <String>[];

    void addAll(dynamic v) {
      if (v is List) {
        for (final e in v) {
          final s = (e is Map)
              ? _asString(e['text']).trim()
              : _asString(e).trim();
          if (s.isNotEmpty) out.add(_cap(s, 180));
        }
      } else if (v is String) {
        final parts = _splitBullets(v);
        for (final s in parts) {
          final t = s.trim();
          if (t.isNotEmpty) out.add(_cap(t, 180));
        }
      }
    }

    addAll(m['memories']);
    if (m['memory'] is Map) addAll((m['memory'] as Map)['facts']);
    addAll(m['facts']);
    addAll(m['insights']);
    addAll(_path(m, const ['understanding', 'lines']));

    final seen = <String>{};
    final dedup = <String>[];
    for (final s in out) {
      final k = s.toLowerCase();
      if (seen.add(k)) dedup.add(s);
      if (dedup.length >= 10) break;
    }
    return dedup;
  }

  static List<String> _extractWorkerTopics(Map<String, dynamic> m) {
    final out = <String>[
      ..._asStringList(m['tags']),
      ..._asStringList(_path(m, const ['context','topics'])),
      ..._asStringList(_path(m, const ['understanding','facets'])),
      ..._asStringList(_path(m, const ['flow','facets'])),
      ..._asStringList(m['topics']),
      ..._asStringList(m['recent_facets']),
      ..._asStringList(m['recent_tags']),
      ..._asStringList(m['last_themes']),
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final seen = <String>{};
    final dedup = <String>[];
    for (final t in out) {
      final key = t.toLowerCase();
      if (seen.add(key)) dedup.add(_cap(t, 72));
      if (dedup.length >= 12) break;
    }
    return dedup;
  }

  static Future<List<String>?> _topicsFromUserInput(String? userInput) async {
    final seed = (userInput ?? '').trim();
    if (seed.isEmpty) {
      try {
        final hint = mem.MemoryService.instance.buildContextHint(
          maxFacets: 3, maxTags: 5, maxAgeDays: 14,
        );
        if (hint != null) {
          final facetsDyn = (hint as dynamic).facets;
          if (facetsDyn is List) {
            return facetsDyn
                .map((e) => (e == null ? '' : e.toString()).trim())
                .where((s) => s.isNotEmpty)
                .toList(growable: false);
          }
        }
      } catch (_) {}
      return null;
    }

    // Bevorzugt: MemoryStore.pickFor(userText)
    try {
      final storeDyn = (mem.MemoryService.instance as dynamic).store ??
          mem.MemoryService.instance;
      final pick = await storeDyn.pickFor?.call(seed);
      final topics = <String>[
        ..._asStringList(_asMap(pick)['topics']),
        ..._asStringList(_asMap(pick)['facets']),
        ..._asStringList(_asMap(pick)['tags']),
        if (_asString(_asMap(pick)['topic']).isNotEmpty)
          _asString(_asMap(pick)['topic']),
      ].where((e) => e.trim().isNotEmpty).toList();
      if (topics.isNotEmpty) return topics;
    } catch (_) {}

    final tokens = seed
        .toLowerCase()
        .split(RegExp(r'[^a-zäöüß0-9]+'))
        .where((w) => w.length >= 4)
        .toSet()
        .take(6)
        .toList();
    return tokens;
  }

  // -------- Utilities --------------------------------------------------------

  static dynamic _path(Map<String, dynamic> m, List<String> p) {
    dynamic cur = m;
    for (final k in p) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur;
  }

  static List<String> _overlap(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return const <String>[];
    final A = a.map((e) => e.toLowerCase().trim()).where((e) => e.isNotEmpty).toSet();
    final res = <String>[];
    for (final t in b) {
      final k = t.toLowerCase().trim();
      if (A.contains(k)) res.add(t);
    }
    return res;
  }

  static String _firstNonEmpty(List<dynamic> xs) {
    for (final x in xs) {
      final s = _asString(x).trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _cap(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max).trimRight()}…';
  }

  static String _asString(dynamic v) {
    if (v is String) return v;
    if (v == null) return '';
    return v.toString();
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return const <String>[];
      final parts = _splitBullets(s);
      return parts.isEmpty ? <String>[s] : parts;
    }
    return const <String>[];
  }

  static List<String> _splitBullets(String s) {
    return s
        .split(RegExp(r'\r?\n+|[•\-\–\—]\s+|;\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y';
    }
    return false;
  }

  static int? _coerceInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static num? _coerceNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim());
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static String? _firstOfList(List<String> xs) => xs.isEmpty ? null : xs.first;
}
