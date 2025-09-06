// lib/shared/ui/zen_shadows.dart
//
// Oxford–Zen Shadows & Elevation Utilities
// v6.1 — 2025-09-03
// -----------------------------------------------------------------------------
// • Presets: card/popover/modal/floating/tooltip
// • Glow: soft/golden/jade (ruhig, ohne grelle Kanten)
// • Elevation-API: ZenShadow.of(ZenElevationLevel.m, context)
// • Ringe: FocusRing / ErrorRing (BoxDecoration)
// • Wrap-Widgets: ZenShadowWrap / ZenGlowWrap
//
// Abhängigkeiten: nur Flutter + eure Tokens (zen_style.dart)

import 'package:flutter/material.dart';
import '../../shared/zen_style.dart' as zs;

/// Einfache, lesbare Stufen – genug für App-UI ohne Overkill.
enum ZenElevationLevel { none, xs, s, m, l, xl }

/// Zentrale Fabrik für Shades/Glows – an Oxford–Zen angepasst.
class ZenShadow {
  ZenShadow._();

  // ---------- Presets (Lists of BoxShadow) ----------

  /// Leichte Karten/Listen (Standard)
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000), // 8% schwarz
      blurRadius: 14,
      offset: Offset(0, 5),
    ),
    BoxShadow(
      color: Color(0x0A000000), // 4% schwarz (Kontaktkante)
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  /// Leicht angehoben (Hover/Lift)
  static const List<BoxShadow> cardLift = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000), // 10% schwarz
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x0D000000), // 5% schwarz
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Popover/Callout/Context-Menü
  static const List<BoxShadow> popover = <BoxShadow>[
    BoxShadow(
      color: Color(0x24000000), // 14%
      blurRadius: 22,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0D000000), // 5%
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Modal/Dialog (deutlicher, aber nicht hart)
  static const List<BoxShadow> modal = <BoxShadow>[
    BoxShadow(
      color: Color(0x33000000), // 20%
      blurRadius: 36,
      spreadRadius: 4,
      offset: Offset(0, 18),
    ),
  ];

  /// Schwebende Buttons/FAB
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F000000), // ~12%
      blurRadius: 20,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Tooltips / leichte Helfer
  static const List<BoxShadow> tooltip = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000), // 10%
      blurRadius: 12,
      offset: Offset(0, 6),
    ),
  ];

  // ---------- Glows (BoxShadow / Decorations) ----------

  /// Sehr sanfter, neutraler Glow (Universal)
  static const BoxShadow glowSoft = BoxShadow(
    color: Color(0x12000000), // 7–8%
    blurRadius: 18,
    offset: Offset(0, 6),
  );

  /// Jade-Glow – dezent für aktive Elemente
  static List<BoxShadow> glowJade([double k = 1.0]) => <BoxShadow>[
        BoxShadow(
          color: zs.ZenColors.jade.withOpacity(0.10 * k),
          blurRadius: 18 * k,
          spreadRadius: 1.2 * k,
          offset: const Offset(0, 6),
        ),
      ];

  /// Golden-Mist-Glow – passend zu Warm-Glow Hintergründen
  static List<BoxShadow> glowGolden([double k = 1.0]) => <BoxShadow>[
        BoxShadow(
          color: zs.ZenColors.goldenMist.withOpacity(0.18 * k),
          blurRadius: 26 * k,
          spreadRadius: 2.0 * k,
          offset: const Offset(0, 6),
        ),
      ];

  // ---------- Elevation API ----------

  /// Liefert eine kuratierte Shadow-Liste pro Stufe, leicht angepasst an Theme.
  static List<BoxShadow> of(ZenElevationLevel level, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // In Dark reduzieren wir Opazität etwas, um nicht „staubig“ zu wirken.
    double darkFactor(double v) => isDark ? v * 0.85 : v;

    switch (level) {
      case ZenElevationLevel.none:
        return const <BoxShadow>[];
      case ZenElevationLevel.xs:
        return <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.06)),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ];
      case ZenElevationLevel.s:
        return <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.08)),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.04)),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ];
      case ZenElevationLevel.m:
        return <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.10)),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.05)),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ];
      case ZenElevationLevel.l:
        return <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.12)),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.06)),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ];
      case ZenElevationLevel.xl:
        return <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.18)),
            blurRadius: 36,
            spreadRadius: 2,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(darkFactor(0.08)),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ];
    }
  }

  // ---------- Ringe (Focus/Error) als Dekoration ----------

  /// Ruhiger Fokus-Ring (für manuelles Dekorieren)
  static BoxDecoration focusRing({double width = 2.0}) {
    return BoxDecoration(
      borderRadius: const BorderRadius.all(zs.ZenRadii.l),
      boxShadow: [
        BoxShadow(
          color: zs.ZenColors.focus.withOpacity(.55),
          blurRadius: 0,
          spreadRadius: width,
        ),
        BoxShadow(
          color: zs.ZenColors.focus.withOpacity(.22),
          blurRadius: 10,
          spreadRadius: 1.0,
        ),
      ],
    );
  }

  /// Dezent roter Fehler-Ring
  static BoxDecoration errorRing({double width = 2.0}) {
    return BoxDecoration(
      borderRadius: const BorderRadius.all(zs.ZenRadii.l),
      boxShadow: [
        BoxShadow(
          color: zs.ZenColors.error.withOpacity(.45),
          blurRadius: 0,
          spreadRadius: width,
        ),
        BoxShadow(
          color: zs.ZenColors.error.withOpacity(.18),
          blurRadius: 8,
          spreadRadius: 0.8,
        ),
      ],
    );
  }

  // ---------- Helper: zusammengesetzte Decoration ----------

  static BoxDecoration cardDecoration({
    BorderRadius borderRadius = const BorderRadius.all(zs.ZenRadii.l),
    Color? color,
    List<BoxShadow>? shadows,
    BorderSide? borderSide,
  }) {
    return BoxDecoration(
      color: color ?? zs.ZenColors.surface,
      borderRadius: borderRadius,
      boxShadow: shadows ?? ZenShadow.card,
      border: Border.all(
        color: borderSide?.color ??
            Colors.black.withOpacity(0.03), // feine Kontaktkante
        width: borderSide?.width ?? 1,
      ),
    );
  }
}

/// Einfacher Wrapper, um einem Kind eine (optionale) Shadow-Dekoration zu geben.
class ZenShadowWrap extends StatelessWidget {
  final Widget child;
  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BoxBorder? border;

  const ZenShadowWrap({
    super.key,
    required this.child,
    this.shadows = ZenShadow.card,
    this.borderRadius = const BorderRadius.all(zs.ZenRadii.l),
    this.padding = EdgeInsets.zero,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: borderRadius,
        boxShadow: shadows,
        border: border,
      ),
      child: child,
    );
  }
}

/// Glow-Wrapper (z. B. für aktive Chips/Buttons)
class ZenGlowWrap extends StatelessWidget {
  final Widget child;
  final List<BoxShadow> glows;
  final BorderRadius borderRadius;

  const ZenGlowWrap({
    super.key,
    required this.child,
    this.glows = const <BoxShadow>[ZenShadow.glowSoft],
    this.borderRadius = const BorderRadius.all(zs.ZenRadii.l),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration:
          BoxDecoration(borderRadius: borderRadius, boxShadow: glows),
      child: child,
    );
  }
}
