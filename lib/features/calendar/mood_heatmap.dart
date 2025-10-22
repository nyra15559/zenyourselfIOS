// lib/features/calendar/mood_heatmap.dart
//
// MoodHeatmap — ZenYourself (Oxford Edition, ZenColors, Scale 0–4)
// -----------------------------------------------------------------
// • Wochen-Heatmap (Mo–So), ruhige Ästhetik, Theme-basiert
// • Farben aus ZenColors (Jade-Hue, steigende Deckkraft je Score 0–4)
// • A11y: Semantics-Labels inkl. „Heute“-Hinweis
// • „Heute“-Ring, sanfter Tooltip, optionaler Lottie-Glow im Hintergrund
// • Null-safety: keine ?. + ! Mischfehler
//
// Hinweise:
// – Keine hartcodierten Marken-Fonts; nutze Theme.
// – Color.withValues(alpha: …) gemäß Projektstandard.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../shared/zen_style.dart' as zs; // ZenColors, Radii, Spacing
import '../../data/mood_entry.dart';

class MoodHeatmap extends StatelessWidget {
  final List<MoodEntry> moodEntries;

  /// Optional: sanfter Lottie-Glow im Hintergrund
  final bool showBackgroundGlow;

  const MoodHeatmap({
    super.key,
    required this.moodEntries,
    this.showBackgroundGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMini = size.width < 340 || size.height < 560;
    final now = DateTime.now();

    // Wochenfenster (Mo–So) basierend auf heutigem Datum
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekDays =
        List<DateTime>.generate(7, (i) => monday.add(Duration(days: i)));

    // Für jeden Wochentag: letzter Eintrag (oder null)
    final entries = weekDays
        .map((date) => moodEntries.lastWhereOrNull(
              (e) =>
                  e.timestamp.year == date.year &&
                  e.timestamp.month == date.month &&
                  e.timestamp.day == date.day,
            ))
        .toList();

    final cardBg = Theme.of(context).colorScheme.surfaceContainerHighest
        .withValues(alpha: .96);
    final borderColor =
        Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .18);
    final shadowColor = zs.ZenColors.deepSage.withValues(alpha: .07);
    final titleColor = zs.ZenColors.deepSage;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (!isMini && showBackgroundGlow)
          Positioned.fill(
            child: Lottie.asset(
              'assets/lottie/cloud_glow.json',
              fit: BoxFit.cover,
              repeat: true,
              animate: true,
              alignment: Alignment.topCenter,
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: borderColor, width: 1.2),
          ),
          padding: EdgeInsets.symmetric(
            vertical: isMini ? 9 : 19,
            horizontal: isMini ? 7 : 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isMini ? 'Zen-Woche' : 'Deine Woche im Zen-Flow',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                      letterSpacing: .14,
                    ),
              ),
              SizedBox(height: isMini ? 10 : 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(7, (i) {
                  final date = weekDays[i];
                  final entry = entries[i];
                  final isEmpty = entry == null || (entry.moodScore ?? -1) < 0;
                  final score = entry?.moodScore ?? -1;
                  final moodColor = isEmpty
                      ? Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: .22)
                      : _scoreColor(score).withValues(alpha: .95);
                  final emoji = isEmpty ? '…' : _emojiForScore(score);
                  final isToday = _isSameDay(date, now);

                  return _ZenDayMoodBubble(
                    emoji: emoji,
                    score: isEmpty ? null : score,
                    label: _weekdayLabel(i),
                    color: moodColor,
                    highlight: !isEmpty && score == 4,
                    mini: isMini,
                    date: date,
                    entry: entry,
                    isToday: isToday,
                  );
                }),
              ),
              if (!isMini)
                Padding(
                  padding: const EdgeInsets.only(top: 13.0),
                  child: Opacity(
                    opacity: .88,
                    child: Text(
                      'Tippe für Details · lange halten für Zitat',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                zs.ZenColors.deepSage.withValues(alpha: .88),
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Farbskala 0–4 auf Basis **ZenColors.jade** (gleicher Hue, wachsende Deckkraft).
  static Color _scoreColor(int score) {
    final jade = zs.ZenColors.jade;
    switch (score) {
      case 0:
        return jade.withValues(alpha: .16);
      case 1:
        return jade.withValues(alpha: .28);
      case 2:
        return jade.withValues(alpha: .42);
      case 3:
        return jade.withValues(alpha: .62);
      case 4:
        return jade.withValues(alpha: .82);
      default:
        return jade.withValues(alpha: .10);
    }
  }

  static String _emojiForScore(int score) {
    switch (score) {
      case 0:
        return '🌫️';
      case 1:
        return '🌦️';
      case 2:
        return '⛅';
      case 3:
        return '🌤️';
      case 4:
        return '🌞';
      default:
        return '…';
    }
  }

  static String _labelForScore(int? score) {
    switch (score) {
      case 0:
        return 'Tief';
      case 1:
        return 'Niedrig';
      case 2:
        return 'Neutral';
      case 3:
        return 'Klar';
      case 4:
        return 'Erfüllt';
      default:
        return 'Keine Angabe';
    }
  }

  static String _weekdayLabel(int i) {
    const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return labels[i];
  }
}

// --- Einzelner Wochentag: Zen-MoodBubble, interaktiv, animiert, A11y --------
class _ZenDayMoodBubble extends StatefulWidget {
  final String emoji;
  final int? score;
  final String label;
  final Color color;
  final bool highlight;
  final bool mini;
  final DateTime date;
  final MoodEntry? entry;
  final bool isToday;

  const _ZenDayMoodBubble({
    required this.emoji,
    required this.score,
    required this.label,
    required this.color,
    required this.highlight,
    required this.mini,
    required this.date,
    required this.entry,
    required this.isToday,
  });

  @override
  State<_ZenDayMoodBubble> createState() => _ZenDayMoodBubbleState();
}

class _ZenDayMoodBubbleState extends State<_ZenDayMoodBubble> {
  bool _showTooltip = false;

  @override
  Widget build(BuildContext context) {
    final double bubbleSize = widget.mini ? 29 : 37;
    final double emojiSize = widget.mini ? 15 : 20;

    final semanticsLabel = _semanticsForDay(
      date: widget.date,
      score: widget.score,
      label: widget.label,
      isToday: widget.isToday,
    );

    final ringColor =
        zs.ZenColors.deepSage.withValues(alpha: .22); // „Heute“-Ring

    return Semantics(
      button: widget.entry != null,
      label: semanticsLabel,
      child: GestureDetector(
        onTap: widget.entry == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(() => _showTooltip = !_showTooltip);
                if (_showTooltip) {
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _showTooltip = false);
                  });
                }
              },
        onLongPress: () {
          final summary = widget.entry?.aiSummary;
          final hasSummary =
              summary != null && summary.trim().isNotEmpty;
          if (!hasSummary) return;

          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '„${summary.trim()}“',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: zs.ZenColors.white,
                    ),
              ),
              backgroundColor:
                  zs.ZenColors.deepSage.withValues(alpha: .92),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        },
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // „Heute“-Ring
                if (widget.isToday)
                  Container(
                    width: bubbleSize + 10,
                    height: bubbleSize + 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ringColor,
                        width: 2.0,
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: bubbleSize,
                  height: bubbleSize,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (widget.highlight)
                        BoxShadow(
                          color: zs.ZenColors.deepSage.withValues(alpha: .15),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                    ],
                    border: Border.all(
                      color: widget.highlight
                          ? zs.ZenColors.deepSage
                          : Colors.transparent,
                      width: widget.highlight ? 2.2 : 1.1,
                    ),
                  ),
                  child: Center(
                    child: ExcludeSemantics(
                      child: Text(
                        widget.emoji,
                        style: TextStyle(fontSize: emojiSize),
                      ),
                    ),
                  ),
                ),
                if (_showTooltip && widget.entry != null)
                  Positioned(
                    top: -44,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              zs.ZenColors.deepSage.withValues(alpha: .96),
                          borderRadius: const BorderRadius.all(zs.ZenRadii.s),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .11),
                              blurRadius: 7,
                            ),
                          ],
                        ),
                        child: Text(
                          _tooltipText(widget.entry!),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: zs.ZenColors.white,
                                fontSize: 12.6,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (!widget.mini) ...[
              const SizedBox(height: 7),
              Text(
                widget.score?.toString() ?? '',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: zs.ZenColors.deepSage,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: zs.ZenColors.deepSage,
                      fontWeight: FontWeight.w400,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _tooltipText(MoodEntry entry) {
    final day = entry.timestamp.day.toString().padLeft(2, '0');
    final month = entry.timestamp.month.toString().padLeft(2, '0');
    final label = MoodHeatmap._labelForScore(entry.moodScore);
    final extra = entry.aiSummary;
    if (extra == null || extra.trim().isEmpty) {
      return 'Am $day.$month. – Stimmung: $label';
    }
    return 'Am $day.$month. – $label · ${extra.trim()}';
  }

  String _semanticsForDay({
    required DateTime date,
    required int? score,
    required String label,
    required bool isToday,
  }) {
    final d =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.';
    final moodLabel = MoodHeatmap._labelForScore(score);
    final today = isToday ? ' (Heute)' : '';
    return '$label, $d – Stimmung: $moodLabel$today';
  }
}

// Null-safe lastWhereOrNull-Extension:
extension LastWhereOrNull<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
