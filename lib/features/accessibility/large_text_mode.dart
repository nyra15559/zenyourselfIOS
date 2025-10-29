// lib/features/accessibility/large_text_mode.dart
import '../../shared/zen_style.dart';
//
// LargeTextMode — sichere, a11y-freundliche Textskalierung
// --------------------------------------------------------
// • Vier Stufen: System / Normal / Groß / XL
// • Respektiert System (nimmt nie weniger als System)
// • Persistenz via SharedPreferences
// • TextScaler (Flutter ≥3.12), Clamping [0.8, 2.0]

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'a11y_utils.dart';

/// Verschiedene Stufen für die Textgröße
enum LargeTextScale { system, normal, large, xl }

/// Provider für Large-Text-Mode (global)
class LargeTextModeProvider with ChangeNotifier {
  static const _prefsKey = 'a11y.textScale';
  LargeTextScale _scale;

  LargeTextModeProvider([this._scale = LargeTextScale.normal]);

  LargeTextScale get scale => _scale;

  set scale(LargeTextScale v) {
    if (_scale != v) {
      _scale = v;
      _persist(); // fire-and-forget
      notifyListeners();
    }
  }

  /// Faktor für linearen TextScaler.
  /// -1 bedeutet: Systemwert unverändert durchreichen.
  double get factor {
    switch (_scale) {
      case LargeTextScale.system:
        return -1;
      case LargeTextScale.normal:
        return 1.0;
      case LargeTextScale.large:
        return 1.33;
      case LargeTextScale.xl:
        return 1.55;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _scale.name);
    } catch (_) {
      // A11y-Fehler nie crashen lassen
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        final parsed = LargeTextScale.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => _scale,
        );
        _scale = parsed;
        notifyListeners();
      }
    } catch (_) {}
  }
}

/// Umschalter für Settings
class LargeTextModeSwitcher extends StatelessWidget {
  const LargeTextModeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LargeTextModeProvider>(context);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Tooltip(
          message: "Aktiviere große Schrift, um Texte leichter zu lesen.\n"
              "Wir respektieren immer deine System-Einstellungen.",
          child: A11yText(
            "Textgröße",
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _scaleBtn(
                context, provider, LargeTextScale.system, "System", accent),
            _scaleBtn(
                context, provider, LargeTextScale.normal, "Normal", accent),
            _scaleBtn(context, provider, LargeTextScale.large, "Groß", accent),
            _scaleBtn(context, provider, LargeTextScale.xl, "XL", accent),
          ],
        ),
      ],
    );
  }

  Widget _scaleBtn(
    BuildContext ctx,
    LargeTextModeProvider prov,
    LargeTextScale scale,
    String label,
    Color accent,
  ) {
    final isActive = prov.scale == scale;

    return Semantics(
      button: true,
      selected: isActive,
      label: "Textgröße $label${isActive ? ' (aktiv)' : ''}",
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: isActive ? accent.withValue(alpha: 0.14) : null,
          side: BorderSide(color: isActive ? accent : Colors.grey.shade300),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          prov.scale = scale;
        },
        child: Text(
          label,
          style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }
}

/// Provider-Widget, das MediaQuery.textScaler global setzt.
/// GANZ OBEN im Widget-Tree einbinden!
class LargeTextProvider extends StatelessWidget {
  final Widget child;
  const LargeTextProvider({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final chosen = context.watch<LargeTextModeProvider>().factor;
    if (chosen < 0) {
      // Systemwert respektieren (unverändert)
      return child;
    }

    final media = MediaQuery.of(context);
    // System-Faktor aus TextScaler approximieren
    final systemScale = MediaQuery.textScalerOf(context).scale(16.0) / 16.0;

    // Niemals kleiner als System; dann clampen
    final maxed = systemScale >= chosen ? systemScale : chosen;
    final effective = _clampDouble(maxed, 0.8, 2.0);

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(effective)),
      child: child,
    );
  }

  double _clampDouble(double v, double min, double max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }
}

// Beispiel-Verwendung:
//
// ChangeNotifierProvider(
//   create: (_) {
//     final p = LargeTextModeProvider();
//     p.load(); // optional laden
//     return p;
//   },
//   child: LargeTextProvider(child: AppRoot()),
// )
