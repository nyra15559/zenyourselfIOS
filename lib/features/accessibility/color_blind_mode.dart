// lib/features/accessibility/color_blind_mode.dart
//
// Color-Blind Mode — robuste A11y-Farbsteuerung
// ---------------------------------------------
// • Zwei Paletten: normal & farbenblindenfreundlich (deuter-/protan-sicher)
// • Persistenz via SharedPreferences
// • Hoher Kontrast & automatische „onColor“-Berechnung
// • Semantiken/Haptik im Switcher
// • Hilfs-Widgets für farbcodierte Statuschips, die NICHT nur Farbe nutzen

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Farbpalette für Accessibility/Color-Blind-Mode
class AccessibilityPalette {
  final Color accent;
  final Color good;
  final Color warning;
  final Color bad;

  const AccessibilityPalette({
    required this.accent,
    required this.good,
    required this.warning,
    required this.bad,
  });

  /// Standard (normale App-Farben)
  static const normal = AccessibilityPalette(
    accent: Color(0xFFA5CBA1), // Jade
    good: Color(0xFF365486),   // Oxford Blue
    warning: Color(0xFFFFD580),// Gold
    bad: Color(0xFFB2B2B2),    // Grey
  );

  /// Farbenblindenfreundlich (hoher Kontrast, gut unterscheidbar)
  static const colorBlind = AccessibilityPalette(
    accent: Color(0xFF3777B6), // Blau
    good: Color(0xFF3BA54A),   // Grün
    warning: Color(0xFFE6A700),// Gelb/Amber
    bad: Color(0xFFB71C1C),    // Rot (dunkel für Kontrast)
  );

  /// Ermittelt die aktive Palette aus dem Context (Provider)
  static AccessibilityPalette of(BuildContext context) {
    final enabled =
        context.select<ColorBlindModeProvider, bool>((p) => p.enabled);
    return enabled ? AccessibilityPalette.colorBlind : AccessibilityPalette.normal;
  }

  /// Lesefarbe (schwarz/weiß) mit solidem Kontrast
  static Color onColor(Color bg) => _relativeLuminance(bg) > 0.58
      ? Colors.black
      : Colors.white;

  /// Relative Luminanz (WCAG) – aktualisiert auf neues Color-API:
  /// Achtung: `Color.r/g/b` liefern 0..1 Floats (nicht 0..255).
  static double _relativeLuminance(Color c) {
    double gamma(double s) =>
        s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    final r = gamma(c.r);
    final g = gamma(c.g);
    final b = gamma(c.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
}

/// Provider für Color-Blind-Mode (global)
class ColorBlindModeProvider with ChangeNotifier {
  static const _prefsKey = 'a11y.colorBlind.enabled';
  bool _enabled;

  ColorBlindModeProvider([this._enabled = false]);

  bool get enabled => _enabled;

  set enabled(bool v) {
    if (_enabled != v) {
      _enabled = v;
      _persist(); // fire-and-forget
      notifyListeners();
    }
  }

  /// Persistenz laden (z. B. im App-Start)
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? _enabled;
      notifyListeners();
    } catch (_) {
      // nie crashen wegen A11y
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, _enabled);
    } catch (_) {}
  }
}

/// Umschalter für Einstellungen – mit Semantik & Haptik
class ColorBlindModeSwitcher extends StatelessWidget {
  const ColorBlindModeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ColorBlindModeProvider>();
    final palette = AccessibilityPalette.of(context);

    // Material 3: activeColor ist deprecated → Thumb/Track separat setzen.
    final activeThumb = palette.accent;
    final activeTrack = palette.accent.withValues(alpha: 0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Farbenblinden-Modus",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Semantics(
              toggled: provider.enabled,
              label:
                  "Farbenblinden-Modus ${provider.enabled ? 'aktiv' : 'inaktiv'}",
              child: Switch.adaptive(
                value: provider.enabled,
                // ersetzt deprecated activeColor:
                activeThumbColor: activeThumb,
                activeTrackColor: activeTrack,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  provider.enabled = v;
                },
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                "Optimierte Farben mit hohem Kontrast – zusätzlich nutzen wir Symbole, nicht nur Farbe.",
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Kleine Legende, die Form + Farbe kombiniert (nicht nur Farbe!)
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SignalChip(icon: Icons.check_circle, label: "Gut", kind: _SignalKind.good),
            _SignalChip(icon: Icons.warning, label: "Hinweis", kind: _SignalKind.warning),
            _SignalChip(icon: Icons.cancel, label: "Kritisch", kind: _SignalKind.bad),
          ],
        ),
      ],
    );
  }
}

/// Interne Kennzeichnung für Signalarten
enum _SignalKind { good, warning, bad }

/// Kompakter Status-Chip, der Farbe + Icon kombiniert
class _SignalChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final _SignalKind kind;

  const _SignalChip({
    required this.icon,
    required this.label,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final p = AccessibilityPalette.of(context);

    // komplette, aber erreichbare Fallunterscheidung (kein unreachable default)
    Color bg;
    switch (kind) {
      case _SignalKind.good:
        bg = p.good;
        break;
      case _SignalKind.warning:
        bg = p.warning;
        break;
      case _SignalKind.bad:
        bg = p.bad;
        break;
    }

    final fg = AccessibilityPalette.onColor(bg);

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 12.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// kleine, stabile Potenzfunktion für Gamma 2.4 (nutzt dart:math)
class MathPow {
  static double pow24(double base) => math.pow(base, 2.4).toDouble();
}
