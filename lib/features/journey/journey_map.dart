// lib/features/journey/journey_map.dart
//
// JourneyMapScreen — v7.3 Oxford (Therapeuten-Tile, Privacy-Footer, Safe-Nav)
// Anpassungsdatum: 2025-09-13
// Hinweise:
// • Gemäß Projektstil: keine übermäßige Verwendung von `const` bei Widgets.
// • Safe-Nav-Lock verhindert doppelte Navigations-Pushes.
// • Story-Gate via Provider: Freischaltung nach ≥ StoryScreen.neededReflections.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Tokens (ohne Widget-Backdrop, um Namenskollision zu vermeiden)
import '../../shared/zen_style.dart' as zs hide ZenBackdrop, ZenGlassCard;
// UI-Widgets (mit Widget-Backdrop)
import '../../shared/ui/zen_widgets.dart' show ZenBackdrop, ZenGlassCard;

// Datenmodelle (Legacy – bleibt für Konstruktor-Signatur als Fallback)
import '../../data/mood_entry.dart';
import '../../data/reflection_entry.dart';

// Kanonische Quelle für Reflexionen
import '../../providers/journal_entries_provider.dart';

// Screens
import '../journal/journal_screen.dart';
import '../reflection/reflection_screen.dart';
import '../impulse/impulse_screen.dart';
import '../pro/pro_screen.dart';
import '../story/story_screen.dart';

const double _tabletMaxWidth = 720;
const int _kStoryUnlock = StoryScreen.neededReflections;

class JourneyMapScreen extends StatefulWidget {
  final List<MoodEntry> moodEntries;
  final List<ReflectionEntry> reflections; // Legacy-Param (Fallback)

  const JourneyMapScreen({
    super.key,
    required this.moodEntries,
    required this.reflections,
  });

  @override
  State<JourneyMapScreen> createState() => _JourneyMapScreenState();
}

class _JourneyMapScreenState extends State<JourneyMapScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introCtrl;
  late final AnimationController _tilesCtrl;

  bool _navLocked = false;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(vsync: this, duration: zs.animLong)..forward();
    _tilesCtrl = AnimationController(vsync: this, duration: zs.animMed)..forward();
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _tilesCtrl.dispose();
    super.dispose();
  }

  Future<T?> _pushLocked<T>(Route<T> route) async {
    if (_navLocked) return null;
    _navLocked = true;
    try {
      final nav = Navigator.maybeOf(context);
      if (nav == null) {
        _navLocked = false;
        return null;
      }
      final res = await nav.push(route);
      return res;
    } finally {
      if (!mounted) {
        _navLocked = false;
      } else {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _navLocked = false;
        });
      }
    }
  }

  Future<void> _openReflection() async {
    HapticFeedback.selectionClick();
    await _pushLocked(MaterialPageRoute(builder: (_) => const ReflectionScreen()));
  }

  void _showLockedSnack(int remaining) {
    final plural = remaining == 1 ? 'Runde' : 'Runden';
    final snack = SnackBar(
      content: Text('Noch $remaining komplette $plural bis zur Kurzgeschichte.'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    );
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(snack);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 520;
    final maxGridWidth = size.width < _tabletMaxWidth ? 480.0 : 720.0;
    final tt = Theme.of(context).textTheme;

    // Reflexions-Zähler aus dem JournalEntriesProvider (Fallback: Legacy-Param).
    final prov = context.watch<JournalEntriesProvider?>();
    final reflectionsCount = prov?.reflections.length ?? widget.reflections.length;
    final storyUnlocked = reflectionsCount >= _kStoryUnlock;
    final remaining = storyUnlocked ? 0 : (_kStoryUnlock - reflectionsCount);

    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const PositionedFillBackdrop(),

            // Back-Button
            const SafeArea(
              child: Padding(
                padding: EdgeInsets.only(top: zs.ZenSpacing.l, left: zs.ZenSpacing.l),
                child: _BackButton(),
              ),
            ),

            // Content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    zs.ZenSpacing.m,
                    size.height < 700 ? zs.ZenSpacing.m : zs.ZenSpacing.xl,
                    zs.ZenSpacing.m,
                    zs.ZenSpacing.xl,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxGridWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Headline
                        ScaleTransition(
                          scale: CurvedAnimation(parent: _introCtrl, curve: Curves.elasticOut),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: zs.ZenSpacing.m),
                            child: Text(
                              'Was brauchst du?',
                              textAlign: TextAlign.center,
                              style: tt.headlineMedium!.copyWith(
                                fontSize: 24,
                                color: zs.ZenColors.deepSage,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .2,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.black.withValues(alpha: .08),
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Grid
                        FadeTransition(
                          opacity: CurvedAnimation(parent: _tilesCtrl, curve: Curves.easeOutCubic),
                          child: LayoutBuilder(
                            builder: (context, _) {
                              return GridView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isCompact ? 1 : 2,
                                  mainAxisSpacing: zs.ZenSpacing.m,
                                  crossAxisSpacing: zs.ZenSpacing.m,
                                  childAspectRatio: isCompact ? 16 / 5 : 16 / 4.6,
                                ),
                                children: [
                                  _OptionTile(
                                    icon: Icons.menu_book_rounded,
                                    label: 'Gedankenbuch',
                                    subtitle: 'Lass deine Gedanken los',
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _pushLocked(MaterialPageRoute(builder: (_) => const JournalScreen()));
                                    },
                                  ),
                                  _OptionTile(
                                    icon: Icons.psychology_alt_rounded,
                                    label: 'Selbstreflexion',
                                    subtitle: 'Ordne deine Gedanken',
                                    onTap: _openReflection,
                                  ),
                                  _OptionTile(
                                    icon: Icons.auto_stories_rounded,
                                    label: 'Kurzgeschichte',
                                    subtitle: storyUnlocked
                                        ? 'Therapeutische Kurzgeschichte lesen'
                                        : 'Noch $remaining bis freigeschaltet',
                                    locked: !storyUnlocked,
                                    lockHint:
                                        'Noch $remaining vollständige Runde${remaining == 1 ? '' : 'n'} bis zur Story',
                                    onTap: () {
                                      if (!storyUnlocked) {
                                        HapticFeedback.selectionClick();
                                        _showLockedSnack(remaining);
                                        return;
                                      }
                                      HapticFeedback.selectionClick();
                                      _pushLocked(MaterialPageRoute(builder: (_) => const StoryScreen()));
                                    },
                                  ),
                                  _OptionTile(
                                    icon: Icons.bubble_chart_rounded,
                                    label: 'Impuls',
                                    subtitle: 'Atem & Mini-Reset',
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _pushLocked(MaterialPageRoute(builder: (_) => const ImpulseScreen()));
                                    },
                                  ),
                                  _OptionTile(
                                    icon: Icons.insights_rounded,
                                    label: 'Dich erkennen',
                                    subtitle: 'Dein Weg in Bildern',
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _pushLocked(
                                        MaterialPageRoute(
                                          builder: (_) => ProScreen(
                                            moodEntries: widget.moodEntries,
                                            reflectionEntries: widget.reflections,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // Therapeuten-Modus als eigener Tile
                                  _OptionTile(
                                    icon: Icons.verified_user_rounded,
                                    label: 'Therapeuten-Modus',
                                    subtitle: 'Code eingeben & teilen',
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _pushLocked(
                                        MaterialPageRoute(
                                          builder: (_) => ProScreen(
                                            moodEntries: widget.moodEntries,
                                            reflectionEntries: widget.reflections,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Footer: Zitat + Privacy-Hinweis (dezent)
            Positioned(
              left: 0,
              right: 0,
              bottom: zs.ZenSpacing.l,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: zs.animShort,
                        child: Text(
                          _randomQuote(reflectionsCount),
                          key: ValueKey(reflectionsCount % 7),
                          textAlign: TextAlign.center,
                          style: tt.titleMedium!.copyWith(
                            color: zs.ZenColors.deepSage,
                            fontStyle: FontStyle.italic,
                            fontSize: 16.0,
                            shadows: [
                              const Shadow(
                                blurRadius: 6,
                                color: Colors.black26,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Privacy first · Lokaler Modus: Deine Daten bleiben auf deinem Gerät.',
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: zs.ZenColors.deepSage.withValues(alpha: .82),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _randomQuote(int idx) {
    final quotes = [
      'Manchmal reicht es, einfach da zu sein.',
      'Ruhe finden beginnt mit dem Annehmen.',
      'Dein Weg darf leicht sein.',
      'Es ist okay, einfach zu fühlen.',
      'Heute darfst du einfach du sein.',
      'Die Stille kennt keinen Plan.',
      'Atme. Mehr musst du nicht tun.',
    ];
    return quotes[idx % quotes.length];
  }
}

class PositionedFillBackdrop extends StatelessWidget {
  const PositionedFillBackdrop({super.key});
  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: ZenBackdrop(
        asset: 'assets/zen_journey_bg.png',
        glow: .36,
        vignette: .12,
        enableHaze: true,
        hazeStrength: .12,
        saturation: .94,
        wash: .10,
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Zurück',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: const BorderRadius.all(zs.ZenRadii.l),
          onTap: () => Navigator.maybeOf(context)?.maybePop(),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: zs.ZenColors.surface.withValues(alpha: .49),
              shape: BoxShape.circle,
              boxShadow: zs.ZenShadows.card,
              border: Border.all(
                color: zs.ZenColors.sage.withValues(alpha: .18),
                width: 1.2,
              ),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: zs.ZenColors.deepSage,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool locked;
  final String? lockHint;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.locked = false,
    this.lockHint,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final tile = Opacity(
      opacity: locked ? 0.65 : 1.0,
      child: ZenGlassCard(
        padding: const EdgeInsets.symmetric(
          horizontal: zs.ZenSpacing.m,
          vertical: zs.ZenSpacing.s,
        ),
        topOpacity: .22,
        bottomOpacity: .08,
        borderOpacity: .16,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: zs.ZenColors.cta.withValues(alpha: .12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: zs.ZenColors.cta.withValues(alpha: .35),
                ),
              ),
              child: Icon(icon, color: zs.ZenColors.cta, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelLarge!.copyWith(
                      color: zs.ZenColors.cta,
                      fontWeight: FontWeight.w700,
                      fontSize: 17.2,
                      letterSpacing: .1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium!.copyWith(
                      color: zs.ZenColors.cta.withValues(alpha: .82),
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              locked ? Icons.lock_rounded : Icons.chevron_right_rounded,
              color: zs.ZenColors.cta,
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      label: label,
      hint: locked ? (lockHint ?? 'Gesperrt') : subtitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
          splashColor: zs.ZenColors.cta.withValues(alpha: .12),
          highlightColor: zs.ZenColors.cta.withValues(alpha: .06),
          onTap: () {
            if (locked) {
              HapticFeedback.selectionClick();
              final msg = lockHint ?? 'Noch etwas Geduld – bald freigeschaltet.';
              final snack = SnackBar(
                content: Text(msg),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              );
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(snack);
              return;
            }
            onTap();
          },
          child: tile,
        ),
      ),
    );
  }
}
