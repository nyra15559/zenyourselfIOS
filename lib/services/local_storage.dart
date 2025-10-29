// lib/services/local_storage.dart
//
// LocalStorageService — Oxford-Zen v3.8 (Prefs + Secure, Namespace, JSON)
// ----------------------------------------------------------------------
// • Gemeinsamer Namespace: alle Keys werden mit "zen:" geprefixt
// • Settings-API: saveSetting/loadSetting/remove
// • Secure-API: saveSecure/loadSecure/removeSecure
// • Journal-API:
//     - saveJournalEntries(List<dynamic>)  → Backwards-Compat (roh oder Maps)
//     - saveJournalEntriesV6(List<JournalEntry>) → Wrapper (schema/version)
//     - loadJournalEntries<T>(fromMap)     → erkennt Wrapper ODER rohe Liste
// • Backup/Restore: exportNamespace/importNamespace/clearNamespace
// • Robust gegen fehlerhafte Daten (try/catch + defensive returns)
// • Neu 3.8: Wrapper-Erkennung mit Fallback, stabile Sortierung bei JournalEntry
//
// Lizenz: ZenYourself (v6zenyourself) — Oxford–Zen Style

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/journal_entry.dart' as jm;
import 'persistence_serializer.dart' as ps;

typedef FromMap<T> = T Function(Map<String, dynamic> json);

class LocalStorageService {
  static const String _ns = 'zen:'; // Namespace-Prefix
  static SharedPreferences? _prefs;
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  // ---------------------------- Lifecycle ------------------------------------

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> _ensurePrefs() async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ---------------------------- Helpers --------------------------------------

  String _nsKey(String key) => key.startsWith(_ns) ? key : '$_ns$key';

  // ---------------------------- Settings API ---------------------------------

  Future<bool> saveSetting<T>(String key, T value) async {
    final prefs = await _ensurePrefs();
    final k = _nsKey(key);

    if (value is bool) return prefs.setBool(k, value);
    if (value is int) return prefs.setInt(k, value);
    if (value is double) return prefs.setDouble(k, value);
    if (value is String) return prefs.setString(k, value);
    if (value is List<String>) return prefs.setStringList(k, value);

    // Fallback: als JSON-String speichern
    try {
      final s = jsonEncode(value);
      return prefs.setString(k, s);
    } catch (e) {
      debugPrint('[LocalStorage] saveSetting fallback JSON failed for $k: $e');
      return false;
    }
  }

  Future<T?> loadSetting<T>(String key) async {
    final prefs = await _ensurePrefs();
    final k = _nsKey(key);

    final obj = prefs.get(k);
    if (obj == null) return null;

    try {
      if (T == bool) return (obj is bool ? obj : null) as T?;
      if (T == int) return (obj is int ? obj : null) as T?;
      if (T == double) return (obj is double ? obj : null) as T?;
      if (T == String) return (obj is String ? obj : null) as T?;
      if (T == List<String>) return (obj is List<String> ? obj : null) as T?;

      // Falls jemand komplexe Typen über saveSetting (JSON) abgelegt hat:
      if (obj is String) {
        final decoded = jsonDecode(obj);
        return decoded as T?;
      }
    } catch (e) {
      debugPrint('[LocalStorage] loadSetting<$T> error for $k: $e');
    }
    return null;
  }

  Future<bool> remove(String key) async {
    final prefs = await _ensurePrefs();
    return prefs.remove(_nsKey(key));
  }

  // ---------------------------- Secure API -----------------------------------

  Future<void> saveSecure(String key, String value) async {
    await _secure.write(key: _nsKey(key), value: value);
  }

  Future<String?> loadSecure(String key) async {
    return _secure.read(key: _nsKey(key));
  }

  Future<void> removeSecure(String key) async {
    await _secure.delete(key: _nsKey(key));
  }

  // ---------------------------- Journal API ----------------------------------

  static const String _journalKey = 'journal:entries';

  /// Bevorzugt die V6-Wrapper-Speicherung, wenn alle Items JournalEntry sind.
  /// Andernfalls wird — aus Kompatibilitätsgründen — ein reines JSON-Array gespeichert.
  Future<bool> saveJournalEntries(List<dynamic> entries) async {
    final prefs = await _ensurePrefs();
    final k = _nsKey(_journalKey);

    try {
      if (entries.isEmpty) {
        return prefs.setString(k, '[]');
      }

      // Wenn alle Items JournalEntry sind → Wrapper via PersistenceSerializer
      final allAreEntries = entries.every((e) => e is jm.JournalEntry);
      if (allAreEntries) {
        final jsonStr =
            ps.PersistenceSerializer.encode(entries.cast<jm.JournalEntry>());
        return prefs.setString(k, jsonStr);
      }

      // Fallback: als Liste von Maps speichern (Backwards-Compat)
      final list = <Map<String, dynamic>>[];
      for (final e in entries) {
        if (e == null) continue;
        if (e is Map<String, dynamic>) {
          list.add(e);
        } else if (e is jm.JournalEntry) {
          list.add(e.toMap());
        } else {
          // dynamischer toMap()-Call
          try {
            final dynamic maybe = (e as dynamic);
            final map = maybe.toMap?.call();
            if (map is Map<String, dynamic>) {
              list.add(map);
            } else {
              // letzte Chance: toJson -> decode
              final js = maybe.toJson?.call();
              if (js is String) {
                final dec = jsonDecode(js);
                if (dec is Map<String, dynamic>) {
                  list.add(dec);
                }
              }
            }
          } catch (_) {
            // still und tolerant
          }
        }
      }
      final jsonStr = jsonEncode(list);
      return prefs.setString(k, jsonStr);
    } catch (e, st) {
      debugPrint('[LocalStorage] saveJournalEntries failed: $e\n$st');
      return false;
    }
  }

  /// Moderne, eindeutige API: speichert stets als V6-Wrapper.
  Future<bool> saveJournalEntriesV6(List<jm.JournalEntry> entries,
      {bool pretty = false}) async {
    final prefs = await _ensurePrefs();
    final k = _nsKey(_journalKey);
    try {
      final jsonStr = ps.PersistenceSerializer.encode(entries, pretty: pretty);
      return prefs.setString(k, jsonStr);
    } catch (e, st) {
      debugPrint('[LocalStorage] saveJournalEntriesV6 failed: $e\n$st');
      return false;
    }
  }

  /// Lädt JournalEntries und wandelt sie mit [fromMap] in T um.
  /// Erkennt automatisch Wrapper {journal:[...]} ODER rohe Listen.
  /// Sortiert stabil DESC (nur wenn T == JournalEntry).
  Future<List<T>> loadJournalEntries<T>(FromMap<T> fromMap) async {
    final prefs = await _ensurePrefs();
    final k = _nsKey(_journalKey);

    try {
      final jsonStr = prefs.getString(k);
      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return List<T>.empty(growable: false);
      }

      // 1) Versuch: volle V6-Deserialisierung
      try {
        final decodedEntries = ps.PersistenceSerializer.decode(jsonStr);
        if (decodedEntries.isNotEmpty) {
          if (T == jm.JournalEntry) {
            // Direkte Rückgabe (stabil sortiert)
            return decodedEntries as List<T>;
          }
          // Für andere Typen: via fromMap() mappen
          final mapped = decodedEntries
              .map((e) => fromMap(e.toMap()))
              .toList(growable: false);
          return mapped;
        }
      } catch (_) {
        // fällt auf Backwards-Compat-Zweig
      }

      // 2) Backwards-Compat: roh oder Wrapper manuell extrahieren
      final raw = jsonDecode(jsonStr);

      List listToMap;
      if (raw is List) {
        listToMap = raw;
      } else if (raw is Map) {
        // Wrapper oder exotischer Export
        if (raw['journal'] is List) {
          listToMap = raw['journal'] as List;
        } else {
          // erste Liste im Objekt nehmen (sehr alte Exporte)
          final firstList = raw.values
              .firstWhere((v) => v is List, orElse: () => const <dynamic>[]);
          listToMap = (firstList is List) ? firstList : const <dynamic>[];
        }
      } else {
        listToMap = const <dynamic>[];
      }

      final out = <T>[];
      for (final item in listToMap) {
        try {
          if (item is Map<String, dynamic>) {
            out.add(fromMap(item));
          } else if (item is Map) {
            out.add(fromMap(item.cast<String, dynamic>()));
          } else if (item is String) {
            final dec = jsonDecode(item);
            if (dec is Map<String, dynamic>) {
              out.add(fromMap(dec));
            } else if (dec is Map) {
              out.add(fromMap(dec.cast<String, dynamic>()));
            }
          }
        } catch (_) {
          // einzelnes Item tolerant überspringen
        }
      }

      // Falls JournalEntry: stabil sortieren (DESC createdAt, dann ID)
      if (T == jm.JournalEntry && out.isNotEmpty) {
        try {
          final entries = out.cast<jm.JournalEntry>().toList();
          entries.sort((a, b) {
            final c = b.createdAt.compareTo(a.createdAt);
            return c != 0 ? c : b.id.compareTo(a.id);
          });
          return entries as List<T>;
        } catch (_) {
          // falls Mapping nicht passt, Originalreihenfolge behalten
        }
      }

      return out;
    } catch (e, st) {
      debugPrint('[LocalStorage] loadJournalEntries failed: $e\n$st');
      return <T>[];
    }
  }

  // ---------------------------- Backup / Restore ------------------------------

  /// Exportiert alle SharedPreferences-Werte aus unserem Namespace.
  Future<Map<String, dynamic>> exportNamespace() async {
    final prefs = await _ensurePrefs();
    final out = <String, dynamic>{};
    for (final k in prefs.getKeys()) {
      if (!k.startsWith(_ns)) continue;
      final short = k.substring(_ns.length);
      final v = prefs.get(k);
      if (v is List<String> ||
          v is String ||
          v is bool ||
          v is int ||
          v is double) {
        out[short] = v;
      } else {
        // Unbekannt → als String (JSON?) ablegen
        try {
          out[short] = jsonEncode(v);
        } catch (_) {
          out[short] = v.toString();
        }
      }
    }
    return out;
  }

  /// Importiert Werte (überschreibt gleichnamige Keys).
  Future<void> importNamespace(Map<String, dynamic> data) async {
    final prefs = await _ensurePrefs();

    for (final entry in data.entries) {
      final k = _nsKey(entry.key);
      final v = entry.value;

      if (v is bool) {
        await prefs.setBool(k, v);
      } else if (v is int) {
        await prefs.setInt(k, v);
      } else if (v is double) {
        await prefs.setDouble(k, v);
      } else if (v is String) {
        await prefs.setString(k, v);
      } else if (v is List) {
        // Versuchen, List<String> zu speichern
        final asStr = v.whereType<String>().toList(growable: false);
        if (asStr.length == v.length) {
          await prefs.setStringList(k, asStr);
        } else {
          await prefs.setString(k, jsonEncode(v));
        }
      } else {
        await prefs.setString(k, jsonEncode(v));
      }
    }
  }

  /// Löscht alle Keys aus unserem Namespace in SharedPreferences.
  Future<void> clearNamespace() async {
    final prefs = await _ensurePrefs();
    final keys = prefs.getKeys().where((k) => k.startsWith(_ns)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
