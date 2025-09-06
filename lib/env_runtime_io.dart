// lib/env_runtime_io.dart
// IO-Only: liest echte Prozess-Umgebungsvariablen.

import 'dart:io' show Platform;

class EnvRuntime {
  static String? read(String key) => Platform.environment[key];
}
