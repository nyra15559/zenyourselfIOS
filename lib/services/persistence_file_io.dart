// lib/services/persistence_file_io.dart
//
// File-Backend (nur Mobile/Desktop). Atomare Writes via .tmp → rename.

import 'dart:convert';
import 'dart:io' show File;

import '../models/journal_entry.dart';
import 'persistence_adapter.dart';
import 'persistence_serializer.dart';

class FilePersistenceAdapter extends PersistenceAdapter {
  final File file;
  final bool pretty;

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
      return const <JournalEntry>[];
    }
  }

  @override
  Future<void> save(List<JournalEntry> entries) {
    _writeChain = _writeChain.then((_) async {
      final jsonStr = PersistenceSerializer.encode(entries, pretty: pretty);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final tmp = File('${file.path}.tmp');
      try {
        await tmp.writeAsString(jsonStr, flush: true, encoding: utf8);
        if (await file.exists()) {
          await file.delete();
        }
        await tmp.rename(file.path); // atomar
      } catch (_) {
        try {
          await file.writeAsString(jsonStr, flush: true, encoding: utf8);
        } catch (_) {}
      } finally {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
    });
    return _writeChain;
  }
}

/// Fabrik für conditional import
PersistenceAdapter createFileAdapter(String path, {bool pretty = true}) =>
    FilePersistenceAdapter.fromPath(path, pretty: pretty);
