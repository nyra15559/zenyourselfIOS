// lib/features/therapist/therapist_dashboard.dart
//
// TherapistDashboard — Oxford Calm Edition (v2)
// ---------------------------------------------
// • Responsives, barrierearmes Layout (Semantics, große Ziele)
// • Klinisch-clean: keine Freitexte/PII im Verlauf
// • Zeitfenster: 7-Tage-Betrachtung inkl. HEUTE
// • Konsistente ZenYourself-Farben & Typo
// • Heatmap-Legende auf Zen-Palette abgestimmt

import 'package:flutter/material.dart';
import '../../shared/zen_style.dart';
import '../../data/mood_entry.dart';
import 'anon_export.dart';
import '../calendar/mood_heatmap.dart';

class TherapistDashboard extends StatelessWidget {
  final List<MoodEntry> allEntries;

  const TherapistDashboard({super.key, required this.allEntries});

  @override
  Widget build(BuildContext context) {
    // 7-Tage-Fenster inkl. heute (Start = heute 00:00 - 6 Tage)
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final last7Days = allEntries
        .where((e) => !e.timestamp.isBefore(start))
        .toList(growable: false);

    // Ø-Stimmung & letzte Stimmung (chronologisch)
    final avgMood = allEntries.isEmpty
        ? 0.0
        : allEntries.fold<int>(0, (a, e) => a + e.moodScore) / allEntries.length;

    final MoodEntry? latest = allEntries.isEmpty
        ? null
        : allEntries.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);

    // Letzte 5 (DESC)
    final lastFive = [...allEntries]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final recentFive = lastFive.take(5).toList(growable: false);

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
              ],
            ),

            const SizedBox(height: 28),

            // --- Heatmap (7 Tage) oder Empty State ---
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                          // Hinweis: MoodHeatmap nutzt die gefilterten last7Days
                          // und mappt intern Scores → Farben.
                          // Wir geben nur die Daten hinein (siehe Aufrufer unten).
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

            // --- Export (anonym) ---
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 2,
              color: ZenColors.surface,
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Mood-Journal exportieren'),
                    SizedBox(height: 8),
                    // AnonExportWidget: liefert PII-armen Export (Client-kontrolliert)
                    // → UI-Hinweis darunter.
                  ],
                ),
              ),
            ),

            // Komponente separat, damit sie Daten bekommt
            Padding(
              padding: const EdgeInsets.only(top: 0, left: 20, right: 20),
              child: AnonExportWidget(moodEntries: allEntries),
            ),
            const _TherapistHint(
              'Export ist anonym. Die Kontrolle bleibt stets bei der/dem Klient*in.',
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

class _TherapistHint extends StatelessWidget {
  final String text;
  const _TherapistHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: ZenTextStyles.caption.copyWith(
          color: ZenColors.inkSubtle,
          fontStyle: FontStyle.italic,
        ),
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
        final cols = (maxW / (cardW + 16)).floor().clamp(1, items.length);
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
    final bg = color.withValues(alpha: 0.08);
    final border = color.withValues(alpha: 0.18);

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
              backgroundColor: color.withValues(alpha: 0.12),
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
                        color: color.withValues(alpha: 0.8),
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
      {'label': 'Sehr gut',     'color': ZenColors.deepSage},
      {'label': 'Gut',          'color': ZenColors.sage},
      {'label': 'Neutral',      'color': ZenColors.goldenMist},
      {'label': 'Weniger gut',  'color': ZenColors.sunHaze},
      {'label': 'Schwach',      'color': ZenColors.inkSubtle},
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items
          .map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  CircleAvatar(radius: 6.5, backgroundColor: m['color'] as Color),
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
      label: 'Eintrag vom ${_formatDate(entry.timestamp)} mit Stimmung ${entry.moodLabel}',
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
