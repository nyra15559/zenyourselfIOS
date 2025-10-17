// lib/shared/zen_style.dart
//
// ZenYourself — Oxford-Zen Design System (Tokens · Themes · Backdrop · Glass)
// v8.2 — 2025-10-16 · Deprecation-clean (withValues), SafeAssets, ZenAppBar compat
// -----------------------------------------------------------------------------
// • Keine Breaking Changes: gleiche öffentlichen Klassen/Signaturen.
// • Deprecation-Fix: überall .withValues(alpha: x) statt .withOpacity(x).
// • Safe-Assets: _SafeAssetImage rendert still, wenn Asset fehlt (kein Crash).
// • ZenAppBar-Wrapper: behebt "hidden name 'ZenAppBar'"-Importwarnungen.
// • Vollständiges M3-Theme (AA-kontrastsicher), warmes Dark-Theme.
// • NEU: questionStyle/mirrorStyle/answerStyle für Reflection-UI.

import 'dart:ui' as ui show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// ==========================================================================
// COMPAT — einheitlich `withValues(alpha: …)` auf allen SDKs
// ==========================================================================
extension ZenColorCompat on Color {
  /// Setzt nur den Alpha-Kanal (0.0–1.0). RGB bleiben unverändert.
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final a01 = alpha.clamp(0.0, 1.0) as double;
    // Robust gegenüber älteren/neuen Flutter-Versionen:
    // nutze die stabilen Komponenten red/green/blue (0..255).
    return Color.fromARGB(
      (a01 * 255).round(),
      red,
      green,
      blue,
    );
  }
}

/// Kleiner Helper: Alpha 0.0–1.0 (breit kompatibel)
double colorAlpha01(Color c) => c.alpha / 255.0;

/// ==========================================================================
/// PUBLIC API COMPAT — ZenAppBar (für alte Importe `show ZenAppBar`)
/// ==========================================================================
class ZenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  const ZenAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      title: title,
      centerTitle: centerTitle,
      leading: leading,
      actions: actions,
      elevation: 0,
      foregroundColor: cs.primary,
    );
  }
}

/// ==========================================================================
/// COLORS — Oxford-Zen Palette (UI-Tokens)
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
  static const jadeMid    = sage;              // COMPAT alias

  // CTA Family
  static const cta        = deepSage;
  static const ctaHover   = Color(0xFF275242);
  static const ctaPressed = Color(0xFF214538);
  static const ctaDisabled= Color(0xFF7FA190);

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

  // Misc / COMPAT
  static const white   = Color(0xFFFFFFFF);
  static const cloud   = Color(0xFFF0F3F5);
  static const mist    = Color(0xFFEFEFEF);
  static const gold    = Color(0xFFFFD580);
  static const bamboo  = Color(0xFFA5CBA1);
  static const cherry  = Color(0xFFD7263D);
}

/// ==========================================================================
/// RADII · SPACING · SHADOWS — Layout-Tokens
/// ==========================================================================
class ZenRadii {
  static const s   = Radius.circular(8);
  static const m   = Radius.circular(12);
  static const l   = Radius.circular(16);
  static const xl  = Radius.circular(20);
  static const xxl = Radius.circular(28);
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
    BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 5)),
  ];

  static const BoxShadow glow = BoxShadow(
    color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 6),
  );

  static const List<BoxShadow> popover = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

/// ==========================================================================
/// TYPOGRAPHY — Grundsystem
/// ==========================================================================
class ZenTypography {
  static const body = TextStyle(
    fontFamily: 'NotoSans',
    fontSize: 16,
    height: 24 / 16,
    letterSpacing: 0.1,
    color: ZenColors.ink,
  );

  static const title = TextStyle(
    fontFamily: 'NotoSans',
    fontSize: 20,
    height: 26 / 20,
    letterSpacing: 0.1,
    fontWeight: FontWeight.w600,
    color: ZenColors.inkStrong,
  );

  /// Display/Brand Headline (mit Fallback)
  static const display = TextStyle(
    fontFamily: 'ZenKalligrafie',
    fontFamilyFallback: ['NotoSans'],
    fontWeight: FontWeight.w800,
    fontSize: 28,
    height: 32 / 28,
    letterSpacing: 0.0,
    color: ZenColors.inkStrong,
  );
}

/// Exporte für Reflection-UI (ruhig & konsistent)
class ZenReflectionText {
  static final questionStyle = ZenTypography.title.copyWith(
    fontStyle: FontStyle.normal,
    fontWeight: FontWeight.w600,
    color: ZenColors.inkStrong,
    height: 1.32,
  );

  static final mirrorStyle = ZenTypography.body.copyWith(
    fontWeight: FontWeight.w500,
    color: ZenColors.ink.withValues(alpha: .87),
    height: 1.35,
  );

  static final answerStyle = ZenTypography.body.copyWith(
    fontWeight: FontWeight.w600,
    color: ZenColors.inkStrong,
    height: 1.35,
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
/// THEMES (Light/Dark) — vollständige, stabile ThemeData-Konfiguration
/// ==========================================================================
ThemeData zenLightTheme() => _buildTheme(brightness: Brightness.light);
ThemeData zenDarkTheme()  => _buildTheme(brightness: Brightness.dark);

ThemeData _buildTheme({required Brightness brightness}) {
  final bool isDark = brightness == Brightness.dark;

  // Dark Palette (ruhig, nicht pechschwarz)
  const bgDark         = Color(0xFF0F1211);
  const surfaceDark    = Color(0xFF151917);
  const surfaceAltDark = Color(0xFF1B201D);
  const inkDark        = Color(0xFFE6E4E0);
  const borderDark     = Color(0xFF2A2E2B);
  const outlineDark    = Color(0xFF3A403C);

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
    error:        ZenColors.error,
    onError:      Colors.white,
    tertiary:     ZenColors.cta,
    onTertiary:   Colors.white,
    outline:      isDark ? outlineDark : ZenColors.outline,
    surfaceTint:  ZenColors.cta,
  );

  // AppBar
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

  // Buttons
  final elevated = ElevatedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return ZenColors.ctaDisabled;
        if (states.contains(WidgetState.pressed))  return ZenColors.ctaPressed;
        if (states.contains(WidgetState.hovered))  return ZenColors.ctaHover;
        return ZenColors.cta;
      }),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
      elevation: const WidgetStatePropertyAll(1.5),
      shape: const WidgetStatePropertyAll(
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

  // IconButtons
  final iconButton = IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: isDark ? inkDark : ZenColors.ink,
      minimumSize: const Size(40, 40),
      padding: const EdgeInsets.all(8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  // Inputs
  final input = InputDecorationTheme(
    filled: true,
    fillColor: isDark ? surfaceAltDark : ZenColors.surfaceAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    hintStyle: TextStyle(
      color: (isDark ? inkDark : ZenColors.ink).withValues(alpha: .55),
    ),
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

  // Chips
  final chip = ChipThemeData(
    backgroundColor: isDark ? surfaceAltDark : ZenColors.surfaceAlt,
    selectedColor: ZenColors.jade.withValues(alpha: .18),
    labelStyle: TextStyle(color: isDark ? inkDark : ZenColors.ink),
    side: BorderSide(color: isDark ? borderDark : ZenColors.border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(
      horizontal: ZenSpacing.chipPadH,
      vertical: ZenSpacing.chipPadV,
    ),
  );

  // Lists / Tiles
  final listTile = ListTileThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    iconColor: isDark ? inkDark : ZenColors.ink,
    textColor: isDark ? inkDark : ZenColors.ink,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    tileColor: (isDark ? surfaceAltDark : ZenColors.surface).withValues(alpha: .6),
  );

  // Tabs
  const tabTheme = TabBarThemeData(
    indicatorSize: TabBarIndicatorSize.label,
    dividerColor: Colors.transparent,
    labelPadding: EdgeInsets.symmetric(horizontal: 8),
  );

  // Tooltips
  final tooltip = TooltipThemeData(
    decoration: BoxDecoration(
      color: isDark ? surfaceAltDark : ZenColors.surface,
      borderRadius: BorderRadius.circular(10),
      boxShadow: ZenShadows.popover,
      border: Border.all(color: isDark ? outlineDark : ZenColors.outline),
    ),
    textStyle: TextStyle(
      color: isDark ? inkDark : ZenColors.ink,
      fontWeight: FontWeight.w600,
    ),
    waitDuration: const Duration(milliseconds: 350),
    showDuration: const Duration(milliseconds: 2400),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );

  // Scrollbar
  final scrollbar = ScrollbarThemeData(
    thickness: const WidgetStatePropertyAll(4.0),
    radius: const Radius.circular(6),
    thumbVisibility: const WidgetStatePropertyAll(false),
    thumbColor: WidgetStatePropertyAll(
      (isDark ? ZenColors.jade : ZenColors.ink).withValues(alpha: .25),
    ),
  );

  // Toggles
  final switchTheme = SwitchThemeData(
    trackColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.selected)) {
        return ZenColors.jade.withValues(alpha: .45);
      }
      return (isDark ? outlineDark : ZenColors.outline).withValues(alpha: .6);
    }),
    thumbColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.selected)) return ZenColors.jade;
      return isDark ? inkDark : ZenColors.surface;
    }),
  );

  final checkboxTheme = CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.selected)) return ZenColors.jade;
      return isDark ? outlineDark : ZenColors.outline;
    }),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  );

  final radioTheme = RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.selected)) return ZenColors.jade;
      return isDark ? outlineDark : ZenColors.outline;
    }),
  );

  // SnackBar
  final snack = SnackBarThemeData(
    backgroundColor: ZenColors.deepSage,
    contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  // Bottom Sheet
  final bottomSheet = BottomSheetThemeData(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    modalBackgroundColor: (isDark ? surfaceAltDark : ZenColors.surface).withValues(alpha: .92),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: ZenRadii.xl),
    ),
  );

  // Cards / Dividers
  final cardTheme = CardThemeData(
    color: (isDark ? surfaceAltDark : ZenColors.surface).withValues(alpha: .88),
    elevation: 0,
    margin: const EdgeInsets.all(0),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(ZenRadii.l)),
    shadowColor: Colors.black.withValues(alpha: .08),
    surfaceTintColor: Colors.transparent,
  );

  final dividerTheme = DividerThemeData(
    color: isDark ? borderDark : ZenColors.border,
    thickness: 1,
    space: 16,
  );

  // FAB / Bottom Nav
  const fabTheme = FloatingActionButtonThemeData(
    elevation: 0, highlightElevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(ZenRadii.l)),
  );

  final bottomNavTheme = BottomNavigationBarThemeData(
    backgroundColor: (isDark ? surfaceDark : ZenColors.surface).withValues(alpha: .92),
    selectedItemColor: ZenColors.cta,
    unselectedItemColor: (isDark ? inkDark : ZenColors.ink).withValues(alpha: .65),
    showUnselectedLabels: false, type: BottomNavigationBarType.fixed, elevation: 0,
  );

  // ThemeData
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.standard,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isDark ? bgDark : colorScheme.surface,
    fontFamily: 'NotoSans',

    appBarTheme: appBar,
    textTheme: TextTheme(
      bodyMedium: ZenTypography.body.copyWith(color: colorScheme.onSurface),
      titleMedium: ZenTypography.title.copyWith(color: colorScheme.onSurface),
      headlineMedium: ZenTypography.display.copyWith(color: colorScheme.onSurface),
      labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),

    elevatedButtonTheme: elevated,
    outlinedButtonTheme: outlined,
    textButtonTheme: textButton,
    inputDecorationTheme: input,
    chipTheme: chip,
    iconButtonTheme: iconButton,
    listTileTheme: listTile,
    tabBarTheme: tabTheme,
    tooltipTheme: tooltip,
    scrollbarTheme: scrollbar,
    switchTheme: switchTheme,
    checkboxTheme: checkboxTheme,
    radioTheme: radioTheme,
    cardTheme: cardTheme,
    dividerTheme: dividerTheme,
    floatingActionButtonTheme: fabTheme,
    bottomNavigationBarTheme: bottomNavTheme,
    snackBarTheme: snack,
    bottomSheetTheme: bottomSheet,

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
/// GRADIENTS & OVERLAYS — visuelle Layer (screen/button, Glow/Haze/Fades)
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
                Colors.black.withValues(alpha: strength),
                Colors.transparent,
                Colors.black.withValues(alpha: .08),
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
        colors: [ZenColors.goldenMist.withValues(alpha: opacity), Colors.transparent],
        stops: const [.0, 1],
      ),
    );
  }
}

/// ==========================================================================
/// ART ASSETS & BACKDROP PRESETS (optional, dank Safe-Loader niemals fatal)
/// ==========================================================================
class ZenArt {
  // Passe diese Pfade an dein Projekt an (oder ignoriere sie einfach).
  static const start      = 'assets/bg/bg_start.png';
  static const menu       = 'assets/bg/bg_menu.png';
  static const reflection = 'assets/bg/bg_reflection.png';
  static const journal    = 'assets/bg/bg_journal.png';

  static const baseW = 2560.0;
  static const baseH = 1440.0;

  // Laterne rechts (ruhige, konsistente Position)
  static const alignRightSafe = Alignment(0.20, 0.0);
}

class ZenBackdropPresets {
  static Widget start({String? art}) => ZenBackdrop(
        asset: art ?? ZenArt.start,
        alignment: ZenArt.alignRightSafe,
        artBaseWidth: ZenArt.baseW,
        artBaseHeight: ZenArt.baseH,
        vignette: .10, glow: .24, enableHaze: true, hazeStrength: .10,
        dimRight: false, saturation: .98, wash: .06,
      );

  static Widget menu({String? art}) => ZenBackdrop(
        asset: art ?? ZenArt.menu,
        alignment: ZenArt.alignRightSafe,
        artBaseWidth: ZenArt.baseW,
        artBaseHeight: ZenArt.baseH,
        vignette: .12, glow: .22, enableHaze: true, hazeStrength: .08,
        dimRight: false, saturation: .96, wash: .04,
      );

  static Widget reflection({String? art}) => ZenBackdrop(
        asset: art ?? ZenArt.reflection,
        alignment: ZenArt.alignRightSafe,
        artBaseWidth: ZenArt.baseW,
        artBaseHeight: ZenArt.baseH,
        vignette: .14, glow: .20, enableHaze: true, hazeStrength: .12,
        dimRight: false, saturation: .94, wash: .03,
      );

  static Widget journal({String? art}) => ZenBackdrop(
        asset: art ?? ZenArt.journal,
        alignment: ZenArt.alignRightSafe,
        artBaseWidth: ZenArt.baseW,
        artBaseHeight: ZenArt.baseH,
        vignette: .10, glow: .26, enableHaze: true, hazeStrength: .10,
        dimRight: false, saturation: .98, wash: .05,
      );
}

/// ==========================================================================
/// BACKDROP — Artwork mit Glow/Vignette/Haze/Sättigung/Wash (safe)
// ==========================================================================
class ZenBackdrop extends StatelessWidget {
  /// Pfad zum Asset (PNG/JPG/WebP).
  final String asset;

  /// Bildausrichtung im Container (bei Cover/Contain).
  final Alignment alignment;

  /// Wenn true, wird nie über die Basisgröße hinaus skaliert (letterboxed).
  final bool fixedContain;

  /// Referenzgröße des Artworks (für fixedContain).
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
    Widget applySaturation(Widget child) {
      if (saturation >= 0.999) return child;
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
        child: child,
      );
    }

    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(decoration: BoxDecoration(gradient: ZenGradients.screen)),

      // Blur-Fill als Unterfütterung
      applySaturation(
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.white.withValues(alpha: 0.05), BlendMode.srcATop),
            child: _SafeAssetImage(
              path: asset, fit: BoxFit.cover, alignment: Alignment.center,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
      ),

      // Hauptbild (Contain optional)
      applySaturation(
        fixedContain
            ? _ContainArtwork(
                asset: asset,
                baseWidth: artBaseWidth,
                baseHeight: artBaseHeight,
                alignment: alignment,
              )
            : _SafeAssetImage(
                path: asset, fit: BoxFit.cover, alignment: alignment,
                filterQuality: FilterQuality.high,
              ),
      ),

      if (wash > 0) IgnorePointer(child: Container(color: Colors.white.withValues(alpha: wash))),

      // Gold-Grün Glow
      IgnorePointer(child:
        Container(decoration: ZenOverlays.radialGlow(center: const Offset(.50, -.05), opacity: glow)),
      ),

      // Haze (optional)
      if (enableHaze)
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  ZenColors.white.withValues(alpha: hazeStrength * 1.0),
                  ZenColors.surfaceAlt.withValues(alpha: hazeStrength * 0.75),
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
              center: Alignment.center, radius: 1.15,
              colors: [Colors.transparent, Colors.black.withValues(alpha: vignette)],
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
                  begin: Alignment.centerRight, end: Alignment.centerLeft,
                  colors: [Colors.black.withValues(alpha: dimRightStrength), Colors.transparent],
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

/// Safe-Loader für Assets: rendert still, wenn Asset fehlt (kein Fehlerlog-Spam).
class _SafeAssetImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;

  static final Map<String, bool> _cache = {};

  const _SafeAssetImage({
    required this.path,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
  });

  static Future<bool> _exists(String p) async {
    if (_cache.containsKey(p)) return _cache[p]!;
    try {
      await rootBundle.load(p);
      _cache[p] = true;
    } catch (_) {
      _cache[p] = false;
    }
    return _cache[p]!;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _exists(path),
      builder: (_, snap) {
        final ok = snap.data == true;
        if (!ok) return const SizedBox.shrink();
        return Image.asset(
          path, fit: fit, alignment: alignment, filterQuality: filterQuality,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      },
    );
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
          1.0,
        );
        final w = baseWidth * scale;
        final h = baseHeight * scale;

        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: _SafeAssetImage(
              path: asset,
              fit: BoxFit.contain,
              alignment: alignment,
              filterQuality: FilterQuality.high,
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
/// GLASS PRIMITIVES — generische Glas-Bausteine (UI-unabhängig)
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
                const EdgeInsets.symmetric(horizontal: ZenSpacing.l, vertical: ZenSpacing.l),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  ZenColors.surface.withValues(alpha: resolvedTopOpacity),
                  ZenColors.surface.withValues(alpha: resolvedBottomOpacity),
                ],
              ),
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: borderOpacity), width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000), blurRadius: 18, spreadRadius: 1.2, offset: Offset(0, 5),
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
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0x26FFFFFF), Color(0x1AFFFFFF)],
            ),
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.0),
            boxShadow: const [ZenShadows.glow],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// ==========================================================================
/// SMALL UI HELPERS — Divider/Badges/TextStyles/Format
/// ==========================================================================
class ZenDivider extends StatelessWidget {
  final double height;
  final double opacity;
  const ZenDivider({super.key, this.height = 16, this.opacity = .28});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: height, thickness: 1, color: ZenColors.outline.withValues(alpha: opacity),
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
        color: ZenColors.mist.withValues(alpha: .80),
        borderRadius: const BorderRadius.all(ZenRadii.s),
        border: Border.all(color: ZenColors.jadeMid.withValues(alpha: .18)),
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
              fontWeight: FontWeight.w700, fontSize: 14.5, color: ZenColors.jade,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kontext-Extension & konsolidierte TextStyles
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
/// ==========================================================================
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

    if (DateTime(d.year, d.month, d.day) == today) return 'Heute';
    if (DateTime(d.year, d.month, d.day) == gestern(today)) return 'Gestern';
    return date(d);
  }

  static DateTime gestern(DateTime today) => today.subtract(const Duration(days: 1));

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
