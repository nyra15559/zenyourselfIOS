// lib/features/_legacy_gedankenbuch/gedankenbuch_timeline.dart
//
// GedankenbuchTimelineScreen — Oxford-Zen v8.2 (Calm Glass Timeline + Stories + Bulk Delete)
// -----------------------------------------------------------------------------------------
// Highlights
// • Eine ruhige, einheitliche Timeline für Journal, Reflexion **und** Kurzgeschichte.
// • Glas-Karten, sanfter Stagger, performante Rail via CustomPaint.
// • Filterchips: Alle · Tagebuch · Reflexion · Kurzgeschichte  — mit Zähler (auch 0).
// • „Alle löschen“ in der App-Bar: löscht lokale Items; versucht Provider-Clear, sonst blendet aus.
// • Tap: Journal/Reflexion/Story → Vollbild-Viewer (Story-Viewer aktiv).
// • Lokale Edit/Löschen via BottomSheet (ALT) bleiben erhalten.
//
// Abhängigkeiten (im Projekt vorhanden):
//   ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, PandaMoodChip
//   GedankenbuchEntryCard (ALT-Sheet), GedankenbuchEntryScreen (Composer)
//
// WICHTIG
// • Neues Model (kanonisch): lib/models/journal_entry.dart (als jm importiert)
// • Viewer alias: jv.JournalEntryView (um EntryKind-Konflikte zu vermeiden)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Zen DNA
import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenGlassInput, ZenAppBar;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, PandaMoodChip;

// Unified Composer (neuer Editor)
import 'gedankenbuch_entry_screen.dart' show GedankenbuchEntryScreen;

// ALT (Übergang – lokale Edit/Bearbeiten via Sheet)
import 'gedankenbuch_entry_card.dart' show GedankenbuchEntryCard, EntryType;

// Viewer (alias, um EntryKind-Konflikte zu vermeiden)
import '../journal/journal_entry_view.dart' as jv show JournalEntryView, EntryKind;

// Legacy-lokales Model (für Übergangsliste)
import '../../models/_legacy/gedankenbuch_entry.dart' show GedankenbuchEntry;

// Globales Journal / Provider (KANON)
import '../../providers/journal_entries_provider.dart';
import '../../models/journal_entry.dart' as jm;

import '../reflection/reflection_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Filter
// ─────────────────────────────────────────────────────────────────────────────

enum _Filter { all, journal, reflection, story }

class _FilterCounts {
  final int all;
  final int journal;
  final int reflection;
  final int story;
  const _FilterCounts({
    required this.all,
    required this.journal,
    required this.reflection,
    required this.story,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Public Screen
// ─────────────────────────────────────────────────────────────────────────────

class GedankenbuchTimelineScreen extends StatefulWidget {
  // Übergangs-API (lokale Liste + Callbacks), bleibt abwärtskompatibel:
  final List<GedankenbuchEntry> entries;
  final void Function(String text, String mood, {bool isReflection}) onAdd;
  final void Function(int idx, String text, String mood, {bool isReflection})
      onEdit;
  final void Function(int idx) onDelete;

  const GedankenbuchTimelineScreen({
    Key? key,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<GedankenbuchTimelineScreen> createState() =>
      _GedankenbuchTimelineScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
// View-Union (lokal + Provider) + Mapping
// ─────────────────────────────────────────────────────────────────────────────

enum _EntryKindView { journal, reflection, story }

class _EntryView {
  final String? id; // Provider-ID (falls vorhanden)
  final DateTime date;

  final _EntryKindView kind;

  // Gemeinsame Felder
  final String text; // Tagebuch: Inhalt · Reflexion: letzte Antwort · Story: Teaser/Title
  final String mood; // Label (bei Story meist '')

  // Reflexion
  final String? aiQuestion;
  final String? thought;

  // Story
  final String? storyTitle;
  final String? storyTeaser;

  // Lokal-spezifische Aktionen (nur lokale Items)
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  _EntryView({
    required this.id,
    required this.date,
    required this.kind,
    required this.text,
    required this.mood,
    this.aiQuestion,
    this.thought,
    this.storyTitle,
    this.storyTeaser,
    this.onEdit,
    this.onDelete,
  });

  factory _EntryView.fromLocal(
    GedankenbuchEntry e, {
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return _EntryView(
      id: null,
      date: e.date,
      kind: e.isReflection ? _EntryKindView.reflection : _EntryKindView.journal,
      text: e.text,
      mood: e.mood,
      aiQuestion: e.isReflection ? e.aiQuestion : null,
      thought: null,
      storyTitle: null,
      storyTeaser: null,
      onEdit: onEdit,
      onDelete: onDelete,
    );
    }

  factory _EntryView.fromJournal(jm.JournalEntry j) {
    final isRefl = j.kind == jm.EntryKind.reflection;
    final isStory = j.kind == jm.EntryKind.story;

    String _moodFromTags(List<String> tags) {
      for (final t in tags) {
        final s = t.trim();
        if (s.startsWith('mood:')) return s.substring(5);
      }
      for (final t in tags) {
        final s = t.trim();
        if (s.startsWith('moodScore:')) {
          final n = int.tryParse(s.substring(10));
          switch (n) {
            case 0:
              return 'Sehr schlecht';
            case 1:
              return 'Eher schlecht';
            case 2:
              return 'Neutral';
            case 3:
              return 'Eher gut';
            case 4:
              return 'Sehr gut';
          }
        }
      }
      return '';
    }

    final moodLabel = _moodFromTags(j.tags);

    final String textForList = () {
      if (isStory) {
        final teaser = (j.storyTeaser ?? '').trim();
        if (teaser.isNotEmpty) return teaser;
        final titleSafe = ((j.storyTitle ?? j.title) ?? '').trim();
        return titleSafe.isNotEmpty ? titleSafe : 'Kurzgeschichte';
      }
      if (isRefl) {
        final ans = (j.userAnswer ?? '').trim();
        if (ans.isNotEmpty) return ans;
        final thought = (j.thoughtText ?? '').trim();
        if (thought.isNotEmpty) return thought;
        final q = (j.aiQuestion ?? '').trim();
        return q.isNotEmpty ? q : 'Reflexion';
      }
      // Journal
      final t = (j.thoughtText ?? '').trim();
      if (t.isNotEmpty) return t;
      final title = (j.title ?? '').trim();
      return title.isNotEmpty ? title : 'Gedanke';
    }();

    return _EntryView(
      id: j.id,
      date: j.createdAt,
      kind: isStory
          ? _EntryKindView.story
          : (isRefl ? _EntryKindView.reflection : _EntryKindView.journal),
      text: textForList,
      mood: isStory ? '' : moodLabel,
      aiQuestion: isRefl ? j.aiQuestion : null,
      thought: isRefl ? j.thoughtText : null,
      storyTitle:
          isStory ? ((j.storyTitle?.trim().isNotEmpty == true ? j.storyTitle : j.title)) : null,
      storyTeaser: isStory ? j.storyTeaser : null,
      onEdit: null,
      onDelete: null,
    );
  }

  bool get isReflection => kind == _EntryKindView.reflection;
  bool get isJournal => kind == _EntryKindView.journal;
  bool get isStory => kind == _EntryKindView.story;

  String get key {
    final kindCode = isReflection ? 'R' : (isStory ? 'S' : 'J');
    return '${date.microsecondsSinceEpoch}-$kindCode-${text.hashCode}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _GedankenbuchTimelineScreenState extends State<GedankenbuchTimelineScreen> {
  static const double _maxContentWidth = 820;
  static const Duration _mergeDupeWindow = Duration(seconds: 30);

  _Filter _filter = _Filter.all;

  // Schonendes Verbergen-Set (nicht persistent)
  final Set<String> _hiddenKeys = <String>{};

  // ───────────── Merge/Dedupe ─────────────

  String _norm(String? s) {
    if (s == null) return '';
    final t = s.trim();
    if (t.isEmpty) return '';
    return t.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _fp(_EntryView v) => [
        _norm(v.text),
        _norm(v.mood),
        v.isReflection ? 'r1' : (v.isStory ? 's1' : 'j1'),
        _norm(v.aiQuestion),
      ].join('|');

  bool _isSameEntry(_EntryView a, _EntryView b) {
    if (_fp(a) != _fp(b)) return false;
    final da = a.date.toUtc();
    final db = b.date.toUtc();
    return da.difference(db).abs() <= _mergeDupeWindow;
  }

  List<_EntryView> _mergeProviderAndLocal(
    List<_EntryView> providerViews,
    List<_EntryView> localViews,
  ) {
    final merged = <_EntryView>[...providerViews];
    for (final lv in localViews) {
      final dup = providerViews.any((pv) => _isSameEntry(pv, lv));
      if (!dup) merged.add(lv);
    }
    merged.sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }

  // ───────────── Hidden ─────────────

  void _hideView(_EntryView v) {
    _hiddenKeys.add(v.key);
    setState(() {});
    HapticFeedback.selectionClick();
  }

  bool _isHidden(_EntryView v) => _hiddenKeys.contains(v.key);

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 560;

    // 1) Provider lesen (KANON)
    final providerEntries =
        context.select<JournalEntriesProvider?, List<jm.JournalEntry>>(
      (p) => p?.entries ?? const <jm.JournalEntry>[],
    );

    // 2) Provider→View (inkl. Stories)
    final providerViews =
        providerEntries.map<_EntryView>(_EntryView.fromJournal).toList();

    // 3) Lokale Liste als Fallback/Ergänzung
    final localViews = <_EntryView>[];
    for (var i = 0; i < widget.entries.length; i++) {
      final e = widget.entries[i];
      localViews.add(
        _EntryView.fromLocal(
          e,
          onEdit: () => _editEntry(context, i, e),
          onDelete: () => _confirmDeleteLocal(context, i),
        ),
      );
    }

    // 4) Merge
    final allViews = _mergeProviderAndLocal(providerViews, localViews);

    // 5) Filter
    List<_EntryView> filtered;
    switch (_filter) {
      case _Filter.journal:
        filtered = allViews.where((e) => e.isJournal).toList();
        break;
      case _Filter.reflection:
        filtered = allViews.where((e) => e.isReflection).toList();
        break;
      case _Filter.story:
        filtered = allViews.where((e) => e.isStory).toList();
        break;
      case _Filter.all:
      default:
        filtered = allViews;
        break;
    }

    // 6) Hidden anwenden
    filtered = filtered.where((v) => !_isHidden(v)).toList();

    final counts = _FilterCounts(
      all: allViews.where((v) => !_isHidden(v)).length,
      journal: allViews.where((e) => e.isJournal && !_isHidden(e)).length,
      reflection:
          allViews.where((e) => e.isReflection && !_isHidden(e)).length,
      story: allViews.where((e) => e.isStory && !_isHidden(e)).length,
    );

    final isEmpty = filtered.isEmpty;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: zw.ZenAppBar(
        title: null,
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Alle löschen',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () => _confirmDeleteAll(context),
          ),
        ],
      ),
      floatingActionButton: _NewEntryFab(
        isEmpty: isEmpty,
        onTap: () => _openNewEntry(context),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: zw.ZenBackdrop(
              asset: 'assets/schoen.png',
              alignment: Alignment.center,
              glow: .28,
              vignette: .12,
              enableHaze: false,
              hazeStrength: .12,
              saturation: .95,
              wash: .06,
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: isMobile ? 20 : 36, bottom: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: _buildListArea(
                  context,
                  filtered,
                  isMobile,
                  counts,
                  isEmpty,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // List/Items inkl. Header + Filter
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildListArea(
    BuildContext context,
    List<_EntryView> views,
    bool isMobile,
    _FilterCounts counts,
    bool isEmpty,
  ) {
    final items = _buildTimelineItems(views);

    // Empty-State
    if (isEmpty) {
      final pandaSize = MediaQuery.of(context).size.width < 470 ? 88.0 : 112.0;
      return ListView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
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
            topOpacity: .24,
            bottomOpacity: .10,
            borderOpacity: .14,
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
                  'Wenn dir etwas auffällt oder du etwas festhalten möchtest, tippe auf „Neuer Eintrag“.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Neuer Eintrag'),
                  onPressed: () => _openNewEntry(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: zs.ZenColors.deepSage,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(zs.ZenRadii.m),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      );
    }

    return ListView.builder(
      key: const PageStorageKey('gb_timeline_list'),
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? zs.ZenSpacing.s : zs.ZenSpacing.xl,
      ),
      // + Panda-Header + Filter-Header + Gap
      itemCount: items.length + 3,
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
          return Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 12),
            child: zw.ZenGlassCard(
              borderRadius: const BorderRadius.all(zs.ZenRadii.l),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              topOpacity: .24,
              bottomOpacity: .10,
              borderOpacity: .14,
              child: _FilterHeader(
                current: _filter,
                counts: counts,
                onChanged: (f) {
                  HapticFeedback.selectionClick();
                  setState(() => _filter = f);
                },
              ),
            ),
          );
        }
        if (i == 2) return const SizedBox(height: 6);

        final it = items[i - 3];
        final delayMs = (i - 3) >= 0 ? 28 * ((i - 3) % 8) : 0;

        switch (it.kind) {
          case _TLKind.header:
            return _StaggerFadeSlide(
              delay: Duration(milliseconds: delayMs),
              child: Padding(
                padding: const EdgeInsets.only(
                    top: zs.ZenSpacing.s, bottom: 6),
                child: _DayHeader(date: it.date!),
              ),
            );
          case _TLKind.entry:
            return _StaggerFadeSlide(
              delay: Duration(milliseconds: delayMs + 36),
              child: _TimelineRow(
                showAbove: it.showAbove,
                showBelow: it.showBelow,
                child: _GlassEntryCard(
                  key: ValueKey(it.view!.key),
                  view: it.view!,
                  onOpen: () => _openViewer(context, it.view!),
                  onContinueReflection: () =>
                      _continueIntoReflection(context, it.view!),
                  onHide: () => _hideView(it.view!),
                ),
              ),
            );
          case _TLKind.gap:
            return const SizedBox(height: zs.ZenSpacing.s);
        }
      },
    );
  }

  List<_TLItem> _buildTimelineItems(List<_EntryView> views) {
    final items = <_TLItem>[];
    DateTime? lastDay;

    for (var i = 0; i < views.length; i++) {
      final e = views[i];
      final dLocal = e.date.toLocal();
      final day = DateTime(dLocal.year, dLocal.month, dLocal.day);
      final isNewDay = lastDay == null || day != lastDay;
      if (isNewDay) items.add(_TLItem.header(day));

      final prevLocal = i > 0 ? views[i - 1].date.toLocal() : null;
      final nextLocal = i < views.length - 1 ? views[i + 1].date.toLocal() : null;

      final hasPrevSameDay = prevLocal != null && _sameDayLocal(dLocal, prevLocal);
      final hasNextSameDay = nextLocal != null && _sameDayLocal(dLocal, nextLocal);

      items.add(
        _TLItem.entry(
          e,
          showAbove: hasPrevSameDay,
          showBelow: hasNextSameDay,
        ),
      );
      items.add(_TLItem.gap());
      lastDay = day;
    }
    return items;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Actions / Composer / Viewer
  // ───────────────────────────────────────────────────────────────────────────

  void _openNewEntry(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GedankenbuchEntryScreen(
          onSave: (text, mood) {
            var providerOk = false;
            try {
              context.read<JournalEntriesProvider>().addDiary(
                    text: text,
                    moodLabel: mood,
                  );
              providerOk = true;
            } catch (_) {}
            if (!providerOk) {
              widget.onAdd(text, mood, isReflection: false);
            }
          },
        ),
      ),
    );
  }

  void _editEntry(BuildContext context, int idx, GedankenbuchEntry entry) {
    _presentEntryCardSheet(
      context,
      type: entry.isReflection ? EntryType.reflexion : EntryType.journal,
      initialText: entry.text,
      initialMood: entry.mood,
      aiQuestion: entry.aiQuestion,
      onPersist: (text, mood, {aiQuestion}) async {
        widget.onEdit(idx, text, mood, isReflection: entry.isReflection);
        HapticFeedback.selectionClick();
      },
    );
  }

  Future<void> _continueIntoReflection(
      BuildContext context, _EntryView v) async {
    // Stories: optional Reflexion aus Titel/Teaser starten
    final seed = v.isStory
        ? [v.storyTitle, v.storyTeaser]
            .where((s) => (s ?? '').trim().isNotEmpty)
            .join(' — ')
        : v.text;

    if (v.id != null && !v.isStory) {
      _hideView(v); // Provider-Item weich ausblenden (Journal/Reflexion)
    } else if (v.onDelete != null && !v.isStory) {
      try {
        v.onDelete!.call();
      } catch (_) {}
    }

    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReflectionScreen(initialUserText: seed),
      ),
    );
  }

  Future<void> _openViewer(BuildContext context, _EntryView v) async {
    HapticFeedback.selectionClick();

    // Ab jetzt: Story wird regulär angezeigt (kein Platzhalter).
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => jv.JournalEntryView(
          kind: v.isStory
              ? jv.EntryKind.story
              : (v.isReflection ? jv.EntryKind.reflection : jv.EntryKind.journal),
          createdAt: v.date,
          // Journal
          journalText: v.isReflection || v.isStory ? null : v.text,
          // Reflexion
          userThought: v.isReflection ? v.thought : null,
          aiQuestion: v.isReflection ? v.aiQuestion : null,
          userAnswer: v.isReflection ? v.text : null,
          // Story
          storyTitle: v.isStory ? v.storyTitle : null,
          storyTeaser: v.isStory ? v.storyTeaser : null,
          // storyBody derzeit nicht im View; Teaser wird im Viewer genutzt.
          onEdit: v.onEdit, // lokale Items: ALT-Editor
        ),
      ),
    );
  }

  // ALT-Sheet
  void _presentEntryCardSheet(
    BuildContext context, {
    required EntryType type,
    String? initialText,
    String? initialMood,
    String? aiQuestion,
    required Future<void> Function(
      String text,
      String mood, {
      String? aiQuestion,
    })
        onPersist,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.25),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: zs.ZenRadii.xl,
              topRight: zs.ZenRadii.xl,
            ),
            child: GedankenbuchEntryCard(
              entryType: type,
              initialText: initialText,
              initialMood: initialMood,
              aiQuestion: aiQuestion,
              onSave: (text, mood, {aiQuestion, bool isReflection = false}) async {
                await onPersist(text, mood, aiQuestion: aiQuestion);
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteLocal(BuildContext context, int idx) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Eintrag löschen?'),
        content:
            const Text('Dieser Schritt kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Löschen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      widget.onDelete(idx); // nur lokale Items
      if (mounted) setState(() {});
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Bulk Delete (App-Bar)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final choice = await showDialog<_BulkDeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Alle Einträge löschen?'),
        content: const Text(
            'Du kannst nur lokale Einträge löschen oder versuchen, alle Einträge '
            '(inkl. Provider) zu entfernen. Wenn der Provider das nicht unterstützt, '
            'blenden wir sie aus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _BulkDeleteChoice.cancel),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _BulkDeleteChoice.localOnly),
            child: const Text('Nur lokale löschen'),
          ),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pop(ctx, _BulkDeleteChoice.allIfPossible),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Alles löschen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == _BulkDeleteChoice.cancel) {
      return;
    }

    if (choice == _BulkDeleteChoice.localOnly) {
      _deleteAllLocal();
      return;
    }
    _deleteAllIncludingProvider();
  }

  void _deleteAllLocal() {
    // Von hinten nach vorn, damit Indizes stabil bleiben.
    for (int i = widget.entries.length - 1; i >= 0; i--) {
      try {
        widget.onDelete(i);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Alle lokalen Einträge gelöscht.'),
          backgroundColor: zs.ZenColors.deepSage,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(zs.ZenRadii.m),
          ),
        ),
      );
    }
  }

  void _deleteAllIncludingProvider() {
    bool providerCleared = false;

    // Sicherer Versuch, eine optionale clearAll()-API des Providers aufzurufen.
    try {
      final prov = context.read<JournalEntriesProvider>();
      (prov as dynamic).clearAll(); // wir fangen NoSuchMethod unten ab
      providerCleared = true;
    } catch (_) {
      providerCleared = false;
    }

    // Lokale Einträge immer löschen
    _deleteAllLocal();

    if (!providerCleared) {
      // Fallback: Provider-Items weich ausblenden (UI-only)
      try {
        final entries =
            context.read<JournalEntriesProvider?>()?.entries ??
                const <jm.JournalEntry>[];
        for (final e in entries) {
          final v = _EntryView.fromJournal(e);
          _hiddenKeys.add(v.key);
        }
      } catch (_) {}
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Provider-Löschen nicht verfügbar – Einträge ausgeblendet.'),
            backgroundColor: zs.ZenColors.deepSage,
            behavior: SnackBarBehavior.floating,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(zs.ZenRadii.m),
            ),
          ),
        );
      }
    } else {
      if (mounted) setState(() {});
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Utils
  // ───────────────────────────────────────────────────────────────────────────

  bool _sameDayLocal(DateTime a, DateTime b) {
    final al = a.toLocal(), bl = b.toLocal();
    return al.year == bl.year && al.month == bl.month && al.day == bl.day;
  }
}

enum _BulkDeleteChoice { cancel, localOnly, allIfPossible }

// ─────────────────────────────────────────────────────────────────────────────
// UI-Widgets: FAB, FilterHeader, Header, TimelineRow, Painter
// ─────────────────────────────────────────────────────────────────────────────

class _NewEntryFab extends StatelessWidget {
  final bool isEmpty;
  final VoidCallback onTap;
  const _NewEntryFab({required this.isEmpty, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = isEmpty ? zs.ZenColors.deepSage : zs.ZenColors.jadeMid;
    return FloatingActionButton.extended(
      heroTag: isEmpty ? 'gb_add_empty' : 'gb_add',
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Neuer Eintrag'),
      backgroundColor: bg,
      foregroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(zs.ZenRadii.m),
      ),
      elevation: 2.5,
      tooltip:
          isEmpty ? 'Neuen Eintrag verfassen' : 'Neuen Tagebucheintrag verfassen',
    );
  }
}

class _FilterHeader extends StatelessWidget {
  final _Filter current;
  final ValueChanged<_Filter> onChanged;
  final _FilterCounts counts;
  const _FilterHeader({
    required this.current,
    required this.onChanged,
    required this.counts,
  });

  int _countFor(_Filter f) {
    switch (f) {
      case _Filter.all:
        return counts.all;
      case _Filter.journal:
        return counts.journal;
      case _Filter.reflection:
        return counts.reflection;
      case _Filter.story:
        return counts.story;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(_Filter f, String label, IconData icon) {
      final selected = current == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: FilterChip(
          selected: selected,
          onSelected: (_) => onChanged(f),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? zs.ZenColors.deepSage : zs.ZenColors.jadeMid),
              const SizedBox(width: 6),
              Text('$label (${_countFor(f)})'),
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
      children: [
        chip(_Filter.all, 'Alle', Icons.all_inclusive_rounded),
        chip(_Filter.journal, 'Tagebuch', Icons.menu_book_rounded),
        chip(_Filter.reflection, 'Reflexion', Icons.psychology_alt_rounded),
        chip(_Filter.story, 'Kurzgeschichte', Icons.auto_stories_rounded),
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

class _TimelineRow extends StatelessWidget {
  final bool showAbove;
  final bool showBelow;
  final Widget child;

  const _TimelineRow({
    required this.showAbove,
    required this.showBelow,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: CustomPaint(
              painter: _RailPainter(showAbove: showAbove, showBelow: showBelow),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: child),
        ],
      ),
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

    final linePaint = Paint()..strokeWidth = 2..style = PaintingStyle.stroke;

    Shader grad(Offset from, Offset to) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            zs.ZenColors.sage.withOpacity(.18),
            zs.ZenColors.deepSage.withOpacity(.26),
            zs.ZenColors.sage.withOpacity(.18),
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
      ..color = zs.ZenColors.deepSage.withOpacity(.28)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.drawCircle(Offset(centerX, dotY), 4.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.showAbove != showAbove || old.showBelow != showBelow;
}

// ─────────────────────────────────────────────────────────────────────────────
// Karten
// ─────────────────────────────────────────────────────────────────────────────

class _GlassEntryCard extends StatefulWidget {
  final _EntryView view;
  final VoidCallback onOpen; // öffnet Viewer / Hinweis
  final VoidCallback onContinueReflection; // in Reflexion fortsetzen
  final VoidCallback onHide; // „Verbergen“ (Provider)

  const _GlassEntryCard({
    Key? key,
    required this.view,
    required this.onOpen,
    required this.onContinueReflection,
    required this.onHide,
  }) : super(key: key);

  @override
  State<_GlassEntryCard> createState() => _GlassEntryCardState();
}

class _GlassEntryCardState extends State<_GlassEntryCard>
    with AutomaticKeepAliveClientMixin<_GlassEntryCard> {
  bool _expanded = false;

  @override
  bool get wantKeepAlive => _expanded;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final v = widget.view;

    final combinedLen = v.text.trim().length +
        (v.aiQuestion?.length ?? 0) +
        (v.thought?.length ?? 0) +
        (v.storyTeaser?.length ?? 0);
    final needsExpand = v.isReflection
        ? combinedLen > 160
        : (v.isJournal
            ? v.text.trim().length > 160
            : (v.storyTeaser ?? '').length > 160);

    return Semantics(
      label: v.isReflection
          ? 'Reflexionseintrag'
          : (v.isStory ? 'Kurzgeschichte' : 'Tagebucheintrag'),
      child: zw.ZenGlassCard(
        margin: const EdgeInsets.symmetric(vertical: zs.ZenSpacing.s),
        padding: const EdgeInsets.fromLTRB(18, 18, 12, 14),
        borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
        topOpacity: .24,
        bottomOpacity: .10,
        borderOpacity: .14,
        child: InkWell(
          borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
          onTap: widget.onOpen,
          child: Stack(
            children: [
              if (v.isReflection)
                const Positioned(
                  top: 4,
                  left: 2,
                  child: _Badge(
                      label: 'Reflexion',
                      icon: Icons.psychology_alt_outlined),
                ),
              if (v.isStory)
                const Positioned(
                  top: 4,
                  left: 2,
                  child: _Badge(
                      label: 'Kurzgeschichte',
                      icon: Icons.auto_stories_rounded),
                ),

              Padding(
                padding: EdgeInsets.fromLTRB(
                    0, (v.isReflection || v.isStory) ? 34 : 6, 6, 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (v.isReflection)
                            _ReflectionPreview(
                              question: v.aiQuestion,
                              answer: v.text,
                              thought: v.thought,
                              expanded: _expanded,
                            ),

                          if (v.isJournal)
                            AnimatedCrossFade(
                              crossFadeState: _expanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration:
                                  const Duration(milliseconds: 180),
                              firstChild: Text(
                                v.text,
                                maxLines: 4,
                                overflow: TextOverflow.fade,
                                style: const TextStyle(
                                  fontFamily: 'ZenKalligrafie',
                                  fontSize: 17.3,
                                  color: zs.ZenColors.jade,
                                  height: 1.28,
                                ),
                              ),
                              secondChild: Text(
                                v.text,
                                style: const TextStyle(
                                  fontFamily: 'ZenKalligrafie',
                                  fontSize: 17.3,
                                  color: zs.ZenColors.jade,
                                  height: 1.28,
                                ),
                              ),
                            ),

                          if (v.isStory)
                            _StoryPreview(
                              title: (v.storyTitle ?? '').trim().isEmpty
                                  ? 'Kurzgeschichte'
                                  : v.storyTitle!.trim(),
                              teaser: (v.storyTeaser ?? '').trim(),
                              expanded: _expanded,
                            ),

                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Text(
                                _formatDate(v.date),
                                style: zs.ZenTextStyles.caption.copyWith(
                                  color: Colors.black.withOpacity(.55),
                                ),
                              ),
                              if (!v.isStory && v.mood.trim().isNotEmpty) ...[
                                const SizedBox(width: 8),
                                zw.PandaMoodChip(mood: v.mood, small: true),
                              ],
                              const Spacer(),

                              if (!v.isStory)
                                Tooltip(
                                  message: 'In Reflexion fortsetzen',
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          zs.ZenColors.jadeMid,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      minimumSize: const Size(0, 40),
                                    ),
                                    onPressed:
                                        widget.onContinueReflection,
                                    icon: const Icon(
                                        Icons.playlist_add_rounded,
                                        size: 18),
                                    label: const Text(
                                        'In Reflexion fortsetzen'),
                                  ),
                                ),
                              if (v.isStory)
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: zs.ZenColors.jadeMid,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    minimumSize: const Size(0, 40),
                                  ),
                                  onPressed:
                                      widget.onContinueReflection,
                                  icon: const Icon(
                                      Icons.psychology_alt_rounded,
                                      size: 18),
                                  label: const Text('Reflexion starten'),
                                ),

                              if (needsExpand)
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        zs.ZenColors.jadeMid,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    minimumSize: const Size(0, 40),
                                  ),
                                  onPressed: () => setState(
                                      () => _expanded = !_expanded),
                                  icon: Icon(
                                      _expanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 18),
                                  label: Text(
                                      _expanded ? 'Weniger' : 'Mehr'),
                                ),

                              _MoreMenu(
                                hasLocalEdit:
                                    (v.id == null && v.onEdit != null),
                                hasLocalDelete:
                                    (v.id == null && v.onDelete != null),
                                canHide: v.id != null,
                                onEdit: v.onEdit,
                                onDelete: v.onDelete,
                                onHide: widget.onHide,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay =
        now.year == local.year && now.month == local.month && now.day == local.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (sameDay) return 'Heute, $hh:$mm';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd.$mo.${local.year}, $hh:$mm';
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Badge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      decoration: BoxDecoration(
        color: zs.ZenColors.mist.withOpacity(0.80),
        borderRadius: const BorderRadius.all(zs.ZenRadii.s),
        border: Border.all(color: zs.ZenColors.jadeMid.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: zs.ZenColors.jadeMid, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: zs.ZenColors.jade,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reflexions-Preview (Labels = Ink, Inhalte = Jade, Frage kursiv Ink)
class _ReflectionPreview extends StatelessWidget {
  final String? question;
  final String answer;
  final String? thought;
  final bool expanded;

  const _ReflectionPreview({
    Key? key,
    required this.question,
    required this.answer,
    required this.thought,
    required this.expanded,
  }) : super(key: key);

  TextStyle get _userStyle => const TextStyle(
        fontFamily: 'ZenKalligrafie',
        fontSize: 17.3,
        color: zs.ZenColors.jade,
        height: 1.28,
        fontWeight: FontWeight.w600,
      );

  TextStyle _labelStyle(BuildContext c) =>
      Theme.of(c).textTheme.labelMedium!.copyWith(
            color: zs.ZenColors.inkStrong,
            fontWeight: FontWeight.w700,
          );

  TextStyle _questionStyle(BuildContext c) =>
      Theme.of(c).textTheme.bodySmall!.copyWith(
            color: zs.ZenColors.inkStrong.withOpacity(.90),
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
          );

  @override
  Widget build(BuildContext context) {
    final hasThought = (thought ?? '').trim().isNotEmpty;
    final hasQuestion = (question ?? '').trim().isNotEmpty;

    final int qLines = expanded ? 32 : 1;
    final int aLines = expanded ? 32 : 3;
    final int tLines = expanded ? 32 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasThought) ...[
          Text('Dein Gedanke', style: _labelStyle(context)),
          const SizedBox(height: 4),
          Text('„${thought!.trim()}“',
              style: _userStyle,
              maxLines: tLines,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
        ],
        if (hasQuestion) ...[
          Text(question!.trim(),
              style: _questionStyle(context),
              maxLines: qLines,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
        ],
        Text('Deine Antwort', style: _labelStyle(context)),
        const SizedBox(height: 4),
        Text(
          answer.trim(),
          style: _userStyle,
          maxLines: aLines,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Story-Preview (Titel + Teaser, ruhige Typo)
class _StoryPreview extends StatelessWidget {
  final String title;
  final String teaser;
  final bool expanded;
  const _StoryPreview({
    Key? key,
    required this.title,
    required this.teaser,
    required this.expanded,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.isEmpty ? 'Kurzgeschichte' : title,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (teaser.isNotEmpty)
          Text(
            teaser,
            maxLines: expanded ? 32 : 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'ZenKalligrafie',
              fontSize: 17.0,
              color: zs.ZenColors.jade,
              height: 1.28,
            ),
          ),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final bool hasLocalEdit;
  final bool hasLocalDelete;
  final bool canHide;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onHide;

  const _MoreMenu({
    Key? key,
    required this.hasLocalEdit,
    required this.hasLocalDelete,
    required this.canHide,
    this.onEdit,
    this.onDelete,
    this.onHide,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final itemTextStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: zs.ZenColors.inkStrong,
              fontWeight: FontWeight.w600,
            );

    return PopupMenuButton<String>(
      tooltip: 'Mehr Optionen',
      offset: const Offset(0, 8),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];

        if (hasLocalEdit) {
          items.add(
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  const Icon(Icons.edit_rounded,
                      size: 18, color: zs.ZenColors.jadeMid),
                  const SizedBox(width: 10),
                  Text('Bearbeiten', style: itemTextStyle),
                ],
              ),
            ),
          );
        }

        if (hasLocalDelete) {
          items.add(
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: const [
                  Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.redAccent),
                  SizedBox(width: 10),
                  Text('Löschen',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          );
        }

        if (canHide) {
          items.add(
            PopupMenuItem(
              value: 'hide',
              child: Row(
                children: [
                  const Icon(Icons.visibility_off_rounded,
                      size: 18, color: zs.ZenColors.jadeMid),
                  const SizedBox(width: 10),
                  Text('Verbergen', style: itemTextStyle),
                ],
              ),
            ),
          );
        }

        return items;
      },
      onSelected: (value) {
        if (value == 'edit' && onEdit != null) onEdit!();
        if (value == 'delete' && onDelete != null) onDelete!();
        if (value == 'hide' && onHide != null) onHide!();
      },
      icon: const Icon(Icons.more_vert_rounded,
          size: 20, color: zs.ZenColors.jadeMid),
      padding: EdgeInsets.zero,
      elevation: 10,
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(zs.ZenRadii.m),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline-Items + Stagger
// ─────────────────────────────────────────────────────────────────────────────

enum _TLKind { header, entry, gap }

class _TLItem {
  final _TLKind kind;
  final DateTime? date;
  final _EntryView? view;
  final bool showAbove;
  final bool showBelow;

  _TLItem._(this.kind, this.date, this.view, this.showAbove, this.showBelow);

  factory _TLItem.header(DateTime date) =>
      _TLItem._(_TLKind.header, date, null, false, false);
  factory _TLItem.entry(_EntryView v,
          {required bool showAbove, required bool showBelow}) =>
      _TLItem._(_TLKind.entry, null, v, showAbove, showBelow);
  factory _TLItem.gap() => _TLItem._(_TLKind.gap, null, null, false, false);
}

class _StaggerFadeSlide extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const _StaggerFadeSlide({
    Key? key,
    required this.child,
    this.delay = const Duration(milliseconds: 0),
    this.duration = const Duration(milliseconds: 280),
  }) : super(key: key);

  @override
  State<_StaggerFadeSlide> createState() => _StaggerFadeSlideState();
}

class _StaggerFadeSlideState extends State<_StaggerFadeSlide> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, .06),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
