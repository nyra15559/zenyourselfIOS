// lib/features/start/start_screen.dart
//
// StartScreen — ZenYourself · v6.0 (responsive, overflow-safe)
// -----------------------------------------------------------------------------
// - 1 CTA: „Beginnen“ (Erststart → Reflection, sonst → JourneyMap)
// - Voll responsiv mit Breakpoints (xs/sm 1-Spalten-Layout, Scroll immer erlaubt)
// - Footer/Links sind Teil des Scroll-Contents (kein Overlay/Stack)
// - TextScaler lokal geklemmt (verhindert Layout-Sprengungen)
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/ui/zen_widgets.dart'
    show
        ZenAppScaffold,
        ZenSafeImage,
        ZenPrimaryButton,
        ZenInfoBar,
        ZenDialog,
        ZenColors,
        ZenTextStyles,
        ZenRadii;

import '../../providers/journal_entries_provider.dart';

// Direktnavigation
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
    final width = size.width;

    // Breakpoints
    final bool isXsSm = width < 480;
    final bool isLg = width >= 760;

    // Typo/Paddings responsiv
    final double pandaSize = isXsSm ? 160 : 200;
    final EdgeInsets pad =
        EdgeInsets.fromLTRB(isXsSm ? 16 : 24, isXsSm ? 12 : 20, isXsSm ? 16 : 24, isXsSm ? 18 : 28);

    // TextScaling lokal zähmen (damit große OS-Schriften das Layout nicht sprengen)
    final media = MediaQuery.of(context);
    final clamped = media.textScaler.clamp(maxScaleFactor: 1.15, minScaleFactor: 0.90);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: MediaQuery(
        data: media.copyWith(textScaler: clamped),
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
          body: const SafeArea(
            child: _StartScrollable(),
          ),
        ),
      ),
    );
  }
}

class _StartScrollable extends StatelessWidget {
  const _StartScrollable();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isXsSm = width < 480;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 760),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(top: isXsSm ? 8 : 16),
            ),

            // Haupt-Content (Panda, Titel, Bullets, Info, CTA)
            SliverToBoxAdapter(
              child: _StartContent(),
            ),

            // Footer-Links + Made in CH
            SliverPadding(
              padding: EdgeInsets.only(top: isXsSm ? 12 : 16, bottom: isXsSm ? 6 : 10),
              sliver: SliverToBoxAdapter(child: _SecondaryActions()),
            ),
            SliverToBoxAdapter(
              child: Opacity(
                opacity: .70,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Designed in Switzerland.',
                    style: ZenTextStyles.caption.copyWith(color: ZenColors.ink),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isXsSm = width < 480;
    final bool isNarrow = width < 420;
    final double pandaSize = isXsSm ? 160 : 200;

    // Gibt es bereits Einträge?
    final hasEntries = context.select<JournalEntriesProvider, bool>(
      (p) => p.entries.isNotEmpty,
    );

    // Kürzere Texte für xs/sm
    final bullets = isXsSm
        ? const [
            _BulletRow(icon: Icons.local_florist_rounded, text: 'Geführte Reflexion'),
            SizedBox(height: 8),
            _BulletRow(icon: Icons.lock_outline_rounded, text: 'Deine Antworten bleiben privat'),
            SizedBox(height: 8),
            _BulletRow(icon: Icons.groups_2_rounded, text: 'Entwickelt mit Experten & Betroffenen'),
          ]
        : const [
            _BulletRow(
              icon: Icons.local_florist_rounded,
              text: 'Geführte Reflexion mit wissenschaftlichem Ansatz',
            ),
            SizedBox(height: 8),
            _BulletRow(
              icon: Icons.lock_outline_rounded,
              text: 'Deine Antworten sind privat – du entscheidest, was du teilst',
            ),
            SizedBox(height: 8),
            _BulletRow(
              icon: Icons.groups_2_rounded,
              text: 'Entwickelt mit Psychologen & Betroffenen',
            ),
          ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isXsSm ? 0 : 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Panda
          Container(
            margin: EdgeInsets.only(bottom: isNarrow ? 10 : 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: ZenColors.deepSage.withValues(alpha: .14),
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
              fontSize: isXsSm ? 26 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isNarrow ? 4 : 6),
          Text(
            'Your inner voice, reconnected.',
            textAlign: TextAlign.center,
            style: ZenTextStyles.subtitle.copyWith(
              color: ZenColors.jade,
              fontWeight: FontWeight.w700,
              height: 1.25,
              fontSize: isXsSm ? 14.5 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          SizedBox(height: isNarrow ? 12 : 16),

          // Bullet-Punkte (max 620, mittig)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(children: bullets),
          ),

          SizedBox(height: isNarrow ? 14 : 18),

          // Info-Bubble
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ZenInfoBar(
              message: isXsSm
                  ? 'Erster Start: Beginnen öffnet die Reflexion. Ab dem ersten Eintrag führt Beginnen zum Hauptmenü.'
                  : 'Erster Start: Beginnen führt dich in die Reflexion.\nAb dem ersten Eintrag öffnet Beginnen das Hauptmenü.',
              color: ZenColors.jade.withValues(alpha: .08),
            ),
          ),

          // CTA
          SizedBox(height: isNarrow ? 18 : 22),
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
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BulletRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final isXsSm = MediaQuery.of(context).size.width < 480;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: ZenColors.inkStrong,
          height: 1.32,
          fontSize: isXsSm ? 13.5 : null,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: isXsSm ? 16 : 18, color: ZenColors.deepSage),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: style,
            maxLines: isXsSm ? 2 : 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SecondaryActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isXsSm = MediaQuery.of(context).size.width < 480;
    final linkStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: ZenColors.jade,
          fontWeight: FontWeight.w700,
          fontSize: isXsSm ? 12.5 : null,
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
    final isXsSm = MediaQuery.of(context).size.width < 480;
    return Text(
      '·',
      style: ZenTextStyles.caption.copyWith(
        color: ZenColors.ink,
        fontWeight: FontWeight.w700,
        fontSize: isXsSm ? 12.0 : null,
      ),
      textAlign: TextAlign.center,
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
                  const Icon(Icons.info_outline_rounded, color: ZenColors.deepSage),
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
                style: ZenTextStyles.body.copyWith(color: ZenColors.ink, height: 1.34),
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
                  const Icon(Icons.lock_outline_rounded, color: ZenColors.deepSage),
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
                style: ZenTextStyles.body.copyWith(color: ZenColors.ink, height: 1.34),
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
                style: ZenTextStyles.body.copyWith(color: ZenColors.ink, height: 1.34),
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
