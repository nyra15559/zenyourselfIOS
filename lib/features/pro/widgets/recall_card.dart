// [MERGE] lib/features/pro/widgets/recall_card.dart
// Pro Widgets — RecallCard (v1.0.1) · 2025-11-09
// -----------------------------------------------------------------------------
// Zweck
// • Kompakte Rückblick-Karte mit optionaler 14-Tage-Mini-Sparkline (−2..+2)
//   und kurzer Zusammenfassung (Recall-Summary).
//
// Patchnotes v1.0.1
// • FIX: Skeleton-Farbe via withOpacity (statt withValue) — compile-safe.
// • A11y: Semantics als Button, klare Labels/Hinweise; Material-Wrap für sauberes Ink.
// • UX: Defensive Null-/Empty-Guards; sanfte Platzhaltertexte.
// • Chart: Werte defensiv auf −2..+2 clampen; 14er-Schnitt robust.
//
// API
//   RecallCard(
//     series14: <double>?,                    // optionaler Verlauf −2..+2
//     initialSummary: String?,                // vorhandener Text (Cache) hat Vorrang
//     loadRecallSummary: () => Future<String?>?, // async Loader (z. B. MemoryService.buildRecallSummary())
//     onTap: () { ... },                      // optional Details öffnen
//   )
//
// Abhängigkeiten: fl_chart, eigene Zen-UI (zs/zw)
// -----------------------------------------------------------------------------

library recall_card;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

// Shared UI & Design (Pfad relativ zu /features/pro/widgets)
import '../../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../../shared/ui/zen_widgets.dart' as zw show ZenGlassCard;

class RecallCard extends StatefulWidget {
  /// Optionaler 14-Tage-Trend (Werte idealerweise −2..+2). Wenn null/leer, wird kein Trend angezeigt.
  final List<double>? series14;

  /// Bereits vorhandene Zusammenfassung (z. B. Cache), hat Vorrang vor async-Loader.
  final String? initialSummary;

  /// Async-Loader für die Rückblick-Copy (z. B. MemoryService.buildRecallSummary()).
  final Future<String?> Function()? loadRecallSummary;

  /// Optionaler Tap-Handler (Details öffnen).
  final VoidCallback? onTap;

  const RecallCard({
    super.key,
    this.series14,
    this.initialSummary,
    this.loadRecallSummary,
    this.onTap,
  });

  @override
  State<RecallCard> createState() => _RecallCardState();
}

class _RecallCardState extends State<RecallCard> {
  String? _summary;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSummary?.trim();
    _summary = (s == null || s.isEmpty) ? null : s;
    if (_summary == null && widget.loadRecallSummary != null) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final s = await widget.loadRecallSummary!.call();
      if (!mounted) return;
      final clean = s?.trim();
      setState(() => _summary = (clean == null || clean.isEmpty) ? null : clean);
    } catch (_) {
      if (!mounted) return;
      // still silent; neutraler Platzhalter bleibt
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasTrend = (widget.series14 != null && widget.series14!.isNotEmpty);

    return Semantics(
      container: true,
      button: widget.onTap != null,
      label:
          'Rückblick. ${_summary == null ? "Keine Zusammenfassung verfügbar." : "Zusammenfassung vorhanden."}',
      child: ClipRRect(
        borderRadius: const BorderRadius.all(zs.ZenRadii.l),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: const BorderRadius.all(zs.ZenRadii.l),
              child: zw.ZenGlassCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                topOpacity: .22,
                bottomOpacity: .10,
                borderOpacity: .14,
                borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.history_rounded,
                            size: 18, color: zs.ZenColors.sage),
                        const SizedBox(width: 8),
                        Text(
                          'Rückblick',
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: zs.ZenColors.deepSage,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Mini-Sparkline (optional)
                    if (hasTrend) ...[
                      _MiniSparkline14(series: widget.series14!),
                      const SizedBox(height: 10),
                    ],

                    // Inhalt / Copy
                    if (_loading)
                      const _SummarySkeleton()
                    else if (_summary != null)
                      Semantics(
                        label: 'Zusammenfassung',
                        child: Text(
                          _summary!,
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium?.copyWith(
                            height: 1.36,
                            color: zs.ZenColors.deepSage,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Opacity(
                        opacity: .85,
                        child: Text(
                          'Heute lassen wir Raum. Wenn etwas wichtig ist, zeigt es sich.',
                          textAlign: TextAlign.center,
                          style: tt.bodySmall,
                        ),
                      ),

                    // optionaler Hint
                    if (widget.onTap != null) ...[
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: .75,
                        child: Text(
                          'Tippen für Details.',
                          textAlign: TextAlign.center,
                          style: tt.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini-Sparkline (14 Tage, 2 Linien: Trend & Ø7), −2..+2
// ─────────────────────────────────────────────────────────────────────────────

class _MiniSparkline14 extends StatelessWidget {
  final List<double> series; // −2..+2; ältestes → neuestes empfohlen
  const _MiniSparkline14({required this.series});

  @override
  Widget build(BuildContext context) {
    // Nur die letzten 14 Werte anzeigen
    final raw = series.length > 14 ? series.sublist(series.length - 14) : series;
    if (raw.isEmpty) return const SizedBox(height: 36);

    // Clamp auf [-2, 2] für Stabilität
    final data = raw.map((v) => v.clamp(-2.0, 2.0) as double).toList();

    final smoothed = _smoothSeries(data, strength: 0.35);
    final avg7 = _movingAverageSeries(data, 7);

    return Semantics(
      label: 'Mini-Stimmungsverlauf der letzten 14 Tage.',
      child: ClipRRect(
        borderRadius: const BorderRadius.all(zs.ZenRadii.s),
        child: SizedBox(
          height: 36,
          child: LineChart(
            LineChartData(
              minY: -2,
              maxY: 2,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                // Ø7
                LineChartBarData(
                  spots: List.generate(
                    avg7.length,
                    (i) => FlSpot(i.toDouble(), avg7[i]),
                  ),
                  isCurved: true,
                  color: zs.ZenColors.sage,
                  barWidth: 2.0,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
                // geglätteter Trend
                LineChartBarData(
                  spots: List.generate(
                    smoothed.length,
                    (i) => FlSpot(i.toDouble(), smoothed[i]),
                  ),
                  isCurved: true,
                  color: zs.ZenColors.deepSage,
                  barWidth: 2.2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeletons & Helper
// ─────────────────────────────────────────────────────────────────────────────

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _skel(width: 220),
        const SizedBox(height: 6),
        _skel(width: 180),
      ],
    );
  }

  Widget _skel({double width = 200}) => Container(
        width: width,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.08),
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

// Glättung − einfache EMA-ähnliche Smoothing-Kurve
List<double> _smoothSeries(List<double> d, {double strength = 0.3}) {
  if (d.isEmpty) return const [];
  final s = <double>[];
  double prev = d.first;
  for (final v in d) {
    prev = prev + (v - prev) * (0.2 + strength * 0.6);
    s.add(prev.clamp(-2.0, 2.0));
  }
  return s;
}

// Gleitender Durchschnitt (clamped)
List<double> _movingAverageSeries(List<double> d, int window) {
  if (d.isEmpty || window <= 1) return List<double>.from(d);
  final out = <double>[];
  double sum = 0;
  int start = 0;
  for (int i = 0; i < d.length; i++) {
    sum += d[i];
    if (i - start + 1 > window) {
      sum -= d[start];
      start++;
    }
    final len = (i - start + 1);
    final avg = (sum / len).clamp(-2.0, 2.0);
    out.add(avg);
  }
  return out.cast<double>();
}
