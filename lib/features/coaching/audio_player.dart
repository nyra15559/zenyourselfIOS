// lib/features/coaching/audio_player.dart
//
// CoachingAudioPlayer — Oxford Zen Edition
// ---------------------------------------
// • Schlanker, barrierearmer Audio-Player für Mini-Coach-Impulse
// • Saubere just_audio-Integration mit defensiven Defaults
// • Glasige ZenCard, konsistente Farben/Typografie, Lottie optional
// • Robust gegen Edge-Cases (0-Länge, Fehler, Replay am Ende)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lottie/lottie.dart';

import '../../shared/zen_style.dart';
import '../../shared/ui/zen_widgets.dart';

class CoachingAudioPlayer extends StatefulWidget {
  /// Asset-Pfad, z. B. "assets/audio/breathe.mp3"
  final String asset;

  /// Optionaler Titel (Fallback: Dateiname)
  final String? title;

  /// Optional: kurze Beschreibung unterhalb des Titels
  final String? description;

  /// Optional: Lottie-Animation (z. B. "assets/lottie/breath.json")
  final String? lottieAnim;

  /// Autoplay beim Laden?
  final bool autoplay;

  /// In Schleife abspielen?
  final bool loop;

  const CoachingAudioPlayer({
    super.key,
    required this.asset,
    this.title,
    this.description,
    this.lottieAnim,
    this.autoplay = false,
    this.loop = false,
  });

  @override
  State<CoachingAudioPlayer> createState() => _CoachingAudioPlayerState();
}

class _CoachingAudioPlayerState extends State<CoachingAudioPlayer> {
  late final AudioPlayer _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durSub;

  Duration? _duration;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isReady = false;
  String? _error;

  Color get _accent => ZenColors.jade; // Design-DNA

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setAsset(widget.asset);
      if (widget.loop) {
        await _player.setLoopMode(LoopMode.one);
      }
      _duration = _player.duration;
      _isReady = true;
      _subscribe();
      if (widget.autoplay) _player.play();
      if (mounted) setState(() {});
    } catch (_) {
      _error = "Audio konnte nicht geladen werden.";
      if (mounted) setState(() {});
    }
  }

  void _subscribe() {
    _posSub = _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _stateSub = _player.playerStateStream.listen((st) {
      if (!mounted) return;
      setState(() => _isPlaying = st.playing);
    });
    _durSub = _player.durationStream.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (!_isReady) return;
    final dur = _duration ?? Duration.zero;
    // Wenn am Ende, zurückspulen
    if (_position >= dur && dur > Duration.zero) {
      await _player.seek(Duration.zero);
    }
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekRelative(Duration delta) async {
    if (!_isReady) return;
    final dur = _duration ?? Duration.zero;
    final next = (_position + delta);
    final clamped = next < Duration.zero
        ? Duration.zero
        : (dur == Duration.zero ? Duration.zero : next > dur ? dur : next);
    await _player.seek(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? _fallbackTitle(widget.asset);
    final desc = widget.description ?? '';

    return Semantics(
      container: true,
      label: 'Audio-Player: $title',
      child: ZenCard(
        elevation: 7,
        borderRadius: ZenRadii.l,
        color: ZenColors.white.withOpacity(0.96),
        padding: const EdgeInsets.symmetric(
          vertical: ZenSpacing.m,
          horizontal: ZenSpacing.m,
        ),
        showWatermark: false,
        child: _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 15.5),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.lottieAnim != null && widget.lottieAnim!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        height: 98,
                        child: Lottie.asset(
                          widget.lottieAnim!,
                          repeat: true,
                          animate: _isPlaying,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  // Titel
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: ZenTextStyles.h3.copyWith(
                      color: ZenColors.jade,
                      fontSize: 20.5,
                      letterSpacing: 0.2,
                      shadows: [
                        Shadow(
                          blurRadius: 8,
                          color: ZenColors.jade.withOpacity(0.12),
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  // Beschreibung (optional)
                  if (desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 12),
                      child: Text(
                        desc,
                        textAlign: TextAlign.center,
                        style: ZenTextStyles.body.copyWith(
                          fontSize: 15,
                          color: ZenColors.inkSubtle,
                          height: 1.35,
                        ),
                      ),
                    ),

                  // Loader oder Player-Bar
                  if (!_isReady)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14.0),
                      child: SizedBox(
                        height: 26,
                        width: 26,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    _playerBar(),
                ],
              ),
      ),
    );
  }

  Widget _playerBar() {
    final duration = _duration ?? Duration.zero;
    final position = _position.clamp(Duration.zero, duration);

    // Schutz vor NaN/INF bei sehr kurzen Assets
    final maxMs = duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();

    return Column(
      children: [
        // Steuerleiste
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // -15s
            IconButton(
              tooltip: "15 Sekunden zurück",
              onPressed: () => _seekRelative(const Duration(seconds: -15)),
              icon: Icon(Icons.replay_10_rounded, color: _accent.withOpacity(0.9)),
            ),
            // Play/Pause
            Semantics(
              button: true,
              label: _isPlaying ? 'Pause' : 'Abspielen',
              child: IconButton(
                iconSize: 44,
                onPressed: _togglePlay,
                icon: Icon(
                  _isPlaying ? Icons.pause_circle : Icons.play_circle,
                  color: _accent,
                ),
              ),
            ),
            // +15s
            IconButton(
              tooltip: "15 Sekunden vor",
              onPressed: () => _seekRelative(const Duration(seconds: 15)),
              icon: Icon(Icons.forward_10_rounded, color: _accent.withOpacity(0.9)),
            ),
          ],
        ),

        // Slider + Zeiten
        Row(
          children: [
            Text(
              _fmt(position),
              style: TextStyle(fontSize: 12.5, color: ZenColors.inkSubtle.withOpacity(0.9)),
            ),
            Expanded(
              child: Slider(
                value: position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
                min: 0,
                max: maxMs,
                onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                activeColor: _accent,
                inactiveColor: _accent.withOpacity(0.18),
              ),
            ),
            Text(
              _fmt(duration),
              style: TextStyle(fontSize: 12.5, color: ZenColors.inkSubtle.withOpacity(0.9)),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    if (d.inMilliseconds.isNegative) return '00:00';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
    }

  String _fallbackTitle(String assetPath) {
    final name = assetPath.split('/').last;
    final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    return base.replaceAll('_', ' ');
  }
}
