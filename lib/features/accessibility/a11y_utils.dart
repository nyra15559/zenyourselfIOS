// lib/features/accessibility/a11y_utils.dart
//
// ZenYourself • Accessibility Utils (safe-by-default)
// ---------------------------------------------------
// • Eigene Palette/Provider (keine Kollision mit Color-Blind-Palette)
// • WCAG-Kontrast-Helpers, dynamische On-Color, Reduced-Motion-Hinweis
// • Semantik-Werkzeuge (Announce), fokusfreundliche Text-Komponente
// • Auf Flutter ≥3.12+ aktualisiert (TextScaler, Color.r/g/b, withValues)

import 'dart:math' as math;
import 'package:flutter/material.dart';
// Für optionales Live-Announcement (sparsam verwenden!)
import 'package:flutter/semantics.dart';

/// ===================
/// ZEN ACCESSIBILITY THEME
/// ===================
///
/// Hinweis: Diese Datei definiert bewusst **ZenA11yPalette**, um eine
/// Kollision mit der in `color_blind_mode.dart` definierten
/// `AccessibilityPalette` zu vermeiden.
class ZenA11yPalette {
  final bool isColorBlind;
  final bool isDark;
  final bool isHighContrast;
  final bool reduceMotion;

  const ZenA11yPalette({
    this.isColorBlind = false,
    this.isDark = false,
    this.isHighContrast = false,
    this.reduceMotion = false,
  });

  // Zen Brand (konservativ, beruhigende Töne)
  static const _zenJade = Color(0xFF0B3D2E);
  static const _zenJadeLight = Color(0xFF386F5B);
  static const _zenWhite = Color(0xFFFDFCF6);
  static const _zenGold = Color(0xFFFFD48A);

  Color get primary =>
      isDark
          ? _zenWhite
          : isColorBlind
              ? const Color(0xFF1B263B)
              : _zenJade;

  Color get accent => isColorBlind ? _zenGold : _zenJadeLight;

  Color get background => isDark ? const Color(0xFF23272F) : _zenWhite;

  Color get positive => isColorBlind ? _zenGold : const Color(0xFFA5CBA1);

  Color get error => const Color(0xFFD7263D);

  Color get border =>
      isHighContrast ? Colors.black : _zenJadeLight.withValues(alpha: 0.14);

  /// Kontrastfreundliche Textfarbe zu einem Hintergrund bestimmen.
  static Color onColor(Color bg) =>
      _relativeLuminance(bg) > 0.58 ? Colors.black : Colors.white;

  /// WCAG-Kontrast-Ratio (>= 4.5 empfohlen für normale Schrift)
  static double contrastRatio(Color a, Color b) {
    final l1 = _relativeLuminance(a) + 0.05;
    final l2 = _relativeLuminance(b) + 0.05;
    return l1 > l2 ? l1 / l2 : l2 / l1;
  }

  static bool isContrastGood(Color fg, Color bg, {double min = 4.5}) =>
      contrastRatio(fg, bg) >= min;

  /// Relative Luminanz nach WCAG – aktualisiert auf neues Color-API.
  /// Achtung: `Color.r/g/b` sind **0..1**-Floats (nicht 0..255).
  static double _relativeLuminance(Color c) {
    double gamma(double s) =>
        s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();

    final r = gamma(c.r);
    final g = gamma(c.g);
    final b = gamma(c.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  ZenA11yPalette copyWith({
    bool? isColorBlind,
    bool? isDark,
    bool? isHighContrast,
    bool? reduceMotion,
  }) {
    return ZenA11yPalette(
      isColorBlind: isColorBlind ?? this.isColorBlind,
      isDark: isDark ?? this.isDark,
      isHighContrast: isHighContrast ?? this.isHighContrast,
      reduceMotion: reduceMotion ?? this.reduceMotion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZenA11yPalette &&
          isColorBlind == other.isColorBlind &&
          isDark == other.isDark &&
          isHighContrast == other.isHighContrast &&
          reduceMotion == other.reduceMotion;

  @override
  int get hashCode =>
      Object.hash(isColorBlind, isDark, isHighContrast, reduceMotion);

  /// Aus dem BuildContext holen
  static ZenA11yPalette of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<_ZenA11yPaletteProvider>();
    return inherited?.palette ?? const ZenA11yPalette();
  }
}

/// Globaler A11y-Provider für das gesamte ZenTheme
class A11yProvider extends StatelessWidget {
  final Widget child;
  final bool colorBlind;
  final bool darkMode;
  final bool highContrast;
  final bool reduceMotion;

  const A11yProvider({
    super.key,
    required this.child,
    this.colorBlind = false,
    this.darkMode = false,
    this.highContrast = false,
    this.reduceMotion = false,
  });

  @override
  Widget build(BuildContext context) {
    return _ZenA11yPaletteProvider(
      palette: ZenA11yPalette(
        isColorBlind: colorBlind,
        isDark: darkMode,
        isHighContrast: highContrast,
        reduceMotion: reduceMotion,
      ),
      child: child,
    );
  }
}

class _ZenA11yPaletteProvider extends InheritedWidget {
  final ZenA11yPalette palette;
  const _ZenA11yPaletteProvider({
    required this.palette,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ZenA11yPaletteProvider oldWidget) =>
      oldWidget.palette != palette;
}

/// ===================
/// A11yText – fokus- & kontrastfreundlicher Text
/// ===================
/// - Achtet den systemweiten TextScaler (nonlinear scaling ready)
/// - Optionaler Fokusrahmen (High-Contrast & Tastaturnavigation)
/// - Minimiert visuelle Belastung (schwache Schatten nur bei animatedFocus)
class A11yText extends StatelessWidget {
  final String text;
  final double? fontSize;
  final String? semanticsLabel;
  final TextAlign? align;
  final Color? color;
  final FontWeight? fontWeight;
  final bool bold;
  final bool highContrastOutline;
  final bool animatedFocus;
  final int? maxLines;
  final TextOverflow? overflow;

  const A11yText(
    this.text, {
    super.key,
    this.fontSize,
    this.semanticsLabel,
    this.align,
    this.color,
    this.fontWeight,
    this.bold = false,
    this.highContrastOutline = false,
    this.animatedFocus = false,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    // Neu: TextScaler statt textScaleFactorOf (deprecatet).
    // Wir kappen sanft auf 1.0–2.2, um extreme Skalen zu entschärfen.
    final scaler = MediaQuery.textScalerOf(context);
    final base = fontSize ?? 17.0;
    final scaled = scaler.scale(base);
    final clamped = scaled.clamp(base * 1.0, base * 2.2).toDouble();

    final palette = ZenA11yPalette.of(context);

    final baseStyle = TextStyle(
      fontFamily: "SFProText",
      fontSize: clamped, // bereits skaliert & gekappt
      color: color ?? palette.primary,
      fontWeight: fontWeight ?? (bold ? FontWeight.w600 : FontWeight.normal),
      height: 1.22,
      shadows: animatedFocus
          ? [
              Shadow(
                blurRadius: 10,
                color: palette.accent.withValues(alpha: 0.12),
                offset: const Offset(0, 2),
              )
            ]
          : const [],
    );

    Widget txt = Text(
      text,
      textAlign: align,
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );

    if (highContrastOutline || palette.isHighContrast) {
      txt = Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: palette.isHighContrast ? Colors.black : Colors.transparent,
            width: palette.isHighContrast ? 2.0 : 0,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: txt,
      );
    }

    return Semantics(
      label: semanticsLabel ?? text,
      child: Focus(
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: palette.reduceMotion ? 0 : 180),
          child: txt,
        ),
      ),
    );
  }
}

/// ===================
/// A11yAnnounce – Screenreader-Label Wrapper
/// ===================
/// Nutzt Semantik-Label, ohne Sichtbarkeit zu verändern.
class A11yAnnounce extends StatelessWidget {
  final String label;
  final Widget child;
  const A11yAnnounce({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Semantics(label: label, child: child);
  }
}

/// ===================
/// A11yLiveAnnouncer – optionales Live-Announcement
/// ===================
/// Ruft nach dem Frame SemanticsService.announce() auf.
/// **Wichtig:** sehr sparsam einsetzen (kann sonst aufdringlich sein).
class A11yLiveAnnouncer extends StatefulWidget {
  final String message;
  final TextDirection textDirection;
  final Widget child;
  final bool announceOnce;

  const A11yLiveAnnouncer({
    super.key,
    required this.message,
    required this.child,
    this.textDirection = TextDirection.ltr,
    this.announceOnce = true,
  });

  @override
  State<A11yLiveAnnouncer> createState() => _A11yLiveAnnouncerState();
}

class _A11yLiveAnnouncerState extends State<A11yLiveAnnouncer> {
  bool _announced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_announced || !widget.announceOnce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Hinweis: Einige Lints markieren announce() als "deprecated_member_use".
        // In Flutter ist announce weiterhin de facto-API. Bei Änderung: zentral hier anpassen.
        // ignore: deprecated_member_use_from_same_package
        SemanticsService.announce(widget.message, widget.textDirection);
      });
      if (widget.announceOnce) _announced = true;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// ===================
/// Kontrast-Helpers (öffentlich)
/// ===================
bool isContrastGood(Color fg, Color bg) =>
    ZenA11yPalette.isContrastGood(fg, bg);
double contrastRatio(Color a, Color b) => ZenA11yPalette.contrastRatio(a, b);

/// ===========================
/// Demo-Komponente (Showcase)
/// ===========================
class A11yContrastDemo extends StatelessWidget {
  const A11yContrastDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = ZenA11yPalette.of(context);
    final chipBg = palette.accent;
    final chipFg = ZenA11yPalette.onColor(chipBg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const A11yText("Normale Schrift – ZenBrand"),
        const SizedBox(height: 9),
        const A11yText(
          "High Contrast",
          highContrastOutline: true,
          animatedFocus: true,
          bold: true,
        ),
        const SizedBox(height: 9),
        Container(
          width: 160,
          height: 36,
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: A11yText(
              "Accessible Button",
              color: chipFg,
              fontWeight: FontWeight.w700,
              semanticsLabel: "Klickbarer, kontrastreicher Button",
            ),
          ),
        ),
        const SizedBox(height: 6),
        A11yText(
          "Kontrast: ${contrastRatio(chipFg, chipBg).toStringAsFixed(2)}",
          fontSize: 12.5,
          color: Colors.black.withValues(alpha: 0.6),
        ),
      ],
    );
  }
}
