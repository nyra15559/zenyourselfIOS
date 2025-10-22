// lib/services/persistence_adapter.dart
//
// PersistenceAdapter — Oxford–Zen v7.2
// -----------------------------------------------------------------------------
// Ziele dieses Reworks
// • Einheitliches Interface mit LocalStorageService (austauschbar; Default: SharedPreferences)
// • File-Adapter via conditional import (nur IO) → createFileAdapter()
// • Web/Desktop Stub mit identischer Signatur (kein Plattform-Leak)
// • Sanfte Guards: niemals Exceptions „nach oben“
// • Gemeinsamer Namespace/Keying für KVs
//
// Hinweise
// • Der File-Adapter speichert das gleiche JSON-Format wie LocalStorage.
// • Empfohlenes Dateiname-Pattern (wenn ihr selbst Pfade wählt):
//     "journal_entries.v1.json"
//
// Abhängigkeiten: shared_preferences

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

/// ==============================
/// LocalStorageService (austauschbar)
/// ==============================

/// Abstraktes Backend – kann bei Bedarf extern ersetzt werden (z. B. eigene Storage-Implementierung).
abstract class LocalStorageBackend {
  Future<void> setBool(String key, bool value);
  Future<bool?> getBool(String key);

  Future<void> setString(String key, String value);
  Future<String?> getString(String key);

  Future<void> remove(String key);
}

/// Default-Backend: SharedPreferences
class _PrefsBackend implements LocalStorageBackend {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<void> setBool(String key, bool value) async {
    try {
      final p = await _prefs;
      await p.setBool(_Keys.ns(key), value);
    } catch (_) {}
  }

  @override
  Future<bool?> getBool(String key) async {
    try {
      final p = await _prefs;
      return p.getBool(_Keys.ns(key));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setString(String key, String value) async {
    try {
      final p = await _prefs;
      await p.setString(_Keys.ns(key), value);
    } catch (_) {}
  }

  @override
  Future<String?> getString(String key) async {
    try {
      final p = await _prefs;
      return p.getString(_Keys.ns(key));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      final p = await _prefs;
      await p.remove(_Keys.ns(key));
    } catch (_) {}
  }
}

/// Service-Fassade: nutzt ein Backend (Default: SharedPreferences)
class LocalStorageService {
  LocalStorageService._();
  static LocalStorageBackend _backend = _PrefsBackend();

  /// Backend ersetzen (z. B. für Tests/Mocks)
  static void use(LocalStorageBackend backend) {
    _backend = backend;
  }

  static Future<void> setBool(String key, bool value) =>
      _backend.setBool(key, value);
  static Future<bool?> getBool(String key) =>
      _backend.getBool(key);

  static Future<void> setString(String key, String value) =>
      _backend.setString(key, value);
  static Future<String?> getString(String key) =>
      _backend.getString(key);

  static Future<void> remove(String key) => _backend.remove(key);
}

/// ==============================
/// Adapter-Basis + Journey-Kompat-Hooks
/// ==============================
abstract class PersistenceAdapter {
  const PersistenceAdapter();

  Future<List<jm.JournalEntry>> load();
  Future<void> save(List<jm.JournalEntry> entries);

  /// ⚙️ Journey-Kompat: erwarteter Settings-Key
  static const String kGhostMode = 'settings:ghost_mode';

  /// ⚙️ Journey-Kompat: erwartete .instance mit KV-Methoden
  static final KVStore instance = KVStore();
}

/// Schlanker Key-Value-Wrapper auf LocalStorageService
class KVStore {
  bool _inited = false;

  Future<void> init() async {
    // SharedPreferences initialisiert sich lazy; hier nur Semantik wahren.
    if (_inited) return;
    _inited = true;
  }

  Future<void> setBool(String key, bool value) =>
      LocalStorageService.setBool(key, value);

  Future<bool?> getBool(String key) =>
      LocalStorageService.getBool(key);

  Future<void> setString(String key, String value) =>
      LocalStorageService.setString(key, value);

  Future<String?> getString(String key) =>
      LocalStorageService.getString(key);

  Future<void> remove(String key) =>
      LocalStorageService.remove(key);
}

/// ==============================
/// LocalStorage (Web & IO über SharedPreferences)
/// ==============================
/// Speichert die komplette Journal-Liste als JSON unter `_Keys.entries`.
class LocalStoragePersistenceAdapter extends PersistenceAdapter {
  final bool pretty;

  const LocalStoragePersistenceAdapter({this.pretty = true});

  @override
  Future<List<jm.JournalEntry>> load() async {
    try {
      final jsonStr = await LocalStorageService.getString(_Keys.entries);
      return PersistenceSerializer.decode(jsonStr);
    } catch (_) {
      return const <jm.JournalEntry>[];
    }
  }

  @override
  Future<void> save(List<jm.JournalEntry> entries) async {
    try {
      final jsonStr = PersistenceSerializer.encode(entries, pretty: pretty);
      await LocalStorageService.setString(_Keys.entries, jsonStr);
    } catch (_) {
      // best effort – keine Exceptions nach oben
    }
  }
}

/// ==============================
/// Functions-Adapter (frei definierbar; z. B. SecureStorage, Cloud, …)
/// ==============================
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

/// ==============================
/// Memory-Adapter (Tests/Seeds/In-Memory)
/// ==============================
class MemoryPersistenceAdapter extends PersistenceAdapter {
  List<jm.JournalEntry> _entries;
  MemoryPersistenceAdapter([Iterable<jm.JournalEntry>? seed])
      : _entries = List<jm.JournalEntry>.from(seed ?? const <jm.JournalEntry>[]);

  @override
  Future<List<jm.JournalEntry>> load() async =>
      List<jm.JournalEntry>.from(_entries)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> save(List<jm.JournalEntry> entries) async {
    _entries = List<jm.JournalEntry>.from(entries);
  }
}

/// ==============================
/// File-Adapter (nur IO-Targets)
/// ==============================
/// Achtung: Auf Web nicht verfügbar – dort LocalStorage/Functions verwenden.
PersistenceAdapter createFileAdapter(
  String path, {
  bool pretty = true,
}) =>
    file_impl.createFileAdapter(path, pretty: pretty);

/// Provider-Convenience
extension JournalEntriesPersistenceX on JournalEntriesProvider {
  Future<void> attach(PersistenceAdapter adapter, {bool loadNow = true}) {
    return attachPersistence(
      load: () => adapter.load(),
      save: (entries) => adapter.save(entries),
      loadNow: loadNow,
    );
  }
}
