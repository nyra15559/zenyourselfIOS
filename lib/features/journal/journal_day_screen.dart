// lib/features/journal/journal_day_screen.dart
//
// JournalDayScreen — Zen v6.28 · 2025-09-04 (Future-Vision)
// --------------------------------------------------------------------
// • Tages-Detailansicht im Oxford-Zen-Look (Backdrop + PandaHeader).
// • Header-Karte als Glas-Bubble: Datum, Kennzahlen, 7-Tage-Sparkline.
// • Filter-Chips (Alle / Notizen / Reflexionen / Kurzgeschichten).
// • Einträge als Mini-Story-Karten (JournalEntryCard) inkl. Aktionen.
// • A11y/Haptics, sanfte Abstände, iOS-ähnliches Bouncing.
//

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/journal_entry.dart';
import '../../models/journal_entries_provider.dart';
import '../../shared/zen_style.dart'
    show ZenColors, ZenTextStyles, ZenShadows, ZenSpacing, ZenRadii;
import '../../shared/ui/zen_widgets.dart' as zw;

import './journal_entry_card.dart';
import '../reflection/reflection_screen.dart';

class JournalDayScreen extends StatefulWidget {
  /// Lokaler Tagesstart (nur Datum zählt).
  final DateTime dayLocal;

  const JournalDayScreen({Key? key, required this.dayLocal}) : super(key: key);

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
    final provider = context.watch<JournalEntriesProvider>();
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
        title: null, // Titel über PandaHeader → kein Doppel
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
              asset: 'assets/pro_screen.png',
              alignment: Alignment.center,
              glow: .34,
              vignette: .12,
              enableHaze: true,
              hazeStrength: .14,
              saturation: .94,
              wash: .10,
            ),
          ),
          RefreshIndicator(
            color: ZenColors.deepSage,
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
            },
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                // PandaHeader (ruhige Überschrift)
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
                            ctx.read<JournalEntriesProvider>().remove(e.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: JournalEntryCard(
                            entry: e,
                            maxWidth: 640,
                            onTap: () => _showEntrySheet(ctx, e),
                            onContinueReflection: e.type == JournalType.reflection
                                ? () => _continueReflection(ctx, e)
                                : null,
                            onEdit: () => _editEntry(ctx, e),
                            onShare: () => _shareEntry(ctx, e),
                            onDelete: () async {
                              final ok =
                                  await _confirmDeleteDialog(ctx) ?? false;
                              if (!ok) return;
                              // ignore: use_build_context_synchronously
                              ctx.read<JournalEntriesProvider>().remove(e.id);
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

  List<JournalEntry> _applyFilter(List<JournalEntry> all, _EntryFilter f) {
    switch (f) {
      case _EntryFilter.all:
        return all;
      case _EntryFilter.notes:
        return all.where((e) => e.type == JournalType.note).toList();
      case _EntryFilter.reflections:
        return all.where((e) => e.type == JournalType.reflection).toList();
      case _EntryFilter.stories:
        return all.where((e) => e.type == JournalType.story).toList();
    }
  }

  static Widget _deleteBg() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.redAccent.withOpacity(.14),
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

  Future<void> _showEntrySheet(BuildContext context, JournalEntry e) async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EntryBottomSheet(entry: e),
    );
  }

  void _continueReflection(BuildContext context, JournalEntry e) {
    final seed =
        (e.text.isNotEmpty ? e.text : (e.analysis?.mirror ?? e.label)).trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReflectionScreen(
          initialUserText: seed.isEmpty ? e.label : seed,
        ),
      ),
    );
  }

  void _editEntry(BuildContext context, JournalEntry e) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bearbeiten – kommt gleich 🙂')),
    );
  }

  Future<void> _shareEntry(BuildContext context, JournalEntry e) async {
    final dd = e.createdAtLocal.day.toString().padLeft(2, '0');
    final mm = e.createdAtLocal.month.toString().padLeft(2, '0');
    final hh = e.createdAtLocal.hour.toString().padLeft(2, '0');
    final mi = e.createdAtLocal.minute.toString().padLeft(2, '0');
    final meta = '$dd.$mm.${e.createdAtLocal.year}, $hh:$mi';
    final text = '${e.label}\n\n${e.text}\n\n— $meta';
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('In Zwischenablage kopiert')),
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
      DateTime day, List<JournalEntry> entries, _DayMetrics m) {
    final dd = day.day.toString().padLeft(2, '0');
    final mm = day.month.toString().padLeft(2, '0');
    final head =
        'Journal — $dd.$mm.${day.year} · ${entries.length} Einträge · Ø-Mood ${m.avgMood.toStringAsFixed(2)}';
    final lines = <String>[head, ''];
    for (final e in entries) {
      final t = e.createdAtLocal;
      final hh = t.hour.toString().padLeft(2, '0');
      final min = t.minute.toString().padLeft(2, '0');
      final typ = e.type == JournalType.reflection
          ? 'Reflexion'
          : (e.type == JournalType.story ? 'Story' : 'Notiz');
      lines.add('[$hh:$min] $typ ${e.moodEmoji} — ${e.preview(120)}');
    }
    return lines.join('\n');
  }
}

// ---------- Header ----------

class _HeaderCard extends StatelessWidget {
  final DateTime day;
  final _DayMetrics metrics;

  const _HeaderCard({Key? key, required this.day, required this.metrics})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JournalEntriesProvider>();
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
      {Key? key,
      required this.icon,
      required this.label,
      required this.value,
      this.color})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZenColors.jadeMid;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: ZenColors.white.withOpacity(.72),
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

  const _FilterChips({Key? key, required this.filter, required this.onChanged})
      : super(key: key);

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
        selectedColor: ZenColors.jade.withOpacity(.10),
        side: BorderSide(
            color:
                selected ? ZenColors.jade.withOpacity(.55) : ZenColors.outline),
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
  const _EmptyDay({Key? key}) : super(key: key);

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
  const _Sparkline({Key? key, required this.values}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(values: values),
      size: Size.infinite,
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
        colors: [ZenColors.jadeMid.withOpacity(.22), Colors.transparent],
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

  static _DayMetrics fromEntries(List<JournalEntry> entries) {
    final n = entries.length;
    final refs =
        entries.where((e) => e.type == JournalType.reflection).length;
    double sum = 0;
    int m = 0;
    for (final e in entries) {
      final score = _moodMap[e.moodLabel ?? ''];
      if (score != null) {
        sum += score;
        m++;
      }
    }
    final avg = m == 0 ? 0.0 : double.parse((sum / m).toStringAsFixed(2));
    return _DayMetrics(count: n, reflections: refs, avgMood: avg);
  }
}

/// ---- Detail-BottomSheet (ruhige Mini-Reader-Ansicht) -----------------------

class _EntryBottomSheet extends StatelessWidget {
  final JournalEntry entry;
  const _EntryBottomSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.96),
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
              Icon(
                entry.type == JournalType.reflection
                    ? Icons.psychology_alt
                    : (entry.type == JournalType.story
                        ? Icons.auto_stories
                        : Icons.edit_note),
                color: entry.type == JournalType.reflection
                    ? ZenColors.jadeMid
                    : (entry.type == JournalType.story
                        ? ZenColors.cta
                        : ZenColors.deepSage),
              ),
              const SizedBox(width: 8),
              Text(
                entry.type == JournalType.reflection
                    ? 'Reflexion'
                    : (entry.type == JournalType.story
                        ? 'Kurzgeschichte'
                        : 'Tagebuch'),
                style:
                    ZenTextStyles.subtitle.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                _formatTime(entry.createdAtLocal),
                style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            entry.text.isNotEmpty ? entry.text : (entry.analysis?.mirror ?? ''),
            style: ZenTextStyles.body.copyWith(fontSize: 16.5, height: 1.38),
          ),
          if (((entry.aiQuestion ?? entry.analysis?.question) ?? '')
              .trim()
              .isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Frage: ${(entry.aiQuestion ?? entry.analysis?.question)!.trim()}',
                style: ZenTextStyles.caption.copyWith(
                  fontStyle: FontStyle.italic,
                  color: ZenColors.jadeMid,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(entry.moodEmoji.isNotEmpty ? entry.moodEmoji : '📝',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                entry.moodLabel ?? entry.mood?.note ?? '—',
                style: ZenTextStyles.caption.copyWith(color: ZenColors.ink),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Löschen'),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () async {
                  final ok = await _JournalDayScreenState
                          ._confirmDeleteDialog(context) ??
                      false;
                  if (!ok) return;
                  // ignore: use_build_context_synchronously
                  context.read<JournalEntriesProvider>().remove(entry.id);
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
