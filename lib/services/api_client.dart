// lib/services/api_client.dart
//
// ApiClient — HttpInvoker-Adapter (Pro-Version, v6.3)
// ---------------------------------------------------
// • Schlankes HTTP via dart:io (keine zusätzlichen Pakete)
// • Kompatibel mit HttpInvoker (Guidance/ApiService.configureHttp)
// • Robust: Retry/Backoff (0.5s · 1.5s · 3s) + Jitter, Retry-After-Header
// • GZip-Antworten (HttpClient.autoUncompress = true)
// • Timeouts pro Request, dezentes Logging inkl. Dauer je Versuch
// • Tolerantes JSON-Parsing inkl. text/plain-Fallback → {output_text: "..."}.
// • Sichere Defaults bei Accept-/Content-Type-Headern (Problem+JSON/Text)
// • Extras: PATCH-Support, eindeutige Header-Sets, Request-Id/At, Health-Check
//
// Hinweis zu Retries:
// - Sowohl der Client als auch der aufrufende Service können Retries machen.
//   Um doppelte Retries zu vermeiden, entweder hier `retries: const []` setzen
//   ODER Retries im aufrufenden Service deaktivieren.
//
// Beispiel-Wiring (App-Init):
//
//   final client = ApiClient(
//     baseUrl: Uri.parse('https://your-worker.example.com'),
//     tokenProvider: () async => 'YOUR_APPTOKEN', // oder null wenn offen
//     onLog: (msg) => debugPrint(msg),
//     requestTimeout: const Duration(seconds: 18),
//   );
//   GuidanceService.instance.configureHttp(
//     invoker: client.call,         // <- erfüllt HttpInvoker-Signatur
//     baseUrl: client.baseUrlStr,   // optional für Logging
//     timeout: const Duration(seconds: 25),
//   );

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'guidance_service.dart' show HttpInvoker;

class ApiClient {
  ApiClient({
    required Uri baseUrl,
    this.tokenProvider,
    this.staticHeaders = const {},
    this.requestTimeout = const Duration(seconds: 12),
    this.retries = const [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
      Duration(milliseconds: 3000),
    ],
    this.onLog,
    HttpClient? httpClient,
    this.connectionTimeout = const Duration(seconds: 8),
  })  : _baseUrl = baseUrl,
        _http = httpClient ?? (HttpClient()..autoUncompress = true) {
    _http.connectionTimeout = connectionTimeout;
  }

  final Uri _baseUrl;
  final HttpClient _http;

  /// Optionaler Bearer-Token-Lieferant (wird pro Request abgefragt).
  final FutureOr<String?> Function()? tokenProvider;

  /// Zusätzliche statische Header (werden zu Standard-Headern gemerged).
  final Map<String, String> staticHeaders;

  /// Timeout pro Request (inkl. Übertragung).
  final Duration requestTimeout;

  /// Backoff-Staffel (wird ggf. durch Retry-After überschrieben).
  final List<Duration> retries;

  /// Optionales, dezentes Logger-Callback.
  final void Function(String message)? onLog;

  /// Connection-Timeout (Socket-Ebene).
  final Duration connectionTimeout;

  /// Nützlich für configureHttp(... baseUrl: ...)
  String get baseUrlStr => _baseUrl.toString();

  /// Erfüllt die HttpInvoker-Signatur, die `GuidanceService` erwartet.
  Future<Map<String, dynamic>> call(String path, Map<String, dynamic> body) async {
    return _send('POST', path, body);
  }

  // ------------------------------------------------------------
  // Health-Check (optional)
  // ------------------------------------------------------------

  /// GET /health → true, wenn Worker erreichbar/ok.
  Future<bool> health() async {
    try {
      final uri = _resolve('/health');
      final headers = await _buildHeaders(null);
      final req = await _openRequest('GET', uri, headers, reqId: _reqId());
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode >= 400) return false;

      final text = await resp.transform(utf8.decoder).join();
      final ct = resp.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (ct.toLowerCase().contains('json')) {
        final obj = _tryDecodeJson(text);
        if (obj is Map && (obj['ok'] == true || obj['status'] == 'ok')) return true;
      }
      return text.trim().toLowerCase() == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------
  // Core HTTP
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path);
    final effectiveHeaders = await _buildHeaders(headers);
    final reqId = _reqId();

    _log('[HTTP] $method ${_short(uri)} (id=$reqId)');

    int attempt = 0;
    while (true) {
      attempt++;
      final sw = Stopwatch()..start();
      try {
        final req = await _openRequest(method, uri, effectiveHeaders, reqId: reqId);

        // Body schreiben (JSON) — nur wenn vorhanden
        if (body != null) {
          final jsonStr = jsonEncode(body);
          req.add(utf8.encode(jsonStr));
        }

        final resp = await req.close().timeout(requestTimeout);

        final status = resp.statusCode;
        final rawText = await resp.transform(utf8.decoder).join();
        final contentType = resp.headers.value(HttpHeaders.contentTypeHeader) ?? '';
        sw.stop();

        if (_isOk(status)) {
          // Erfolgsfall → tolerant parsen
          final parsed = _decodeByContentType(rawText, contentType);
          _log('[HTTP] $status OK ${_short(uri)} in ${sw.elapsed.inMilliseconds}ms (id=$reqId)');
          return _normalizeJson(parsed);
        }

        // Fehlerfall → ggf. retry
        if (_isRetryable(status) && attempt <= retries.length + 1) {
          final wait = _retryDelay(resp, attempt - 1);
          _log('[HTTP] $status RETRY in ${wait.inMilliseconds}ms ${_short(uri)} '
               '(${sw.elapsed.inMilliseconds}ms) (id=$reqId)');
          await Future.delayed(wait);
          continue;
        }

        // Letzter Fehler ohne weiteren Retry
        final parsed = _tryDecodeJson(rawText);
        _log('[HTTP] $status FAIL ${_short(uri)} in ${sw.elapsed.inMilliseconds}ms (id=$reqId)');
        throw ApiClientException(status, 'HTTP $status', uri, parsed);
      } on TimeoutException catch (_) {
        sw.stop();
        if (attempt <= retries.length + 1) {
          final wait = _jitter(_retryBaseFor(attempt - 1));
          _log('[HTTP] TIMEOUT RETRY in ${wait.inMilliseconds}ms ${_short(uri)} '
               '(${sw.elapsed.inMilliseconds}ms) (id=$reqId)');
          await Future.delayed(wait);
          continue;
        }
        _log('[HTTP] TIMEOUT ${_short(uri)} after ${sw.elapsed.inMilliseconds}ms (id=$reqId)');
        throw ApiClientException(408, 'Request Timeout', uri, null);
      } on SocketException catch (e) {
        sw.stop();
        if (attempt <= retries.length + 1) {
          final wait = _jitter(_retryBaseFor(attempt - 1));
          _log('[HTTP] NETWORK ${e.osError?.errorCode ?? ''} RETRY in ${wait.inMilliseconds}ms '
               '${_short(uri)} (${sw.elapsed.inMilliseconds}ms) (id=$reqId)');
          await Future.delayed(wait);
          continue;
        }
        _log('[HTTP] NETWORK FAIL ${_short(uri)} after ${sw.elapsed.inMilliseconds}ms (id=$reqId)');
        throw ApiClientException(-1, 'Network error: ${e.message}', uri, null);
      } catch (err) {
        sw.stop();
        _log('[HTTP] EXCEPTION ${_short(uri)} after ${sw.elapsed.inMilliseconds}ms (id=$reqId): ${err.runtimeType}');
        rethrow;
      }
    }
  }

  Duration _retryBaseFor(int idx) {
    return retries[idx < retries.length ? idx : retries.length - 1];
  }

  Future<HttpClientRequest> _openRequest(
    String method,
    Uri uri,
    Map<String, String> headers, {
    required String reqId,
  }) async {
    late HttpClientRequest request;
    switch (method.toUpperCase()) {
      case 'POST':
        request = await _http.postUrl(uri);
        break;
      case 'GET':
        request = await _http.getUrl(uri);
        break;
      case 'PUT':
        request = await _http.putUrl(uri);
        break;
      case 'PATCH':
        request = await _http.patchUrl(uri);
        break;
      case 'DELETE':
        request = await _http.deleteUrl(uri);
        break;
      default:
        request = await _http.openUrl(method, uri);
    }

    // Eindeutig setzen (keine doppelten Standard-Header)
    headers.forEach((k, v) => request.headers.set(k, v));
    // Zusätzliche Tracking-Header
    request.headers.set('X-Request-Id', reqId);
    request.headers.set('X-Request-At', DateTime.now().toUtc().toIso8601String());

    return request;
  }

  Uri _resolve(String path) {
    // Akzeptiert 'path' mit oder ohne führenden Slash
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return _baseUrl.resolve(clean);
  }

  Future<Map<String, String>> _buildHeaders(Map<String, String>? extra) async {
    final token = await tokenProvider?.call();

    // Basis-Header; werden von [extra]/[staticHeaders] überschrieben (intentional)
    final base = <String, String>{
      HttpHeaders.acceptHeader:
          'application/json, application/problem+json;q=0.95, text/plain;q=0.9, */*;q=0.8',
      HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      HttpHeaders.acceptLanguageHeader: 'de',
      HttpHeaders.userAgentHeader: 'Zen/6 (api_client.dart)',
      HttpHeaders.acceptEncodingHeader: 'gzip', // Antworten gzip-gekapselt
      if (token != null && token.trim().isNotEmpty)
        HttpHeaders.authorizationHeader: 'Bearer ${token.trim()}',
    };

    // Merge-Reihenfolge: base < staticHeaders < extra
    final merged = <String, String>{}
      ..addAll(base)
      ..addAll(staticHeaders)
      ..addAll(extra ?? const {});

    // Trim einfache Whitespace-Ausreißer
    merged.updateAll((key, value) => value.trim());

    return merged;
  }

  bool _isOk(int status) => status >= 200 && status < 300;

  bool _isRetryable(int status) =>
      status == 429 || status == 408 || (status >= 500 && status < 600);

  Duration _retryDelay(HttpClientResponse resp, int retryIndex) {
    // 1) Retry-After beachten (Sekunden ODER HTTP-Date-Format)
    final ra = resp.headers.value('retry-after');
    if (ra != null) {
      final secs = int.tryParse(ra.trim());
      if (secs != null && secs >= 0) {
        return _jitter(Duration(seconds: secs));
      }
      // HTTP-date
      try {
        final when = HttpDate.parse(ra);
        final delta = when.difference(DateTime.now());
        if (delta.inMilliseconds > 0) return _jitter(delta);
      } catch (_) {/* ignore */}
    }
    // 2) Sonst Staffel nutzen
    return _jitter(_retryBaseFor(retryIndex));
  }

  Duration _jitter(Duration base) {
    // +/- 20% Jitter (deterministisch per Zeit)
    final ms = base.inMilliseconds;
    if (ms <= 0) return Duration.zero;
    final delta = (ms * 0.2).round();
    final now = DateTime.now().microsecondsSinceEpoch;
    final sign = (now & 1) == 0 ? 1 : -1;
    final offset = now % (delta + 1);
    final jittered = ms + sign * offset;
    final clamped = jittered.clamp(0, ms + delta);
    return Duration(milliseconds: clamped);
  }

  dynamic _decodeByContentType(String body, String contentType) {
    final lower = (contentType).toLowerCase();
    if (lower.contains('application/json') || lower.contains('application/problem+json')) {
      return _tryDecodeJson(body);
    }
    // text/plain oder unbekannt → als "output_text" für Guidance-Parsing
    final trimmed = body.toString();
    if (trimmed.trim().isEmpty) return <String, dynamic>{};
    return <String, dynamic>{'output_text': trimmed};
  }

  dynamic _tryDecodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      // Notfalls als raw zurückgeben (Service kann {raw:"..."} ebenfalls handhaben)
      return {'raw': text};
    }
  }

  Map<String, dynamic> _normalizeJson(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      // Map mit non-string Keys tolerant in String-Keys wandeln
      final out = <String, dynamic>{};
      v.forEach((k, val) => out['$k'] = val);
      return out;
    }
    if (v is List) return {'data': v};
    if (v == null) return <String, dynamic>{};
    return {'value': v};
  }

  String _short(Uri uri) {
    final s = uri.toString();
    return s.length <= 100 ? s : '${s.substring(0, 97)}…';
  }

  String _reqId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = (t.hashCode ^ _baseUrl.host.hashCode).toRadixString(36);
    return 'zen-$t-$r';
  }

  void _log(String msg) {
    onLog?.call(_redactForLog(msg));
  }

  /// PII-Reduktion für Logs (sanft).
  String _redactForLog(String s) {
    var out = s;
    // E-Mail
    out = out.replaceAll(
      RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
      '[E-Mail]',
    );
    // Telefonnummern
    out = out.replaceAll(RegExp(r'(\+?\d[\d\s\-\(\)]{6,}\d)'), '[Telefon]');
    // URLs
    out = out.replaceAll(RegExp(r'(https?:\/\/|www\.)\S+', caseSensitive: false), '[Link]');
    // IBAN
    out = out.replaceAll(RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b'), '[IBAN]');
    // Kreditkarten
    out = out.replaceAll(RegExp(r'\b(?:\d[ \-]*?){13,19}\b'), '[Karte]');
    return out;
  }

  /// Optionale Aufräumroutine (z. B. beim App-Shutdown).
  void close() {
    _http.close(force: true);
  }
}

class ApiClientException implements IOException {
  final int statusCode; // -1 Netzfehler, sonst HTTP
  final String message;
  final Uri uri;
  final dynamic body; // evtl. geparstes JSON/Fehlerdetails

  ApiClientException(this.statusCode, this.message, this.uri, this.body);

  @override
  String toString() =>
      'ApiClientException($statusCode) $message @ ${uri.toString()}';
}
