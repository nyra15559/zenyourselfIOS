// lib/features/start/start_screen.dart
import '../../shared/zen_style.dart';
//
// StartScreen — ZenYourself · v6.2 (responsive, overflow-safe, a11y-first)
// -----------------------------------------------------------------------------
// • 1 CTA: „Beginnen“ (Erststart → Reflection, sonst → JourneyMap)
// • Voll responsiv mit Breakpoints; Scroll immer erlaubt
// • Footer/Links sind Teil des Scroll-Contents (kein Overlay/Stack)
// • TextScaler lokal geklemmt (verhindert Layout-Sprengungen)
// • Dialog-Titel overflow-safe (Expanded + maxLines + ellipsis)
// • A11y: Semantics für Heading, Panda-Illustration, CTA; Keyboard: Enter/Space
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

    final media = MediaQuery.of(context);
    final clamped =
        media.textScaler.clamp(maxScaleFactor: 1.15, minScaleFactor: 0.90);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: MediaQuery(
        data: media.copyWith(textScaler: clamped),
        child: ZenAppScaffold(
          appBar: null,
          maxBodyWidth: 760,
          bodyPadding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          backdropAsset: 'assets/startscreen1.png',
          backdropWash: .06,
          backdropSaturation: .96,
          backdropGlow: .30,
          backdropVignette: .12,
          backdropMilk: .10,
          body: const SafeArea(child: _StartScrollable()),
        ),
      ),
    );
  }
}

class _StartScrollable extends StatelessWidget {
  const _StartScrollable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 760),
        child: CustomScrollView(
          slivers: [
            const SliverPadding(padding: EdgeInsets.only(top: 12)),
            const SliverToBoxAdapter(child: _StartContent()),
            SliverPadding(
              padding: const EdgeInsets.only(top: 16, bottom: 10),
              sliver: const SliverToBoxAdapter(child: _SecondaryActions()),
            ),
            const SliverToBoxAdapter(
              child: Opacity(
                opacity: .70,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Designed in Switzerland.',
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
  const _StartContent();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isXsSm = width < 480;
    final bool isNarrow = width < 420;

    // Gibt es bereits Einträge?
    final hasEntries = context.select<JournalEntriesProvider, bool>(
      (p) => p.entries.isNotEmpty,
    );

    // Kürzere Texte für xs/sm
    final bullets = isXsSm
        ? const [
            _BulletRow(
                icon: Icons.local_florist_rounded, text: 'Geführte Reflexion'),
            SizedBox(height: 8),
            _BulletRow(
                icon: Icons.lock_outline_rounded,
                text: 'Privat – du entscheidest, was du teilst'),
            SizedBox(height: 8),
            _BulletRow(
                icon: Icons.groups_2_rounded,
                text: 'Mit Psychologen & Betroffenen entwickelt'),
          ]
        : const [
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
          ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isXsSm ? 0 : 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Panda (mit Semantics)
          Semantics(
            label: 'Panda-Illustration',
            image: true,
            child: Container(
              margin: EdgeInsets.only(bottom: isNarrow ? 10 : 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: ZenColors.deepSage.withValue(alpha: .14),
                    blurRadius: 28,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const ZenSafeImage.asset(
                'assets/star_pa.png',
                width: 200,
                height: 200,
              ),
            ),
          ),

          // Titel + Tagline (mit Header-Semantics)
          Semantics(
            header: true,
            child: Text(
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
                  ? 'Erster Start: „Beginnen“ öffnet die Reflexion. Ab dem ersten Eintrag führt „Beginnen“ zum Hauptmenü.'
                  : 'Erster Start: „Beginnen“ führt dich in die Reflexion.\nAb dem ersten Eintrag öffnet „Beginnen“ das Hauptmenü.',
              color: ZenColors.jade.withValue(alpha: .08),
            ),
          ),

          // CTA (mit Semantics & Keyboard-Aktivierung)
          SizedBox(height: isNarrow ? 18 : 22),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _BeginButton(hasEntries: hasEntries),
          ),
        ],
      ),
    );
  }
}

class _BeginButton extends StatelessWidget {
  final bool hasEntries;
  const _BeginButton({required this.hasEntries});

  @override
  Widget build(BuildContext context) {
    void go() {
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
          MaterialPageRoute(builder: (_) => const ReflectionScreen()),
        );
      }
    }

    return Semantics(
      button: true,
      label: 'Beginnen',
      hint: hasEntries ? 'Öffnet das Hauptmenü.' : 'Startet die Reflexion.',
      child: FocusableActionDetector(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(onInvoke: (_) {
            go();
            return null;
          }),
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: ZenPrimaryButton(
                label: 'Beginnen',
                icon: Icons.spa_rounded,
                height: 50,
                onPressed: go,
                tooltip: hasEntries ? 'Hauptmenü öffnen' : 'Reflexion starten',
              ),
            ),
          ],
        ),
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
  const _SecondaryActions();

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
          const _Dot(),
          _TextLink(
            label: 'Datenschutz',
            onTap: () => _showPrivacy(context),
            style: linkStyle,
          ),
          const _Dot(),
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
  const _Dot();

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
                  const Icon(Icons.info_outline_rounded,
                      color: ZenColors.deepSage),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Wie funktioniert ZenYourself?',
                      style: ZenTextStyles.title.copyWith(
                        color: ZenColors.deepSage,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
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
                style: ZenTextStyles.body
                    .copyWith(color: ZenColors.ink, height: 1.34),
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
                  Expanded(
                    child: Text(
                      'Datenschutz',
                      style: ZenTextStyles.title.copyWith(
                        color: ZenColors.deepSage,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Deine Antworten sind privat. '
                'Sie werden lokal angezeigt und nur dann geteilt, wenn du das ausdrücklich möchtest. '
                'Du kannst jede Reflexion auch als Entwurf behalten oder später löschen.',
                style: ZenTextStyles.body
                    .copyWith(color: ZenColors.ink, height: 1.34),
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
                  Expanded(
                    child: Text(
                      'Impressum',
                      style: ZenTextStyles.title.copyWith(
                        color: ZenColors.deepSage,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'ZenYourself · Switzerland\n'
                'Kontakt: info@mta-solution.ch\n'
                'Hinweis: Dies ist eine mentale Unterstützungs-App und ersetzt keine Therapie.',
                style: ZenTextStyles.body
                    .copyWith(color: ZenColors.ink, height: 1.34),
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
