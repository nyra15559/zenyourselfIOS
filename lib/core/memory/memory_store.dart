// lib/core/memory/memory_store.dart
//
// MemoryStore — SharedPreferences-basierte Persistenz für MemoryEntry
// -------------------------------------------------------------------
// • Kompatibel zu v1-Key: 'memory.entries.json'
// • Tolerantes Einlesen (v1/v2 Strukturen), normalisiert via MemoryEntry.fromMap
// • Speichern als Liste aus Maps (v2), sanftes Dedupe + FIFO-Pruning
// • Kleine Helfer: latest(), facetHistogram(), topFacets()
// • Niemals UI-blockierend: alle APIs async, Fehler still gefangen

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'memory_entry.dart';

class MemoryStore {
  MemoryStore._();
  static final MemoryStore instance = MemoryStore._();

  static const _kEnabled = 'memory.enabled';
  static const _kEntries = 'memory.entries.json'; // Kompat-Key (v1)
  static const _kMax = 200;

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // default: enabled = true
    if (!_prefs!.containsKey(_kEnabled)) {
      await _prefs!.setBool(_kEnabled, true);
    }
  }

  bool get isEnabled => _prefs?.getBool(_kEnabled) ?? true;

  Future<void> setEnabled(bool enabled) async {
    await init();
    await _prefs!.setBool(_kEnabled, enabled);
  }

  Future<void> clearAll() async {
    await init();
    await _prefs!.remove(_kEntries);
  }

  Future<List<MemoryEntry>> all() async {
    await init();
    final raw = _prefs!.getString(_kEntries);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);

      // v1/v2: Primär erwarten wir eine Liste; fallback: { entries: [...] }
      final List<dynamic> list = decoded is List
          ? decoded
          : (decoded is Map && decoded['entries'] is List)
              ? List<dynamic>.from(decoded['entries'] as List)
              : const [];

      final out = <MemoryEntry>[];
      for (final e in list) {
        if (e is Map) {
          // tolerant: Map<dynamic, dynamic> → Map<String, dynamic>
          out.add(MemoryEntry.fromMap(Map<String, dynamic>.from(e)));
        }
      }

      // Sortierung: neueste zuerst
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (_) {
      // korruptes JSON → leer zurückgeben (kein Bruch in der App)
      return const [];
    }
  }

  Future<List<MemoryEntry>> latest({int limit = 3}) async {
    final list = await all();
    return list.take(limit).toList(growable: false);
  }

  Future<void> save(MemoryEntry entry) async {
    await init();
    if (!isEnabled) return;

    final existing = await all();
    final updated = <MemoryEntry>[entry, ...existing];

    // Sanftes Dedupe: (sessionId|createdAt) als Schlüssel
    final seen = <String>{};
    final deduped = <MemoryEntry>[];
    for (final e in updated) {
      final key = '${e.sessionId}|${e.createdAt.toUtc().toIso8601String()}';
      if (seen.add(key)) deduped.add(e);
    }

    // FIFO-Pruning
    final pruned = deduped.take(_kMax).toList(growable: false);

    // Persistieren (v2): Liste aus Maps
    final jsonList = pruned.map((e) => e.toMap()).toList(growable: false);
    await _prefs!.setString(_kEntries, jsonEncode(jsonList));
  }

  /// Histogramm (Label → Häufigkeit) über die letzten [take] Einträge.
  Future<Map<String, int>> facetHistogram({int take = 60}) async {
    final list = await all();
    final slice = list.take(take);
    final Map<String, int> hist = {};
    for (final e in slice) {
      for (final f in e.contextFacets) {
        final k = f.label.trim();
        if (k.isEmpty) continue;
        hist[k] = (hist[k] ?? 0) + 1;
      }
    }
    return hist;
  }

  /// Top-Facettenlabels (nur Text), nach Häufigkeit sortiert.
  Future<List<String>> topFacets({int take = 3}) async {
    final hist = await facetHistogram();
    final sorted = hist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(take).map((e) => e.key).toList(growable: false);
  }
}
