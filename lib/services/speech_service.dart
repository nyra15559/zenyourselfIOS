// lib/services/speech_service.dart
//
// SpeechService — Oxford Safety Edition v2.2 (prod-safe, reentrancy-proof)
// -----------------------------------------------------------------------
// Drop-in-Kompatibilität zu bestehendem Code:
//   - Klasse: SpeechService (ChangeNotifier)
//   - Properties: isRecording, isPaused, isActive, transcript$, partial$,
//                 level$, elapsed$, elapsedSeconds$, totalSeconds
//   - Methoden: start/stop/pause/resume/toggle/reset/dispose
//   - Debug-Simulation optional (kDebugMode)
//   - attachTranscriber(...) & attachWhisper(...)
//
// Hinweis ggü. v2.1: Die Transcriber-Schnittstelle liegt in whisper_service.dart
// (SpeechTranscriber). Wir importieren sie als `stt` und re-exportieren die Typen.
//

import 'dart:async';
import 'package:flutter/foundation.dart';

// Transcriber-Typen aus whisper_service.dart
import './whisper_service.dart' as stt;

// Re-Export, damit Konsumenten nur diese Datei importieren müssen.
export './whisper_service.dart' show SpeechTranscriber, WhisperService;

/// Aufnahmezustand.
enum SpeechState { idle, recording, paused, stopping, error }

/// Produktiv-sichere Hülle um die Engine – UI konsumiert NUR SpeechService.
class SpeechService with ChangeNotifier {
  // ---------------- Konfiguration ----------------
  static const Duration _kDefaultMaxDuration = Duration(minutes: 2);
  static const Duration _kTick = Duration(milliseconds: 200);
  static const Duration _kFinalDedupWindow = Duration(milliseconds: 350);

  // ---------------- State ----------------
  SpeechState _state = SpeechState.idle;
  SpeechState get state => _state;

  bool get isRecording => _state == SpeechState.recording;
  bool get isPaused => _state == SpeechState.paused;
  bool get isActive => _state == SpeechState.recording || _state == SpeechState.paused;

  DateTime? _recordingSince;
  DateTime? get recordingSince => _recordingSince;

  Duration get elapsed => _sw.elapsed;
  int get totalSeconds => _sw.elapsed.inSeconds; // v5-Compat

  String? _lastError;
  String? get lastError => _lastError;

  bool _disposed = false;

  // ---------------- Streams (UI-API) ----------------
  final _transcriptCtrl = StreamController<String>.broadcast(); // finale Segmente
  Stream<String> get transcript$ => _transcriptCtrl.stream;

  final _partialCtrl = StreamController<String>.broadcast(); // partielle Hypothesen
  Stream<String> get partial$ => _partialCtrl.stream;

  final _levelCtrl = StreamController<double>.broadcast(); // 0.0..1.0
  Stream<double> get level$ => _levelCtrl.stream;

  final _elapsedCtrl = StreamController<Duration>.broadcast();
  Stream<Duration> get elapsed$ => _elapsedCtrl.stream;

  /// Praktisch für Timings im UI (distinct).
  Stream<int> get elapsedSeconds$ => _elapsedCtrl.stream.map((d) => d.inSeconds).distinct();

  final _errorCtrl = StreamController<String>.broadcast();
  Stream<String> get error$ => _errorCtrl.stream;

  // ---------------- Zeitgeber ----------------
  final Stopwatch _sw = Stopwatch();
  Timer? _tick;
  Timer? _limitTimer;

  // Final-Dedup
  String? _lastFinalText;
  DateTime? _lastFinalAt;

  // Debug-Simulation
  bool _simulate = false;
  Timer? _simuTimer;

  // ---------------- Transcriber-Engine (Whisper etc.) ----------------
  stt.SpeechTranscriber? _engine; // optional – bei Nichtsetzung nur Simulation
  StreamSubscription<String>? _engPartialSub;
  StreamSubscription<String>? _engFinalSub;
  StreamSubscription<double>? _engLevelSub;

  /// Engine andocken (z. B. deine Whisper-Klasse).
  void attachTranscriber(stt.SpeechTranscriber engine) {
    _engine = engine;
  }

  /// Bequemer Alias für Whisper:
  void attachWhisper(stt.WhisperService service) {
    attachTranscriber(service);
  }

  /// Engine lösen (z. B. bei Hot-Swap oder Fehler).
  Future<void> detachTranscriber() async {
    await _cancelEngineSubs();
    _engine = null;
  }

  // ---------------- Public Helpers ----------------

  /// Idempotenter Toggle: Startet (falls idle) oder stoppt (falls aktiv).
  Future<void> toggle({bool? simulate, Duration? maxDuration, String? locale}) async {
    if (isRecording || isPaused) {
      await stop();
    } else {
      await start(simulate: simulate, maxDuration: maxDuration, locale: locale);
    }
  }

  // ---------------- API: Start / Stop / Pause / Resume ----------------

  /// Startet Aufnahme & (falls Engine vorhanden) die Transkription.
  /// simulate: null → im Debug-Build true, sonst false.
  Future<void> start({bool? simulate, Duration? maxDuration, String? locale}) async {
    if (_disposed) return;
    if (_state == SpeechState.stopping) return; // mitten im Stop → ignoriere
    if (isRecording || isPaused) return; // idempotent

    // Mic-Permission (später mit permission_handler ersetzen)
    final hasMic = await _checkMicrophonePermission();
    if (!hasMic) {
      _fail('Mikrofonberechtigung verweigert');
      return;
    }

    _simulate = simulate ?? kDebugMode; // Prod-Default: false
    _setState(SpeechState.recording);
    _recordingSince = DateTime.now();

    // Elapsed-Ticker
    _startElapsedTicker(reset: true);

    // Max-Dauer
    final limit = (maxDuration == null || maxDuration <= Duration.zero)
        ? _kDefaultMaxDuration
        : maxDuration;
    _limitTimer?.cancel();
    _limitTimer = Timer(limit, () async {
      await stop(); // Auto-Stop
    });

    // Reset Dedup
    _lastFinalText = null;
    _lastFinalAt = null;

    // Engine konfigurieren
    if (_engine != null) {
      await _cancelEngineSubs();
      _engPartialSub = _engine!.partial$.listen(
        pushPartial,
        onError: (e, s) => _fail('$e'),
      );
      _engFinalSub = _engine!.final$.listen(
        pushFinal,
        onError: (e, s) => _fail('$e'),
      );
      _engLevelSub = _engine!.level$.listen(
        setLevel,
        onError: (e, s) {},
      );
      try {
        await _engine!.start(locale: locale);
      } catch (e) {
        _fail('Transcriber-Start fehlgeschlagen', error: e);
        if (_simulate) {
          _startSimulation();
        }
      }
    } else if (_simulate) {
      _startSimulation();
    }
  }

  /// Stoppt Aufnahme & Transkription. Gibt evtl. Audio-Pfad zurück.
  Future<String?> stop() async {
    if (_disposed) return null;
    if (_state == SpeechState.idle) return null;
    if (_state == SpeechState.stopping) return null;

    _setState(SpeechState.stopping);
    _stopElapsedTicker();
    _stopSimulation();
    _limitTimer?.cancel();
    _limitTimer = null;

    String? path;
    if (_engine != null) {
      try {
        path = await _engine!.stop();
      } catch (e) {
        _fail('Transcriber-Stop fehlgeschlagen', error: e);
      }
    }
    await _cancelEngineSubs();

    _recordingSince = null;
    _setState(SpeechState.idle);
    return path;
  }

  /// Pausiert (falls Engine das kann).
  Future<void> pause() async {
    if (_disposed) return;
    if (!isRecording) return;
    _setState(SpeechState.paused);
    _sw.stop();
    _cancelTickerOnly();
    if (_engine != null) {
      try {
        await _engine!.pause();
      } catch (e) {
        _fail('Pause fehlgeschlagen', error: e);
      }
    }
  }

  /// Setzt fort (falls Engine das kann).
  Future<void> resume() async {
    if (_disposed) return;
    if (!isPaused) return;
    _setState(SpeechState.recording);
    _startElapsedTicker(reset: false);
    if (_engine != null) {
      try {
        await _engine!.resume();
      } catch (e) {
        _fail('Resume fehlgeschlagen', error: e);
      }
    }
  }

  /// Setzt den Service in Grundzustand (ohne Streams zu schließen).
  void reset() {
    if (_disposed) return;
    _stopElapsedTicker();
    _stopSimulation();
    _limitTimer?.cancel();
    _limitTimer = null;
    _sw.reset();
    _lastError = null;
    _recordingSince = null;
    _lastFinalText = null;
    _lastFinalAt = null;
    _setState(SpeechState.idle);
  }

  // ---------------- Bridge-Methoden (Engine → UI) ----------------

  /// Partielle Hypothese weiterreichen (Engine ruft das indirekt via Stream).
  void pushPartial(String text) {
    if (_disposed) return;
    if (_partialCtrl.isClosed) return;
    if (!isActive) return;
    final t = text.trim();
    if (t.isEmpty) return;
    _partialCtrl.add(t);
  }

  /// Finale Zeile weiterreichen – mit Anti-Deduplikation (350ms).
  void pushFinal(String text) {
    if (_disposed) return;
    if (_transcriptCtrl.isClosed) return;
    final t = text.trim();
    if (t.isEmpty) return;

    final now = DateTime.now();
    if (_lastFinalText == t &&
        _lastFinalAt != null &&
        now.difference(_lastFinalAt!).abs() <= _kFinalDedupWindow) {
      return; // Duplikat unterdrücken
    }
    _lastFinalText = t;
    _lastFinalAt = now;

    _transcriptCtrl.add(t);
  }

  /// Pegel 0.0..1.0.
  void setLevel(double level) {
    if (_disposed) return;
    if (_levelCtrl.isClosed) return;
    final clamped = level.clamp(0.0, 1.0);
    _levelCtrl.add(clamped);
  }

  /// Fehler von der Engine durchreichen.
  void pushError(String message) => _fail(message);

  // ---------------- Fehlerbehandlung ----------------

  void _fail(String message, {Object? error}) {
    if (_disposed) return;
    _lastError = message;
    if (!_errorCtrl.isClosed) _errorCtrl.add(message);

    // Aufnahme stoppen (sanft), aber Service intakt lassen.
    _stopElapsedTicker();
    _stopSimulation();
    _limitTimer?.cancel();
    _limitTimer = null;
    _setState(SpeechState.error);

    if (kDebugMode) {
      // ignore: avoid_print
      print('[SpeechService] $message ${error != null ? '($error)' : ''}');
    }
  }

  // ---------------- Ticker / Elapsed ----------------

  void _startElapsedTicker({required bool reset}) {
    _tick?.cancel();
    if (reset) {
      _sw
        ..reset()
        ..start();
    } else {
      if (!_sw.isRunning) _sw.start();
    }
    _tick = Timer.periodic(_kTick, (_) {
      if (_elapsedCtrl.isClosed) return;
      _elapsedCtrl.add(_sw.elapsed);
      if (_simulate) {
        // kleiner Pegel-Jitter für UI-Feedback
        final ms = _sw.elapsedMilliseconds % 2000;
        final amp = (ms < 1000 ? ms / 1000 : (2000 - ms) / 1000).clamp(0.05, 0.9);
        setLevel(amp);
      }
    });
  }

  void _stopElapsedTicker() {
    _sw.stop();
    _tick?.cancel();
    _tick = null;
  }

  void _cancelTickerOnly() {
    _tick?.cancel();
    _tick = null;
  }

  // ---------------- Simulation (nur Dev) ----------------

  void _startSimulation() {
    _simuTimer?.cancel();

    final lines = <String>[
      '… ich fühle mich heute',
      '… ich fühle mich heute etwas müde',
      '… ich fühle mich heute etwas müde, aber',
      '… ich fühle mich heute etwas müde, aber hoffnungsvoll',
    ];
    int i = 0;

    _simuTimer = Timer.periodic(const Duration(milliseconds: 550), (t) {
      if (_state != SpeechState.recording) return;
      if (i < lines.length - 1) {
        pushPartial(lines[i]);
        i++;
      } else {
        pushFinal(lines.last);
        t.cancel();
      }
    });
  }

  void _stopSimulation() {
    _simuTimer?.cancel();
    _simuTimer = null;
  }

  // ---------------- Permissions (Stub) ----------------

  Future<bool> _checkMicrophonePermission() async {
    // TODO: mit permission_handler/Platform-APIs ersetzen.
    return true;
  }

  // ---------------- Engine-Subs Cleanup ----------------

  Future<void> _cancelEngineSubs() async {
    try { await _engPartialSub?.cancel(); } catch (_) {}
    try { await _engFinalSub?.cancel(); } catch (_) {}
    try { await _engLevelSub?.cancel(); } catch (_) {}
    _engPartialSub = null;
    _engFinalSub = null;
    _engLevelSub = null;
  }

  // ---------------- State-Notify ----------------

  void _setState(SpeechState s) {
    if (_disposed) return;
    _state = s;
    try {
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Listener evtl. schon entkoppelt – kein Hard-Fail.
    }
  }

  // ---------------- Lifecycle ----------------

  /// Asynchrones, sicheres Schließen (z. B. in einem Service-Locator).
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;

    _stopElapsedTicker();
    _stopSimulation();
    _limitTimer?.cancel();
    _limitTimer = null;

    await _cancelEngineSubs();

    await _closeSafely(_transcriptCtrl);
    await _closeSafely(_partialCtrl);
    await _closeSafely(_levelCtrl);
    await _closeSafely(_elapsedCtrl);
    await _closeSafely(_errorCtrl);
  }

  Future<void> _closeSafely(StreamController c) async {
    try { await c.close(); } catch (_) {}
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _stopElapsedTicker();
    _stopSimulation();
    _limitTimer?.cancel();
    _limitTimer = null;

    // Engine-Subs lösen
    _engPartialSub?.cancel(); _engPartialSub = null;
    _engFinalSub?.cancel();   _engFinalSub = null;
    _engLevelSub?.cancel();   _engLevelSub = null;

    // Controller schließen (sync, defensive)
    try { _transcriptCtrl.close(); } catch (_) {}
    try { _partialCtrl.close(); } catch (_) {}
    try { _levelCtrl.close(); } catch (_) {}
    try { _elapsedCtrl.close(); } catch (_) {}
    try { _errorCtrl.close(); } catch (_) {}

    super.dispose();
  }
}
