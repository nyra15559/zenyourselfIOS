// lib/core/memory/memory_service.dart
//
// MemoryService — Worker-Kontext-Recall (nicht UI-blockierend)
// ------------------------------------------------------------
// • Flags (enabled/shareEnabled) mit Persistenz via MemoryStore
// • saveFromWorker(): tolerant, fängt Fehler ab, aktualisiert leichten Hint-Cache
// • Read-APIs: latest(), topFacets(), recentTopics() — alle async
// • buildContextHint(): SYNCHRON, nutzt kleinen In-Memory-Cache (TTL)
// • recall(): sanfte, asynchrone Vorschläge (Labels), deduped
//
// Leitlinie: Memory darf die UI nie blockieren. Alle schweren Pfade sind async,
// der synchrone Hint nutzt nur kleine In-Memory-Daten.

import '../models/insight_models.dart';
import 'memory_entry.dart';
import 'memory_mapper.dart';
import 'memory_store.dart';

/// Leichte, synchrone Hint-Struktur für den Worker.
/// Wird von ApiService._appendMemoryHints() genutzt.
/// Alle Felder optional; leere/nicht vorhandene Felder werden nicht gesendet.
class MemoryContextHint {
  final List<String>? facets; // z. B. Facet-Keys (stabil)
  final List<String>? tags;   // optional (derzeit nicht gepflegt)
  final List<String>? topics; // human labels (z. B. Facet-Labels)
  const MemoryContextHint({this.facets, this.tags, this.topics});
}

class MemoryService {
  MemoryService._internal();
  static final MemoryService instance = MemoryService._internal();

  final MemoryStore _store = MemoryStore.instance;

  bool _enabled = true;       // „Kontext-Gedächtnis“ (Ghost-Mode)
  bool _shareEnabled = false; // Opt-in Share (Therapist-Mode) – nur Flag, Logik extern

  bool get enabled => _enabled;
  bool get shareEnabled => _shareEnabled;

  // Kleiner, rein lokaler Cache für buildContextHint() (sync!)
  MemoryContextHint? _lastHint;
  DateTime? _lastHintTs;

  // Optional: weiche Caches für UI-nahe Abfragen (kurzer TTL, wenige Elemente)
  List<String>? _latestTopicsCache;
  DateTime? _latestTopicsTs;

  List<Facet>? _topFacetsCache;
  DateTime? _topFacetsTs;

  // TTLs (kurz halten, damit nichts „alt“ wird)
  static const _hintTtlDays = 14;
  static const _topicsTtlSec = 30;
  static const _facetsTtlSec = 30;
  static const _transcriptMaxRounds = 12;

  Future<void> init() async {
    await _store.init();
    _enabled = _store.isEnabled;
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await _store.setEnabled(v);
  }

  Future<void> setShareEnabled(bool v) async {
    _shareEnabled = v;
  }

  // ---------------- Write -----------------------------------------------------

  /// Speichert tolerant aus einer Worker-Response (no-op, wenn disabled).
  /// [source] ist optional (Telemetrie: z. B. "reflect_full", "next_turn_full").
  Future<void> saveFromWorker(dynamic workerResponse, {String? source}) async {
    if (!_enabled) return;
    try {
      if (workerResponse is! Map) return; // wir erwarten eine Map vom Worker
      final map = Map<String, dynamic>.from(workerResponse);

      final entry = MemoryMapper.fromWorker(map); // <- nullable
      if (entry == null) return;                  // kein Signal -> still

      await _store.save(entry);

      // --------- Kleinen Sync-Hint-Cache aktualisieren -----------------------
      if (entry.contextFacets.isNotEmpty) {
        // Sortiere nach hits (desc), dann by label asc – defensiv
        final sorted = [...entry.contextFacets]..sort((a, b) {
          final byHits = (b.hits).compareTo(a.hits);
          if (byHits != 0) return byHits;
          return (a.label).toLowerCase().compareTo((b.label).toLowerCase());
        });

        final facetKeys   = sorted.map((f) => f.key).where((s) => s.trim().isNotEmpty).toList();
        final facetLabels = sorted.map((f) => f.label).where((s) => s.trim().isNotEmpty).toList();

        _lastHint = MemoryContextHint(
          facets: facetKeys.take(6).toList(growable: false),  // defensiv begrenzen
          tags: null,                                         // optional später
          topics: facetLabels.take(6).toList(growable: false),
        );
        _lastHintTs = DateTime.now();
      }

      // Weiche UI-Caches update’n (best effort, keine Garantien)
      _latestTopicsCache = null;
      _latestTopicsTs = null;
      _topFacetsCache = null;
      _topFacetsTs = null;

    } catch (_) {
      // still – Memory darf niemals die Hauptlogik stören
    }
  }

  Future<void> clear() async {
    _lastHint = null;
    _lastHintTs = null;
    _latestTopicsCache = null;
    _latestTopicsTs = null;
    _topFacetsCache = null;
    _topFacetsTs = null;
    await _store.clearAll();
  }

  // ---------------- Read ------------------------------------------------------

  Future<List<MemoryEntry>> latest(int n) => _store.latest(limit: n);

  /// Aggregiert Top-Facetten (als Facet-Objekte mit 'hits').
  Future<List<Facet>> topFacets({int limit = 8}) async {
    // kurzer Cache (vermeidet häufige SharedPrefs-Reads in UI-Schleifen)
    if (_topFacetsCache != null &&
        _topFacetsTs != null &&
        DateTime.now().difference(_topFacetsTs!).inSeconds <= _facetsTtlSec) {
      return _topFacetsCache!.take(limit).toList(growable: false);
    }

    final all = await _store.all();
    if (all.isEmpty) return const [];
    final counts = <String, int>{};
    final labels = <String, String>{};

    for (final e in all) {
      for (final f in e.contextFacets) {
        final k = f.key;
        counts[k] = (counts[k] ?? 0) + (f.hits <= 0 ? 1 : f.hits);
        labels.putIfAbsent(k, () => f.label);
      }
    }

    final keys = counts.keys.toList()
      ..sort((a, b) {
        final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
        if (byCount != 0) return byCount;
        // leichte Recency-Präferenz: erster Index im Verlauf
        final aIdx = all.indexWhere((e) => e.contextFacets.any((f) => f.key == a));
        final bIdx = all.indexWhere((e) => e.contextFacets.any((f) => f.key == b));
        return aIdx.compareTo(bIdx);
      });

    final result = keys.take(limit).map((k) =>
      Facet(key: k, label: labels[k] ?? k, hits: counts[k] ?? 1)
    ).toList(growable: false);

    _topFacetsCache = result;
    _topFacetsTs = DateTime.now();
    return result;
  }

  /// Human-friendly „Letzte Themen“ (nur Labels, deduped, neueste zuerst).
  Future<List<String>> latestTopics({int limit = 6}) async {
    // kurzer Cache
    if (_latestTopicsCache != null &&
        _latestTopicsTs != null &&
        DateTime.now().difference(_latestTopicsTs!).inSeconds <= _topicsTtlSec) {
      return _latestTopicsCache!.take(limit).toList(growable: false);
    }

    final entries = await latest(12);
    final out = <String>[];
    final seen = <String>{};
    for (final e in entries) {
      for (final f in e.contextFacets) {
        final key = f.key.toLowerCase();
        if (seen.add(key)) {
          out.add(f.label);
          if (out.length >= limit) {
            _latestTopicsCache = out;
            _latestTopicsTs = DateTime.now();
            return out;
          }
        }
      }
    }
    _latestTopicsCache = out;
    _latestTopicsTs = DateTime.now();
    return out;
  }

  /// Alias (für ApiService.recentTopics)
  Future<List<String>> recentTopics({int limit = 6}) => latestTopics(limit: limit);

  /// Liefert eine kompakte Recall-Liste für UI-Brücken.
  /// Rückgabe: Liste aus Labels (Strings). Typ bleibt bewusst `List<dynamic>`,
  /// damit bestehende Call-Sites ohne Cast funktionieren.
  ///
  /// Strategie:
  /// 1) Nimm die jüngsten Themenlabels (latestTopics), dedupe, ggf. nach topicHint
  ///    leicht vorreihen.
  /// 2) Falls leer → Fallback auf Facetten-Labels (topFacets).
  Future<List<dynamic>> recall({int limit = 6, String? topicHint}) async {
    try {
      // 1) Neueste Themen laden (etwas großzügiger, dann dedupen & schneiden)
      final int takeN = (limit * 2).clamp(6, 24).toInt();
      final rawTopics = await latestTopics(limit: takeN);
      final seen = <String>{};
      final ranked = <String>[];

      // Optionales weiches Re-Ranking nach topicHint
      final hint = (topicHint ?? '').trim().toLowerCase();
      final tmp = [...rawTopics];

      if (hint.isNotEmpty) {
        tmp.sort((a, b) {
          final al = a.toLowerCase().contains(hint);
          final bl = b.toLowerCase().contains(hint);
          if (al == bl) return 0;
          return al ? -1 : 1; // Treffer zuerst
        });
      }

      for (final t in tmp) {
        final label = t.trim();
        if (label.isEmpty) continue;
        final key = label.toLowerCase();
        if (seen.add(key)) {
          ranked.add(label);
          if (ranked.length >= limit) break;
        }
      }

      if (ranked.isNotEmpty) {
        // Strings genügen für die Bridge-Composer-Logik
        return List<dynamic>.from(ranked);
      }

      // 2) Fallback: Facetten-Labels
      final facets = await topFacets(limit: limit);
      final viaFacets = facets
          .map((f) => f.label.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);

      return List<dynamic>.from(viaFacets);
    } catch (_) {
      // Memory darf niemals die Hauptlogik stören
      return const <dynamic>[];
    }
  }

  // ---------------- Sync-Hints für ApiService -------------------------------

  /// Liefert eine **synchrone**, leichte Hint-Struktur für den Worker.
  /// ApiService ruft das innerhalb des Payload-Baus auf (kein await möglich).
  ///
  /// Aktuell nutzen wir einen kleinen lokalen Cache (_lastHint), der bei
  /// saveFromWorker() aktualisiert wird. Ist nichts im Cache oder zu alt,
  /// geben wir null zurück (ApiService sendet dann keinen context_hint).
  MemoryContextHint? buildContextHint({
    int maxFacets = 3,
    int maxTags = 5,
    int maxAgeDays = _hintTtlDays,
  }) {
    try {
      if (!_enabled) return null;
      final hint = _lastHint;
      if (hint == null) return null;

      // Altersprüfung (grob, Tagesgenauigkeit reicht hier völlig)
      if (_lastHintTs != null && maxAgeDays > 0) {
        final ageDays = DateTime.now().difference(_lastHintTs!).inDays;
        if (ageDays > maxAgeDays) return null;
      }

      // Begrenzen ohne Seiteneffekte
      final facets = (hint.facets == null)
          ? null
          : hint.facets!.take(maxFacets).toList(growable: false);
      final tags = (hint.tags == null)
          ? null
          : hint.tags!.take(maxTags).toList(growable: false);
      // topics defensiv auf 5 begrenzen (UI/Worker: human labels)
      final topics = (hint.topics == null)
          ? null
          : hint.topics!.take(5).toList(growable: false);

      // Nichts Sinnvolles? → null
      if ((facets == null || facets.isEmpty) &&
          (tags == null || tags.isEmpty) &&
          (topics == null || topics.isEmpty)) {
        return null;
      }

      return MemoryContextHint(facets: facets, tags: tags, topics: topics);
    } catch (_) {
      return null;
    }
  }

  // ---------------- Reflection Transcript -----------------------------------

  Future<void> saveReflectionTranscript({
    required List<Map<String, dynamic>> rounds,
    Map<String, dynamic>? session,
  }) async {
    if (!_enabled) return;
    try {
      if (rounds.isEmpty) {
        await _store.clearReflectionTranscript();
        return;
      }

      final start = rounds.length > _transcriptMaxRounds
          ? rounds.length - _transcriptMaxRounds
          : 0;
      final sliced = rounds.sublist(start);

      final seenIds = <String>{};
      final normalized = <Map<String, dynamic>>[];
      for (final raw in sliced) {
        final map = Map<String, dynamic>.from(raw);
        final id = (map['id'] ?? '').toString();
        if (id.isNotEmpty && !seenIds.add(id)) {
          continue;
        }
        final userInput = (map['userInput'] ?? '').toString().trim();
        final stepsRaw = (map['steps'] is List)
            ? List<dynamic>.from(map['steps'] as List)
            : const <dynamic>[];
        if (userInput.isEmpty && stepsRaw.isEmpty) {
          continue;
        }
        map['steps'] = stepsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        normalized.add(map);
      }

      if (normalized.isEmpty) {
        await _store.clearReflectionTranscript();
        return;
      }

      final payload = <String, dynamic>{
        'version': 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'rounds': normalized,
        if (session != null && session.isNotEmpty) 'session': session,
      };

      await _store.saveReflectionTranscript(payload);
    } catch (_) {
      // Memory darf niemals die Hauptlogik stören
    }
  }

  Future<Map<String, dynamic>> loadReflectionTranscript() async {
    try {
      if (!_enabled) return const {};
      final raw = await _store.loadReflectionTranscript();
      if (raw.isEmpty) return const {};

      final roundsRaw = raw['rounds'];
      final rounds = <Map<String, dynamic>>[];
      if (roundsRaw is List) {
        for (final r in roundsRaw) {
          if (r is Map) {
            rounds.add(Map<String, dynamic>.from(r));
          }
        }
      }

      final sessionRaw = raw['session'];
      Map<String, dynamic>? session;
      if (sessionRaw is Map) {
        session = Map<String, dynamic>.from(sessionRaw);
      }

      final updatedAtRaw = raw['updatedAt'] ?? raw['updated_at'];
      final updatedAt = updatedAtRaw is String ? updatedAtRaw : null;

      return <String, dynamic>{
        if (rounds.isNotEmpty) 'rounds': rounds,
        if (session != null) 'session': session,
        if (updatedAt != null && updatedAt.trim().isNotEmpty)
          'updatedAt': updatedAt,
        if (raw['version'] is int) 'version': raw['version'],
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> clearReflectionTranscript() async {
    try {
      await _store.clearReflectionTranscript();
    } catch (_) {
      // still
    }
  }
}
