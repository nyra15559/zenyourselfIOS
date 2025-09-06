// lib/repositories/reflection_repository.dart
//
// ReflectionRepository — Oxford Robust Edition (v5-ready)
// -------------------------------------------------------
// - Lokale Persistenz aller ReflectionEntry-Objekte via LocalStorageService
// - Stabil, null-safe, defensives JSON-Parsing
// - Beibehält bestehende API (loadAll/saveAll/add/upsert/removeById/clear)
// - Extras: getById, latestN, inRange, editById, export/import (Legacy JSON),
//           Dedupe & konsistente Sortierung (DESC)
// - NEU (v5-Bridge):
//     • toJournalEntries()                 → List<JournalEntry> (type:"reflection")
//     • exportJournalV5JsonString()        → JSON (v5 Union-Shape)
//     • importJournalV5JsonString(json)    → importiert nur type:"reflection"
//
// Hinweise
// - Speicher-Key bleibt 'reflections_v1' (keine Migration nötig).
// - Repository kümmert sich NICHT um UI/Provider-Logik (Fingerprint-Dedupe etc.),
//   sondern nur um stabile Persistenz & Parsing.

import 'dart:convert';
import '../data/reflection_entry.dart';
import '../data/journal_entry.dart';
import '../services/local_storage.dart';

class ReflectionRepository {
  static const String _storageKey = 'reflections_v1';

  final LocalStorageService storage;

  ReflectionRepository({required this.storage});

  // ===========================================================================
  // Core (Legacy-kompatibel)
  // ===========================================================================

  /// Lädt alle Einträge (leere Liste bei Erststart/Fehler).
  /// Sortierung: timestamp DESC (neueste zuerst).
  Future<List<ReflectionEntry>> loadAll() async {
    try {
      final raw = await storage.getString(_storageKey);
      if (raw == null || raw.isEmpty) return <ReflectionEntry>[];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ReflectionEntry>[];

      final list = <ReflectionEntry>[];
      for (final e in decoded) {
        if (e is Map) {
          try {
            list.add(ReflectionEntry.fromJson(e.cast<String, dynamic>()));
          } catch (_) {
            // defekter Eintrag → überspringen
          }
        }
      }
      _sortDesc(list);
      return list;
    } catch (_) {
      return <ReflectionEntry>[];
    }
  }

  /// Überschreibt vollständig die Liste (z. B. nach Add/Update/Remove).
  /// Gewährleistet Sortierung (DESC) und dedupliziert per id (letzter gewinnt).
  Future<void> saveAll(List<ReflectionEntry> items) async {
    final normalized = _dedupById(items);
    _sortDesc(normalized);
    final data = normalized.map((e) => e.toJson()).toList(growable: false);
    final jsonStr = const JsonEncoder().convert(data);
    await storage.setString(_storageKey, jsonStr);
  }

  /// Fügt einen Eintrag hinzu (und speichert).
  Future<List<ReflectionEntry>> add(ReflectionEntry entry) async {
    final items = await loadAll();
    items.add(entry);
    await saveAll(items);
    return items;
  }

  /// Upsert per ID (existiert → ersetzen, sonst hinzufügen).
  Future<List<ReflectionEntry>> upsert(ReflectionEntry entry) async {
    final items = await loadAll();
    final i = items.indexWhere((e) => e.id == entry.id);
    if (i == -1) {
      items.add(entry);
    } else {
      items[i] = entry;
    }
    await saveAll(items);
    return items;
  }

  /// Entfernt per ID (liefert neue Liste).
  Future<List<ReflectionEntry>> removeById(String id) async {
    final items = await loadAll();
    items.removeWhere((e) => e.id == id);
    await saveAll(items);
    return items;
  }

  /// Komplett löschen.
  Future<void> clear() => storage.remove(_storageKey);

  // ===========================================================================
  // Extras
  // ===========================================================================

  /// Hole Eintrag per ID (oder null).
  Future<ReflectionEntry?> getById(String id) async {
    final items = await loadAll();
    try {
      return items.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Neueste N Einträge (DESC). n<=0 → [].
  Future<List<ReflectionEntry>> latestN(int n) async {
    if (n <= 0) return const <ReflectionEntry>[];
    final items = await loadAll();
    // items ist bereits DESC
    return items.take(n).toList(growable: false);
  }

  /// Einträge im Bereich [start, end] (inklusive), DESC sortiert.
  Future<List<ReflectionEntry>> inRange(DateTime start, DateTime end) async {
    final s = start.isBefore(end) ? start : end;
    final e = end.isAfter(start) ? end : start;
    final items = await loadAll(); // bereits DESC
    final filtered = items.where((x) {
      final t = x.timestamp;
      final afterStart = t.isAtSameMomentAs(s) || t.isAfter(s);
      final beforeEnd = t.isAtSameMomentAs(e) || t.isBefore(e);
      return afterStart && beforeEnd;
    }).toList(growable: false);
    return filtered;
  }

  /// Funktionales Update per ID (mutate), speichert nur wenn gefunden.
  /// Liefert die neue gesamte Liste zurück.
  Future<List<ReflectionEntry>> editById(
    String id,
    ReflectionEntry Function(ReflectionEntry current) mutate,
  ) async {
    final items = await loadAll();
    final i = items.indexWhere((e) => e.id == id);
    if (i == -1) return items;
    items[i] = mutate(items[i]);
    await saveAll(items);
    return items;
  }

  /// Export als JSON-String (kompakt). `pretty: true` für eingerückt.
  Future<String> exportJsonString({bool pretty = false}) async {
    final items = await loadAll();
    final data = items.map((e) => e.toJson()).toList(growable: false);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  /// Import aus JSON-String. Ersetzt die komplette Liste.
  /// Ungültige Einträge werden übersprungen.
  Future<List<ReflectionEntry>> importJsonString(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) return await loadAll();

      final list = <ReflectionEntry>[];
      for (final e in decoded) {
        if (e is Map) {
          try {
            list.add(ReflectionEntry.fromJson(e.cast<String, dynamic>()));
          } catch (_) {
            // skip invalid
          }
        }
      }
      await saveAll(list);
      return await loadAll();
    } catch (_) {
      return await loadAll();
    }
  }

  // ===========================================================================
  // v5-Bridge: JournalEntry Integration
  // ===========================================================================

  /// Mappt ALLE gespeicherten ReflectionEntry → v5 JournalEntry (type:"reflection").
  Future<List<JournalEntry>> toJournalEntries() async {
    final reflections = await loadAll();
    final out = <JournalEntry>[];
    for (final r in reflections) {
      try {
        // ReflectionEntry.toJsonV5() liefert direkt v5-Union-Shape
        final v5 = r.toJsonV5();
        out.add(JournalEntry.fromJson(v5));
      } catch (_) {
        // überspringen, falls etwas nicht parsbar ist
      }
    }
    // JournalEntries selbst sortieren (DESC) nach ts
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Exportiert NUR Reflexionen als v5-JSON (Union-Shape).
  Future<String> exportJournalV5JsonString({bool pretty = false}) async {
    final reflections = await loadAll();
    final data = reflections.map((r) => r.toJsonV5()).toList(growable: false);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  /// Importiert v5-JSON (Union-Shape) und übernimmt NUR `type:"reflection"` Objekte.
  /// Andere Typen (note/story) werden ignoriert.
  Future<List<ReflectionEntry>> importJournalV5JsonString(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) return await loadAll();

      final list = <ReflectionEntry>[];
      for (final e in decoded) {
        if (e is Map) {
          final map = e.cast<String, dynamic>();
          final type = (map['type'] ?? '').toString().toLowerCase().trim();
          if (type == 'reflection' || type == 'reflexion') {
            try {
              // ReflectionEntry kann v5-Form (inkl. 'ts') parsen
              list.add(ReflectionEntry.fromJson(map));
            } catch (_) {
              // skip invalid reflection
            }
          }
        }
      }
      await saveAll(list);
      return await loadAll();
    } catch (_) {
      return await loadAll();
    }
  }

  // ===========================================================================
  // intern
  // ===========================================================================

  static void _sortDesc(List<ReflectionEntry> list) {
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Dedup nach id: letzter Eintrag mit derselben id gewinnt.
  static List<ReflectionEntry> _dedupById(List<ReflectionEntry> items) {
    final map = <String, ReflectionEntry>{};
    for (final e in items) {
      final key = e.id.toString();
      map[key] = e;
    }
    return map.values.toList(growable: true);
  }
}
