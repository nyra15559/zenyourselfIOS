// lib/features/journal/journal_screen.dart
//
// JournalScreen — Oxford-Zen Timeline (Phase 2.8 • Parität + sanftes Pull-to-refresh)
// -----------------------------------------------------------------------------------
// • Nutzt JournalEntriesProvider (Filter + Soft-Hide) und JournalEntry.
// • Tages-Gruppierung (lokale Zeit) + ruhige Timeline mit Panda-Header.
// • Zentrierte Filter-Pille: Alle / Tagebuch / Reflexion / Kurzgeschichte (Counts).
// • Card: features/journal/widgets/journal_entry_card.dart
// • Aktionen: Öffnen, Erneut reflektieren (nur Reflexion), Ausblenden, Löschen.
// • Crash-Fix: KEIN IntrinsicHeight mehr (Timeline-Reihe via Stack/Align).
// • FAB („+“) kontextsensitiv, optisch beruhigt (Deep Sage).
// • Pull-to-refresh → provider.restore() (falls Persistence-Hooks gesetzt).
//
// In diesem Patch (Parität zum Viewer):
// • _openViewer: Story wird korrekt als Story angezeigt (Header, Badge, Volltext).
// • Übergabe der Story-Felder (title/teaser/body) an JournalEntryView.
// • Kommentare/Benennung aufgeräumt; keine Verhaltensänderung außerhalb des Fixes.
//
// Technische Notizen:
// • Bei ZenAppBar/Backdrop KEINE const verwenden (intern dynamisch).
// • Color.withOpacity(...) statt withValues(...).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, ZenToast;

import '../../models/journal_entry.dart' as jm;
import '../../providers/journal_entries_provider.dart' as jp;

import 'widgets/journal_entry_card.dart';
import 'journal_entry_view.dart' as jv;
import '../reflection/reflection_screen.dart';

class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  static const double _maxContentWidth = 820;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 560;

    final provider = context.watch<jp.JournalEntriesProvider?>();
    if (provider == null) {
      return const Scaffold(
        body: Center(child: Text('JournalEntriesProvider nicht vorhanden')),
      );
    }

    // Sichtbare Liste (Filter + Soft-Hide im Provider)
    final entries = provider.listVisible();

    // Counts für Filter-Pille
    final counts = provider.countsByKind();
    final allCount = counts[jp.JournalFilterKind.all] ?? 0;
    final journalCount = counts[jp.JournalFilterKind.journal] ?? 0;
    final reflectionCount = counts[jp.JournalFilterKind.reflection] ?? 0;
    final storyCount = counts[jp.JournalFilterKind.story] ?? 0;

    final grouped = _groupByDay(entries); // lokale Tages-Gruppierung
    final isEmpty = entries.isEmpty;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: const zw.ZenAppBar(
        title: null,
        showBack: true,
        actions: [],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'journal-add',
        tooltip: 'Neuen Eintrag',
        onPressed: () => _startNewEntry(context, provider),
        backgroundColor: zs.ZenColors.deepSage,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(zs.ZenRadii.l),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: zw.ZenBackdrop(
              asset: 'assets/schoen.png',
              alignment: Alignment.center,
              glow: .40,
              vignette: .16,
              enableHaze: true,
              hazeStrength: .16,
              saturation: .92,
              wash: .12,
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: isMobile ? 20 : 36, bottom: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: isEmpty
                    ? _wrapRefresh(
                        context: context,
                        provider: provider,
                        child: _buildEmptyState(context, isMobile, provider),
                      )
                    : _wrapRefresh(
                        context: context,
                        provider: provider,
                        child: _buildTimelineList(
                          context,
                          provider: provider,
                          isMobile: isMobile,
                          groups: grouped,
                          allCount: allCount,
                          journalCount: journalCount,
                          reflectionCount: reflectionCount,
                          storyCount: storyCount,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ——————————————————— Pull-to-refresh Wrapper ———————————————————

  Widget _wrapRefresh({
    required BuildContext context,
    required jp.JournalEntriesProvider provider,
    required Widget child,
  }) {
    return RefreshIndicator.adaptive(
      onRefresh: () async {
        await provider.restore(); // no-op wenn kein Load-Hook
        HapticFeedback.selectionClick();
      },
      edgeOffset: 8,
      displacement: 34,
      child: child,
    );
  }

  // ———————————————————————— UI: Empty State ————————————————————————

  Widget _buildEmptyState(
    BuildContext context,
    bool isMobile,
    jp.JournalEntriesProvider provider,
  ) {
    final pandaSize = MediaQuery.of(context).size.width < 470 ? 88.0 : 112.0;
    final activeFilter = provider.filterKind;

    // Klarer CTA zusätzlich zum FAB (falls Nutzer das FAB übersieht)
    return ListView(
      key: const PageStorageKey('journal_empty'),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? zs.ZenSpacing.s : zs.ZenSpacing.xl,
      ),
      children: [
        const SizedBox(height: 6),
        zw.PandaHeader(
          title: 'Dein Gedankenbuch',
          caption: 'Beginne mit deinem ersten Eintrag.',
          pandaSize: pandaSize,
          strongTitleGreen: true,
        ),
        const SizedBox(height: 12),
        zw.ZenGlassCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
          topOpacity: .26,
          bottomOpacity: .10,
          borderOpacity: .18,
          child: Column(
            children: [
              Text(
                'Noch keine Einträge.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: zs.ZenColors.deepSage,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Wenn dir etwas auffällt oder du etwas festhalten möchtest, tippe unten auf das Plus.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: Text(_ctaLabelFor(activeFilter)),
                onPressed: () => _startNewEntry(context, provider),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  static String _ctaLabelFor(jp.JournalFilterKind k) {
    switch (k) {
      case jp.JournalFilterKind.reflection:
        return 'Neue Reflexion starten';
      case jp.JournalFilterKind.story:
        return 'Neue Kurzgeschichte beginnen';
      case jp.JournalFilterKind.journal:
        return 'Neuen Gedanken festhalten';
      case jp.JournalFilterKind.all:
        return 'Neuen Eintrag beginnen';
    }
  }

  // ———————————————————————— UI: Timeline —————————————————————————

  Widget _buildTimelineList(
    BuildContext context, {
    required jp.JournalEntriesProvider provider,
    required bool isMobile,
    required List<_DayGroup> groups,
    required int allCount,
    required int journalCount,
    required int reflectionCount,
    required int storyCount,
  }) {
    return ListView.builder(
      key: const PageStorageKey('journal_timeline_list'),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? zs.ZenSpacing.s : zs.ZenSpacing.xl,
      ),
      itemCount: groups.length + 3, // PandaHeader + Filter + Gap
      itemBuilder: (ctx, i) {
        if (i == 0) {
          final pandaSize = MediaQuery.of(ctx).size.width < 470 ? 88.0 : 112.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: zw.PandaHeader(
              title: 'Dein Gedankenbuch',
              caption: 'Zeit hat keine Eile.',
              pandaSize: pandaSize,
              strongTitleGreen: true,
            ),
          );
        }
        if (i == 1) {
          // Zentrierte, kompakte Filter-Pille unter dem Panda
          return Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 12),
            child: Center(
              child: IntrinsicWidth(
                child: zw.ZenGlassCard(
                  borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  topOpacity: .26,
                  bottomOpacity: .10,
                  borderOpacity: .18,
                  child: _FilterPill(
                    provider: provider,
                    allCount: allCount,
                    journalCount: journalCount,
                    reflectionCount: reflectionCount,
                    storyCount: storyCount,
                  ),
                ),
              ),
            ),
          );
        }
        if (i == 2) return const SizedBox(height: 6);

        final group = groups[i - 3];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: zs.ZenSpacing.s, bottom: 6),
              child: _DayHeader(date: group.dateOnly),
            ),
            ...List.generate(group.items.length, (idx) {
              final e = group.items[idx];
              final showAbove = idx > 0;
              final showBelow = idx < group.items.length - 1;
              return _TimelineRow(
                key: ValueKey('row-${e.id}'),
                showAbove: showAbove,
                showBelow: showBelow,
                child: JournalEntryCard(
                  entry: e,
                  onTap: () => _openViewer(context, e),
                  onContinue: e.kind == jm.EntryKind.reflection
                      ? () => _continueIntoReflection(context, provider, e)
                      : null, // Story/Journal → kein CTA
                  onEdit: null,
                  onHide: () {
                    provider.hide(e.id);
                    HapticFeedback.selectionClick();
                    zw.ZenToast.show(context, 'Eintrag verborgen');
                  },
                  onDelete: () {
                    provider.removeById(e.id);
                    HapticFeedback.selectionClick();
                    zw.ZenToast.show(context, 'Eintrag gelöscht');
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ———————————————————————— Actions / Navigation ————————————————————————

  Future<void> _openViewer(BuildContext context, jm.JournalEntry e) async {
    // Korrekte Abbildung des Model-Enums auf den Viewer-Typ.
    final viewKind = switch (e.kind) {
      jm.EntryKind.journal    => jv.EntryKind.journal,
      jm.EntryKind.reflection => jv.EntryKind.reflection,
      jm.EntryKind.story      => jv.EntryKind.story, // ← wichtig: Story bleibt Story
    };

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => jv.JournalEntryView(
          kind: viewKind,
          createdAt: e.createdAt,

          // Tagebuch
          journalText: viewKind == jv.EntryKind.journal ? e.thoughtText : null,

          // Reflexion
          userThought: viewKind == jv.EntryKind.reflection ? e.thoughtText : null,
          aiQuestion:  viewKind == jv.EntryKind.reflection ? e.aiQuestion  : null,
          userAnswer:  viewKind == jv.EntryKind.reflection ? e.userAnswer  : null,

          // Kurzgeschichte — vollständige Weitergabe an den Viewer
          storyTitle:  viewKind == jv.EntryKind.story ? _storyTitleFor(e) : null,
          storyTeaser: viewKind == jv.EntryKind.story ? e.storyTeaser   : null,
          storyBody:   viewKind == jv.EntryKind.story ? e.storyBody     : null,

          // Stimmung (Panda-Chip)
          moodLabel: _moodLabelOf(e),
          onEdit: null,
        ),
      ),
    );
  }

  // Falls Story keinen expliziten Titel hat, fällt sauber auf e.title zurück.
  String? _storyTitleFor(jm.JournalEntry e) {
    final t = (e.storyTitle ?? '').trim();
    if (t.isNotEmpty) return t;
    final fallback = (e.title ?? '').trim();
    return fallback.isEmpty ? null : fallback;
  }

  Future<void> _continueIntoReflection(
    BuildContext context,
    jp.JournalEntriesProvider provider,
    jm.JournalEntry e,
  ) async {
    provider.hide(e.id);

    final seed = (() {
      if ((e.thoughtText ?? '').trim().isNotEmpty) return e.thoughtText!.trim();
      if ((e.userAnswer ?? '').trim().isNotEmpty) return e.userAnswer!.trim();
      if ((e.aiQuestion ?? '').trim().isNotEmpty) return e.aiQuestion!.trim();
      return _computedTitle(e);
    })();

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReflectionScreen(initialUserText: seed)),
    );
  }

  void _startNewEntry(BuildContext context, jp.JournalEntriesProvider provider) {
    final active = provider.filterKind;

    switch (active) {
      case jp.JournalFilterKind.journal:
        _showNewDiarySheet(context, provider);
        return;
      case jp.JournalFilterKind.reflection:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReflectionScreen()),
        );
        return;
      case jp.JournalFilterKind.story:
        _showStoryStartSheet(context);
        return;
      case jp.JournalFilterKind.all:
        _showNewEntryChooser(context, provider);
        return;
    }
  }

  // ———————————————————————— Bottom Sheets ————————————————————————

  void _showNewDiarySheet(
      BuildContext context, jp.JournalEntriesProvider provider) {
    final titleCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final padBottom = MediaQuery.of(ctx).viewInsets.bottom + 16;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, padBottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Neuen Gedanken festhalten',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: zs.ZenColors.deepSage,
                    ),
              ),
              const SizedBox(height: 10),
              // Titel (optional) – wird zur Kompatibilität in den Text eingearbeitet.
              TextField(
                controller: titleCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Überschrift (optional)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: textCtrl,
                maxLines: 5,
                minLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Was möchtest du festhalten?',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Schließen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Festhalten'),
                      onPressed: () {
                        final t = textCtrl.text.trim();
                        final title = titleCtrl.text.trim();
                        if (t.isEmpty && title.isEmpty) return;
                        final merged = title.isNotEmpty ? '$title\n\n$t' : t;
                        provider.addDiary(text: merged);
                        Navigator.pop(ctx);
                        HapticFeedback.selectionClick();
                        zw.ZenToast.show(context, 'Tagebuch-Eintrag gespeichert');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  void _showNewEntryChooser(
      BuildContext context, jp.JournalEntriesProvider provider) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: const Text('Tagebuch-Eintrag'),
              onTap: () {
                Navigator.pop(ctx);
                _showNewDiarySheet(context, provider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology_alt_rounded),
              title: const Text('Neue Reflexion'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReflectionScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_stories_rounded),
              title: const Text('Neue Kurzgeschichte'),
              subtitle: const Text('Aus deinen Reflexionen generieren'),
              onTap: () {
                Navigator.pop(ctx);
                _showStoryStartSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showStoryStartSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Kurzgeschichte starten',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: zs.ZenColors.deepSage,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kurzgeschichten entstehen aus deinen Reflexionen. '
                'Beginne jetzt eine neue Reflexion — die Geschichte erscheint danach im Gedankenbuch.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reflexion starten'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReflectionScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ———————————————————————— Helpers ————————————————————————

  List<_DayGroup> _groupByDay(List<jm.JournalEntry> items) {
    if (items.isEmpty) return const <_DayGroup>[];
    final list = items.toList()
      ..sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });

    final groups = <int, List<jm.JournalEntry>>{};
    for (final e in list) {
      final d = e.createdAt.toLocal();
      final key = d.year * 10000 + d.month * 100 + d.day;
      (groups[key] ??= <jm.JournalEntry>[]).add(e);
    }

    final out = <_DayGroup>[];
    groups.forEach((key, list) {
      list.sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
      final y = key ~/ 10000;
      final m = (key % 10000) ~/ 100;
      final d = key % 100;
      out.add(_DayGroup(DateTime(y, m, d), List.unmodifiable(list)));
    });
    out.sort((a, b) => b.dateOnly.compareTo(a.dateOnly));
    return out;
  }

  // ——— Local fallbacks for fehlende Model-Getter ———

  String? _moodLabelOf(jm.JournalEntry e) {
    for (final t in e.tags) {
      final s = t.trim();
      if (s.toLowerCase().startsWith('mood:')) {
        final raw = s.substring(5).trim();
        if (raw.isEmpty) return null;
        // Erster Buchstabe groß
        return raw[0].toUpperCase() + raw.substring(1);
      }
    }
    return null;
  }

  String _computedTitle(jm.JournalEntry e) {
    String pickFirstNonEmpty(Iterable<String?> opts) {
      for (final s in opts) {
        final v = (s ?? '').trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final base = pickFirstNonEmpty([
      e.title,
      e.userAnswer,
      e.thoughtText,
      e.aiQuestion,
    ]);

    if (base.isEmpty) {
      final d = e.createdAt.toLocal();
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      return 'Eintrag $dd.$mm.${d.year}';
    }
    final words = base.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 10) return base;
    return '${words.take(10).join(' ')}…';
  }
}

// ———————————————————————— Kleine UI-Bausteine ————————————————————————

class _FilterPill extends StatelessWidget {
  final jp.JournalEntriesProvider provider;
  final int allCount;
  final int journalCount;
  final int reflectionCount;
  final int storyCount;

  const _FilterPill({
    required this.provider,
    required this.allCount,
    required this.journalCount,
    required this.reflectionCount,
    required this.storyCount,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(jp.JournalFilterKind kind, String label, IconData icon, int count) {
      final selected = provider.filterKind == kind;
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: FilterChip(
          selected: selected,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            provider.setFilter(kind);
          },
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? zs.ZenColors.deepSage : zs.ZenColors.jadeMid,
              ),
              const SizedBox(width: 6),
              Text('$label ($count)'),
            ],
          ),
          selectedColor: zs.ZenColors.sage.withOpacity(.22),
          backgroundColor: zs.ZenColors.white.withOpacity(.18),
          showCheckmark: false,
          labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? zs.ZenColors.deepSage : zs.ZenColors.jadeMid,
                fontWeight: FontWeight.w700,
              ),
          side: BorderSide(
            color: selected
                ? zs.ZenColors.deepSage
                : zs.ZenColors.jadeMid.withOpacity(.22),
          ),
          shape: const StadiumBorder(),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center, // zentriert unter dem Panda
      children: [
        chip(jp.JournalFilterKind.all, 'Alle', Icons.all_inclusive_rounded, allCount),
        chip(jp.JournalFilterKind.journal, 'Tagebuch', Icons.menu_book_rounded, journalCount),
        chip(jp.JournalFilterKind.reflection, 'Reflexion', Icons.psychology_alt_rounded, reflectionCount),
        chip(jp.JournalFilterKind.story, 'Kurzgeschichte', Icons.auto_stories_rounded, storyCount),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime date;
  const _DayHeader({required this.date});

  String _label(DateTime d) {
    final local = d.toLocal();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    bool same(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (same(local, today)) return 'Heute';
    if (same(local, yesterday)) return 'Gestern';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd.$mo.${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final txt = _label(date);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        header: true,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.66),
            borderRadius: const BorderRadius.all(zs.ZenRadii.m),
            border: Border.all(
              color: zs.ZenColors.jadeMid.withOpacity(0.14),
              width: 1,
            ),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
          ),
          child: Text(
            txt,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: zs.ZenColors.deepSage,
                ),
          ),
        ),
      ),
    );
  }
}

/// Timeline-Reihe OHNE IntrinsicHeight (Crash-Fix):
/// Die Karte bestimmt die Höhe. Links eine schmale Fläche mit CustomPaint,
/// die via Align auf die volle Kartenhöhe gestreckt wird.
class _TimelineRow extends StatelessWidget {
  final bool showAbove;
  final bool showBelow;
  final Widget child;

  const _TimelineRow({
    super.key,
    required this.showAbove,
    required this.showBelow,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Die Karte (bestimmt die Höhe)
        Padding(
          padding: const EdgeInsets.only(left: 32), // Platz für Rail + Abstand
          child: child,
        ),
        // Linke Rail, über die volle Höhe der Karte
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 26,
            child: CustomPaint(
              painter: _RailPainter(showAbove: showAbove, showBelow: showBelow),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailPainter extends CustomPainter {
  final bool showAbove;
  final bool showBelow;

  _RailPainter({required this.showAbove, required this.showBelow});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final dotY = size.height / 2;

    final linePaint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    Shader grad(Offset from, Offset to) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x2A6E8B74), // sage-ish
            Color(0x442F5F49), // deep sage-ish
            Color(0x2A6E8B74),
          ],
        ).createShader(Rect.fromPoints(from, to));

    if (showAbove) {
      final p1 = Offset(centerX, 0);
      final p2 = Offset(centerX, dotY - 5);
      canvas.drawLine(p1, p2, linePaint..shader = grad(p1, p2));
    }
    if (showBelow) {
      final p1 = Offset(centerX, dotY + 5);
      final p2 = Offset(centerX, size.height);
      canvas.drawLine(p1, p2, linePaint..shader = grad(p1, p2));
    }

    final dotPaint = Paint()
      ..color = const Color(0xFF2F5F49).withOpacity(.28)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.drawCircle(Offset(centerX, dotY), 4.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.showAbove != showAbove || old.showBelow != showBelow;
}

// Gruppentyp für die Tagesanzeige
class _DayGroup {
  final DateTime dateOnly; // 00:00 lokales Datum
  final List<jm.JournalEntry> items;
  const _DayGroup(this.dateOnly, this.items);
}
