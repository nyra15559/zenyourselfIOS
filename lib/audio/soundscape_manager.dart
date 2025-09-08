import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// SoundscapeManager
/// -----------------
/// Sanfte, sichere Audiosteuerung für ZenYourself:
/// • Sanfte Fade-In/Fade-Outs (ohne „Audio-Schreckmomente“)
/// • Crossfade beim Wechseln der Landschaft (asset → asset)
/// • Volumen-Clamping & Fehler-Toleranz
/// • Thread-safe Fades mittels „Generation Token“ (unterbrichbar)
/// • Schlanke API: play / stop / toggle / setVolume / playMood
///
/// Hinweis zu Sicherheit & Achtsamkeit:
/// - Startet Sounds grundsätzlich leise und fährt langsam hoch.
/// - Alle Fades sind unterbrechbar, um plötzliche Lautstärkewechsel zu verhindern.
/// - Keine personenbezogenen Daten; nur lokale Assets.
///
/// Abhängigkeiten: just_audio
class SoundscapeManager with ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  // Nutzerpräferenz-Lautstärke (Zielwert). Tatsächliche Player-Volume kann
  // während Fades zwischen 0.0.._volume liegen.
  double _volume = 0.35;
  String? _currentAsset;

  // Interner Fade-/Zustands-Schutz
  bool _busy = false;
  bool _disposed = false;
  int _fadeGen = 0; // erhöht sich bei jedem neuen Fade → bricht alte Fades ab

  double get volume => _volume;
  bool get isPlaying => _player.playing;
  String? get currentAsset => _currentAsset;

  /// Lade & spiele eine Soundscape-Datei aus den Assets.
  /// [fadeIn] in Sekunden (Standard sanft).
  /// [loop] standardmäßig true (Ambience).
  Future<void> play(
    String asset, {
    double? fadeIn,
    bool loop = true,
  }) async {
    if (_disposed) return;

    // Wenn derselbe Track bereits läuft → nichts tun
    if (_currentAsset == asset && _player.playing) return;

    // Crossfade (sanft stoppen, dann starten)
    if (_currentAsset != null && _currentAsset != asset && _player.playing) {
      await stop(fadeOut: 0.9);
      // Mini-Pause, damit Geräte-Audiofokus sauber wechselt
      await Future.delayed(const Duration(milliseconds: 120));
    }

    _busy = true;
    _cancelFades(); // laufende Fades abbrechen
    try {
      // Starte immer leise und fade dann zum Wunsch-Volumen
      await _player.setVolume(0.0);
      await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await _player.setAsset(asset);
      _currentAsset = asset;
      notifyListeners();

      await _player.play();
      await _fadeTo(_volume, durationSec: fadeIn ?? 1.5);
    } catch (e) {
      debugPrint('[Soundscape] play error: $e');
      // Rollback-Zustand
      _currentAsset = null;
      try {
        await _player.stop();
      } catch (_) {}
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  /// Lautstärke (0.0–1.0) mit sanftem Fade setzen.
  Future<void> setVolume(double target, {double duration = 1.0}) async {
    if (_disposed) return;
    // Clamp
    target = target.clamp(0.0, 1.0);
    _volume = target;
    notifyListeners();

    // Wenn gerade kein Audio aktiv ist, nur Ziel „merken“,
    // aber dennoch Player-Volume setzen (für Preview/Sofortfeedback).
    if (!_player.playing) {
      try {
        await _player.setVolume(target);
      } catch (_) {}
      return;
    }

    await _fadeTo(target, durationSec: duration);
  }

  /// Sanftes Stoppen (Fade-Out), setzt aktuellen Track zurück.
  Future<void> stop({double fadeOut = 1.0}) async {
    if (_disposed) return;
    if (!_player.playing && _currentAsset == null) return;

    _busy = true;
    _cancelFades();
    try {
      await _fadeTo(0.0, durationSec: fadeOut);
      await _player.stop();
    } catch (e) {
      debugPrint('[Soundscape] stop error: $e');
    } finally {
      _currentAsset = null;
      _busy = false;
      notifyListeners();
    }
  }

  /// Stimmung → passende Soundscape (Dart-2-kompatibel ohne switch-expression).
  Future<void> playMood(int moodScore) async {
    if (_disposed) return;
    String asset;
    switch (moodScore) {
      case 0:
        asset = 'assets/audio/rain_zen.mp3';
        break;
      case 1:
        asset = 'assets/audio/clouds_ambience.mp3';
        break;
      case 2:
        asset = 'assets/audio/neutral_flow.mp3';
        break;
      case 3:
        asset = 'assets/audio/birds_garden.mp3';
        break;
      case 4:
        asset = 'assets/audio/sunshine_zen.mp3';
        break;
      default:
        asset = 'assets/audio/neutral_flow.mp3';
        break;
    }
    await play(asset, fadeIn: 2.0);
  }

  /// Play/Pause-ähnliches Verhalten:
  /// – Wenn etwas spielt → sanft stoppen
  /// – Wenn pausiert und es gibt einen letzten Track → wieder sanft starten
  Future<void> toggle() async {
    if (_disposed || _busy) return;
    if (isPlaying) {
      await stop();
    } else if (_currentAsset != null) {
      await play(_currentAsset!);
    }
  }

  // =========================
  // Interna: Fade-Engine
  // =========================

  /// Bricht laufende Fades ab, indem die Generation erhöht wird.
  void _cancelFades() {
    _fadeGen++;
  }

  /// Fährt Lautstärke sanft auf [to].
  Future<void> _fadeTo(double to, {required double durationSec}) async {
    // Minimale Dauer & Schritte
    const steps = 20;
    final totalMs = (durationSec * 1000).clamp(60, 6000).toInt();
    final rawStep = (totalMs / steps).floor(); // int
    final stepMs = rawStep < 8 ? 8 : (rawStep > 400 ? 400 : rawStep);

    final gen = ++_fadeGen; // neue Fade-Generation
    double from;
    try {
      from = _player.volume;
    } catch (_) {
      from = 0.0;
    }

    for (int i = 0; i <= steps; i++) {
      if (_disposed || gen != _fadeGen) return; // abgebrochen
      final t = i / steps;
      final v = from + (to - from) * _easeOutCubic(t);
      try {
        await _player.setVolume(v);
      } catch (_) {
        // Ignoriere einzelne Set-Fehler (z. B. wenn Player wechselt)
      }
      if (i < steps) {
        await Future.delayed(Duration(milliseconds: stepMs));
      }
    }

    // Ziel laut & deutlich setzen (Numerik-Drift vermeiden)
    try {
      if (!_disposed) await _player.setVolume(to);
    } catch (_) {}
  }

  double _easeOutCubic(double t) {
    final p = t - 1.0;
    return p * p * p + 1.0;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelFades();
    _player.dispose();
    super.dispose();
  }
}

/// SoundscapeVolumeWidget
/// ----------------------
/// Barrierearmer Lautstärkeregler mit optischem Feedback.
/// – Semantics/Tooltip für Screenreader
/// – Live-Höhenmeter (sanfte Reaktion)
class SoundscapeVolumeWidget extends StatelessWidget {
  final SoundscapeManager manager;

  const SoundscapeVolumeWidget({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFA5CBA1);
    const ink = Color(0xFF365486);

    return Semantics(
      label: 'Lautstärkeregler für Klanglandschaft',
      child: Row(
        children: [
          const Icon(Icons.volume_down, color: ink),
          Expanded(
            child: Slider(
              min: 0,
              max: 1,
              value: manager.volume.clamp(0.0, 1.0), // cast für Analyzer
              onChanged: (v) {
                // bewusst ohne await – UI soll nicht blocken
                manager.setVolume(v, duration: 0.25);
              },
              activeColor: accent,
              inactiveColor: Colors.black12,
              semanticFormatterCallback: (v) {
                final p = ((v.clamp(0.0, 1.0)) * 100).round();
                return 'Lautstärke $p Prozent';
              },
            ),
          ),
          const Icon(Icons.volume_up, color: ink),
          // Visuelles Pegel-Feedback (ohne Text, rein dekorativ)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 24,
            height: 10 + (manager.volume.clamp(0.0, 1.0)) * 18,
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                if (manager.volume > 0.01)
                  BoxShadow(
                    color: ink.withValues(alpha: 0.17 + manager.volume * 0.2),
                    blurRadius: 4 + manager.volume * 8,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
