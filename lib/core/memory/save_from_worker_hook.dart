// [BASELINE] lib/core/memory/save_from_worker_hook.dart (Stand: 29.10.2025)
// lib/core/memory/save_from_worker_hook.dart
//
// SaveFromWorkerHook — Panda v1.4 (kompatibel mit MemoryService v6.3.3+hotfix1)
// -----------------------------------------------------------------------------
// Kleiner, toleranter Sammel-Hook, der Worker-Antworten zentral an das lokale
// Memory weiterreicht. Zwei Pfade:
//   1) saveFromWorker(...)  → jetzt via MemoryService.saveFromWorker(payload, source:'hook')
//   2) recordAcknowledge(...) → MemoryService.recordAcknowledge(ackMap)
//
// Eigenschaften:
// • Zero-crash/tolerant: arbeitet defensiv mit dynamic + try/catch
// • Keine UI-Abhängigkeit, kein State: reine Utility-Funktionen
// • Themen-Overlap: vermeidet Memory-Spam für weiche Facts (nur bei Schnittmenge)
// • Akzeptiert *jede* Turn-Form (Map oder typed), liest robust verschachtelte Felder
//
// Änderungen v1.4 (S12.1):
// • NEU: Übernimmt `memories_to_save` (auch Aliasse & verschachtelt unter `plan.*`).
// • Starke Fakten aus `memories_to_save` werden IMMER persistiert (ohne Overlap-Gate).
// • Weiche Fakten (z. B. aus `facts/insights/understanding.lines`) bleiben overlapped-gated.
// • Payload enthält zusätzlich roh-normalisierte `memories_to_save`-Einträge.
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
    final flow = _coerceFlow(m);
    final risk = _riskLevel(m); // 'high' | 'mild' | 'none'

    // 1) Starke Memories: memories_to_save (immer speichern)
    final memSave = _extractMemoriesToSave(m); // List<Map<String,dynamic>>
    final strongFacts = _factsFromMemoriesToSave(memSave); // List<String>
    final strongTopics = _topicsFromMemoriesToSave(memSave); // List<String>

    // 2) Weiche Memories/Fakten: aus diversen Feldern (behutsam + overlap)
    final softFacts = _extractSoftFacts(m);
    final workerTopics = _mergeDedup<String>(strongTopics, _extractWorkerTopics(m));

    final score = flow['insight_score'] is num
        ? (flow['insight_score'] as num).toDouble()
        : null;
    final bool insightFlag = _asBool(m['insight']) ||
        _asBool(_path(m, const ['understanding', 'insight'])) ||
        (score != null && score >= 0.60);

    final topicsU = await _topicsFromUserInput(userInput) ?? const <String>[];
    final overlap = _overlap(topicsU, workerTopics);
    final hasOverlap = overlap.isNotEmpty;

    // --- Persistenz: Starke Fakten zuerst, ohne Gate ------------------------
    if (memSave.isNotEmpty || strongFacts.isNotEmpty) {
      await _callSaveFromWorker(
        session: session,
        risk: risk,
        facts: strongFacts,
        topics: workerTopics,
        rawMemoriesToSave: memSave,
        debug: debug,
      );
    } else if (debug && kDebugMode) {
      debugPrint('[SaveFromWorkerHook] no strong memories_to_save found');
    }

    // --- Persistenz: Weiche Fakten nur bei Themen-Overlap -------------------
    if (softFacts.isNotEmpty && hasOverlap) {
      await _callSaveFromWorker(
        session: session,
        risk: risk,
        facts: softFacts,
        topics: workerTopics,
        // keine rawMemoriesToSave hier, das kam ggf. schon oben
        debug: debug,
      );
    } else if (debug && kDebugMode) {
      debugPrint('[SaveFromWorkerHook] skip soft facts '
          '(facts=${softFacts.length}, overlap=$hasOverlap)');
    }

    // --- Acknowledge: nur wenn sinnvoll (Insight + Overlap) -----------------
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

  // -------- Interna: Calls (MemoryService Public-APIs) ----------------------

  static Future<void> _callSaveFromWorker({
    required Map<String, dynamic> session,
    required String risk,
    required List<String> facts,
    required List<String> topics,
    List<Map<String, dynamic>> rawMemoriesToSave = const <Map<String, dynamic>>[],
    required bool debug,
  }) async {
    try {
      final payload = <String, dynamic>{
        'session': session, // {thread_id, turn_index, max_turns}
        'risk_level': risk, // 'high' | 'mild' | 'none'
        if (facts.isNotEmpty) 'facts': _dedupCap(facts, 10, 180),
        if (topics.isNotEmpty) 'topics': _dedupCap(topics, 12, 72),
        if (rawMemoriesToSave.isNotEmpty)
          'memories_to_save': rawMemoriesToSave, // normalisiert
        'origin': 'reflection', // Telemetrie-Hinweis
      };

      await mem.MemoryService.instance.saveFromWorker(payload, source: 'hook');

      if (debug && kDebugMode) {
        debugPrint('[SaveFromWorkerHook] saveFromWorker '
            '(facts:${facts.length}, raw:${rawMemoriesToSave.length}) ✓');
      }
    } catch (e) {
      if (debug && kDebugMode) {
        debugPrint('[SaveFromWorkerHook] saveFromWorker error: $e');
      }
    }
  }

  static Future<void> _callRecordAcknowledge({
    required List<String> topics,
    required Map<String, dynamic> session,
    required bool debug,
  }) async {
    try {
      final ack = <String, dynamic>{
        'session_id': (session['thread_id'] ?? '').toString(),
        'turn': session['turn_index'] ?? 0,
        'facet_keys': _dedupCap(topics, 8, 72),
        'ts': DateTime.now().toUtc().toIso8601String(),
        'origin': 'reflection',
      };

      await mem.MemoryService.instance.recordAcknowledge(ack);

      if (debug && kDebugMode) {
        debugPrint('[SaveFromWorkerHook] recordAcknowledge(${topics.length}) ✓');
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
    final raw = (m['session'] is Map)
        ? Map<String, dynamic>.from(m['session'])
        : <String, dynamic>{};
    final threadId =
        _firstNonEmpty([raw['thread_id'], raw['id'], raw['threadId']]);
    final turnIdx =
        _coerceInt(raw['turn_index'] ?? raw['turn'] ?? raw['turnIndex']) ?? 0;
    final maxTurns = _coerceInt(raw['max_turns'] ?? raw['maxTurns']) ?? 3;
    return {
      'thread_id': '$threadId',
      'turn_index': turnIdx,
      'max_turns': maxTurns,
    };
  }

  static Map<String, dynamic> _coerceFlow(Map<String, dynamic> m) {
    final f = (m['flow'] is Map)
        ? Map<String, dynamic>.from(m['flow'])
        : <String, dynamic>{};
    final recommendEnd = _asBool(f['recommend_end']);
    final moodPrompt = _asBool(f['mood_prompt']) ||
        recommendEnd ||
        _asBool(_path(m, const ['mood', 'prompt']));
    final q = _firstNonEmpty([
      f['question'],
      _firstOfList(_asStringList(f['questions'])),
      _path(m, const ['question']),
    ]);
    final iscore = _coerceNum(f['insight_score']);
    return {
      'mood_prompt': moodPrompt,
      'recommend_end': recommendEnd,
      if ((q ?? '').toString().trim().isNotEmpty)
        'question': (q as String).trim(),
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

  // --- S12.1: memories_to_save (starke Fakten) -------------------------------

  /// Liest verschiedene Quellen für `memories_to_save` und normalisiert sie.
  /// Rückgabe: Liste von Maps mit mind. { 'text': String } + optional {topic,tags,facets,meta}
  static List<Map<String, dynamic>> _extractMemoriesToSave(Map<String, dynamic> m) {
    List<Map<String, dynamic>> collect(dynamic v) {
      final out = <Map<String, dynamic>>[];
      if (v == null) return out;
      final list = (v is List) ? v : (v is Map ? [v] : const []);
      for (final e in list) {
        if (e is Map) {
          final mm = Map<String, dynamic>.from(e);
          final text = _firstNonEmpty([
            mm['text'],
            mm['value'],
            mm['fact'],
            _asMap(mm['fact'])['text'],
          ]).trim();
          if (text.isEmpty) continue;
          final topic = _firstNonEmpty([mm['topic'], mm['key'], mm['label']]).trim();
          final tags = _asStringList(mm['tags']);
          final facets = _asStringList(mm['facets']);
          final meta = _asMap(mm['meta']);
          out.add({
            'text': _cap(text, 220),
            if (topic.isNotEmpty) 'topic': _cap(topic, 72),
            if (tags.isNotEmpty) 'tags': _dedupCap(tags, 10, 36),
            if (facets.isNotEmpty) 'facets': _dedupCap(facets, 10, 36),
            if (meta.isNotEmpty) 'meta': meta,
          });
        } else if (e is String) {
          final t = e.trim();
          if (t.isNotEmpty) out.add({'text': _cap(t, 220)});
        }
      }
      return out;
    }

    final out = <Map<String, dynamic>>[];
    // Top-Level Aliasse
    out.addAll(collect(m['memories_to_save']));
    out.addAll(collect(m['memoriesToSave']));
    // Verschachtelt (häufig)
    out.addAll(collect(_path(m, const ['plan', 'memories_to_save'])));
    out.addAll(collect(_path(m, const ['plan', 'memoriesToSave'])));
    out.addAll(collect(_path(m, const ['primary', 'memories_to_save'])));
    out.addAll(collect(_path(m, const ['flow', 'memories_to_save'])));
    return _dedupMemSave(out);
  }

  static List<String> _factsFromMemoriesToSave(List<Map<String, dynamic>> memSave) {
    return _dedupCap(
      memSave.map((e) => _asString(e['text'])).where((s) => s.trim().isNotEmpty).toList(),
      12,
      220,
    );
  }

  static List<String> _topicsFromMemoriesToSave(List<Map<String, dynamic>> memSave) {
    final t1 = memSave.map((e) => _asString(e['topic'])).toList();
    final t2 = memSave.expand((e) => _asStringList(e['tags'])).toList();
    final t3 = memSave.expand((e) => _asStringList(e['facets'])).toList();
    return _dedupCap(<String>[...t1, ...t2, ...t3]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(), 16, 72);
  }

  // --- Weiche Fakten (behutsam) ---------------------------------------------

  static List<String> _extractSoftFacts(Map<String, dynamic> m) {
    final out = <String>[];

    void addAll(dynamic v) {
      if (v == null) return;
      if (v is List) {
        for (final e in v) {
          final s =
              (e is Map) ? _asString(e['text']).trim() : _asString(e).trim();
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

    // klassische weichere Quellen
    addAll(m['memories']);                       // evtl. unstrukturiert
    if (m['memory'] is Map) addAll(_asMap(m['memory'])['facts']);
    addAll(m['facts']);
    addAll(m['insights']);
    addAll(_path(m, const ['understanding', 'lines']));

    return _dedupCap(out, 10, 180);
  }

  static List<String> _extractWorkerTopics(Map<String, dynamic> m) {
    final out = <String>[
      ..._asStringList(m['tags']),
      ..._asStringList(_path(m, const ['context', 'topics'])),
      ..._asStringList(_path(m, const ['understanding', 'facets'])),
      ..._asStringList(_path(m, const ['flow', 'facets'])),
      ..._asStringList(m['topics']),
      ..._asStringList(m['recent_facets']),
      ..._asStringList(m['recent_tags']),
      ..._asStringList(m['last_themes']),
      // Bonus: explizite Analyse-Themen
      _asString(_path(m, const ['analysis', 'topic'])),
      ..._asStringList(_path(m, const ['analysis', 'topic_suggestions'])),
      _asString(_path(m, const ['speech_meta', 'topic'])),
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    return _dedupCap(out, 16, 72);
  }

  static Future<List<String>?> _topicsFromUserInput(String? userInput) async {
    final seed = (userInput ?? '').trim();
    if (seed.isEmpty) {
      try {
        final hint = mem.MemoryService.instance.buildContextHint(
          maxFacets: 3,
          maxTags: 5,
          maxAgeDays: 14,
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
    final A =
        a.map((e) => e.toLowerCase().trim()).where((e) => e.isNotEmpty).toSet();
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

  static List<T> _mergeDedup<T>(List<T> a, List<T> b) {
    final seen = <String>{};
    final out = <T>[];
    void addAll(Iterable<T> it) {
      for (final e in it) {
        final k = e.toString().toLowerCase().trim();
        if (k.isEmpty) continue;
        if (seen.add(k)) out.add(e);
      }
    }
    addAll(a);
    addAll(b);
    return out;
  }

  static List<String> _dedupCap(List<String> src, int maxCount, int maxLen) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in src) {
      final k = s.toLowerCase().trim();
      if (k.isEmpty) continue;
      if (seen.add(k)) {
        out.add(_cap(s, maxLen));
        if (out.length >= maxCount) break;
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _dedupMemSave(List<Map<String, dynamic>> src) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final m in src) {
      final text = _asString(m['text']).trim().toLowerCase();
      if (text.isEmpty) continue;
      if (seen.add(text)) out.add(m);
      if (out.length >= 20) break;
    }
    return out;
  }
}
