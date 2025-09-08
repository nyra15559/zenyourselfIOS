// lib/services/persistence_serializer.dart
//
// PersistenceSerializer — v6 (robust, tolerant, backwards-friendly)
// - Akzeptiert Wrapper {schema,version,count,journal:[...]} ODER rohe Liste
// - Items dürfen Map ODER JSON-String (Map) sein
// - Toleriert verschiedene Feldnamen (type/kind, createdAt/created_at/timestamp)
// - Sortiert stabil DESC nach createdAt
// - Zusätzliche Helfer: decodeList, decodeEntry, decodeJsonLines

import 'dart:convert';
import '../models/journal_entry.dart' as jm;

class PersistenceSerializer {
  static const String schema = 'zen.v6.persistence';
  static const int version = 1;

  /// Serialisiert Einträge in einen Wrapper (journal: [Maps]).
  static String encode(List<jm.JournalEntry> entries, {bool pretty = true}) {
    final payload = <String, dynamic>{
      'schema': schema,
      'version': version,
      'count': entries.length,
      'journal': entries.map((e) => e.toMap()).toList(growable: false),
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    };
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(payload)
        : jsonEncode(payload);
  }

  /// Deserialisiert Wrapper ODER rohe Liste.
  /// Elemente dürfen Map oder JSON-String (Map) sein.
  static List<jm.JournalEntry> decode(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) {
      return const <jm.JournalEntry>[];
    }

    dynamic data;
    try {
      data = jsonDecode(jsonStr);
    } catch (_) {
      return const <jm.JournalEntry>[];
    }

    final list = _extractList(data);
    final out = <jm.JournalEntry>[];

    for (final item in list) {
      final entry = decodeEntry(item);
      if (entry != null) out.add(entry);
    }

    // Stabil: DESC nach createdAt
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Deserialisiert eine Liste, die bereits als Dart-Objekt vorliegt.
  /// (z. B. für Teilimporte oder Tests.)
  static List<jm.JournalEntry> decodeList(List<dynamic> list) {
    final out = <jm.JournalEntry>[];
    for (final item in list) {
      final e = decodeEntry(item);
      if (e != null) out.add(e);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Robustes Item-Decoding:
  /// - akzeptiert Map ODER JSON-String(Map)
  /// - normalisiert Feldnamen (type/kind, createdAt/created_at/timestamp)
  static jm.JournalEntry? decodeEntry(dynamic item) {
    Map<String, dynamic>? map;

    try {
      if (item is Map) {
        map = Map<String, dynamic>.from(item);
      } else if (item is String) {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {
      map = null;
    }

    if (map == null) return null;

    // Feldnamen tolerant normalisieren
    _normalizeMapKeys(map);

    // createdAt sicherstellen: ISO oder (ms|s) Timestamp → ISO
    final createdAtIso = _normalizeCreatedAt(map['createdAt']);
    if (createdAtIso != null) {
      map['createdAt'] = createdAtIso;
    }

    try {
      return jm.JournalEntry.fromMap(map);
    } catch (_) {
      // einzelner Fehler killt nicht den ganzen Import
      return null;
    }
  }

  /// JSON-Lines (eine JSON-Struktur pro Zeile) → Liste
  static List<jm.JournalEntry> decodeJsonLines(String? lines) {
    if (lines == null || lines.trim().isEmpty) {
      return const <jm.JournalEntry>[];
    }
    final out = <jm.JournalEntry>[];
    for (final line in const LineSplitter().convert(lines)) {
      final e = decode(line);
      if (e.isNotEmpty) out.addAll(e);
    }
    return out..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // ---------------- intern ----------------

  static List _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final j = data['journal'];
      if (j is List) return j;

      // Fallback: erste List-Val in Map nehmen (sehr alt)
      final possible = data.values.firstWhere(
        (v) => v is List,
        orElse: () => const <dynamic>[],
      );
      if (possible is List) return possible;
    }
    return const <dynamic>[];
  }

  static void _normalizeMapKeys(Map<String, dynamic> m) {
    // kind/type → kind (neues Feld)
    if (!m.containsKey('kind') && m.containsKey('type')) {
      m['kind'] = m['type'];
    }

    // createdAt-Varianten
    if (!m.containsKey('createdAt')) {
      if (m.containsKey('created_at')) {
        m['createdAt'] = m['created_at'];
      } else if (m.containsKey('timestamp')) {
        m['createdAt'] = m['timestamp'];
      }
    }

    // id-Fallback
    if (!m.containsKey('id') && m.containsKey('_id')) {
      m['id'] = m['_id'];
    }
  }

  static String? _normalizeCreatedAt(dynamic v) {
    if (v == null) return null;

    // ISO-String unverändert (sofern parsebar)
    if (v is String) {
      try {
        final dt = DateTime.parse(v).toUtc();
        return dt.toIso8601String();
      } catch (_) {
        // weiter unten evtl. als Zahl interpretieren
      }
    }

    // Numerische Timestamps: ms oder s
    if (v is num) {
      final intVal = v.toInt();
      // Heuristik: >= 10^12 → ms, sonst s
      final isMillis = intVal.abs() >= 1000000000000;
      final dt = DateTime.fromMillisecondsSinceEpoch(
        isMillis ? intVal : intVal * 1000,
        isUtc: true,
      );
      return dt.toIso8601String();
    }

    return null;
  }
}
