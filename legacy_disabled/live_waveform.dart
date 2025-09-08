// lib/features/_legacy_gedankenbuch/live_waveform.dart
//
// LiveWaveform — Oxford Zen Edition (refined)
// ------------------------------------------
// • Sanfte, performante Echtzeit-Wellenform für Mic/Voice-UI
// • Design-DNA: Glas, Soft-Glow, runde Caps, Zen-Farben
// • A11y-Semantics, Amplituden-Clamp, FPS-freundlich
// • Konfigurierbar: Frequenz, Speed, Thickness, Glow, Blur
// • Technische Verfeinerungen:
//   - Ticker-basiertes, kontinuierliches Animations-Loop (ohne künstliche Perioden)
//   - Weicher „Schatten“-Stroke statt harter drawShadow
//   - Subtilerer Glow-Dot
//   - Theme-Fallback für Farbe

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../shared/zen_style.dart';

class LiveWaveform extends StatefulWidget {
  /// Aktiviert/pausiert die Animation (Mic an/aus).
  final bool isActive;

  /// 0.0–1.0 — relative Ausschlagstärke der Welle.
  final double amplitude;

  /// Primärfarbe der Welle; Default: Theme.primary → Zen DeepSage.
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
    this.cornerRadius = 20, // entspricht in etwa ZenRadii.l
    this.semanticsLabel,
  });

  @override
  State<LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<LiveWaveform>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _phase = 0.0;

  @override
  void initState() {
    super.initState();
    // Kontinuierliches, fps-geregeltes Phase-Update:
    _ticker = createTicker((_) {
      // Ein einfacher, konstanter Schritt je Frame ist hier ausreichend
      // (die resultierende Geschwindigkeit hängt leicht von der fps ab,
      // was im UI-Kontext gewollt und natürlich wirkt).
      setState(() {
        _phase = (_phase + widget.speed) % (math.pi * 2);
      });
    });

    if (widget.isActive) _ticker.start();
  }

  @override
  void didUpdateWidget(LiveWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.isActive && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  bool get _shouldBlur =>
      widget.isActive || widget.amplitude.clamp(0.0, 1.0) > 0.05;

  @override
  Widget build(BuildContext context) {
    // Farb-Fallback: zuerst Theme.primary, dann Zen DeepSage
    final themePrimary = Theme.of(context).colorScheme.primary;
    final baseColor = widget.color ?? themePrimary ?? ZenColors.deepSage;
    final amp = (widget.amplitude).clamp(0.0, 1.0);

    final semanticsText = widget.semanticsLabel ??
        'Mikrofon-Wellenform ${widget.isActive ? "aktiv" : "inaktiv"}, Pegel ${(amp * 100).round()} Prozent';

    return Semantics(
      label: semanticsText,
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
                          baseColor.withValues(alpha: 0.16),
                          ZenColors.white.withValues(alpha: 0.17),
                          baseColor.withValues(alpha: 0.12),
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
                    color: baseColor,
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

    // Schrittweite dpi-bewusst, capped für Performance
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

    // „Weicher Schatten“ als extrabreiter, transparenter Stroke
    final softShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness * 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.16);
    canvas.drawPath(mainPath, softShadow);

    final mainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = grad;
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
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8); // subtiler
      canvas.drawCircle(Offset(size.width * t, dotY), 5.0, glow);

      final core = Paint()..color = color.withValues(alpha: 0.78);
      canvas.drawCircle(Offset(size.width * t, dotY), 2.6, core);
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
