// lib/shared/analytics/offline_queue.dart
//
// AnalyticsOfflineQueue — robuste Offline-Telemetrie ohne PII (v1.0 · 2025-10-23)
// -----------------------------------------------------------------------------
// Ziele:
// • retry queue einbauen            → Exponential Backoff + Jitter, pro Event.
// • events lokal puffern            → Speicher-Interface + InMemory/Datei-Implementierung.
// • flush bedingungen setzen        → Timer, Count-Threshold, manuell, Netzwerk-Check-Hook.
// • fehler robust behandeln         → retriable vs. nicht-retriable, Caps & Drop-Policy.
// • telemetry ohne pii              → Sanitizer (Allow-/Block-List, Typ-Normalisierung).
//
// Abhängigkeiten: Nur Dart (async/convert/io/math). Keine externen Pakete nötig.
// Hinweis: FileOfflineStorage nutzt dart:io und benötigt einen gültigen Pfad im App-Speicher.
// Für Web kann InMemoryStorage verwendet werden.
//
// Beispiel:
// final queue = AnalyticsOfflineQueue(
//   transport: (batch) async {
//     // Sende batch (List<Map>) an euren Endpoint (HTTP o. ä.)
//     // return TransportOutcome(success: true);
//     throw UnimplementedError();
//   },
//   storage: InMemoryOfflineStorage(), // oder FileOfflineStorage(filePath: ...)
//   isNetworkAvailable: () => connectivity.isOnline, // optional
// );
//
// queue.track('screen_view', {'screen': 'ProScreen', 'feature': 'mood_chart'});
// await queue.flush(); // z. B. an App-Resume oder beim Schließen.
//
// -----------------------------------------------------------------------------
//
// Hinweis: Diese Datei importiert 'dart:io' für die File-Variante. Für Web
// sollte nur InMemoryOfflineStorage verwendet werden.
//
// Lint-Ausnahme: In diesem Modul sind interne Typen (_QueueItem) Teil der
// Storage-Schnittstelle. Wir unterdrücken den Hinweis gezielt.
// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File; // Für FileOfflineStorage (mobil/desktop)
import 'dart:math';

typedef JsonMap = Map<String, dynamic>;

/// Ergebnis des Transport-Versands (Batch).
class TransportOutcome {
  final bool ok;          // erfolgreich übertragen
  final bool retriable;   // bei Fehler: ob Retry sinnvoll (z. B. Netzwerk/5xx)
  final int? status;      // optionaler HTTP-Status
  final String? message;  // optionaler Fehlertext

  const TransportOutcome({
    required this.ok,
    this.retriable = true,
    this.status,
    this.message,
  });

  factory TransportOutcome.success() => const TransportOutcome(ok: true, retriable: false);
  factory TransportOutcome.retry([String? msg]) =>
      TransportOutcome(ok: false, retriable: true, message: msg);
  factory TransportOutcome.fail([String? msg]) =>
      TransportOutcome(ok: false, retriable: false, message: msg);
}

/// Schnittstelle für die physische Queue-Persistenz.
abstract class OfflineStorage {
  /// Lädt den vollständigen Queue-Inhalt (stabil sortiert: alt → neu).
  Future<List<_QueueItem>> load();

  /// Schreibt den vollständigen Queue-Inhalt (ersetzt alles).
  Future<void> save(List<_QueueItem> all);

  /// Optional: schneller Length-Pfad (kann per load() emuliert werden).
  Future<int> length() async => (await load()).length;
}

/// Einfache In-Memory-Variante (prozesslokal; nicht persistent).
class InMemoryOfflineStorage implements OfflineStorage {
  List<_QueueItem> _items = <_QueueItem>[];

  @override
  Future<List<_QueueItem>> load() async => List<_QueueItem>.from(_items);

  @override
  Future<void> save(List<_QueueItem> all) async {
    _items = List<_QueueItem>.from(all);
  }

  @override
  Future<int> length() async => _items.length;
}

/// Datei-basierte Persistenz (JSON); Pfad muss beschreibbar sein.
/// Tipp: z. B. per path_provider ermitteln und "offline_analytics_queue.json" setzen.
class FileOfflineStorage implements OfflineStorage {
  final String filePath;

  FileOfflineStorage({required this.filePath});

  File get _file => File(filePath);

  @override
  Future<List<_QueueItem>> load() async {
    try {
      if (!await _file.exists()) return <_QueueItem>[];
      final txt = await _file.readAsString();
      if (txt.trim().isEmpty) return <_QueueItem>[];
      final raw = jsonDecode(txt);
      if (raw is! List) return <_QueueItem>[];
      return raw
          .map<_QueueItem>((e) => _QueueItem.fromJson(e as JsonMap))
          .toList()
        ..sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
    } catch (_) {
      // Korrupt? Vorsichtig leeren (keine Exceptions nach außen).
      return <_QueueItem>[];
    }
  }

  @override
  Future<void> save(List<_QueueItem> all) async {
    try {
      final data = all.map((e) => e.toJson()).toList(growable: false);
      await _file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // Falls Schreiben scheitert: still (Events bleiben im Speicher des Aufrufers).
    }
  }

  @override
  Future<int> length() async {
    try {
      if (!await _file.exists()) return 0;
      final txt = await _file.readAsString();
      if (txt.trim().isEmpty) return 0;
      final raw = jsonDecode(txt);
      if (raw is List) return raw.length;
      return 0;
    } catch (_) {
      return 0;
    }
  }
}

/// Öffentliche API: Offline-Queue für Telemetrie-Events (ohne PII).
class AnalyticsOfflineQueue {
  // --- Konfiguration ---
  final Future<TransportOutcome> Function(List<JsonMap> batch) transport;
  final OfflineStorage storage;

  /// Max. Elemente in der Queue (älteste werden verworfen).
  final int maxBuffer;

  /// Ab dieser Anzahl gepufferter Events wird ein Flush angestoßen.
  final int flushCountThreshold;

  /// Max. Größe eines Batches beim Versand.
  final int maxBatchSize;

  /// Zyklische Flush-Periode (sofern Timer aktiv).
  final Duration flushInterval;

  /// Retry/Backoff
  final int maxRetryAttempts;
  final Duration initialBackoff;
  final Duration maxBackoff;

  /// Optionaler Netzwerkchecker (true = online).
  final bool Function()? isNetworkAvailable;

  /// Sanitizer-Listen (telemetry ohne PII)
  final Set<String> allowedProps; // Whitelist; leere Menge → alle erlaubt (außer blockiert)
  final Set<String> blockedProps; // Blacklist; gewinnt immer

  /// Key-Normalisierung: max. Länge pro Wert (Strings werden ggf. gekürzt).
  final int maxStringLength;

  // --- Zustand ---
  Timer? _timer;
  bool _flushing = false;
  DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);
  final Random _rand = Random.secure();

  AnalyticsOfflineQueue({
    required this.transport,
    OfflineStorage? storage,
    this.maxBuffer = 500,
    this.flushCountThreshold = 30,
    this.maxBatchSize = 50,
    this.flushInterval = const Duration(seconds: 30),
    this.maxRetryAttempts = 5,
    this.initialBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(minutes: 2),
    this.isNetworkAvailable,
    Set<String>? allowedProps,
    Set<String>? blockedProps,
    this.maxStringLength = 256,
    bool startPeriodicFlush = true,
  })  : storage = storage ?? InMemoryOfflineStorage(),
        allowedProps = (allowedProps ?? const <String>{
          // unkritische, aggregierbare Felder (Beispiele)
          'screen', 'action', 'feature', 'category',
          'success', 'error_code', 'retry_count',
          'duration_ms', 'network', 'locale',
          'app_version', 'platform', 'build', 'release',
          'session_id', // kurzlebig, pseudonym (keine User-ID!)
        }),
        blockedProps = (blockedProps ?? const <String>{
          // typische PII-Schlüssel — werden gnadenlos entfernt
          'name', 'full_name', 'first_name', 'last_name',
          'email', 'mail', 'phone', 'phone_number',
          'address', 'street', 'zip', 'city',
          'user_id', 'account_id', 'customer_id',
          'message', 'content', 'text', 'note', 'body',
        }) {
    if (startPeriodicFlush) _startTimer();
  }

  // -----------------------------------------------------------------------------
  // Öffentliche API
  // -----------------------------------------------------------------------------

  /// Fügt ein Ereignis hinzu (wird sanitisiert) und flusht ggf. nach Bedingungen.
  Future<void> track(String type, [Map<String, dynamic>? props]) async {
    final clean = _sanitizeProps(props ?? const {});
    final evt = _TelemetryEvent(
      type: _cleanKey(type),
      ts: DateTime.now().toUtc(),
      props: clean,
    );

    var q = await storage.load();

    // Ring-Puffer: Überlauf → älteste verwerfen
    if (q.length >= maxBuffer) {
      final over = q.length - maxBuffer + 1;
      if (over > 0) q = q.sublist(over);
    }

    q.add(_QueueItem.fromEvent(evt));
    await storage.save(q);

    // Flush-Bedingungen
    if (q.length >= flushCountThreshold) {
      unawaited(flush(reason: 'threshold'));
    }
  }

  /// Komfort: Fehler-Event tracken (ohne Stacktrace/PII).
  Future<void> trackError(String code, {String? where}) {
    return track('error', {
      'error_code': _truncate(code),
      if (where != null && where.trim().isNotEmpty) 'feature': _truncate(where),
      'success': false,
    });
  }

  /// Löst einen Flush aus, wenn Bedingungen erfüllt (oder force=true).
  Future<void> flush({bool force = false, String? reason}) async {
    if (_flushing) return;
    if (!force) {
      // Netzwerkbedingung
      if (isNetworkAvailable != null && !isNetworkAvailable!()) return;

      // Intervallbedingung
      final now = DateTime.now();
      if (now.difference(_lastFlush) < flushInterval) {
        // kein Count-Trigger? dann warten
        final len = await storage.length();
        if (len < flushCountThreshold) return;
      }
    }

    _flushing = true;
    try {
      var queue = await storage.load();
      if (queue.isEmpty) return;

      final now = DateTime.now().toUtc();

      // Nur reife Items (nextEligibleAt <= now) bis maxBatchSize
      final batchItems = <_QueueItem>[];
      for (final it in queue) {
        if (batchItems.length >= maxBatchSize) break;
        if (!it.isExpired(now)) continue;
        batchItems.add(it);
      }

      if (batchItems.isEmpty) return;

      final payload = batchItems.map((e) => e.event.toJson()).toList(growable: false);

      TransportOutcome outcome;
      try {
        outcome = await transport(payload);
      } catch (_) {
        outcome = TransportOutcome.retry('transport_exception');
      }

      if (outcome.ok) {
        // Erfolgreich: entferne versendete Items aus Queue
        final sentIds = batchItems.map((e) => e.id).toSet();
        queue = queue.where((e) => !sentIds.contains(e.id)).toList(growable: true);
        await storage.save(queue);
        _lastFlush = DateTime.now();
        return;
      }

      // Fehler: retriable → Backoff erhöhen; sonst verwerfen.
      final updated = <_QueueItem>[];

      for (final it in batchItems) {
        if (!outcome.retriable) {
          // nicht-retriable → Drop (z. B. 4xx Validation)
          continue;
        }
        final next = it.incrementRetry(
          maxRetryAttempts: maxRetryAttempts,
          initial: initialBackoff,
          maxBackoff: maxBackoff,
          rand: _rand,
        );
        if (next == null) {
          // Retry-Limit erreicht → Drop
          continue;
        }
        updated.add(next);
      }

      // Queue neu zusammensetzen: unveränderte + updated (statt der alten batchItems)
      final sentIds = batchItems.map((e) => e.id).toSet();
      final survivors = queue.where((e) => !sentIds.contains(e.id)).toList(growable: true);
      survivors.addAll(updated);
      await storage.save(survivors);
      _lastFlush = DateTime.now();
    } finally {
      _flushing = false;
    }
  }

  /// Manuell Intervall-Flush starten/stoppen (z. B. bei App-Background).
  void startPeriodicFlush() => _startTimer();
  void stopPeriodicFlush() => _stopTimer();

  /// App-Lifecycle Hooks (optional)
  Future<void> onAppResumed() => flush(reason: 'resume');
  Future<void> onAppBackgrounded() => flush(reason: 'background');

  Future<void> dispose() async {
    _stopTimer();
    // kein automatisches Flush on dispose (kann der Host entscheiden)
  }

  // -----------------------------------------------------------------------------
  // Timer/Intervall
  // -----------------------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(flushInterval, (_) {
      unawaited(flush(reason: 'timer'));
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // -----------------------------------------------------------------------------
  // Sanitizer (ohne PII) + Normalisierung
  // -----------------------------------------------------------------------------

  JsonMap _sanitizeProps(Map<String, dynamic> input) {
    final out = <String, dynamic>{};

    input.forEach((k, v) {
      final key = _cleanKey(k);
      if (key.isEmpty) return;

      // Blocklist gewinnt immer
      if (blockedProps.contains(key)) return;

      // Wenn Allowlist gesetzt → nur erlaubte Keys (ansonsten alle)
      if (allowedProps.isNotEmpty && !allowedProps.contains(key)) return;

      out[key] = _normalizeValue(v);
    });

    return out;
  }

  String _cleanKey(String key) {
    // Normiert Keys auf [a-z0-9_], kürzt und entfernt doppelte Trennzeichen.
    final lower = key.trim().toLowerCase();
    final replaced = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final squashed = replaced.replaceAll(RegExp(r'_+'), '_');
    final trimmed = squashed.replaceAll(RegExp(r'^_|_$'), '');
    return trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;
  }

  dynamic _normalizeValue(dynamic v) {
    if (v == null) return null;

    // Nur primitive JSON-Typen behalten; Rest serialisieren + kürzen.
    if (v is num || v is bool) return v;
    if (v is String) return _truncate(v);

    try {
      final s = jsonEncode(v);
      return _truncate(s);
    } catch (_) {
      return _truncate(v.toString());
    }
  }

  String _truncate(String s) {
    if (s.length <= maxStringLength) return s;
    return s.substring(0, maxStringLength);
  }
}

// ============================================================================
// Interne Queue-Datenstrukturen
// ============================================================================

class _TelemetryEvent {
  final String type;
  final DateTime ts; // UTC
  final JsonMap props;

  _TelemetryEvent({required this.type, required this.ts, required this.props});

  JsonMap toJson() => <String, dynamic>{
        'type': type,
        'ts': ts.toIso8601String(),
        'props': props,
      };

  factory _TelemetryEvent.fromJson(JsonMap j) => _TelemetryEvent(
        type: (j['type'] as String?) ?? 'unknown',
        ts: DateTime.tryParse((j['ts'] as String?) ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        props: (j['props'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      );
}

class _QueueItem {
  final String id; // stabil (für Entfernen/Update)
  final _TelemetryEvent event;
  final int retryCount;
  final DateTime nextEligibleAt; // frühester Versandzeitpunkt (Backoff)
  final DateTime enqueuedAt;

  _QueueItem({
    required this.id,
    required this.event,
    required this.retryCount,
    required this.nextEligibleAt,
    required this.enqueuedAt,
  });

  bool isExpired(DateTime nowUtc) => !nowUtc.isBefore(nextEligibleAt);

  _QueueItem? incrementRetry({
    required int maxRetryAttempts,
    required Duration initial,
    required Duration maxBackoff,
    required Random rand,
  }) {
    final nextRetry = retryCount + 1;
    if (nextRetry > maxRetryAttempts) return null;

    // Exponential Backoff mit Jitter (Full Jitter)
    final base = initial.inMilliseconds * pow(2, (nextRetry - 1)).toDouble();
    final capped = min(base, maxBackoff.inMilliseconds.toDouble());
    final delayMs = rand.nextInt(capped.floor() + 1); // 0..capped
    final nextAt = DateTime.now().toUtc().add(Duration(milliseconds: delayMs));

    return _QueueItem(
      id: id,
      event: event,
      retryCount: nextRetry,
      nextEligibleAt: nextAt,
      enqueuedAt: enqueuedAt,
    );
  }

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'event': event.toJson(),
    'retry': retryCount,
    'next': nextEligibleAt.toIso8601String(),
    'enq': enqueuedAt.toIso8601String(),
  };

  factory _QueueItem.fromJson(JsonMap j) => _QueueItem(
        id: (j['id'] as String?) ?? _makeId(),
        event: _TelemetryEvent.fromJson((j['event'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{}),
        retryCount: (j['retry'] as num?)?.toInt() ?? 0,
        nextEligibleAt: DateTime.tryParse((j['next'] as String?) ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        enqueuedAt: DateTime.tryParse((j['enq'] as String?) ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      );

  factory _QueueItem.fromEvent(_TelemetryEvent e) => _QueueItem(
        id: _makeId(),
        event: e,
        retryCount: 0,
        nextEligibleAt: DateTime.now().toUtc(),
        enqueuedAt: DateTime.now().toUtc(),
      );

  static String _makeId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final rnd = (Random.secure().nextDouble() * 1e9).floor();
    return '$now-$rnd';
  }
}
