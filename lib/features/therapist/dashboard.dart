// lib/features/therapist/dashboard.dart
//
// TherapistDashboard — Oxford Calm Edition (v2.2 · 2025-10-22)
// -----------------------------------------------------------------
// • Responsives, barrierearmes Layout (Semantics, große Ziele).
// • Keine PII im Verlauf (nur Labels/Scores/Datum).
// • 7-Tage-Heatmap + Legende (Zen-Palette).
// • „Top-Stimmung“ (häufigstes Mood-Label) & kurzer CH-Disclaimer.
// • Export-Kachel nutzt AnonExportWidget (asynchron, redacted-metrics).

import 'package:flutter/material.dart';
import '../../shared/zen_style.dart';
import '../../data/mood_entry.dart';
import 'anon_export.dart';
import '../calendar/mood_heatmap.dart';
import '../../core/privacy/privacy_texts.dart';

class TherapistDashboard extends StatelessWidget {
  final List<MoodEntry> allEntries;

  const TherapistDashboard({super.key, required this.allEntries});

  @override
  Widget build(BuildContext context) {
    // 7-Tage-Fenster inkl. heute (Start = heute 00:00 - 6 Tage)
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final last7Days = allEntries
        .where((e) => !e.timestamp.isBefore(start))
        .toList(growable: false);

    // Ø-Stimmung & letzte Stimmung (chronologisch)
    final avgMood = allEntries.isEmpty
        ? 0.0
        : allEntries.fold<int>(0, (a, e) => a + e.moodScore) /
            allEntries.length;

    final MoodEntry? latest = allEntries.isEmpty
        ? null
        : allEntries.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);

    // Letzte 5 (DESC)
    final lastFive = [...allEntries]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final recentFive = lastFive.take(5).toList(growable: false);

    // „Top-Stimmung“ aus MoodEntry.moodLabel (robust, da immer vorhanden)
    final topLabel = _computeTopLabelFromEntries(allEntries);

    return Semantics(
      label: 'Therapeutisches Reflexions-Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TherapistHeadline('Reflexions-Dashboard'),
            const SizedBox(height: 20),

            // --- Stat-Kacheln (responsiv per Wrap) ---
            _StatsGrid(
              items: [
                _StatItem(
                  label: 'Einträge gesamt',
                  value: allEntries.length.toString(),
                  icon: Icons.library_books_rounded,
                  color: ZenColors.jade,
                ),
                _StatItem(
                  label: 'Ø Stimmung',
                  value: allEntries.isEmpty ? '—' : avgMood.toStringAsFixed(2),
                  icon: Icons.emoji_emotions_outlined,
                  color: ZenColors.bamboo,
                ),
                _StatItem(
                  label: 'Letzte Stimmung',
                  value: latest?.moodLabel ?? '—',
                  icon: Icons.insights_rounded,
                  color: latest?.moodColor ?? ZenColors.jadeMid,
                ),
                _StatItem(
                  label: 'Top-Stimmung',
                  value: topLabel ?? '—',
                  icon: Icons.local_florist_rounded,
                  color: ZenColors.deepSage,
                ),
              ],
            ),

            const SizedBox(height: 28),

            // --- Heatmap (7 Tage) oder Empty State ---
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 3,
              color: ZenColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: last7Days.isEmpty
                    ? const _EmptyState(
                        title: 'Noch keine Stimmungsdaten',
                        subtitle:
                            'Sobald Einträge vorhanden sind, erscheint hier deine 7-Tage-Heatmap.',
                        icon: Icons.calendar_month_outlined,
                      )
                    : const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionTitle('Mood Heatmap (7 Tage)'),
                          SizedBox(height: 14),
                        ],
                      ),
              ),
            ),

            // (Heatmap separat, damit Semantics sauber bleibt)
            if (last7Days.isNotEmpty) ...[
              const SizedBox(height: 6),
              MoodHeatmap(moodEntries: last7Days),
              const SizedBox(height: 10),
              const _HeatmapLegend(),
            ],

            const SizedBox(height: 28),

            // --- Export (anonym, asynchron, redacted-metrics) ---
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 2,
              color: ZenColors.surface,
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Mood-Journal exportieren'),
                    SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // Komponente separat, damit sie Daten bekommt
            Padding(
              padding: const EdgeInsets.only(top: 0, left: 20, right: 20),
              child: AnonExportWidget(moodEntries: allEntries),
            ),
            const SizedBox(height: 8),
            Text(
              PrivacyTexts.chDisclaimerShort,
              style: ZenTextStyles.caption.copyWith(color: ZenColors.inkSubtle),
            ),

            const SizedBox(height: 28),

            // --- Letzte Einträge (PII-frei) ---
            const _SectionTitle('Letzte 5 Einträge'),
            const SizedBox(height: 12),
            if (recentFive.isEmpty)
              const _EmptyState(
                title: 'Noch keine Einträge',
                subtitle:
                    'Sobald Reflexionen erfasst wurden, erscheinen sie hier in zeitlicher Reihenfolge.',
                icon: Icons.menu_book_outlined,
              )
            else
              ...recentFive.map((e) => _MoodEntryTile(entry: e)),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Häufigstes Mood-Label (robust ohne Tags/Faces-Felder).
  String? _computeTopLabelFromEntries(List<MoodEntry> entries) {
    final Map<String, int> counts = {};
    for (final e in entries) {
      final s = (e.moodLabel).trim();
      if (s.isEmpty) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    String? label;
    int max = 0;
    counts.forEach((k, v) {
      if (v > max) {
        max = v;
        label = k;
      }
    });
    return label;
  }
}

/// Überschriften & Infotexte
class _TherapistHeadline extends StatelessWidget {
  final String text;
  const _TherapistHeadline(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ZenTextStyles.h2.copyWith(
        fontSize: 26,
        color: ZenColors.inkStrong,
        letterSpacing: 0.15,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ZenTextStyles.title.copyWith(
        fontSize: 18,
        color: ZenColors.jade,
        letterSpacing: 0.02,
      ),
    );
  }
}

/// Responsives Grid für Stat-Karten
class _StatsGrid extends StatelessWidget {
  final List<_StatItem> items;
  const _StatsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final maxW = c.maxWidth;
        const cardW = 180.0;

        // Stabil ohne num.clamp()-Typing-Fallen
        final rawCols = (maxW / (cardW + 16)).floor();
        final int cols =
            rawCols < 1 ? 1 : (rawCols > items.length ? items.length : rawCols);

        final effectiveW = (maxW - (16 * (cols - 1))) / cols;

        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: items
              .map((it) => SizedBox(
                    width: effectiveW,
                    child: _StatCard(
                      label: it.label,
                      value: it.value,
                      icon: it.icon,
                      color: it.color,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

/// Stat-Kachel, ruhig & klar
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color.withValue(alpha: 0.08);
    final border = color.withValue(alpha: 0.18);

    return Semantics(
      label: '$label: $value',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValue(alpha: 0.12),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: ZenTextStyles.h3.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 2),
                  Text(label,
                      style: ZenTextStyles.caption.copyWith(
                        color: color.withValue(alpha: 0.8),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Heatmap-Legende (Zen-Palette)
class _HeatmapLegend extends StatelessWidget {
  const _HeatmapLegend();

  @override
  Widget build(BuildContext context) {
    final items = [
      {'label': 'Sehr gut', 'color': ZenColors.deepSage},
      {'label': 'Gut', 'color': ZenColors.sage},
      {'label': 'Neutral', 'color': ZenColors.goldenMist},
      {'label': 'Weniger gut', 'color': ZenColors.sunHaze},
      {'label': 'Schwach', 'color': ZenColors.inkSubtle},
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items
          .map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  CircleAvatar(
                      radius: 6.5, backgroundColor: m['color'] as Color),
                  const SizedBox(width: 6),
                  Text(m['label'] as String, style: ZenTextStyles.caption),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Ein MoodEntry als Verlaufskachel (PII-frei)
class _MoodEntryTile extends StatelessWidget {
  final MoodEntry entry;
  const _MoodEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final badgeFg = entry.moodScore >= 3 ? Colors.white : Colors.black87;

    return Semantics(
      label:
          'Eintrag vom ${_formatDate(entry.timestamp)} mit Stimmung ${entry.moodLabel}',
      child: Card(
        elevation: 1.5,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: entry.moodColor,
            child: Text(
              entry.moodScore.toString(),
              style: TextStyle(
                color: badgeFg,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          title: Text(
            entry.moodLabel,
            style: ZenTextStyles.title.copyWith(fontSize: 16),
          ),
          // PII-sicher: keine Freitexte/Notizen anzeigen
          subtitle: Text(
            _formatDate(entry.timestamp),
            style: ZenTextStyles.caption.copyWith(color: ZenColors.inkSubtle),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}

/// Freundlicher leerer Zustand
class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $subtitle',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: ZenColors.jadeMid),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: ZenTextStyles.title.copyWith(
                        color: ZenColors.jadeMid,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: ZenTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
