// lib/features/start/start_screen.dart
//
// StartScreen — Oxford Calm Onboarding (Green Style, v3.4)
// -----------------------------------------------------------------
// • Einheitlicher Full-bleed Backdrop via ZenBackdrop (Glow/Vignette/Haze/Wash)
// • Panda mit sanftem Sage-Halo (Hero-ready)
// • CTA: "Beginnen" mit Blume/Samen (Icons.spa_outlined)
// • Trustline (Text only)
// • A11y: Semantics, große Touch-Ziele
//
// Hinweis: nutzt ZenBackdrop statt mehrerer Overlays (performanter & konsistent)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Design-Tokens (Farben/Spacing/Radii) – als Alias `zs`, Widgets werden hier „gehidet“
import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenGlassInput;

// Zen-Widgets (nur die benötigten Widgets) – als Alias `zw`
import '../../shared/ui/zen_widgets.dart' as zw show ZenBackdrop;

import '../../models/mood_entries_provider.dart';
import '../../models/reflection_entries_provider.dart';
import '../journey/journey_map.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({Key? key}) : super(key: key);

  static const String _bgAsset = 'assets/startscreen1.png';
  static const String _pandaAsset = 'assets/panda.png';
  static const String _appName = 'ZenYourself';
  static const String _tagline =
      'Dein Raum für Selbstreflexion,\nAchtsamkeit & innere Ruhe';

  // Responsive Konstanten
  static const double _mobileMaxWidth = 560.0;
  static const double _pandaSizeRel = 0.30;

  @override
  Widget build(BuildContext context) {
    // Provider-Reads (einmalig im Build, kein Listen)
    final entries = context.read<MoodEntriesProvider>().entries;
    final reflections = context.read<ReflectionEntriesProvider>().reflections;

    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < _mobileMaxWidth;

    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final pandaW = _clampDouble(size.width * _pandaSizeRel, 130, 260);

    final titleStyle = Theme.of(context).textTheme.headlineMedium!;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: zs.ZenColors.bg,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1) Einheitlicher Backdrop (performant & konsistent)
              const Positioned.fill(
                child: zw.ZenBackdrop(
                  asset: _bgAsset,
                  alignment: Alignment.center,
                  glow: .38,
                  vignette: .12,
                  enableHaze: true,
                  hazeStrength: .16,
                  saturation: .92, // leicht entsättigt
                  wash: .06, // sanft aufgehellt
                ),
              ),

              // 2) Inhalt
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: zs.ZenSpacing.xl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _mobileMaxWidth),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? zs.ZenSpacing.l : zs.ZenSpacing.xl,
                        vertical: zs.ZenSpacing.s,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: MediaQuery.of(context).padding.top),
                          const SizedBox(height: zs.ZenSpacing.l),

                          // Panda mit Sage-Halo
                          _PandaWithHalo(asset: _pandaAsset, width: pandaW),

                          const SizedBox(height: zs.ZenSpacing.l),

                          // App-Name (weicher als tiefschwarz)
                          Text(
                            _appName,
                            textAlign: TextAlign.center,
                            style: titleStyle.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: zs.ZenColors.inkStrong.withOpacity(0.90),
                            ),
                          ),

                          const SizedBox(height: zs.ZenSpacing.s),

                          // Tagline in Deep-Sage
                          Text(
                            _tagline,
                            textAlign: TextAlign.center,
                            style: bodyStyle.copyWith(
                              fontWeight: FontWeight.w700,
                              color: zs.ZenColors.deepSage,
                              height: 1.35,
                            ),
                          ),

                          const SizedBox(height: zs.ZenSpacing.l),

                          // Bulletpoints
                          Semantics(
                            label:
                                'Hauptvorteile: Geführte Reflexion, Privatsphäre, Mit Expertinnen und Experten entwickelt',
                            container: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _ChampionBullet(
                                  icon: Icons.spa_rounded,
                                  text:
                                      'Geführte Reflexion mit wissenschaftlichem Ansatz',
                                ),
                                SizedBox(height: zs.ZenSpacing.s),
                                _ChampionBullet(
                                  icon: Icons.lock_rounded,
                                  text:
                                      'Deine Antworten sind privat – du entscheidest, was du teilst',
                                ),
                                SizedBox(height: zs.ZenSpacing.s),
                                _ChampionBullet(
                                  icon: Icons.groups_rounded,
                                  text:
                                      'Entwickelt mit Psychologen & Betroffenen',
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: zs.ZenSpacing.l * 1.25),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3) CTA unten
              Positioned(
                left: 0,
                right: 0,
                bottom: zs.ZenSpacing.xl + MediaQuery.of(context).padding.bottom,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _mobileMaxWidth),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? zs.ZenSpacing.l : zs.ZenSpacing.xl,
                      ),
                      child: Column(
                        children: [
                          // CTA: „Beginnen“ (Blume/Samen)
                          Semantics(
                            button: true,
                            label: 'Beginnen',
                            child: _PrimaryCtaButton(
                              label: 'Beginnen',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => JourneyMapScreen(
                                      moodEntries: entries,
                                      reflections: reflections,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Trustline (Text only, no emoji)
                          Text(
                            'Designed in Switzerland.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: zs.ZenColors.inkSubtle,
                                  letterSpacing: 0.15,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _clampDouble(double v, double min, double max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }
}

// --- Panda mit sanftem Sage-Halo ---
class _PandaWithHalo extends StatelessWidget {
  final String asset;
  final double width;
  const _PandaWithHalo({required this.asset, required this.width});

  @override
  Widget build(BuildContext context) {
    final haloSize = width + 56;
    return Semantics(
      label: 'Willkommensmaskottchen: Panda',
      image: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Sage-Halo
          Container(
            width: haloSize,
            height: haloSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  zs.ZenColors.sage.withOpacity(0.30),
                  zs.ZenColors.sage.withOpacity(0.00),
                ],
                stops: const [0.0, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: zs.ZenColors.jadeMid.withOpacity(0.10),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Hero(
            tag: 'panda-hero',
            child: Image.asset(
              asset,
              width: width,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const SizedBox(width: 180, height: 180),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Bullet mit Icon & Zen-Typografie ---
class _ChampionBullet extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ChampionBullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: 15.8,
          color: zs.ZenColors.ink,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.07,
          height: 1.32,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: zs.ZenColors.deepSage, size: 21.5),
        const SizedBox(width: zs.ZenSpacing.s),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

// --- Lokaler Primary CTA (kompakt) mit Blume/Samen-Icon ---
class _PrimaryCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryCtaButton({
    Key? key,
    required this.label,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 16.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6, // ruhiger Raum zwischen Buchstaben
          color: Colors.white,
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48), // kompakter
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: zs.ZenColors.deepSage,
          foregroundColor: Colors.white,
          elevation: 1.7,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(zs.ZenRadii.l),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.pressed)
                ? Colors.black.withOpacity(0.06)
                : null,
          ),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.spa_outlined, size: 22),
        label: Text(label, style: txt),
      ),
    );
  }
}
