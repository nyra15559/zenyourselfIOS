// lib/env_runtime_stub.dart
//
// EnvRuntime (Stub/Web) — Oxford UtilityPolish v2.0 · 2025-10-22
// -----------------------------------------------------------------------------
// Zweck
// • API-kompatibler Stub für Targets ohne dart:io (z. B. Web).
// • Bietet dieselben Methoden wie IO-Variante, liefert aber leere/Default-Werte.
// • Für bedingten Import zusammen mit env_runtime_io.dart verwenden:
//
//   import 'env_runtime_stub.dart'
//     if (dart.library.io) 'env_runtime_io.dart';
//
//   final api = EnvRuntime.readOr('API_BASE_URL', 'https://…');
// -----------------------------------------------------------------------------

import 'dart:collection';

class EnvRuntime {
  EnvRuntime._();

  // ---------- Basisschicht ----------

  static Map<String, String> _env() => const {};

  static String? read(String key) {
    // Keine Umgebung verfügbar im Stub
    return null;
  }

  static String? readAny(Iterable<String> keys) => null;

  static String readOr(String key, String fallback) => fallback;

  static Map<String, String> snapshot({String? prefix}) =>
      const UnmodifiableMapView(<String, String>{});

  // ---------- Typed Helpers ----------

  static bool readBool(String key, {bool defaultValue = false}) =>
      defaultValue;

  static int? readInt(String key) => null;

  static int readIntOr(String key, int fallback) => fallback;

  static Duration? readDuration(String key) => null;
}
