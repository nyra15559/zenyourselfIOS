// lib/widgets/hotline_widget.dart
// -----------------------------------------------------------------------------
// Oxford–Zen v1.2 — Schweizer Hotlines (kompakt, 2 Kernnummern)
// - Klare, barrierearme Darstellung der wichtigsten CH-Hotlines
// - Primär-Call-Button je Eintrag; Long-Press kopiert die Nummer
// - Nutzt Launching.openTel() (lib/shared/launching.dart)
// - Design: ruhig, kompakt; kompatibel mit ZenGlassCard (falls vorhanden)
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../shared/launching.dart';

// Optional: Zen-Design nutzen, wenn vorhanden
// Entferne den Import, falls du kein ZenGlassCard-/ZenPrimaryButton-Widget hast.
import '../shared/ui/zen_widgets.dart' show ZenGlassCard, ZenPrimaryButton;

/// Datenmodell für eine Hotline-Zeile.
class _Helpline {
  final String title;
  final String phone;   // 143 / 144 / +41 …
  final String note;    // Kurzinfo wie "24/7, anonym"
  final bool emphasized; // z. B. 144 (Notruf)

  const _Helpline({
    required this.title,
    required this.phone,
    required this.note,
    this.emphasized = false,
  });
}

// Kompakte Kernliste: nur 143 (Gespräch) und 144 (Notruf)
const List<_Helpline> _chHelplines = [
  _Helpline(
    title: 'Dargebotene Hand',
    phone: '143',
    note: '24/7, anonym & vertraulich',
  ),
  _Helpline(
    title: 'Sanität / Notfall',
    phone: '144',
    note: 'Akute Notfälle, 24/7',
    emphasized: true,
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
        const SizedBox(height: 10),
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

/// Stellt die Hotlines als volle Sektion mit Titel + Call-to-Action dar.
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
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          child: SingleChildScrollView(
            child: Column(
              children: const [
                _SheetHandle(),
                SizedBox(height: 8),
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

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.12),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Text(
      'Wenn es sich akut belastend anfühlt',
      textAlign: TextAlign.center,
      style: tt.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: Colors.black.withOpacity(.85),
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
        const Icon(Icons.health_and_safety_rounded, color: Colors.orange, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Schweizer Hotlines — diskret & 24/7 erreichbar',
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.black.withOpacity(.85),
              height: 1.25,
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

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = helpline.emphasized ? Colors.redAccent : const Color(0xFF2F5F49);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Launching.openTel(helpline.phone),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: helpline.phone));
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(.06), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.call_rounded, color: color, size: 20),
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
                        color: Colors.black.withOpacity(.90),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      helpline.note,
                      style: tt.bodySmall?.copyWith(
                        color: Colors.black.withOpacity(.65),
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
      label: '$label',
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          backgroundColor: emphasized ? Colors.redAccent : const Color(0xFF2F5F49),
          foregroundColor: Colors.white,
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
      // Bewusst kurz & ohne Nummernliste:
      'Sprich mit jemandem, dem du vertraust. Für anonyme Unterstützung: 143. In akuten Notfällen: 144.',
      textAlign: TextAlign.center,
      style: tt.bodySmall?.copyWith(
        color: Colors.black.withOpacity(.72),
        height: 1.25,
      ),
    );
  }
}
