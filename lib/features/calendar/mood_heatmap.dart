// lib/features/calendar/mood_heatmap.dart
//
// MoodHeatmap — ZenYourself (Oxford Edition)
// -----------------------------------------
// • Wochen-Heatmap (Mo–So) mit ruhiger Ästhetik
// • A11y: Semantics-Labels, klare Kontraste
// • „Heute“-Ring, sanfte Tooltip-Animation
// • Optionaler Lottie-Glow im Hintergrund

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../../data/mood_entry.dart';

const zenGreen = Color(0xFF0B3D2E);
const sandBeige = Color(0xFFFDF8EC);
const zenGrey = Color(0xFFD8D8D8);

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
    final weekDays = List<DateTime>.generate(7, (i) => monday.add(Duration(days: i)));

    // Für jeden Wochentag: letzter Eintrag (oder null)
    final entries = weekDays
        .map((date) => moodEntries.lastWhereOrNull(
              (e) =>
                  e.timestamp.year == date.year &&
                  e.timestamp.month == date.month &&
                  e.timestamp.day == date.day,
            ))
        .toList();

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
            color: sandBeige.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(23),
            boxShadow: [
              BoxShadow(
                color: zenGreen.withValues(alpha: 0.07),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: zenGreen.withValues(alpha: 0.065), width: 1.2),
          ),
          padding: EdgeInsets.symmetric(
            vertical: isMini ? 9 : 19,
            horizontal: isMini ? 7 : 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isMini ? "Zen-Woche" : "Deine Woche im Zen-Flow",
                style: const TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.bold,
                  color: zenGreen,
                  fontFamily: "ZenKalligrafie",
                  letterSpacing: 0.14,
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
                  final moodColor =
                      isEmpty ? zenGrey.withValues(alpha: 0.22) : _zenMoodColor(score).withValues(alpha: 0.93);
                  final emoji = isEmpty ? "…" : _emojiForScore(score);
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
                const Padding(
                  padding: EdgeInsets.only(top: 13.0),
                  child: Opacity(
                    opacity: 0.88,
                    child: Text(
                      "*Tippe für Details, lang halten für Zitat*",
                      style: TextStyle(
                        color: zenGreen,
                        fontSize: 12.7,
                        fontStyle: FontStyle.italic,
                        fontFamily: "SFProText",
                        letterSpacing: 0.03,
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

  static Color _zenMoodColor(int score) {
    switch (score) {
      case 0:
        return const Color(0xFFD0DFE2); // Nebelgrau
      case 1:
        return const Color(0xFFE9E4CC); // Pastell-Sand
      case 2:
        return const Color(0xFFF7EDD6); // Sanftbeige
      case 3:
        return const Color(0xFFDFF2E6); // Hellgrün
      case 4:
        return const Color(0xFFC2E5CF); // Zen-Grün
      default:
        return sandBeige;
    }
  }

  static String _emojiForScore(int score) {
    switch (score) {
      case 0:
        return "🌫️";
      case 1:
        return "🌦️";
      case 2:
        return "⛅";
      case 3:
        return "🌤️";
      case 4:
        return "🌞";
      default:
        return "…";
    }
  }

  static String _labelForScore(int? score) {
    switch (score) {
      case 0:
        return "Tief";
      case 1:
        return "Niedrig";
      case 2:
        return "Neutral";
      case 3:
        return "Klar";
      case 4:
        return "Erfüllt";
      default:
        return "Keine Angabe";
    }
  }

  static String _weekdayLabel(int i) {
    const labels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];
    return labels[i];
  }
}

// --- Einzelner Wochentag: Zen-MoodBubble, interaktiv, animiert, A11y ---
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
    );

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
        onLongPress: (widget.entry?.aiSummary == null || widget.entry!.aiSummary!.trim().isEmpty)
            ? null
            : () {
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '"${widget.entry!.aiSummary}"',
                      style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic),
                    ),
                    backgroundColor: zenGreen.withValues(alpha: 0.90),
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
                        color: zenGreen.withValues(alpha: 0.22),
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
                          color: zenGreen.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                    ],
                    border: Border.all(
                      color: widget.highlight ? zenGreen : Colors.transparent,
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: zenGreen.withValues(alpha: 0.93),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.11),
                              blurRadius: 7,
                            ),
                          ],
                        ),
                        child: Text(
                          _tooltipText(widget.entry!),
                          style: const TextStyle(
                            color: sandBeige,
                            fontSize: 12.6,
                            fontFamily: "SFProText",
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
                widget.score?.toString() ?? "",
                style: const TextStyle(
                  color: zenGreen,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: const TextStyle(
                  color: zenGreen,
                  fontSize: 13,
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
      return "Am $day.$month. – Stimmung: $label";
    }
    return "Am $day.$month. – $label · ${extra.trim()}";
  }

  String _semanticsForDay({
    required DateTime date,
    required int? score,
    required String label,
  }) {
    final d = "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.";
    final moodLabel = MoodHeatmap._labelForScore(score);
    return "$label, $d – Stimmung: $moodLabel";
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
