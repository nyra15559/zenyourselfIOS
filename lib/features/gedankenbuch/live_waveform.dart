// lib/features/_legacy_gedankenbuch/live_waveform.dart
//
// LiveWaveform — Oxford Zen Edition
// ---------------------------------
// • Sanfte, performante Echtzeit-Wellenform für Mic/Voice-UI
// • Design-DNA: Glas, Soft-Glow, runde Caps, Zen-Farben
// • A11y-Semantics, Amplituden-Clamp, FPS-freundlich
// • Konfigurierbar: Frequenz, Speed, Thickness, Glow, Blur

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../shared/zen_style.dart';

class LiveWaveform extends StatefulWidget {
  /// Aktiviert/pausiert die Animation (Mic an/aus).
  final bool isActive;

  /// 0.0–1.0 — relative Ausschlagstärke der Welle.
  final double amplitude;

  /// Primärfarbe der Welle; Default: Zen Jade Mid.
  final Color? color;

  /// Zeichenfläche (px).
  final double width;
  final double height;

  /// Cycles über die Breite (1.0 = eine volle Sinuswelle).
  final double frequency;

  /// Wie schnell die Phase pro Tick voranschreitet (Rad).
  final double speed;

  /// Strichstärke der Hauptwelle.
  final double thickness;

  /// Hintergrund-Blur (nur wenn aktiv oder amplitude > 0.05).
  final double backgroundBlurSigma;

  /// Leichter Glow/Highlight-Punkt am rechten Rand.
  final bool showGlow;

  /// Abgerundete Ecken der Zeichenfläche.
  final double cornerRadius;

  /// Optionales Semantik-Label (Screenreader).
  final String? semanticsLabel;

  const LiveWaveform({
    super.key,
    required this.isActive,
    required this.amplitude,
    this.color,
    this.width = 140,
    this.height = 44,
    this.frequency = 1.15,
    this.speed = 0.045,
    this.thickness = 3.3,
    this.backgroundBlurSigma = 14,
    this.showGlow = true,
    this.cornerRadius = 20,
    this.semanticsLabel,
  });

  @override
  State<LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<LiveWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _phase = 0.0;

  @override
  void initState() {
    super.initState();
    // 1 s Loop; wir benutzen den Ticker nur als Frame-Callback.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(() {
        setState(() {
          _phase = (_phase + widget.speed) % (math.pi * 2);
        });
      });

    if (widget.isActive) _controller.repeat();
  }

  @override
  void didUpdateWidget(LiveWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _shouldBlur =>
      widget.isActive || widget.amplitude.clamp(0.0, 1.0) > 0.05;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? ZenColors.jadeMid;
    final amp = (widget.amplitude).clamp(0.0, 1.0);

    return Semantics(
      label: widget.semanticsLabel ??
          'Live Waveform ${widget.isActive ? "aktiv" : "inaktiv"} — Amplitude ${(amp * 100).round()} Prozent',
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.cornerRadius),
          child: Stack(
            children: [
              // Zen-Glas-Hintergrund
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 360),
                  opacity: widget.isActive ? 1.0 : 0.75,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          c.withValues(alpha: 0.16),
                          ZenColors.white.withValues(alpha: 0.17),
                          c.withValues(alpha: 0.12),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: _shouldBlur
                        ? BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: widget.backgroundBlurSigma,
                              sigmaY: widget.backgroundBlurSigma,
                            ),
                            child: const SizedBox.expand(),
                          )
                        : const SizedBox.expand(),
                  ),
                ),
              ),

              // Wellen-Malfläche
              SizedBox(
                width: widget.width,
                height: widget.height,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    phase: _phase,
                    amplitude: amp,
                    color: c,
                    frequency: widget.frequency,
                    thickness: widget.thickness,
                    showGlow: widget.showGlow,
                    active: widget.isActive,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double phase;
  final double amplitude; // 0..1
  final Color color;
  final double frequency;
  final double thickness;
  final bool showGlow;
  final bool active;

  _WaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.color,
    required this.frequency,
    required this.thickness,
    required this.showGlow,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Hann-Fenster = weiche Ränder
    double envelope(double t) => 0.5 * (1 - math.cos(2 * math.pi * t));

    // Schrittweite dpi-bewusst, aber capped für Performance
    final step = math.max(1.0, size.width / 160.0);

    // Unterwelle (schwächer, leicht phasenversetzt)
    final underPath = Path();
    for (double x = 0; x <= size.width; x += step) {
      final t = x / size.width;
      final env = envelope(t);
      final y = size.height / 2 +
          math.sin(phase + t * 2 * math.pi * frequency + 0.6) *
              (amplitude * 0.55) *
              env *
              size.height *
              0.40;
      if (x == 0) {
        underPath.moveTo(x, y);
      } else {
        underPath.lineTo(x, y);
      }
    }

    final underPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness * 0.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.35);
    canvas.drawPath(underPath, underPaint);

    // Hauptwelle (Gradient über die Breite)
    final mainPath = Path();
    for (double x = 0; x <= size.width; x += step) {
      final t = x / size.width;
      final env = envelope(t);
      final y = size.height / 2 +
          math.sin(phase + t * 2 * math.pi * frequency) *
              (amplitude) *
              env *
              size.height *
              0.42;
      if (x == 0) {
        mainPath.moveTo(x, y);
      } else {
        mainPath.lineTo(x, y);
      }
    }

    final grad = LinearGradient(
      colors: [
        color.withValues(alpha: active ? 0.90 : 0.75),
        color.withValues(alpha: active ? 0.65 : 0.55),
        color.withValues(alpha: active ? 0.90 : 0.75),
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(Offset.zero & size);

    final mainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = grad;

    // Leichter Schatten unter der Welle
    canvas.drawShadow(mainPath, color.withValues(alpha: 0.12), 6.0, false);
    canvas.drawPath(mainPath, mainPaint);

    // Glow-Dot am rechten Rand
    if (showGlow) {
      const t = 0.93; // leicht links vom Rand
      final env = envelope(t);
      final dotY = size.height / 2 +
          math.sin(phase + t * 2 * math.pi * frequency + 0.2) *
              (amplitude) *
              env *
              size.height *
              0.42;

      final glow = Paint()
        ..color = color.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(size.width * t, dotY), 5.5, glow);

      final core = Paint()..color = color.withValues(alpha: 0.75);
      canvas.drawCircle(Offset(size.width * t, dotY), 3.0, core);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) {
    return old.phase != phase ||
        old.amplitude != amplitude ||
        old.color != color ||
        old.frequency != frequency ||
        old.thickness != thickness ||
        old.showGlow != showGlow ||
        old.active != active;
  }
}
