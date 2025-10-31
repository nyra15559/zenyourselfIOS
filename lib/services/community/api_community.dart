// lib/services/community/api_community.dart
//
// Community API — Help Flower Client (v1.0 · fixed)
// -----------------------------------------------------------------------------
// – Fix: HelpFlower-Konstruktor ist NICHT mehr const (wegen DateTime.now()).
// – Rest wie gehabt: HMAC, Offline-Queue-Hook, Invoke-Override.
//
// Abhängigkeiten:
//   crypto: ^3.0.3
//
// Hinweis Plattformen:
//   Für Web kann invokeOverride gesetzt werden.
//

library api_community;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, ContentType;
import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:flutter/foundation.dart' show debugPrint;

/// Frei wählbare Signatur-Headernamen (Server muss entsprechen).
class CommunityHeaders {
  static const apiKey = 'X-Api-Key';
  static const signature = 'X-Signature';
  static const timestamp = 'X-Timestamp';
  static const client = 'X-Client';
  static const responseSignature =
      'X-Signature-Response'; // optional serverseitig
}

/// Datenträger: Help-Flower (minimal, PII-frei).
class HelpFlower {
  final String topic; // z. B. "Schlafroutine"
  final String summary; // kurze neutrale Beschreibung
  final List<String> tags; // max 8 empfohlen
  final String locale; // "de-CH" / "de" / ...
  final DateTime createdAt; // Clientzeitpunkt
  final Map<String, dynamic>? meta; // optionale, PII-freie Metadaten

  // WICHTIG: nicht const, damit DateTime.now() erlaubt ist.
  HelpFlower({
    required this.topic,
    required this.summary,
    required this.tags,
    this.locale = 'de',
    DateTime? createdAt,
    this.meta,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'topic': topic.trim(),
        'summary': summary.trim(),
        'tags': tags
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'locale': locale,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (meta != null && meta!.isNotEmpty) 'meta': meta,
      };
}

/// Ergebnisobjekt ohne Exceptions in der UI-Schicht.
class CommunityResult {
  final bool ok;
  final int status;
  final Map<String, dynamic>? data;
  final String? error;

  const CommunityResult._(
      {required this.ok, required this.status, this.data, this.error});

  factory CommunityResult.success(int status, Map<String, dynamic>? data) =>
      CommunityResult._(ok: true, status: status, data: data);

  factory CommunityResult.failure(int status, String message) =>
      CommunityResult._(ok: false, status: status, error: message);

  @override
  String toString() =>
      'CommunityResult(ok=$ok, status=$status, error=$error, data=$data)';
}

/// Einfache Offline-Queue-Funktion: wird mit (kind, payload) aufgerufen.
typedef EnqueueFn = Future<void> Function(
    String kind, Map<String, dynamic> payload);

/// Request-Invoker (für Tests/Web austauschbar).
typedef InvokeFn = Future<_InvokeResponse> Function(_InvokeRequest req);

class _InvokeRequest {
  final Uri url;
  final String method;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  final Duration timeout;
  const _InvokeRequest({
    required this.url,
    required this.method,
    required this.headers,
    required this.bodyBytes,
    required this.timeout,
  });
}

class _InvokeResponse {
  final int status;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  const _InvokeResponse(
      {required this.status, required this.headers, required this.bodyBytes});

  String get bodyString => utf8.decode(bodyBytes);
  Map<String, dynamic>? get jsonOrNull {
    try {
      final raw = bodyString.trim();
      if (raw.isEmpty) return null;
      final v = json.decode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}

/// Haupt-Client
class CommunityApi {
  CommunityApi._();
  static final CommunityApi instance = CommunityApi._();

  String _baseUrl = 'https://community.zenyourself.app';
  String _apiKey = '';
  String _hmacSecret = '';
  String? _responseHmacSecret; // optional anderes Secret für Response-Check
  Duration _timeout = const Duration(seconds: 10);
  InvokeFn? _invokeOverride; // z. B. für Web/Mocks
  EnqueueFn? _enqueue; // Offline-Queue-Adapter
  bool _simulateFailure = false; // Test-Haken

  /// Konfiguration – idempotent aufrufbar.
  void configure({
    String? baseUrl,
    String? apiKey,
    String? hmacSecret,
    String? responseHmacSecret,
    Duration? timeout,
    InvokeFn? invokeOverride,
    EnqueueFn? enqueue,
    bool? simulateFailure,
  }) {
    if (baseUrl != null && baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (apiKey != null) _apiKey = apiKey;
    if (hmacSecret != null) _hmacSecret = hmacSecret;
    if (responseHmacSecret != null) _responseHmacSecret = responseHmacSecret;
    if (timeout != null) _timeout = timeout;
    if (invokeOverride != null) _invokeOverride = invokeOverride;
    if (enqueue != null) _enqueue = enqueue;
    if (simulateFailure != null) _simulateFailure = simulateFailure;
  }

  /// POST /v1/community/help-flower
  Future<CommunityResult> postHelpFlower({
    required HelpFlower flower,
    Map<String, dynamic>? telemetry, // wird sanitisiert
    Map<String, String>? extraHeaders,
    bool enqueueOnFail = true,
    String path = '/v1/community/help-flower',
  }) async {
    try {
      if (_simulateFailure) {
        throw const _NetError('Simulierte Störung');
      }
      if (_apiKey.isEmpty || _hmacSecret.isEmpty) {
        return CommunityResult.failure(
            0, 'CommunityApi nicht konfiguriert (apiKey/secret fehlen).');
      }

      final url = Uri.parse('$_baseUrl$path');
      final safeTelemetry = _sanitizeTelemetry(telemetry);
      final payload = <String, dynamic>{
        'flower': flower.toJson(),
        if (safeTelemetry.isNotEmpty) 'telemetry': safeTelemetry,
        'client': {
          'sdk': 'zenyourself-community-dart',
          'v': '1.0',
        },
      };
      final bodyBytes = utf8.encode(json.encode(payload));

      final ts = DateTime.now().toUtc().toIso8601String();
      final sig = _signRequest(
          method: 'POST', path: path, timestamp: ts, bodyBytes: bodyBytes);

      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        CommunityHeaders.apiKey: _apiKey,
        CommunityHeaders.timestamp: ts,
        CommunityHeaders.signature: sig,
        CommunityHeaders.client: 'ZenYourself/CommunityApi 1.0',
        if (extraHeaders != null) ...extraHeaders,
      };

      final resp = await _invoke(
        _InvokeRequest(
          url: url,
          method: 'POST',
          headers: headers,
          bodyBytes: bodyBytes,
          timeout: _timeout,
        ),
      );

      // Optional: Response-Signatur prüfen, wenn Header vorhanden
      _maybeVerifyResponseSignature(resp,
          secret: _responseHmacSecret ?? _hmacSecret);

      if (resp.status >= 200 && resp.status < 300) {
        return CommunityResult.success(resp.status, resp.jsonOrNull);
      }

      final msg = _errorMessage(resp.status, resp.bodyString);
      if (enqueueOnFail) {
        await _enqueue?.call('community.help_flower', {
          'ts': DateTime.now().toUtc().toIso8601String(),
          'path': path,
          'payload': payload, // enthält keine Secrets
        });
      }
      return CommunityResult.failure(resp.status, msg);
    } on _NetTimeout catch (e) {
      if (enqueueOnFail) {
        await _enqueue?.call('community.help_flower', {
          'ts': DateTime.now().toUtc().toIso8601String(),
          'path': path,
          'payload': {
            'flower': flower.toJson(),
            if (telemetry != null) 'telemetry': _sanitizeTelemetry(telemetry),
            'client': {'sdk': 'zenyourself-community-dart', 'v': '1.0'},
          },
        });
      }
      return CommunityResult.failure(408, e.message);
    } on _NetError catch (e) {
      if (enqueueOnFail) {
        await _enqueue?.call('community.help_flower', {
          'ts': DateTime.now().toUtc().toIso8601String(),
          'path': path,
          'payload': {
            'flower': flower.toJson(),
            if (telemetry != null) 'telemetry': _sanitizeTelemetry(telemetry),
            'client': {'sdk': 'zenyourself-community-dart', 'v': '1.0'},
          },
        });
      }
      return CommunityResult.failure(0, e.message);
    } catch (e, st) {
      debugPrint('[CommunityApi] Unerwarteter Fehler: $e\n$st');
      return CommunityResult.failure(0, 'Unerwarteter Fehler.');
    }
  }

  // ─────────────────────────────────────────────────────────────────────

  String _signRequest({
    required String method,
    required String path,
    required String timestamp,
    required List<int> bodyBytes,
  }) {
    final bodyHash = sha256.convert(bodyBytes).toString();
    final signString = '$method\n$path\n$timestamp\n$bodyHash';
    final h = Hmac(sha256, utf8.encode(_hmacSecret));
    final sig = h.convert(utf8.encode(signString)).toString();
    return sig;
  }

  void _maybeVerifyResponseSignature(_InvokeResponse resp,
      {required String secret}) {
    final header = resp.headers[CommunityHeaders.responseSignature];
    if (header == null || header.isEmpty) return;
    try {
      final bodyHash = sha256.convert(resp.bodyBytes).toString();
      final ts = resp.headers[CommunityHeaders.timestamp] ?? '';
      final signString = 'RESP\n$ts\n$bodyHash';
      final h = Hmac(sha256, utf8.encode(secret));
      final expected = h.convert(utf8.encode(signString)).toString();
      if (expected != header) {
        debugPrint(
            '[CommunityApi] Response-Signatur ungültig (Header != expected).');
      }
    } catch (e) {
      debugPrint('[CommunityApi] Response-Signatur-Check fehlgeschlagen: $e');
    }
  }

  String _errorMessage(int status, String body) {
    final trimmed = body.trim();
    if (status == 0) return 'Keine Verbindung.';
    if (status == 401) return 'Nicht autorisiert.';
    if (status == 403) return 'Verboten.';
    if (status == 404) return 'Nicht gefunden.';
    if (status == 408) return 'Zeitüberschreitung.';
    if (status == 409) return 'Konflikt.';
    if (status == 413) return 'Payload zu groß.';
    if (status == 429) return 'Zu viele Anfragen.';
    if (status >= 500) return 'Serverfehler ($status).';
    return trimmed.isEmpty ? 'Fehler ($status).' : 'Fehler ($status): $trimmed';
  }

  Map<String, dynamic> _sanitizeTelemetry(Map<String, dynamic>? t) {
    if (t == null || t.isEmpty) return const {};
    final redacted = <String, dynamic>{};

    const deny = <String>{
      'name',
      'fullName',
      'vorname',
      'nachname',
      'email',
      'e-mail',
      'mail',
      'phone',
      'telefon',
      'mobile',
      'handy',
      'address',
      'adresse',
      'strasse',
      'plz',
      'ort',
      'ip',
      'ipv4',
      'ipv6',
      'lat',
      'lng',
      'latitude',
      'longitude',
      'geolocation',
      'birthdate',
      'geburtstag',
      'userId',
      'user_id',
      'accountId',
      'account_id',
      'sessionId',
      'session_id',
    };

    const allow = <String>{
      'app_version',
      'build',
      'platform',
      'os',
      'device_class',
      'locale',
      'tz',
      'screen',
      'theme',
      'feature_flags',
      'network',
      'retry_count',
      'queue_len',
    };

    t.forEach((k, v) {
      if (allow.contains(k)) redacted[k] = _safeScalar(v);
    });

    void takeNested(String key) {
      final v = t[key];
      if (v is Map) {
        final m = <String, dynamic>{};
        v.forEach((kk, vv) {
          if (!deny.contains(kk)) m[kk] = _safeScalar(vv);
        });
        if (m.isNotEmpty) redacted[key] = m;
      }
    }

    takeNested('performance');
    takeNested('timers');
    takeNested('flags');

    return redacted;
  }

  dynamic _safeScalar(dynamic v) {
    if (v == null) return null;
    if (v is num || v is bool) return v;
    final s = v.toString();
    return s.length > 120 ? s.substring(0, 120) : s;
  }

  Future<_InvokeResponse> _invoke(_InvokeRequest req) async {
    if (_invokeOverride != null) {
      return _invokeOverride!(req).timeout(req.timeout, onTimeout: () {
        throw _NetTimeout('Zeitüberschreitung nach ${req.timeout.inSeconds}s.');
      });
    }

    final client = HttpClient()..connectionTimeout = req.timeout;
    try {
      final r = await client.openUrl(req.method, req.url).timeout(req.timeout,
          onTimeout: () =>
              throw _NetTimeout('Zeitüberschreitung beim Verbindungsaufbau.'));

      req.headers.forEach(r.headers.add);
      r.headers.contentType = ContentType.json;
      r.add(req.bodyBytes);

      final res = await r.close().timeout(
            req.timeout,
            onTimeout: () =>
                throw _NetTimeout('Zeitüberschreitung beim Lesen.'),
          );

      final bytes = await res.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
      final headers = <String, String>{};
      res.headers.forEach((name, values) {
        if (values.isNotEmpty) headers[name] = values.join(',');
      });

      return _InvokeResponse(
          status: res.statusCode, headers: headers, bodyBytes: bytes);
    } on _NetTimeout {
      rethrow;
    } catch (e) {
      throw _NetError('Netzwerkfehler: $e');
    } finally {
      client.close(force: true);
    }
  }
}

class _NetError implements Exception {
  final String message;
  const _NetError(this.message);
  @override
  String toString() => message;
}

class _NetTimeout extends _NetError {
  const _NetTimeout(String msg) : super(msg);
}
