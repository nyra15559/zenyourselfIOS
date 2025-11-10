// [REVISED] lib/services/core/api_service.dart — Stand: 2025-11-10 — ZenYourself v6.7.4 (V7)
// MERGE SIGNAL (V7): next_turn_full primär; session.history (~20) mitsenden;
// Privacy-Gate: context.memories NUR bei consent && memoryActive (≤2048 B, Recall ≤240 B);
// Merge 644++: Server mergen nur wenn meta.flags.client_memory==true && meta.memory.bridge==true;
// Parser: answer_helpers(max3), flow.mood_prompt, risk_level, closure{hope_reply}, smalltalk_reply,
// memories_to_save[], Fragen/Helpers dedupliziert/normalisiert; ZIP-Core mit timeline (best-effort);
// HTTP: contact_tints + contact_tins (Alias), X-Thread-Id(header), Out-Soft-Gate (warmup) – offline tolerant.

library api_service;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder;
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../guidance/dtos.dart'
    show
        AnalyzeResult,
        Analysis,
        JourneyEntry,
        JourneyInsights,
        MoodResponse,
        ReflectionFlow,
        ReflectionSession,
        ReflectionTurn,
        StoryResult,
        StructuredThoughtResult,
        IfEmptyX,
        UserAction,
        TurnAnalysis;

import '../../data/reflection_entry.dart' as re hide Analysis;
import '../../models/question.dart';
import '../../core/memory/memory_service.dart';

// ---------------- Fallback-DTOs (lokal) ----------------
class ReflectionAIResult {
  final String reflection;
  final String depth; // 'light' | 'medium' | 'deep'
  final String riskFlag; // 'none' | 'support' | 'crisis'
  final List<String> tags;
  const ReflectionAIResult({
    required this.reflection,
    required this.depth,
    required this.riskFlag,
    required this.tags,
  });
}

class ZipCoreResult {
  final Uint8List bytes;
  final String filename;
  const ZipCoreResult({required this.bytes, required this.filename});
}

// 2–28 Zeichen, startet groß, keine typischen Zustandswörter
bool _looksLikeName(String s) {
  final base = RegExp(r"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-']{1,27}$");
  const bad = {'Müde','Traurig','Gestresst','Erschöpft','Okay','Ok','Nein','Ja','Einfach','Uund'};
  return base.hasMatch(s) && !bad.contains(s);
}

typedef HttpInvoker = Future<Map<String, dynamic>> Function(
  String path,
  Map<String, dynamic> body,
);

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final _rand = Random.secure();
  final _uuid = const Uuid();

  HttpInvoker? _http;
  String? _baseUrl;
  Duration _timeout = const Duration(seconds: 25);

  bool _outGateOpen = true;
  bool _outGatePrimed = false;

  static const String _brand = 'ZenYourself';
  static const String _channel = 'app';
  static const String _samfring = 'optional';
  static const String loadingHint = '$_brand zählt die Blümchen …';
  static const String errorHint   =
      'ZenYourself hat die Blümchen nicht gefunden. Bitte Verbindung prüfen.';

  // ---------------- Memory/Consent (best-effort) ----------------
  bool _memoryConsentDefault() {
    try {
      final dyn = MemoryService.instance;
      // ignore: avoid_dynamic_calls
      return dyn.shareEnabled == true;
    } catch (_) { return false; }
  }

  bool _memoryActiveNow() {
    try {
      final dyn = MemoryService.instance as dynamic;
      final v = (dyn.isActive ?? dyn.memoryActive ?? dyn.bridgeActive ?? dyn.active);
      if (v is bool) return v;
      if (v is Function) { final r = v(); if (r is bool) return r; }
    } catch (_) {}
    return false;
  }

  Map<String, dynamic> _setClientMemoryFlagOnBody(
    Map<String, dynamic> body, {required bool enabled}) {
    final meta  = Map<String, dynamic>.from((body['meta'] as Map?) ?? const {});
    final flags = Map<String, dynamic>.from((meta['flags'] as Map?) ?? const {});
    flags['client_memory'] = enabled;            // offizieller Schlüssel
    flags['client_memory_merge'] = enabled;      // Legacy-Alias
    meta['flags'] = flags;

    final memMeta = Map<String, dynamic>.from((meta['memory'] as Map?) ?? const {});
    memMeta['bridge'] = enabled;                 // Merge 644++ Partnerflag
    meta['memory'] = memMeta;

    body['meta'] = meta;
    return body;
  }

  void _saveUserTurnBestEffort(String text) {
    try { (MemoryService.instance as dynamic).saveUserTurn?.call(text); } catch (_) {}
  }

  void _invokeSaveIdentityName(dynamic mem, String name) {
    try {
      final fn = (mem as dynamic).saveIdentityName;
      if (fn is Function) {
        try { fn(name); return; } catch(_){}
        try { Function.apply(fn, [name], {#greetByName:true}); return; } catch(_){}
        try { fn(name, true); return; } catch (_){}
      }
    } catch (_) {}
  }

  void _maybeLearnName(String text) {
    try {
      final raw = text.trim(); if (raw.isEmpty) return;
      final m = RegExp(
        r"\b(ich heiße|ich heisse|mein name ist|nenn mich|man nennt mich)\s+([A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-\' ]+)",
        caseSensitive:false).firstMatch(raw);
      if (m == null) return;
      var seg = (m.group(2) ?? '').trim();
      seg = seg.split(RegExp(r'[.,;:!?]')).first.trim();
      final first = seg.split(RegExp(r'\s+')).first;
      if (_looksLikeName(first)) _invokeSaveIdentityName(MemoryService.instance, first);
    } catch (_) {}
  }

  String? _extractNameFromTextQuick(String text) {
    try {
      final raw = text.trim(); if (raw.isEmpty) return null;
      final m = RegExp(
        r"\b(ich heiße|ich heisse|mein name ist|nenn mich|man nennt mich|ich bin)\s+([A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-\' ]+)",
        caseSensitive:false).firstMatch(raw);
      if (m == null) return null;
      var seg = (m.group(2) ?? '').trim();
      seg = seg.split(RegExp(r'[.,;:!?]')).first.trim();
      final first = seg.split(RegExp(r'\s+')).first;
      return _looksLikeName(first) ? first : null;
    } catch (_) { return null; }
  }

  Map<String, dynamic> _ensureClientMemoryMergeFlag(
    Map<String, dynamic> body, {required bool consent}) {
    if (!consent) return body;
    final meta  = Map<String, dynamic>.from((body['meta'] as Map?) ?? const {});
    final flags = Map<String, dynamic>.from((meta['flags'] as Map?) ?? const {});
    flags['client_memory'] = true;
    flags['client_memory_merge'] ??= true;
    meta['flags'] = flags;
    body['meta'] = meta;
    return body;
  }

  // ---------------- Recall (nur 🍃/🌿, Byte-Guard) ----------------
  String _flattenWs(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _utf8Truncate(String s, int maxBytes) {
    if (maxBytes <= 0) return '';
    final bytes = utf8.encode(s);
    if (bytes.length <= maxBytes) return s;
    final b = StringBuffer(); var used = 0;
    for (final r in s.runes) {
      final c = utf8.encode(String.fromCharCode(r));
      if (used + c.length > maxBytes) break;
      b.writeCharCode(r); used += c.length;
    }
    final out = b.toString().trimRight();
    return out.isEmpty ? '' : (out.endsWith('…') ? out : '$out…');
  }

  String? _recallFromService({required bool consent}) {
    if (!consent) return null;
    try {
      final ms = MemoryService.instance as dynamic;
      dynamic r;
      try { r = ms.buildRecall?.call(consent: true); } catch (_){}
      r ??= (() { try { return ms.buildRecall?.call(); } catch(_){ } return null; })();
      r ??= (() { try { return ms.recall?.call(); }       catch(_){ } return null; })();
      r ??= (() { try { return ms.getRecall?.call(); }    catch(_){ } return null; })();
      if (r == null) return null;
      if (r is String) return r;
      if (r is Map) {
        final m = r.cast<String, dynamic>();
        final s = (m['text'] ?? m['summary'] ?? m['recall'] ?? '').toString();
        return s.trim().isEmpty ? null : s;
      }
      if (r is List) {
        final parts = r.where((e) => e != null).map((e) => e.toString().trim())
                       .where((e) => e.isNotEmpty).take(4).toList();
        return parts.isEmpty ? null : parts.join(' · ');
      }
    } catch (_) {}
    return null;
  }

  String? _composeRecallFromMem(Map<String, dynamic> mem) {
    final id = (mem['identity'] as Map?) ?? const {};
    final last = (mem['last'] as Map?) ?? const {};
    final String? name = (id['name']?.toString().trim().isEmpty ?? true) ? null : id['name'].toString().trim();
    final int? mood     = (last['mood'] is num) ? (last['mood'] as num).toInt() : int.tryParse('${last['mood'] ?? ''}');
    final String? moodL = (mood == null) ? null : _labelFromScore(mood);
    final String? emotion = ((last['emotion'] ?? '').toString().trim().isEmpty) ? null : last['emotion'].toString().trim();
    final String? topic   = ((last['topic']   ?? '').toString().trim().isEmpty) ? null : last['topic'  ].toString().trim();
    final String? date    = ((last['date']    ?? '').toString().trim().isEmpty) ? null : last['date'   ].toString().trim();

    final parts = <String>[];
    if (emotion != null) parts.add(emotion);
    if (moodL   != null) parts.add(moodL);
    if (topic   != null) parts.add('Thema: $topic');
    if (date    != null) parts.add(date);

    if (parts.isEmpty) return null;
    final body = parts.join(' · ');
    return (name != null && name.isNotEmpty) ? '$name — $body' : body;
  }

  String? _buildRecallSafe({required bool consent, required Map<String, dynamic> mem, int maxBytes = 240}) {
    if (!consent) return null;
    String? raw = _recallFromService(consent: consent);
    raw ??= _composeRecallFromMem(mem);
    if (raw == null || raw.trim().isEmpty) return null;
    String clean = _flattenWs(_redactPII(raw));
    clean = _utf8Truncate(clean, maxBytes);
    return clean.isEmpty ? null : clean;
  }

  // ---------------- Konfiguration / HTTP-Adapter ----------------
  void configureHttp({HttpInvoker? invoker, String? baseUrl, Duration? timeout}) {
    _http = invoker;
    if (baseUrl != null && baseUrl.trim().isNotEmpty) _baseUrl = _normalizeBase(baseUrl);
    if (timeout != null) _timeout = timeout;
    _primeMemory();
    _primeOutSoftGate();
  }

  void configureForWorker({
    required String baseUrl,
    String? appToken,
    Duration timeout = const Duration(seconds: 25),
  }) {
    _baseUrl = _normalizeBase(baseUrl);
    _timeout = timeout;
    _primeMemory();
    _primeOutSoftGate();

    _http = (String path, Map<String, dynamic> body) async {
      final uri = _join(_baseUrl!, path);
      final headers = <String, String>{
        if (appToken != null && appToken.trim().isNotEmpty) 'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json, application/problem+json;q=0.95, text/plain;q=0.9, */*;q=0.8',
        'X-App-Brand': _brand,
        'X-App-Channel': _channel,
        'X-Samfring': _samfring,
        'X-Out-Gate': _outGateOpen ? 'open' : 'warmup',
      };

      // Thread-Id → Header
      try {
        final sid = (body['session'] as Map?)?['id'];
        if (sid != null) headers['X-Thread-Id'] = sid.toString();
      } catch (_) {}

      final enriched = Map<String, dynamic>.from(body);

      // contact_tints + contact_tins (Alias)
      final _tints = {
        'brand': _brand,
        'channel': _channel,
        'samfring': _samfring,
        'locale': (body['locale'] ?? 'de').toString(),
        'tz': (body['tz'] ?? 'Europe/Zurich').toString(),
      };
      enriched.putIfAbsent('contact_tints', () => Map<String, dynamic>.from(_tints));
      enriched.putIfAbsent('contact_tins',  () => Map<String, dynamic>.from(_tints));

      _appendByteContext(enriched);

      // -------- Memory-Bridge Guard (Server-Adapter) --------
      bool consent = false;
      bool active  = false;
      try {
        consent = (enriched['memory_consent'] == true) ||
                  (((enriched['context'] as Map?)?['memory_consent']) == true);
        active  = _memoryActiveNow();

        final hasCtx = (enriched['context'] is Map);
        final Map<String, dynamic> ctx = hasCtx
            ? Map<String, dynamic>.from(enriched['context'] as Map)
            : <String, dynamic>{};
        final bool hasMemoriesAlready =
            (ctx['memories'] is Map) || (enriched['memories'] is Map);

        if (consent && active && !hasMemoriesAlready) {
          final memSvc = MemoryService.instance;
          Map<String, dynamic> mem = <String, dynamic>{};
          try {
            final dyn = (memSvc as dynamic).buildContextMemories;
            if (dyn is Function) {
              final out = await Function.apply(dyn, const [], const {#consent: true});
              if (out is Map) mem = out.map((k, v) => MapEntry(k.toString(), v));
            }
          } catch (_) {}

          // Quick-Inject Name/Mood/Emotion/Date
          final textRaw = (enriched['text'] ?? '').toString();
          final qn = _extractNameFromTextQuick(textRaw);
          if (qn != null && qn.isNotEmpty) {
            final id = Map<String, dynamic>.from((mem['identity'] as Map?) ?? const {});
            id['name'] = qn; mem['identity'] = id;
          }
          final lastMap = Map<String, dynamic>.from((mem['last'] as Map?) ?? const {});
          lastMap['mood'] ??= classifyMoodSync(textRaw);
          final emo = detectEmotionSync(textRaw);
          if (emo != null && (lastMap['emotion'] == null)) lastMap['emotion'] = emo;
          lastMap['date'] ??= DateTime.now().toUtc().toIso8601String().split('T').first;
          if (lastMap.isNotEmpty) mem['last'] = lastMap;

          // Recall ≤240 B
          final recall = _buildRecallSafe(consent: consent, mem: mem, maxBytes: 240);
          if (recall != null && recall.isNotEmpty) mem['recall'] = recall;

          if (mem.isNotEmpty) {
            final capped = _capMemoriesSize(mem, maxBytes: 2048);
            if (capped != null && capped.isNotEmpty) {
              final Map<String, dynamic> cappedMap = Map<String, dynamic>.from(capped as Map);
              ctx['memories'] = cappedMap;
              enriched['context']  = ctx;
              enriched['memories'] = Map<String, dynamic>.from(cappedMap); // Legacy
            }
          }
        }

        // Merge-Flags 644++
        _ensureClientMemoryMergeFlag(enriched, consent: consent);
        _setClientMemoryFlagOnBody(enriched, enabled: consent && active);

        // Deaktiviert → niemals Memories mitsenden
        if (!active || !consent) {
          if (enriched['context'] is Map) (enriched['context'] as Map).remove('memories');
          enriched.remove('memories');
        }
      } catch (_) {}

      if (!_outGateOpen && !_isHealthPath(path)) {
        final jitter = 90 + _rand.nextInt(90);
        await Future.delayed(Duration(milliseconds: jitter));
      }

      final res = await http.post(uri, headers: headers, body: jsonEncode(enriched))
                            .timeout(_timeout);

      if (res.statusCode >= 400) { throw Exception('Worker ${res.statusCode}: ${res.body}'); }

      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('json')) {
        try {
          final parsed = jsonDecode(res.body);
          if (parsed is Map<String, dynamic>) return parsed;
          return <String, dynamic>{'output_text': parsed.toString()};
        } catch (_) {
          return <String, dynamic>{'output_text': _decodeBody(res)};
        }
      }
      return <String, dynamic>{'output_text': _decodeBody(res)};
    };
  }

  void _primeOutSoftGate() {
    if (_outGatePrimed) return;
    _outGatePrimed = true; _outGateOpen = false;
    unawaited(() async {
      final ms = 120 + _rand.nextInt(80);
      await Future.delayed(Duration(milliseconds: ms));
      unawaited(healthCheck().then((_){}));
      _outGateOpen = true;
    }());
  }

  void _primeMemory() {
    try {
      final m = MemoryService.instance; final dyn = m as dynamic;
      unawaited(() async {
        try { await (dyn.warmup?.call()); } catch (_){}
        try { dyn.preload?.call(); } catch (_){}
      }());
    } catch (_) {}
  }

  static bool _isHealthPath(String path) {
    final p = path.trim().toLowerCase();
    return p == '/health' || p.endsWith('/health');
  }

  static String _normalizeBase(String base) {
    var b = base.trim(); b = b.replaceAll(RegExp(r'/+$'), '');
    return b.isEmpty ? base : b;
  }

  static Uri _join(String base, String path) {
    final p = path.trim().isEmpty ? '' : (path.startsWith('/') ? path : '/$path');
    return Uri.parse('$base$p');
  }

  static String _decodeBody(http.Response res) {
    try { return utf8.decode(res.bodyBytes); } catch (_) { return res.body.toString(); }
  }

  // ---------------- Health ----------------
  Future<bool> healthCheck() async {
    final base = _baseUrl; if (base == null || base.trim().isEmpty) return false;
    try {
      final uri = _join(base, '/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode >= 400) return false;
      final body = res.body.trim();
      if (body.toLowerCase() == 'ok') return true;
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('json')) {
        final json = jsonDecode(body);
        if (json is Map && (json['ok'] == true ||
            json['status']?.toString().toLowerCase() == 'ok')) return true;
      }
      return true;
    } catch (_) { return false; }
  }

  // ---------------- Session API ----------------
  ReflectionSession maybeResetThreadOnPrivacyChange({
    required bool privacyEnabled,
    required ReflectionSession session,
    bool forceReset = false,
  }) {
    if (forceReset || !privacyEnabled) {
      return session.copyWith(threadId: _uuid.v4(), turnIndex: 0);
    }
    return session;
  }

  Future<ReflectionTurn> startSession({
    String? text,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    final input = (text ?? userText ?? '').trim();
    final session = ReflectionSession(threadId: _uuid.v4(), turnIndex: 0, maxTurns: max(2, min(6, maxTurns)));
    return _reflectStep(
      text: input, session: session, locale: locale, tz: tz,
      history: history ?? const [], userAction: userAction, clientContext: clientContext,
    );
  }

  Future<ReflectionTurn> startSessionFull({
    required String text,
    ReflectionSession? session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    int maxTurns = 3,
    List<Map<String, String>>? history,
    dynamic memories,
    bool memoryConsent = false,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    final s = session ?? ReflectionSession(threadId: _uuid.v4(), turnIndex: 0, maxTurns: max(2, min(6, maxTurns)));
    return _reflectFullStep(
      text: text.trim(), session: s, locale: locale, tz: tz,
      history: history ?? const [], memories: memories, memoryConsent: memoryConsent,
      userAction: userAction, clientContext: clientContext,
    );
  }

  /// @deprecated – Kompat-Wrapper (bevorzugt next_turn_full)
  Future<ReflectionTurn> reflectFull({
    required String text,
    required ReflectionSession session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories,
    bool memoryConsent = false,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    if (_http == null) return _errorTurn(session);

    final payload = _basePayload(
      text: text.trim(), locale: locale, tz: tz, session: session,
      messages: history ?? const [], userAction: userAction, clientContext: clientContext,
    );
    _attachMemories(payload, memories: memories, memoryConsent: memoryConsent);

    final json = await _tryEndpoints(
      endpoints: const ['/next_turn_full', '/reflect_full', '/reflect'],
      payload: payload,
    );
    if (json == null) return _errorTurn(session);
    return _turnFromReflectAny(json, session);
  }

  Future<ReflectionTurn> continueSession({
    required ReflectionSession session,
    String? text,
    String? userText,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    final input = (text ?? userText ?? '').trim();
    final next = session.copyWith(turnIndex: session.turnIndex + 1);
    return _reflectStep(
      text: input, session: next, locale: locale, tz: tz,
      history: history ?? const [], userAction: userAction, clientContext: clientContext,
    );
  }

  Future<ReflectionTurn> nextTurnFull({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    dynamic memories,
    bool? memoryConsent,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    if (_http == null) return _errorTurn(session);
    final next = session.copyWith(turnIndex: session.turnIndex + 1);

    final payload = _basePayload(
      text: text.trim(), locale: locale, tz: tz, session: next,
      messages: history ?? const [], userAction: userAction, clientContext: clientContext,
    );
    if (memories != null || memoryConsent != null) {
      _attachMemories(payload, memories: memories, memoryConsent: memoryConsent ?? false);
    }

    final json = await _tryEndpoints(
      endpoints: const ['/next_turn_full', '/reflect_full', '/reflect'],
      payload: payload,
    );
    if (json == null) return _errorTurn(next);
    return _turnFromReflectAny(json, next);
  }

  Future<ReflectionTurn> sendNextTurnFull({
    required ReflectionSession session,
    required String userText,
    required List<Map<String, String>> history,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    dynamic memories,
    bool? memoryConsent,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) {
    final cappedHistory  = _capHistory(history, maxTurns: 20);
    final cappedMemories = _capMemoriesSize(memories, maxBytes: 2048);
    return nextTurnFull(
      session: session, text: userText, locale: locale, tz: tz,
      history: cappedHistory, memories: cappedMemories,
      memoryConsent: memoryConsent, userAction: userAction, clientContext: clientContext,
    );
  }

  Future<ReflectionTurn> nextTurnAction({
    required ReflectionSession session,
    required UserAction action,
    String locale = 'de',
    String tz = 'Europe/Zurich',
  }) async {
    if (_http == null) return _errorTurn(session);
    final next = session.copyWith(turnIndex: session.turnIndex + 1);

    final payload = _basePayload(
      text: '', locale: locale, tz: tz, session: next,
      messages: const [], userAction: action, clientContext: null,
    );

    final json = await _tryEndpoints(
      endpoints: const ['/next_turn_action', '/next_turn_full', '/reflect_full', '/reflect'],
      payload: payload,
    );
    if (json == null) return _errorTurn(next);
    return _turnFromReflectAny(json, next);
  }

  Future<ReflectionTurn> nextTurn({
    required ReflectionSession session,
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<Map<String, String>>? history,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) => continueSession(
        session: session, text: text, locale: locale, tz: tz,
        history: history, userAction: userAction, clientContext: clientContext,
      );

  Future<ReflectionSession> endSession(ReflectionSession s) async => s;

  // ---------------- closure_full ----------------
  Future<Map<String, dynamic>> closureFull({
    required ReflectionSession? session,
    required String answer,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    if (_http == null) return _closureFallback(session);

    final payload = <String, dynamic>{
      'answer': answer.trim(),
      'text':   answer.trim(),
      'locale': locale,
      'tz': tz,
      'session': session == null ? null : _buildSessionMap(session, history: const []),
      'intent': 'closure',
      if (userAction != null) 'user_action': userAction.toJson(),
      if (clientContext != null && clientContext.isNotEmpty)
        'client_context': _sanitizeClientContext(clientContext),
    };
    payload['memory_consent'] ??= _memoryConsentDefault();

    _mergeExtraMetaFromClientContext(payload, clientContext);
    _appendMemoryHints(payload);
    _appendContactTints(payload, locale: locale, tz: tz);
    _appendByteContext(payload);
    _ensureClientMemoryMergeFlag(payload, consent: payload['memory_consent'] == true);
    _setClientMemoryFlagOnBody(payload,
        enabled: (payload['memory_consent'] == true) && _memoryActiveNow());

    final json = await _postMaybe('/closure_full', payload, saveSource: 'closure_full');
    return json ?? _closureFallback(session);
  }

  Future<ReflectionTurn> _reflectStep({
    required String text,
    required ReflectionSession session,
    required String locale,
    required String tz,
    required List<Map<String, String>> history,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    if (_http == null) return _errorTurn(session);
    final payload = _basePayload(
      text: text, locale: locale, tz: tz, session: session,
      messages: history, userAction: userAction, clientContext: clientContext,
    );
    final json = await _tryEndpoints(endpoints: const ['/reflect'], payload: payload);
    if (json == null) return _errorTurn(session);
    return _turnFromReflectAny(json, session);
  }

  Future<ReflectionTurn> _reflectFullStep({
    required String text,
    required ReflectionSession session,
    required String locale,
    required String tz,
    required List<Map<String, String>> history,
    dynamic memories,
    bool memoryConsent = false,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    if (_http == null) return _errorTurn(session);
    final payload = _basePayload(
      text: text, locale: locale, tz: tz, session: session,
      messages: history, userAction: userAction, clientContext: clientContext,
    );
    _attachMemories(payload, memories: memories, memoryConsent: memoryConsent);

    final json = await _tryEndpoints(
      endpoints: const ['/next_turn_full', '/reflect_full', '/reflect'],
      payload: payload,
    );
    if (json == null) return _errorTurn(session);
    return _turnFromReflectAny(json, session);
  }

  Future<ReflectionTurn> talk({
    required ReflectionSession session,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    String? userText,
    List<Map<String, String>>? history,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) async {
    if (_http == null) {
      return const ReflectionTurn(
        outputText: '',
        mirror: null,
        context: [],
        followups: [],
        answerHelpers: [],
        helperSuggestion: null,
        flow: ReflectionFlow(recommendEnd: false, suggestBreak: false, talkOnly: true, allowReflect: true),
        session: ReflectionSession(threadId: 'local', turnIndex: 0, maxTurns: 3),
        tags: [],
        riskFlag: 'none',
        questions: [],
        talk: ['Das darf hier ganz in Ruhe Platz haben.','Nimm dir einen Augenblick für das, was wichtig ist.'],
      );
    }

    final payload = _basePayload(
      text: (userText ?? '').trim(), locale: locale, tz: tz,
      session: session.copyWith(turnIndex: session.turnIndex + 1),
      intent: 'talk', messages: history ?? const [],
      userAction: userAction, clientContext: clientContext,
    );

    try {
      final json = await _tryEndpoints(
        endpoints: const ['/next_turn_full', '/reflect_full', '/reflect'],
        payload: payload,
      );
      if (json == null) throw Exception('no json');
      return _turnFromReflectJson(json, session);
    } catch (_) {
      return const ReflectionTurn(
        outputText: '',
        mirror: null,
        context: [],
        followups: [],
        answerHelpers: [],
        helperSuggestion: null,
        flow: ReflectionFlow(recommendEnd: false, suggestBreak: false, talkOnly: true, allowReflect: true),
        session: ReflectionSession(threadId: 'local', turnIndex: 0, maxTurns: 3),
        tags: [],
        riskFlag: 'none',
        questions: [],
        talk: ['Ich bin hier bei dir.'],
      );
    }
  }

  ReflectionTurn _errorTurn(ReflectionSession session) => ReflectionTurn(
    outputText: errorHint,
    mirror: null,
    context: const [],
    followups: const [],
    answerHelpers: const [],
    helperSuggestion: null,
    flow: const ReflectionFlow(recommendEnd: false, suggestBreak: false),
    session: session,
    tags: const [],
    riskFlag: 'none',
    questions: const [],
  );

  // ---------------- analyze() (V7-tolerant) ----------------
  Future<AnalyzeResult> analyze({
    required String mode, // 'voice'|'text'
    required String text,
    int? durationSec,
    List<int>? recentMoods,
    int? streak,
    bool useServerIfAvailable = true,
  }) async {
    if (_http == null) {
      const analysis = Analysis(sorc: null, levers: [], mirror: null, question: null, riskLevel: 'none');
      return const AnalyzeResult(analysis: analysis, challenge: null);
    }

    final payload = <String, dynamic>{
      'text': text,
      'messages': [{'role': 'user', 'content': text}],
      'locale': 'de',
      'tz': 'Europe/Zurich',
      'session': {'id': _uuid.v4(), 'turn': 0, 'max_turns': 3, 'history': [{'role':'user','content':text}]},
      'intent': 'analyze',
      if (durationSec != null) 'duration_sec': durationSec,
      if (recentMoods != null) 'recent_moods': recentMoods,
      if (streak != null) 'streak': streak,
      'mode': mode,
    };
    _appendMemoryHints(payload);
    _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
    _appendByteContext(payload);

    try {
      final json = await _postMaybe('/reflect_full', payload, saveSource: 'reflect_full')
          .timeout(_timeout);
      if (json == null) throw Exception('no json');

      final qsList = _parseStringList(json['questions'] ?? json['qs'] ?? json['multi_questions']);
      final joined  = _normalizeQuestions(qsList);

      final rawPrimary = _extractPrimary(json).trim();
      final primary    = joined.isNotEmpty ? joined : rawPrimary;

      final riskLevel = ((json['risk_level'] ?? json['risk'] ?? 'none')).toString();
      final mirrorRaw = (json['mirror'] ?? '').toString().trim();
      final String? mirror = mirrorRaw.isEmpty ? null : mirrorRaw;

      final analysis = Analysis(
        sorc: null, levers: const [], mirror: mirror,
        question: primary.isNotEmpty ? primary : errorHint, riskLevel: riskLevel,
      );
      return AnalyzeResult(analysis: analysis, challenge: null);
    } catch (_) {
      const analysis = Analysis(sorc: null, levers: [], mirror: null, question: errorHint, riskLevel: 'none');
      return const AnalyzeResult(analysis: analysis, challenge: null);
    }
  }
  // ---------------- Legacy-Kompat: aiReflect() ----------------
  Future<ReflectionAIResult> aiReflect({
    required List<Map<String, String>> messages,
    String model = 'gpt-4.1',
  }) async {
    if (_http == null) {
      return const ReflectionAIResult(
        reflection: errorHint, depth: 'light', riskFlag: 'none', tags: <String>[],
      );
    }

    String userText = '';
    final lastUser = messages.lastWhereOrNull((m) => (m['role'] ?? '') == 'user');
    if (lastUser != null && ((lastUser['content'] ?? '').trim().isNotEmpty)) {
      userText = lastUser['content']!.trim();
    } else if (messages.isNotEmpty && (messages.last['content'] ?? '').trim().isNotEmpty) {
      userText = messages.last['content']!.trim();
    }

    final turn = await _reflectStep(
      text: userText,
      session: ReflectionSession(threadId: _uuid.v4(), turnIndex: 0, maxTurns: 3),
      locale: 'de', tz: 'Europe/Zurich', history: messages,
    );

    final depth   = _estimateDepth(messages);
    final riskFlg = (turn.flow?.riskNotice != null) ? 'support' : 'none';

    return ReflectionAIResult(
      reflection: turn.outputText, depth: depth, riskFlag: riskFlg, tags: await suggestTags(turn.outputText),
    );
  }

  // ---------------- mood / story / journey ----------------
  Future<MoodResponse> mood({
    required String entryId,
    required int icon,
    String? note,
    bool useServerIfAvailable = true,
  }) async {
    if (useServerIfAvailable && _http != null) {
      try {
        final payload = {
          'entry_id': entryId,
          'mood': {'icon': icon, if (note != null && note.trim().isNotEmpty) 'note': note},
        };
        _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
        _appendByteContext(payload);
        await _postMaybe('/mood', payload);
      } catch (_) {}
    }
    return const MoodResponse(saved: true);
  }

  Future<StoryResult> story({
    required List<String> entryIds,
    List<String>? topics,
    bool useServerIfAvailable = true,
  }) async {
    if (_http != null && useServerIfAvailable) {
      const bases = [500, 1500, 3000];
      for (int i = 0; i < bases.length; i++) {
        try {
          final nowDate = DateTime.now().toUtc().toIso8601String().split('T').first;
          final merged  = (topics != null && topics.isNotEmpty)
              ? topics.join(' · ')
              : (entryIds.isNotEmpty ? 'Ausgewählte Einträge: ${entryIds.join(', ')}' : '');

          final payload = <String, dynamic>{
            'entries': [{'date': nowDate, 'text': merged, 'mood': null, 'tags': const <String>[]}],
            'locale': 'de', 'tz': 'Europe/Zurich',
          };
          _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
          _appendByteContext(payload);

          final json = await _postMaybe('/story', payload, saveSource: 'story').timeout(_timeout);
          if (json == null) throw Exception('no json');

          final title = (json['title'] ?? 'Kurzgeschichte').toString();
          final body  = (json['story'] ?? '').toString();
          if (body.trim().isEmpty) throw Exception('empty story');

          return StoryResult(
            id: 'story_${DateTime.now().millisecondsSinceEpoch}', title: title, body: body, audioUrl: null,
          );
        } catch (_) {
          if (i < bases.length - 1) {
            final jitter = _rand.nextInt(250);
            await Future.delayed(Duration(milliseconds: bases[i] + jitter));
            continue;
          }
        }
      }
    }
    return StoryResult(
      id: 'story_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Kurzgeschichte', body: errorHint, audioUrl: null,
    );
  }

  Future<JourneyInsights> journey({
    required List<JourneyEntry> entries,
    String horizon = '7d',
    bool useServerIfAvailable = true,
  }) async {
    if (_http != null && useServerIfAvailable) {
      try {
        final payload = <String, dynamic>{
          'entries': entries.map((e) {
            final red = _redactPII(e.text);
            final int end = red.length > 800 ? 800 : red.length;
            return {'date': e.dateIso, 'mood': e.moodLabel ?? '', 'text': red.substring(0, end)};
          }).toList(growable: false),
          'horizon': horizon,
        };
        _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
        _appendByteContext(payload);

        final json = await _postMaybe('/journey', payload, saveSource: 'journey').timeout(_timeout);
        if (json == null) throw Exception('no json');

        final insightsDyn = (json['insights'] as List?) ?? const [];
        final question    = (json['question'] ?? '').toString();

        final insights = insightsDyn.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty).take(6).toList(growable: false);

        if (insights.isEmpty && question.isEmpty) throw Exception('empty journey result');

        return JourneyInsights(
          insights: insights.isEmpty ? <String>[question] : insights,
          question: question.isNotEmpty ? question : (insights.isNotEmpty ? insights.first : loadingHint),
        );
      } catch (_) {}
    }
    return const JourneyInsights(
      insights: <String>['ZenYourself konnte keine Insights laden.'],
      question: loadingHint,
    );
  }

  // ---------------- ZIP-Core Export ----------------
  Future<ZipCoreResult> zipCore({
    required String profileId,
    required List<re.ReflectionEntry> reflections,
    List<Map<String, dynamic>> moods = const [],
    Map<String, dynamic>? profileInfo,
    Map<String, dynamic>? appInfo,
    bool redactPII = true,
    bool useServerIfAvailable = true,
    String locale = 'de',
    String tz = 'Europe/Zurich',
  }) async {
    final timeline = _bestEffortTimeline(reflections: reflections);

    if (useServerIfAvailable && _http != null) {
      try {
        final entriesJson = reflections
            .map((e) => _jsonForReflectionExport(e, redactPII: redactPII))
            .toList(growable: false);

        final payload = <String, dynamic>{
          'profile': {'id': profileId, if (profileInfo != null) ...profileInfo},
          'entries': entriesJson,
          'moods': moods,
          if (timeline != null && timeline.isNotEmpty) 'timeline': timeline,
          'app': {'brand': _brand, 'channel': _channel, if (appInfo != null) ...appInfo},
          'locale': locale, 'tz': tz,
        };

        _appendContactTints(payload, locale: locale, tz: tz);
        _appendByteContext(payload);

        final json = await _tryEndpoints(
          endpoints: const ['/zip_core', '/export/zip_core', '/zip'],
          payload: payload,
        );
        if (json != null) {
          final b64 = (json['zip_b64'] ?? json['b64'] ?? json['zip'])?.toString();
          if (b64 != null && b64.trim().isNotEmpty) {
            final bytes = base64Decode(b64);
            final fname = (json['filename'] ?? _defaultZipName()).toString();
            return ZipCoreResult(bytes: Uint8List.fromList(bytes), filename: fname);
          }
        }
      } catch (_) {}
    }

    final zipBytes = _buildZipLocally(
      profileId: profileId, reflections: reflections, moods: moods,
      profileInfo: profileInfo, appInfo: appInfo, redactPII: redactPII,
      locale: locale, tz: tz, timeline: timeline,
    );
    return ZipCoreResult(bytes: zipBytes, filename: _defaultZipName());
  }

  Future<ZipCoreResult> zipCoreMoot({
    required String profileId,
    required List<re.ReflectionEntry> reflections,
    List<Map<String, dynamic>> moods = const [],
    Map<String, dynamic>? profileInfo,
    Map<String, dynamic>? appInfo,
    bool redactPII = true,
    bool useServerIfAvailable = true,
    String locale = 'de',
    String tz = 'Europe/Zurich',
  }) => zipCore(
        profileId: profileId, reflections: reflections, moods: moods,
        profileInfo: profileInfo, appInfo: appInfo, redactPII: redactPII,
        useServerIfAvailable: useServerIfAvailable, locale: locale, tz: tz,
      );

  Uint8List _buildZipLocally({
    required String profileId,
    required List<re.ReflectionEntry> reflections,
    required List<Map<String, dynamic>> moods,
    Map<String, dynamic>? profileInfo,
    Map<String, dynamic>? appInfo,
    required bool redactPII,
    required String locale,
    required String tz,
    List<Map<String, dynamic>>? timeline,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final archive = Archive();

    final manifest = {
      'brand': _brand, 'channel': _channel, 'created_at': nowIso, 'version': 'v6.7.4',
      'counts': {'reflections': reflections.length, 'moods': moods.length, if (timeline != null) 'timeline': timeline.length},
      'locale': locale, 'tz': tz,
    };

    final profileJson = <String, dynamic>{'id': profileId, if (profileInfo != null && profileInfo.isNotEmpty) ...profileInfo};

    final entriesJsonl = StringBuffer();
    for (final e in reflections) {
      entriesJsonl.writeln(jsonEncode(_jsonForReflectionExport(e, redactPII: redactPII)));
    }

    final files = <String, List<int>>{
      'manifest.json': utf8.encode(jsonEncode(manifest)),
      'profile.json': utf8.encode(jsonEncode(profileJson)),
      'reflections.jsonl': utf8.encode(entriesJsonl.toString()),
      'moods.json': utf8.encode(jsonEncode(moods)),
      'VERSION.txt': utf8.encode('ZenYourself export v6.7.4 • $nowIso\n'),
      'README.txt': utf8.encode(
        'ZenYourself Core Export\n\n'
        'Dateien:\n'
        '- manifest.json  • Metadaten\n'
        '- profile.json   • Profilkern\n'
        '- reflections.jsonl • Reflexionen (JSON-Lines)\n'
        '- moods.json     • Stimmungsnotizen\n'
        '- timeline.json  • Zeitleiste (falls vorhanden)\n'
        '- VERSION.txt    • Export-Version\n'
        '\nHinweis: Inhalte können PII-bereinigt sein (redactPII=$redactPII).\n'),
    };

    if (timeline != null && timeline.isNotEmpty) {
      files['timeline.json'] = utf8.encode(jsonEncode(timeline));
    }

    for (final e in files.entries) {
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    final bytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(bytes);
  }

  Map<String, dynamic> _jsonForReflectionExport(
    re.ReflectionEntry entry, {required bool redactPII}) {
    final text    = _bestEffortContent(entry);
    final safe    = redactPII ? _redactPII(text) : text;
    final isoDate = _dateIsoForEntry(entry);
    final id      = _stringProp(entry, const ['id','entryId','uuid'])
                      .ifEmpty(() => 're_${isoDate}_${text.hashCode.abs()}');
    final mood    = _intProp(entry, const ['moodIcon','mood','moodScore','icon']);
    final tags    = _listStringProp(entry, const ['tags','labels']);
    return <String, dynamic>{
      'id': id, 'date': isoDate, 'text': safe,
      if (mood != null) 'mood': mood, if (tags.isNotEmpty) 'tags': tags,
    };
  }

  // ---------------- Timeline (best-effort) ----------------
  List<Map<String, dynamic>>? _bestEffortTimeline({required List<re.ReflectionEntry> reflections}) {
    try {
      final ms = MemoryService.instance as dynamic;
      dynamic t;
      try { t = ms.exportTimeline?.call(); } catch (_){}
      t ??= (() { try { return ms.buildTimeline?.call(); } catch(_){ } return null; })();
      t ??= (() { try { return ms.timeline?.call(); }      catch(_){ } return null; })();
      t ??= (() { try { return ms.getTimeline?.call(); }   catch(_){ } return null; })();
      if (t != null) {
        if (t is String) {
          try {
            final parsed = jsonDecode(t);
            if (parsed is List) {
              final list = parsed.where((e)=>e!=null).map((e)=>e as Map)
                  .map((m)=>m.map((k,v)=>MapEntry(k.toString(), v))).cast<Map<String,dynamic>>().toList(growable:false);
              if (list.isNotEmpty) return list.take(2000).toList();
            }
          } catch (_) {}
        } else if (t is List) {
          final list = t.where((e)=>e!=null).map((e)=>e as Map)
              .map((m)=>m.map((k,v)=>MapEntry(k.toString(), v))).cast<Map<String,dynamic>>().toList(growable:false);
          if (list.isNotEmpty) return list.take(2000).toList();
        } else if (t is Map) {
          final items = (t['items'] as List?) ?? const [];
          final list = items.where((e)=>e!=null).map((e)=>e as Map)
              .map((m)=>m.map((k,v)=>MapEntry(k.toString(), v))).cast<Map<String,dynamic>>().toList(growable:false);
          if (list.isNotEmpty) return list.take(2000).toList();
        }
      }
    } catch (_) {}

    if (reflections.isEmpty) return null;
    final out = <Map<String, dynamic>>[];
    for (final e in reflections) {
      final date = _dateIsoForEntry(e);
      final id   = _stringProp(e, const ['id','entryId','uuid'])
                    .ifEmpty(() => 're_${date}_${_bestEffortContent(e).hashCode.abs()}');
      final mood = _intProp(e, const ['moodIcon','moodScore','mood','icon']);
      final hint = _neatEllipsis(_redactPII(_bestEffortContent(e)), 120);
      out.add({'id': id, 'date': date, if (mood != null) 'mood': mood, 'hint': hint});
    }
    return out.take(10000).toList(growable: false);
  }

  String _dateIsoForEntry(re.ReflectionEntry entry) {
    DateTime? tryDate(dynamic v) {
      if (v is DateTime) return v.toUtc();
      if (v is String) {
        final s = v.trim(); final d = DateTime.tryParse(s);
        if (d != null) return d.toUtc();
        final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
        if (m != null) return DateTime.utc(int.parse(m.group(1)!),
                                           int.parse(m.group(2)!),
                                           int.parse(m.group(3)!));
      }
      return null;
    }
    final candidates = <dynamic>[
      _dynProp(entry, 'dateIso'), _dynProp(entry, 'date'),
      _dynProp(entry, 'createdAt'), _dynProp(entry, 'created'),
    ];
    for (final c in candidates) {
      final dt = tryDate(c); if (dt != null) return dt.toIso8601String().split('T').first;
    }
    return DateTime.now().toUtc().toIso8601String().split('T').first;
  }

  dynamic _dynProp(dynamic obj, String name) {
    if (obj == null) return null;
    try { if (obj is Map) return obj[name]; } catch (_){}
    try {
      final toJson = (obj as dynamic).toJson;
      if (toJson is Function) {
        final j = toJson();
        if (j is Map) return j[name];
        if (j is String && j.trim().startsWith('{')) {
          final parsed = jsonDecode(j);
          if (parsed is Map) return parsed[name];
        }
      }
    } catch (_){}
    try {
      final toMap = (obj as dynamic).toMap;
      if (toMap is Function) {
        final m = toMap(); if (m is Map) return m[name];
      }
    } catch (_){}
    try { return (obj as dynamic).dateIso; } catch (_){}
    try { return (obj as dynamic).date; } catch (_){}
    try { return (obj as dynamic).createdAt; } catch (_){}
    try { return (obj as dynamic).created; } catch (_){}
    try { return (obj as dynamic).id; } catch (_){}
    try { return (obj as dynamic).entryId; } catch (_){}
    try { return (obj as dynamic).uuid; } catch (_){}
    try { return (obj as dynamic).moodIcon; } catch (_){}
    try { return (obj as dynamic).mood; } catch (_){}
    try { return (obj as dynamic).moodScore; } catch (_){}
    try { return (obj as dynamic).icon; } catch (_){}
    try { return (obj as dynamic).tags; } catch (_){}
    try { return (obj as dynamic).labels; } catch (_){}
    return null;
  }

  String _stringProp(dynamic obj, List<String> names) {
    for (final n in names) {
      final v = _dynProp(obj, n);
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  int? _intProp(dynamic obj, List<String> names) {
    for (final n in names) {
      final v = _dynProp(obj, n);
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) { final p = int.tryParse(v.trim()); if (p != null) return p; }
    }
    return null;
  }

  List<String> _listStringProp(dynamic obj, List<String> names) {
    for (final n in names) {
      final v = _dynProp(obj, n);
      if (v is List) {
        return v.where((e)=>e!=null).map((e)=>e.toString().trim())
                .where((s)=>s.isNotEmpty).toList(growable:false);
      }
      if (v is String && v.trim().isNotEmpty) {
        return v.split(RegExp(r'[,\|;]')).map((e)=>e.trim())
                .where((s)=>s.isNotEmpty).toList(growable:false);
      }
    }
    return const <String>[];
  }

  String _defaultZipName() {
    final now = DateTime.now().toUtc();
    String two(int x) => x.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
    return 'zenyourself_export_$stamp.zip';
  }

  // ---------------- Lokal-Heuristiken / Structure ----------------
  Future<StructuredThoughtResult> structureThoughts(String input, {bool useServerIfAvailable = true}) async {
    final raw = input.trim(); await _delay(minMs: 220, maxMs: 360);
    final sanitized = _redactPII(raw);
    final lever     = _pickLever(sanitized);

    final bullets = _bulletsFromText(sanitized, maxItems: 6);
    final core    = _coreIdeaFrom(sanitized, bullets, lever);

    final emo   = detectEmotionSync(sanitized);
    final score = classifyMoodSync(sanitized);
    final moodH = _composeMood(emotion: emo, score: score);

    final next  = _nextStepsForLever(lever);

    return StructuredThoughtResult(
      bullets: bullets,
      coreIdea: core.ifEmpty(() => _neatEllipsis(sanitized, 120)),
      moodHint: moodH,
      nextSteps: next,
      source: 'offline',
    );
  }

  Future<Question> fetchGuidingQuestion({String? contextText, bool followUp = false}) async {
    final ctx = (contextText ?? '').trim();

    if (_http != null) {
      try {
        final payload = {
          'text': ctx.isEmpty ? 'kurze Reflexion' : ctx,
          'locale': 'de', 'tz': 'Europe/Zurich',
          'session': {'id': _uuid.v4(), 'turn': 0, 'max_turns': 1},
        };
        _appendContactTints(payload, locale: 'de', tz: 'Europe/Zurich');
        _appendByteContext(payload);

        final json = await _postMaybe('/reflect_full', payload, saveSource: 'reflect_full')
            .timeout(_timeout);

        if (json != null) {
          final primary = _extractPrimary(json).trim();
          if (primary.isNotEmpty) {
            final now = DateTime.now().toUtc();
            final qText = primary.endsWith('?') ? primary : '$primary?';
            return Question(id: 'q_${now.millisecondsSinceEpoch}_${qText.hashCode}',
                            text: qText, isFollowUp: followUp, createdAt: now);
          }
        }
      } catch (_) {}
    }

    final seeds = followUp
        ? const [
            'Magst du dort weitermachen, wo es gerade wichtig ist?',
            'Was war der kleinste hilfreiche Moment seit eben?',
            'Welcher Gedanke ist jetzt am lautesten – und welcher am leisesten?',
          ]
        : const [
            'Wenn du innehalten magst: Was ist dir gerade am wichtigsten?',
            'Worauf bist du heute sanft stolz?',
            'Was bräuchte jetzt ein wenig Raum?',
            'Welche Sorge oder Hoffnung meldet sich am stärksten?',
          ];

    final pick = seeds[_rand.nextInt(seeds.length)];
    final text = _personalize(pick.endsWith('?') ? pick : '$pick?', ctx);
    final now  = DateTime.now().toUtc();
    return Question(id: 'q_${now.millisecondsSinceEpoch}_${text.hashCode}',
                    text: text, isFollowUp: followUp, createdAt: now);
  }

  Future<Question> fetchFollowUp({String? contextText}) =>
      fetchGuidingQuestion(contextText: contextText, followUp: true);

  Future<String> summarizeReflection(re.ReflectionEntry entry) async {
    final raw = _bestEffortContent(entry); if (raw.isEmpty) return '';
    final red = _redactPII(raw);
    final bullets = _bulletsFromText(red, maxItems: 3);
    final emo = detectEmotionSync(red);
    final mood = classifyMoodSync(red);
    final tail = _composeMood(emotion: emo, score: mood);
    final base = bullets.isNotEmpty ? bullets.first : _neatEllipsis(red, 140);
    return tail == null ? base : '$base — $tail';
  }

  Future<String?> detectEmotion(String text) async => detectEmotionSync(text);
  Future<int?> classifyMood(String text) async => classifyMoodSync(text);

  Future<List<String>> suggestTags(String text) async {
    final t = text.toLowerCase();
    final tags = <String>{};
    void maybe(String tag, List<String> keys) { if (_any(t, keys)) tags.add(tag); }

    maybe('Arbeit',       ['arbeit','job','chef','meeting','projekt','kolleg']);
    maybe('Beziehung',    ['partner','bezieh','freund','famil']);
    maybe('Schlaf',       ['schlaf','müde','insomn','träum']);
    maybe('Stress',       ['stress','überforder','nervös','druck']);
    maybe('Angst',        ['angst','sorge','panik']);
    maybe('Wut',          ['wut','ärger','sauer','genervt']);
    maybe('Traurigkeit',  ['traurig','weinen','leer','melanch']);
    maybe('Dankbarkeit',  ['dankbar','wertschätz','zufrieden','stolz']);
    maybe('Produktivität',['aufschieb','prokrast','fokus','starten']);
    maybe('Gesundheit',   ['körper','sport','beweg','schmerz']);

    if (tags.isEmpty) {
      final words = t.replaceAll(RegExp(r'[^a-zäöüß\s]'),' ')
                     .split(RegExp(r'\s+')).where((w) => w.length >= 5).take(3)
                     .map((w) => w[0].toUpperCase() + w.substring(1)).toList();
      tags.addAll(words);
    }
    return tags.take(6).toList(growable: false);
  }

  // ---------------- Offline-Heuristiken ----------------
  String? detectEmotionSync(String text) {
    final t = text.toLowerCase();
    if (_any(t, ['wut','zorn','ärger','sauer','genervt'])) return 'wütend';
    if (_any(t, ['traurig','trauer','leer','niedergeschlagen','weinen'])) return 'traurig';
    if (_any(t, ['stress','gestresst','nervös','überforder','panik'])) return 'gestresst';
    if (_any(t, ['ruhig','entspannt','gelassen','friedlich'])) return 'ruhig';
    if (_any(t, ['glücklich','freu','dankbar','zufrieden','stolz'])) return 'glücklich';
    return null;
  }

  int classifyMoodSync(String text) {
    final t = text.toLowerCase();
    int score = 2;
    if (_any(t, ['wut','zorn','ärger','sauer'])) score -= 2;
    if (_any(t, ['traurig','weinen','leer']))    score -= 2;
    if (_any(t, ['stress','gestresst','überforder'])) score -= 1;
    if (_any(t, ['angst','sorge','panik']))      score -= 1;
    if (_any(t, ['ruhig','entspannt','gelassen'])) score += 1;
    if (_any(t, ['glücklich','freu','dankbar','zufrieden','stolz'])) score += 2;
    return score.clamp(0, 4).toInt();
  }

  Future<void> _delay({int minMs = 300, int maxMs = 420}) async {
    final span = maxMs - minMs;
    final jitter = span > 0 ? minMs + _rand.nextInt(span) : minMs;
    await Future.delayed(Duration(milliseconds: jitter));
  }

  bool _any(String haystack, List<String> needles) {
    for (final n in needles) { if (haystack.contains(n)) return true; }
    return false;
  }

  String _personalize(String q, String? ctx) {
    final raw = (ctx ?? '').trim(); if (raw.isEmpty) return q;
    final firstLine = raw.split('\n').firstWhereOrNull((e) => e.trim().isNotEmpty) ?? raw;
    final sanitized = _redactPII(firstLine.trim()); if (sanitized.isEmpty) return q;
    final hint = _neatEllipsis(sanitized, 90);
    if (RegExp(r'^\[[^\]]]+\]$').hasMatch(hint)) return q;
    return '$q\n\n(Bezug: $hint)';
  }

  String _redactPII(String input) {
    var s = input;
    final email  = RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false);
    s = s.replaceAll(email, '[E-Mail]');
    final phone  = RegExp(r'(\+?\d[\d\s\-\(\)]{6,}\d)');
    s = s.replaceAll(phone, '[Telefon]');
    final url    = RegExp(r'(https?:\/\/|www\.)\S+', caseSensitive: false);
    s = s.replaceAll(url, '[Link]');
    final iban   = RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b');
    s = s.replaceAll(iban, '[IBAN]');
    final card   = RegExp(r'\b(?:\d[ \-]*?){13,19}\b');
    s = s.replaceAll(card, '[Karte]');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  String _bestEffortContent(re.ReflectionEntry entry) {
    dynamic d = entry;
    String pick(dynamic Function(dynamic x) getter) {
      try { final v = getter(d);
        if (v is String && v.trim().isNotEmpty) return v.trim();
      } catch (_) {}
      return '';
    }
    return pick((x) => x.content)
        .ifEmpty(() => pick((x) => x.answer?.content))
        .ifEmpty(() => pick((x) => x.aiSummary))
        .ifEmpty(() => pick((x) => x.moodNote))
        .ifEmpty(() => '');
  }

  static String _neatEllipsis(String s, int maxChars) {
    if (s.length <= maxChars) return s;
    final cut = s.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    final safe = lastSpace > 40 ? cut.substring(0, lastSpace) : cut;
    return '${safe.trim()}…';
  }

  String _pickLever(String text) {
    final t = text.toLowerCase();
    if (_any(t, const ['gedanke','glaubens','sollte','muss'])) return 'Gedanken';
    if (_any(t, const ['gefüh','angst','wut','traur','überforder'])) return 'Gefühle';
    if (_any(t, const ['körper','schlaf','angespannt','atem','müde'])) return 'Körper';
    if (_any(t, const ['aufschieb','scroll','reaktion','streit','vermeid'])) return 'Verhalten';
    if (_any(t, const ['arbeit','chef','famil','uni','termin','druck'])) return 'Kontext';
    return 'Gedanken';
  }

  List<String> _bulletsFromText(String text, {int maxItems = 6}) {
    if (text.isEmpty) return const <String>[];
    final raw = text.replaceAll('\r',' ').replaceAll(RegExp(r'\s+'),' ').trim();
    final parts = raw.split(RegExp(r'[\.!\?\n;:]')).map((s)=>s.trim()).where((s)=>s.length>=3).toList();
    final seen = <String>{}; final out = <String>[];
    for (final p in parts) {
      final norm = p.toLowerCase();
      if (seen.contains(norm)) continue; seen.add(norm);
      out.add(_neatEllipsis(p, 140));
      if (out.length >= maxItems) break;
    }
    if (out.isEmpty) out.add(_neatEllipsis(text, 140));
    return out;
  }

  String _coreIdeaFrom(String fullText, List<String> bullets, String lever) {
    if (bullets.isEmpty) return '';
    int scoreOf(String s) {
      int score = 0; final l = s.length;
      if (l >= 40 && l <= 140) score += 3;
      if (s.contains('?')) score += 2;
      if (s.contains('!')) score += 1;
      final t = s.toLowerCase();
      if (lever == 'Gedanken'   && _any(t, const ['sollte','muss','immer','nie'])) score += 2;
      if (lever == 'Gefühle'    && _any(t, const ['fühl','angst','wut','traur']))   score += 2;
      if (lever == 'Körper'     && _any(t, const ['körper','müde','schlaf','atem'])) score += 2;
      if (lever == 'Verhalten'  && _any(t, const ['aufschieb','start','beginnen','klein'])) score += 2;
      if (lever == 'Kontext'    && _any(t, const ['arbeit','termin','chef','famil'])) score += 2;
      return score;
    }
    bullets.sort((a,b) => scoreOf(b).compareTo(scoreOf(a)));
    return bullets.first;
  }

  String? _composeMood({String? emotion, int? score}) {
    final String? label = (score == null) ? null : _labelFromScore(score);
    if (emotion == null && label == null) return null;
    if (emotion != null && label != null) return '$emotion · $label';
    return emotion ?? label;
  }

  String? _labelFromScore(int score) {
    switch (score) {
      case 0: return 'Sehr schlecht';
      case 1: return 'Schlecht';
      case 2: return 'Neutral';
      case 3: return 'Gut';
      case 4: return 'Sehr gut';
      default: return null;
    }
  }

  // ---------------- Reflect-Parsing (V7) ----------------
  ReflectionTurn _turnFromReflectAny(Map<String, dynamic> any, ReflectionSession session) {
    if (any.length == 1 && (any.containsKey('output_text') || any.containsKey('raw'))) {
      final text = (any['output_text'] ?? any['raw'] ?? '').toString();
      return ReflectionTurn(
        outputText: text.trim().isNotEmpty ? text.trim() : errorHint,
        mirror: null, context: const [], followups: const [], answerHelpers: const [],
        helperSuggestion: null, flow: const ReflectionFlow(recommendEnd: false, suggestBreak: false),
        session: session, tags: const [], riskFlag: 'none', questions: const [],
      );
    }
    return _turnFromReflectJson(any, session);
  }

  ReflectionTurn _turnFromReflectJson(Map<String, dynamic> json, ReflectionSession session) {
    final dtoBase = ReflectionTurn.fromMaybe(json);

    try {
      final memToSave = (json['memories_to_save'] as List?) ?? const [];
      if (memToSave.isNotEmpty) _memorySave({'memories_to_save': memToSave}, 'reflect_full');
    } catch (_) {}

    final questionsList = _parseStringList(json['questions'] ?? json['multi_questions'] ?? json['qs']);
    final altList       = _parseStringList(json['alt'] ?? json['alt_question'] ?? json['alternatives']
                                           ?? json['alternative'] ?? json['secondary_question']
                                           ?? json['secondary'] ?? json['options']);
    final allQs         = _dedupeStrings([...questionsList, ...altList]);

    final primaryRaw        = _extractPrimary(json).trim();
    final joinedQuestions   = _normalizeQuestions(allQs);
    final primaryDisplay    = joinedQuestions.isNotEmpty ? joinedQuestions : primaryRaw;
    final outputText        = primaryDisplay.ifEmpty(() => errorHint);

    final firstQuestion = allQs.isNotEmpty
        ? _ensureQuestion(allQs.first)
        : (primaryRaw.isNotEmpty ? _ensureQuestion(primaryRaw) : '');

    final mirrorRaw = (json['mirror'] ?? json['empathy'] ?? '').toString().trim();
    final String? mirror = mirrorRaw.isEmpty ? null : mirrorRaw;

    final ctxDyn = (json['context'] as List?) ?? (json['contexts'] as List?) ?? (json['hints'] as List?) ?? const [];
    final ctx = ctxDyn.map((e) => e.toString()).where((e) => e.trim().isNotEmpty)
                      .take(4).toList(growable: false);

    final helpers   = _readAnswerHelpers(json);
    final followups = _parseStringList(json['followups']);

    // Talk + Smalltalk + Closure/Hope
    final talkDyn = (json['talk'] as List?) ?? const [];
    final talk = talkDyn.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList(growable: true);
    final smalltalk = (json['smalltalk_reply'] ?? '').toString().trim();
    if (smalltalk.isNotEmpty && talk.length < 2) talk.add(smalltalk);

    // NEW (V7): closure.hope_reply → falls vorhanden und Talk < 2, aufnehmen
    final closureMap   = (json['closure'] as Map?) ?? const {};
    final hopeReply    = (closureMap['hope_reply'] ?? closureMap['hope'] ?? '').toString().trim();
    final closurePromp = (closureMap['closure_prompt'] ?? '').toString().trim();
    if (hopeReply.isNotEmpty && talk.length < 2) {
      talk.insert(0, hopeReply);
    }
    final talkLimited = talk.take(2).toList(growable: false);

    final flowJson = (json['flow'] as Map?) ?? const {};
    final ui       = (json['ui']   as Map?) ?? const {};
    final moodNested = _boolLike(((flowJson['mood'] as Map?) ?? const {})['prompt']);
    final flowCompat = ReflectionFlow(
      recommendEnd: (flowJson['recommend_end'] == true) || (flowJson['end'] == true),
      suggestBreak: (flowJson['suggest_break'] == true) || (flowJson['break'] == true),
      riskNotice: flowJson['risk_notice']?.toString(),
      sessionTurn: (flowJson['session_turn'] is num)
          ? (flowJson['session_turn'] as num).toInt() : session.turnIndex,
      talkOnly: flowJson['talk_only'] == true,
      allowReflect: flowJson['allow_reflect'] != false,
      moodPrompt: (flowJson['mood_prompt'] == true) ||
                  (flowJson['recommend_end'] == true) || (flowJson['end'] == true) || moodNested,
    );

    final sJson = (json['session'] as Map?) ?? const {};
    final s = session.copyWith(
      threadId: (sJson['id'] ?? sJson['thread_id'] ?? session.threadId).toString(),
      turnIndex: _asInt(sJson['turn'] ?? sJson['turn_index'] ?? session.turnIndex) ?? session.turnIndex,
      maxTurns:  _asInt(sJson['max_turns'] ?? session.maxTurns) ?? session.maxTurns,
    );

    final schoolsDyn = (json['schools'] as List?) ?? (json['therapeutic_schools'] as List?) ??
                       (json['approaches'] as List?) ?? const [];
    final normalizedSchools = _normalizeSchools(_parseStringList(schoolsDyn));
    final workerTags = _parseStringList(json['tags']);
    final tagsCompat = _dedupeStrings([
      ...workerTags,
      ...normalizedSchools,
      ...(_parseStringList(ui['badges'])).map((e) => 'ui:$e'),
      if (hopeReply.isNotEmpty) 'closure:hope',
      if (closurePromp.isNotEmpty) 'closure:prompt',
    ]);

    final riskLevelRoot = (json['risk_level'] ?? json['risk_flag'] ?? json['level'] ?? json['risk'] ?? 'none')
        .toString().trim().toLowerCase();
    final riskFlagCompat = (riskLevelRoot == 'high' || riskLevelRoot == 'crisis')
        ? 'crisis'
        : (riskLevelRoot == 'mild' || riskLevelRoot == 'support' || riskLevelRoot == 'true')
            ? 'support' : 'none';

    final helperSuggestion = _extractHelperSuggestion(json);
    final TurnAnalysis? legacyAnalysis = _analysisFromLegacy(json, flowJson);

    // --- Merge Felder ---
    final mergedFlow = ReflectionFlow(
      recommendEnd: (dtoBase?.flow?.recommendEnd ?? false) || flowCompat.recommendEnd,
      suggestBreak: (dtoBase?.flow?.suggestBreak ?? false) || flowCompat.suggestBreak,
      riskNotice:   dtoBase?.flow?.riskNotice ?? flowCompat.riskNotice,
      sessionTurn:  dtoBase?.flow?.sessionTurn ?? flowCompat.sessionTurn,
      talkOnly:     (dtoBase?.flow?.talkOnly ?? false) || flowCompat.talkOnly,
      allowReflect: (dtoBase?.flow?.allowReflect ?? true) && flowCompat.allowReflect,
      moodPrompt:   (dtoBase?.flow?.moodPrompt ?? false) || flowCompat.moodPrompt,
    );

    final mergedHelpers   = _dedupeStrings([...helpers, if (dtoBase != null) ...dtoBase.answerHelpers]).take(3).toList(growable: false);
    final mergedContext   = _dedupeStrings([...ctx, if (dtoBase != null) ...dtoBase.context]);
    final mergedFollowups = _dedupeStrings([...followups, if (dtoBase != null) ...dtoBase.followups]);
    final mergedTags      = _dedupeStrings([...tagsCompat, if (dtoBase != null) ...dtoBase.tags]);

    final mergedQuestions = _dedupeStrings([
      if (firstQuestion.isNotEmpty) firstQuestion, ...allQs.skip(1),
      if (dtoBase != null) ...dtoBase.questions,
    ]);

    final mergedTalk = (() {
      final list = <String>[...talkLimited, if (dtoBase != null) ...dtoBase.talk]
          .where((e) => e.trim().isNotEmpty).toList();
      return list.take(2).toList(growable: false);
    })();

    return ReflectionTurn(
      outputText: outputText,
      mirror: dtoBase?.mirror ?? mirror,
      context: mergedContext,
      followups: mergedFollowups,
      answerHelpers: mergedHelpers,
      helperSuggestion: dtoBase?.helperSuggestion ?? helperSuggestion,
      flow: mergedFlow,
      session: s,
      tags: mergedTags,
      riskFlag: dtoBase?.riskFlag ?? riskFlagCompat,
      questions: mergedQuestions,
      talk: mergedTalk,
      analysis: dtoBase?.analysis ?? legacyAnalysis,
      topicSuggestions: dtoBase?.topicSuggestions ?? const <String>[],
    );
  }

  List<String> _readAnswerHelpers(Map<String, dynamic> json) {
    List<String> asList(dynamic v) => _parseStringList(v);
    final top = <String>[
      ...asList(json['answer_helpers']),
      ...asList(json['answer_scaffolds']),
      ...asList(json['answer_templates']),
      ...asList(json['helpers']),
      ...asList(json['chips']),
      ...asList(json['answers']),
    ];
    final flow = (json['flow'] as Map?) ?? const {};
    final ui   = (json['ui']   as Map?) ?? const {};
    final nested = <String>[
      ...asList(flow['answer_helpers']),
      ...asList(flow['helpers']),
      ...asList(ui['answer_helpers']),
      ...asList(ui['chips']),
    ];

    final raw = [...top, ...nested].map((e)=>e.trim())
        .where((e)=>e.isNotEmpty && !e.endsWith('?')).toList();

    final cleaned = raw.map((s)=>s.replaceAll(RegExp(r'\s*[:：]\s*$'), '').trim())
        .where((s)=>s.isNotEmpty).toList();

    return _dedupeStrings(cleaned).take(3).toList(growable: false);
  }

  String? _extractHelperSuggestion(Map<String, dynamic> json) {
    String pick(dynamic v) { if (v == null) return ''; final s = v.toString().trim(); return s.isNotEmpty ? s : ''; }
    final flow = (json['flow'] as Map?) ?? const {};
    final ui   = (json['ui']   as Map?) ?? const {};

    final candidates = <String>[
      pick(json['helper_suggestion']), pick(json['helperSuggestion']),
      pick(flow['helper_suggestion']), pick(flow['helperSuggestion']),
      pick(ui['helper_suggestion']),   pick(ui['helperSuggestion']),
    ].where((s) => s.isNotEmpty).toList(growable: false);

    if (candidates.isEmpty) return null;
    final cleaned = candidates.first
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s*\.\s*\.\s*$'), '.')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  TurnAnalysis? _analysisFromLegacy(Map<String, dynamic> root, Map flow) {
    double? asDouble(dynamic x) {
      if (x is num) return x.toDouble();
      final s = x?.toString(); if (s == null) return null;
      return double.tryParse(s);
    }
    final v = asDouble(root['insight_score'] ?? flow['insight_score']);
    if (v == null) return null;
    return TurnAnalysis(insightScore: v);
  }

  static String _extractPrimary(Map<String, dynamic> json) {
    final fromChoices = _contentFromChoices(json['choices']);
    final candidates = <String>[
      if (json['primary'] != null) json['primary'].toString(),
      if (json['primary_question'] != null) json['primary_question'].toString(),
      if (json['lead'] != null) json['lead'].toString(),
      if (json['lead_question'] != null) json['lead_question'].toString(),
      if (json['output_text'] != null) json['output_text'].toString(),
      if (fromChoices != null && fromChoices.trim().isNotEmpty) fromChoices.trim(),
      if (json['question'] != null) json['question'].toString(),
      if (json['content'] != null) json['content'].toString(),
      if (json['raw'] != null) json['raw'].toString(),
    ].map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList(growable: false);
    if (candidates.isEmpty) return '';
    final first = candidates.first;
    return first.endsWith('?') ? first : '$first?';
  }

  static String? _contentFromChoices(dynamic choicesDyn) {
    if (choicesDyn is List && choicesDyn.isNotEmpty) {
      final first = choicesDyn.first;
      if (first is Map) {
        final msg = first['message'];
        if (msg is Map) {
          final content = msg['content'];
          if (content is String) return content;
          if (content is List && content.isNotEmpty) {
            final c0 = content.first;
            if (c0 is Map) {
              final txt = c0['text'];
              if (txt is Map && txt['value'] is String) return txt['value'] as String;
              if (txt is String) return txt;
              final v = txt?.toString(); if (v != null && v.trim().isNotEmpty) return v;
            }
          }
          if (content != null) return content.toString();
        }
        final text = first['text'];
        if (text is String) return text;
        if (text != null) return text.toString();
      }
    }
    return null;
  }

  static List<String> _parseStringList(dynamic v) {
    if (v == null) return const <String>[];
    if (v is List) {
      final nonNull = v.where((e)=>e!=null).map((e)=>e.toString());
      return nonNull.map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList(growable:false);
    }
    if (v is String) {
      final s = v.trim(); if (s.isEmpty) return const <String>[];
      final parts = s.split(RegExp(r'\n+|[•\-–—]\s+|;\s+'))
                     .map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
      return parts.isEmpty ? <String>[s] : parts;
    }
    return const <String>[];
  }

  static String _normalizeQuestions(List<String> qs) {
    if (qs.isEmpty) return '';
    final seen = <String>{}; final clean = <String>[];
    for (final raw in qs) {
      final s = raw.trim(); if (s.isEmpty) continue;
      final key = s.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (seen.contains(key)) continue; seen.add(key);
      clean.add(s.endsWith('?') ? s : '$s?');
    }
    if (clean.isEmpty) return '';
    if (clean.length == 1) return clean.first;
    return clean.map((e) => '– $e').join('\n');
  }

  static String _ensureQuestion(String s) {
    final t = s.trim(); if (t.isEmpty) return '';
    return t.endsWith('?') ? t : '$t?';
  }

  static List<String> _dedupeStrings(List<String> items) {
    final out = <String>[]; final seen = <String>{};
    for (final it in items) {
      final key = it.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key); out.add(it.trim());
    }
    return out;
  }

  static const Map<String, String> _schoolAliases = {
    'cbt': 'CBT/KVT', 'kvt': 'CBT/KVT', 'kognitive verhaltenstherapie': 'CBT/KVT',
    'cognitive behavioral therapy': 'CBT/KVT', 'act': 'ACT',
    'acceptance and commitment therapy': 'ACT', 'dbt': 'DBT',
    'dialektisch-behaviorale therapie': 'DBT', 'schema': 'Schematherapie',
    'schematherapie': 'Schematherapie', 'schema therapy': 'Schematherapie',
    'systemic': 'Systemisch', 'systemisch': 'Systemisch', 'systemic therapy': 'Systemisch',
    'psychodynamic': 'Psychodynamisch', 'psychodynamisch': 'Psychodynamisch', 'tiefenpsychologisch': 'Psychodynamisch',
    'humanistic': 'Humanistisch', 'humanistisch': 'Humanistisch', 'client-centered': 'Humanistisch',
    'personzentriert': 'Humanistisch', 'solution focused': 'Lösungsfokussiert', 'lösungsfokussiert': 'Lösungsfokussiert',
    'sfbt': 'Lösungsfokussiert', 'mi': 'Motivational Interviewing', 'motivational interviewing': 'Motivational Interviewing',
    'mindfulness': 'Achtsamkeit', 'achtsamkeit': 'Achtsamkeit', 'mbct': 'Achtsamkeit',
  };

  static List<String> _normalizeSchools(List<String> raw) {
    if (raw.isEmpty) return const <String>[];
    final out = <String>{};
    for (final r in raw) {
      final s = r.trim(); if (s.isEmpty) continue; final k = s.toLowerCase();
      if (_schoolAliases.containsKey(k)) { out.add(_schoolAliases[k]!); continue; }
      if (k.contains('kvt') || k.contains('cognitive') || k.contains('behavior')) out.add('CBT/KVT');
      else if (k.contains('act')) out.add('ACT');
      else if (k.contains('dbt')) out.add('DBT');
      else if (k.contains('schema')) out.add('Schematherapie');
      else if (k.contains('system')) out.add('Systemisch');
      else if (k.contains('dynam')) out.add('Psychodynamisch');
      else if (k.contains('human') || k.contains('client') || k.contains('person')) out.add('Humanistisch');
      else if (k.contains('solution')) out.add('Lösungsfokussiert');
      else if (k.contains('motiv')) out.add('Motivational Interviewing');
      else if (k.contains('mindful') || k.contains('achtsam') || k.contains('mbct')) out.add('Achtsamkeit');
      else out.add(_neatEllipsis(s, 40));
    }
    return out.toList(growable: false);
  }

  // ---------------- Caps / Sanitizer ----------------
  List<Map<String, String>> _capHistory(List<Map<String, String>> history, {int maxTurns = 20}) {
    if (history.isEmpty) return const [];
    final capped = history.length <= maxTurns ? history : history.sublist(history.length - maxTurns);
    return capped.map((m) => {'role': (m['role'] ?? '').toString(),
                              'content': (m['content'] ?? m['text'] ?? '').toString(),})
        .where((m) => (m['role'] ?? '').isNotEmpty && (m['content'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);
  }

  dynamic _capMemoriesSize(dynamic memories, {int maxBytes = 2048}) {
    final Map<String, dynamic>? map = _normalizeMemories(memories);
    if (map == null || map.isEmpty) return null;

    Map<String, dynamic> cur = Map<String, dynamic>.from(map);
    int Function() byteLen = () => utf8.encode(jsonEncode(cur)).length;
    if (byteLen() <= maxBytes) return cur;

    final essentials = <String, dynamic>{};
    final id = ((cur['identity'] as Map?) ?? const {});
    if (id['name'] != null) essentials['identity'] = {'name': id['name']};
    if (cur['last'] is Map) {
      final last = Map<String, dynamic>.from(cur['last'] as Map);
      final compact = <String, dynamic>{};
      if (last['topic']   != null) compact['topic']   = last['topic'];
      if (last['mood']    != null) compact['mood']    = last['mood'];
      if (last['emotion'] != null) compact['emotion'] = last['emotion'];
      if (last['date']    != null) compact['date']    = last['date'];
      if (compact.isNotEmpty) essentials['last'] = compact;
    }
    cur = essentials.isNotEmpty ? essentials : {'note': 'trimmed'};

    final int finalLen = utf8.encode(jsonEncode(cur)).length;
    if (finalLen > maxBytes) return {'note': 'trimmed'};
    return cur;
  }

  // ---------------- Memory Helpers (Backend-only) ----------------
  void _memorySave(Map<String, dynamic> json, String source) {
    try { unawaited(MemoryService.instance.saveFromWorker(json, source: source)); } catch (_) {}
  }

  void _appendMemoryHints(Map<String, dynamic> payload) {
    final bool consent = payload['memory_consent'] == true ||
        (((payload['context'] as Map?)?['memory_consent']) == true);
    if (!consent) return;
    try {
      final hint = MemoryService.instance.buildContextHint(maxFacets: 3, maxTags: 5, maxAgeDays: 14);
      if (hint != null) {
        payload['context_hint'] = {
          if (hint.facets  != null) 'recent_facets': hint.facets,
          if (hint.tags    != null) 'recent_tags':   hint.tags,
          if (hint.topics  != null) 'last_themes':   hint.topics,
        };
      }
    } catch (_) {}
  }

  void _attachMemories(Map<String, dynamic> payload, {dynamic memories, bool? memoryConsent}) {
    final bool consentEffective = memoryConsent ??
        (payload['memory_consent'] == true) ||
        (((payload['context'] as Map?)?['memory_consent']) == true);
    if (!consentEffective) return;

    final mem = _normalizeMemories(memories);
    if (mem == null || mem.isEmpty) return;

    final ctx = <String, dynamic>{'memories': mem};
    final existing = payload['context'];
    if (existing is Map) {
      final merged = <String, dynamic>{}
        ..addAll(existing.map((k, v) => MapEntry(k.toString(), v)))
        ..addAll(ctx);
      payload['context'] = merged;
    } else {
      payload['context'] = ctx;
    }
  }

  Map<String, dynamic>? _normalizeMemories(dynamic src) {
    if (src == null) return null;

    Map<String, dynamic>? asMap(dynamic x) {
      if (x is Map<String, dynamic>) return x;
      if (x is Map) return x.map((k, v) => MapEntry(k.toString(), v));
      try { final m = x.toMap?.call();
        if (m is Map) return m.map((k, v) => MapEntry(k.toString(), v));
      } catch (_){}
      try { final j = x.toJson?.call();
        if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v));
        if (j is String && j.trim().startsWith('{')) {
          final parsed = jsonDecode(j);
          if (parsed is Map) return parsed.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_){}
      if (x is String && x.trim().startsWith('{')) {
        try { final parsed = jsonDecode(x);
          if (parsed is Map) return parsed.map((k, v) => MapEntry(k.toString(), v));
        } catch (_){}
      }
      return null;
    }

    final map = asMap(src);
    if (map == null) return null;

    Map<String, dynamic> norm = {};
    map.forEach((k, v) {
      final key = k.toString();
      switch (key) {
        case 'recentTopics': norm['recent_topics'] = v; break;
        case 'moodTrend':    norm['mood_trend']    = v; break;
        case 'nextHint':     norm['next_hint']     = v; break;
        case 'insightScore': norm['insight_score'] = v; break;
        case 'contextFacets':norm['context_facets']= v; break;
        case 'facts':
        case 'memoryFacts':  norm['facts']         = v; break;
        case 'summary':      norm['summary']       = v; break;
        // V7: Alias timelineRecent → timeline.recent
        case 'timelineRecent':
          final tl = Map<String, dynamic>.from((norm['timeline'] as Map?) ?? const {});
          tl['recent'] = v; norm['timeline'] = tl; break;
        default: norm[key] = v;
      }
    });
    return norm;
  }

  void _appendContactTints(Map<String, dynamic> payload, {required String locale, required String tz}) {
    final tints = {'brand': _brand, 'channel': _channel, 'samfring': _samfring, 'locale': locale, 'tz': tz};
    payload['contact_tints'] = Map<String, dynamic>.from(tints);
    payload['contact_tins']  = Map<String, dynamic>.from(tints);
  }

  void _appendByteContext(Map<String, dynamic> payload, {int maxBytes = 2048}) {
    try {
      final mem = MemoryService.instance; final dyn = mem as dynamic;
      List<int>? bytes;
      try { bytes = dyn.tryGetByteContext?.call(maxBytes); } catch (_){}
      try { bytes ??= dyn.exportByteContext?.call(maxBytes); } catch (_){}
      try { bytes ??= dyn.byteContext?.call(maxBytes); } catch (_){}
      if (bytes is List<int> && bytes.isNotEmpty) {
        final capped = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
        payload['context_bytes_b64'] = base64Encode(capped);
      }
    } catch (_) {}
  }

  Map<String, dynamic> _buildSessionMap(ReflectionSession s, {List<Map<String, String>> history = const []}) => {
    'id': s.threadId, 'turn': s.turnIndex, 'max_turns': s.maxTurns, 'history': _capHistory(history, maxTurns: 20),
  };

  Map<String, dynamic> _basePayload({
    required String text,
    required String locale,
    required String tz,
    required ReflectionSession session,
    List<Map<String, String>> messages = const [],
    String? intent,
    UserAction? userAction,
    Map<String, dynamic>? clientContext,
  }) {
    _saveUserTurnBestEffort(text);
    _maybeLearnName(text);

    final capped = _capHistory(messages, maxTurns: 20);

    final payload = <String, dynamic>{
      'text': text, 'messages': capped, 'locale': locale, 'tz': tz,
      'session': _buildSessionMap(session, history: capped),
      if (intent != null) 'intent': intent,
      if (userAction != null) 'user_action': userAction.toJson(),
      if (clientContext != null && clientContext.isNotEmpty)
        'client_context': _sanitizeClientContext(clientContext),
    };

    payload['memory_consent'] ??= _memoryConsentDefault();
    _ensureClientMemoryMergeFlag(payload, consent: payload['memory_consent'] == true);

    try {
      final bool consentNow = payload['memory_consent'] == true;
      final bool activeNow  = _memoryActiveNow();

      if (consentNow && activeNow) {
        Map<String, dynamic> mem = <String, dynamic>{};
        try {
          final dyn = (MemoryService.instance as dynamic).buildContextMemories;
          if (dyn is Function) {
            final out = Function.apply(dyn, const [], const {#consent: true});
            if (out is Map) mem = out.map((k, v) => MapEntry(k.toString(), v));
          }
        } catch (_) {}

        final quickName = _extractNameFromTextQuick(text);
        if (quickName != null && quickName.isNotEmpty) {
          final id = Map<String, dynamic>.from((mem['identity'] as Map?) ?? const {});
          id['name'] = quickName; mem['identity'] = id;
        }

        final lastMap = Map<String, dynamic>.from((mem['last'] as Map?) ?? const {});
        lastMap['mood'] ??= classifyMoodSync(text);
        final emo = detectEmotionSync(text);
        if (emo != null && (lastMap['emotion'] == null)) lastMap['emotion'] = emo;
        lastMap['date'] ??= DateTime.now().toUtc().toIso8601String().split('T').first;
        if (lastMap.isNotEmpty) mem['last'] = lastMap;

        final recall = _buildRecallSafe(consent: consentNow, mem: mem, maxBytes: 240);
        if (recall != null && recall.isNotEmpty) mem['recall'] = recall;

        final cappedMem = _capMemoriesSize(mem, maxBytes: 2048);
        if (cappedMem != null && cappedMem.isNotEmpty) {
          final ctx = Map<String, dynamic>.from((payload['context'] as Map?) ?? const <String, dynamic>{});
          ctx['memories'] = cappedMem;
          payload['context'] = ctx;
          payload['memories'] ??= cappedMem; // Legacy
        }
        _setClientMemoryFlagOnBody(payload, enabled: true);
      } else {
        if (payload['context'] is Map) (payload['context'] as Map).remove('memories');
        payload.remove('memories');
        _setClientMemoryFlagOnBody(payload, enabled: false);
      }
    } catch (_) {
      _setClientMemoryFlagOnBody(payload, enabled: false);
      if (payload['context'] is Map) (payload['context'] as Map).remove('memories');
      payload.remove('memories');
    }

    _mergeExtraMetaFromClientContext(payload, clientContext);
    _appendMemoryHints(payload);
    _appendContactTints(payload, locale: locale, tz: tz);
    _appendByteContext(payload);
    return payload;
  }

  void _mergeExtraMetaFromClientContext(Map<String, dynamic> payload, Map<String, dynamic>? clientContext) {
    if (clientContext == null || clientContext.isEmpty) return;

    dynamic pick(List<String> keys) { for (final k in keys) { if (clientContext.containsKey(k)) return clientContext[k]; } return null; }

    final speech = pick(const ['speech_meta','speechMeta']);
    if (speech is Map && speech is! Map<String, dynamic>) {
      payload['speech_meta'] = (speech as Map).map((k, v) => MapEntry(k.toString(), v));
    } else if (speech is Map<String, dynamic> && speech.isNotEmpty) {
      payload['speech_meta'] = Map<String, dynamic>.from(speech);
    }

    final skill = pick(const ['skill']);
    if (skill != null && skill.toString().trim().isNotEmpty) {
      payload['skill'] = skill.toString().trim();
    }

    final facets = pick(const ['facets']);
    if (facets is List && facets.isNotEmpty) {
      payload['facets'] = facets.where((e)=>e!=null).map((e)=>e.toString())
                                .where((s)=>s.trim().isNotEmpty).toList();
    }

    final topicPin = pick(const ['topic_pin','topicPin']);
    if (topicPin != null) {
      final v = topicPin;
      if (v is bool) payload['topic_pin'] = v;
      else {
        final s = v.toString().trim().toLowerCase();
        payload['topic_pin'] = (s == 'true' || s == '1' || s == 'yes');
      }
    }
  }

  Map<String, dynamic> _sanitizeClientContext(Map<String, dynamic> src) {
    const allowed = {
      'appVersion','build','platform','device','os','screen','net','flags','ab','experiment',
      'source','campaign','locale','tz','speech_meta','speechMeta','skill','facets','topic_pin','topicPin',
    };
    final out = <String, dynamic>{};
    for (final e in src.entries) {
      final k = e.key.toString(); if (allowed.contains(k)) out[k] = e.value;
    }
    return out;
  }

  Future<Map<String, dynamic>?> _postMaybe(String path, Map<String, dynamic> payload, {String? saveSource}) async {
    if (_http == null) return null;

    if (!_outGateOpen && !_isHealthPath(path)) {
      final jitter = 90 + _rand.nextInt(90);
      await Future.delayed(Duration(milliseconds: jitter));
    }

    try {
      final json = await _http!(path, payload).timeout(_timeout);
      if (saveSource != null) _memorySave(json, saveSource);
      return json;
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>?> _tryEndpoints({
    required List<String> endpoints,
    required Map<String, dynamic> payload,
  }) async {
    const bases = [420, 900, 1800];
    for (int i = 0; i < endpoints.length; i++) {
      final path = endpoints[i];
      final json = await _postMaybe(path, payload, saveSource: path.replaceFirst('/', ''));
      if (json != null) return json;
      if (i < endpoints.length - 1) {
        final jitter = _rand.nextInt(180);
        final idx = i.clamp(0, bases.length - 1).toInt();
        await Future.delayed(Duration(milliseconds: bases[idx] + jitter));
      }
    }
    return null;
  }

  Map<String, dynamic> _closureFallback(ReflectionSession? session) => <String, dynamic>{
    'closure': {'mood_intro': {'text': ''}},
    'flow': {'recommend_end': true, 'talk_only': false, 'allow_reflect': true, 'suggest_break': false, 'mood_prompt': true},
    if (session != null) 'session': _buildSessionMap(session),
  };

  // ---------------- Parser Utils ----------------
  static int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static bool _boolLike(dynamic v) {
    if (v is bool) return v;
    if (v is num)  return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y';
    }
    return false;
  }

  // ---------------- Helpers für Struktur/Depth ----------------
  String _estimateDepth(List<Map<String, String>> messages) {
    // sehr einfache Heuristik: Länge & Satzzeichen
    final last = messages.isNotEmpty ? (messages.last['content'] ?? '') : '';
    final len = last.length;
    final q = RegExp(r'[?]').allMatches(last).length;
    final excl = RegExp(r'[!]').allMatches(last).length;
    final score = (len ~/ 80) + q + (excl > 0 ? 1 : 0);
    if (score >= 5) return 'deep';
    if (score >= 3) return 'medium';
    return 'light';
  }

  List<String> _nextStepsForLever(String lever) {
    switch (lever) {
      case 'Gedanken':
        return const ['Einen Satz sanft hinterfragen …', 'Gegenbeispiele suchen …', 'Einen kleinen, hilfreichen Reframing-Versuch notieren …'];
      case 'Gefühle':
        return const ['Gefühl benennen & atmen (4–6) …', 'Körper-Ort kurz scannen …', 'Einen sicheren Ort visualisieren …'];
      case 'Körper':
        return const ['Schultern lockern, 3× tief atmen …', 'Ein Glas Wasser trinken …', 'Kurz aufstehen und strecken …'];
      case 'Verhalten':
        return const ['1 sehr kleinen Schritt wählen …', 'Timer auf 5 Minuten setzen …', 'Ablenkung für 10 Min. parken …'];
      case 'Kontext':
        return const ['Rahmen klären (Zeit/Ort) …', 'Eine Person um Hilfe bitten …', 'Grenze freundlich markieren …'];
      default:
        return const ['Einen nächsten kleinen Schritt wählen …'];
    }
  }
}
