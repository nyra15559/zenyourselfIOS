// lib/widgets/hotline_widget.dart
// -----------------------------------------------------------------------------
// Oxford–Zen v1.5 — Schweizer Hotlines (minimal, CH-Fokus)
// - Minimalistische, barrierearme Darstellung (fokus: 144, 143)
// - Primär-Call pro Eintrag; Long-Press kopiert die Nummer (SnackBar)
// - Nutzt Launching.openTel() (lib/shared/launching.dart)
// - Design: ZenColors/Theme; kompatibel mit ZenGlassCard
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../shared/launching.dart';
import '../shared/zen_style.dart' as zs;

// Optional: Zen-Design nutzen, wenn vorhanden
// Entferne den Import, falls dein Projekt diese Widgets nicht hat.
import '../shared/ui/zen_widgets.dart' show ZenGlassCard, ZenPrimaryButton;

/// Datenmodell für eine Hotline-Zeile (intern).
class _Helpline {
  final String title;
  final String phone;    // 143 / 144 / +41 …
  final String note;     // Kurzinfo wie „24/7, anonym“
  final bool emphasized; // z. B. 144 (Notruf)

  const _Helpline({
    required this.title,
    required this.phone,
    required this.note,
    this.emphasized = false,
  });
}

// Kompakte Kernliste (minimal): 144 oben, 143 darunter
const List<_Helpline> _chHelplines = <_Helpline>[
  _Helpline(
    title: 'Sanität / Notfall',
    phone: '144',
    note: 'Akut, 24/7',
    emphasized: true,
  ),
  _Helpline(
    title: 'Dargebotene Hand',
    phone: '143',
    note: 'Anonym & vertraulich, 24/7',
  ),
];

/// Kompakte Hotline-Karte zur direkten Einbindung in Screens.
class SwissHotlineCard extends StatelessWidget {
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const SwissHotlineCard({
    super.key,
    this.maxWidth = 680,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 12),
  });

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(),
        const SizedBox(height: 8),
        for (final h in _chHelplines) ...[
          _HotlineRow(helpline: h),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        const _FooterHint(),
      ],
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ZenGlassCard(
          padding: padding,
          child: body,
        ),
      ),
    );
  }
}

/// Volle Sektion (optional, falls separat eingebunden).
class SwissHotlinesSection extends StatelessWidget {
  final double maxWidth;

  const SwissHotlinesSection({super.key, this.maxWidth = 720});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(),
            const SizedBox(height: 8),
            const SwissHotlineCard(),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: ZenPrimaryButton(
                label: 'Weitere Hilfeoptionen',
                onPressed: () => showSwissHotlinesBottomSheet(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optionales Bottom-Sheet (zeigt dieselbe kompakte Karte).
Future<void> showSwissHotlinesBottomSheet(BuildContext context) async {
  final bg = Theme.of(context).colorScheme.surface;
  await showModalBottomSheet(
    context: context,
    backgroundColor: bg,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 18),
          child: SingleChildScrollView(
            child: Column(
              children: [
                _SectionTitle(),
                SizedBox(height: 8),
                SwissHotlineCard(),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ------------------------------- UI-Teile ------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Text(
      'Hilfe in der Schweiz',
      textAlign: TextAlign.center,
      style: tt.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: zs.ZenColors.inkStrong.withValues(alpha: .95),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(Icons.health_and_safety_rounded, color: zs.ZenColors.deepSage, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Schnelle Hilfe: 144 · Gespräch: 143',
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: zs.ZenColors.inkStrong.withValues(alpha: .92),
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _HotlineRow extends StatelessWidget {
  final _Helpline helpline;
  const _HotlineRow({required this.helpline});

  void _copyWithFeedback(BuildContext context, String number) {
    Clipboard.setData(ClipboardData(text: number));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nummer kopiert: $number'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Launching.openTel(helpline.phone),
      onLongPress: () => _copyWithFeedback(context, helpline.phone),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .12),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.call_rounded, color: zs.ZenColors.deepSage, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                label:
                    '${helpline.title}, ${helpline.note}, Telefonnummer ${helpline.phone}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      helpline.title,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: zs.ZenColors.inkStrong.withValues(alpha: .95),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${helpline.note} · ${helpline.phone}',
                      style: tt.bodySmall?.copyWith(
                        color: zs.ZenColors.inkSubtle.withValues(alpha: .92),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _CallButton(phone: helpline.phone, emphasized: helpline.emphasized),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final String phone;
  final bool emphasized;
  const _CallButton({required this.phone, required this.emphasized});

  @override
  Widget build(BuildContext context) {
    final label = emphasized ? 'Soforthilfe' : 'Anrufen';
    return Semantics(
      button: true,
      label: '$label, ${emphasized ? 'Notrufnummer' : 'Telefonnummer'} $phone',
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          backgroundColor: zs.ZenColors.deepSage,
          foregroundColor: zs.ZenColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        onPressed: () => Launching.openTel(phone),
        icon: const Icon(Icons.call_rounded, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _FooterHint extends StatelessWidget {
  const _FooterHint();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Text(
      // Minimal, klar:
      'Anonyme Unterstützung: 143 · Notfall: 144',
      textAlign: TextAlign.center,
      style: tt.bodySmall?.copyWith(
        color: zs.ZenColors.inkSubtle.withValues(alpha: .92),
        height: 1.25,
      ),
    );
  }
}
