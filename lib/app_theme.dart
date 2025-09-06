// lib/app_theme.dart
//
// AppTheme — zentrale Theme-Basis auf Oxford–Zen (zen_style.dart)
// ---------------------------------------------------------------
// • Baut auf zenLightTheme()/zenDarkTheme() auf.
// • Feinschliff: Ripple/Highlight, Tooltips, Icons, NavigationBar, Divider.

import 'package:flutter/material.dart';
import 'shared/zen_style.dart' as zs;

class AppTheme {
  AppTheme._();

  static final ThemeData light = _base(zs.zenLightTheme());
  static final ThemeData dark  = _base(zs.zenDarkTheme());

  static ThemeData _base(ThemeData t) {
    final cs = t.colorScheme;

    return t.copyWith(
      // Ruhigeres Feedback
      splashColor: cs.primary.withOpacity(.08),
      highlightColor: cs.primary.withOpacity(.06),

      // Dezentere Default-Icons
      iconTheme: t.iconTheme.copyWith(
        color: cs.onSurface.withOpacity(.92),
        size: 22,
      ),

      // Tooltips (matte Karte + feiner Rand)
      tooltipTheme: t.tooltipTheme.copyWith(
        waitDuration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(.96),
          borderRadius: const BorderRadius.all(zs.ZenRadii.s),
          border: Border.all(color: cs.outline.withOpacity(.45)),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        textStyle: t.textTheme.bodySmall?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // (Falls NavigationBar verwendet wird)
      navigationBarTheme: t.navigationBarTheme.copyWith(
        height: 64,
        backgroundColor: cs.surface.withOpacity(.98),
        elevation: 0,
        indicatorColor: zs.ZenColors.goldenMist.withOpacity(.22),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: MaterialStatePropertyAll(
          t.textTheme.labelLarge?.copyWith(
            color: zs.ZenColors.deepSage,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // BottomSheet minimal justiert (Hintergrund-Tint behalten wir in zen_style)
      bottomSheetTheme: t.bottomSheetTheme.copyWith(
        elevation: 0,
        showDragHandle: false,
      ),

      // Divider global leicht weicher
      dividerColor: t.dividerColor.withOpacity(.9),
    );
  }
}
