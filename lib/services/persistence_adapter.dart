// lib/services/persistence_adapter.dart
//
// PersistenceAdapter — Oxford–Zen v6.1 (web-safe, KV-Wrapper kompatibel)
// --------------------------------------------------------------------
// • LocalStoragePersistenceAdapter (Web & IO)
// • File-Adapter via conditional import (nur IO) – Fabrik: filePersistenceAdapterFromPath()
// • Functions-/Memory-Adapter
// • Öffentlicher Serializer: PersistenceSerializer (separate Datei)
// • ⚠️ Kompatibilität für Journey: static kGhostMode + static instance (KVStore)

import '../models/journal_entry.dart' as jm;
import '../models/journal_entries_provider.dart';
import 'local_storage.dart';
import 'persistence_serializer.dart';
import 'persistence_file_stub.dart'
  if (dart.library.io) 'persistence_file_io.dart' as file_impl;

/// Abstrakte Basis + statische Kompatibilitäts-Hooks für Journey
abstract class PersistenceAdapter {
  const PersistenceAdapter();

  Future<List<jm.JournalEntry>> load();
  Future<void> save(List<jm.JournalEntry> entries);

  /// ⚙️ Kompat: Journey erwartet diese Konstante
  static const String kGhostMode = 'settings:ghost_mode';

  /// ⚙️ Kompat: Journey erwartet eine .instance mit KV-Methoden
  static final KVStore instance = KVStore();
}

/// Schlanker Key-Value-Wrapper mit den erwarteten Methoden
class KVStore {
  final LocalStorageService _ls = LocalStorageService();

  Future<void> init() => _ls.init();

  // LocalStorageService v2 hat keine setBool/getBool-Shortcuts mehr.
  // Wir nutzen saveJson/loadJson, die JSON-sicher und namespaced sind.
  Future<void> setBool(String key, bool value) async {
    await _ls.saveJson(key, value);
  }

  Future<bool?> getBool(String key) async {
    return _ls.loadJson<bool>(key, null);
  }

  Future<void> setString(String key, String value) async {
    await _ls.setString(key, value);
  }

  Future<String?> getString(String key) => _ls.getString(key);

  Future<void> remove(String key) async {
    await _ls.remove(key);
  }
}

/// ---------------- LocalStorage (Web & IO) ----------------
class LocalStoragePersistenceAdapter extends PersistenceAdapter {
  final LocalStorageService _store;

  LocalStoragePersistenceAdapter([LocalStorageService? store])
      : _store = store ?? LocalStorageService();

  @override
  Future<List<jm.JournalEntry>> load() async {
    await _store.init();
    // KANONISCHES Modell laden (models/journal_entry.dart)
    return _store.loadJournalEntries<jm.JournalEntry>(jm.JournalEntry.fromMap);
  }

  @override
  Future<void> save(List<jm.JournalEntry> entries) async {
    await _store.init();
    // LocalStorageService erwartet hier keine Typargumente
    await _store.saveJournalEntries(entries);
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
    } catch (_) {/* best effort */}
  }
}

/// ---------------- Memory (Tests/Seed) ----------------
class MemoryPersistenceAdapter extends PersistenceAdapter {
  List<jm.JournalEntry> _entries;
  MemoryPersistenceAdapter([Iterable<jm.JournalEntry>? seed])
      : _entries = List<jm.JournalEntry>.from(seed ?? const <jm.JournalEntry>[]);

  @override
  Future<List<jm.JournalEntry>> load() async =>
      List<jm.JournalEntry>.from(_entries)..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> save(List<jm.JournalEntry> entries) async {
    _entries = List<jm.JournalEntry>.from(entries);
  }
}

/// ---------------- File (nur IO-Targets) ----------------
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
