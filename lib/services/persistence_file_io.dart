// lib/services/persistence_file_io.dart
//
// File-Backend (nur Mobile/Desktop). Atomare Writes via .tmp → rename.
// Robust gegen IO-Fehler: niemals Exceptions „nach oben“ werfen.

import 'dart:convert';
import 'dart:io' show File;

import '../models/journal_entry.dart';
import 'persistence_adapter.dart';
import 'persistence_serializer.dart';

class FilePersistenceAdapter extends PersistenceAdapter {
  final File file;
  final bool pretty;

  // Serieller Write-Guard (verhindert Überschneidungen)
  Future<void> _writeChain = Future.value();

  FilePersistenceAdapter(this.file, {this.pretty = true});

  factory FilePersistenceAdapter.fromPath(String path, {bool pretty = true}) =>
      FilePersistenceAdapter(File(path), pretty: pretty);

  @override
  Future<List<JournalEntry>> load() async {
    try {
      if (!await file.exists()) return const <JournalEntry>[];
      final contents = await file.readAsString(encoding: utf8);
      return PersistenceSerializer.decode(contents);
    } catch (_) {
      // Fallback: leere Liste
      return const <JournalEntry>[];
    }
  }

  @override
  Future<void> save(List<JournalEntry> entries) {
    _writeChain = _writeChain.then((_) async {
      try {
        final jsonStr = PersistenceSerializer.encode(entries, pretty: pretty);

        final dir = file.parent;
        if (!await dir.exists()) {
          try {
            await dir.create(recursive: true);
          } catch (_) {}
        }

        final tmp = File('${file.path}.tmp');
        try {
          await tmp.writeAsString(jsonStr, flush: true, encoding: utf8);
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
          await tmp.rename(file.path); // atomar
        } catch (_) {
          // Fallback: direkt schreiben (nicht atomar, aber besser als gar nichts)
          try {
            await file.writeAsString(jsonStr, flush: true, encoding: utf8);
          } catch (_) {}
        } finally {
          try {
            if (await tmp.exists()) await tmp.delete();
          } catch (_) {}
        }
      } catch (_) {
        // best effort – keine Exceptions nach oben
      }
    });
    return _writeChain;
  }
}

/// Fabrik für conditional import (gleiche Signatur wie Stub)
PersistenceAdapter createFileAdapter(String path, {bool pretty = true}) =>
    FilePersistenceAdapter.fromPath(path, pretty: pretty);
