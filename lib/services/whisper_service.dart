// lib/services/whisper_service.dart
//
// WhisperService — Streaming STT Bridge v1.2 (prod-safe, reentrancy-proof)
// -----------------------------------------------------------------------------
// Zweck
// • Einheitliche Streaming-Schnittstelle für Live-Spracherkennung (STT).
// • Drop-in für SpeechService.attachWhisper(this) oder separat nutzbar.
// • Streams: partial$ (laufende Hypothesen), final$ (finale Segmente),
//            level$ (0.0..1.0 VU-Meter).
//
// Eigenschaften
// • Idempotentes start/stop/pause/resume; Schutz gegen Reentrancy.
// • Simulationsmodus via Konstruktor-Flag (simulate: true).
// • Optionale Native-Bridge via MethodChannel (default: 'zen.whisper')
//   + EventChannel (default: 'zen.whisper/events') mit Events:
//     - {type:'partial', value:'...'}
//     - {type:'final',   value:'...'}
//     - {type:'level',   value:0.0..1.0}
//
// Hinweise
// • Auf Web & Plattformen ohne Channels wird automatisch in einen
//   no-crash Modus gewechselt (Simulation falls aktiviert, sonst still).
// • level$ ist 0.0..1.0 normalisiert.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Standardisierte Schnittstelle für beliebige STT-Engines.
/// Wird von `WhisperService` implementiert und vom `SpeechService` konsumiert.
abstract class SpeechTranscriber {
  Future<void> start({String? locale});
  Future<String?> stop();
  Future<void> pause();
  Future<void> resume();

  Stream<String> get partial$;
  Stream<String> get final$;
  Stream<double> get level$;
}

class WhisperService implements SpeechTranscriber {
  WhisperService({
    bool simulate = false,
    String methodChannelName = 'zen.whisper',
    String eventChannelName = 'zen.whisper/events',
  })  : _simulate = simulate,
        _methodChannel = MethodChannel(methodChannelName),
        _eventChannel = EventChannel(eventChannelName);

  // ---------------- Public Streams ----------------
  final _partialCtrl = StreamController<String>.broadcast();
  final _finalCtrl = StreamController<String>.broadcast();
  final _levelCtrl = StreamController<double>.broadcast();

  @override
  Stream<String> get partial$ => _partialCtrl.stream;
  @override
  Stream<String> get final$ => _finalCtrl.stream;
  @override
  Stream<double> get level$ => _levelCtrl.stream;

  // ---------------- Internal State ----------------
  final bool _simulate;
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  bool _active = false;
  bool _paused = false;
  bool get isActive => _active;
  bool get isPaused => _paused;

  StreamSubscription? _nativeSub;
  Timer? _levelTick;
  Timer? _simuTimer;

  // Anti-Dedupe für sehr schnelle doppelte Finals aus dem Native-Layer
  String? _lastFinal;
  DateTime? _lastFinalAt;
  static const _kDedupWindow = Duration(milliseconds: 300);

  // ---------------- Lifecycle ----------------

  /// Startet Aufnahme & Transkription (idempotent).
  @override
  Future<void> start({String? locale}) async {
    if (_active) return;
    _active = true;
    _paused = false;

    _startLevelTicker();

    if (_simulate || kIsWeb) {
      // Web: Channels sind oft nicht vorhanden → Simulation nur wenn explizit gewünscht.
      if (_simulate) _startSimulation();
      _debug('[WhisperService] start (simulate:$_simulate web:$kIsWeb)');
      return;
    }

    try {
      // Native Events (falls implementiert)
      _nativeSub = _eventChannel.receiveBroadcastStream().listen(
        (evt) {
          try {
            if (evt is Map) {
              final t = (evt['type'] ?? '').toString();
              switch (t) {
                case 'partial':
                  _pushPartial(evt['value']?.toString() ?? '');
                  break;
                case 'final':
                  _pushFinal(evt['value']?.toString() ?? '');
                  break;
                case 'level':
                  final double lv = _asDouble(evt['value']);
                  _pushLevel(lv);
                  break;
              }
            } else if (evt is String) {
              // Fallback: reine String-Events als final
              _pushFinal(evt);
            }
          } catch (e) {
            _debug('[WhisperService] event error: $e');
          }
        },
        onError: (e) {
          _debug('[WhisperService] stream error: $e');
        },
        cancelOnError: false,
      );

      await _methodChannel.invokeMethod<void>('start', <String, dynamic>{
        if (locale != null) 'locale': locale,
      });
    } catch (e) {
      _debug('[WhisperService] start failed → ${e.runtimeType}: $e');
      // Kein harter Fail – Service bleibt aktiv (Level-Ticker läuft), UI kann weiterleben.
      // Simulation bewusst NICHT automatisch aktivieren (Prod-Transparenz).
    }
  }

  /// Stoppt Aufnahme & Transkription (liefert optionalen Audio-Pfad).
  @override
  Future<String?> stop() async {
    if (!_active) return null;
    _active = false;
    _paused = false;

    _stopLevelTicker();
    _stopSimulation();
    await _nativeSub?.cancel();
    _nativeSub = null;

    if (_simulate || kIsWeb) {
      _lastFinal = null;
      _lastFinalAt = null;
      return null;
    }

    try {
      final res = await _methodChannel.invokeMethod<String?>('stop');
      _lastFinal = null;
      _lastFinalAt = null;
      return res;
    } catch (e) {
      _debug('[WhisperService] stop failed: $e');
      _lastFinal = null;
      _lastFinalAt = null;
      return null;
    }
  }

  /// Pausiert (falls Engine/Native das kann). Idempotent.
  @override
  Future<void> pause() async {
    if (!_active || _paused) return;
    _paused = true;

    if (_simulate || kIsWeb) {
      // Simulation: nichts weiter tun (Level-Ticker läuft weiter, aber wir deckeln Level)
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('pause');
    } catch (e) {
      _debug('[WhisperService] pause failed: $e');
    }
  }

  /// Setzt fort (falls Engine/Native das kann). Idempotent.
  @override
  Future<void> resume() async {
    if (!_active || !_paused) return;
    _paused = false;

    if (_simulate || kIsWeb) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('resume');
    } catch (e) {
      _debug('[WhisperService] resume failed: $e');
    }
  }

  /// Sorgt für sauberes Schließen (Streams/Ticker).
  Future<void> dispose() async {
    await stop();
    await _closeSafely(_partialCtrl);
    await _closeSafely(_finalCtrl);
    await _closeSafely(_levelCtrl);
  }

  // ---------------- Helpers (Streams) ----------------

  void _pushPartial(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    if (!_partialCtrl.isClosed) _partialCtrl.add(t);
  }

  void _pushFinal(String text) {
    final t = text.trim();
    if (t.isEmpty) return;

    // leichte Dedupe-Schranke gegen doppelte Finals vom Native-Layer
    final now = DateTime.now();
    if (_lastFinal == t &&
        _lastFinalAt != null &&
        now.difference(_lastFinalAt!).abs() <= _kDedupWindow) {
      return;
    }
    _lastFinal = t;
    _lastFinalAt = now;

    if (!_finalCtrl.isClosed) _finalCtrl.add(t);
  }

  void _pushLevel(double v) {
    // Bei Pause den Level herunterfahren, aber nicht komplett 0 (ruhige UI).
    final target = _paused ? 0.04 : v;
    final clamped = target.clamp(0.0, 1.0);
    if (!_levelCtrl.isClosed) _levelCtrl.add(clamped);
  }

  // ---------------- Level Jitter ----------------

  void _startLevelTicker() {
    _stopLevelTicker();
    final rnd = Random();
    _levelTick = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!_active) return;

      if (_paused) {
        _pushLevel(0.04);
        return;
      }

      // Dreiecks-Welle + leichtes Rauschen (ruhige Bewegung für UI)
      final ms = DateTime.now().millisecondsSinceEpoch;
      final phase = (ms % 1600) / 1600.0; // 0..1
      final tri = phase < 0.5 ? (phase * 2) : (2 - phase * 2);
      final noise = (rnd.nextDouble() * 0.08) - 0.04; // ±0.04
      final lvl = (0.08 + tri * 0.75 + noise).clamp(0.05, 0.95);
      _pushLevel(lvl);
    });
  }

  void _stopLevelTicker() {
    _levelTick?.cancel();
    _levelTick = null;
  }

  // ---------------- Simulation (Debug/Dev) ----------------

  void _startSimulation() {
    _stopSimulation();
    if (!_active) return;

    final lines = <String>[
      '… ich denke gerade über',
      '… ich denke gerade über einen Wechsel nach',
      '… ich denke gerade über einen Wechsel nach, weil',
      '… ich denke gerade über einen Wechsel nach, weil mir Stabilität wichtig ist',
    ];
    int i = 0;

    _simuTimer = Timer.periodic(const Duration(milliseconds: 520), (t) {
      if (!_active) {
        t.cancel();
        return;
      }
      if (_paused) return;

      if (i < lines.length - 1) {
        _pushPartial(lines[i]);
        i++;
      } else {
        _pushFinal(lines.last);
        t.cancel();
      }
    });
  }

  void _stopSimulation() {
    _simuTimer?.cancel();
    _simuTimer = null;
  }

  // ---------------- Utils ----------------

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) {
      final p = double.tryParse(v);
      if (p != null) return p;
    }
    return 0.0;
  }

  Future<void> _closeSafely(StreamController c) async {
    try { await c.close(); } catch (_) {}
  }

  void _debug(Object msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(msg);
    }
  }
}
