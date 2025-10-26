// lib/core/memory/memory_service.dart
//
// MemoryService — Worker-Kontext-Recall (nicht UI-blockierend)
// ------------------------------------------------------------
// • Flags (enabled/shareEnabled) mit Persistenz via MemoryStore (best-effort)
// • saveFromWorker(): tolerant, fängt Fehler ab, aktualisiert leichten Hint-Cache
// • Read-APIs: latest(), topFacets(), recentTopics() — alle async
// • buildContextHint(): SYNCHRON, nutzt kleinen In-Memory-Cache (TTL)
// • recall(): sanfte, asynchrone Vorschläge (Labels), deduped
// • Byte-Kontext (sync, klein): tryGetByteContext/exportByteContext/byteContext
// • Warmup-Hooks: warmup()/preload() (best-effort, ohne UI zu blockieren)
//
// Leitlinie: Memory darf die UI nie blockieren. Alle schweren Pfade sind async,
// der synchrone Hint nutzt nur kleine In-Memory-Daten.

import 'dart:convert' show jsonEncode, utf8;

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
  bool _shareEnabled = false; // Opt-in Share (Therapist-Mode) – Flag, Logik extern

  bool get enabled => _enabled;
  bool get shareEnabled => _shareEnabled;

  // Kleiner, rein lokaler Cache für buildContextHint() (sync!)
  MemoryContextHint? _lastHint;
  DateTime? _lastHintTs;

  // Optionale weiche Caches (kurzer TTL, wenige Elemente)
  List<String>? _latestTopicsCache;
  DateTime? _latestTopicsTs;

  List<Facet>? _topFacetsCache;
  DateTime? _topFacetsTs;

  // TTLs (kurz halten, damit nichts „alt“ wird)
  static const _hintTtlDays = 14;
  static const _topicsTtlSec = 30;
  static const _facetsTtlSec = 30;

  // ---------------- Lifecycle / Flags ----------------------------------------

  Future<void> init() async {
    try {
      await _store.init();
      _enabled = _store.isEnabled;

      // shareEnabled best-effort lesen (mehrere mögliche Store-APIs, sicher nacheinander testen)
      bool enabled = false;
      // Variante 1: boolesches Feld/Getter 'isShareEnabled'
      try {
        final dyn = _store as dynamic;
        final v = dyn.isShareEnabled; // kann NoSuchMethod werfen
        if (v is bool) {
          enabled = v;
        }
      } catch (_) {/* ignore */}

      // Variante 2: Methode/Getter 'getShareEnabled()'
      if (!enabled) {
        try {
          final dyn = _store as dynamic;
          final res = dyn.getShareEnabled(); // kann NoSuchMethod werfen
          if (res is bool) {
            enabled = res;
          } else if (res is Future) {
            final v = await res;
            if (v is bool) enabled = v;
          }
        } catch (_) {/* ignore */}
      }

      _shareEnabled = enabled;
    } catch (_) {
      // Niemals UI blockieren; Flags bleiben bei Defaults.
    }
  }

  /// Best-effort: initialisiert Store & wärmt leichte Caches an.
  /// Wird vom ApiService opportunistisch (ohne await) aufgerufen.
  Future<void> warmup() async {
    try {
      await init();
      // kleine, häufig benutzte Reads anstoßen (aber nicht kritisch)
      try {
        await topFacets(limit: 8);
        await latestTopics(limit: 6);
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  /// Fire-and-forget-Anschubser (keine Abhängigkeit auf unawaited()).
  void preload() {
    // bewusst ohne await — Analyzer-Warnung ist ok; Fehler intern abgefangen
    warmup();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      await _store.setEnabled(v);
    } catch (_) {/* ignore */}
  }

  Future<void> setShareEnabled(bool v) async {
    _shareEnabled = v;
    // Best-effort Persistenz, ohne das konkrete Store-Interface vorauszusetzen.
    // Wichtig: Jede Variante in einem eigenen try/catch – damit ein NoSuchMethod
    // nicht die folgenden Fallbacks verhindert.
    try {
      final dyn = _store as dynamic;
      final r = dyn.setShareEnabled(v); // bevorzugte Methode
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setFlag('share_enabled', v); // generischer Flag-Setter
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOpt('share_enabled', v); // alternative Option-API
      if (r is Future) await r;
      return;
    } catch (_) {
      // still – niemals UI blockieren
    }
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

      // Weiche UI-Caches invalidieren (best effort, keine Garantien)
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
    try {
      await _store.clearAll();
    } catch (_) {/* ignore */}
  }

  // ---------------- Read ------------------------------------------------------

  Future<List<MemoryEntry>> latest(int n) async {
    try {
      return await _store.latest(limit: n);
    } catch (_) {
      return const <MemoryEntry>[];
    }
  }

  /// Aggregiert Top-Facetten (als Facet-Objekte mit 'hits').
  Future<List<Facet>> topFacets({int limit = 8}) async {
    try {
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
    } catch (_) {
      return const <Facet>[];
    }
  }

  /// Human-friendly „Letzte Themen“ (nur Labels, deduped, neueste zuerst).
  Future<List<String>> latestTopics({int limit = 6}) async {
    try {
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
    } catch (_) {
      return const <String>[];
    }
  }

  /// Alias (für ApiService.recentTopics)
  Future<List<String>> recentTopics({int limit = 6}) => latestTopics(limit: limit);

  /// Liefert eine kompakte Recall-Liste für UI-Brücken.
  /// Rückgabe: Liste aus Labels (Strings). Typ bleibt bewusst `List<dynamic>`,
  /// damit bestehende Call-Sites ohne Cast funktionieren.
  ///
  /// Strategie:
  /// 1) Nimm die jüngsten Themenlabels (latestTopics), dedupe, leicht
  ///    priorisiert nach topicHint (Prefix > Teiltreffer).
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
        int score(String s) {
          final t = s.toLowerCase();
          if (t.startsWith(hint)) return 2; // Prefix-Booster
          if (t.contains(hint)) return 1;   // Teiltreffer
          return 0;
        }
        tmp.sort((a, b) => score(b).compareTo(score(a)));
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

  // ---------------- Byte-Kontext (sync, klein) ------------------------------
  // Diese Hooks werden vom ApiService per dynamic optional aufgerufen.
  // Sie sind bewusst leichtgewichtig und nutzen nur den lokalen Hint-Cache.

  /// Bevorzugter Hook: gibt bis zu [maxBytes] Kontext-Bytes zurück (oder null).
  /// Inhalt: kompaktes JSON mit Facet-Keys & Topic-Labels aus dem Hint-Cache.
  List<int>? tryGetByteContext([int maxBytes = 2048]) {
    try {
      if (_lastHint == null) return null;
      final map = <String, dynamic>{
        if (_lastHint!.facets != null && _lastHint!.facets!.isNotEmpty)
          'facets': _lastHint!.facets!.take(6).toList(),
        if (_lastHint!.topics != null && _lastHint!.topics!.isNotEmpty)
          'topics': _lastHint!.topics!.take(6).toList(),
        if (_shareEnabled) 'share': true,
      };
      if (map.isEmpty) return null;
      final bytes = utf8.encode(jsonEncode(map));
      if (bytes.length <= maxBytes) return bytes;
      return bytes.sublist(0, maxBytes);
    } catch (_) {
      return null;
    }
  }

  /// Alternative Hook-Name (kompatibel zu ApiService): identisch zu tryGetByteContext.
  List<int>? exportByteContext([int maxBytes = 2048]) => tryGetByteContext(maxBytes);

  /// Minimaler Fallback-Name (kompatibel): identisch zu tryGetByteContext.
  List<int>? byteContext([int maxBytes = 2048]) => tryGetByteContext(maxBytes);
}
