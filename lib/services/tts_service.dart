// [MERGE SIGNAL] lib/services/tts_service.dart — v1.0.3 (2025-11-09)
// TtsService — Oxford Zen (robust, ohne zusätzliche Pakete)
// -----------------------------------------------------------------------------
// • MethodChannel-basierter TTS-Wrapper mit sauberem Fallback (Simulation).
// • Läuft auf iOS/Android mit nativer Bridge ("zen.tts"); auf Web/Desktop/Linux
//   automatisch im Simulationsmodus (kein Absturz/Build-Blocker).
// • Öffentliche API:
//     - init(), speak(), stop(), pause(), resume()
//     - setLanguage(lang), setRate(rate), setPitch(pitch), setVolume(volume)
//     - speaking (ValueNotifier<bool>), onComplete (Callback)
//     - queue-Flag in speak(), um Aufrufe zu reihen
// • Kompatibilität:
//     - Klasse TsService spiegelt die API (Legacy/Alias).
//
// Native Bridge (später nachrüstbar):
//   - MethodChannel: 'zen.tts'
//   - Methoden: configure, speak, stop, pause, resume,
//               setLanguage, setRate, setPitch, setVolume
//   - Callbacks (optional): onStart, onComplete, onError
//
// Hinweise:
//   - Auf Plattformen ohne Bridge bleibt _ready=false; speak() nutzt Simulation.
//   - Simulation setzt speaking=true und beendet nach einem kurzen Delay.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  static const MethodChannel _channel = MethodChannel('zen.tts');

  /// Wird true, während gesprochen wird (auch in der Simulation).
  final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  /// Optionaler Callback, wenn ein Sprechvorgang natürlich endet.
  VoidCallback? onComplete;

  bool _ready = false;
  bool get isReady => _ready;

  // Default-Parameter / State
  String _lang = 'de-DE';
  double _rate = 0.5;   // 0.0 .. 1.0 (plattformabhängig)
  double _pitch = 1.0;  // 0.5 .. 2.0
  double _volume = 1.0; // 0.0 .. 1.0

  // Einfache Queue-Logik (nur 1 Job aktiv, optionales Enqueue)
  Completer<void>? _activeJob;

  // ---------- Init / Bridge ----------

  Future<bool> init() async {
    if (_ready) return true;

    // Auf Web: kein MethodChannel → Fallback (Simulation)
    if (kIsWeb) {
      _ready = false;
      return false;
    }

    try {
      // Konfiguration ist optional; wenn die native Seite fehlt, fängt speak() das ab.
      await _channel.invokeMethod('configure', <String, dynamic>{
        'lang': _lang,
        'rate': _rate,
        'pitch': _pitch,
        'volume': _volume,
        'version': 'v1',
      }).timeout(const Duration(milliseconds: 600), onTimeout: () => null);

      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onStart':
            speaking.value = true;
            break;
          case 'onComplete':
            speaking.value = false;
            _completeActiveJob();
            onComplete?.call();
            break;
          case 'onError':
            speaking.value = false;
            _completeActiveJob();
            break;
        }
      });

      _ready = true;
      return true;
    } catch (_) {
      _ready = false; // kein Kanal vorhanden → Fallback
      return false;
    }
  }

  // ---------- Speak / Controls ----------

  /// Spricht [text]. Bei [queue]==false wird eine laufende Ausgabe zuerst gestoppt.
  Future<bool> speak(
    String text, {
    String? lang,
    double? rate,
    double? pitch,
    double? volume,
    bool queue = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    // Laufende Ausgabe behandeln
    if (!queue && speaking.value) {
      await stop();
    }

    // Werte für diesen Aufruf
    final args = <String, dynamic>{
      'text': trimmed,
      'lang': (lang ?? _lang),
      'rate': (rate ?? _rate),
      'pitch': (pitch ?? _pitch),
      'volume': (volume ?? _volume),
      'queue': queue,
    };

    // 1) Versuche Native-Bridge
    final ok = await init();
    if (ok) {
      try {
        _startActiveJob();
        speaking.value = true;
        await _channel
            .invokeMethod('speak', args)
            .timeout(const Duration(seconds: 5));
        // Bei nativer Ausgabe wartet der Abschluss auf 'onComplete'.
        return true;
      } on PlatformException {
        // Fallback unten
      } on TimeoutException {
        // Fallback unten
      } catch (_) {
        // Fallback unten
      }
    }

    // 2) Fallback-Simulation (funktioniert überall)
    await _simulateSpeak(trimmed);
    return true;
  }

  Future<void> stop() async {
    // 1) Versuche, nativ zu stoppen
    if (await init()) {
      try {
        await _channel.invokeMethod('stop').timeout(const Duration(seconds: 2));
      } catch (_) {
        // ignorieren, Simulation beendet unten
      }
    }
    // 2) Simulation/Status beenden
    speaking.value = false;
    _completeActiveJob();
  }

  Future<void> pause() async {
    if (await init()) {
      try {
        await _channel.invokeMethod('pause').timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    // Simulation: keine echte Pause (no-op)
  }

  Future<void> resume() async {
    if (await init()) {
      try {
        await _channel
            .invokeMethod('resume')
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    // Simulation: keine echte Resume-Logik (no-op)
  }

  // ---------- Settings ----------

  Future<void> setLanguage(String lang) async {
    _lang = lang;
    if (!await init()) return;
    try {
      await _channel
          .invokeMethod('setLanguage', <String, dynamic>{'lang': lang})
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.0, 1.0).toDouble();
    if (!await init()) return;
    try {
      await _channel
          .invokeMethod('setRate', <String, dynamic>{'rate': _rate})
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0).toDouble();
    if (!await init()) return;
    try {
      await _channel
          .invokeMethod('setPitch', <String, dynamic>{'pitch': _pitch})
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    if (!await init()) return;
    try {
      await _channel
          .invokeMethod('setVolume', <String, dynamic>{'volume': _volume})
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  // ---------- Helpers ----------

  void _startActiveJob() {
    if (_activeJob == null || _activeJob!.isCompleted) {
      _activeJob = Completer<void>();
    }
  }

  void _completeActiveJob() {
    if (_activeJob != null && !_activeJob!.isCompleted) {
      _activeJob!.complete();
    }
    _activeJob = null;
  }

  Future<void> _simulateSpeak(String text) async {
    // Kleiner, gefühlter „Sprech“-Delay (200ms .. 2500ms).
    final int ms = (200 + text.length * 8).clamp(200, 2500);
    _startActiveJob();
    speaking.value = true;
    try {
      await Future.delayed(Duration(milliseconds: ms));
    } finally {
      speaking.value = false;
      _completeActiveJob();
      onComplete?.call();
    }
  }
}

/// ---------------------------------------------------------------------------
///  Kompatibilitäts-Alias: TsService  (delegiert an TtsService)
/// ---------------------------------------------------------------------------
/// Damit alter Code wie `import '.../ts_service.dart' as tts;` und
/// `tts.TsService.instance.speak(...)` weiterhin funktioniert, spiegelt
/// diese Klasse die TtsService-API 1:1.

class TsService {
  TsService._();
  static final TsService instance = TsService._();

  VoidCallback? get onComplete => TtsService.instance.onComplete;
  set onComplete(VoidCallback? cb) => TtsService.instance.onComplete = cb;

  bool get isSpeaking => TtsService.instance.speaking.value;
  ValueListenable<bool> get speaking => TtsService.instance.speaking;

  Future<bool> speak(
    String text, {
    String? locale, // Alias zu lang
    double? rate,
    double? pitch,
    double? volume,
    bool queue = false,
  }) {
    return TtsService.instance.speak(
      text,
      lang: locale,
      rate: rate,
      pitch: pitch,
      volume: volume,
      queue: queue,
    );
    }

  Future<void> stop() => TtsService.instance.stop();
  Future<void> pause() => TtsService.instance.pause();
  Future<void> resume() => TtsService.instance.resume();

  Future<void> setLanguage(String lang) =>
      TtsService.instance.setLanguage(lang);
  Future<void> setRate(double rate) => TtsService.instance.setRate(rate);
  Future<void> setPitch(double pitch) => TtsService.instance.setPitch(pitch);
  Future<void> setVolume(double volume) =>
      TtsService.instance.setVolume(volume);
}
