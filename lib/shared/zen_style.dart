// lib/shared/zen_style.dart
//
// ZenYourself — Oxford-Zen Design System (Tokens · Themes · Backdrop · Glass)
// v6.32 — 2025-09-03
// -----------------------------------------------------------------------------
// • Tokens konsolidiert (Deep-Sage primary, ruhige Outlines, Focus-Green).
// • ColorScheme via fromSeed (+ copyWith) → stabil über Flutter-Versionen.
// • Display-Font mit Fallback (ZenKalligrafie → NotoSans).
// • Saubere Button/Input/Chip-Themes, realistische Glass-Shadows.
// • COMPAT: jadeMid/bamboo/cherry Aliases für bestehenden Code erhalten.

import 'dart:ui' as ui show ImageFilter;
import 'package:flutter/material.dart';

/// ==========================================================================
/// COLORS — Oxford-Zen Palette (aus Leitfaden)
/// ==========================================================================
class ZenColors {
  // Surfaces & Canvas
  static const bg         = Color(0xFFF5EFE6); // Zen Beige
  static const surface    = Color(0xFFFFFFFF); // Karten/Dialoge
  static const surfaceAlt = Color(0xFFF7F1E8); // Inputs / leichte Flächen

  // Ink
  static const inkStrong  = Color(0xFF14201B); // ruhiges, warmes Schwarzgrün
  static const ink        = Color(0xFF1F2924);
  static const inkSubtle  = Color(0xFF66726C);

  // Greens
  static const sage       = Color(0xFF6E8B74); // Sekundär
  static const deepSage   = Color(0xFF2F5F49); // CTA/Highlights (Primary)
  static const jade       = Color(0xFF3E7D67); // Akzent/Chips
  // ✅ COMPAT alias (legacy Screens nutzen 'jadeMid')
  static const jadeMid    = sage;

  // CTA Family
  static const cta        = deepSage;
  static const ctaHover   = Color(0xFF275242);
  static const ctaPressed = Color(0xFF214538);

  // Lines / Focus
  static const border  = Color(0xFFD9CCBA);
  static const outline = Color(0xFFC8BBA8);
  static const focus   = Color(0xFF78C2A4);

  // Warm Glow
  static const sunHaze    = Color(0xFFEADFAF);
  static const goldenMist = Color(0xFFE3D28A);

  // Semantic
  static const success = Color(0xFF2E7D4F);
  static const error   = Color(0xFFB00020);
  static const warning = Color(0xFFC5901A);
  static const info    = Color(0xFF2C6AA3);

  // COMPAT / Misc
  static const white   = Color(0xFFFFFFFF);
  static const cloud   = Color(0xFFF0F3F5);
  static const mist    = Color(0xFFEFEFEF);
  static const gold    = Color(0xFFFFD580);
  // ✅ COMPAT extras (weiterhin im Code referenziert)
  static const bamboo  = Color(0xFFA5CBA1);
  static const cherry  = Color(0xFFD7263D);
}

/// ==========================================================================
/// RADII · SPACING · SHADOWS
/// ==========================================================================
class ZenRadii {
  static const s  = Radius.circular(8);
  static const m  = Radius.circular(12);
  static const l  = Radius.circular(16);
  static const xl = Radius.circular(20);
}

class ZenSpacing {
  static const xxs = 4.0;
  static const xs  = 8.0;
  static const s   = 12.0;
  static const m   = 16.0;
  static const l   = 20.0;
  static const xl  = 24.0;
  static const xxl = 32.0;

  // COMPAT
  static const padButton = 14.0;
  static const padBubble = 12.0;

  // Chips/Moods
  static const chipPadV = 6.0;
  static const chipPadH = 12.0;
}

class ZenShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x14000000), // ~8%
      blurRadius: 14,
      offset: Offset(0, 5),
    ),
  ];

  static const BoxShadow glow = BoxShadow(
    color: Color(0x12000000), // ~7%
    blurRadius: 18,
    offset: Offset(0, 6),
  );
}

/// ==========================================================================
/// TYPOGRAPHY
/// ==========================================================================
class ZenTypography {
  static const body = TextStyle(
    fontFamily: 'NotoSans',
    fontSize: 16,
    height: 24 / 16,
    color: ZenColors.ink,
  );

  static const title = TextStyle(
    fontFamily: 'NotoSans',
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
    color: ZenColors.inkStrong,
  );

  /// Display/Brand Headline (mit Fallback)
  static const display = TextStyle(
    fontFamily: 'ZenKalligrafie',
    fontFamilyFallback: ['NotoSans'],
    fontWeight: FontWeight.w800,
    fontSize: 28,
    color: ZenColors.inkStrong,
  );
}

/// ==========================================================================
/// MOTION — Curves & Durations
/// ==========================================================================
class ZenMotion {
  static const Duration short = Duration(milliseconds: 160);
  static const Duration med   = Duration(milliseconds: 240);
  static const Duration long  = Duration(milliseconds: 340);

  static const Curve ease     = Curves.easeOutCubic;
  static const Curve inOut    = Curves.fastOutSlowIn;
  static const Curve fade     = Curves.linearToEaseOut;
}

const animShort = ZenMotion.short;
const animMed   = ZenMotion.med;
const animLong  = ZenMotion.long;

const zenMobileMaxWidth = 520.0;
const zenTabletMaxWidth = 768.0;

/// ==========================================================================
/// THEMES (Light/Dark)
/// ==========================================================================
ThemeData zenLightTheme() => _buildTheme(brightness: Brightness.light);
ThemeData zenDarkTheme()  => _buildTheme(brightness: Brightness.dark);

ThemeData _buildTheme({required Brightness brightness}) {
  final bool isDark = brightness == Brightness.dark;

  // Dark Palette
  const bgDark         = Color(0xFF0F1211);
  const surfaceDark    = Color(0xFF151917);
  const surfaceAltDark = Color(0xFF1B201D);
  const inkDark        = Color(0xFFE6E4E0);
  const inkStrongDark  = Color(0xFFF2F2F0);
  const borderDark     = Color(0xFF2A2E2B);
  const outlineDark    = Color(0xFF3A403C);

  // Base scheme from seed → dann Tokens anpassen
  final base = ColorScheme.fromSeed(
    seedColor: ZenColors.deepSage,
    brightness: brightness,
  );

  final colorScheme = base.copyWith(
    primary:      ZenColors.cta,
    onPrimary:    Colors.white,
    secondary:    ZenColors.jade,
    onSecondary:  isDark ? bgDark : ZenColors.inkStrong,
    surface:      isDark ? surfaceDark : ZenColors.surface,
    onSurface:    isDark ? inkDark : ZenColors.ink,
    background:   isDark ? bgDark : ZenColors.bg,
    onBackground: isDark ? inkStrongDark : ZenColors.inkStrong,
    error:        ZenColors.error,
    onError:      Colors.white,
    tertiary:     ZenColors.cta,
    onTertiary:   Colors.white,
    outline:      isDark ? outlineDark : ZenColors.outline,
    surfaceTint:  ZenColors.cta,
  );

  final appBar = AppBarTheme(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    foregroundColor: isDark ? ZenColors.jade : ZenColors.inkStrong,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: ZenTypography.display.copyWith(
      color: isDark ? ZenColors.jade : ZenColors.inkStrong,
    ),
    iconTheme: IconThemeData(color: isDark ? ZenColors.jade : ZenColors.inkStrong),
  );

  final elevated = ElevatedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.pressed)) return ZenColors.ctaPressed;
        if (states.contains(MaterialState.hovered))  return ZenColors.ctaHover;
        return ZenColors.cta;
      }),
      foregroundColor: const MaterialStatePropertyAll(Colors.white),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      minimumSize: const MaterialStatePropertyAll(Size(0, 52)),
      elevation: const MaterialStatePropertyAll(1.5),
      shape: const MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(ZenRadii.l)),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  final outlined = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ZenColors.jade,
      side: BorderSide(color: isDark ? outlineDark : ZenColors.outline),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      minimumSize: const Size(0, 48),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(ZenRadii.l)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  final textButton = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: ZenColors.jade,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: const Size(0, 40),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  final input = InputDecorationTheme(
    filled: true,
    fillColor: isDark ? surfaceAltDark : ZenColors.surfaceAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(ZenRadii.l),
      borderSide: BorderSide(color: ZenColors.outline),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(ZenRadii.l),
      borderSide: BorderSide(color: ZenColors.focus, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(ZenRadii.l),
      borderSide: BorderSide(color: isDark ? outlineDark : ZenColors.outline),
    ),
  );

  final chip = ChipThemeData(
    backgroundColor: isDark ? surfaceAltDark : ZenColors.surfaceAlt,
    selectedColor: ZenColors.jade.withOpacity(.18),
    labelStyle: TextStyle(color: isDark ? inkDark : ZenColors.ink),
    side: BorderSide(color: isDark ? borderDark : ZenColors.border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  final snack = SnackBarThemeData(
    backgroundColor: ZenColors.deepSage,
    contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.standard,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.background,
    fontFamily: 'NotoSans',

    appBarTheme: appBar,
    textTheme: TextTheme(
      bodyMedium: ZenTypography.body.copyWith(color: colorScheme.onSurface),
      titleMedium: ZenTypography.title.copyWith(color: colorScheme.onBackground),
      headlineMedium: ZenTypography.display.copyWith(color: colorScheme.onBackground),
      labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),

    elevatedButtonTheme: elevated,
    outlinedButtonTheme: outlined,
    textButtonTheme: textButton,
    inputDecorationTheme: input,
    chipTheme: chip,
    dividerColor: isDark ? borderDark : ZenColors.border,
    snackBarTheme: snack,

    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: ZenColors.jade,
      selectionColor: Color(0x223E7D67), // Jade ~13%
      selectionHandleColor: ZenColors.jade,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(ZenRadii.l),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: (isDark ? surfaceAltDark : ZenColors.surface).withOpacity(.92),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: ZenRadii.xl),
      ),
    ),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS:     CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS:   FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux:   FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// ==========================================================================
/// GRADIENTS & OVERLAYS
/// ==========================================================================
class ZenGradients {
  static const LinearGradient screen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ZenColors.bg, ZenColors.white, ZenColors.cloud],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient button = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ZenColors.cta, ZenColors.ctaHover],
  );
}

class ZenOverlays {
  static Widget topSoftFade({double strength = .12}) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(strength),
                Colors.transparent,
                Colors.black.withOpacity(.08),
              ],
              stops: const [0, .28, 1],
            ),
          ),
        ),
      ),
    );
  }

  static BoxDecoration radialGlow({
    Offset center = const Offset(.5, .35),
    double opacity = .32,
  }) {
    return BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(center.dx, center.dy),
        radius: .9,
        colors: [ZenColors.goldenMist.withOpacity(opacity), Colors.transparent],
        stops: const [.0, 1],
      ),
    );
  }
}

/// ==========================================================================
/// BACKDROP — Artwork mit Glow/Vignette/Haze/Sättigung/Wash
/// ==========================================================================
class ZenBackdrop extends StatelessWidget {
  final String asset;
  final Alignment alignment;

  final bool fixedContain;
  final double artBaseWidth;
  final double artBaseHeight;

  // Effekte
  final double vignette; // 0..1
  final double glow;     // 0..1
  final bool enableHaze;
  final double hazeStrength; // 0..1
  final bool dimRight;
  final double dimRightStrength; // 0..1

  // Globale Entsättigung & Wash
  final double saturation; // 1.0 = original … 0.0 = grau
  final double wash;       // 0.0 = aus … 0.12 = leichtes Weiß-Wash

  const ZenBackdrop({
    super.key,
    required this.asset,
    this.alignment = Alignment.center,
    this.fixedContain = false,
    this.artBaseWidth = 1440,
    this.artBaseHeight = 810,
    this.vignette = .14,
    this.glow = .34,
    this.enableHaze = false,
    this.hazeStrength = .12,
    this.dimRight = false,
    this.dimRightStrength = .10,
    this.saturation = 1.0,
    this.wash = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    Widget _applySaturation(Widget child) {
      if (saturation >= 0.999) return child;
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
        child: child,
      );
    }

    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(decoration: BoxDecoration(gradient: ZenGradients.screen)),

      // Blur-Fill als Unterfütterung
      _applySaturation(
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.white.withOpacity(0.05), BlendMode.srcATop),
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),

      // Hauptbild
      _applySaturation(
        fixedContain
            ? _ContainArtwork(
                asset: asset,
                baseWidth: artBaseWidth,
                baseHeight: artBaseHeight,
                alignment: alignment,
              )
            : Image.asset(
                asset,
                fit: BoxFit.cover,
                alignment: alignment,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
      ),

      if (wash > 0) IgnorePointer(child: Container(color: Colors.white.withOpacity(wash))),

      // Gold-Grün Glow
      IgnorePointer(
        child: Container(
          decoration: ZenOverlays.radialGlow(center: const Offset(.50, -.05), opacity: glow),
        ),
      ),

      // Haze (optional)
      if (enableHaze)
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ZenColors.white.withOpacity(hazeStrength * 1.0),
                  ZenColors.surfaceAlt.withOpacity(hazeStrength * 0.75),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),

      // Vignette
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.15,
              colors: [Colors.transparent, Colors.black.withOpacity(vignette)],
              stops: const [0.78, 1.0],
            ),
          ),
        ),
      ),

      // Rechte Abdunklung (optional)
      if (dimRight)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    Colors.black.withOpacity(dimRightStrength),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.22],
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  // Rec.709 Luma Sättigungs-Matrix
  static List<double> _saturationMatrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final a = (1 - s);
    return <double>[
      r * a + s, g * a,     b * a,     0, 0,
      r * a,     g * a + s, b * a,     0, 0,
      r * a,     g * a,     b * a + s, 0, 0,
      0,         0,         0,         1, 0,
    ];
  }
}

/// Artwork, das nie über die Basisgröße hinaus skaliert und immer komplett sichtbar bleibt.
class _ContainArtwork extends StatelessWidget {
  final String asset;
  final double baseWidth;
  final double baseHeight;
  final Alignment alignment;

  const _ContainArtwork({
    required this.asset,
    required this.baseWidth,
    required this.baseHeight,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final scale = _min3(
          c.maxWidth / baseWidth,
          c.maxHeight / baseHeight,
          1.0, // nicht über Originalgröße hinaus
        );
        final w = baseWidth * scale;
        final h = baseHeight * scale;

        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              alignment: alignment,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  double _min3(double a, double b, double c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
  }
}

/// ==========================================================================
/// GLASS PRIMITIVES
/// ==========================================================================
class ZenGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final double blurSigmaX;
  final double blurSigmaY;

  /// Lichtverlauf (0..1)
  final double topOpacity;
  final double bottomOpacity;
  final double borderOpacity;

  /// Legacy-Aliase (Back-Compat)
  final double? gradientTopOpacity;
  final double? gradientBottomOpacity;

  const ZenGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = const BorderRadius.all(ZenRadii.xl),
    this.blurSigmaX = 24,
    this.blurSigmaY = 24,
    this.topOpacity = 0.26,
    this.bottomOpacity = 0.08,
    this.borderOpacity = 0.18,
    this.gradientTopOpacity,
    this.gradientBottomOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedTopOpacity    = gradientTopOpacity ?? topOpacity;
    final resolvedBottomOpacity = gradientBottomOpacity ?? bottomOpacity;

    return Container(
      margin: margin,
      decoration: const BoxDecoration(), // sauberes Hit-Testing
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigmaX, sigmaY: blurSigmaY),
          child: Container(
            padding: padding ??
                const EdgeInsets.symmetric(
                  horizontal: ZenSpacing.l,
                  vertical: ZenSpacing.l,
                ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ZenColors.surface.withOpacity(resolvedTopOpacity),
                  ZenColors.surface.withOpacity(resolvedBottomOpacity),
                ],
              ),
              borderRadius: borderRadius,
              border: Border.all(
                color: Colors.white.withOpacity(borderOpacity),
                width: 1.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000), // ~8%
                  blurRadius: 18,
                  spreadRadius: 1.2,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ZenGlassInput extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final double blurSigmaX;
  final double blurSigmaY;

  const ZenGlassInput({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(ZenRadii.l),
    this.blurSigmaX = 24,
    this.blurSigmaY = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigmaX, sigmaY: blurSigmaY),
        child: Container(
          padding: padding ?? const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x26FFFFFF), // ~0.15
                Color(0x1AFFFFFF), // ~0.10
              ],
            ),
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withOpacity(0.16), width: 1.0),
            boxShadow: const [ZenShadows.glow],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// ==========================================================================
/// SMALL UI HELPERS
/// ==========================================================================
class ZenDivider extends StatelessWidget {
  final double height;
  final double opacity;
  const ZenDivider({super.key, this.height = 16, this.opacity = .28});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: height,
      thickness: 1,
      color: ZenColors.outline.withOpacity(opacity),
    );
  }
}

/// Badge-Pille (z. B. „Reflexion“)
class ZenBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  const ZenBadge({super.key, required this.label, this.icon});

  /// Bequemer Named-Ctor
  const ZenBadge.icon({Key? key, required String label, required IconData icon})
      : this(key: key, label: label, icon: icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      decoration: BoxDecoration(
        color: ZenColors.mist.withOpacity(.80),
        borderRadius: const BorderRadius.all(ZenRadii.s),
        border: Border.all(color: ZenColors.jadeMid.withOpacity(.18)),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: ZenColors.jadeMid),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: ZenColors.jade,
            ),
          ),
        ],
      ),
    );
  }
}

/// ==========================================================================
/// CONTEXT EXTENSIONS · TEXTSTYLES (Compat)
/// ==========================================================================
extension ZenContext on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme  get tt => Theme.of(this).textTheme;
  EdgeInsets get screenPad => const EdgeInsets.fromLTRB(16, 16, 16, 24);
}

class ZenTextStyles {
  static final h1       = ZenTypography.display.copyWith(fontSize: 28);
  static final h2       = ZenTypography.title.copyWith(fontSize: 22);
  static final h3       = ZenTypography.title.copyWith(fontSize: 18, fontWeight: FontWeight.w700);
  static const title    = ZenTypography.title;
  static final subtitle = ZenTypography.body.copyWith(fontSize: 14.5, color: ZenColors.inkSubtle);
  static const body     = ZenTypography.body;
  static final caption  = ZenTypography.body.copyWith(fontSize: 12.5, color: ZenColors.inkSubtle);
  static const button   = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white);

  static final sectionHeader = h3.copyWith(letterSpacing: .2);
  static final meta = caption.copyWith(fontStyle: FontStyle.italic);
}

/// ==========================================================================
/// FORMAT — Datum/Zeit/Helfer (ohne intl-Abhängigkeit)
// ==========================================================================
class ZenFormat {
  static String two(int n) => n.toString().padLeft(2, '0');

  /// 24h-Zeit "HH:MM"
  static String time(DateTime dt) {
    final l = dt.toLocal();
    return '${two(l.hour)}:${two(l.minute)}';
  }

  /// Datum "TT.MM.JJJJ"
  static String date(DateTime dt) {
    final l = dt.toLocal();
    return '${two(l.day)}.${two(l.month)}.${l.year}';
  }

  /// "Heute" / "Gestern" / "TT.MM.JJJJ"
  static String dayLabel(DateTime day, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toLocal();
    final d = day.toLocal();
    final today = DateTime(n.year, n.month, n.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final onlyDay = DateTime(d.year, d.month, d.day);

    if (onlyDay == today) return 'Heute';
    if (onlyDay == yesterday) return 'Gestern';
    return date(d);
  }

  /// Optional: Mood → Emoji
  static String moodEmoji(String mood) {
    switch (mood) {
      case 'Glücklich': return '😊';
      case 'Ruhig':     return '🧘';
      case 'Neutral':   return '😐';
      case 'Traurig':   return '😔';
      case 'Gestresst': return '😱';
      case 'Wütend':    return '😡';
      default:          return '📝';
    }
  }
}
