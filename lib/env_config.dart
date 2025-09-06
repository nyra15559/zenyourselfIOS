// lib/env_config.dart
//
// Zentrale Umgebungs-Konfiguration (web-safe).
// Reihenfolge: --dart-define → Runtime-Env (nur IO) → Defaults.

import 'env_runtime_stub.dart'
  if (dart.library.io) 'env_runtime_io.dart';

class ZenEnv {
  // 1) Compile-time Flags
  static const _dEnabled = String.fromEnvironment('ZEN_API_ENABLED', defaultValue: '');
  static const _dUrl     = String.fromEnvironment('ZEN_API_URL',     defaultValue: '');
  static const _dToken   = String.fromEnvironment('ZEN_APP_TOKEN',   defaultValue: '');

  // 2) Runtime (nur IO-Targets; auf Web immer null)
  static String? _env(String key) => EnvRuntime.read(key);

  // 3) Defaults
  static const _defaultEnabled = true;
  static const _defaultUrl     = 'https://nameless-breeze-87fb.edcvaultcom.workers.dev';
  static const _defaultToken   =
      'daded2f03bd67dd25d8434272c7095c234c80f9d15daefb253418b7a779244aa';

  // Helper
  static bool _parseBool(String s) {
    final v = s.toLowerCase().trim();
    return v == 'true' || v == '1' || v == 'yes' || v == 'y';
  }
  static String _normalizeUrl(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  // Getter
  static bool get apiEnabled {
    if (_dEnabled.isNotEmpty) return _parseBool(_dEnabled);
    final e = _env('ZEN_API_ENABLED');
    if (e != null) return _parseBool(e);
    return _defaultEnabled;
  }

  static String get apiUrl {
    if (_dUrl.isNotEmpty) return _normalizeUrl(_dUrl);
    return _normalizeUrl(_env('ZEN_API_URL') ?? _defaultUrl);
  }

  static String get appToken {
    if (_dToken.isNotEmpty) return _dToken;
    return _env('ZEN_APP_TOKEN') ?? _defaultToken;
  }
}
