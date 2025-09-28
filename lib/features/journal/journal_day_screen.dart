// lib/features/journal/journal_day_screen.dart
//
// JournalDayScreen — Oxford-Zen v6.30 (SenStyleDart, ruhig & konsistent)
// Update: 2025-09-13
// --------------------------------------------------------------------
// • Tages-Detailansicht mit PandaHeader und Glas-Karte für Kennzahlen.
// • 7-Tage-Sparkline (Provider.moodSparkline) und kompakte Stat-Badges.
// • Filter-Chips: Alle / Notizen / Reflexionen / Kurzgeschichten.
// • Einträge als Mini-Story-Karten (JournalEntryCard) inkl. Aktionen.
// • Teilen: Tageszusammenfassung in Zwischenablage.
// • A11y: semantische Labels, ruhige Kontraste.
// • Fixes:
//   - RefreshIndicator ruft nun provider.restore() (sanftes Pull-to-refresh).
//   - Einheitlicher Provider-API-Call: removeById(...) statt remove(...).
//   - Null-sicher bei moodLabel in BottomSheet.
//   - CustomPaint: kein Size.infinite (nimmt Eltern-Constraints → vermeidet Layout-Issues).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/journal_entry.dart' as jm;
import '../../providers/journal_entries_provider.dart' as jp;

import '../../shared/zen_style.dart'
    show ZenColors, ZenTextStyles, ZenShadows, ZenSpacing, ZenRadii;
import '../../shared/ui/zen_widgets.dart' as zw;

import 'widgets/journal_entry_card.dart';
import '../reflection/reflection_screen.dart';

class JournalDayScreen extends StatefulWidget {
  /// Lokaler Tagesstart (nur Datum zählt).
  final DateTime dayLocal;

  const JournalDayScreen({super.key, required this.dayLocal});

  /// Komfort: Screen aus YYYYMMDD-Schlüssel.
  factory JournalDayScreen.forDayKey(int dayKey) => JournalDayScreen(
        dayLocal:
            DateTime(dayKey ~/ 10000, (dayKey % 10000) ~/ 100, dayKey % 100),
      );

  /// Komfort: Screen für beliebiges lokales Datum (Zeit ignoriert).
  factory JournalDayScreen.forDay(DateTime dayLocal) => JournalDayScreen(
        dayLocal: DateTime(dayLocal.year, dayLocal.month, dayLocal.day),
      );

  @override
  State<JournalDayScreen> createState() => _JournalDayScreenState();
}

enum _EntryFilter { all, notes, reflections, stories }

class _JournalDayScreenState extends State<JournalDayScreen>
    with TickerProviderStateMixin {
  _EntryFilter _filter = _EntryFilter.all;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<jp.JournalEntriesProvider>();
    final entries = provider.entriesForLocalDay(widget.dayLocal);
    final filtered = _applyFilter(entries, _filter);
    final metrics = _DayMetrics.fromEntries(entries);
    final canPop = Navigator.of(context).canPop();

    final isMobile = MediaQuery.of(context).size.width < 470;
    final pandaSize = isMobile ? 88.0 : 112.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: zw.ZenAppBar(
        title: null,
        showBack: canPop,
        actions: [
          IconButton(
            tooltip: 'Teilen (Kopie in Zwischenablage)',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () async {
              final text = _shareTextForDay(widget.dayLocal, entries, metrics);
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tageszusammenfassung kopiert')),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: zw.ZenBackdrop(
              asset: 'assets/schoen.png',
              alignment: Alignment.center,
              glow: .34,
              vignette: .12,
              enableHaze: true,
              hazeStrength: .14,
              saturation: .94,
              wash: .10,
            ),
          ),
          RefreshIndicator.adaptive(
            color: ZenColors.deepSage,
            onRefresh: () async {
              await context.read<jp.JournalEntriesProvider>().restore(); // sanft
              HapticFeedback.selectionClick();
            },
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                // PandaHeader
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 70, 16, 10),
                    child: zw.PandaHeader(
                      title: 'Dein Tag',
                      caption: _formatDay(widget.dayLocal, DateTime.now()),
                      pandaSize: pandaSize,
                      strongTitleGreen: true,
                    ),
                  ),
                ),

                // Header-Kennzahlen + Sparkline
                SliverToBoxAdapter(
                  child: _HeaderCard(day: widget.dayLocal, metrics: metrics),
                ),

                // Filter
                SliverToBoxAdapter(
                  child: _FilterChips(
                    filter: _filter,
                    onChanged: (f) {
                      HapticFeedback.selectionClick();
                      setState(() => _filter = f);
                    },
                  ),
                ),

                // Einträge (als Karten)
                if (filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyDay(),
                  )
                else
                  SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final e = filtered[i];
                      return Dismissible(
                        key: ValueKey(e.id),
                        direction: DismissDirection.endToStart,
                        background: _deleteBg(),
                        confirmDismiss: (_) => _confirmDeleteDialog(ctx),
                        onDismissed: (_) =>
                            ctx.read<jp.JournalEntriesProvider>().removeById(e.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: JournalEntryCard(
                            entry: e,
                            onTap: () => _showEntrySheet(ctx, e),
                            onContinue: e.kind == jm.EntryKind.reflection
                                ? () => _continueReflection(ctx, e)
                                : null,
                            onEdit: null,
                            onHide: null,
                            onDelete: () async {
                              final ok =
                                  await _confirmDeleteDialog(ctx) ?? false;
                              if (!ok) return;
                              // ignore: use_build_context_synchronously
                              ctx.read<jp.JournalEntriesProvider>().removeById(e.id);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- List helpers ---------------------------------------------------------

  List<jm.JournalEntry> _applyFilter(List<jm.JournalEntry> all, _EntryFilter f) {
    switch (f) {
      case _EntryFilter.all:
        return all;
      case _EntryFilter.notes:
        return all.where((e) => e.kind == jm.EntryKind.journal).toList();
      case _EntryFilter.reflections:
        return all.where((e) => e.kind == jm.EntryKind.reflection).toList();
      case _EntryFilter.stories:
        return all.where((e) => e.kind == jm.EntryKind.story).toList();
    }
  }

  static Widget _deleteBg() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.redAccent.withValues(alpha: .14),
      child: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 28),
    );
  }

  static Future<bool?> _confirmDeleteDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text('Dieser Vorgang kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEntrySheet(BuildContext context, jm.JournalEntry e) async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EntryBottomSheet(entry: e),
    );
  }

  void _continueReflection(BuildContext context, jm.JournalEntry e) {
    final seed = (() {
      if ((e.thoughtText ?? '').trim().isNotEmpty) return e.thoughtText!.trim();
      if ((e.userAnswer ?? '').trim().isNotEmpty) return e.userAnswer!.trim();
      if ((e.aiQuestion ?? '').trim().isNotEmpty) return e.aiQuestion!.trim();
      return e.computedTitle;
    })();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReflectionScreen(
          initialUserText: seed,
        ),
      ),
    );
  }

  // ---- Date & share ---------------------------------------------------------

  String _formatDay(DateTime dayLocal, DateTime now) {
    final isToday =
        dayLocal.year == now.year &&
        dayLocal.month == now.month &&
        dayLocal.day == now.day;
    final yest =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    final isYesterday =
        dayLocal.year == yest.year &&
        dayLocal.month == yest.month &&
        dayLocal.day == yest.day;
    if (isToday) return 'Heute';
    if (isYesterday) return 'Gestern';
    final dd = dayLocal.day.toString().padLeft(2, '0');
    final mm = dayLocal.month.toString().padLeft(2, '0');
    return '$dd.$mm.${dayLocal.year}';
  }

  String _shareTextForDay(
      DateTime day, List<jm.JournalEntry> entries, _DayMetrics m) {
    final dd = day.day.toString().padLeft(2, '0');
    final mm = day.month.toString().padLeft(2, '0');
    final head =
        'Journal — $dd.$mm.${day.year} · ${entries.length} Einträge · Ø-Mood ${m.avgMood.toStringAsFixed(2)}';
    final lines = <String>[head, ''];
    for (final e in entries) {
      final t = e.createdAt.toLocal();
      final hh = t.hour.toString().padLeft(2, '0');
      final min = t.minute.toString().padLeft(2, '0');
      final typ = e.kind == jm.EntryKind.reflection
          ? 'Reflexion'
          : (e.kind == jm.EntryKind.story ? 'Story' : 'Notiz');
      final preview = (() {
        if (e.kind == jm.EntryKind.journal) return (e.thoughtText ?? '').trim();
        if (e.kind == jm.EntryKind.reflection) {
          final a = (e.userAnswer ?? '').trim();
          if (a.isNotEmpty) return a;
          final q = (e.aiQuestion ?? '').trim();
          if (q.isNotEmpty) return q;
          return (e.thoughtText ?? '').trim();
        }
        // Story
        final s = (e.storyTeaser ?? '').trim();
        return s.isNotEmpty ? s : (e.storyTitle ?? '').trim();
      })();
      lines.add('[$hh:$min] $typ — ${_first(preview, 120)}');
    }
    return lines.join('\n');
  }

  String _first(String s, int n) =>
      s.length <= n ? s : ('${s.substring(0, n).trimRight()}…');
}

// ---------- Header ----------

class _HeaderCard extends StatelessWidget {
  final DateTime day;
  final _DayMetrics metrics;

  const _HeaderCard({required this.day, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<jp.JournalEntriesProvider>();
    final spark = provider.moodSparkline(days: 7); // ältestes -> neuestes

    final dd = day.day.toString().padLeft(2, '0');
    final mm = day.month.toString().padLeft(2, '0');
    final dateStr = '$dd.$mm.${day.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        label:
            'Tagesübersicht $dateStr. ${metrics.count} Einträge. Ø-Mood ${metrics.avgMood.toStringAsFixed(2)}.',
        child: zw.ZenGlassCard(
          padding: const EdgeInsets.all(ZenSpacing.padBubble),
          borderRadius: const BorderRadius.all(ZenRadii.xl),
          topOpacity: .24,
          bottomOpacity: .10,
          borderOpacity: .16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateStr,
                  style:
                      ZenTextStyles.h3.copyWith(color: ZenColors.inkStrong)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatBadge(
                    icon: Icons.article_outlined,
                    label: 'Einträge',
                    value: metrics.count.toString(),
                  ),
                  _StatBadge(
                    icon: Icons.psychology_alt_outlined,
                    label: 'Reflexionen',
                    value: metrics.reflections.toString(),
                  ),
                  _StatBadge(
                    icon: Icons.sentiment_satisfied_alt_outlined,
                    label: 'Ø-Mood',
                    value: metrics.avgMood.toStringAsFixed(2),
                    color: _moodColorFromScore(metrics.avgMood),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (spark.isNotEmpty) ...[
                Text('Mood — 7 Tage',
                    style:
                        ZenTextStyles.caption.copyWith(color: ZenColors.ink)),
                const SizedBox(height: 8),
                SizedBox(height: 64, child: _Sparkline(values: spark)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _moodColorFromScore(double s) {
    if (s <= -1.5) return ZenColors.cherry;
    if (s < -0.5) return ZenColors.gold;
    if (s < 0.5) return ZenColors.bamboo;
    if (s < 1.5) return ZenColors.jadeMid;
    return ZenColors.jade;
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _StatBadge(
      {required this.icon,
      required this.label,
      required this.value,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZenColors.jadeMid;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: ZenColors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZenColors.border),
        boxShadow: ZenShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Text(label,
              style: ZenTextStyles.caption.copyWith(color: ZenColors.ink)),
          const SizedBox(width: 8),
          Text(value, style: ZenTextStyles.subtitle.copyWith(color: c)),
        ],
      ),
    );
  }
}

// ---------- Filter ----------

class _FilterChips extends StatelessWidget {
  final _EntryFilter filter;
  final ValueChanged<_EntryFilter> onChanged;

  const _FilterChips({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(_EntryFilter f, String text, IconData icon) {
      final selected = f == filter;
      return ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? ZenColors.jade : ZenColors.jadeMid),
            const SizedBox(width: 6),
            Text(text),
          ],
        ),
        selected: selected,
        onSelected: (_) => onChanged(f),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        selectedColor: ZenColors.jade.withValues(alpha: .10),
        side: BorderSide(
          color: selected
              ? ZenColors.jade.withValues(alpha: .55)
              : ZenColors.outline,
        ),
        shape: const StadiumBorder(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        children: [
          chip(_EntryFilter.all, 'Alle', Icons.all_inclusive),
          chip(_EntryFilter.notes, 'Notizen', Icons.edit_note),
          chip(_EntryFilter.reflections, 'Reflexionen', Icons.psychology_alt),
          chip(_EntryFilter.stories, 'Kurzgeschichten', Icons.auto_stories),
        ],
      ),
    );
  }
}

// ---------- Empty ----------

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.nights_stay_outlined,
                size: 36, color: ZenColors.jadeMid),
            const SizedBox(height: 12),
            Text(
              'Noch keine Einträge für diesen Tag.',
              style:
                  ZenTextStyles.subtitle.copyWith(color: ZenColors.inkStrong),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Schreibe eine kurze Notiz oder halte eine Reflexion fest.',
              style: ZenTextStyles.caption.copyWith(color: ZenColors.ink),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Sparkline ----------

class _Sparkline extends StatelessWidget {
  final List<double> values; // erwarteter Bereich ~ −2..+2
  const _Sparkline({required this.values});

  @override
  Widget build(BuildContext context) {
    // Größe kommt von der umgebenden SizedBox (64px Höhe, volle Breite)
    return CustomPaint(
      painter: _SparklinePainter(values: values),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  _SparklinePainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final w = size.width;
    final h = size.height;

    // Achse: normalisiere in [0, 1] mit Min/Max (Fallback −2..+2)
    double minV = values.reduce(math.min);
    double maxV = values.reduce(math.max);
    if (minV == maxV) {
      minV -= 1;
      maxV += 1;
    }
    minV = math.min(minV, -2.0);
    maxV = math.max(maxV, 2.0);

    final dx = w / (values.length - 1);
    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final x = i * dx;
      final t = (values[i] - minV) / (maxV - minV); // 0..1
      final y = h - t * h;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paintLine = Paint()
      ..color = ZenColors.jadeMid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // leichte Fläche unter der Linie
    final fillPath = Path.from(path)
      ..lineTo((values.length - 1) * dx, h)
      ..lineTo(0, h)
      ..close();

    final paintFill = Paint()
      ..shader = LinearGradient(
        colors: [ZenColors.jadeMid.withValues(alpha: .22), Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    if (oldDelegate.values.length != values.length) return true;
    for (int i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}

// ---------- Metrics ----------

class _DayMetrics {
  final int count;
  final int reflections;
  final double avgMood;

  const _DayMetrics(
      {required this.count, required this.reflections, required this.avgMood});

  static const Map<String, double> _moodMap = {
    'Wütend': -2.0,
    'Gestresst': -1.0,
    'Traurig': -1.0,
    'Neutral': 0.0,
    'Ruhig': 1.0,
    'Glücklich': 2.0,
  };

  static _DayMetrics fromEntries(List<jm.JournalEntry> entries) {
    final n = entries.length;
    final refs =
        entries.where((e) => e.kind == jm.EntryKind.reflection).length;
    double sum = 0;
    int m = 0;
    for (final e in entries) {
      final label = e.moodLabel; // vom Model aus Tags abgeleitet
      final score = _moodMap[label ?? ''];
      if (score != null) {
        sum += score;
        m++;
      }
    }
    final avg = m == 0 ? 0.0 : double.parse((sum / m).toStringAsFixed(2));
    return _DayMetrics(count: n, reflections: refs, avgMood: avg);
  }
}

/// ---- Detail-BottomSheet ----------------------------------------------------

class _EntryBottomSheet extends StatelessWidget {
  final jm.JournalEntry entry;
  const _EntryBottomSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    final local = entry.createdAt.toLocal();
    final kindLabel = entry.kind == jm.EntryKind.reflection
        ? 'Reflexion'
        : (entry.kind == jm.EntryKind.story ? 'Kurzgeschichte' : 'Tagebuch');

    final icon = entry.kind == jm.EntryKind.reflection
        ? Icons.psychology_alt
        : (entry.kind == jm.EntryKind.story
            ? Icons.auto_stories
            : Icons.edit_note);

    final mainText = (() {
      if (entry.kind == jm.EntryKind.journal) {
        return (entry.thoughtText ?? '').trim();
      } else if (entry.kind == jm.EntryKind.reflection) {
        final a = (entry.userAnswer ?? '').trim();
        if (a.isNotEmpty) return a;
        final q = (entry.aiQuestion ?? '').trim();
        if (q.isNotEmpty) return q;
        return (entry.thoughtText ?? '').trim();
      } else {
        // story
        final teaser = (entry.storyTeaser ?? '').trim();
        if (teaser.isNotEmpty) return teaser;
        return (entry.storyTitle ?? '').trim();
      }
    })();

    final auxQuestion = entry.kind == jm.EntryKind.reflection
        ? (entry.aiQuestion ?? '').trim()
        : '';

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ZenColors.border),
        boxShadow: ZenShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: entry.kind == jm.EntryKind.reflection
                      ? ZenColors.jadeMid
                      : (entry.kind == jm.EntryKind.story
                          ? ZenColors.cta
                          : ZenColors.deepSage)),
              const SizedBox(width: 8),
              Text(
                kindLabel,
                style:
                    ZenTextStyles.subtitle.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                _formatTime(local),
                style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            mainText,
            style: ZenTextStyles.body.copyWith(fontSize: 16.5, height: 1.38),
          ),
          if (auxQuestion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Frage: $auxQuestion',
                style: ZenTextStyles.caption.copyWith(
                  fontStyle: FontStyle.italic,
                  color: ZenColors.jadeMid,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                (entry.moodLabel ?? '').isNotEmpty ? (entry.moodLabel ?? '') : '—',
                style: ZenTextStyles.caption.copyWith(color: ZenColors.ink),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Löschen'),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () async {
                  final ok =
                      await _JournalDayScreenState._confirmDeleteDialog(context) ??
                          false;
                  if (!ok) return;
                  // ignore: use_build_context_synchronously
                  context.read<jp.JournalEntriesProvider>().removeById(entry.id);
                  // ignore: use_build_context_synchronously
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
