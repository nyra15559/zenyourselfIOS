// lib/features/search/search_screen.dart
//
// SearchScreen — Oxford Zen Pro
// ------------------------------
// • Volltextsuche über JournalEntriesProvider.search()
// • Filter-Chips (Alle / Notizen / Reflexionen / Stories)
// • Snippet-Highlighting (case-insensitive), sichere Ellipsen
// • Live-Update: hört auf Provider-Changes
// • A11y: Semantics, klare Focus-Ringe, Keyboard-Shortcuts
// • UX: Clear-Icon, statische Leere-Zustände, sanfte Animationen

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/journal_entries_provider.dart';
import '../../data/journal_entry.dart';
import '../../shared/zen_style.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with TickerProviderStateMixin {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  JournalType? _typeFilter; // null = alle
  List<JournalEntry> _results = const [];
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _queryCtrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _queryCtrl.removeListener(_onQueryChanged);
    _queryCtrl.dispose();
    _fieldFocus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _runSearch();
  }

  void _runSearch() {
    final provider = context.read<JournalEntriesProvider>();
    final q = _queryCtrl.text.trim();
    List<JournalEntry> hits;
    if (q.isEmpty) {
      hits = const [];
    } else {
      hits = provider.search(q, limit: 120);
      if (_typeFilter != null) {
        hits = hits.where((e) => e.type == _typeFilter).toList();
      }
    }
    setState(() => _results = hits);
    _fadeCtrl
      ..reset()
      ..forward();
  }

  void _clear() {
    _queryCtrl.clear();
    _fieldFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild auf Provider-Changes → Index „live“
    context.watch<JournalEntriesProvider>();
    // Suche bei externen Änderungen erneut evaluieren (z. B. Löschen)
    // (Nur wenn eine Query existiert; sonst bleibt Liste leer)
    if (_queryCtrl.text.isNotEmpty) {
      // microtask, um setState während build zu vermeiden
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
    }

    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suche'),
        actions: [
          IconButton(
            tooltip: 'Eingabe löschen',
            icon: const Icon(Icons.clear_all_rounded),
            onPressed: results.isEmpty && _queryCtrl.text.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(
            children: [
              _buildSearchField(),
              const SizedBox(height: 10),
              _buildFilters(),
              const SizedBox(height: 6),
              _buildMetaRow(results.length),
              const SizedBox(height: 6),
              Expanded(
                child: results.isEmpty
                    ? _buildEmptyState()
                    : FadeTransition(
                        opacity: _fadeCtrl,
                        child: ListView.separated(
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _SearchResultTile(
                            entry: results[i],
                            query: _queryCtrl.text,
                            onOpenDay: () => _openDay(results[i]),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Semantics(
      textField: true,
      label: 'Sucheingabe',
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (e) {
          final withCmd = e.isMetaPressed || e.isControlPressed;
          if (e is RawKeyDownEvent && withCmd && e.logicalKey == LogicalKeyboardKey.keyK) {
            _fieldFocus.requestFocus();
          }
        },
        child: TextField(
          controller: _queryCtrl,
          focusNode: _fieldFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _runSearch(),
          decoration: InputDecoration(
            hintText: 'Suche nach Gedanken, Fragen oder Stimmungen …',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _queryCtrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _clear,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    Chip build(String label, IconData icon, JournalType? t) {
      final selected = _typeFilter == t;
      return ChoiceChip.elevated(
        selected: selected,
        onSelected: (_) {
          HapticFeedback.selectionClick();
          setState(() => _typeFilter = t);
          _runSearch();
        },
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selectedColor: ZenColors.sage.withValues(alpha: .18),
        side: BorderSide(color: selected ? ZenColors.jade : ZenColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        build('Alle', Icons.all_inclusive, null),
        build('Notizen', Icons.edit_note_rounded, JournalType.note),
        build('Reflexionen', Icons.psychology_rounded, JournalType.reflection),
        build('Stories', Icons.auto_stories_rounded, JournalType.story),
      ],
    );
  }

  Widget _buildMetaRow(int count) {
    final q = _queryCtrl.text.trim();
    final txt = q.isEmpty ? 'Gib etwas ein, um zu suchen.' : '$count Ergebnis${count == 1 ? '' : 'se'}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        txt,
        style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid),
      ),
    );
  }

  Widget _buildEmptyState() {
    final q = _queryCtrl.text.trim();
    final isEmpty = q.isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isEmpty ? Icons.search_rounded : Icons.find_in_page_outlined,
                size: 56, color: ZenColors.jadeMid.withValues(alpha: .6)),
            const SizedBox(height: 12),
            Text(
              isEmpty ? 'Suche starten' : 'Keine Treffer',
              style: ZenTextStyles.subtitle.copyWith(color: ZenColors.jade),
            ),
            const SizedBox(height: 6),
            Text(
              isEmpty
                  ? 'Tippe oben z. B. „dankbar“, „schlaf“ oder „Projekt“'
                  : 'Probiere ein anderes Wort oder weite die Filter aus.',
              textAlign: TextAlign.center,
              style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid),
            ),
          ],
        ),
      ),
    );
  }

  void _openDay(JournalEntry e) {
    // Optional: eigene Day-Screen-Route, hier simple Dialog-Preview
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(e.label),
        content: Text(e.preview(280)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final JournalEntry entry;
  final String query;
  final VoidCallback onOpenDay;

  const _SearchResultTile({
    required this.entry,
    required this.query,
    required this.onOpenDay,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcon(entry.type);
    final accent = _typeColor(entry.type);
    final when = _friendlyDate(entry.createdAtLocal);

    return ListTile(
      onTap: onOpenDay,
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: .12),
        foregroundColor: accent,
        child: Icon(icon),
      ),
      title: _highlight(entry.label, query, style: ZenTextStyles.subtitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          _highlight(_makeSnippet(entry.text, query), query,
              style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 14, color: ZenColors.jadeMid),
              const SizedBox(width: 4),
              Text(when, style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid)),
              const SizedBox(width: 10),
              if (entry.moodLabel != null) ...[
                const Icon(Icons.emoji_emotions_rounded, size: 14, color: ZenColors.jadeMid),
                const SizedBox(width: 4),
                Text(entry.moodLabel!, style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid)),
              ],
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      visualDensity: VisualDensity.compact,
    );
  }

  static IconData _typeIcon(JournalType t) {
    switch (t) {
      case JournalType.note:
        return Icons.edit_note_rounded;
      case JournalType.reflection:
        return Icons.psychology_rounded;
      case JournalType.story:
        return Icons.auto_stories_rounded;
    }
  }

  static Color _typeColor(JournalType t) {
    switch (t) {
      case JournalType.note:
        return ZenColors.deepSage;
      case JournalType.reflection:
        return ZenColors.jadeMid;
      case JournalType.story:
        return ZenColors.cta;
    }
  }

  static String _friendlyDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dd = DateTime(d.year, d.month, d.day);
    if (dd == today) return 'Heute, ${_hhmm(d)}';
    if (dd == today.subtract(const Duration(days: 1))) return 'Gestern, ${_hhmm(d)}';
    return '${_dd(dd.day)}.${_dd(dd.month)}.${dd.year}, ${_hhmm(d)}';
  }

  static String _dd(int n) => n.toString().padLeft(2, '0');
  static String _hhmm(DateTime d) => '${_dd(d.hour)}:${_dd(d.minute)}';

  static String _makeSnippet(String text, String query, {int radius = 70}) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty || query.trim().isEmpty) return t.length <= 140 ? t : '${t.substring(0, 140)}…';
    final q = query.trim().toLowerCase();
    final idx = t.toLowerCase().indexOf(q);
    if (idx < 0) return t.length <= 140 ? t : '${t.substring(0, 140)}…';
    final start = max(0, idx - radius);
    final end = min(t.length, idx + q.length + radius);
    final head = start > 0 ? '…' : '';
    final tail = end < t.length ? '…' : '';
    return '$head${t.substring(start, end)}$tail';
  }

  static Widget _highlight(String text, String query, {TextStyle? style}) {
    if (query.trim().isEmpty) return Text(text, style: style);
    final q = query.trim();
    final lc = text.toLowerCase();
    final lq = q.toLowerCase();

    final spans = <TextSpan>[];
    int i = 0;
    while (true) {
      final hit = lc.indexOf(lq, i);
      if (hit < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (hit > i) spans.add(TextSpan(text: text.substring(i, hit)));
      spans.add(TextSpan(
        text: text.substring(hit, hit + q.length),
        style: (style ?? const TextStyle()).copyWith(
          backgroundColor: ZenColors.jade.withValues(alpha: .18),
          fontWeight: FontWeight.w700,
        ),
      ));
      i = hit + q.length;
    }
    return RichText(text: TextSpan(style: style ?? const TextStyle(color: ZenColors.ink), children: spans));
  }
}
