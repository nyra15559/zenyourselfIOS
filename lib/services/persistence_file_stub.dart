// lib/services/persistence_file_stub.dart
//
// Stub für Nicht-IO-Targets (z. B. Web). Identische API, klare Fehlermeldung.

import 'persistence_adapter.dart';

PersistenceAdapter createFileAdapter(String path, {bool pretty = true}) {
  // Einheitliche, leicht verständliche Meldung – kein Stacktrace im UI.
  throw UnsupportedError(
    'FilePersistenceAdapter ist auf diesem Target nicht verfügbar. '
    'Bitte nutze LocalStoragePersistenceAdapter oder FunctionsPersistenceAdapter.',
  );
}
