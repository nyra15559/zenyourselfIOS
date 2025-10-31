// lib/widgets/panda_mood_chip.dart
import '../shared/zen_style.dart';
//
// PandaMoodChip — A11y-first Chip (icon + label, large-text-safe, CB-friendly)
// Update: 2025-10-22
// ---------------------------------------------------------------------------
// • Kein „nur Farbe“: Bild + Label + (optional) Check-Icon bei Auswahl.
// • Semantics korrekt (button + selected).
// • Mindest-Touchhöhe 44dp, Text ellipsized.

import 'package:flutter/material.dart';
import '../models/panda_mood.dart';

class PandaMoodChip extends StatelessWidget {
  final PandaMood mood;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool showSelectedCheck; // non-color affordance

  const PandaMoodChip({
    super.key,
    required this.mood,
    this.selected = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.showSelectedCheck = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withValue(alpha: .12)
        : theme.colorScheme.surfaceContainerHighest.withValue(alpha: .45);
    final border = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValue(alpha: .6);

    return Semantics(
      button: true,
      selected: selected,
      label: mood.labelDe,
      child: Tooltip(
        message: mood.labelDe,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValue(alpha: .06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bild-Icon (kein nur-Farbe-Signal)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    mood.asset,
                    width: 22,
                    height: 22,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(Icons.emoji_emotions,
                        size: 22, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 8),
                // Label — robust gegen Large Text
                Flexible(
                  child: Text(
                    mood.labelDe,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (showSelectedCheck && selected) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                    semanticLabel: 'Ausgewählt',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
