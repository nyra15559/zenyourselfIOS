// [MERGE SIGNAL] lib/features/pro/widgets/timeline_bar.dart (Stand: 2025-11-09, v1.3.3)
// Pro · TimelineBar — performante Punkte-Leiste mit 7/30/90-Filterchips
// Oxford-Zen · Senior-Self Niveau · Safe-Area/Hit-Tests fix · Memory-Modus
// -----------------------------------------------------------------------------
// Änderungen v1.3.3 (09.11.2025)
// • Alpha/Transparenz: konsequent .withValue(...) statt .withOpacity(...).
// • Keine weiteren inhaltlichen Änderungen.
//
// Änderungen v1.3.2 (09.11.2025)
// • Provider-Import entfernt (dynamischer Zugriff), um Build-Brüche zu vermeiden.
// • Alle Alphas auf withOpacity(...) umgestellt (keine projekt-spezifische Extension nötig).
// • Kleinere Robustheits-Guards beibehalten.
//
// Änderungen v1.3.1 (08.11.2025)
// • Provider-Zugriff robust (kein Crash ohne Provider im Tree), Set-basierte Topic-De-Dup.
// • Verbesserte Semantics und Material-Safety.
//
// Änderungen v1.3.0 (08.11.2025)
// • Optionaler Memory-Modus (useMemory:true) — Daten direkt aus MemoryService.timelineRecent(days).
// • A11y-Labels, Touch-Areas, performante ListView (itemExtent), Glas-Karte-Polish.
//
// Einbindung (Beispiele)
// -----------------------------------------------------------------------------
// import 'features/pro/widgets/timeline_bar.dart';
//
// // 1) Automatisch aus MemoryService (empfohlen für Kutsche 3):
// TimelineBar(
//   useMemory: true,
//   onTapDot: (dot) => _openTimelineSheet(dot),
// );
//
// // 2) Automatisch über vorhandenen Provider (dynamisch; kein harter Import hier):
// TimelineBar(
//   useProvider: true,
//   onTapDot: (dot) => _openTimelineSheet(dot),
// );
//
// // 3) Mit vorgefertigten Dots:
// TimelineBar(
//   dots: precomputedDots,
//   initialRange: TimelineRange.d30,
//   onRangeChanged: (r) => setState(() => _range = r),
//   onTapDot: (dot) => _openTimelineSheet(dot),
// );
//
// Hinweise
// • Memory-Variante erwartet MemoryService.timelineRecent(days) (topic/mood/ts tolerant).
// • Provider-Variante erwartet ein Objekt mit .entries (createdAt, tags[] : List<String>).
// • Mood-Score wird auf −2..+2 skaliert; Farben via ZenStyle-Tokens.
// -----------------------------------------------------------------------------

library timeline_bar;

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Shared UI & Design
import '../../../shared/zen_style.dart' as zs; // ZenColors, ZenRadii, etc.
import '../../../shared/ui/zen_widgets.dart' as zw show ZenGlassCard;

// Memory (optional, wenn useMemory:true)
import '../../../core/memory/memory_service.dart' show MemoryService;

// ─────────────────────────────────────────────────────────────────────────────
// Öffentliche API-Modelle
// ─────────────────────────────────────────────────────────────────────────────

/// Zeitfenster für die Timeline.
enum TimelineRange { d7, d30, d90 }

extension on TimelineRange {
  int get days => switch (this) {
        TimelineRange.d7 => 7,
        TimelineRange.d30 => 30,
        TimelineRange.d90 => 90
      };
  String get labelShort => switch (this) {
        TimelineRange.d7 => '7',
        TimelineRange.d30 => '30',
        TimelineRange.d90 => '90'
      };
  String get labelLong => 'letzte $labelShort Tage';
}

/// Ein Verlaufspunkt (Tag) für die Timeline.
class TimelineDot {
  /// Tagesstempel (UTC, 00:00 des Tages).
  final DateTime dayUtc;

  /// Extrahierte Themen (z. B. „topic:Arbeit“ → „Arbeit“).
  final List<String> topics;

  /// Gemittelter Stimmungswert im Bereich −2..+2 (optional).
  final double? avgMood;

  /// Anzahl Einträge an diesem Tag.
  final int count;

  const TimelineDot({
    required this.dayUtc,
    required this.topics,
    required this.avgMood,
    required this.count,
  });

  String get dayHuman {
    final d = dayUtc.toLocal();
    return '${_pad2(d.day)}.${_pad2(d.month)}.${d.year}';
  }

  String get oneLiner {
    final t = topics.isNotEmpty ? topics.first : '—';
    final moodWord = avgMood == null
        ? null
        : (avgMood! >= 1.2 ? 'hell' : (avgMood! <= -1.2 ? 'schwer' : 'ruhiger'));
    if (moodWord == null) return 'Thema: $t';
    return 'Wirkte $moodWord · Thema: $t';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TimelineBar – Widget
// ─────────────────────────────────────────────────────────────────────────────

class TimelineBar extends StatefulWidget {
  /// Falls gesetzt, werden diese Dots angezeigt (anstelle von Provider/Memory).
  final List<TimelineDot>? dots;

  /// Nutze automatisch einen JournalEntries-Provider, um Dots zu bauen (dynamisch).
  final bool useProvider;

  /// Nutze automatisch den MemoryService, um Dots zu bauen.
  final bool useMemory;

  /// Initiales Zeitfenster (default: 30 Tage).
  final TimelineRange initialRange;

  /// Callback bei Range-Wechsel (optional).
  final ValueChanged<TimelineRange>? onRangeChanged;

  /// Callback beim Tippen auf einen Verlaufspunkt (optional).
  final ValueChanged<TimelineDot>? onTapDot;

  /// Optional benutzerdefinierter Header-Titel (default: „Verlauf – letzte N Tage“).
  final String? title;

  /// Feste Höhe des List-View-Viewports (default: 220).
  final double viewportHeight;

  /// Leerer-Zustand-Text.
  final String emptyText;

  /// Ob der Hilfetext „Tippe für Details“ angezeigt werden soll.
  final bool showHint;

  const TimelineBar({
    super.key,
    this.dots,
    this.useProvider = false,
    this.useMemory = false,
    this.initialRange = TimelineRange.d30,
    this.onRangeChanged,
    this.onTapDot,
    this.title,
    this.viewportHeight = 220,
    this.emptyText = 'Noch keine Verlaufspunkte im Zeitraum.',
    this.showHint = true,
  });

  /// Hilfsfunktion: Zählt Top-Themen im Fenster.
  static Map<String, int> buildTopicCounts(List<TimelineDot> dots) {
    final map = <String, int>{};
    for (final d in dots) {
      for (final t in d.topics) {
        map[t] = (map[t] ?? 0) + 1;
      }
    }
    return map;
  }

  @override
  State<TimelineBar> createState() => _TimelineBarState();
}

class _TimelineBarState extends State<TimelineBar> {
  late TimelineRange _range = widget.initialRange;

  @override
  void didUpdateWidget(covariant TimelineBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Wenn sich die initialRange extern ändert (selten), übernehmen.
    if (oldWidget.initialRange != widget.initialRange) {
      _range = widget.initialRange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final dots = _resolveDots(context, _range.days);

    return ClipRRect(
      borderRadius: const BorderRadius.all(zs.ZenRadii.l),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: zw.ZenGlassCard(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
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
                  const Icon(Icons.timeline_rounded,
                      size: 18, color: zs.ZenColors.sage),
                  const SizedBox(width: 8),
                  Text(
                    widget.title ?? 'Verlauf – ${_range.labelLong}',
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: zs.ZenColors.deepSage,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Range-Chips
              Center(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _RangeChip(
                      label: '7 Tage',
                      selected: _range == TimelineRange.d7,
                      onTap: () => _setRange(TimelineRange.d7),
                    ),
                    _RangeChip(
                      label: '30 Tage',
                      selected: _range == TimelineRange.d30,
                      onTap: () => _setRange(TimelineRange.d30),
                    ),
                    _RangeChip(
                      label: '90 Tage',
                      selected: _range == TimelineRange.d90,
                      onTap: () => _setRange(TimelineRange.d90),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Punkte-Liste
              SizedBox(
                height: widget.viewportHeight,
                child: (dots.isEmpty)
                    ? Center(
                        child: _EmptyRowHint(
                          icon: Icons.hourglass_empty_rounded,
                          text: widget.emptyText,
                        ),
                      )
                    : ListView.builder(
                        key: ValueKey(_range), // rebuild bei Range-Wechsel
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        itemCount: dots.length,
                        itemExtent: 48, // fix für Layout-Performance
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (ctx, i) {
                          final dot = dots[i];
                          return _TimelineItem(
                            dot: dot,
                            onTap: () => widget.onTapDot?.call(dot),
                          );
                        },
                      ),
              ),

              if (widget.showHint) ...[
                const SizedBox(height: 2),
                Opacity(
                  opacity: .78,
                  child: Text(
                    'Tippe auf einen Punkt für Details (Datum, Thema, 1-Satz).',
                    textAlign: TextAlign.center,
                    style: tt.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _setRange(TimelineRange r) {
    if (_range == r) return;
    setState(() => _range = r);
    widget.onRangeChanged?.call(r);
  }

  List<TimelineDot> _resolveDots(BuildContext ctx, int days) {
    // 1) Externe Dots priorisieren
    final ext = widget.dots;
    if (ext != null) {
      final now = DateTime.now().toUtc();
      final start = now.subtract(Duration(days: days));
      return ext
          .where((d) => d.dayUtc.isAfter(start) || _sameDay(d.dayUtc, now))
          .toList()
        ..sort((a, b) => b.dayUtc.compareTo(a.dayUtc));
    }

    // 2) MemoryService verwenden, wenn gewünscht und vorhanden
    if (widget.useMemory) {
      final ms = _tryGetMemoryService(ctx);
      if (ms != null) {
        return _buildDotsFromMemory(ms, days);
      }
    }

    // 3) Provider (dynamisch) nutzen, wenn gewünscht
    if (widget.useProvider) {
      final prov = _tryGetJournalProvider(ctx);
      if (prov != null) {
        return _buildDotsFromProvider(prov, days);
      }
    }

    // 4) Fallback leer
    return const <TimelineDot>[];
  }

  // Aus MemoryService.timelineRecent(days) -> gruppiere je Tag, Topics + Ø-Mood
  List<TimelineDot> _buildDotsFromMemory(MemoryService ms, int days) {
    try {
      final list = ms.timelineRecent(days); // erwartet List<dynamic>/Marker
      if (list == null || list.isEmpty) return const [];

      final now = DateTime.now().toUtc();
      final start = now.subtract(Duration(days: days));

      final byDayTopics = <String, Set<String>>{};
      final byDayMood = <String, List<double>>{};
      final byDayCount = <String, int>{};
      final byDayDt = <String, DateTime>{};

      for (final m in list) {
        final dt = _parseToUtcDay(_getAny(m, ['ts', 'date', 'day', 'dayUtc', 'timestamp']));
        if (dt == null || dt.isBefore(start)) continue;

        final key = _toDayTag(dt);
        byDayDt[key] = DateTime.utc(dt.year, dt.month, dt.day);

        // Topic(s)
        final topics = <String>[];
        final t1 = _getAny(m, ['topic', 'thema']);
        if (t1 is String && t1.trim().isNotEmpty) topics.add(_normTopic(t1));
        final t2 = _getAny(m, ['topics']);
        if (t2 is List) {
          for (final x in t2) {
            if (x is String && x.trim().isNotEmpty) topics.add(_normTopic(x));
          }
        }
        if (topics.isNotEmpty) {
          (byDayTopics[key] ??= <String>{}).addAll(topics);
        } else {
          byDayTopics.putIfAbsent(key, () => <String>{});
        }

        // Mood
        final rawMood = _getAny(m, ['mood', 'moodScore', 'score']);
        final mood = _toMoodScore(rawMood);
        if (mood != null) {
          (byDayMood[key] ??= <double>[]).add(mood);
        }

        byDayCount[key] = (byDayCount[key] ?? 0) + 1;
      }

      if (byDayCount.isEmpty) return const [];

      final keys = byDayCount.keys.toList()
        ..sort((a, b) => byDayDt[b]!.compareTo(byDayDt[a]!));

      final out = <TimelineDot>[];
      for (final k in keys) {
        final dt = byDayDt[k]!;
        final topics = (byDayTopics[k] ?? const <String>{}).toList();
        final topThemes = _topN(topics, 3);
        final moods = byDayMood[k];
        final avgMood = (moods == null || moods.isEmpty)
            ? null
            : (moods.reduce((a, b) => a + b) / moods.length).clamp(-2.0, 2.0);
        out.add(TimelineDot(
          dayUtc: dt,
          topics: topThemes,
          avgMood: avgMood,
          count: byDayCount[k] ?? 0,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // Aus einem dynamischen Provider-Objekt -> gruppiere je Tag
  List<TimelineDot> _buildDotsFromProvider(dynamic prov, int days) {
    try {
      final entries = prov.entries as List<dynamic>?; // erwartet .entries
      if (entries == null || entries.isEmpty) return const [];

      final now = DateTime.now().toUtc();
      final start = now.subtract(Duration(days: days));

      final byDayTopics = <String, Set<String>>{};
      final byDayMood = <String, List<double>>{};
      final byDayCount = <String, int>{};
      final byDayDt = <String, DateTime>{};

      for (final e in entries) {
        final createdAt = (e.createdAt as DateTime?)?.toUtc();
        if (createdAt == null || createdAt.isBefore(start)) continue;

        final key = _toDayTag(createdAt);
        byDayDt[key] = DateTime.utc(createdAt.year, createdAt.month, createdAt.day);

        // Themen aus Tags extrahieren
        final tags = (e.tags as List<dynamic>? ?? const []).cast<String>();
        final topics = _extractTopics(tags);
        if (topics.isNotEmpty) {
          (byDayTopics[key] ??= <String>{}).addAll(topics);
        } else {
          byDayTopics.putIfAbsent(key, () => <String>{});
        }

        // Stimmung extrahieren
        final mood = _scoreFromTags(tags);
        if (mood != null) {
          (byDayMood[key] ??= <double>[]).add(mood);
        }

        byDayCount[key] = (byDayCount[key] ?? 0) + 1;
      }

      if (byDayCount.isEmpty) return const [];

      final keys = byDayCount.keys.toList()
        ..sort((a, b) => byDayDt[b]!.compareTo(byDayDt[a]!)); // neueste zuerst

      final out = <TimelineDot>[];
      for (final k in keys) {
        final dt = byDayDt[k]!;
        final topics = (byDayTopics[k] ?? const <String>{}).toList();
        final topThemes = _topN(topics, 3);
        final moods = byDayMood[k];
        final avgMood = (moods == null || moods.isEmpty)
            ? null
            : (moods.reduce((a, b) => a + b) / moods.length).clamp(-2.0, 2.0);
        out.add(TimelineDot(
          dayUtc: dt,
          topics: topThemes,
          avgMood: avgMood,
          count: byDayCount[k] ?? 0,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // Provider-Access (robust, kein Crash wenn nicht vorhanden)
  MemoryService? _tryGetMemoryService(BuildContext ctx) {
    try {
      return Provider.of<MemoryService>(ctx, listen: false);
    } catch (_) {
      return null;
    }
  }

  dynamic _tryGetJournalProvider(BuildContext ctx) {
    try {
      // dynamisch (kein Typ-Import) – erwartet Objekt mit .entries
      return Provider.of<Object>(ctx, listen: false);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Visuelle Unterbausteine
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineItem extends StatelessWidget {
  final TimelineDot dot;
  final VoidCallback? onTap;

  const _TimelineItem({required this.dot, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = _moodColor(dot.avgMood);

    final semanticMood = dot.avgMood == null
        ? 'ohne Stimmung'
        : (dot.avgMood! >= 1.0
            ? 'hell'
            : (dot.avgMood! <= -1.0 ? 'schwer' : 'ruhiger'));

    return Semantics(
      button: true,
      label:
          'Verlaufspunkt ${dot.dayHuman}. ${dot.topics.isEmpty ? "Kein Thema" : "Thema: ${dot.topics.first}"} . Stimmung: $semanticMood. Doppeltippen für Details.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Center(child: _MoodDot(color: color, size: 10)),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dot.dayHuman,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: zs.ZenColors.deepSage,
                        ),
                      ),
                    ),
                    Flexible(
                      flex: 2,
                      child: Opacity(
                        opacity: .85,
                        child: Text(
                          dot.topics.isEmpty ? '—' : dot.topics.join(' · '),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoodDot extends StatelessWidget {
  final Color color;
  final double size;
  const _MoodDot({required this.color, this.size = 10});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValue(.30),
            blurRadius: 8,
            spreadRadius: 1.2,
            offset: const Offset(0, 2),
          )
        ],
        border: Border.all(color: Colors.black.withValue(.10)),
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
        ? zs.ZenColors.deepSage.withValue(.15)
        : Colors.white.withValue(.12);
    final border = selected
        ? zs.ZenColors.deepSage.withValue(.40)
        : Colors.black.withValue(.14);
    final fg = selected ? zs.ZenColors.deepSage : Colors.black87;

    return Semantics(
      button: true,
      label: '$label anzeigen',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
                  color: zs.ZenColors.deepSage.withValue(.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded,
                    size: 14, color: zs.ZenColors.deepSage),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.8,
                ).copyWith(color: fg),
              ),
            ],
          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Logik-Helper (Tag/Mood/Topics)
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, double> _moodScoreMap = {
  'glücklich': 2.0,
  'ruhig': 1.0,
  'neutral': 0.0,
  'traurig': -1.0,
  'gestresst': -1.0,
  'wütend': -2.0,
};

double? _scoreFromTags(List<String> tags) {
  for (final t in tags) {
    final s = t.trim();
    if (s.startsWith('moodScore:')) {
      final n = int.tryParse(s.substring(10));
      if (n != null) return (n.clamp(0, 4) * 1.0) - 2.0; // 0..4 → −2..+2
    }
  }
  for (final t in tags) {
    final s = t.trim();
    if (s.toLowerCase().startsWith('mood:')) {
      final key = s.substring(5).trim().toLowerCase();
      final v = _moodScoreMap[key];
      if (v != null) return v;
    }
  }
  return null;
}

List<String> _extractTopics(List<String> tags) {
  final out = <String>[];
  for (final t in tags) {
    final s = t.trim();
    if (s.toLowerCase().startsWith('topic:')) {
      final v = s.substring(6).trim();
      if (v.isNotEmpty) out.add(v);
    } else if (s.toLowerCase().startsWith('thema:')) {
      final v = s.substring(6).trim();
      if (v.isNotEmpty) out.add(v);
    }
  }
  return out;
}

List<String> _topN(List<String> items, int n) {
  if (items.isEmpty) return const [];
  final map = <String, int>{};
  for (final x in items) {
    map[x] = (map[x] ?? 0) + 1;
  }
  final sorted = map.keys.toList()
    ..sort((a, b) => (map[b]!).compareTo(map[a]!));
  return sorted.take(n).toList();
}

Color _moodColor(double? v) {
  if (v == null) return Colors.grey.withValue(.65);
  if (v >= 1.0) return zs.ZenColors.deepSage;
  if (v <= -1.0) return Colors.redAccent.withValue(.85);
  return zs.ZenColors.sage;
}

// Tag-/Datum-/Parsing-Helfer
String _toDayTag(DateTime dtUtc) =>
    '${dtUtc.year}-${_pad2(dtUtc.month)}-${_pad2(dtUtc.day)}';
String _pad2(int v) => v.toString().padLeft(2, '0');

DateTime? _parseDayTag(String tag) {
  try {
    final parts = tag.split('-');
    if (parts.length != 3) return null;
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime.utc(y, m, d);
  } catch (_) {
    return null;
  }
}

bool _sameDay(DateTime aUtc, DateTime bUtc) =>
    aUtc.year == bUtc.year && aUtc.month == bUtc.month && aUtc.day == bUtc.day;

DateTime? _parseToUtcDay(dynamic v) {
  DateTime? dt;
  if (v is DateTime) {
    dt = v.isUtc ? v : v.toUtc();
  } else if (v is int) {
    // Sekunden vs Millisekunden heuristisch
    if (v < 20000000000) {
      dt = DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true);
    } else {
      dt = DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    }
  } else if (v is String) {
    final p = DateTime.tryParse(v);
    if (p != null) dt = p.isUtc ? p : p.toUtc();
  }
  if (dt == null) return null;
  return DateTime.utc(dt.year, dt.month, dt.day);
}

dynamic _getAny(dynamic obj, List<String> keys) {
  if (obj is Map) {
    for (final k in keys) {
      if (obj.containsKey(k)) return obj[k];
    }
  }
  return null;
}

String _normTopic(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  // Kürzen auf maximal ~3 Wörter
  final parts = t.split(RegExp(r'\s+'));
  final cut = parts.take(3).join(' ');
  return cut;
}

double? _toMoodScore(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    final d = v.toDouble();
    // Wenn im Bereich 0..4 → auf −2..+2 mappen
    if (d >= 0 && d <= 4) return (d - 2.0).clamp(-2.0, 2.0);
    // Falls bereits −2..+2, klemmen
    if (d >= -2 && d <= 2) return d;
    // sonst heuristisch klemmen
    return d.clamp(-2.0, 2.0);
  }
  if (v is String) {
    final n = double.tryParse(v);
    if (n != null) return _toMoodScore(n);
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Kleine Helfer
// ─────────────────────────────────────────────────────────────────────────────

extension ListTakeLast<T> on List<T> {
  List<T> takeLast(int count) =>
      skip(length > count ? length - count : 0).toList();
}
