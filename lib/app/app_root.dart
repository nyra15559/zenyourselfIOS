// lib/app/app_root.dart
//
// ZenAppRoot — Hauptmenü/Hub (v2.2 · 2025-09-14)
// -----------------------------------------------------------------------------
// • Tabs: Reflexion, Journal, Impulse, Pro, Story
// • Ruhige AppBar via ZenAppBar, asset-freier Hintergrund (stabil).
// • State-Persistenz pro Tab via KeepAlive.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

// Styles/Naming klar trennen: alles aus zen_style via Alias `zs`
import '../shared/zen_style.dart' as zs;
// Aus den UI-Widgets nehmen wir nur die AppBar
import '../shared/ui/zen_widgets.dart' show ZenAppBar;

// Feature-Screens
import '../features/reflection/reflection_screen.dart';
import '../features/journal/journal_screen.dart';
import '../features/impulse/impulse_screen.dart';
import '../features/pro/pro_screen.dart';
import '../features/story/story_screen.dart';

// Optionale Daten für Pro (legacy-Signatur)
import '../data/mood_entry.dart';
import '../data/reflection_entry.dart';

class ZenAppRoot extends StatefulWidget {
  const ZenAppRoot({super.key});

  @override
  State<ZenAppRoot> createState() => _ZenAppRootState();
}

class _ZenAppRootState extends State<ZenAppRoot> {
  int _index = 0;

  late final List<_TabItem> _tabs = <_TabItem>[
    _TabItem(
      label: 'Reflexion',
      icon: Icons.self_improvement_rounded,
      builder: () => const ReflectionScreen(), // bewusst ohne aggressive const-Nutzung
    ),
    _TabItem(
      label: 'Journal',
      icon: Icons.book_rounded,
      builder: () => const JournalScreen(),
    ),
    _TabItem(
      label: 'Impulse',
      icon: Icons.spa_rounded,
      builder: () => const ImpulseScreen(),
    ),
    _TabItem(
      label: 'Pro',
      icon: Icons.workspace_premium_rounded,
      builder: () => const ProScreen(
        moodEntries: <MoodEntry>[],
        reflectionEntries: <ReflectionEntry>[],
      ),
    ),
    _TabItem(
      label: 'Story',
      icon: Icons.auto_stories_rounded,
      builder: () => const StoryScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _tabs[_index];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ZenAppBar(
        title: current.label,
        showBack: false,
        actions: [
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Einstellungen folgen …')),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Solider, asset-freier Hintergrund (kein Absturz, kein Konflikt)
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: zs.ZenColors.bg),
            ),
          ),
          SafeArea(child: _KeepAlive(child: current.builder())),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: _tabs
            .map((t) => NavigationDestination(icon: Icon(t.icon), label: t.label))
            .toList(growable: false),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  final Widget Function() builder;
  _TabItem({required this.label, required this.icon, required this.builder});
}

// Hält pro Tab den State (z. B. Scrollpositionen)
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
