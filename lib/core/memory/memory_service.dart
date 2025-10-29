// [BASELINE] lib/core/memory/memory_service.dart — v6.3.1 (Stand: 29.10.2025)
// ZenYourself — MemoryService (Lokales Kontext-Gedächtnis, Ghost-Mode by default)
// -----------------------------------------------------------------------------
// Leitprinzipien:
// • Passives Gedächtnis (Regel 46): keine proaktive Aufzählung, nur kontextual nutzen
// • Ghost-Mode: keine PII ohne explizites Opt-in (Therapist-Mode = shareEnabled)
// • UI darf nie blockieren: schwere Pfade async/best-effort, sync nur Tiny-Hints/Bytes
// • Snake-Case für Payload-Brücken (context.memories{...}, memory_consent)
// • Tolerant gegenüber Store-Implementierungen (reflektive Calls mit Fallbacks)
//
// In diesem Modul:
// • Flags: enabled (lokal), shareEnabled (Opt-in)
// • Identity: saveIdentityName()/loadGreetingName()/forgetIdentityName()/learnNameFromText(...)
// • Konversation: saveUserTurn()/savePandaTurn() (best-effort Append)
// • Worker-Integration: saveFromWorker(workerResponse) + leichter Sync-Hint-Cache
// • Read-APIs: latest(), topFacets(), latestTopics()/recentTopics(), recall()
// • Hints/Memories: buildContextHint() (sync, klein, TTL), buildContextMemories(consent:)
// • Byte-Kontext: tryGetByteContext()/exportByteContext()/byteContext()
// • Warmup/Init: init()/warmup()/preload()
// • Fehlerbehandlung: niemals Exceptions nach außen; still/ignore in catch-Blöcken
//
// Abhängigkeiten: insight_models.dart (Facet), MemoryEntry/Mapper/Store
// -----------------------------------------------------------------------------

import 'dart:convert' show jsonEncode, utf8;

import '../models/insight_models.dart';
import 'memory_entry.dart';
import 'memory_mapper.dart';
import 'memory_store.dart';

/// Leichte, synchrone Hint-Struktur für den Worker (keine PII).
/// Wird von ApiService._appendMemoryHints() genutzt.
/// Alle Felder optional; leere Felder werden nicht gesendet.
class MemoryContextHint {
  final List<String>? facets; // stabile Facet-Keys
  final List<String>? tags;   // optional
  final List<String>? topics; // human labels der Facetten
  const MemoryContextHint({this.facets, this.tags, this.topics});

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (facets != null && facets!.isNotEmpty) 'facets': facets,
        if (tags != null && tags!.isNotOrEmpty) 'tags': tags,
        if (topics != null && topics!.isNotEmpty) 'topics': topics,
      };
}

class MemoryService {
  MemoryService._internal();
  static final MemoryService instance = MemoryService._internal();

  final MemoryStore _store = MemoryStore.instance;

  // Flags
  bool _enabled = true;        // Ghost-Mode (lokales Gedächtnis)
  bool _shareEnabled = false;  // Therapist-Mode (Opt-in)

  bool get enabled => _enabled;
  bool get shareEnabled => _shareEnabled;

  // Kleiner, rein lokaler Cache für buildContextHint() (sync!)
  MemoryContextHint? _lastHint;
  DateTime? _lastHintTs;

  // Weiche Caches (kurzer TTL)
  List<String>? _latestTopicsCache;
  DateTime? _latestTopicsTs;
  List<Facet>? _topFacetsCache;
  DateTime? _topFacetsTs;

  // TTLs
  static const _hintTtlDays = 14;
  static const _topicsTtlSec = 30;
  static const _facetsTtlSec = 30;

  // Storage-Keys (nur lokal)
  static const String _kIdentityName = 'identity.name';
  static const String _kIdentityGreetByName = 'identity.greet_by_name';
  static const String _kShareEnabled = 'share_enabled';

  // ---------------- Lifecycle / Flags ----------------------------------------

  Future<void> init() async {
    try {
      await _store.init();
      _enabled = _store.isEnabled;

      final se = await _getOptBool(_kShareEnabled);
      _shareEnabled = se ?? _tryReadShareEnabledReflective() ?? false;
    } catch (_) {
      // Defaults beibehalten
    }
  }

  Future<void> warmup() async {
    try {
      await init();
      try {
        await topFacets(limit: 8);
        await latestTopics(limit: 6);
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  void preload() {
    // fire-and-forget
    // ignore: discarded_futures
    warmup();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    try { await _store.setEnabled(v); } catch (_) {/* ignore */}
  }

  Future<void> setShareEnabled(bool v) async {
    _shareEnabled = v;
    try { await _setOptBool(_kShareEnabled, v); } catch (_) {/* ignore */}
  }

  // ---------------- Identity (lokal, nur bei Opt-in nutzbar) -----------------

  /// Speichert Name lokal (PII). greetByName steuert, ob Panda den Namen
  /// verwenden darf. Kein Versand ohne Consent.
  Future<void> saveIdentityName(String name, {bool greetByName = true}) async {
    try {
      final n = name.trim();
      if (n.isEmpty) return;
      await _setOptString(_kIdentityName, n);
      await _setOptBool(_kIdentityGreetByName, greetByName);
    } catch (_) {/* ignore */}
  }

  /// Löscht den lokal gespeicherten Namen (PII) und setzt greet_by_name=false.
  Future<void> forgetIdentityName() async {
    try {
      final dyn = _store as dynamic;
      try {
        final r = dyn.removeOpt?.call(_kIdentityName);
        if (r is Future) await r;
      } catch (_) {/* try next */}
      try {
        final r = dyn.setOptBool?.call(_kIdentityGreetByName, false);
        if (r is Future) await r;
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  /// Optionale Sammellöschung aller PII-Fakten (z. B. für Privacy-Screen).
  Future<void> forgetAllPII() async {
    try {
      final dyn = _store as dynamic;
      try {
        final r = dyn.forgetAllPII?.call();
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      await forgetIdentityName();
    } catch (_) {/* ignore */}
  }

  /// Liefert (Name, greetByName). Ist greetByName != true → Name NICHT verwenden.
  Future<({String? name, bool greetByName})> loadGreetingName() async {
    try {
      final name = await _getOptString(_kIdentityName);
      final greet = await _getOptBool(_kIdentityGreetByName) ?? false;
      final trimmed = (name?.trim().isEmpty ?? true) ? null : name!.trim();
      return (name: trimmed, greetByName: greet);
    } catch (_) {
      return (name: null, greetByName: false);
    }
  }

  /// Extrahiert aus natürlichem Text einen Vornamen und speichert ihn (Opt-in default true).
  /// Beispiele:
  ///  - „ich heiße matthias“, „mein name ist lea“, „nenn mich alex“,
  ///  - „ich bin sara“, „mein vorname ist tom“, „man nennt mich lio“, „ja einfach matthias“
  Future<void> learnNameFromText(String text, {bool greetByName = true}) async {
    if (!_enabled) return;
    try {
      final t = text.trim();
      if (t.isEmpty) return;

      final lower = t.toLowerCase();

      String? candidate;

      // klassische & erweiterte Muster
      final patterns = <RegExp>[
        RegExp(r"\bich\s+hei(?:ß|ss|s)e\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bmein\s+name\s+ist\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bmein\s+vorname\s+ist\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bich\s+bin\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bnenn\s+mich\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bman\s+nennt\s+mich\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bdu\s+kannst\s+mich\s+([a-zäöüß\-\' ]+)\s+nennen", caseSensitive: false),
        RegExp(r"\bja(?:,\s*)?\s*einfach\s+([a-zäöüß\-\' ]+)\b", caseSensitive: false),
      ];

      for (final re in patterns) {
        final m = re.firstMatch(lower);
        if (m != null && m.groupCount >= 1) {
          candidate = m.group(1);
          break;
        }
      }

      // fallback: Einzelwort nach "heiße/Name ist"
      candidate ??= () {
        final m = RegExp(r"\b(hei(?:ß|ss|s)e|name\s+ist)\b\s+([a-zäöüß\-\' ]+)")
            .firstMatch(lower);
        return (m != null && m.groupCount >= 2) ? m.group(2) : null;
      }();

      if (candidate == null) return;

      // auf erstes Token reduzieren (z. B. "matthias k." → "matthias")
      final firstToken = candidate.split(RegExp(r"\s+")).first;

      // säubern & in Title-Case (Apostroph bleibt erlaubt)
      String clean = firstToken.replaceAll(RegExp(r"[^a-zA-ZäöüÄÖÜß\-' ]"), '');
      clean = clean.replaceAll(' ', '');
      if (clean.length < 2) return;
      clean = clean[0].toUpperCase() + clean.substring(1);

      // Ausschlüsse
      const banned = {'einfach','ja','okay','ok','nein'};
      if (banned.contains(clean.toLowerCase())) return;

      await saveIdentityName(clean, greetByName: greetByName);
    } catch (_) {/* ignore */}
  }

  // ---------------- Write: Konversation & Worker-Save ------------------------

  /// Speichert tolerant aus einer Worker-Response (no-op, wenn disabled).
  /// [source] optional (Telemetrie).
  Future<void> saveFromWorker(dynamic workerResponse, {String? source}) async {
    if (!_enabled) return;
    try {
      if (workerResponse is! Map) return;
      final map = Map<String, dynamic>.from(workerResponse);

      final entry = MemoryMapper.fromWorker(map); // nullable
      if (entry == null) return;

      await _store.save(entry);

      // leichten Sync-Hint aktualisieren
      if (entry.contextFacets.isNotEmpty) {
        final sorted = [...entry.contextFacets]..sort((a, b) {
          final byHits = (b.hits).compareTo(a.hits);
          if (byHits != 0) return byHits;
          return (a.label).toLowerCase().compareTo((b.label).toLowerCase());
        });

        final facetKeys   = sorted.map((f) => f.key).where((s) => s.trim().isNotEmpty).toList();
        final facetLabels = sorted.map((f) => f.label).where((s) => s.trim().isNotEmpty).toList();

        _lastHint = MemoryContextHint(
          facets: facetKeys.take(6).toList(growable: false),
          tags: null,
          topics: facetLabels.take(6).toList(growable: false),
        );
        _lastHintTs = DateTime.now();
      }

      _invalidateSoftCaches();
    } catch (_) {
      // still
    }
  }

  /// Konversationszeile des Nutzers lokal protokollieren (best-effort).
  Future<void> saveUserTurn(String text, {Map<String, dynamic>? meta}) async {
    await _saveLine('user', text, meta: meta);
  }

  /// Konversationszeile des Panda lokal protokollieren (best-effort).
  Future<void> savePandaTurn(String text, {Map<String, dynamic>? meta}) async {
    await _saveLine('panda', text, meta: meta);
  }

  /// Acknowledge-Ereignis bei Einsicht & Themen-Overlap registrieren (best-effort).
  /// Erwartet z. B. {round_id, session_id, insight_score, ts, facet_keys:[]}
  Future<void> recordAcknowledge(Map<String, dynamic> ack) async {
    if (!_enabled) return;
    try {
      final safeAck = Map<String, dynamic>.from(ack);
      final dyn = _store as dynamic;

      // 1) Spezifische Store-Methode
      try {
        final r = dyn.recordAcknowledge(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}

      // 2) Alternative Namensvarianten
      try {
        final r = dyn.saveAck?.call(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}

      // 3) Fallback: generische Map-Speicherung mit kind:'ack'
      safeAck.putIfAbsent('kind', () => 'ack');
      safeAck.putIfAbsent('ts', () => DateTime.now().toUtc().toIso8601String());
      try {
        final r = dyn.saveMap?.call(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = dyn.save?.call(safeAck);
        if (r is Future) await r;
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  /// Zentrale, compile-sichere Line-Save-Kaskade ohne statische MemoryEntry-Factories.
  Future<void> _saveLine(String role, String text, {Map<String, dynamic>? meta}) async {
    if (!_enabled) return;
    try {
      final m = meta ?? const <String, dynamic>{};
      final dyn = _store as dynamic;

      // 1) Spezifische Methoden (falls vorhanden)
      try {
        if (role == 'user') {
          final r = dyn.saveUserLine(text, m);
          if (r is Future) await r;
          return;
        } else {
          final r = dyn.savePandaLine(text, m);
          if (r is Future) await r;
          return;
        }
      } catch (_) {/* try next */}

      // 2) Generische Append/SaveLine-Varianten
      try {
        final r = dyn.appendLine(role, text, m);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = dyn.saveLine(role: role, text: text, meta: m);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}

      // 3) Map-Fallback (einige Stores akzeptieren Map-Objekte)
      final map = {
        'kind': 'line',
        'role': role,
        'text': text,
        'meta': m,
        'ts': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        final r = dyn.saveMap(map);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = dyn.save(map);
        if (r is Future) await r;
        return;
      } catch (_) {/* swallow */}
    } catch (_) {/* ignore */}
  }

  Future<void> clear() async {
    _lastHint = null;
    _lastHintTs = null;
    _latestTopicsCache = null;
    _latestTopicsTs = null;
    _topFacetsCache = null;
    _topFacetsTs = null;
    try { await _store.clearAll(); } catch (_) {/* ignore */}
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
      if (_topFacetsCache != null &&
          _topFacetsTs != null &&
          DateTime.now().difference(_topFacetsTs!).inSeconds <= _facetsTtlSec) {
        return _topFacetsCache!.take(limit).toList(growable: false);
      }

      final all = await _store.all();
      if (all.isEmpty) return const <Facet>[];
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
          final aIdx = all.indexWhere((e) => e.contextFacets.any((f) => f.key == a));
          final bIdx = all.indexWhere((e) => e.contextFacets.any((f) => f.key == b));
          return aIdx.compareTo(bIdx);
        });

      final result = keys.take(limit).map((k) =>
          Facet(key: k, label: labels[k] ?? k, hits: counts[k] ?? 1)).toList(growable: false);

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

  /// Liefert kompakte Recall-Liste (Labels) für UI-Brücken.
  /// Hinweis: UI soll aktuell **keine** „Letzten Themen“-Chips anzeigen; diese API
  /// dient nur internen Bridges/Experimenten.
  Future<List<dynamic>> recall({int limit = 6, String? topicHint}) async {
    try {
      final int takeN = (limit * 2).clamp(6, 24).toInt();
      final rawTopics = await latestTopics(limit: takeN);
      final seen = <String>{};
      final ranked = <String>[];

      final hint = (topicHint ?? '').trim().toLowerCase();
      final tmp = [...rawTopics];

      if (hint.isNotEmpty) {
        int score(String s) {
          final t = s.toLowerCase();
          if (t.startsWith(hint)) return 2;
          if (t.contains(hint)) return 1;
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
        return List<dynamic>.from(ranked);
      }

      final facets = await topFacets(limit: limit);
      final viaFacets = facets
          .map((f) => f.label.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);

      return List<dynamic>.from(viaFacets);
    } catch (_) {
      return const <dynamic>[];
    }
  }

  // ---------------- Sync-Hints & Memories für ApiService ---------------------

  /// **Synchroner** Hint für den Worker (klein, aus Cache).
  MemoryContextHint? buildContextHint({
    int maxFacets = 3,
    int maxTags = 5,
    int maxAgeDays = _hintTtlDays,
  }) {
    try {
      if (!_enabled) return null;
      final hint = _lastHint;
      if (hint == null) return null;

      if (_lastHintTs != null && maxAgeDays > 0) {
        final ageDays = DateTime.now().difference(_lastHintTs!).inDays;
        if (ageDays > maxAgeDays) return null;
      }

      final facets = (hint.facets == null)
          ? null
          : hint.facets!.take(maxFacets).toList(growable: false);
      final tags = (hint.tags == null)
          ? null
          : hint.tags!.take(maxTags).toList(growable: false);
      final topics = (hint.topics == null)
          ? null
          : hint.topics!.take(5).toList(growable: false);

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

  /// **Memories-Block** für ApiService (nur bei Consent verwenden!).
  Future<Map<String, dynamic>> buildContextMemories({required bool consent}) async {
    try {
      if (!_enabled || !consent) return const <String, dynamic>{};

      final out = <String, dynamic>{};

      final id = await loadGreetingName();
      if (id.greetByName && id.name != null && id.name!.isNotEmpty) {
        out['identity'] = <String, dynamic>{'name': id.name};
      }

      final hint = buildContextHint();
      if (hint != null) {
        out['hint'] = hint.toJson();
      }

      if (_shareEnabled) {
        out['share'] = true;
      }

      return out;
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  // ---------------- Byte-Kontext (sync, klein) ------------------------------

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

  List<int>? exportByteContext([int maxBytes = 2048]) => tryGetByteContext(maxBytes);
  List<int>? byteContext([int maxBytes = 2048]) => tryGetByteContext(maxBytes);

  // ---------------- interne Helfer ------------------------------------------

  void _invalidateSoftCaches() {
    _latestTopicsCache = null;
    _latestTopicsTs = null;
    _topFacetsCache = null;
    _topFacetsTs = null;
  }

  bool? _tryReadShareEnabledReflective() {
    try {
      final dyn = _store as dynamic;
      final v = dyn.isShareEnabled;
      if (v is bool) return v;
    } catch (_) {/* ignore */}
    try {
      final dyn = _store as dynamic;
      final res = dyn.getShareEnabled();
      if (res is bool) return res;
    } catch (_) {/* ignore */}
    return null;
  }

  Future<void> _setOptString(String key, String value) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOptString(key, value);
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOpt(key, value);
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setKey(key, value);
      if (r is Future) await r;
    } catch (_) {/* ignore */}
  }

  Future<String?> _getOptString(String key) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.getOptString(key);
      if (r is String) return r;
      if (r is Future) {
        final v = await r;
        if (v is String) return v;
      }
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.getOpt(key);
      if (r is String) return r;
      if (r is Future) {
        final v = await r;
        if (v is String) return v;
      }
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.getKey(key);
      if (r is String) return r;
      if (r is Future) {
        final v = await r;
        if (v is String) return v;
      }
    } catch (_) {/* ignore */}
    return null;
  }

  Future<void> _setOptBool(String key, bool value) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOptBool(key, value);
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOpt(key, value);
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setFlag(key, value);
      if (r is Future) await r;
    } catch (_) {/* ignore */}
  }

  Future<bool?> _getOptBool(String key) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.getOptBool(key);
      if (r is bool) return r;
      if (r is Future) {
        final v = await r;
        if (v is bool) return v;
      }
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.getOpt(key);
      if (r is bool) return r;
      if (r is Future) {
        final v = await r;
        if (v is bool) return v;
      }
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.getFlag(key);
      if (r is bool) return r;
      if (r is Future) {
        final v = await r;
        if (v is bool) return v;
      }
    } catch (_) {/* ignore */}
    return null;
  }
}

// ---------------- kleine Extension-Helfer ------------------------------------

extension _ListX<T> on List<T>? {
  bool get isNotEmpty => (this != null && this!.isNotEmpty);
}
