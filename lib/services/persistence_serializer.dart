// lib/services/persistence_serializer.dart
//
// PersistenceSerializer — shared, public (v6)
// Akzeptiert Wrapper {schema,version,count,journal:[...]} ODER reine Liste.
// Tolerant: Elemente dürfen Map **oder** JSON-String (Map) sein.

import 'dart:convert';
import '../models/journal_entry.dart' as jm;

class PersistenceSerializer {
  static const String schema = 'zen.v6.persistence';
  static const int version = 1;

  /// Serialisiert Einträge in ein Wrapper-JSON (journal: [Maps]).
  static String encode(List<jm.JournalEntry> entries, {bool pretty = true}) {
    final payload = <String, dynamic>{
      'schema': schema,
      'version': version,
      'count': entries.length,
      'journal': entries.map((e) => e.toMap()).toList(growable: false),
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (pretty) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(payload);
    }
    return jsonEncode(payload);
  }

  /// Deserialisiert sowohl Wrapper als auch eine rohe Liste.
  /// Unterstützt Elemente als Map **oder** als JSON-String (robust gegen Altformate).
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

    // 1) Journal-Liste aus Wrapper oder rohe Liste extrahieren
    List list;
    if (data is List) {
      list = data;
    } else if (data is Map<String, dynamic>) {
      final j = data['journal'];
      if (j is List) {
        list = j;
      } else {
        final possible = data.values.firstWhere(
          (v) => v is List,
          orElse: () => const <dynamic>[],
        );
        list = possible is List ? possible : const <dynamic>[];
      }
    } else {
      list = const <dynamic>[];
    }

    // 2) Items in JournalEntry mappen (Map bevorzugt, String als JSON-Map interpretieren)
    final out = <jm.JournalEntry>[];
    for (final item in list) {
      try {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item as Map);
          out.add(jm.JournalEntry.fromMap(map));
        } else if (item is String) {
          final decoded = jsonDecode(item);
          if (decoded is Map) {
            out.add(jm.JournalEntry.fromMap(Map<String, dynamic>.from(decoded)));
          }
        }
      } catch (_) {
        // Ein fehlerhafter Eintrag soll den Import nicht stoppen.
      }
    }

    // 3) Stabil: DESC nach createdAt
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }
}
