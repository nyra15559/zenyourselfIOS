// lib/services/persistence_adapter.dart
//
// PersistenceAdapter — Oxford–Zen v7 (web-safe, no LocalStorageService dependency)
// ------------------------------------------------------------------------------
// • LocalStoragePersistenceAdapter (Web & IO)  → SharedPreferences-Backend
// • File-Adapter via conditional import (nur IO) → filePersistenceAdapterFromPath()
// • Functions-/Memory-Adapter
// • Öffentlicher Serializer: PersistenceSerializer (separate Datei)
// • ⚠️ Journey-Kompat: static kGhostMode + static instance (KVStore)

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/journal_entry.dart' as jm;
import '../providers/journal_entries_provider.dart';
import 'persistence_serializer.dart';
import 'persistence_file_stub.dart'
    if (dart.library.io) 'persistence_file_io.dart' as file_impl;

/// Speicher-Schlüssel (Namespace)
class _Keys {
  static const entries = 'persist::journal_entries.v1';
  static String ns(String key) => 'persist::$key';
}

/// Abstrakte Basis + Journey-Kompat-Hooks
abstract class PersistenceAdapter {
  const PersistenceAdapter();

  Future<List<jm.JournalEntry>> load();
  Future<void> save(List<jm.JournalEntry> entries);

  /// ⚙️ Kompat: Journey erwartet diese Konstante
  static const String kGhostMode = 'settings:ghost_mode';

  /// ⚙️ Kompat: Journey erwartet eine .instance mit KV-Methoden
  static final KVStore instance = KVStore();
}

/// Schlanker Key-Value-Wrapper (SharedPreferences-basiert)
class KVStore {
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    // SharedPreferences initialisiert sich lazy; wir halten nur die Semantik ein.
    _inited = true;
  }

  Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Keys.ns(key), value);
  }

  Future<bool?> getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_Keys.ns(key));
  }

  Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Keys.ns(key), value);
  }

  Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_Keys.ns(key));
  }

  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_Keys.ns(key));
  }
}

/// ---------------- LocalStorage (Web & IO via SharedPreferences) ----------------
/// Speichert die komplette Journal-Liste als JSON unter einem Namespaced-Key.
/// Serializer: `PersistenceSerializer` (encode/decode)
class LocalStoragePersistenceAdapter extends PersistenceAdapter {
  final bool pretty;

  const LocalStoragePersistenceAdapter({this.pretty = true});

  @override
  Future<List<jm.JournalEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_Keys.entries);
    // Tolerant decodieren: null/invalid → leere Liste
    return PersistenceSerializer.decode(jsonStr);
  }

  @override
  Future<void> save(List<jm.JournalEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = PersistenceSerializer.encode(entries, pretty: pretty);
    await prefs.setString(_Keys.entries, jsonStr);
  }
}

/// ---------------- Functions (frei definierbar) ----------------
class FunctionsPersistenceAdapter extends PersistenceAdapter {
  final Future<String?> Function() read;
  final Future<void> Function(String json) write;
  final bool pretty;

  const FunctionsPersistenceAdapter({
    required this.read,
    required this.write,
    this.pretty = true,
  });

  @override
  Future<List<jm.JournalEntry>> load() async {
    try {
      final s = await read();
      return PersistenceSerializer.decode(s);
    } catch (_) {
      return const <jm.JournalEntry>[];
    }
  }

  @override
  Future<void> save(List<jm.JournalEntry> entries) async {
    try {
      final jsonStr = PersistenceSerializer.encode(entries, pretty: pretty);
      await write(jsonStr);
    } catch (_) {
      // best effort
    }
  }
}

/// ---------------- Memory (Tests/Seed) ----------------
class MemoryPersistenceAdapter extends PersistenceAdapter {
  List<jm.JournalEntry> _entries;
  MemoryPersistenceAdapter([Iterable<jm.JournalEntry>? seed])
      : _entries =
            List<jm.JournalEntry>.from(seed ?? const <jm.JournalEntry>[]);

  @override
  Future<List<jm.JournalEntry>> load() async =>
      List<jm.JournalEntry>.from(_entries)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> save(List<jm.JournalEntry> entries) async {
    _entries = List<jm.JournalEntry>.from(entries);
  }
}

/// ---------------- File (nur IO-Targets) ----------------
/// Achtung: Auf Web nicht verfügbar – dort bitte LocalStorage/Functions verwenden.
PersistenceAdapter filePersistenceAdapterFromPath(
  String path, {
  bool pretty = true,
}) =>
    file_impl.createFileAdapter(path, pretty: pretty);

/// ---------------- Provider-Convenience ----------------
extension JournalEntriesPersistenceX on JournalEntriesProvider {
  Future<void> attach(PersistenceAdapter adapter, {bool loadNow = true}) {
    return attachPersistence(
      load: () => adapter.load(),
      save: (entries) => adapter.save(entries),
      loadNow: loadNow,
    );
  }
}
