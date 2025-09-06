// lib/widgets/panda_mood_chip.dart
import 'package:flutter/material.dart';
import '../models/panda_mood.dart';

/// PandaMoodChip — kleiner, zugänglicher Chip mit Bild + Label.
class PandaMoodChip extends StatelessWidget {
  final PandaMood mood;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const PandaMoodChip({
    super.key,
    required this.mood,
    this.selected = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withOpacity(.12)
        : theme.colorScheme.surfaceVariant.withOpacity(.45);
    final border = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withOpacity(.6);

    return Semantics(
      button: true,
      selected: selected,
      label: mood.labelDe,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  mood.asset,
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                mood.labelDe,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
