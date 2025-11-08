// [BASELINE] lib/features/pro/widgets/mood_sparkline.dart (Stand: 2025-11-07)
// PRO-Widgets — MoodSparkline (mental + körperlich)
// v1.0.0 — Lightweight CustomPainter; Tooltip via computeMoodTrend(...)
//
// Zweck
// ------
// Kompakte Sparkline für den Pro-Screen, die ZWEI Stimmungsreihen zeigt:
//  - mental:    −2 … +2
//  - physical:  −2 … +2
// Kein fl_chart; reines CustomPaint → schnell & leicht.
//
// Öffentliche API
// ---------------
// MoodSparkline(
//    mental: <List<double>> ,   // −2..+2, ältestes → neuestes
//    physical: <List<double>> , // −2..+2, ältestes → neuestes
//    windowDays: 14,            // wie viele letzte Punkte visualisieren
//    height: 36,
//    computeMoodTrend: (m, p) => MemoryService.computeMoodTrend(m, p),
//    tooltipText: null,         // alternativ fixen Text übergeben
// )
//
// Hinweise
// --------
// • Tooltip zeigt Text aus `tooltipText ?? computeMoodTrend(mental, physical)`.
// • X-Skalierung: gleichmäßige Verteilung der letzten N Punkte (windowDays).
// • Y-Skalierung: feste Achsen −2 … +2, Nulllinie wird dezent gezeichnet.
// • Fallback: leere Reihen → schlanker Platzhalter.
//
// Design
// ------
// Farben aus ZenStyle, falls verfügbar; sonst neutrale Fallbacks.
// Keine Unschärfe, kein Glas — Caller kann ein ZenGlassCard-Wrapper außen herum setzen.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../shared/zen_style.dart' as zs;

class MoodSparkline extends StatelessWidget {
  final List<double> mental;     // −2..+2, alt → neu
  final List<double> physical;   // −2..+2, alt → neu
  final int windowDays;          // wie viele Punkte anzeigen (Ende der Reihen)
  final double height;           // visuelle Höhe
  final EdgeInsets padding;      // Innenabstand für die Kurven
  final double strokeMental;     // Linienbreite mental
  final double strokePhysical;   // Linienbreite körperlich
  final bool showZeroLine;       // Nulllinie bei y=0
  final String? tooltipText;     // fixer Tooltip-Text (optional)
  final String Function(List<double> mental, List<double> physical)?
      computeMoodTrend;          // liefert Tooltip-Text (optional)
  final bool smooth;             // leichte Glättung

  const MoodSparkline({
    super.key,
    required this.mental,
    required this.physical,
    this.windowDays = 14,
    this.height = 36,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.strokeMental = 2.2,
    this.strokePhysical = 2.0,
    this.showZeroLine = true,
    this.tooltipText,
    this.computeMoodTrend,
    this.smooth = true,
  });

  @override
  Widget build(BuildContext context) {
    // Tooltip-Text ermitteln
    final tip = tooltipText ?? computeMoodTrend?.call(mental, physical) ?? 'Stimmungstrend';

    // Letztes Fenster ausschneiden & clampen
    final m = _prepSeries(mental, windowDays);
    final p = _prepSeries(physical, windowDays);

    // Semantik & Tooltip; Caller kann zusätzlich um einen ZenGlassCard-Wrapper ergänzen
    return Semantics(
      label:
          'Stimmungs-Sparkline, mental und körperlich. Langer Druck zeigt den Trend-Text.',
      child: Tooltip(
        message: tip,
        triggerMode: TooltipTriggerMode.longPress,
        preferBelow: true,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _MoodSparklinePainter(
              mental: smooth ? _smooth(m) : m,
              physical: smooth ? _smooth(p) : p,
              padding: padding,
              strokeMental: strokeMental,
              strokePhysical: strokePhysical,
              showZeroLine: showZeroLine,
            ),
          ),
        ),
      ),
    );
  }

  // Nimmt die letzten N Werte, clamped auf −2..+2
  List<double> _prepSeries(List<double> src, int n) {
    if (src.isEmpty) return const [];
    final slice = src.length <= n ? List<double>.from(src) : src.sublist(src.length - n);
    return slice.map((v) => v.clamp(-2.0, 2.0)).toList();
  }

  // Exponentielle Glättung (leicht)
  List<double> _smooth(List<double> d, [double alpha = 0.35]) {
    if (d.isEmpty) return d;
    double prev = d.first;
    final out = <double>[];
    for (final v in d) {
      prev = prev + (v - prev) * alpha;
      out.add(prev.clamp(-2.0, 2.0));
    }
    return out;
  }
}

class _MoodSparklinePainter extends CustomPainter {
  final List<double> mental;
  final List<double> physical;
  final EdgeInsets padding;
  final double strokeMental;
  final double strokePhysical;
  final bool showZeroLine;

  // Feste Skala
  static const double _minY = -2.0;
  static const double _maxY =  2.0;

  _MoodSparklinePainter({
    required this.mental,
    required this.physical,
    required this.padding,
    required this.strokeMental,
    required this.strokePhysical,
    required this.showZeroLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if ((mental.isEmpty && physical.isEmpty) || size.width <= 0 || size.height <= 0) {
      // Kleiner Platzhalter (Nulllinie)
      final zeroY = _mapY(0, size);
      final paintZero = Paint()
        ..color = Colors.black.withOpacity(.10)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), paintZero);
      return;
    }

    // Innenfläche berücksichtigen
    final rect = Offset(padding.left, padding.top) &
        Size(size.width - padding.horizontal, size.height - padding.vertical);

    // Nulllinie
    if (showZeroLine) {
      final y0 = _mapY(0.0, size, rect: rect);
      final paintZero = Paint()
        ..color = Colors.black.withOpacity(.12)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(rect.left, y0), Offset(rect.right, y0), paintZero);
    }

    // Pfade aufspannen
    if (physical.isNotEmpty) {
      final pathP = _buildPath(physical, rect);
      final paintP = Paint()
        ..color = zs.ZenColors.sage
        ..strokeWidth = strokePhysical
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(pathP, paintP);
    }

    if (mental.isNotEmpty) {
      final pathM = _buildPath(mental, rect);
      final paintM = Paint()
        ..color = zs.ZenColors.deepSage
        ..strokeWidth = strokeMental
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(pathM, paintM);
    }
  }

  Path _buildPath(List<double> data, Rect rect) {
    final n = data.length;
    if (n == 1) {
      final x = rect.left;
      final y = _mapY(data.first, rect.size, rect: rect);
      return Path()..moveTo(x, y)..lineTo(x + 0.001, y);
    }

    final dx = n <= 1 ? 0.0 : rect.width / math.max(1, n - 1);
    final path = Path();

    for (int i = 0; i < n; i++) {
      final x = rect.left + dx * i;
      final y = _mapY(data[i], rect.size, rect: rect);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  // Wert (−2..+2) → Y in Pixel
  double _mapY(double v, Size size, {Rect? rect}) {
    final r = rect ?? (Offset.zero & size);
    final t = ((v - _minY) / (_maxY - _minY)).clamp(0.0, 1.0); // 0..1
    // 0 (bei _minY) → bottom, 1 (bei _maxY) → top
    return r.bottom - t * r.height;
  }

  @override
  bool shouldRepaint(covariant _MoodSparklinePainter old) {
    return old.mental != mental ||
        old.physical != physical ||
        old.padding != padding ||
        old.strokeMental != strokeMental ||
        old.strokePhysical != strokePhysical ||
        old.showZeroLine != showZeroLine;
  }
}
