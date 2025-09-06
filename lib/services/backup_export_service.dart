// lib/services/backup_export_service.dart
//
// BackupExportService — Zen v5 (ohne neue Dependencies)
// -----------------------------------------------------
// Features
// • Baut ein konsistentes Backup-Dokument (JSON) aus deinen Daten.
// • Optional gzip-komprimiert (.json.gz) – nur dart:io / GZipCodec.
// • Keine harten Abhängigkeiten zu Legacy-Modellen (toJson/toMap wird dynamisch erkannt).
// • Rückgabe als Bundle + Helper zum Speichern in ein Directory.
//
// Struktur des Backups (Beispiel):
// {
//   "schema": "zen.v5.backup/1",
//   "exported_at": "2025-01-10T20:15:30.123Z",
//   "app": { "name": "Zen", "version": "5.0.0", "platform": "flutter" },
//   "user": { "id": "optional-user-id" },
//   "counts": { "journal": 42, "mood_legacy": 10, "reflection_legacy": 5 },
//   "latest": { "journal_ts": "2025-01-10T19:59:00.000Z" },
//   "data": {
//     "journal": [ { ...JournalEntry.toJson() }, ... ],
//     "mood_legacy": [ ...optional... ],
//     "reflection_legacy": [ ...optional... ]
//   }
// }
//
// Verwendung (Beispiel):
// final bundle = await BackupExportService.instance.build(
//   journal: provider.entries,
//   moodsLegacy: moodProvider.entries,              // optional
//   reflectionsLegacy: reflectionProvider.entries,  // optional
//   appVersion: '5.0.0', userId: 'abc123',
// );
// final dir = await getApplicationDocumentsDirectory(); // falls path_provider genutzt
// await BackupExportService.instance.writeGzip(bundle, dir); // schreibt *.json.gz
//
// Hinweis: Für Mobile/Desktop kannst du frei wählen, wohin geschrieben wird.
// Ohne path_provider kannst du auch Directory.systemTemp verwenden.
//
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import '../data/journal_entry.dart';

class BackupBundle {
  /// Basis des Dateinamens, z. B. "zen_backup_2025-01-10_201530Z"
  final String filenameBase;

  /// Pretty-printed JSON (UTF-8)
  final String jsonPretty;

  /// UTF-8 Rohbytes des JSON
  final List<int> jsonBytes;

  /// GZip-komprimierte Bytes des JSON (kann leer sein, falls compress=false übergeben würde)
  final List<int> gzipBytes;

  /// Zählwerte für UI/Logs
  final int countJournal;
  final int countMoodLegacy;
  final int countReflectionLegacy;

  const BackupBundle({
    required this.filenameBase,
    required this.jsonPretty,
    required this.jsonBytes,
    required this.gzipBytes,
    required this.countJournal,
    required this.countMoodLegacy,
    required this.countReflectionLegacy,
  });

  String get jsonFilename => '$filenameBase.json';
  String get gzipFilename => '$filenameBase.json.gz';
}

class BackupExportService {
  BackupExportService._();
  static final BackupExportService instance = BackupExportService._();

  /// Baut das Backup-Dokument und liefert JSON sowie gzip-Bytes in einem Bundle.
  ///
  /// [journal]      — Liste v5 `JournalEntry` (bevorzugt, DESC sortiert).
  /// [moodsLegacy]  — optional; beliebige Objekte mit `toJson()`/`toMap()` oder Map.
  /// [reflectionsLegacy] — optional; s. o.
  /// [appVersion]   — Version-String für Metadaten.
  /// [userId]       — optionaler User-Identifier (kein PII-Zwang).
  /// [now]          — Zeitstempel für Export; default: DateTime.now().toUtc().
  Future<BackupBundle> build({
    required List<JournalEntry> journal,
    List<dynamic>? moodsLegacy,
    List<dynamic>? reflectionsLegacy,
    String? appVersion,
    String? userId,
    DateTime? now,
    bool compress = true,
  }) async {
    final exportedAt = (now ?? DateTime.now().toUtc());
    final doc = _buildDocument(
      journal: journal,
      moodsLegacy: moodsLegacy,
      reflectionsLegacy: reflectionsLegacy,
      appVersion: appVersion,
      userId: userId,
      exportedAt: exportedAt,
    );

    // Pretty JSON (stabil für Diff/Lesbarkeit)
    const encoder = JsonEncoder.withIndent('  ');
    final jsonPretty = encoder.convert(doc);
    final jsonBytes = utf8.encode(jsonPretty);

    // gzip (moderater Level 6)
    final gzipBytes = compress ? const GZipCodec(level: 6).encode(jsonBytes) : <int>[];

    final base = _suggestedFilenameBase(exportedAt);

    return BackupBundle(
      filenameBase: base,
      jsonPretty: jsonPretty,
      jsonBytes: jsonBytes,
      gzipBytes: gzipBytes,
      countJournal: journal.length,
      countMoodLegacy: moodsLegacy?.length ?? 0,
      countReflectionLegacy: reflectionsLegacy?.length ?? 0,
    );
  }

  /// Schreibt die **.json**-Datei in [dir] und gibt die Datei zurück.
  Future<File> writeJson(BackupBundle bundle, Directory dir) async {
    final path = _join(dir.path, bundle.jsonFilename);
    final file = File(path);
    await file.writeAsBytes(bundle.jsonBytes, flush: true);
    return file;
  }

  /// Schreibt die **.json.gz**-Datei in [dir] und gibt die Datei zurück.
  Future<File> writeGzip(BackupBundle bundle, Directory dir) async {
    if (bundle.gzipBytes.isEmpty) {
      // Falls nicht komprimiert wurde, schreiben wir stattdessen das JSON.
      return writeJson(bundle, dir);
    }
    final path = _join(dir.path, bundle.gzipFilename);
    final file = File(path);
    await file.writeAsBytes(bundle.gzipBytes, flush: true);
    return file;
  }

  /// Baut das finale Dokument (Map) gemäß Schema.
  Map<String, dynamic> _buildDocument({
    required List<JournalEntry> journal,
    List<dynamic>? moodsLegacy,
    List<dynamic>? reflectionsLegacy,
    required DateTime exportedAt,
    String? appVersion,
    String? userId,
  }) {
    // Defensive: Journal nach ts DESC sortieren (falls Provider-Garantie fehlt)
    final sortedJournal = [...journal]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final latestTs = sortedJournal.isEmpty ? null : sortedJournal.first.createdAt.toUtc();

    return <String, dynamic>{
      'schema': 'zen.v5.backup/1',
      'exported_at': exportedAt.toIso8601String(),
      'app': {
        'name': 'Zen',
        'version': appVersion ?? '5.x',
        'platform': 'flutter',
      },
      if (userId != null && userId.trim().isNotEmpty) 'user': {'id': userId.trim()},
      'counts': {
        'journal': sortedJournal.length,
        'mood_legacy': moodsLegacy?.length ?? 0,
        'reflection_legacy': reflectionsLegacy?.length ?? 0,
      },
      'latest': {
        if (latestTs != null) 'journal_ts': latestTs.toIso8601String(),
      },
      'data': {
        'journal': sortedJournal.map((e) => e.toJson()).toList(growable: false),
        if ((moodsLegacy?.isNotEmpty ?? false))
          'mood_legacy': _encodeUnknownList(moodsLegacy!),
        if ((reflectionsLegacy?.isNotEmpty ?? false))
          'reflection_legacy': _encodeUnknownList(reflectionsLegacy!),
      },
    }..removeWhere((_, v) => v == null);
  }

  /// Versucht, unbekannte Modelle zu serialisieren:
  /// - Map -> Map
  /// - hat toJson() -> Map
  /// - hat toMap()  -> Map
  /// - sonst -> String (fallback)
  List<dynamic> _encodeUnknownList(List<dynamic> items) {
    return items.map((e) {
      if (e == null) return null;
      if (e is Map) return e;
      try {
        // toJson()
        final json = (e as dynamic).toJson();
        if (json is Map<String, dynamic>) return json;
      } catch (_) {}
      try {
        // toMap()
        final map = (e as dynamic).toMap();
        if (map is Map<String, dynamic>) return map;
      } catch (_) {}
      // letzter Fallback: als String
      return e.toString();
    }).where((e) => e != null).toList(growable: false);
  }

  /// Baut einen stabilen Dateinamen (UTC) ohne Sonderzeichen.
  String _suggestedFilenameBase(DateTime utcNow) {
    // 2025-01-10_201530Z
    final y = utcNow.year.toString().padLeft(4, '0');
    final m = utcNow.month.toString().padLeft(2, '0');
    final d = utcNow.day.toString().padLeft(2, '0');
    final hh = utcNow.hour.toString().padLeft(2, '0');
    final mm = utcNow.minute.toString().padLeft(2, '0');
    final ss = utcNow.second.toString().padLeft(2, '0');
    return 'zen_backup_${y}-${m}-${d}_${hh}${mm}${ss}Z';
  }

  /// Kleines path join, um `path`-Dependency zu vermeiden.
  String _join(String dir, String file) {
    if (dir.isEmpty) return file;
    if (dir.endsWith(Platform.pathSeparator)) return '$dir$file';
    return '$dir${Platform.pathSeparator}$file';
  }
}
