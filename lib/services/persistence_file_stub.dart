// lib/services/persistence_file_stub.dart
//
// Stub für Nicht-IO-Targets (z. B. Web). Saubere Fehlermeldung.

import 'persistence_adapter.dart';

PersistenceAdapter createFileAdapter(String path, {bool pretty = true}) {
  throw UnsupportedError(
    'FilePersistenceAdapter ist auf diesem Target nicht verfügbar. '
    'Nutze LocalStoragePersistenceAdapter statt filePersistenceAdapterFromPath().',
  );
}
