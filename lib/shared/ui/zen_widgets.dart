// [BASELINE] lib/shared/ui/zen_widgets.dart (Stand: 31.10.)
// lib/shared/ui/zen_widgets.dart
//
// Oxford–Zen UI Widgets (v6.96 · 2025-10-31)
// ---------------------------------------------------------------------------
// WICHTIG – Vereinheitlichung v6.1 (ohne neue Dateien):
// • Glas: Blur σ=18, bg White @0.20, border White @0.22, Shadow (0,8,20,0.10), Radius 20
// • Header: Panda→Titel 12 px, Titel→Caption 6 px, Caption Ink @70% (nicht italic)
// • CTA: Höhe 48, Stadium→Radius wie L, konsistentes Padding
// • Scaffold: Default Max-Width 680, Padding 24 (Grid 8/16/24/32)
// • Keine Breaking Changes: öffentliche API unverändert, nur Defaults/Styles justiert
//
// v6.95 – Änderungen (Task 15):
// • SafeArea-Audit: ZenAppScaffold mit optionalen safeTop/Bottom/Left/Right & respectKeyboardInsets.
// • Effektives Body-Padding berücksichtigt Tastatur-Insets > SafeArea.
// • Buttons: einheitlicher Icon–Label Abstand (10 px), optionale Semantics (TalkBack).
// • ZenMetricTile hinzugefügt (A11y-freundlicher Metric-Tile).
//
// v6.96 – Änderungen (Task 9):
// • F1: Wiederverwendbare Bausteine für PinBar/Footer ergänzt:
//   – ZenOutlineButton: optionaler Tooltip-Parameter (rückwärtskompatibel).
//   – NEU: ZenIconChip (Icon + optionales Label), kompakt & tonal/outlinefähig.
//
// Abhängigkeiten (pubspec):
//   lottie: ^3.3.1
//   flutter_svg: ^2.0.10

import 'dart:ui' show ImageFilter, ColorFilter;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../shared/zen_style.dart'
    hide
        ZenBackdrop,
        ZenGlassCard,
        ZenGlassInput,
        ZenAppBar; // ⟵ Konflikte vermeiden

// Re-export (Kompatibilität: ZenFormat weiterhin über dieses File nutzbar)
export '../../shared/zen_style.dart'
    show ZenFormat, ZenSpacing, ZenRadii, ZenColors, ZenShadows, ZenTextStyles;

/// interne Animations-Dauer (vereinheitlicht)
const Duration _animMed = Duration(milliseconds: 240);

// -------- Oxford–Zen v6.1 Style Defaults (lokal, keine zusätzlichen Dateien) -----
const double _kGlassBlur = 18.0;
const double _kGlassBgOpacity = 0.20;
const double _kGlassBorderOpacity = 0.22;
final BoxShadow _kGlassShadow = BoxShadow(
    color: Colors.black.withValue(alpha: 0.10),
    blurRadius: 20,
    offset: const Offset(0, 8));

/// ======================================================================
/// ZEN APP SCAFFOLD — optionaler Backdrop & responsive Breite
/// ======================================================================
class ZenAppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;

  /// Optional: Hintergrundbild (Artwork). Wenn null → nur Theme-Hintergrund.
  final String? backdropAsset;

  /// Maximalbreite des Inhaltsbereichs (z. B. Tablet/Desktop)
  final double maxBodyWidth;

  /// Basis-Innenabstand um den Body herum (wird mit SafeArea/Keyboard-Insets kombiniert)
  final EdgeInsets bodyPadding;

  /// Optional: Backdrop-Feinjustage (nur wirksam, wenn backdropAsset != null)
  final double? backdropWash;
  final double? backdropSaturation;
  final double? backdropGlow;
  final double? backdropVignette;

  /// Extra: „Milchigkeit“ (kombiniert leichter Haze + Weißfilm)
  final double? backdropMilk;

  // ---- SafeArea/Keyboard Optionen (NEU; abwärtskompatibel) -------------------
  /// Top-SafeArea zusätzlich berücksichtigen (Default false, um Layouts nicht zu verschieben)
  final bool safeTop;

  /// Bottom-SafeArea berücksichtigen (Default true)
  final bool safeBottom;

  /// Seitliche SafeAreas (Notch/Curved) berücksichtigen (Default true)
  final bool safeLeft;
  final bool safeRight;

  /// Wenn true, überschreibt die Tastatur die Bottom-SafeArea (Keyboard > SafeArea)
  final bool respectKeyboardInsets;

  const ZenAppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.backdropAsset,
    this.maxBodyWidth = 680, // v6.1
    this.bodyPadding = const EdgeInsets.fromLTRB(24, 24, 24, 24), // v6.1
    this.backdropWash,
    this.backdropSaturation,
    this.backdropGlow,
    this.backdropVignette,
    this.backdropMilk,
    // SafeArea/Keyboard
    this.safeTop = false,
    this.safeBottom = true,
    this.safeLeft = true,
    this.safeRight = true,
    this.respectKeyboardInsets = true,
  });

  EdgeInsets _effectivePadding(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = bodyPadding;

    final addTop = safeTop ? mq.padding.top : 0.0;
    final addLeft = safeLeft ? mq.padding.left : 0.0;
    final addRight = safeRight ? mq.padding.right : 0.0;

    final kb = respectKeyboardInsets ? mq.viewInsets.bottom : 0.0;
    final safeBtm = safeBottom ? mq.padding.bottom : 0.0;
    final addBottom = kb > 0 ? kb : safeBtm;

    return EdgeInsets.fromLTRB(
      pad.left + addLeft,
      pad.top + addTop,
      pad.right + addRight,
      pad.bottom + addBottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBodyWidth),
        child: Padding(
          padding: _effectivePadding(context),
          child: body,
        ),
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (backdropAsset != null)
            ZenBackdrop(
              asset: backdropAsset!,
              wash: (backdropWash ?? .06),
              saturation: (backdropSaturation ?? .95),
              glow: (backdropGlow ?? .28),
              vignette: (backdropVignette ?? .12),
              milk: (backdropMilk ?? .10).clamp(0.0, 1.0),
            )
          else
            const DecoratedBox(decoration: BoxDecoration(color: ZenColors.bg)),
          content,
        ],
      ),
    );
  }
}

/// ======================================================================
/// SAFE IMAGE — robustes Asset-Image mit Fallback (kein Crash)
/// ======================================================================
class ZenSafeImage extends StatelessWidget {
  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? fallback;

  const ZenSafeImage.asset(
    this.asset, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, __, ___) =>
          fallback ??
          const Icon(Icons.image_not_supported_outlined,
              color: ZenColors.jade, size: 28),
    );
  }
}

/// ======================================================================
/// APP BAR — luftig, transparent, mit sanftem Top-Fade
/// ======================================================================
class ZenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final bool showBack;
  final double elevation;

  /// Feinjustage des integrierten Top-Fades
  final double fadeHeight; // px
  final double fadeOpacity; // 0..1

  const ZenAppBar({
    super.key,
    this.title,
    this.actions,
    this.showBack = true,
    this.elevation = 0,
    this.fadeHeight = 64,
    this.fadeOpacity = .12,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Integrierter Top-Fade (ohne externe Overlay-Utility)
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: fadeHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValue(alpha: fadeOpacity),
                    Colors.white.withValue(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: elevation,
          centerTitle: true,
          title: title != null
              ? Text(
                  title!,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(overflow: TextOverflow.ellipsis),
                )
              : null,
          actions: actions,
          leading: showBack && canPop
              ? IconButton(
                  tooltip: 'Zurück',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => Navigator.maybePop(context),
                )
              : null,
        ),
      ],
    );
  }
}

/// ======================================================================
/// PANDA HEADER — Brand-Moment (Panda + Titel + Caption)
/// ======================================================================
class PandaHeader extends StatelessWidget {
  final String title;
  final String? caption;
  final double pandaSize; // 88–112 empfohlen
  final bool strongTitleGreen; // true → DeepSage, false → InkStrong

  const PandaHeader({
    super.key,
    required this.title,
    this.caption,
    this.pandaSize = 96,
    this.strongTitleGreen = true,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Semantics(
      header: true,
      child: Column(
        children: [
          _AnimatedPandaGlow(size: pandaSize),
          const SizedBox(height: 12), // v6.1
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: tt.headlineMedium!.copyWith(
              fontSize: 26, // etwas ruhiger
              color:
                  strongTitleGreen ? ZenColors.deepSage : ZenColors.inkStrong,
              fontWeight: FontWeight.w700, // v6.1 (semibold)
              letterSpacing: 0.10, // v6.1
              shadows: [
                Shadow(
                  blurRadius: 4,
                  color: Colors.black.withValue(alpha: .05),
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6), // v6.1
            Opacity(
              opacity: 0.92,
              child: Text(
                caption!,
                textAlign: TextAlign.center,
                style: ZenTextStyles.caption.copyWith(
                  fontSize: 14.5,
                  // Oxford-Zen v6.1: ruhige Tagline in Ink @70%, nicht italic
                  color: const Color(0xFF1A1A1A).withValue(alpha: .70),
                  fontStyle: FontStyle.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnimatedPandaGlow extends StatefulWidget {
  final double size;
  const _AnimatedPandaGlow({required this.size});

  @override
  State<_AnimatedPandaGlow> createState() => _AnimatedPandaGlowState();
}

class _AnimatedPandaGlowState extends State<_AnimatedPandaGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(top: 16, bottom: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ZenColors.deepSage
                  .withValue(alpha: 0.10 + 0.17 * _glow.value),
              blurRadius: 30 + 16 * _glow.value,
              spreadRadius: 4 + 5 * _glow.value,
            ),
          ],
        ),
        child: ZenSafeImage.asset(
          'assets/star_pa.png',
          width: widget.size,
          height: widget.size,
          fallback: const Icon(Icons.pets, color: ZenColors.deepSage, size: 42),
        ),
      ),
    );
  }
}

/// ======================================================================
/// GLASS CARD — UI-Variante (parallel zu Primitives)
/// ======================================================================
class ZenGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;

  /// Obere/untere Licht-Schicht (0..1) — behalten für Backwards-Compat
  final double topOpacity;
  final double bottomOpacity;

  /// Rahmen-Deckkraft (0..1)
  final double borderOpacity;

  const ZenGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ZenSpacing.l),
    this.margin = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(ZenRadii.xl), // v6.1 Radius 20
    this.topOpacity = _kGlassBgOpacity,
    this.bottomOpacity = _kGlassBgOpacity,
    this.borderOpacity = _kGlassBorderOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.white.withValue(alpha: borderOpacity);

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            // Vereinheitlichter Blur
            BackdropFilter(
              filter:
                  ImageFilter.blur(sigmaX: _kGlassBlur, sigmaY: _kGlassBlur),
              child: const SizedBox.shrink(),
            ),
            // Einheitlicher „Weißfilm“ (statt wechselnder Gradients)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValue(alpha: _kGlassBgOpacity),
                  ),
                ),
              ),
            ),
            // Border + Shadow + Inhalt
            Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [_kGlassShadow], // v6.1
              ),
              padding: padding,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// ======================================================================
/// GLASS INPUT — rahmt Textfelder im Glas-Stil (ein Layer, klare Kante)
/// ======================================================================
class ZenGlassInput extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  const ZenGlassInput({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12), // v6.1
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final br =
        borderRadius ?? const BorderRadius.all(ZenRadii.xl); // v6.1 Radius 20

    return ClipRRect(
      borderRadius: br,
      child: Stack(
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _kGlassBlur, sigmaY: _kGlassBlur),
            child: const SizedBox.shrink(),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: br,
              color: Colors.white.withValue(alpha: _kGlassBgOpacity),
              border: Border.all(
                color: Colors.white.withValue(alpha: _kGlassBorderOpacity),
                width: 1,
              ),
              boxShadow: [_kGlassShadow],
            ),
            padding: padding,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// ======================================================================
/// BACKDROP — Bild + Wash/Sättigung/Glow/Vignette/Haze/Milk (Widget-Variante)
/// ======================================================================
class ZenBackdrop extends StatelessWidget {
  final String asset;
  final Alignment alignment;

  /// 0..1 – heller Glow von der Mitte
  final double glow;

  /// 0..1 – Vignette-Randabdunklung
  final double vignette;

  /// Farbsättigung (1 = normal, <1 = „gebleached“)
  final double saturation;

  /// Weiß-Wash (0..1) als leichte Aufhellung
  final double wash;

  /// Haze-Blur-Layer aktivieren
  final bool enableHaze;

  /// Stärke des Haze (0..1)
  final double hazeStrength;

  /// Neu: „Milkiness“ – kombiniert leichter Blur + Weißfilm (0..1)
  /// Wirkt zusätzlich zu wash/saturation; aktiviert internen soften Layer.
  final double milk;

  const ZenBackdrop({
    super.key,
    required this.asset,
    this.alignment = Alignment.center,
    this.glow = .28,
    this.vignette = .12,
    this.saturation = .95,
    this.wash = .08,
    this.enableHaze = false,
    this.hazeStrength = .12,
    this.milk = .0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Bild mit Sättigungsfilter
        Positioned.fill(
          child: ColorFiltered(
            colorFilter:
                _saturationFilter(saturation.clamp(0.0, 1.0).toDouble()),
            child: ZenSafeImage.asset(
              asset,
              fit: BoxFit.cover,
              alignment: alignment,
            ),
          ),
        ),

        // Wash (Weißschleier)
        if (wash > 0)
          Positioned.fill(
            child: Container(
                color: Colors.white.withValue(alpha: wash.clamp(0.0, 1.0))),
          ),

        // Milk (zusätzliche, weiche „Milchigkeit“)
        if (milk > 0)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 4 + 10 * milk,
                sigmaY: 4 + 10 * milk,
              ),
              child: Container(
                color: Colors.white.withValue(alpha: .04 + .10 * milk),
              ),
            ),
          ),

        // Glow (sanftes Aufhellen in der Mitte)
        if (glow > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: alignment,
                    radius: 1.0,
                    colors: [
                      Colors.white
                          .withValue(alpha: (glow.clamp(0.0, 1.0) * .55)),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

        // Vignette (Randabdunklung)
        if (vignette > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      Colors.transparent,
                      Colors.black,
                    ],
                    stops: [0.65, 1.0],
                  ),
                ).copyWith(
                    // Alpha gemäß Parameter steuern
                    ),
              ),
            ),
          ),

        // Haze (optional: milder Weichzeichner + leichter Weißfilm)
        if (enableHaze)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color:
                    Colors.white.withValue(alpha: hazeStrength.clamp(0.0, 1.0)),
              ),
            ),
          ),
      ],
    );
  }

  // Sättigungs-Matrix (1 = original, 0 = grau)
  ColorFilter _saturationFilter(double s) {
    // Sicherheit & Typkonsistenz
    s = s.clamp(0.0, 1.0);
    final inv = 1.0 - s;

    // Luma-Gewichte gemäß Rec. 709
    const wr = 0.213, wg = 0.715, wb = 0.072;

    final r = wr * inv;
    final g = wg * inv;
    final b = wb * inv;

    return ColorFilter.matrix(<double>[
      r + s,
      g,
      b,
      0,
      0,
      r,
      g + s,
      b,
      0,
      0,
      r,
      g,
      b + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}

/// ======================================================================
/// HEADLINES & QUOTE
/// ======================================================================
class ZenHeadline extends StatelessWidget {
  final String text;
  const ZenHeadline(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.headlineMedium!.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: .2,
          ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class ZenQuoteBanner extends StatelessWidget {
  final String? text;
  const ZenQuoteBanner({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: ZenGlassCard(
        borderRadius: const BorderRadius.all(ZenRadii.m),
        child: Text(
          text ?? 'ZenYourself – Dein Raum für Reflexion.',
          style: ZenTextStyles.body.copyWith(
            fontStyle: FontStyle.italic,
            color: ZenColors.deepSage,
            fontSize: 17,
          ),
        ),
      ),
    );
  }
}

/// ======================================================================
/// PANDA-SPRECHBLASE (mit weichem Tail)
/// ======================================================================
class ZenPandaSpeechBubble extends StatelessWidget {
  final String text;
  final bool fromPanda; // Tail links/rechts
  final EdgeInsets padding;
  final double elevation;
  final bool showTail;

  const ZenPandaSpeechBubble({
    super.key,
    required this.text,
    this.fromPanda = true,
    this.padding = const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
    this.elevation = 8,
    this.showTail = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface.withValue(alpha: .96);

    return AnimatedContainer(
      duration: _animMed,
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(ZenRadii.l),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValue(alpha: .08),
            blurRadius: elevation,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: ZenColors.outline.withValue(alpha: .6)),
      ),
      padding: padding,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Semantics(
            label: 'Panda sagt',
            child: Text(
              text,
              textAlign: TextAlign.left,
              style: ZenTextStyles.body.copyWith(
                fontSize: 17,
                height: 1.44,
                color: ZenColors.deepSage,
              ),
            ),
          ),
          if (showTail)
            Positioned(
              left: fromPanda ? 26 : null,
              right: fromPanda ? null : 26,
              bottom: -14,
              child: CustomPaint(
                painter: _BubbleTailPainter(
                  fill: bg,
                  stroke: ZenColors.outline.withValue(alpha: .6),
                ),
                size: const Size(26, 16),
              ),
            ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color fill;
  final Color stroke;

  _BubbleTailPainter({required this.fill, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final p = Path()
      ..moveTo(0, h * .2)
      ..quadraticBezierTo(w * .35, h * .05, w * .55, h * .45)
      ..quadraticBezierTo(w * .74, h * .80, w, h)
      ..quadraticBezierTo(w * .48, h * .70, 6, h - 2)
      ..quadraticBezierTo(0, h * .65, 0, h * .2)
      ..close();

    final fillPaint = Paint()..color = fill;
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawShadow(p, Colors.black.withValue(alpha: .18), 3, false);
    canvas.drawPath(p, fillPaint);
    canvas.drawPath(p, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.fill != fill || oldDelegate.stroke != stroke;
  }
}

/// ======================================================================
/// BUTTONS — Primary / Outline / Ghost / Danger
/// ======================================================================
class ZenPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final double? width;

  /// NEU (optional): Tooltip-Text für Hover/Long-Press.
  final String? tooltip;

  /// Optional: explizite A11y-Texte (überschreiben Standard)
  final String? semanticsLabel;
  final String? semanticsHint;

  const ZenPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 48, // v6.1
    this.width,
    this.tooltip,
    this.semanticsLabel,
    this.semanticsHint,
  });

  @override
  Widget build(BuildContext context) {
    final buttonChild = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 10),
        ],
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
      ],
    );

    Widget btn = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: ZenColors.cta,
        foregroundColor: Colors.white,
        minimumSize: Size(width ?? 0, height),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(ZenRadii.l),
        ),
        elevation: 1.5,
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      child: buttonChild,
    );

    // Optionaler Tooltip
    if (tooltip != null && tooltip!.trim().isNotEmpty) {
      btn = Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 600),
        child: btn,
      );
    }

    // Optionale explizite Semantics
    if ((semanticsLabel != null && semanticsLabel!.isNotEmpty) ||
        (semanticsHint != null && semanticsHint!.isNotEmpty)) {
      btn = Semantics(
        button: true,
        label: semanticsLabel,
        hint: semanticsHint,
        child: btn,
      );
    }

    return btn;
  }
}

class ZenOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final double? width;
  final Color? color;

  /// A11y (optional)
  final String? semanticsLabel;
  final String? semanticsHint;

  /// Optional: Tooltip (für PinBar/Footer praktisch)
  final String? tooltip;

  const ZenOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 48,
    this.width,
    this.color,
    this.semanticsLabel,
    this.semanticsHint,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZenColors.jade;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: c),
          const SizedBox(width: 10),
        ],
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: c),
        ),
      ],
    );

    Widget btn = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: c.withValue(alpha: .75), width: 1.1),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(ZenRadii.l)),
        minimumSize: Size(width ?? 0, height),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      child: child,
    );

    if ((semanticsLabel != null && semanticsLabel!.isNotEmpty) ||
        (semanticsHint != null && semanticsHint!.isNotEmpty)) {
      btn = Semantics(
        button: true,
        label: semanticsLabel,
        hint: semanticsHint,
        child: btn,
      );
    }

    if (tooltip != null && tooltip!.trim().isNotEmpty) {
      btn = Tooltip(message: tooltip!, child: btn);
    }

    return btn;
  }
}

class ZenGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  /// A11y (optional)
  final String? semanticsLabel;
  final String? semanticsHint;

  const ZenGhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.color,
    this.semanticsLabel,
    this.semanticsHint,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZenColors.jade;

    Widget btn = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.play_arrow_rounded, size: 18, color: c),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, color: c),
          ),
        ],
      ),
    );

    if ((semanticsLabel != null && semanticsLabel!.isNotEmpty) ||
        (semanticsHint != null && semanticsHint!.isNotEmpty)) {
      btn = Semantics(
        button: true,
        label: semanticsLabel,
        hint: semanticsHint,
        child: btn,
      );
    }

    return btn;
  }
}

class ZenGhostButtonDanger extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// A11y (optional)
  final String? semanticsLabel;
  final String? semanticsHint;

  const ZenGhostButtonDanger({
    super.key,
    required this.label,
    this.onPressed,
    this.semanticsLabel,
    this.semanticsHint,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Colors.redAccent),
          ),
        ],
      ),
    );

    if ((semanticsLabel != null && semanticsLabel!.isNotEmpty) ||
        (semanticsHint != null && semanticsHint!.isNotEmpty)) {
      btn = Semantics(
        button: true,
        label: semanticsLabel,
        hint: semanticsHint,
        child: btn,
      );
    }

    return btn;
  }
}

/// ======================================================================
/// ACTION-CHIPS — dezente Varianten
/// ======================================================================
class ZenChipGhost extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const ZenChipGhost({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ActionChip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
      backgroundColor: isDark
          ? Colors.white.withValue(alpha: 0.06)
          : ZenColors.surfaceAlt.withValue(alpha: 0.92),
      labelStyle: Theme.of(context).textTheme.bodyMedium,
      shape: const StadiumBorder(side: BorderSide(color: ZenColors.outline)),
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: ZenSpacing.chipPadH,
        vertical: ZenSpacing.chipPadV,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class ZenChipPrimary extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const ZenChipPrimary(
      {super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    const c = ZenColors.cta;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ActionChip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
      backgroundColor:
          isDark ? c.withValue(alpha: 0.14) : c.withValue(alpha: 0.10),
      labelStyle: Theme.of(context)
          .textTheme
          .bodyMedium!
          .copyWith(color: c, fontWeight: FontWeight.w600),
      shape: StadiumBorder(side: BorderSide(color: c.withValue(alpha: 0.55))),
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: ZenSpacing.chipPadH,
        vertical: ZenSpacing.chipPadV,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class ZenChipOutline extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  const ZenChipOutline(
      {super.key, required this.label, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    final c = (color ?? ZenColors.inkStrong).withValue(alpha: 0.9);
    return ActionChip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
      backgroundColor: Colors.transparent,
      labelStyle: Theme.of(context)
          .textTheme
          .bodyMedium!
          .copyWith(color: c, fontWeight: FontWeight.w600),
      shape: const StadiumBorder(side: BorderSide(color: ZenColors.outline)),
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: ZenSpacing.chipPadH,
        vertical: ZenSpacing.chipPadV,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// ======================================================================
/// ICON CHIP — kompakter Icon-Chip (PinBar/Footer)
/// ======================================================================
class ZenIconChip extends StatelessWidget {
  /// Haupticon (z. B. push_pin, bookmark, mic, send, more_horiz)
  final IconData icon;

  /// Optionales Label (rechts vom Icon). Wenn null → reiner Icon-Chip.
  final String? label;

  /// Tap-Callback
  final VoidCallback onPressed;

  /// Primärfarbe des Chips (Umriss/Text/Icon). Default: ZenColors.jade
  final Color? color;

  /// Visuelle Auswahl (tonaler Fill + stärkere Outline)
  final bool selected;

  /// Dichter Modus (geringere Höhe/Padding; gut für Toolbars)
  final bool dense;

  /// Optionaler Tooltip (für reine Icon-Chips empfohlen)
  final String? tooltip;

  /// A11y (optional)
  final String? semanticsLabel;
  final String? semanticsHint;

  const ZenIconChip({
    super.key,
    required this.icon,
    this.label,
    required this.onPressed,
    this.color,
    this.selected = false,
    this.dense = true,
    this.tooltip,
    this.semanticsLabel,
    this.semanticsHint,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? ZenColors.jade;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = selected
        ? base.withValue(alpha: isDark ? .20 : .12)
        : (isDark ? Colors.white.withValue(alpha: .06) : Colors.transparent);

    final border = selected
        ? base.withValue(alpha: .70)
        : ZenColors.outline.withValue(alpha: .90);

    final labelStyle = Theme.of(context)
        .textTheme
        .bodyMedium!
        .copyWith(color: base, fontWeight: FontWeight.w700);

    final padH = dense ? 10.0 : ZenSpacing.chipPadH.toDouble();
    final padV = dense ? 6.0 : ZenSpacing.chipPadV.toDouble();

    Widget chip = ActionChip(
      onPressed: onPressed,
      backgroundColor: bg,
      elevation: 0,
      visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      shape: StadiumBorder(side: BorderSide(color: border, width: 1.1)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 18 : 19, color: base),
          if (label != null && label!.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(label!, overflow: TextOverflow.ellipsis, style: labelStyle),
          ],
        ],
      ),
    );

    if ((semanticsLabel != null && semanticsLabel!.isNotEmpty) ||
        (semanticsHint != null && semanticsHint!.isNotEmpty)) {
      chip = Semantics(
        button: true,
        label: semanticsLabel,
        hint: semanticsHint,
        child: chip,
      );
    }

    if (tooltip != null && tooltip!.trim().isNotEmpty) {
      chip = Tooltip(message: tooltip!, child: chip);
    }

    return chip;
  }
}

/// ======================================================================
/// CHOICE- & MOOD-CHIPS — für Composer/Timeline
/// ======================================================================
class ZenChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  const ZenChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const green = ZenColors.jade;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilterChip(
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? green : ZenColors.jadeMid,
            ),
      ),
      selected: selected,
      onSelected: onSelected,
      side: BorderSide(
          color: selected ? green.withValue(alpha: .55) : Colors.transparent),
      selectedColor: green.withValue(alpha: .10),
      backgroundColor: isDark
          ? Colors.white.withValue(alpha: .06)
          : Colors.white.withValue(alpha: .14),
      showCheckmark: false,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(
        horizontal: ZenSpacing.chipPadH,
        vertical: ZenSpacing.chipPadV,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class LegacyPandaMoodChip extends StatelessWidget {
  final String mood; // 'Glücklich' | 'Ruhig' | ...
  final bool small;
  const LegacyPandaMoodChip(
      {super.key, required this.mood, this.small = false});

  static String _emoji(String m) {
    switch (m) {
      case 'Glücklich':
        return '😊';
      case 'Traurig':
        return '😔';
      case 'Ruhig':
        return '🧘';
      case 'Wütend':
        return '😡';
      case 'Gestresst':
        return '😱';
      case 'Neutral':
        return '😐';
      default:
        return '📝';
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _emoji(mood);
    final fs = small ? 14.0 : 15.0;
    final es = small ? 18.0 : 20.0;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10, vertical: small ? 4 : 6),
      decoration: BoxDecoration(
        color: ZenColors.sunHaze.withValue(alpha: .20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZenColors.outline.withValue(alpha: .60)),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(e, style: TextStyle(fontSize: es)),
          const SizedBox(width: 6),
          Text(
            mood,
            style: TextStyle(
              fontSize: fs,
              fontWeight: FontWeight.w700,
              color: ZenColors.jadeMid,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// Alias für Alt-Code, der noch ZenMoodChip nutzt
class ZenMoodChip extends LegacyPandaMoodChip {
  const ZenMoodChip({super.key, required String label})
      : super(mood: label, small: false);
  const ZenMoodChip.small({super.key, required String label})
      : super(mood: label, small: true);
}

class PandaMoodRow extends StatelessWidget {
  final List<String> moods; // Reihenfolge, z. B. ['Glücklich','Ruhig',...]
  const PandaMoodRow({super.key, required this.moods});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: moods.map((m) => LegacyPandaMoodChip(mood: m)).toList(),
    );
  }
}

/// ======================================================================
/// LOTTIE & SVG WRAPPER
/// ======================================================================
class ZenLottie extends StatelessWidget {
  final String asset;
  final double? width;
  final double? height;
  final bool repeat;
  final String? semanticsLabel;

  const ZenLottie({
    super.key,
    required this.asset,
    this.width = 180,
    this.height = 180,
    this.repeat = true,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? 'Animierte Zen-Visualisierung',
      child: Lottie.asset(
        asset,
        width: width,
        height: height,
        repeat: repeat,
        fit: BoxFit.contain,
      ),
    );
  }
}

class ZenSVG extends StatelessWidget {
  final String asset;
  final double size;
  final Color? color;
  final String? semanticsLabel;

  const ZenSVG({
    super.key,
    required this.asset,
    this.size = 30,
    this.color,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? 'Zen Symbol',
      child: SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter:
            color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null,
      ),
    );
  }
}

/// ======================================================================
/// INFOBAR — dezente Hinweisleiste + Action
/// ======================================================================
class ZenInfoBar extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? color;

  const ZenInfoBar({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZenColors.jade.withValue(alpha: .08);
    return Container(
      decoration: BoxDecoration(
        color: c,
        borderRadius: const BorderRadius.all(ZenRadii.m),
        border: Border.all(color: ZenColors.jade.withValue(alpha: .20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: ZenColors.jade, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: ZenTextStyles.caption.copyWith(color: ZenColors.jade),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: ZenColors.jade),
              ),
            ),
        ],
      ),
    );
  }
}

/// ======================================================================
/// TEXTFIELD ACTION — Icon + Label, kompakt
/// ======================================================================
class ZenTextFieldAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const ZenTextFieldAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: ZenColors.jade),
      label: Text(
        label,
        style:
            const TextStyle(fontWeight: FontWeight.w700, color: ZenColors.jade),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: const StadiumBorder(),
        side:
            BorderSide(color: ZenColors.jade.withValue(alpha: .55), width: 1.2),
        minimumSize: const Size(0, 42),
      ),
    );
  }
}

/// ======================================================================
/// TOAST / SNACK
/// ======================================================================
class ZenToast {
  static void show(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg), // nutzt SnackBarTheme (weiß auf deep-sage)
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(ZenRadii.m),
        ),
      ),
    );
  }
}

/// ======================================================================
/// VOICE ICON BUTTON
/// ======================================================================
class ZenVoiceButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const ZenVoiceButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Spracheingabe starten',
      button: true,
      child: IconButton(
        tooltip: 'Spracheingabe',
        icon: const Icon(Icons.mic_rounded),
        iconSize: 32,
        color: ZenColors.deepSage,
        onPressed: onPressed,
      ),
    );
  }
}

/// ======================================================================
/// SUBTILES BRANDING-WASSERZEICHEN
/// ======================================================================
class ZenWatermark extends StatelessWidget {
  final double fontSize;
  final double opacity;

  const ZenWatermark({
    super.key,
    this.fontSize = 12,
    this.opacity = .14,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            'ZenYourself',
            style: ZenTextStyles.title.copyWith(
              fontSize: fontSize,
              letterSpacing: 1.2,
              color: ZenColors.deepSage,
            ),
          ),
        ),
      ),
    );
  }
}

/// ======================================================================
/// LEVEL-UP BANNER (Optional)
/// ======================================================================
class ZenLevelUpBanner extends StatelessWidget {
  final int level;
  const ZenLevelUpBanner({required this.level, super.key});

  @override
  Widget build(BuildContext context) {
    return ZenGlassCard(
      padding: const EdgeInsets.symmetric(
          vertical: ZenSpacing.s, horizontal: ZenSpacing.m),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events, color: ZenColors.deepSage, size: 28),
          const SizedBox(width: 12),
          Text(
            'Level $level erreicht!',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  color: ZenColors.deepSage,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// ======================================================================
/// ZENTRIERTES LOADING-OVERLAY — sanfter Dim + Glas-Badge
/// ======================================================================
class ZenCenteredLoadingOverlay extends StatelessWidget {
  final String text;
  final bool ignoreTouches;

  const ZenCenteredLoadingOverlay({
    super.key,
    this.text = 'ZenYourself holt sein Buch heraus …',
    this.ignoreTouches = true,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: ignoreTouches,
        child: Container(
          color: Colors.black.withValue(alpha: 0.08),
          padding: EdgeInsets.only(top: topPad),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              child: ZenGlassCard(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        text,
                        style: const TextStyle(fontSize: 15.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ======================================================================
/// BACKWARDS-COMPAT: ZenCard, ZenDialog, ZenBackground
/// ======================================================================
class ZenCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? width;
  final double? height;
  final bool glass; // aktiviert BackdropBlur
  final bool showWatermark;
  final double elevation;
  final BorderRadius borderRadius;
  final Color? color;

  const ZenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: ZenSpacing.m,
      vertical: ZenSpacing.m,
    ),
    this.margin = EdgeInsets.zero,
    this.width,
    this.height,
    this.glass = false,
    this.showWatermark = false,
    this.elevation = 8,
    this.borderRadius = const BorderRadius.all(ZenRadii.xl), // v6.1 Radius 20
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (glass) {
      return ZenGlassCard(
        margin: margin,
        padding: padding,
        borderRadius: borderRadius,
        child: _CardInner(
          width: width,
          height: height,
          elevation: elevation,
          showWatermark: showWatermark,
          bgColor: null, // ZenGlassCard liefert den Fond
          borderRadius: borderRadius,
          child: child,
        ),
      );
    }

    return Padding(
      padding: margin,
      child: _CardInner(
        width: width,
        height: height,
        elevation: elevation,
        showWatermark: showWatermark,
        bgColor: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: borderRadius,
        child: child,
      ),
    );
  }
}

class _CardInner extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double elevation;
  final bool showWatermark;
  final Color? bgColor;
  final BorderRadius borderRadius;

  const _CardInner({
    required this.child,
    required this.width,
    required this.height,
    required this.elevation,
    required this.showWatermark,
    required this.bgColor,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        boxShadow: ZenShadows.card,
        border: Border.all(
          color: isDark
              ? Colors.white.withValue(alpha: .05)
              : Colors.black.withValue(alpha: .03),
        ),
      ),
      child: child,
    );

    return Stack(
      children: [
        if (showWatermark)
          const Positioned(
            left: 10,
            top: 8,
            child: ZenWatermark(fontSize: 11, opacity: 0.18),
          ),
        card,
      ],
    );
  }
}

class ZenDialog extends StatelessWidget {
  final Widget child;
  const ZenDialog({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ZenColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(ZenRadii.m)),
      child: child,
    );
  }
}

class ZenBackground extends StatelessWidget {
  const ZenBackground({super.key});
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: ZenColors.bg),
    );
  }
}

/// ======================================================================
/// ZEN METRIC TILE — kompakte KPI-Kachel (A11y, konsistente Spacing)
/// ======================================================================
class ZenMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? semanticsLabel;

  const ZenMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Semantics(
      label: semanticsLabel ?? '$label: $value',
      container: true,
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: ZenColors.sage.withValue(alpha: .18),
            radius: 20.5,
            child: Icon(icon, color: ZenColors.sage, size: 20.5),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2.5),
          Text(
            label,
            style: tt.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
