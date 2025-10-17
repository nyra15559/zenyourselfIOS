// lib/features/pro/pro_screen.dart
//
// ProScreen — Oxford Journey Board (v3.9 · 2025-10-16)
// ------------------------------------------------------------------
// Neu & verfeinert (Oxford Dashboard):
// • Range-Switcher (7/30/90 Tage) steuert Trend + Ø-Mood.
// • Mobile: statt Zahlenchips jetzt echte Mini-Balken (ohne Zahlen).
// • Entfernt: unbenutztes Zahnrad oben rechts.
// • Streak (aufeinanderfolgende aktive Tage) + ruhige Empty-States.
// • Sanfte Appear-Animation, konsistente Typo/Weights/Schatten.
// • Provider-first, stabile Legacy-Fallbacks (MoodEntry/ReflectionEntry).
//

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

// Shared UI & Design (Alias-Imports → keine Namenskollisionen)
import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar;

// Domain (Legacy-Fallback)
import '../../data/mood_entry.dart';
import '../../data/reflection_entry.dart';

// Journal (kanonisches Modell)
import '../../providers/journal_entries_provider.dart';
import '../../models/journal_entry.dart' as jm;

// Export (AnonExportWidget)
import '../therapist/anon_export.dart';

// ------------------------------------------------------------------

enum _Range { d7, d30, d90 }

extension on _Range {
  int get days => switch (this) { _Range.d7 => 7, _Range.d30 => 30, _Range.d90 => 90 };
  String get label => switch (this) { _Range.d7 => '7', _Range.d30 => '30', _Range.d90 => '90' };
}

class ProScreen extends StatefulWidget {
  /// Legacy-Props bleiben für Export/Fallback erhalten.
  final List<MoodEntry> moodEntries;
  final List<ReflectionEntry> reflectionEntries;

  const ProScreen({
    super.key,
    required this.moodEntries,
    required this.reflectionEntries,
  });

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> with SingleTickerProviderStateMixin {
  _Range _range = _Range.d30;

  late final AnimationController _appearCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
        ..forward();

  @override
  void dispose() {
    _appearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 470;

    // ---- Provider (optional) -------------------------------------------------
    final prov = context.watch<JournalEntriesProvider?>();
    final hasProv = prov != null;

    // Serie & Kennzahlen aus Provider (−2 … +2); Fallbacks auf Legacy.
    final series = hasProv
        ? _seriesFromProvider(prov!, days: _range.days)
        : _fallbackSeriesFromMoodEntries(widget.moodEntries).takeLast(_range.days);

    final avgMood = hasProv
        ? _averageMoodFromProvider(prov!, window: Duration(days: _range.days))
        : _fallbackAvgMoodFromMoodEntries(widget.moodEntries);

    final reflectionsCount =
        hasProv ? prov!.reflections.length : widget.reflectionEntries.length;

    final activeDays = hasProv
        ? _activeDaysCountFromProvider(prov!)
        : widget.moodEntries.map((e) => e.dayTag).toSet().length;

    final streak = hasProv
        ? _streakFromProvider(prov!)
        : _streakFromLegacy(widget.moodEntries);

    final lastInsights =
        hasProv ? prov!.reflections.take(5).toList() : const <jm.JournalEntry>[];

    final last7MoodLegacy = widget.moodEntries.takeLast(7);
    final last7FromSeries = series.takeLast(7);

    final showMoodGraph =
        size.width > 410 && size.height > 670 && (series.length >= 4);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      // Zahnrad entfernt (keine actions)
      appBar: const zw.ZenAppBar(title: null, showBack: true),
      body: Stack(
        children: [
          // 0) Einheitlicher Backdrop (extra milchig)
          const Positioned.fill(
            child: zw.ZenBackdrop(
              asset: 'assets/pro_screen.png',
              alignment: Alignment.center,
              glow: .38,
              vignette: .14,
              enableHaze: true,
              hazeStrength: .18,
              saturation: .92,
              wash: .12,
            ),
          ),

          // 1) Inhalt
          FadeTransition(
            opacity: _appearCtrl
                .drive(Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic))),
            child: SlideTransition(
              position: _appearCtrl
                  .drive(Tween(begin: const Offset(0, .02), end: Offset.zero)
                      .chain(CurveTween(curve: Curves.easeOutCubic))),
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 20,
                    vertical: isMobile ? 20 : 36,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Panda & Titel
                        Column(
                          children: [
                            AnimatedPandaGlow(size: isMobile ? 88 : 112),
                            const SizedBox(height: 6),
                            Text(
                              'Deine Reise',
                              textAlign: TextAlign.center,
                              style: tt.headlineMedium!.copyWith(
                                fontSize: 28,
                                color: zs.ZenColors.deepSage,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.1,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.black.withValues(alpha: .08),
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Opacity(
                              opacity: 0.92,
                              child: Text(
                                _randomMantra(reflectionsCount),
                                textAlign: TextAlign.center,
                                style: tt.bodySmall!.copyWith(
                                  fontSize: 14.5,
                                  fontStyle: FontStyle.italic,
                                  color: zs.ZenColors.sage,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),

                        // Range Switcher — kleine Bubble
                        _RangeBubble(
                          range: _range,
                          onChange: (r) => setState(() => _range = r),
                          isMobile: isMobile,
                        ),

                        const SizedBox(height: 12),

                        // Mood-Trend — Glas-Bubble im Journey-Stil
                        ClipRRect(
                          borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: zw.ZenGlassCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              topOpacity: .26,
                              bottomOpacity: .10,
                              borderOpacity: .18,
                              borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.stacked_line_chart_rounded,
                                          size: 18, color: zs.ZenColors.jadeMid),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Stimmung – letzte ${_range.label} Tage',
                                        style: tt.bodyMedium!.copyWith(
                                          color: zs.ZenColors.deepSage,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (series.isNotEmpty)
                                    (showMoodGraph
                                        ? ZenMoodGraphSeries(series: series)
                                        : (last7FromSeries.isNotEmpty
                                            ? _ZenMoodBarSeries(last7: last7FromSeries)
                                            : _ZenMoodBar(last7: last7MoodLegacy)))
                                  else
                                    const _EmptyRowHint(
                                      icon: Icons.data_thresholding_rounded,
                                      text: 'Noch keine Daten in diesem Zeitraum.',
                                    ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Ø Stimmung: ${avgMood.toStringAsFixed(2)}',
                                      style: tt.bodyMedium!.copyWith(
                                        color: zs.ZenColors.deepSage,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Statistiken — Bubble
                        Semantics(
                          label: 'Statistiken',
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: zw.ZenGlassCard(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 10),
                                topOpacity: .24,
                                bottomOpacity: .10,
                                borderOpacity: .16,
                                borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _ProStatTile(
                                      label: 'Reflexionen',
                                      value: '$reflectionsCount',
                                      icon: Icons.psychology_alt_rounded,
                                    ),
                                    _vSep(),
                                    _ProStatTile(
                                      label: 'Aktive Tage',
                                      value: '$activeDays',
                                      icon: Icons.calendar_today_rounded,
                                    ),
                                    _vSep(),
                                    _ProStatTile(
                                      label: 'Streak',
                                      value: '${streak}d',
                                      icon: Icons.local_fire_department_rounded,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Export-Bereich — Bubble (PDF guarded, CSV stabil)
                        ClipRRect(
                          borderRadius: const BorderRadius.all(zs.ZenRadii.m),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: zw.ZenGlassCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              topOpacity: .22,
                              bottomOpacity: .10,
                              borderOpacity: .14,
                              borderRadius: const BorderRadius.all(zs.ZenRadii.m),
                              child: Column(
                                children: [
                                  Text(
                                    'Monatsdaten exportieren',
                                    textAlign: TextAlign.center,
                                    style: tt.titleMedium!.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: zs.ZenColors.sage,
                                      fontSize: isMobile ? 15.1 : 15.9,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _ProExportCircleButton(
                                        icon: Icons.picture_as_pdf_rounded,
                                        label: 'PDF',
                                        semanticsLabel:
                                            'Monatsdaten als PDF exportieren',
                                        onTap: () {
                                          try {
                                            AnonExportWidget.exportAsPDF(
                                              context,
                                              widget.moodEntries,
                                              widget.reflectionEntries,
                                            );
                                          } catch (_) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'PDF-Export nicht möglich. Bitte später erneut versuchen.',
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 18),
                                      _ProExportCircleButton(
                                        icon: Icons.grid_on_rounded,
                                        label: 'CSV',
                                        semanticsLabel:
                                            'Monatsdaten als CSV exportieren',
                                        onTap: () {
                                          try {
                                            AnonExportWidget.exportAsCSV(
                                              context,
                                              widget.moodEntries,
                                            );
                                          } catch (_) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'CSV-Export nicht möglich. Bitte später erneut versuchen.',
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Letzte Einsichten — Bubble (Provider-first)
                        if ((hasProv && lastInsights.isNotEmpty) ||
                            widget.reflectionEntries.isNotEmpty)
                          ClipRRect(
                            borderRadius: const BorderRadius.all(zs.ZenRadii.m),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                              child: zw.ZenGlassCard(
                                topOpacity: .20,
                                bottomOpacity: .10,
                                borderOpacity: .14,
                                borderRadius:
                                    const BorderRadius.all(zs.ZenRadii.m),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Deine letzten Einsichten',
                                      style: tt.titleMedium!.copyWith(
                                        color: zs.ZenColors.sage,
                                        fontSize: isMobile ? 14.3 : 15.5,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    ..._buildInsightsList(
                                      context: context,
                                      tt: tt,
                                      prov: prov,
                                      lastInsights: lastInsights,
                                      legacy: widget.reflectionEntries,
                                    ),
                                    if ((hasProv && lastInsights.isEmpty) &&
                                        widget.reflectionEntries.isEmpty)
                                      const _EmptyRowHint(
                                        icon: Icons.bubble_chart_rounded,
                                        text: 'Noch keine Reflexionen.',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Privacy / Features — kleine Bubble
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(zs.ZenRadii.s),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                              child: zw.ZenGlassCard(
                                topOpacity: .16,
                                bottomOpacity: .08,
                                borderOpacity: .12,
                                borderRadius:
                                    const BorderRadius.all(zs.ZenRadii.s),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('• Daten bleiben lokal & anonym',
                                        style: tt.bodySmall),
                                    Text('• Export jederzeit möglich',
                                        style: tt.bodySmall),
                                    Text('• Deine Reflexionen gehören nur dir',
                                        style: tt.bodySmall),
                                    Text('• Keine Werbung, maximale Kontrolle',
                                        style: tt.bodySmall),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Affirmation
                        Opacity(
                          opacity: 0.96,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.spa_rounded,
                                  color: zs.ZenColors.sage, size: 21),
                              const SizedBox(width: 7),
                              Text(
                                'Du darfst einfach da sein.',
                                style: tt.bodyMedium!.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: zs.ZenColors.deepSage,
                                  fontSize: isMobile ? 14.1 : 15.2,
                                  letterSpacing: 0.02,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('🤍', style: TextStyle(fontSize: 16.5)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Insights-Listenaufbau (Provider-first, Legacy-Fallback) ----
  List<Widget> _buildInsightsList({
    required BuildContext context,
    required TextTheme tt,
    required JournalEntriesProvider? prov,
    required List<jm.JournalEntry> lastInsights,
    required List<ReflectionEntry> legacy,
  }) {
    if (prov != null && lastInsights.isNotEmpty) {
      return lastInsights.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.7),
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.bubble_chart_rounded,
              color: zs.ZenColors.deepSage.withValues(alpha: 0.86),
            ),
            title: Text(
              _bestReflectionTextJournal(e),
              style: tt.bodyMedium!.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 14.2,
              ),
            ),
            subtitle: Text(
              _formatDate(e.createdAt.toLocal()),
              style: tt.bodySmall!.copyWith(
                fontSize: 11.5,
                color: Colors.black54,
              ),
            ),
          ),
        );
      }).toList();
    }

    // Legacy
    return legacy.reversed.take(5).map((e) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.7),
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.bubble_chart_rounded,
            color: zs.ZenColors.deepSage.withValues(alpha: 0.86),
          ),
          title: Text(
            _bestReflectionTextLegacy(e),
            style: tt.bodyMedium!.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 14.2,
            ),
          ),
          subtitle: Text(
            _formatDate(e.timestamp),
            style: tt.bodySmall!.copyWith(
              fontSize: 11.5,
              color: Colors.black54,
            ),
          ),
        ),
      );
    }).toList();
  }

  static String _bestReflectionTextLegacy(ReflectionEntry e) {
    final raw = (e.aiSummary ?? e.preview(120)).trim();
    return raw.isEmpty ? '—' : raw;
  }

  static String _bestReflectionTextJournal(jm.JournalEntry e) {
    final raw = [
      e.userAnswer,
      e.thoughtText,
      e.title,
      e.aiQuestion,
    ]
        .whereType<String>()
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '—');

    return raw.length <= 120 ? raw : '${raw.substring(0, 120).trimRight()}…';
  }

  static String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  static String _randomMantra(int idx) {
    const lines = [
      'Du darfst einfach da sein.',
      'Zeit hat keine Eile.',
      'Heute genügt.',
      'Hier ist Raum für dich.',
      'Alles darf sein, wie es ist.',
      'Atme. Mehr braucht es nicht.',
      'Sanft ist stark genug.',
      'Kleine Wellen, stilles Wasser.',
      'Dein Tempo ist willkommen.',
    ];
    return lines[idx % lines.length];
  }
}

// ---------- Widgets ----------

class _RangeBubble extends StatelessWidget {
  final _Range range;
  final ValueChanged<_Range> onChange;
  final bool isMobile;

  const _RangeBubble({
    required this.range,
    required this.onChange,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: const BorderRadius.all(zs.ZenRadii.s),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: zw.ZenGlassCard(
          topOpacity: .18,
          bottomOpacity: .08,
          borderOpacity: .12,
          borderRadius: const BorderRadius.all(zs.ZenRadii.s),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RangeChip(
                label: '7 Tage',
                selected: range == _Range.d7,
                onTap: () => onChange(_Range.d7),
              ),
              const SizedBox(width: 6),
              _RangeChip(
                label: '30 Tage',
                selected: range == _Range.d30,
                onTap: () => onChange(_Range.d30),
              ),
              const SizedBox(width: 6),
              _RangeChip(
                label: '90 Tage',
                selected: range == _Range.d90,
                onTap: () => onChange(_Range.d90),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 10),
                Opacity(
                  opacity: .75,
                  child: Text(
                    'Ansicht verfeinern',
                    style: tt.bodySmall,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
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
        ? zs.ZenColors.deepSage.withValues(alpha: .15)
        : Colors.white.withValues(alpha: .12);
    final border = selected
        ? zs.ZenColors.deepSage.withValues(alpha: .40)
        : Colors.black.withValues(alpha: .14);
    final fg = selected ? zs.ZenColors.deepSage : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: border),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: zs.ZenColors.deepSage.withValues(alpha: .10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Row(
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 14, color: zs.ZenColors.deepSage),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: fg,
                fontSize: 12.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRowHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyRowHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Opacity(
        opacity: .85,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.black54),
            const SizedBox(width: 6),
            Text(text, style: tt.bodySmall),
          ],
        ),
      ),
    );
  }
}

class AnimatedPandaGlow extends StatefulWidget {
  final double size;
  const AnimatedPandaGlow({this.size = 68, super.key});

  @override
  State<AnimatedPandaGlow> createState() => _AnimatedPandaGlowState();
}

class _AnimatedPandaGlowState extends State<AnimatedPandaGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(top: 16, bottom: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: zs.ZenColors.deepSage
                  .withValues(alpha: 0.10 + 0.17 * _glowController.value),
              blurRadius: 30 + 16 * _glowController.value,
              spreadRadius: 4 + 5 * _glowController.value,
            ),
          ],
        ),
        child: Image.asset(
          'assets/star_pa.png',
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.pets, color: zs.ZenColors.deepSage, size: 42),
        ),
      ),
    );
  }
}

// MoodBar für kleine Screens (Legacy-Fallback)
class _ZenMoodBar extends StatelessWidget {
  final List<MoodEntry> last7;
  const _ZenMoodBar({required this.last7});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final e = i < last7.length ? last7[i] : null;
        final Color barColor = e == null
            ? Colors.grey.withValues(alpha: 0.30)
            : e.color.withValues(alpha: 0.96);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 18 + (e?.moodScore ?? 1) * 5.0,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: (e?.color ?? Colors.grey).withValues(alpha: 0.10),
                blurRadius: 9,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: (e?.color ?? Colors.grey).withValues(alpha: 0.35),
              width: 1.1,
            ),
          ),
        );
      }),
    );
  }
}

// Alternative MoodBar für Provider-Serie (−2..+2) für kleine Screens
class _ZenMoodBarSeries extends StatelessWidget {
  final List<double> last7; // −2..+2
  const _ZenMoodBarSeries({required this.last7});

  @override
  Widget build(BuildContext context) {
    // Normiere −2..+2 → 0..4 für die gleiche Visualhöhe
    final norm = last7.map((v) => (v + 2.0)).toList(); // 0..4
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final val = i < norm.length ? norm[i] : null;
        final color = val == null
            ? Colors.grey.withValues(alpha: 0.30)
            : (val >= 3.0
                ? zs.ZenColors.deepSage
                : (val >= 2.0 ? zs.ZenColors.sage : Colors.grey));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 18 + (val ?? 1) * 5.0,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 9,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: color.withValues(alpha: 0.35),
              width: 1.1,
            ),
          ),
        );
      }),
    );
  }
}

// MoodGraph (fl_chart) – Provider-Serie (−2 … +2) in Glas-Bubble
class ZenMoodGraphSeries extends StatelessWidget {
  final List<double> series; // −2 … +2; ältestes → neuestes
  const ZenMoodGraphSeries({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final data = series.takeLast(90); // falls Range 90 gewählt wurde

    return SizedBox(
      height: 118,
      child: LineChart(
        LineChartData(
          minY: -2,
          maxY: 2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                data.length,
                (i) => FlSpot(i.toDouble(), data[i]),
              ),
              isCurved: true,
              gradient: const LinearGradient(
                colors: [zs.ZenColors.deepSage, zs.ZenColors.sage],
              ),
              barWidth: 5.0,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    zs.ZenColors.sage.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots
                  .map(
                    (t) => LineTooltipItem(
                      'Wert: ${t.y.toStringAsFixed(2)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                  .toList(),
            ),
            handleBuiltInTouches: true,
          ),
        ),
      ),
    );
  }
}

// vertikale Trennlinie
Widget _vSep() => Container(
      width: 1.6,
      height: 37,
      color: zs.ZenColors.sage.withValues(alpha: 0.18),
    );

// Statistik-Kachel
class _ProStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ProStatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: zs.ZenColors.sage.withValues(alpha: 0.18),
          radius: 20.5,
          child: Icon(icon, color: zs.ZenColors.sage, size: 20.5),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: tt.bodyMedium!.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2.5),
        Text(
          label,
          style: tt.bodySmall!.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

// Export-Button als Zen-Kreis (mit A11y/Tooltips)
class _ProExportCircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback onTap;

  const _ProExportCircleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      child: Column(
        children: [
          Tooltip(
            message: label,
            child: GestureDetector(
              onTap: onTap,
              child: CircleAvatar(
                backgroundColor: zs.ZenColors.deepSage,
                radius: 19.5,
                child: Icon(icon, color: Colors.white, size: 18.5),
              ),
            ),
          ),
          const SizedBox(width: 0, height: 3.5),
          Text(
            label,
            style: tt.bodySmall!.copyWith(
              fontWeight: FontWeight.w600,
              color: zs.ZenColors.sage,
            ),
          ),
        ],
      ),
    );
  }
}

// takeLast-Extension
extension ListTakeLast<T> on List<T> {
  List<T> takeLast(int count) =>
      skip(length > count ? length - count : 0).toList();
}

// ---- Helper zur Provider-Analyse -------------------------------------------

const Map<String, double> _moodScoreMap = {
  // Label → Score (−2 … +2)
  'glücklich': 2.0,
  'ruhig': 1.0,
  'neutral': 0.0,
  'traurig': -1.0,
  'gestresst': -1.0,
  'wütend': -2.0,
};

double? _scoreFromTags(List<String> tags) {
  // 1) moodScore:<0..4> → −2..+2
  for (final t in tags) {
    final s = t.trim();
    if (s.startsWith('moodScore:')) {
      final n = int.tryParse(s.substring(10));
      if (n != null) return (n.clamp(0, 4) * 1.0) - 2.0;
    }
  }
  // 2) mood:<Label> → Map
  for (final t in tags) {
    final s = t.trim();
    if (s.startsWith('mood:')) {
      final key = s.substring(5).trim().toLowerCase();
      final v = _moodScoreMap[key];
      if (v != null) return v;
    }
  }
  return null;
}

List<double> _seriesFromProvider(JournalEntriesProvider prov, {required int days}) {
  if (prov.entries.isEmpty) return const [];

  final now = DateTime.now().toUtc();
  final start = now.subtract(Duration(days: days));
  final byDay = <String, List<double>>{};

  for (final e in prov.entries) {
    final t = e.createdAt.toUtc();
    if (t.isBefore(start)) continue; // robust gegen unsortierte Quellen
    final score = _scoreFromTags(e.tags);
    if (score == null) continue;
    final key =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    (byDay[key] ??= <double>[]).add(score);
  }

  if (byDay.isEmpty) return const [];

  // nach Datum aufsteigend sortieren und Tagesmittel bilden
  final keys = byDay.keys.toList()..sort((a, b) => a.compareTo(b));
  return keys.map((k) {
    final list = byDay[k]!;
    final avg =
        list.isEmpty ? 0.0 : (list.reduce((a, b) => a + b) / list.length);
    return avg.clamp(-2.0, 2.0);
  }).toList();
}

double _averageMoodFromProvider(JournalEntriesProvider prov,
    {Duration window = const Duration(days: 30)}) {
  if (prov.entries.isEmpty) return 0.0;
  final now = DateTime.now().toUtc();
  final start = now.subtract(window);
  final vals = <double>[];

  for (final e in prov.entries) {
    final t = e.createdAt.toUtc();
    if (t.isBefore(start)) continue;
    final score = _scoreFromTags(e.tags);
    if (score != null) vals.add(score);
  }
  if (vals.isEmpty) return 0.0;
  return vals.reduce((a, b) => a + b) / vals.length;
}

int _activeDaysCountFromProvider(JournalEntriesProvider prov) {
  final set = <String>{};
  for (final e in prov.entries) {
    final t = e.createdAt.toUtc();
    set.add('${t.year}-${t.month}-${t.day}');
  }
  return set.length;
}

int _streakFromProvider(JournalEntriesProvider prov) {
  final days = <String>{};
  for (final e in prov.entries) {
    final t = e.createdAt.toUtc();
    days.add('${t.year}-${t.month}-${t.day}');
  }
  if (days.isEmpty) return 0;

  int streak = 0;
  var cur = DateTime.now().toUtc();
  String key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  while (days.contains(key(cur))) {
    streak++;
    cur = cur.subtract(const Duration(days: 1));
  }
  return streak;
}

// ---- Helper zur Legacy-Reskalierung ----------------------------------------

List<double> _fallbackSeriesFromMoodEntries(List<MoodEntry> moodEntries) {
  // MoodEntry.moodScore (0..4) → −2..+2
  if (moodEntries.isEmpty) return const [];
  final data = moodEntries.takeLast(90); // Support bis 90 Tage
  return data.map((e) => (e.moodScore.toDouble() - 2.0)).toList();
}

double _fallbackAvgMoodFromMoodEntries(List<MoodEntry> moodEntries) {
  if (moodEntries.isEmpty) return 0.0;
  final avg =
      moodEntries.map((e) => e.moodScore).reduce((a, b) => a + b) /
          moodEntries.length;
  return avg - 2.0; // 0..4 → −2..+2
}

int _streakFromLegacy(List<MoodEntry> moodEntries) {
  if (moodEntries.isEmpty) return 0;
  final days = moodEntries
      .map((e) => e.dayTag)
      .where((s) => s.isNotEmpty)
      .toSet();
  int streak = 0;
  var cur = DateTime.now();
  String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  while (days.contains(key(cur))) {
    streak++;
    cur = cur.subtract(const Duration(days: 1));
  }
  return streak;
}
