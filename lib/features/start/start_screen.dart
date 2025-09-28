// lib/features/start/start_screen.dart
//
// StartScreen — ZenYourself · v5.4.1 (Ein-CTA Flow, route-agnostic)
// -----------------------------------------------------------------------------
// - Hintergrund: assets/startscreen1.png
// - Panda:       assets/pandasitz.png
// - 1 Haupt-CTA: „Beginnen“
//     • Erststart (keine Einträge)  → ReflectionScreen
//     • Wiederkehrend (>=1 Eintrag) → JourneyMapScreen
// - Info-Bubble: kurzer Kontext-Hinweis (ohne Aktion)
// - Footer: „Wie funktioniert das?“, „Datenschutz“, „Impressum“
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/ui/zen_widgets.dart'
    show
        ZenAppScaffold,
        ZenBackdrop,
        ZenSafeImage,
        ZenPrimaryButton,
        ZenInfoBar,
        ZenDialog,
        ZenColors,
        ZenTextStyles,
        ZenRadii;

// Daten/Provider
import '../../providers/journal_entries_provider.dart';

// Direktnavigation (harness-sicher)
import '../journey/journey_map.dart';
import '../reflection/reflection_screen.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 420;
    final double pandaSize = isNarrow ? 160 : 200;

    final EdgeInsets pad =
        EdgeInsets.fromLTRB(16, isNarrow ? 12 : 20, 16, isNarrow ? 18 : 28);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: ZenAppScaffold(
        appBar: null,
        maxBodyWidth: 760,
        bodyPadding: pad,
        backdropAsset: 'assets/startscreen1.png',
        backdropWash: .06,
        backdropSaturation: .96,
        backdropGlow: .30,
        backdropVignette: .12,
        backdropMilk: .10,
        body: SafeArea(
          child: Center(
            child: _StartContent(pandaSize: pandaSize),
          ),
        ),
      ),
    );
  }
}

class _StartContent extends StatelessWidget {
  final double pandaSize;
  const _StartContent({required this.pandaSize});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final narrow = width < 420;

    // Live aus Provider: gibt es bereits Einträge?
    final hasEntries = context.select<JournalEntriesProvider, bool>(
      (p) => p.entries.isNotEmpty,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Panda
        Container(
          margin: EdgeInsets.only(bottom: narrow ? 10 : 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: ZenColors.deepSage.withOpacity(.14),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ZenSafeImage.asset(
            'assets/star_pa.png',
            width: pandaSize,
            height: pandaSize,
          ),
        ),

        // Titel + Tagline
        Text(
          'ZenYourself',
          textAlign: TextAlign.center,
          style: ZenTextStyles.h2.copyWith(
            fontWeight: FontWeight.w800,
            color: ZenColors.deepSage,
          ),
        ),
        SizedBox(height: narrow ? 4 : 6),
        Text(
          'Your inner voice, reconnected.',
          textAlign: TextAlign.center,
          style: ZenTextStyles.subtitle.copyWith(
            color: ZenColors.jade,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),

        SizedBox(height: narrow ? 12 : 16),

        // Bullet-Punkte
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: const Column(
            children: [
              _BulletRow(
                icon: Icons.local_florist_rounded,
                text: 'Geführte Reflexion mit wissenschaftlichem Ansatz',
              ),
              SizedBox(height: 8),
              _BulletRow(
                icon: Icons.lock_outline_rounded,
                text:
                    'Deine Antworten sind privat – du entscheidest, was du teilst',
              ),
              SizedBox(height: 8),
              _BulletRow(
                icon: Icons.groups_2_rounded,
                text: 'Entwickelt mit Psychologen & Betroffenen',
              ),
            ],
          ),
        ),

        SizedBox(height: narrow ? 14 : 18),

        // Info-Bubble (Option A, ohne Aktion)
        const _StartInfoBar(),

        // CTA: Beginnen → Reflection (0) / Journey (>=1)
        SizedBox(height: narrow ? 18 : 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ZenPrimaryButton(
                  label: 'Beginnen',
                  icon: Icons.spa_rounded,
                  height: 50,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    if (hasEntries) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const JourneyMapScreen(
                            moodEntries: [],
                            reflections: [],
                          ),
                        ),
                      );
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReflectionScreen(),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),

        // Footer-Links
        SizedBox(height: narrow ? 12 : 16),
        _SecondaryActions(),

        SizedBox(height: narrow ? 8 : 12),
        Opacity(
          opacity: .70,
          child: Text(
            'Designed in Switzerland.',
            style: ZenTextStyles.caption.copyWith(color: ZenColors.ink),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: narrow ? 6 : 10),
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BulletRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: ZenColors.inkStrong, height: 1.32);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: ZenColors.deepSage),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

class _StartInfoBar extends StatelessWidget {
  const _StartInfoBar();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: ZenInfoBar(
        message:
            'Erster Start: Beginnen führt dich in die Reflexion.\n'
            'Ab dem ersten Eintrag öffnet Beginnen das Hauptmenü.',
        // keine Aktion – Footer deckt weiterführende Infos ab
        color: ZenColors.jade.withOpacity(.08),
      ),
    );
  }
}

class _SecondaryActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final linkStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: ZenColors.jade,
          fontWeight: FontWeight.w700,
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          _TextLink(
            label: 'Wie funktioniert das?',
            onTap: () => _showHowItWorks(context),
            style: linkStyle,
          ),
          _Dot(),
          _TextLink(
            label: 'Datenschutz',
            onTap: () => _showPrivacy(context),
            style: linkStyle,
          ),
          _Dot(),
          _TextLink(
            label: 'Impressum',
            onTap: () => _showImprint(context),
            style: linkStyle,
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      '·',
      style: ZenTextStyles.caption.copyWith(
        color: ZenColors.ink,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final TextStyle? style;
  const _TextLink({required this.label, required this.onTap, this.style});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: const BorderRadius.all(ZenRadii.s),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(label, style: style),
      ),
    );
  }
}

// ───────────────────────────────── Dialoge ─────────────────────────────────

void _showHowItWorks(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => ZenDialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: ZenColors.deepSage),
                  const SizedBox(width: 8),
                  Text(
                    'Wie funktioniert ZenYourself?',
                    style: ZenTextStyles.title.copyWith(
                      color: ZenColors.deepSage,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Du startest mit einem Gedanken oder einer kurzen Frage. '
                'Der Panda spiegelt und stellt eine ruhige, präzise Frage zurück. '
                'Du entscheidest, was du teilen möchtest. '
                'Deine Antworten kannst du später im Gedankenbuch speichern.',
                style:
                    ZenTextStyles.body.copyWith(color: ZenColors.ink, height: 1.34),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Schließen'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showPrivacy(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => ZenDialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      color: ZenColors.deepSage),
                  const SizedBox(width: 8),
                  Text(
                    'Datenschutz',
                    style: ZenTextStyles.title.copyWith(
                      color: ZenColors.deepSage,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Deine Antworten sind privat. '
                'Sie werden lokal angezeigt und nur dann geteilt, wenn du das ausdrücklich möchtest. '
                'Du kannst jede Reflexion auch als Entwurf behalten oder später löschen.',
                style:
                    ZenTextStyles.body.copyWith(color: ZenColors.ink, height: 1.34),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Schließen'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showImprint(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => ZenDialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.badge_outlined, color: ZenColors.deepSage),
                  const SizedBox(width: 8),
                  Text(
                    'Impressum',
                    style: ZenTextStyles.title.copyWith(
                      color: ZenColors.deepSage,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'ZenYourself · Switzerland\n'
                'Kontakt: hello@zenyourself.app\n'
                'Hinweis: Dies ist eine mentale Unterstützungs-App und ersetzt keine Therapie.',
                style:
                    ZenTextStyles.body.copyWith(color: ZenColors.ink, height: 1.34),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Schließen'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
