// lib/features/story/story_list_screen.dart
//
// StoryListScreen — Oxford Zen Edition (Pro)
// -------------------------------------------
// • Zeigt alle gespeicherten Stories (JournalEntry.type == story).
// • Schöne Empty-States, Pull-to-Refresh-Feeling (sanftes Delay), Swipe-Delete mit Guard.
// • FAB: Generiert eine neue Story aus den letzten N Reflexionen (3/5/7) via GuidanceService.
// • Navigation: Tap → StoryViewScreen, LongPress → Quick-Actions.
// • Barrierearm: Semantics, große Touch-Zonen, klare Labels.
// • Keine neuen Dependencies; nutzt Provider + bestehende Services.
//
// Hinweise:
// - Stories werden als JournalEntry(type: story, text: body) gespeichert.
// - Titel wird aus dem Body hergeleitet (erste sinnvolle Zeile).
// - audioUrl wird (falls vorhanden) momentan nicht persistiert; UI unterstützt es via View-Screen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/zen_style.dart';
import '../../shared/ui/zen_widgets.dart';
import '../../models/journal_entries_provider.dart';
import '../../data/journal_entry.dart';
import '../../services/guidance_service.dart';
import 'story_view_screen.dart';

class StoryListScreen extends StatefulWidget {
  const StoryListScreen({super.key});

  @override
  State<StoryListScreen> createState() => _StoryListScreenState();
}

class _StoryListScreenState extends State<StoryListScreen> {
  bool _busy = false;

  Future<void> _softRefresh() async {
    // Simuliert ein sanftes Refresh-Gefühl (z. B. um FutureBuilders zu entkoppeln)
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() {});
  }

  String _deriveTitle(String body) {
    final raw = body.trim();
    if (raw.isEmpty) return 'Kurzgeschichte';
    // Erste sinnvolle Zeile/Satz nehmen
    final firstLine = raw.split('\n').firstWhere(
          (e) => e.trim().isNotEmpty,
          orElse: () => raw,
        );
    final single = firstLine.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length > 60 ? '${single.substring(0, 57)}…' : single;
  }

  String _dateLabel(DateTime local) {
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final isYesterday = local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day;

    if (isToday) return 'Heute';
    if (isYesterday) return 'Gestern';
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return '$dd.$mm.${local.year}';
  }

  Future<void> _generateStory(BuildContext context) async {
    final provider = context.read<JournalEntriesProvider>();
    if (_busy) return;

    // Auswahl der Reflektionsmenge anbieten
    final n = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _PickCountSheet(),
    );

    if (n == null) return;

    // Letzte N Reflexionen einsammeln
    final reflections = provider.reflections;
    if (reflections.isEmpty) {
      if (!mounted) return;
      ZenToast.show(context, 'Keine Reflexionen gefunden.', tone: ZenToastTone.info);
      return;
    }
    final ids = reflections.take(n).map((e) => e.id).toList(growable: false);

    setState(() => _busy = true);
    try {
      final storyRes = await GuidanceService.instance.story(entryIds: ids);
      final created = provider.addEntry(
        text: storyRes.body,
        type: JournalType.story,
        id: storyRes.id, // stabil; Upsert-geeignet
        // moodLabel/aiQuestion nicht relevant für Story; bleiben leer.
      );

      if (!mounted) return;
      ZenToast.show(context, 'Story erstellt ✨');
      // Direkt öffnen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StoryViewScreen(
            title: _deriveTitle(created.text),
            body: created.text,
            audioUrl: null, // aktuell nicht persistiert
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ZenToast.show(context, 'Story konnte nicht erzeugt werden.', tone: ZenToastTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context, JournalEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Story löschen?'),
        content: const Text('Diese Story wird aus deinem Journal entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final provider = context.read<JournalEntriesProvider>();
    final removed = provider.remove(e.id);
    if (mounted) {
      ZenToast.show(
        context,
        removed ? 'Story gelöscht.' : 'Löschen fehlgeschlagen.',
        tone: removed ? ZenToastTone.info : ZenToastTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stories = context.watch<JournalEntriesProvider>().stories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stories'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _softRefresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _softRefresh,
        displacement: 20,
        child: stories.isEmpty ? _buildEmpty(context) : _buildList(context, stories),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _generateStory(context),
        label: _busy
            ? const Text('Erzeuge…')
            : const Text('Story erzeugen'),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 48),
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ZenColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ZenColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.menu_book_rounded, size: 48, color: ZenColors.jadeMid),
                const SizedBox(height: 12),
                Text(
                  'Noch keine Stories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Erzeuge aus deinen letzten Reflexionen eine kleine, warme Kurzgeschichte.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Jetzt Story erzeugen'),
                  onPressed: () => _generateStory(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 160),
      ],
    );
  }

  Widget _buildList(BuildContext context, List<JournalEntry> stories) {
    // Stories sind bereits DESC sortiert (neueste zuerst) durch Provider.
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: stories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = stories[i];
        final title = _deriveTitle(e.text);
        final date = _dateLabel(e.createdAtLocal);

        return Dismissible(
          key: ValueKey('story_${e.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
          confirmDismiss: (_) async {
            await _confirmDelete(context, e);
            // Dismissible selbst nicht auto-entfernen; Liste kommt aus Provider.
            return false;
          },
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StoryViewScreen(
                    title: title,
                    body: e.text,
                    audioUrl: null,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: ZenColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ZenColors.border),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.menu_book_outlined, color: ZenColors.jadeMid),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          e.preview(140),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 14, color: ZenColors.jadeMid),
                            const SizedBox(width: 6),
                            Text(
                              date,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: ZenColors.jadeMid),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// BottomSheet zur Auswahl, wie viele Reflexionen als Basis dienen sollen.
class _PickCountSheet extends StatelessWidget {
  final List<int> _choices = const [3, 5, 7];

  const _PickCountSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        decoration: BoxDecoration(
          color: ZenColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZenColors.border),
          boxShadow: ZenShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: ZenColors.jadeMid.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Wie viele Reflexionen sollen in die Story einfließen?',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _choices
                  .map((n) => ElevatedButton(
                        onPressed: () => Navigator.pop<int>(context, n),
                        child: Text('$n Reflexionen'),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop<int>(context, 3),
              child: const Text('Empfohlen: 3'),
            ),
          ],
        ),
      ),
    );
  }
}
