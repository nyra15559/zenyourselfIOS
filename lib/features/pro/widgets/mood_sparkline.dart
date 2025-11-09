// [NEW] lib/features/pro/widgets/mood_sparkline.dart — v1.2.1 (2025-11-08)
// MERGE SIGNAL: Kutsche-2 — Mood Sparkline (7/14/30), Dual-Line (mental/körperlich),
//               A11y-Label „Kopf X, Körper Y, dd.MM.yyyy“, Oxford-Zen-Stil, kein externes Paket
// -----------------------------------------------------------------------------------------------------------------
// Änderungen in v1.2.1
// • Factory .fromProvider(): scoreOfMental/scoreOfPhysical jetzt REQUIRED (vermeidet Feldzugriffe, die evtl. nicht existieren).
// • A11y-Label: clamp() → .toInt() für Strong-Mode-Sauberkeit.
// • Kleinere Kommentare & Semantics-Polish.
//
// Zweck
// • Visualisiert mentale & körperliche Stimmung als zwei Linien (Wertebereich 0..4, gemappt auf −2..+2) über 7/14/30 Tage.
// • A11y: Screen-Reader-Kurztext z. B. „Kopf 2, Körper 3, 08.11.2025“ basierend auf dem neuesten Tages-Eintrag.
// • Robust: funktioniert auch bei wenigen/ausgelassenen Tagen, zeigt Nulllinie als Platzhalter.
// • Stil: dezente Oxford-Zen-Optik, Farben aus ZenColors (deepSage/sage); keine externen Abhängigkeiten.
//
// Integration (Beispiele)
// -----------------------------------------------------------------------------------------------------------------
// // 1) Minimal: Nur die Kurve rendern (wenn du die Range extern steuerst):
// MoodSparkline.fromProvider(
//   provider: context.watch<MoodEntriesProvider>(),
//   windowDays: 14,
//   scoreOfMental: (e) => e.mental,     // 0..4
//   scoreOfPhysical: (e) => e.physical, // 0..4
// )
//
// // 2) Komfort: Card mit Titel + 7/14/30-Chips & A11y-Label:
// MoodSparklineCard(
//   provider: context.watch<MoodEntriesProvider>(),
//   initialDays: 14,
//   scoreOfMental: (e) => e.mental,
//   scoreOfPhysical: (e) => e.physical,
// )
//
// Hinweise
// • Der Provider liefert mit sparklineSeries() eine chronologische Reihe (nur Tage mit Eintrag). Fehlende Tage werden ausgelassen.
// • Für das A11y-Label wird der neueste MoodEntry (latestByDay) herangezogen. Existiert nur einer der beiden Werte, wird der andere als „–“ ausgegeben.
// • Farben/Typo kommen aus Zen-Style. Wenn ZenColors nicht verfügbar ist, passe die Imports/Farben lokal an.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../models/mood_entries_provider.dart' as mep;
import '../../../shared/zen_style.dart' as zs;

// ───────────────────────────────────────────────────────────────────────────────
// Public: Komfort-Card mit Titel + Range-Chips + A11y-Label
// ───────────────────────────────────────────────────────────────────────────────

class MoodSparklineCard extends StatefulWidget {
  final mep.MoodEntriesProvider provider;

  /// 7 / 14 / 30 (default 14)
  final int initialDays;

  /// 0..4
  final mep.ScoreOf scoreOfMental;

  /// 0..4
  final mep.ScoreOf scoreOfPhysical;

  final String title;
  final EdgeInsets contentPadding;
  final bool showZeroLine;

  const MoodSparklineCard({
    super.key,
    required this.provider,
    required this.scoreOfMental,
    required this.scoreOfPhysical,
    this.initialDays = 14,
    this.title = 'Dein Stimmungsverlauf',
    this.contentPadding = const EdgeInsets.fromLTRB(12, 10, 12, 12),
    this.showZeroLine = true,
  });

  @override
  State<MoodSparklineCard> createState() => _MoodSparklineCardState();
}

class _MoodSparklineCardState extends State<MoodSparklineCard> {
  static const _ranges = [7, 14, 30];
  late int _days;

  @override
  void initState() {
    super.initState();
    _days = _ranges.contains(widget.initialDays) ? widget.initialDays : 14;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final a11y = _buildA11yLabel();

    return Semantics(
      label: a11y,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .66),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: zs.ZenColors.outline, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: widget.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Titel + Range-Chips
            Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(Icons.show_chart_rounded,
                      size: 18, color: zs.ZenColors.ink),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: zs.ZenColors.inkStrong,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final r in _ranges)
                      _RangeChip(
                        label: '$r',
                        selected: _days == r,
                        onTap: () => setState(() => _days = r),
                      ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Sparkline
            MoodSparkline.fromProvider(
              provider: widget.provider,
              windowDays: _days,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              scoreOfMental: widget.scoreOfMental,
              scoreOfPhysical: widget.scoreOfPhysical,
              showZeroLine: widget.showZeroLine,
              // Tooltip: kleiner Trend-Hint (Δ letzter Punkt ggü. vorletztem)
              computeMoodTrend: (m, p) {
                final dm = _deltaOf(m);
                final dp = _deltaOf(p);
                String s(double v) => (v == 0)
                    ? '±0.0'
                    : (v > 0 ? '+${v.toStringAsFixed(1)}' : v.toStringAsFixed(1));
                return 'Trend • Kopf ${s(dm)} · Körper ${s(dp)}';
              },
            ),

            const SizedBox(height: 6),

            // Legende
            Row(
              children: [
                _LegendDot(color: zs.ZenColors.deepSage, label: 'Kopf'),
                const SizedBox(width: 12),
                _LegendDot(color: zs.ZenColors.sage, label: 'Körper'),
                const Spacer(),
                // Kurztext für A11y/Visuell
                Flexible(
                  child: Text(
                    a11y,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: zs.ZenColors.ink.withValues(alpha: .75),
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Δ zwischen letztem Wert des Fensters und vorletztem
  double _deltaOf(List<double> series) {
    if (series.length < 2) return 0.0;
    return (series.last - series[series.length - 2]).clamp(-4.0, 4.0);
  }

  String _buildA11yLabel() {
    // Neuester pro Tag aus Provider, dann jüngsten wählen
    final byDay = widget.provider.latestByDay();
    if (byDay.isEmpty) return 'Keine Stimmungsdaten vorhanden';

    // Jüngster Eintrag
    final latest = byDay.values.reduce(
      (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
    );

    final ment = widget.scoreOfMental(latest);
    final phys = widget.scoreOfPhysical(latest);

    final dd = _fmtDate(latest.timestamp);
    final mStr = ment == null ? '–' : ment.clamp(0, 4).toInt().toString();
    final pStr = phys == null ? '–' : phys.clamp(0, 4).toInt().toString();

    // Gewünschtes Format: „Kopf 2, Körper 3, 08.11.2025“
    return 'Kopf $mStr, Körper $pStr, $dd';
  }

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? zs.ZenColors.jade.withValues(alpha: .16)
        : Colors.white.withValues(alpha: .66);
    final fg = selected ? zs.ZenColors.jade : zs.ZenColors.inkStrong;
    final border = selected ? zs.ZenColors.jade : zs.ZenColors.outline;

    return Semantics(
      button: true,
      toggled: selected,
      label: 'Zeitraum $label Tage',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(
              shape: StadiumBorder(side: BorderSide(color: border, width: 1.2)),
              color: bg,
              shadows: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: fg,
                height: 1.0,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              )
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: zs.ZenColors.inkStrong,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        )
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Public: Reiner Sparkline-Renderer (wenn du die Range extern steuerst)
// ───────────────────────────────────────────────────────────────────────────────

class MoodSparkline extends StatelessWidget {
  /// Wertebereich bereits gemappt auf −2..+2, ältestes → neuestes
  final List<double> mental;
  final List<double> physical;

  /// Letzte N Punkte anzeigen (Fenster am Reihen-Ende)
  final int windowDays;

  /// Visuelle Höhe
  final double height;

  /// Innenabstand (Plot-Rect)
  final EdgeInsets padding;

  /// Linienbreite mental/körperlich
  final double strokeMental;
  final double strokePhysical;

  /// Nulllinie bei y=0
  final bool showZeroLine;

  /// Statischer Tooltip oder dynamisch via computeMoodTrend
  final String? tooltipText;
  final String Function(List<double> mental, List<double> physical)?
      computeMoodTrend;

  /// Leichte Exponential-Glättung
  final bool smooth;

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

  /// Komfort-Fabrik: mappt Provider-Scores 0..4 → −2..+2 (s − 2.0)
  factory MoodSparkline.fromProvider({
    Key? key,
    required mep.MoodEntriesProvider provider,
    required mep.ScoreOf scoreOfMental,
    required mep.ScoreOf scoreOfPhysical,
    int windowDays = 14,
    double height = 36,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    double strokeMental = 2.2,
    double strokePhysical = 2.0,
    bool showZeroLine = true,
    String? tooltipText,
    String Function(List<double> mental, List<double> physical)?
        computeMoodTrend,
    bool smooth = true,
  }) {
    final m0 = provider.sparklineSeries(days: windowDays, scoreOf: scoreOfMental);
    final p0 = provider.sparklineSeries(days: windowDays, scoreOf: scoreOfPhysical);

    final m = m0.map((s) => (s.toDouble() - 2.0).clamp(-2.0, 2.0)).toList();
    final p = p0.map((s) => (s.toDouble() - 2.0).clamp(-2.0, 2.0)).toList();

    return MoodSparkline(
      key: key,
      mental: m,
      physical: p,
      windowDays: windowDays,
      height: height,
      padding: padding,
      strokeMental: strokeMental,
      strokePhysical: strokePhysical,
      showZeroLine: showZeroLine,
      tooltipText: tooltipText,
      computeMoodTrend: computeMoodTrend,
      smooth: smooth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tip =
        tooltipText ?? computeMoodTrend?.call(mental, physical) ?? 'Stimmungstrend';

    final m = _prepSeries(mental, windowDays);
    final p = _prepSeries(physical, windowDays);

    final semantic = [
      'Stimmungs-Sparkline (mental & körperlich)',
      if (m.isNotEmpty) 'mental aktuell: ${m.last.toStringAsFixed(1)}' else 'mental: n. v.',
      if (p.isNotEmpty) 'körperlich aktuell: ${p.last.toStringAsFixed(1)}' else 'körperlich: n. v.',
    ].join(', ');

    return Semantics(
      label: semantic,
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
    final slice =
        src.length <= n ? List<double>.from(src) : src.sublist(src.length - n);
    return slice.map((v) => v.clamp(-2.0, 2.0)).toList(growable: false);
  }

  // Leichte exponentielle Glättung
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

// ───────────────────────────────────────────────────────────────────────────────
// Painter
// ───────────────────────────────────────────────────────────────────────────────

class _MoodSparklinePainter extends CustomPainter {
  final List<double> mental;   // −2..+2
  final List<double> physical; // −2..+2
  final EdgeInsets padding;
  final double strokeMental;
  final double strokePhysical;
  final bool showZeroLine;

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
    final rect = Offset(padding.left, padding.top) &
        Size(size.width - padding.horizontal, size.height - padding.vertical);

    // Platzhalter: Nulllinie, wenn nichts zu zeichnen ist
    if ((mental.isEmpty && physical.isEmpty) ||
        rect.width <= 0 ||
        rect.height <= 0) {
      final y0 = _mapY(0.0, rect);
      final zero = Paint()
        ..color = Colors.black.withOpacity(.10)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(rect.left, y0), Offset(rect.right, y0), zero);
      return;
    }

    // Nulllinie
    if (showZeroLine) {
      final y0 = _mapY(0.0, rect);
      final zero = Paint()
        ..color = Colors.black.withOpacity(.12)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(rect.left, y0), Offset(rect.right, y0), zero);
    }

    // Reihenfolge: körperlich unten, mental oben (Kontrast)
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
      // Single-Punkt: hauchdünnes Segment (sichtbar, ohne Spitze)
      final x = rect.left;
      final y = _mapY(data.first, rect);
      return Path()
        ..moveTo(x, y)
        ..lineTo(x + 0.001, y);
    }

    final dx = n <= 1 ? 0.0 : rect.width / math.max(1, n - 1);
    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = rect.left + dx * i;
      final y = _mapY(data[i], rect);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
    // (Optional: später Cubic-Smoothing hinzufügen, aktuell bewusst linear/ruhig)
  }

  double _mapY(double v, Rect rect) {
    final t = ((v - _minY) / (_maxY - _minY)).clamp(0.0, 1.0); // 0..1
    return rect.bottom - t * rect.height;
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
