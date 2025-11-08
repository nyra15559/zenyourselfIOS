// [BASELINE] lib/features/pro/widgets/insights_list.dart (Stand: 2025-11-07, v1.0.0)
// Pro → Widgets — InsightsList (kompakt)
// -----------------------------------------------------------------------------
// Zweck
// • Kompakte Kartenliste für Einsichten (Insight-Notizen) mit Zeitstempel & Tag-Chips.
// • Ruhiger Oxford-Zen-Stil, dezent (kein Coaching-Ton), gut lesbar, a11y-freundlich.
// • Designed für Einbettung in bestehende Scroll-Container (shrinkWrap + no scroll).
//
// API
//   class InsightItem {
//     final String id;
//     final DateTime createdAt;
//     final String text;
//     final List<String> tags; // frei; typische Präfixe: topic:/thema:/mood:/insight:
//   }
//
//   InsightsListView(
//     items: <InsightItem>[],
//     onTapItem: (item) { ... }?,
//     onTapTag: (tag) { ... }?,
//     maxItems: 6,             // optional begrenzen
//     dense: true,             // reduzierte Abstände
//     showDivider: true,       // feine Trennlinie zwischen Karten
//   )
//
// Stil
// • ZenGlassCard mit leichter Unschärfe.
// • Zeitstempel rechts oben, Fließtext max. 3 Zeilen, darunter Tag-Chips (Wrap).
// • Farben: ZenColors deepSage/sage; Chips mit sanfter Kontur.
//
// Abhängigkeiten: zen_style.dart, zen_widgets.dart (ZenGlassCard)
// -----------------------------------------------------------------------------

library insights_list;

import 'dart:ui';
import 'package:flutter/material.dart';

// Pfade relativ zu /lib/features/pro/widgets/
import '../../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../../shared/ui/zen_widgets.dart' as zw show ZenGlassCard;

/// Datenmodell für eine kompakte Einsichtskarte.
class InsightItem {
  final String id;
  final DateTime createdAt;
  final String text;
  final List<String> tags;

  const InsightItem({
    required this.id,
    required this.createdAt,
    required this.text,
    this.tags = const <String>[],
  });
}

/// Kompakte Liste von Einsichten – integriert sich in übergeordnete ScrollViews.
class InsightsListView extends StatelessWidget {
  final List<InsightItem> items;
  final ValueChanged<InsightItem>? onTapItem;
  final ValueChanged<String>? onTapTag;

  /// Begrenze die Anzahl der dargestellten Items (null = alle).
  final int? maxItems;

  /// Dichterer Look (kleinere Abstände).
  final bool dense;

  /// Feine Trennlinien zwischen Karten.
  final bool showDivider;

  const InsightsListView({
    super.key,
    required this.items,
    this.onTapItem,
    this.onTapTag,
    this.maxItems,
    this.dense = true,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final list = (maxItems != null && maxItems! > 0)
        ? items.take(maxItems!).toList()
        : items;

    if (list.isEmpty) {
      return _EmptyHint(dense: dense);
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          showDivider ? const _HairlineDivider() : const SizedBox(height: 6),
      itemBuilder: (ctx, i) {
        final item = list[i];
        return _InsightCard(
          item: item,
          dense: dense,
          onTap: onTapItem == null ? null : () => onTapItem!(item),
          onTapTag: onTapTag,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Einzelkarte
// ─────────────────────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final InsightItem item;
  final bool dense;
  final VoidCallback? onTap;
  final ValueChanged<String>? onTapTag;

  const _InsightCard({
    required this.item,
    required this.dense,
    this.onTap,
    this.onTapTag,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final ts = _formatTimestamp(item.createdAt);

    final content = ClipRRect(
      borderRadius: const BorderRadius.all(zs.ZenRadii.m),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: zw.ZenGlassCard(
          padding: EdgeInsets.fromLTRB(12, dense ? 10 : 12, 12, dense ? 10 : 12),
          topOpacity: .16,
          bottomOpacity: .08,
          borderOpacity: .12,
          borderRadius: const BorderRadius.all(zs.ZenRadii.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kopfzeile: Icon + Zeitstempel rechts
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.lightbulb_rounded,
                      size: 18, color: zs.ZenColors.sage),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Opacity(
                      opacity: .85,
                      child: Text(
                        'Einsicht',
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: zs.ZenColors.deepSage,
                          letterSpacing: .1,
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: .78,
                    child: Text(
                      ts,
                      style: tt.bodySmall?.copyWith(
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: dense ? 8 : 10),

              // Text (max. 3 Zeilen)
              Text(
                item.text.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(
                  height: 1.28,
                  color: Colors.black.withOpacity(.90),
                ),
              ),

              if (item.tags.isNotEmpty) ...[
                SizedBox(height: dense ? 8 : 10),
                _TagWrap(
                  tags: item.tags,
                  onTap: onTapTag,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // A11y / Semantics
    final semanticsLabel = StringBuffer()
      ..write('Einsicht vom ${_formatDateOnly(item.createdAt)}. ')
      ..write(item.text.length > 60
          ? '${item.text.substring(0, 60)}… '
          : '${item.text} ')
      ..write(item.tags.isNotEmpty
          ? 'Tags: ${_tagsForSemantics(item.tags)}.'
          : '');

    // Optional tappable
    return Semantics(
      button: onTap != null,
      label: semanticsLabel.toString(),
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: content,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tag-Chips
// ─────────────────────────────────────────────────────────────────────────────

class _TagWrap extends StatelessWidget {
  final List<String> tags;
  final ValueChanged<String>? onTap;

  const _TagWrap({required this.tags, this.onTap});

  @override
  Widget build(BuildContext context) {
    final clean = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map(_stripKnownPrefixes)
        .toList();

    if (clean.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: clean.map((t) => _TagChip(text: t, onTap: onTap)).toList(),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  final ValueChanged<String>? onTap;

  const _TagChip({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = Colors.white.withOpacity(.10);
    final border = Colors.black.withOpacity(.12);
    final fg = zs.ZenColors.deepSage;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sell_rounded, size: 13, color: zs.ZenColors.sage),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w700,
              color: zs.ZenColors.deepSage,
              letterSpacing: .1,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;

    return Semantics(
      button: true,
      label: 'Tag $text. Doppeltippen zum Filtern.',
      child: GestureDetector(
        onTap: () => onTap!(text),
        child: Tooltip(
          message: 'Filtern nach „$text“',
          child: chip,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helfer & Deko
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final bool dense;
  const _EmptyHint({required this.dense});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 6 : 8),
      child: Opacity(
        opacity: .85,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty_rounded,
                size: 16, color: Colors.black54),
            const SizedBox(width: 6),
            Text('Noch keine Einsichten im Zeitraum.', style: tt.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _HairlineDivider extends StatelessWidget {
  const _HairlineDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8, // visueller Air-Space + feine Linie
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: zs.ZenColors.sage.withOpacity(.18),
      ),
    );
  }
}

// Entfernt Präfixe wie "topic:", "thema:", "mood:", "insight:".
String _stripKnownPrefixes(String raw) {
  final s = raw.trim();
  final lower = s.toLowerCase();
  for (final p in const ['topic:', 'thema:', 'mood:', 'insight:', 'tag:']) {
    if (lower.startsWith(p)) {
      return s.substring(p.length).trim();
    }
  }
  return s;
}

String _tagsForSemantics(List<String> tags) =>
    tags.map(_stripKnownPrefixes).where((t) => t.isNotEmpty).join(', ');

// Zeitformatierungen (leicht, DE-nah)
String _formatTimestamp(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final isToday = _isSameDay(local, now);
  final isYesterday = _isSameDay(
      local, DateTime(now.year, now.month, now.day - 1));

  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (isToday) return 'heute $hh:$mm';
  if (isYesterday) return 'gestern $hh:$mm';
  return '${_pad2(local.day)}.${_pad2(local.month)}.${local.year}  $hh:$mm';
}

String _formatDateOnly(DateTime dt) {
  final l = dt.toLocal();
  return '${_pad2(l.day)}.${_pad2(l.month)}.${l.year}';
}

String _pad2(int v) => v.toString().padLeft(2, '0');

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
