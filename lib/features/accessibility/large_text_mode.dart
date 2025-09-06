// lib/features/accessibility/large_text_mode.dart
//
// LargeTextMode — sichere, a11y-freundliche Textskalierung
// --------------------------------------------------------
// • Vier Stufen: System / Normal / Groß / XL
// • Respektiert systemweite Einstellungen (nimmt niemals weniger als das System)
// • Persistenz via SharedPreferences (über App-Neustarts hinweg)
// • Saubere Semantik & Tooltips, klare Kontraste
// • Clamping (0.8–2.0), um Layoutbrüche zu vermeiden

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'a11y_utils.dart';

/// Verschiedene Stufen für die Textgröße (system/normal/large/xl)
enum LargeTextScale { system, normal, large, xl }

/// Provider für Large-Text-Mode (globale Accessibility)
class LargeTextModeProvider with ChangeNotifier {
  static const _prefsKey = 'a11y.textScale';
  LargeTextScale _scale;

  LargeTextModeProvider([this._scale = LargeTextScale.normal]);

  LargeTextScale get scale => _scale;

  /// Setzt die Skala, speichert sie und benachrichtigt Listener.
  set scale(LargeTextScale v) {
    if (_scale != v) {
      _scale = v;
      _persist(); // fire-and-forget
      notifyListeners();
    }
  }

  /// Faktor für MediaQuery.textScaleFactor.
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

  /// Persistiert die aktuelle Wahl in SharedPreferences.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _scale.name);
    } catch (_) {
      // bewusst schlucken: A11y darf nie crashen
    }
  }

  /// Lädt den gespeicherten Wert (optional im App-Start aufrufen).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        // byName kann werfen – defensiv auffangen
        final parsed = LargeTextScale.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => _scale,
        );
        _scale = parsed;
        notifyListeners();
      }
    } catch (_) {
      // still: sicher weiterlaufen
    }
  }
}

/// Umschalter für Settings-Screen – inklusive Erklärung/Tooltip
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
        Tooltip(
          message:
              "Aktiviere große Schrift, um Texte leichter zu lesen.\n"
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
            _scaleBtn(context, provider, LargeTextScale.system, "System", accent),
            _scaleBtn(context, provider, LargeTextScale.normal, "Normal", accent),
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
          backgroundColor: isActive ? accent.withOpacity(0.14) : null,
          side: BorderSide(color: isActive ? accent : Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          prov.scale = scale;
        },
        child: Text(
          label,
          style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }
}

/// Provider-Widget, das MediaQuery.textScaleFactor global setzt.
/// GANZ OBEN im Widget-Tree einbinden!
/// Sicherheitslogik:
///  • Wenn "System": gib unverändert durch
///  • Sonst: nimm das Maximum aus System- und gewählter Skala (reduziert nie A11y)
///  • Clamp auf [0.8, 2.0], um UI-Brüche zu vermeiden
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
    final base = media.textScaleFactor;
    final effective = _clampDouble(
      base >= chosen ? base : chosen, // niemals kleiner als System
      0.8,
      2.0,
    );

    return MediaQuery(
      data: media.copyWith(textScaleFactor: effective),
      child: child,
    );
  }

  double _clampDouble(double v, double min, double max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
    }
}

// Tipp zur Verwendung:
//
// ChangeNotifierProvider(
//   create: (_) {
//     final p = LargeTextModeProvider();
//     p.load(); // optional laden
//     return p;
//   },
//   child: LargeTextProvider(child: AppRoot()),
// )
