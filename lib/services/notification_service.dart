// lib/services/notification_service.dart
//
// NotificationService — Lokale Reminders (Pro, ohne neue Deps)
// ------------------------------------------------------------
// Ziele
// • Keine neuen Packages: Platform-Bridge via MethodChannel "zen.notifications"
// • API: init, Permission, show/schedule, cancel, pending, Badge/Settings
// • Web/Unsupported: No-Op (sichere Rückgaben)
// • Tap-Events: Stream<String> (payload)
// • Robust: id-Helfer, Guards, defensive Fehlerbehandlung
//
// Native Bridge (später):
// • Android: Kanal erstellen + POST_NOTIFICATIONS (API 33+) + AlarmManager/WorkManager
// • iOS: UNUserNotificationCenter (Request/Auth/Categories), Badge-API
// • Optional: macOS; andere Plattformen No-Op
//
// MethodChannel-Contract (Vorschlag):
//   "configure" -> { android_channel_id, android_channel_name, android_channel_desc }
//   "requestPermission" -> { granted: bool }
//   "hasPermission" -> { granted: bool }
//   "show" -> { id, title, body, payload? }
//   "scheduleAt" -> { id, epochMillis, title, body, payload?, allowWhileIdle? }
//   "scheduleDaily" -> { id, hour, minute, title, body, payload? }
//   "scheduleWeekly" -> { id, weekday(1=Mon..7=Sun), hour, minute, title, body, payload? }
//   "cancel" -> { id }
//   "cancelAll" -> {}
//   "pending" -> { list: [ {id, title, body, payload?, whenMillis?}, ... ] }
//   "setBadge" -> { count }
//   "clearBadge" -> {}
//   "openSettings" -> {}
//
//   Callbacks (MethodCall vom Native auf Dart):
//   - "onSelect" -> { payload? }   // Nutzer tippt Notification
//
// Anbindung:
//   final ns = NotificationService.instance;
//   await ns.init();
//   await ns.requestPermission();
//   await ns.scheduleDaily(
//     id: NotificationService.idFrom('reflection.08:00'),
//     time: const TimeOfDay(hour: 8, minute: 0),
//     title: 'Kurze Reflexion',
//     body: '2 Minuten für dich – bereit?',
//   );

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const MethodChannel _ch = MethodChannel('zen.notifications');

  /// Ob `init()` erfolgreich lief (bzw. auf Web immer true → No-Op).
  bool _ready = false;

  /// Permission-Status (UI-bindbar)
  final ValueNotifier<bool> permissionGranted = ValueNotifier<bool>(false);

  /// Taps auf Notifications (payload als String; kann JSON sein)
  final StreamController<String?> _tapCtrl = StreamController<String?>.broadcast();
  Stream<String?> get onTap => _tapCtrl.stream;

  // -----------------------------
  // Init & Permission
  // -----------------------------

  /// Initialisiert den Native-Kanal. Safe mehrfach aufrufbar.
  /// Android: Erstellt Notification-Channel (falls nicht vorhanden).
  Future<bool> init({
    String androidChannelId = 'zenyourself.main',
    String androidChannelName = 'ZenYourself',
    String androidChannelDescription = 'Achtsame Erinnerungen',
  }) async {
    if (kIsWeb) {
      _ready = true;
      permissionGranted.value = true; // Web: No-Op/Immer "ok" für UI
      return true;
    }

    if (!_isSupportedPlatform) {
      _ready = true; // No-Op auf nicht unterstützten Plattformen
      permissionGranted.value = false;
      return true;
    }

    try {
      // Native → Dart Callback-Handler
      _ch.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onSelect':
            final payload = call.arguments is Map ? call.arguments['payload'] : call.arguments;
            _tapCtrl.add((payload?.toString().trim().isEmpty ?? true) ? null : payload.toString());
            break;
          case 'onPermissionChanged':
            final granted = (call.arguments is Map)
                ? (call.arguments['granted'] == true)
                : (call.arguments == true);
            permissionGranted.value = granted;
            break;
        }
      });

      // Konfiguration/Channel-Setup (id/name/desc)
      await _ch.invokeMethod('configure', {
        'android_channel_id': androidChannelId,
        'android_channel_name': androidChannelName,
        'android_channel_desc': androidChannelDescription,
      });

      // Permission abfragen
      final has = await hasPermission();
      permissionGranted.value = has;
      _ready = true;
      return true;
    } catch (_) {
      _ready = false;
      permissionGranted.value = false;
      return false;
    }
  }

  /// Fragt eine Notification-Berechtigung aktiv an (iOS / Android 13+).
  Future<bool> requestPermission() async {
    if (!_ready || !_isSupportedPlatform) return kIsWeb ? true : false;
    try {
      final res = await _ch.invokeMethod('requestPermission');
      final ok = (res is Map) ? (res['granted'] == true) : (res == true);
      permissionGranted.value = ok;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Prüft die Berechtigung (ohne Dialog).
  Future<bool> hasPermission() async {
    if (!_ready || !_isSupportedPlatform) return kIsWeb ? true : false;
    try {
      final res = await _ch.invokeMethod('hasPermission');
      return (res is Map) ? (res['granted'] == true) : (res == true);
    } catch (_) {
      return false;
    }
  }

  /// Öffnet die System-Einstellungen (Benachrichtigungen).
  Future<void> openSystemSettings() async {
    if (!_ready || !_isSupportedPlatform) return;
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }

  // -----------------------------
  // Show & Schedule
  // -----------------------------

  /// Zeigt sofort eine lokale Notification.
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_canNotify) return false;
    try {
      await _ch.invokeMethod('show', {
        'id': id,
        'title': title,
        'body': body,
        if (payload != null) 'payload': payload,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Plant eine Notification zu einem absoluten Zeitpunkt (lokale Zeit).
  Future<bool> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? payload,
    bool allowWhileIdle = true,
  }) async {
    if (!_canNotify) return false;
    try {
      final epoch = when.millisecondsSinceEpoch;
      await _ch.invokeMethod('scheduleAt', {
        'id': id,
        'epochMillis': epoch,
        'title': title,
        'body': body,
        'allowWhileIdle': allowWhileIdle,
        if (payload != null) 'payload': payload,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Plant eine tägliche Erinnerung (lokale Zeit).
  Future<bool> scheduleDaily({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_canNotify) return false;
    try {
      await _ch.invokeMethod('scheduleDaily', {
        'id': id,
        'hour': time.hour,
        'minute': time.minute,
        'title': title,
        'body': body,
        if (payload != null) 'payload': payload,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Plant eine wöchentliche Erinnerung (1=Montag … 7=Sonntag, lokale Zeit).
  Future<bool> scheduleWeekly({
    required int id,
    required int weekday,
    required TimeOfDay time,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_canNotify) return false;
    final wd = weekday.clamp(1, 7);
    try {
      await _ch.invokeMethod('scheduleWeekly', {
        'id': id,
        'weekday': wd,
        'hour': time.hour,
        'minute': time.minute,
        'title': title,
        'body': body,
        if (payload != null) 'payload': payload,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // -----------------------------
  // Cancel, Pending, Badge
  // -----------------------------

  Future<void> cancel(int id) async {
    if (!_ready || !_isSupportedPlatform) return;
    try {
      await _ch.invokeMethod('cancel', {'id': id});
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready || !_isSupportedPlatform) return;
    try {
      await _ch.invokeMethod('cancelAll');
    } catch (_) {}
  }

  /// Liefert pending Notifications (falls vom Native unterstützt).
  Future<List<Map<String, dynamic>>> pending() async {
    if (!_ready || !_isSupportedPlatform) return const <Map<String, dynamic>>[];
    try {
      final res = await _ch.invokeMethod('pending');
      final list = (res is Map) ? res['list'] : res;
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
      }
      return const <Map<String, dynamic>>[];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> setBadge(int count) async {
    if (!_ready || !_isSupportedPlatform) return;
    try {
      await _ch.invokeMethod('setBadge', {'count': count});
    } catch (_) {}
  }

  Future<void> clearBadge() async => setBadge(0);

  // -----------------------------
  // Utils
  // -----------------------------

  /// Stabile ID aus String-Key (z. B. "reflection.08:00").
  static int idFrom(String key) {
    // einfache, aber stabile 31-bit Hash-ID
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    if (h == 0) h = 1;
    return h;
  }

  bool get _canNotify => _ready && !_isWebNoop && permissionGranted.value;

  bool get _isWebNoop => kIsWeb;

  bool get _isSupportedPlatform {
    final p = defaultTargetPlatform;
    return p == TargetPlatform.android || p == TargetPlatform.iOS;
  }

  /// Aufräumen (z. B. in Tests)
  void dispose() {
    _tapCtrl.close();
  }
}
