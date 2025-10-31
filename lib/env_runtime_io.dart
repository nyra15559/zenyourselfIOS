// lib/env_runtime_io.dart
//
// EnvRuntime (IO) — Oxford UtilityPolish v2.0 · 2025-10-22
// -----------------------------------------------------------------------------
// Zweck
// • Einfache, einheitliche Laufzeit-Brücke zu Prozess-Umgebungsvariablen.
// • Keine Abhängigkeit von dart:html — reine IO-Variante.
// • Robuste Helpers (String/Bool/Int/Duration), Key-Normalisierung,
//   Mehrfach-Lookup (readAny), Snapshot mit Prefix.
//
// Verwendung (mit bedingtem Import):
//   import 'env_runtime_stub.dart'
//     if (dart.library.io) 'env_runtime_io.dart';
//
//   final api = EnvRuntime.readOr('API_BASE_URL', 'https://…');
// -----------------------------------------------------------------------------

import 'dart:io' show Platform;
import 'dart:collection';

class EnvRuntime {
  EnvRuntime._();

  // ---------- Basisschicht ----------

  /// Direkter Zugriff auf die (normalisierte) Umgebung. Kann leer sein.
  static Map<String, String> _env() => Platform.environment;

  /// Liest einen Wert (roh) für [key] unter Berücksichtigung gängiger Varianten:
  /// - Original, UPPERCASE, lowercase
  /// - Punkt/Minus → Unterstrich
  /// - Nicht-[A-Z0-9_] → „_“
  static String? read(String key) {
    final env = _env();
    for (final c in _candidates(key)) {
      final v = env[c];
      if (v != null) return v;
    }
    return null;
  }

  /// Liest den ersten gesetzten Wert aus mehreren [keys] (mit Normalisierung).
  static String? readAny(Iterable<String> keys) {
    for (final k in keys) {
      final v = read(k);
      if (v != null) return v;
    }
    return null;
  }

  /// Wie [read], aber mit Fallback.
  static String readOr(String key, String fallback) =>
      (read(key) ?? '').trim().isEmpty ? fallback : read(key)!;

  /// Schnappschuss der Umgebung (optional [prefix] filtern).
  /// [prefix] wird ebenso normalisiert (UPPER/„-/.“→„_“). Case-insensitive.
  static Map<String, String> snapshot({String? prefix}) {
    final env = _env();
    if (prefix == null || prefix.trim().isEmpty) {
      return UnmodifiableMapView(env);
    }
    final norm = _normalize(prefix);
    final out = <String, String>{};
    env.forEach((k, v) {
      final nk = _normalize(k);
      if (nk.startsWith(norm)) out[k] = v;
    });
    return UnmodifiableMapView(out);
  }

  // ---------- Typed Helpers ----------

  static bool readBool(String key, {bool defaultValue = false}) {
    final v = read(key);
    if (v == null) return defaultValue;
    final s = v.trim().toLowerCase();
    if (s.isEmpty) return defaultValue;
    if (['1', 'true', 'yes', 'y', 'on'].contains(s)) return true;
    if (['0', 'false', 'no', 'n', 'off'].contains(s)) return false;
    return defaultValue;
  }

  static int? readInt(String key) {
    final v = read(key);
    if (v == null) return null;
    return int.tryParse(v.trim());
  }

  static int readIntOr(String key, int fallback) => readInt(key) ?? fallback;

  /// Duration aus „15s“, „2m“, „3h“, „1d“ oder nackten Sekunden (z. B. „45“).
  static Duration? readDuration(String key) {
    final raw = read(key)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final numOnly = int.tryParse(raw);
    if (numOnly != null) return Duration(seconds: numOnly);

    final m = RegExp(r'^(\d+)\s*([smhdSMHD])$').firstMatch(raw);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null) return null;
    switch (m.group(2)!.toLowerCase()) {
      case 's':
        return Duration(seconds: n);
      case 'm':
        return Duration(minutes: n);
      case 'h':
        return Duration(hours: n);
      case 'd':
        return Duration(days: n);
      default:
        return null;
    }
  }

  // ---------- intern ----------

  static Iterable<String> _candidates(String key) sync* {
    final raw = key.trim();
    if (raw.isEmpty) return;
    final v1 = raw;
    final v2 = raw.toUpperCase();
    final v3 = raw.toLowerCase();
    final v4 = v2.replaceAll('-', '_');
    final v5 = v2.replaceAll('.', '_');
    final v6 = _normalize(v2);
    final set = <String>{v1, v2, v3, v4, v5, v6};
    // yield in stabiler Reihenfolge
    for (final k in [v1, v2, v3, v4, v5, v6]) {
      if (set.remove(k)) yield k;
    }
  }

  static String _normalize(String k) =>
      k.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_]'), '_');
}
