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
      splashColor: cs.primary.withValues(alpha: .08),
      highlightColor: cs.primary.withValues(alpha: .06),

      // Dezentere Default-Icons
      iconTheme: t.iconTheme.copyWith(
        color: cs.onSurface.withValues(alpha: .92),
        size: 22,
      ),

      // Tooltips (matte Karte + feiner Rand)
      tooltipTheme: t.tooltipTheme.copyWith(
        waitDuration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: .96),
          borderRadius: const BorderRadius.all(zs.ZenRadii.s),
          border: Border.all(color: cs.outline.withValues(alpha: .45)),
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
        backgroundColor: cs.surface.withValues(alpha: .98),
        elevation: 0,
        indicatorColor: zs.ZenColors.goldenMist.withValues(alpha: .22),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
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
      dividerColor: t.dividerColor.withValues(alpha: .9),
    );
  }
}
