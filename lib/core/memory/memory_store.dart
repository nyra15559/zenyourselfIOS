// [BASELINE] lib/core/memory/memory_store.dart — v6.3.1 (Stand: 29.10.2025)
// MemoryStore — SharedPreferences-Persistenz für MemoryEntry (lokal, Ghost-Mode)
// -----------------------------------------------------------------------------
// Eigenschaften:
// • Kompatibel zu v1-Key: 'memory.entries.json' (List) und v2: {entries:[...]}
// • Defensive Reader: akzeptiert List ODER Map; ignoriert kaputte Elemente
// • Speichert NUR snake_case-Maps (v2 Standard); stabiler FIFO-Prune (neueste → alt)
// • Async-API, keine UI-Blocks; sanftes Dedupe via (session_id | created_at)
// • Kleine Helfer: latest(), facetHistogram(), topFacets()
// • Zusatz-Flags: memory.enabled, memory.share_enabled (best-effort)
// • Reflektive Helfer-APIs für MemoryService (setOpt*/getOpt*/setKey/getKey/...)
// • Generische Save-Varianten: saveUserLine/savePandaLine/appendLine/saveLine/recordAcknowledge
//   sowie saveMap/save(dynamic) — kompatibel mit MemoryService-Dyn-Calls
//
// Hinweise:
// • isEnabled default = true (Ghost-/Therapist-Modus steuert MemoryService separat)
// • facetHistogram berücksichtigt Facet.hits (0/fehlend → 1)
// -----------------------------------------------------------------------------

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'memory_entry.dart';

class MemoryStore {
  MemoryStore._();
  static final MemoryStore instance = MemoryStore._();

  static const String _kEnabled = 'memory.enabled';
  static const String _kShareEnabled = 'memory.share_enabled'; // optional
  static const String _kEntries = 'memory.entries.json'; // v1/v2 Kompat-Key
  static const int _kMax = 200;

  SharedPreferences? _prefs;

  // ---------- Init / State ----------------------------------------------------

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (!_prefs!.containsKey(_kEnabled)) {
      await _prefs!.setBool(_kEnabled, true);
    }
    // share_enabled ist optional – nicht erzwingen
  }

  bool get isEnabled => _prefs?.getBool(_kEnabled) ?? true;

  Future<void> setEnabled(bool enabled) async {
    await init();
    await _prefs!.setBool(_kEnabled, enabled);
  }

  // ---- optionale Share-Flag-APIs (für MemoryService best-effort) ------------

  /// Best-effort Getter (nullable → nicht vorhanden).
  bool? get isShareEnabled {
    try {
      return _prefs?.getBool(_kShareEnabled);
    } catch (_) {
      return null;
    }
  }

  /// Expliziter Getter (non-null mit Default false).
  Future<bool> getShareEnabled() async {
    await init();
    return _prefs!.getBool(_kShareEnabled) ?? false;
  }

  /// Bevorzugte Methode für MemoryService.setShareEnabled().
  Future<void> setShareEnabled(bool enabled) async {
    await init();
    await _prefs!.setBool(_kShareEnabled, enabled);
  }

  /// Generischer Flag-Setter (Fallback für dynamische Aufrufe).
  Future<void> setFlag(String key, bool value) async {
    await init();
    await _prefs!.setBool(key, value);
  }

  /// Generischer Flag-Getter (Fallback für dynamische Aufrufe).
  Future<bool?> getFlag(String key) async {
    await init();
    return _prefs!.getBool(key);
  }

  // ---------- Generische Options/Key-APIs (dyn-kompatibel) -------------------

  Future<void> setOpt(String key, Object? value) async {
    await init();
    if (value is bool) {
      await _prefs!.setBool(key, value);
    } else if (value is int) {
      await _prefs!.setInt(key, value);
    } else if (value is double) {
      await _prefs!.setDouble(key, value);
    } else if (value is String) {
      await _prefs!.setString(key, value);
    } else if (value is List<String>) {
      await _prefs!.setStringList(key, value);
    } else {
      // Fallback: JSON-serialisieren
      try {
        await _prefs!.setString(key, jsonEncode(value));
      } catch (_) {
        // still – ignorieren
      }
    }
  }

  Future<void> setOptString(String key, String value) async {
    await init();
    await _prefs!.setString(key, value);
  }

  Future<void> setOptBool(String key, bool value) async {
    await init();
    await _prefs!.setBool(key, value);
  }

  /// Generischer Getter: Liefert rohe gespeicherte Werte (wenn möglich).
  Future<Object?> getOpt(String key) async {
    await init();
    if (!_prefs!.containsKey(key)) return null;
    // shared_prefs gibt typisiert zurück:
    final obj = _prefs!.get(key);
    if (obj == null) return null;
    // Falls String JSON enthält, Original zurückgeben (MemoryService parst selbst bei Bedarf)
    return obj;
  }

  Future<String?> getOptString(String key) async {
    await init();
    final v = _prefs!.getString(key);
    return v;
  }

  Future<bool?> getOptBool(String key) async {
    await init();
    if (!_prefs!.containsKey(key)) return null;
    return _prefs!.getBool(key);
  }

  /// „Key“-Alias (einige dyn-Caller erwarten diese Namen).
  Future<void> setKey(String key, String value) => setOptString(key, value);
  Future<String?> getKey(String key) => getOptString(key);

  /// Entfernt eine gespeicherte Option (best-effort).
  Future<void> removeOpt(String key) async {
    await init();
    await _prefs!.remove(key);
  }

  // ---------- CRUD ------------------------------------------------------------

  Future<void> clearAll() async {
    await init();
    await _prefs!.remove(_kEntries);
    // Flags bewusst NICHT löschen (enabled/share_enabled)
  }

  Future<List<MemoryEntry>> all() async {
    await init();
    final raw = _prefs!.getString(_kEntries);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);

      // v1/v2: Liste direkt ODER {entries: [...]}
      List<dynamic> list = const [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['entries'] is List) {
        list = List<dynamic>.from(decoded['entries'] as List);
      }

      final out = <MemoryEntry>[];
      for (final e in list) {
        if (e is Map) {
          try {
            out.add(MemoryEntry.fromMap(Map<String, dynamic>.from(e)));
          } catch (_) {
            // Kaputtes Element ignorieren
          }
        }
      }

      // Neueste zuerst
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (_) {
      // Korruptes JSON niemals crashen lassen
      return const [];
    }
  }

  Future<List<MemoryEntry>> latest({int limit = 3}) async {
    final list = await all();
    final capped = _cap(limit, 0, _kMax);
    // Iterable.take ist tolerant, falls capped > list.length
    return list.take(capped).toList(growable: false);
  }

  Future<void> save(MemoryEntry entry) async {
    await init();
    if (!isEnabled) return;

    // Bestehende laden (neueste zuerst)
    final existing = await all();

    // Neu vorne einfügen
    final updated = <MemoryEntry>[entry, ...existing];

    // Sanftes Dedupe: Schlüssel = session_id | created_at (ISO-UTC)
    final seen = <String>{};
    final deduped = <MemoryEntry>[];
    for (final e in updated) {
      final key = '${e.sessionId}|${e.createdAt.toUtc().toIso8601String()}';
      if (seen.add(key)) {
        deduped.add(e);
      }
    }

    // FIFO-Pruning (neueste zuerst → Begrenzung mit take)
    final pruned = deduped.take(_kMax).toList(growable: false);

    // Persistieren als v2-Liste (snake_case-Maps)
    try {
      final jsonList = pruned.map((e) => e.toMap()).toList(growable: false);
      await _prefs!.setString(_kEntries, jsonEncode(jsonList));
    } catch (_) {
      // still – auf Persistenzfehler nicht hart reagieren
    }
  }

  // ---------- Generische Save-/Bridge-APIs (für dyn-Calls) -------------------

  /// Fügt eine generische „Zeile“ ein (role: 'user'|'panda'), meta optional.
  Future<void> appendLine(
      String role, String text, Map<String, dynamic>? meta) async {
    // Map in MemoryEntry transformieren und speichern
    final m = <String, dynamic>{
      'kind': 'line',
      'role': role,
      'text': text,
      'meta': meta ?? const <String, dynamic>{},
      // Session aus meta, sonst 'local'
      'session_id': (meta?['session_id'] as String?) ?? 'local',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      // optionale leere Felder für Kompatibilität
      'context_facets': const <dynamic>[],
    };
    await saveMap(m);
  }

  Future<void> saveLine(
      {required String role,
      required String text,
      Map<String, dynamic>? meta}) {
    return appendLine(role, text, meta);
  }

  Future<void> saveUserLine(String text, Map<String, dynamic>? meta) {
    return appendLine('user', text, meta);
  }

  Future<void> savePandaLine(String text, Map<String, dynamic>? meta) {
    return appendLine('panda', text, meta);
  }

  /// Acknowledge-Ereignis speichern (z. B. für Insight-Bestärkung).
  Future<void> recordAcknowledge(Map<String, dynamic> ack) async {
    final safe = Map<String, dynamic>.from(ack);
    safe['kind'] = safe['kind'] ?? 'ack';
    safe['created_at'] = (safe['created_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();
    safe['session_id'] = (safe['session_id'] as String?) ??
        (safe['round_id'] as String?) ??
        'local';
    await saveMap(safe);
  }

  /// Universeller Map-Save: wandelt Map→MemoryEntry und speichert.
  Future<void> saveMap(Map<String, dynamic> map) async {
    try {
      final entry = MemoryEntry.fromMap(map);
      await save(entry);
    } catch (_) {
      // Falls Map nicht direkt parsebar ist, versuche defensive Normalisierung
      try {
        // Minimalfelder erzwingen
        final safe = <String, dynamic>{
          ...map,
          'created_at':
              map['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
          'session_id': map['session_id'] ?? 'local',
        };
        final entry = MemoryEntry.fromMap(safe);
        await save(entry);
      } catch (_) {
        // still – ignorieren
      }
    }
  }

  /// Dynamischer Universal-Save (akzeptiert Map oder MemoryEntry).
  Future<void> saveDynamic(dynamic value) async {
    if (value is MemoryEntry) {
      await save(value);
    } else if (value is Map) {
      await saveMap(Map<String, dynamic>.from(value));
    } else {
      // try JSON string?
      if (value is String) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) {
            await saveMap(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {/* ignore */}
      }
    }
  }

  // Alias für dyn-Caller
  Future<void> save_(dynamic value) => saveDynamic(value);
  Future<void> save$(dynamic value) => saveDynamic(value);
  Future<void> saveCall(dynamic value) => saveDynamic(value);
  Future<void> saveAny(dynamic value) => saveDynamic(value);
  Future<void> saveObject(dynamic value) => saveDynamic(value);

  // ---------- Auswertungen / kleine Helfer -----------------------------------

  /// Histogramm (Label → Häufigkeit) über die letzten [take] Einträge.
  /// Zählt Facet.hits mit (falls 0/fehlend → 1).
  Future<Map<String, int>> facetHistogram({int take = 60}) async {
    final list = await all();
    final slice = list.take(_cap(take, 0, _kMax));
    final Map<String, int> hist = {};
    for (final e in slice) {
      for (final f in e.contextFacets) {
        final k = f.label.trim();
        if (k.isEmpty) continue;
        final inc = (f.hits <= 0) ? 1 : f.hits;
        hist[k] = (hist[k] ?? 0) + inc;
      }
    }
    return hist;
  }

  /// Top-Facettenlabels (nur Text), nach Häufigkeit sortiert.
  Future<List<String>> topFacets({int take = 3}) async {
    final hist = await facetHistogram();
    final sorted = hist.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        // Stabilisierung: alphabetisch bei Gleichstand
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    final capped = _cap(take, 0, sorted.length);
    return sorted.take(capped).map((e) => e.key).toList(growable: false);
  }

  // ---------- Utils -----------------------------------------------------------

  int _cap(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
