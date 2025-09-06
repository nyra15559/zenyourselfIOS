// lib/services/auth.dart
//
// Oxford Safety Edition — robust, privacy-aware, retry-ready.
// - Keine PII im Log (Tokens werden maskiert)
// - Einheitliche HTTP-Hilfen (GET/POST) ohne Abhängigkeit zu ApiService
// - Token-Refresh mit einmaligem Retry bei 401
// - Sichere, defensive JSON-Parsing-Strategie
// - Abwärtskompatibel: Signaturen von login/register/logout/isLoggedIn/fetchProfile bleiben

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // ---------- Konfiguration ----------
  /// Basis-URL (per --dart-define=API_BASE_URL=... überschreibbar)
  static String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.zenyourself.app/',
  );

  /// Optional zur Laufzeit ändern (z. B. Staging).
  static void configure({required String newBaseUrl}) {
    baseUrl = newBaseUrl.endsWith('/') ? newBaseUrl : '$newBaseUrl/';
  }

  // Netzwerk: Default-Timeouts
  static const Duration _defaultTimeout = Duration(seconds: 15);

  // ---------- Storage Keys ----------
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _accessExpKey = 'auth_token_exp';
  static const _refreshExpKey = 'refresh_token_exp';

  // ---------- Öffentliche API (kompatibel) ----------

  /// Login per E-Mail & Passwort. Token wird lokal gespeichert.
  static Future<bool> login(String email, String password) async {
    try {
      final res = await _post(
        'auth/login',
        body: {'email': email, 'password': password},
        withAuth: false,
      );
      if (_isOk(res.statusCode)) {
        final data = _safeJson(res.body);
        await _storeTokensFromMap(data);
        return true;
      }
      _logHttp('Login', res);
      return false;
    } catch (e) {
      _log('Login Exception: $e');
      return false;
    }
  }

  /// Registrierung (E-Mail & Passwort)
  static Future<bool> register(String email, String password) async {
    try {
      final res = await _post(
        'auth/register',
        body: {'email': email, 'password': password},
        withAuth: false,
      );
      if (_isOk(res.statusCode) || res.statusCode == 201) {
        final data = _safeJson(res.body);
        await _storeTokensFromMap(data);
        return true;
      }
      _logHttp('Registration', res);
      return false;
    } catch (e) {
      _log('Registration Exception: $e');
      return false;
    }
  }

  /// Logout – löscht Tokens lokal
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_accessExpKey);
    await prefs.remove(_refreshExpKey);
  }

  /// Schnell prüfen: Ist User eingeloggt?
  /// Versucht bei abgelaufenem Access Token einmalig ein Refresh.
  static Future<bool> isLoggedIn() async {
    final token = await getAuthToken();
    if (token == null || token.isEmpty) return false;

    if (await _isAccessExpired()) {
      final ok = await refreshToken();
      return ok;
    }
    return true;
  }

  /// Hole Profil/Account-Info (sofern API bereitstellt).
  /// Bei 401 wird einmalig ein Refresh versucht und der Call wiederholt.
  static Future<Map<String, dynamic>?> fetchProfile() async {
    try {
      var res = await _get('auth/profile');
      if (res.statusCode == 401 && await refreshToken()) {
        res = await _get('auth/profile'); // retry once
      }
      if (_isOk(res.statusCode)) {
        return _safeJson(res.body);
      }
      _logHttp('Fetch profile', res);
      return null;
    } catch (e) {
      _log('Fetch profile Exception: $e');
      return null;
    }
  }

  /// Hole gespeicherten Bearer-Token
  static Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Access-Token automatisch erneuern (mit Refresh Token)
  static Future<bool> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) return false;

    // Wenn Refresh-Token abgelaufen → sofort false
    if (await _isRefreshExpired()) return false;

    try {
      final res = await _post(
        'auth/refresh',
        body: {'refresh_token': refreshToken},
        withAuth: false,
      );
      if (_isOk(res.statusCode)) {
        final data = _safeJson(res.body);
        await _storeTokensFromMap(data);
        return true;
      }
      _logHttp('Token Refresh', res);
      return false;
    } catch (e) {
      _log('Token Refresh Exception: $e');
      return false;
    }
  }

  // ===================================================================
  //                        Interne HTTP-Helfer
  // ===================================================================

  static Uri _u(String path) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$baseUrl$p');
  }

  static Map<String, String> _jsonHeaders({String? token}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  /// GET mit optionalem Auth und automatischer Header-Setzung.
  static Future<http.Response> _get(
    String path, {
    Map<String, String>? query,
    bool withAuth = true,
  }) async {
    final token = withAuth ? await getAuthToken() : null;
    final uri = query == null ? _u(path) : _u(path).replace(queryParameters: query);
    final res = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(_defaultTimeout);
    return res;
  }

  /// POST mit optionalem Auth und JSON-Body.
  static Future<http.Response> _post(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
  }) async {
    final token = withAuth ? await getAuthToken() : null;
    final uri = _u(path);
    final res = await http
        .post(
          uri,
          headers: _jsonHeaders(token: token),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_defaultTimeout);
    return res;
  }

  // ===================================================================
  //                        Token Handling
  // ===================================================================

  /// Speichert Tokens (unterstützt verschiedene Key-Namen der API).
  static Future<void> _storeTokensFromMap(Map<String, dynamic> data) async {
    // Verschiedene Feldnamen tolerieren
    final access = (data['access_token'] ??
            data['accessToken'] ??
            data['token'] ??
            data['jwt'] ??
            '')
        .toString();
    final refresh =
        (data['refresh_token'] ?? data['refreshToken'] ?? data['id_token'] ?? '').toString();

    // Optional: Expiry (Sekunden seit jetzt ODER ISO-8601/epoch)
    final accessExp = _parseExpiry(data['access_expires'] ?? data['accessExpires']);
    final refreshExp = _parseExpiry(data['refresh_expires'] ?? data['refreshExpires']);

    if (access.isEmpty) {
      _log('Warn: access token missing in response.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, access);
    if (refresh.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, refresh);
    }
    if (accessExp != null) {
      await prefs.setInt(_accessExpKey, accessExp.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_accessExpKey);
    }
    if (refreshExp != null) {
      await prefs.setInt(_refreshExpKey, refreshExp.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_refreshExpKey);
    }
  }

  static Future<bool> _isAccessExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_accessExpKey);
    if (ms == null) return false; // kein Expiry => nicht abgelaufen
    final exp = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    // 30s Sicherheits-Puffer
    return DateTime.now().toUtc().isAfter(exp.subtract(const Duration(seconds: 30)));
  }

  static Future<bool> _isRefreshExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_refreshExpKey);
    if (ms == null) return false;
    final exp = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return DateTime.now().toUtc().isAfter(exp);
  }

  /// Akzeptiert:
  /// - int/double epoch s|ms
  /// - String "+3600" (relativ)
  /// - String epoch ("1700000000"/"1700000000000")
  /// - ISO-8601
  static DateTime? _parseExpiry(dynamic v) {
    if (v == null) return null;

    if (v is int) {
      // epoch seconds ODER ms? Heuristik:
      if (v > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true);
      }
    }
    if (v is double) {
      final i = v.toInt();
      return _parseExpiry(i);
    }
    if (v is String) {
      final s = v.trim();

      // Relativ-Format: +Sekunden
      if (s.startsWith('+')) {
        final secs = int.tryParse(s.substring(1));
        if (secs != null) return DateTime.now().toUtc().add(Duration(seconds: secs));
      }

      // Nur Ziffern? => epoch s/ms
      if (RegExp(r'^\d+$').hasMatch(s)) {
        final n = int.tryParse(s);
        if (n != null) return _parseExpiry(n);
      }

      // ISO-8601
      try {
        return DateTime.parse(s).toUtc();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // ===================================================================
  //                        Logging / JSON Utils
  // ===================================================================

  static Map<String, dynamic> _safeJson(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) return d;
      return <String, dynamic>{'data': d};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static bool _isOk(int code) => code >= 200 && code < 300;

  static void _log(String msg) {
    if (kDebugMode) {
      // Keine PII (Tokens, Passwörter etc.) ins Log schreiben.
      debugPrint('[Auth] $msg');
    }
  }

  static void _logHttp(String context, http.Response res) {
    if (!kDebugMode) return;
    final b = _maskSecrets(res.body);
    final preview = b.length > 300 ? '${b.substring(0, 300)}…' : b;
    debugPrint(
      '[Auth:$context] HTTP ${res.statusCode} ${res.request?.url}\n$preview',
    );
  }

  /// Maskiert offensichtliche Geheimnisse in Response-Bodies.
  static String _maskSecrets(String s) {
    String out = s;
    final patterns = <RegExp>[
      // "access_token":"...","accessToken":"..."
      RegExp(r'("access[_A-Za-z]*token"\s*:\s*")([^"]+)(")', caseSensitive: false),
      // "refresh_token":"..."
      RegExp(r'("refresh[_A-Za-z]*token"\s*:\s*")([^"]+)(")', caseSensitive: false),
      // Bearer token in plain
      RegExp(r'(Bearer\s+)[A-Za-z0-9\-\._~\+\/]+=*', caseSensitive: false),
    ];
    for (final re in patterns) {
      out = out.replaceAllMapped(re, (m) {
        if (m.groupCount == 3) {
          return '${m.group(1)}***${m.group(3)}';
        }
        // Bearer-Pfad
        final full = m.group(0)!;
        return full.replaceAll(RegExp(r'([A-Za-z0-9\-\._~\+\/]+=*)$'), '***');
      });
    }
    return out;
  }
}
