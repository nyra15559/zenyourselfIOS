// lib/services/tts_service.dart
//
// TtsService — Oxford Zen (robust, ohne zusätzliche Pakete)
// ---------------------------------------------------------
// • MethodChannel-basierter TTS-Wrapper mit sauberem Fallback:
//     - Wenn kein nativer Kanal vorhanden / Fehler → SIMULATION (Timer)
//     - So baut & läuft die App auf Linux/Web/Desktop ohne Native-Code.
// • API (kompakt):
//     - init(), speak(), stop(), pause(), resume()
//     - setLanguage(rate/pitch/volume), speaking (ValueNotifier<bool>)
//     - onComplete (VoidCallback?)
// • Kompatibilität:
//     - Zusätzlich wird eine Alias-Klasse TsService bereitgestellt,
//       damit bestehende Imports tts.TsService weiterhin funktionieren.
//
// Hinweis: Später kann man für iOS/Android eine echte Bridge auf "zen.tts"
// nachrüsten (onStart/onComplete/onError Events). Bis dahin simulieren wir.

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
  /// (In der Simulation nach Delay; mit Native-Bridge bei onComplete.)
  VoidCallback? onComplete;

  bool _ready = false;
  bool get isReady => _ready;

  // Default-Parameter
  String _lang = 'de-DE';
  double _rate = 0.5;   // 0.0..1.0 (plattformabhängig)
  double _pitch = 1.0;  // 0.5..2.0
  double _volume = 1.0; // 0.0..1.0

  // ---------- Init / Bridge ----------

  Future<bool> init() async {
    if (_ready) return true;

    // Auf Web: MethodChannel unbrauchbar → wir bleiben im Fallback-Modus
    if (kIsWeb) {
      _ready = false;
      return false;
    }

    try {
      // Configure ist optional — wenn die native Seite fehlt, fängt speak() das ab.
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
            onComplete?.call();
            break;
          case 'onError':
            speaking.value = false;
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
        speaking.value = true;
        await _channel.invokeMethod('speak', args).timeout(const Duration(seconds: 5));
        return true;
      } on PlatformException {
        // weiter unten: Simulation
      } on TimeoutException {
        // weiter unten: Simulation
      } catch (_) {
        // weiter unten: Simulation
      } finally {
        // Falls die native Seite sofort fehlschlägt, übernehmen wir Simulation
      }
    }

    // 2) Fallback-Simulation (funktioniert überall)
    await _simulateSpeak(trimmed);
    return true;
  }

  Future<void> stop() async {
    // Versuch: native stoppen
    if (await init()) {
      try {
        await _channel.invokeMethod('stop').timeout(const Duration(seconds: 2));
      } catch (_) {
        // ignorieren, Simulation macht unten weiter
      }
    }
    // Simulation/Status beenden
    speaking.value = false;
  }

  Future<void> pause() async {
    if (await init()) {
      try {
        await _channel.invokeMethod('pause').timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  Future<void> resume() async {
    if (await init()) {
      try {
        await _channel.invokeMethod('resume').timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
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
    _rate = rate.clamp(0.0, 1.0);
    if (!await init()) return;
    try {
      await _channel
          .invokeMethod('setRate', <String, dynamic>{'rate': _rate})
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    if (!await init()) return;
    try {
      await _channel
          .invokeMethod('setPitch', <String, dynamic>{'pitch': _pitch})
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (!await init()) return;
    try {
      await _channel
          .invokeMethod('setVolume', <String, dynamic>{'volume': _volume})
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  // ---------- Helpers ----------

  Future<void> _simulateSpeak(String text) async {
    // Kleiner, gefühlter „Sprech“-Delay (200ms .. 2500ms).
    final ms = (200 + text.length * 8).clamp(200, 2500);
    speaking.value = true;
    try {
      await Future.delayed(Duration(milliseconds: ms));
    } finally {
      speaking.value = false;
      onComplete?.call();
    }
  }
}

/// ---------------------------------------------------------------------------
///  Kompatibilitäts-Alias: TsService  (delegiert an TtsService)
/// ---------------------------------------------------------------------------
/// Damit alter Code wie `import '.../ts_service.dart' as tts;` und
/// `tts.TsService.instance.speak(...)` keinen Compile-Fehler wirft,
/// spiegeln wir die API hier auf TtsService.
/// (Wenn du willst, kannst du zusätzlich eine Datei ts_service.dart anlegen,
/// die einfach `export 'tts_service.dart';` enthält.)

class TsService {
  TsService._();
  static final TsService instance = TsService._();

  VoidCallback? get onComplete => TtsService.instance.onComplete;
  set onComplete(VoidCallback? cb) => TtsService.instance.onComplete = cb;

  bool get isSpeaking => TtsService.instance.speaking.value;

  ValueListenable<bool> get speaking => TtsService.instance.speaking;

  Future<bool> speak(
    String text, {
    String? locale, // alias zu lang
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

  Future<void> setLanguage(String lang) => TtsService.instance.setLanguage(lang);
  Future<void> setRate(double rate) => TtsService.instance.setRate(rate);
  Future<void> setPitch(double pitch) => TtsService.instance.setPitch(pitch);
  Future<void> setVolume(double volume) => TtsService.instance.setVolume(volume);
}
