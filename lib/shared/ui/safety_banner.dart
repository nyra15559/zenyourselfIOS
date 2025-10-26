// lib/shared/ui/safety_banner.dart
//
// SafetyBanner — Oxford-Zen (CH-Disclaimer + Buttons, Risk-aware)
// -----------------------------------------------------------------------------
// • Zeigt bei RiskLevel.mild/high einen ruhigen Hinweis mit Hotlines-CTA.
// • Buttons: „Hotlines öffnen“ (Bottom-Sheet) und „144 anrufen“ (Soforthilfe).
// • Farben & Typo via ZenColors/Theme, A11y-Semantics inkl. „Heute“-neutral.
// • Verwendet showSwissHotlinesBottomSheet() aus widgets/hotline_widget.dart
//   und Launching.openTel('144') für die Notruf-Schaltfläche.
//
import 'package:flutter/material.dart';
import '../zen_style.dart' as zs;
import '../../widgets/hotline_widget.dart' show showSwissHotlinesBottomSheet;
import '../launching.dart' show Launching;

/// Lokaler, einfacher Risk-Enum (vom App-Model unabhängig halten)
enum RiskLevel { none, mild, high }

class SafetyBanner extends StatelessWidget {
  final RiskLevel level;
  final EdgeInsetsGeometry padding;

  const SafetyBanner({
    super.key,
    required this.level,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    if (level == RiskLevel.none) return const SizedBox.shrink();

    final isHigh = level == RiskLevel.high;

    final String text = isHigh
        ? 'Wenn es sich akut belastend anfühlt: Du musst da nicht alleine durch. '
            'Hier findest du Hilfe – in Notfällen wähle 144.'
        : 'Danke fürs Teilen. Wenn du magst, findest du hier anonyme Hilfe und Unterstützung.';

    // Ruhige Farben aus Theme/Zenschema
    final bg = Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: .80);
    final border = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .30);
    const iconColor = zs.ZenColors.deepSage;
    final textColor = zs.ZenColors.inkStrong.withValues(alpha: .96);

    return Semantics(
      container: true,
      label: 'Sicherheits-Hinweis',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: padding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(zs.ZenRadii.m),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.health_and_safety_rounded, size: 20, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      height: 1.28,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Primäre Aktion: Hotlines öffnen (Bottom-Sheet)
                OutlinedButton(
                  onPressed: () => showSwissHotlinesBottomSheet(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(zs.ZenRadii.m),
                    ),
                    side: BorderSide(color: iconColor.withValues(alpha: .45)),
                  ),
                  child: const Text('Hotlines öffnen'),
                ),
                // Sekundär (High Risk: Soforthilfe 144)
                if (isHigh)
                  ElevatedButton.icon(
                    onPressed: () => Launching.openTel('144'),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('144 anrufen'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      backgroundColor: iconColor,
                      foregroundColor: zs.ZenColors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(zs.ZenRadii.m),
                      ),
                      elevation: 0,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
