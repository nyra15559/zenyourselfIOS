// lib/services/community/community_stats_api.dart
//
// CommunityStatsApi — globaler „Panda hat geholfen“-Zähler (v1.0 · fixed)
// -----------------------------------------------------------------------------
// – Fix: keine doppelten Bezeichner (helpTotal/conversationsTotal).
// – Fix: Null-Coalescing (??) statt || beim Parsen.
// – Getrennte Extractor-Methoden für Help und Conversations.
// – Sanftes TTL-Caching + ETag/Last-Modified.
//

library community_stats_api;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, ContentType;
import 'package:flutter/foundation.dart' show debugPrint;

/// Interne Path-Konstanten (einheitlich & konfliktfrei)
class _Paths {
  static const helpTotal = '/v1/community/help-total';
  static const conversationsTotal = '/v1/community/conversations-total';
}

/// Request-Invoker (für Web/Mocks austauschbar).
typedef InvokeFn = Future<_InvokeResponse> Function(_InvokeRequest req);

class CommunityStatsApi {
  CommunityStatsApi._();
  static final CommunityStatsApi instance = CommunityStatsApi._();

  String _baseUrl = 'https://community.zenyourself.app';
  Duration _timeout = const Duration(seconds: 8);
  Duration _ttl = const Duration(minutes: 2);
  InvokeFn? _invokeOverride;

  Map<String, String> _extraHeaders = const {
    'X-Client': 'ZenYourself/CommunityStatsApi 1.0',
  };

  int? _cachedValue;
  DateTime? _cachedAt;
  String? _etag;
  String? _lastModified;

  void configure({
    String? baseUrl,
    Duration? timeout,
    Duration? ttl,
    InvokeFn? invokeOverride,
    Map<String, String>? extraHeaders,
  }) {
    if (baseUrl != null && baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (timeout != null) _timeout = timeout;
    if (ttl != null) _ttl = ttl;
    if (invokeOverride != null) _invokeOverride = invokeOverride;
    if (extraHeaders != null) _extraHeaders = Map<String, String>.from(extraHeaders);
  }

  /// Lädt den globalen Help-Zähler. `null` bei Fehlern.
  Future<int?> fetchGlobalHelpTotal({
    bool forceRefresh = false,
    String path = _Paths.helpTotal,
    Map<String, String>? headers,
  }) async {
    return _fetchGenericTotal(
      extract: _extractHelpCount,
      forceRefresh: forceRefresh,
      path: path,
      headers: headers,
    );
  }

  /// Optional: Conversations/Chats-Zähler (falls du ihn verwenden willst)
  Future<int?> fetchGlobalConversationsTotal({
    bool forceRefresh = false,
    String path = _Paths.conversationsTotal,
    Map<String, String>? headers,
  }) async {
    return _fetchGenericTotal(
      extract: _extractConversationsCount,
      forceRefresh: forceRefresh,
      path: path,
      headers: headers,
    );
  }

  /// Setzt den in-Memory-Cache bewusst (z. B. nach lokalem Inkrement in der UI).
  void seedCache(int value, {String path = _Paths.helpTotal}) {
    _cachedValue = value;
    _cachedAt = DateTime.now();
  }

  void clearCache() {
    _cachedValue = null;
    _cachedAt = null;
    _etag = null;
    _lastModified = null;
  }

  // ───────────────────────── Interna ─────────────────────────

  Future<int?> _fetchGenericTotal({
    required int? Function(Map<String, dynamic>?) extract,
    required bool forceRefresh,
    required String path,
    Map<String, String>? headers,
  }) async {
    try {
      if (!forceRefresh && _cachedValue != null && _cachedAt != null) {
        final age = DateTime.now().difference(_cachedAt!);
        if (age <= _ttl) return _cachedValue;
      }

      final url = Uri.parse('$_baseUrl$path');
      final h = <String, String>{
        'Accept': 'application/json',
        ..._extraHeaders,
        if (headers != null) ...headers,
      };
      if (_etag != null && _etag!.isNotEmpty) h['If-None-Match'] = _etag!;
      if (_lastModified != null && _lastModified!.isNotEmpty) h['If-Modified-Since'] = _lastModified!;

      final resp = await _invoke(_InvokeRequest(
        url: url,
        method: 'GET',
        headers: h,
        timeout: _timeout,
      ));

      if (resp.status == 304 && _cachedValue != null) {
        _touchCache();
        return _cachedValue;
      }

      if (resp.status < 200 || resp.status >= 300) {
        if (_cachedValue != null) {
          debugPrint('[CommunityStatsApi] HTTP ${resp.status}, liefere Cache.');
          _touchCache();
          return _cachedValue;
        }
        debugPrint('[CommunityStatsApi] Fehlerstatus: ${resp.status}');
        return null;
      }

      _etag = resp.headers['etag'] ?? _etag;
      _lastModified = resp.headers['last-modified'] ?? _lastModified;

      final v = resp.jsonOrNull;
      final extracted = extract(v);
      if (extracted == null) {
        debugPrint('[CommunityStatsApi] Konnte Zähler nicht extrahieren. Body: ${resp.bodyString}');
        return _cachedValue;
      }

      _cachedValue = extracted;
      _cachedAt = DateTime.now();
      return _cachedValue;
    } catch (e, st) {
      debugPrint('[CommunityStatsApi] Unerwarteter Fehler: $e\n$st');
      return _cachedValue;
    }
  }

  void _touchCache() {
    if (_cachedAt != null) _cachedAt = DateTime.now();
  }

  /// Extrahiert *help* Zähler aus tolerantem JSON
  int? _extractHelpCount(Map<String, dynamic>? j) {
    if (j == null) return null;

    int? tryNum(dynamic x) {
      if (x == null) return null;
      if (x is int) return x;
      if (x is double) return x.toInt();
      if (x is String) return int.tryParse(x.trim());
      return null;
    }

    // direkte Felder
    final direct = tryNum(j['help_total']) ?? tryNum(j['count']) ?? tryNum(j['total']);
    if (direct != null) return direct;

    // totals.help / totals.help_total
    final totals = j['totals'];
    if (totals is Map<String, dynamic>) {
      final nested = tryNum(totals['help']) ?? tryNum(totals['help_total']);
      if (nested != null) return nested;
    }

    // data.*
    final data = j['data'];
    if (data is Map<String, dynamic>) {
      final d = tryNum(data['help_total']) ?? tryNum(data['count']) ?? tryNum(data['total']);
      if (d != null) return d;
      final dt = data['totals'];
      if (dt is Map<String, dynamic>) {
        final n2 = tryNum(dt['help']) ?? tryNum(dt['help_total']);
        if (n2 != null) return n2;
      }
    }
    return null;
    }

  /// Extrahiert *conversations* Zähler aus tolerantem JSON
  int? _extractConversationsCount(Map<String, dynamic>? j) {
    if (j == null) return null;

    int? tryNum(dynamic x) {
      if (x == null) return null;
      if (x is int) return x;
      if (x is double) return x.toInt();
      if (x is String) return int.tryParse(x.trim());
      return null;
    }

    // direkte Felder
    final direct =
        tryNum(j['conversations_total']) ??
        tryNum(j['conversation_total']) ??
        tryNum(j['conversations']) ??
        tryNum(j['chats_total']) ??
        tryNum(j['talk_total']) ??
        tryNum(j['count']) ??
        tryNum(j['total']);
    if (direct != null) return direct;

    // totals.*
    final totals = j['totals'];
    if (totals is Map<String, dynamic>) {
      final nested =
          tryNum(totals['conversations']) ??
          tryNum(totals['conversations_total']) ??
          tryNum(totals['chats']) ??
          tryNum(totals['talks']);
      if (nested != null) return nested;
    }

    // data.*
    final data = j['data'];
    if (data is Map<String, dynamic>) {
      final d =
          tryNum(data['conversations_total']) ??
          tryNum(data['conversation_total']) ??
          tryNum(data['conversations']) ??
          tryNum(data['chats_total']) ??
          tryNum(data['talk_total']) ??
          tryNum(data['count']) ??
          tryNum(data['total']);
      if (d != null) return d;

      final dt = data['totals'];
      if (dt is Map<String, dynamic>) {
        final n2 =
            tryNum(dt['conversations']) ??
            tryNum(dt['conversations_total']) ??
            tryNum(dt['chats']) ??
            tryNum(dt['talks']);
        if (n2 != null) return n2;
      }
    }
    return null;
  }

  Future<_InvokeResponse> _invoke(_InvokeRequest req) async {
    if (_invokeOverride != null) {
      return _invokeOverride!(req).timeout(req.timeout, onTimeout: () {
        throw _NetTimeout('Zeitüberschreitung nach ${req.timeout.inSeconds}s.');
      });
    }

    final client = HttpClient()..connectionTimeout = req.timeout;
    try {
      final r = await client
          .openUrl(req.method, req.url)
          .timeout(req.timeout, onTimeout: () => throw _NetTimeout('Timeout beim Verbindungsaufbau.'));

      req.headers.forEach(r.headers.add);
      if (req.method != 'GET') {
        r.headers.contentType = ContentType.json;
      }
      if (req.bodyBytes != null && req.bodyBytes!.isNotEmpty) {
        r.add(req.bodyBytes!);
      }

      final res = await r.close().timeout(
        req.timeout,
        onTimeout: () => throw _NetTimeout('Timeout beim Lesen.'),
      );

      final bytes = await res.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
      final headers = <String, String>{};
      res.headers.forEach((name, values) {
        if (values.isNotEmpty) headers[name.toLowerCase()] = values.join(',');
      });

      return _InvokeResponse(status: res.statusCode, headers: headers, bodyBytes: bytes);
    } on _NetTimeout {
      rethrow;
    } catch (e) {
      throw _NetError('Netzwerkfehler: $e');
    } finally {
      client.close(force: true);
    }
  }
}

// ───────────────────── Transport (intern) ─────────────────────

class _InvokeRequest {
  final Uri url;
  final String method;
  final Map<String, String> headers;
  final List<int>? bodyBytes;
  final Duration timeout;

  const _InvokeRequest({
    required this.url,
    required this.method,
    required this.headers,
    required this.timeout,
    this.bodyBytes,
  });
}

class _InvokeResponse {
  final int status;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  const _InvokeResponse({required this.status, required this.headers, required this.bodyBytes});

  String get bodyString {
    try {
      return utf8.decode(bodyBytes);
    } catch (_) {
      return '';
    }
  }

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

class _NetError implements Exception {
  final String message;
  const _NetError(this.message);
  @override
  String toString() => message;
}

class _NetTimeout extends _NetError {
  const _NetTimeout(String msg) : super(msg);
}
