// lib/core/memory/memory_store.dart
//
// MemoryStore v2.3 — SharedPreferences-Persistenz für MemoryEntry.
// -----------------------------------------------------------------------------
// Eigenschaften:
// • Key-Kompatibilität zu v1: 'memory.entries.json'
// • Defensive Reader: akzeptiert List oder {entries:[...]}; ignoriert Müll sicher
// • Speichert NUR snake_case-Maps (v2 Standard); stabiler FIFO-Prune
// • Async-API, keine UI-Blocks; sanfte Deduplizierung via (sessionId|createdAt)
// • Kleine Helfer: latest(), facetHistogram(), topFacets()
// • Zusatz-Flags: share_enabled (best-effort; kompatibel zu MemoryService)
//
// Hinweise:
// • isEnabled default = true (Ghost-/Therapist-Modus steuert separat, falls vorhanden)
// • facetHistogram berücksichtigt Facet.hits (falls 0/fehlend → 1)

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'memory_entry.dart';

class MemoryStore {
  MemoryStore._();
  static final MemoryStore instance = MemoryStore._();

  static const String _kEnabled = 'memory.enabled';
  static const String _kShareEnabled = 'memory.share_enabled'; // optional
  static const String _kEntries = 'memory.entries.json';       // v1 Kompat-Key
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

  /// Generische Option (Fallback, lässt verschiedene Typen zu).
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

    // Sanftes Dedupe: Schlüssel = sessionId|createdAt(ISO-UTC)
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
