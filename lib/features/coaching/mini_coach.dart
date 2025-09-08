// lib/features/impulse/mini_coach_card.dart
//
// MiniCoachCard — Oxford Zen Edition
// ----------------------------------
// • Sanfte, glasige Karte für Mikro-Impulse, Mini-Meditationen & Coach-Hinweise
// • Optional mit Lottie-Animation und Audio-Button
// • Barrierearm (Semantics), responsiv, markenkonsistentes Styling
// • Defensive Defaults (fällt auf Theme/ZenColors zurück)

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../shared/zen_style.dart';
import '../../shared/ui/zen_widgets.dart';
import 'audio_player.dart';

class MiniCoachCard extends StatelessWidget {
  final String title;
  final String text;

  /// Optional: Mini-Audio/Meditation (Asset-Pfad, z. B. "audio/breath.mp3")
  final String? audioAsset;

  /// Optional: Lottie-Animation (Asset-Pfad, z. B. "assets/lottie/breath.json")
  final String? lottieAnim;

  /// Optionaler Farbakzent (Fallback: ZenColors.jade)
  final Color? accent;

  const MiniCoachCard({
    super.key,
    required this.title,
    required this.text,
    this.audioAsset,
    this.lottieAnim,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor = accent ?? ZenColors.jade;
    final theme = Theme.of(context);

    return Semantics(
      // Screenreader: kurze, klare Ankündigung
      container: true,
      header: true,
      label: 'Mini-Coach: $title',
      child: ZenCard(
        elevation: 8,
        borderRadius: ZenRadii.xl,
        color: ZenColors.white.withValues(alpha: 0.97),
        padding: const EdgeInsets.symmetric(vertical: ZenSpacing.m, horizontal: ZenSpacing.m),
        showWatermark: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Optional: sanfte Animation oben
            if (lottieAnim != null && lottieAnim!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  height: 74,
                  child: Semantics(
                    label: 'Beruhigende Animation',
                    image: true,
                    child: Lottie.asset(
                      lottieAnim!,
                      repeat: true,
                      animate: true,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

            // Titel
            Text(
              title,
              textAlign: TextAlign.center,
              style: ZenTextStyles.h3.copyWith(
                fontSize: 21,
                color: accentColor,
                letterSpacing: 0.14,
                shadows: [
                  Shadow(
                    blurRadius: 9,
                    color: accentColor.withValues(alpha: 0.13),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Text
            Text(
              text,
              textAlign: TextAlign.center,
              style: ZenTextStyles.body.copyWith(
                fontSize: 15.7,
                color: const Color(0xFF1B263B),
                height: 1.36,
                fontWeight: FontWeight.w400,
              ),
            ),

            // Audio (optional)
            if (audioAsset != null && audioAsset!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _ZenHairlineDivider(color: accentColor.withValues(alpha: 0.22)),
              const SizedBox(height: 10),
              Semantics(
                button: true,
                label: 'Audio abspielen',
                child: CoachingAudioPlayer(
                  asset: audioAsset!,
                  description: text,
                  lottieAnim: lottieAnim,
                ),
              ),
            ],

            // Mikro-Hinweis für Achtsamkeit (non-intrusive)
            const SizedBox(height: 6),
            Text(
              'Atme ruhig. Du bestimmst das Tempo.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: ZenColors.jadeMid.withValues(alpha: 0.72),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sehr subtile Trenner-Linie mit leichtem Verlauf (passt in Glas-UI)
class _ZenHairlineDivider extends StatelessWidget {
  final Color color;
  const _ZenHairlineDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.1,
      width: 180,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            color,
            Colors.transparent,
          ],
          stops: const [0.15, 0.5, 0.85],
        ),
      ),
    );
  }
}
