// lib/shared/ui/zen_tab_bar.dart
//
// ZenTabBar — Oxford–Zen Bottom Navigation (calm · matte · tactile)
// v6.3 — 2025-10-22
// ------------------------------------------------------------------
// • Sanfte, matte Leiste (Light: surfaceAlt · Dark: surface).
// • Ausgewählter Tab als „Pill“ (Border + Shadow), ruhige Motion.
// • GoldenMist-Indicator, A11y (Semantics/Tooltips), Haptik onTap.
// • Keyboard: Enter/Space auf fokussiertem Tab → onTap.
// • API: ZenTabBar(currentIndex, onTap, items: [ZenTabItem(...), ...])
//
// Hinweise:
// • Import-Fix: zen_style.dart liegt eine Ebene höher → '../zen_style.dart'.
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../zen_style.dart';

class ZenTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<ZenTabItem> items;

  const ZenTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final barColor =
        (isDark ? cs.surface : ZenColors.surfaceAlt).withValue(alpha: .98);
    final borderColor = theme.dividerColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18, left: 16, right: 16),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Hauptnavigation',
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: const BorderRadius.all(ZenRadii.xl),
            border: Border.all(color: borderColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(items.length, (i) {
                final isSelected = currentIndex == i;
                final item = items[i];

                return Expanded(
                  child: _TabButton(
                    index: i,
                    total: items.length,
                    item: item,
                    isSelected: isSelected,
                    onPressed: () {
                      if (i == currentIndex) return;
                      HapticFeedback.selectionClick();
                      onTap(i);
                    },
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final int index;
  final int total;
  final ZenTabItem item;
  final bool isSelected;
  final VoidCallback onPressed;

  const _TabButton({
    required this.index,
    required this.total,
    required this.item,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final borderColor = theme.dividerColor;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${item.semanticLabel ?? item.label}, Tab ${index + 1} von $total',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (_) {},
        onShowHoverHighlight: (_) {},
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(onInvoke: (_) {
            onPressed();
            return null;
          }),
        },
        child: AnimatedContainer(
          duration: animMed,
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.symmetric(
            vertical: isSelected ? 2 : 6,
            horizontal: 3,
          ),
          decoration: BoxDecoration(
            color: isSelected ? cs.surface : Colors.transparent,
            borderRadius: const BorderRadius.all(ZenRadii.l),
            border: isSelected ? Border.all(color: borderColor) : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValue(alpha: .08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.all(ZenRadii.l),
              splashColor: ZenColors.goldenMist.withValue(alpha: .14),
              hoverColor: ZenColors.focus.withValue(alpha: .06),
              focusColor: ZenColors.focus.withValue(alpha: .10),
              highlightColor: Colors.transparent,
              onTap: onPressed,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: isSelected ? 12 : 10,
                  horizontal: isSelected ? 12 : 0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: item.label,
                      waitDuration: const Duration(milliseconds: 600),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Icon + optional Badge/Dot
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                item.icon,
                                size: isSelected ? 26 : 22,
                                color: isSelected
                                    ? ZenColors.deepSage
                                    : ZenColors.sage.withValue(alpha: .70),
                                semanticLabel: item.label,
                              ),
                              if ((item.badgeCount ?? 0) > 0 || item.showDot)
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: _Badge(
                                    count: item.badgeCount,
                                    dot: item.showDot,
                                  ),
                                ),
                            ],
                          ),
                          // Label nur im Selected-Zustand sichtbar (Icon + Size als nicht-farbiger Hinweis)
                          AnimatedSwitcher(
                            duration: animShort,
                            transitionBuilder: (c, a) =>
                                FadeTransition(opacity: a, child: c),
                            child: isSelected
                                ? Padding(
                                    key: ValueKey('lbl_$index'),
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: (theme.textTheme.labelLarge ??
                                              const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ))
                                          .copyWith(
                                        color: ZenColors.deepSage,
                                        letterSpacing: .15,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    // Dezenter Indicator (zusätzliche, nicht-farbige Rückmeldung via Höhe/Platz)
                    AnimatedContainer(
                      duration: animMed,
                      height: isSelected ? 2.5 : 0,
                      margin: const EdgeInsets.only(top: 8),
                      width: isSelected ? 26 : 0,
                      decoration: const BoxDecoration(
                        color: ZenColors.goldenMist,
                        borderRadius: BorderRadius.all(ZenRadii.s),
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

class ZenTabItem {
  final IconData icon;
  final String label;
  final String? semanticLabel; // optional: explizite Screenreader-Formulierung
  final int? badgeCount; // optional: Zahl
  final bool showDot; // optional: nur Punkt

  const ZenTabItem(
    this.icon,
    this.label, {
    this.semanticLabel,
    this.badgeCount,
    this.showDot = false,
  });
}

class _Badge extends StatelessWidget {
  final int? count;
  final bool dot;
  const _Badge({this.count, this.dot = false});

  @override
  Widget build(BuildContext context) {
    if (dot && (count == null || count == 0)) {
      return Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: ZenColors.goldenMist,
          shape: BoxShape.circle,
        ),
      );
    }
    final value = (count ?? 0);
    final capped = value > 99 ? '99+' : value.clamp(1, 99).toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ZenColors.deepSage,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        capped,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}
