// lib/features/journal/journal_entry_view.dart
//
// v10.3 — JournalEntryView (Oxford-Zen • Full-bleed, Parity, Senior polish)
// -----------------------------------------------------------------------------
// • Vollbild-Detailansicht für: Tagebuch („Dein Gedanke“), Reflexion, Kurzgeschichte.
// • Kein schwarzer Balken: Stack(fit: expand) + Base-ColoredBox + Positioned.fill Backdrop.
// • „Milky“ Hintergrund via enableHaze:true (+ wash/glow/vignette).
// • Einheitliche, ruhige Typografie (Story-ähnlich).
// • Typ-Badge + optionales Mood-Label.
// • Desktop: ClampingScrollPhysics, extra Bottom-Padding per viewPadding.
//
// Fixes (14):
// • Back-Overlap: zusätzlicher Top-Padding um kToolbarHeight.
// • Header-Abstände geprüft (ruhig, konsistent).
// • Textfeld-Fokus: Keyboard-Dismiss on drag (keine Funktionsänderung).
// • SafeArea unten: Keyboard-Insets bevorzugt, sonst Safe-Padding.
// • Lints: prefer_const_constructors (u. a. AppBar) & dynamisches Badge-Label.

import 'package:flutter/material.dart';

import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader;

/// Viewer-spezifische Typen (lokal gehalten).
enum EntryKind { journal, reflection, story }

class JournalEntryView extends StatelessWidget {
  final EntryKind kind;
  final DateTime createdAt;

  // JOURNAL
  final String? journalText;

  // REFLEXION
  final String? userThought; // „Dein Gedanke“
  final String? aiQuestion; // Panda-Frage (kursiv)
  final String? userAnswer; // „Deine Antwort“

  // STORY
  final String? storyTitle;
  final String? storyTeaser; // kurzer Auszug / erster Satz
  final String? storyBody; // Volltext, falls vorhanden

  // Optionales Meta
  final String? moodLabel; // z. B. „Neutral“, „Erleichtert“, …

  // Optional: Sekundär-Aktion (z. B. Editor) — im Detail bewusst nicht angezeigt
  final VoidCallback? onEdit;

  const JournalEntryView({
    super.key,
    required this.kind,
    required this.createdAt,
    this.journalText,
    this.userThought,
    this.aiQuestion,
    this.userAnswer,
    this.storyTitle,
    this.storyTeaser,
    this.storyBody,
    this.moodLabel,
    this.onEdit,
  });

  // ─────────────────────────────── Styles ───────────────────────────────
  TextStyle _bodyInkStyle(BuildContext c) =>
      (Theme.of(c).textTheme.bodyMedium ?? const TextStyle(fontSize: 14.5)).copyWith(
        color: zs.ZenColors.inkStrong.withValues(alpha: .96),
        height: 1.30,
      );

  TextStyle _questionStyle(BuildContext c) =>
      (Theme.of(c).textTheme.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
        color: zs.ZenColors.inkStrong.withValues(alpha: .96),
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
        height: 1.28,
      );

  TextStyle _captionStyle(BuildContext c) =>
      (Theme.of(c).textTheme.labelSmall ?? const TextStyle(fontSize: 12))
          .copyWith(color: zs.ZenColors.inkSubtle.withValues(alpha: .90));

  TextStyle _titleStyle(BuildContext c) =>
      (Theme.of(c).textTheme.titleMedium ?? const TextStyle(fontSize: 18)).copyWith(
        fontWeight: FontWeight.w700,
        color: zs.ZenColors.deepSage,
        height: 1.22,
      );

  // ─────────────────────────────── Build ────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isMobile = mq.size.width < 470;

    // SafeArea unten: Keyboard bevorzugen, sonst Notch/Inset
    final bottomInsets = mq.viewInsets.bottom;
    final bottomSafe = mq.viewPadding.bottom;
    final bottomPad = zs.ZenSpacing.l + (bottomInsets > 0 ? bottomInsets : bottomSafe);

    // Back-Overlap fix: zusätzlicher Top-Offset um AppBar-Höhe
    const topToolbarOffset = kToolbarHeight; // 56.0

    final headerTitle = switch (kind) {
      EntryKind.journal => 'Dein Gedanke',
      EntryKind.reflection => 'Deine Reflexion',
      EntryKind.story => 'Deine Kurzgeschichte',
    };

    final headerCaption = switch (kind) {
      EntryKind.journal => 'Ganz in Ruhe lesen.',
      EntryKind.reflection => 'Klarheit, Schritt für Schritt.',
      EntryKind.story => 'Eine kleine Reise in Worten.',
    };

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: Colors.transparent,
      appBar: const zw.ZenAppBar(title: null, showBack: true),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Base-Fallback-Farbe (Ränder/HiDPI)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          // „Milky“ Backdrop
          const Positioned.fill(
            child: zw.ZenBackdrop(
              asset: 'assets/schoen.png',
              glow: .28,
              vignette: .12,
              saturation: .95,
              wash: .06,
              enableHaze: true,
            ),
          ),
          SafeArea(
            // SafeArea top bleibt aktiv; zusätzlicher topPadding unten in ScrollView
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                zs.ZenSpacing.m,
                20 + topToolbarOffset, // ← Back-Overlap fix (unter AppBar einrücken)
                zs.ZenSpacing.m,
                bottomPad, // ← nutzt Keyboard/Insets, sonst Safe-Padding
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      zw.PandaHeader(
                        title: headerTitle,
                        caption: headerCaption,
                        pandaSize: isMobile ? 88 : 112,
                        strongTitleGreen: true,
                      ),
                      const SizedBox(height: 12), // Header-Abstand geprüft
                      _card(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────── Card ────────────────────────────────

  Widget _card(BuildContext context) {
    late final IconData typeIcon;
    late final String typeLabel;
    switch (kind) {
      case EntryKind.reflection:
        typeIcon = Icons.psychology_alt_outlined;
        typeLabel = 'Reflexion';
        break;
      case EntryKind.story:
        typeIcon = Icons.auto_stories_outlined;
        typeLabel = 'Kurzgeschichte';
        break;
      case EntryKind.journal:
        typeIcon = Icons.menu_book_outlined;
        typeLabel = 'Tagebuch';
        break;
    }

    return Semantics(
      container: true,
      label: typeLabel,
      child: zw.ZenGlassCard(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
        borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
        topOpacity: .24,
        bottomOpacity: .10,
        borderOpacity: .14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Typ-Badge (für alle drei Arten)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                decoration: BoxDecoration(
                  color: zs.ZenColors.mist.withValues(alpha: .80),
                  borderRadius: const BorderRadius.all(zs.ZenRadii.s),
                  border: Border.all(
                    color: zs.ZenColors.jadeMid.withValues(alpha: .18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, color: zs.ZenColors.jadeMid, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: zs.ZenColors.jade,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Inhalt
            if (kind == EntryKind.journal)
              _journalBlock(context)
            else if (kind == EntryKind.reflection)
              _reflectionBlock(context)
            else
              _storyBlock(context),

            const SizedBox(height: 12),
            _metaRow(context),
          ],
        ),
      ),
    );
  }

  // Journal
  Widget _journalBlock(BuildContext context) {
    final raw = (journalText ?? '').trim();
    if (raw.isEmpty) {
      return const SelectableText('—', semanticsLabel: 'Leer');
    }

    final lines = raw.split(RegExp(r'\r?\n')).map((s) => s.trim()).toList();
    final nonEmpty = lines.where((s) => s.isNotEmpty).toList();

    final title = nonEmpty.isNotEmpty ? nonEmpty.first : '';
    final bodyLines = nonEmpty.length > 1 ? nonEmpty.sublist(1) : const <String>[];
    final body = bodyLines.join('\n').trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: _titleStyle(context)),
          if (body.isNotEmpty) const SizedBox(height: 10),
        ],
        if (body.isNotEmpty) SelectableText(body, style: _bodyInkStyle(context)),
      ],
    );
  }

  // Reflexion
  Widget _reflectionBlock(BuildContext context) {
    final thought = (userThought ?? '').trim();
    final question = (aiQuestion ?? '').trim();
    final answer = (userAnswer ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thought.isNotEmpty) ...[
          Text(thought, style: _titleStyle(context)),
          const SizedBox(height: 10),
        ],
        if (question.isNotEmpty) ...[
          SelectableText(question, style: _questionStyle(context)),
          const SizedBox(height: 10),
        ],
        if (answer.isNotEmpty)
          SelectableText(answer, style: _bodyInkStyle(context))
        else
          const SelectableText('—', semanticsLabel: 'Leer'),
      ],
    );
  }

  // Story
  Widget _storyBlock(BuildContext context) {
    final title = (storyTitle ?? '').trim();
    final body = (storyBody ?? '').trim();
    final teaser = (storyTeaser ?? '').trim();
    final text = (body.isNotEmpty ? body : teaser);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: _titleStyle(context)),
          const SizedBox(height: 10),
        ],
        SelectableText(
          text.isEmpty ? '—' : text,
          style: _bodyInkStyle(context),
          textAlign: TextAlign.start,
          maxLines: null,
          semanticsLabel: text.isEmpty ? 'Leer' : null,
        ),
      ],
    );
  }

  // Meta
  Widget _metaRow(BuildContext context) {
    final ts = _formatDate(createdAt);
    final mood = (moodLabel ?? '').trim();

    return Row(
      children: [
        Text(ts, style: _captionStyle(context)),
        if (mood.isNotEmpty) ...[
          const SizedBox(width: 8),
          _MoodLabelChip(text: mood),
        ],
        const Spacer(),
      ],
    );
  }

  // Utils
  String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    final now = DateTime.now();

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    String two(int n) => n.toString().padLeft(2, '0');
    final hh = two(l.hour);
    final mm = two(l.minute);

    if (sameDay(l, now)) return 'Heute, $hh:$mm';
    if (sameDay(l, now.subtract(const Duration(days: 1)))) return 'Gestern, $hh:$mm';

    final dd = two(l.day);
    final mo = two(l.month);
    return '$dd.$mo.${l.year}, $hh:$mm';
  }
}

// ───────────────────────────── Lokaler, leichter Mood-Label-Chip ─────────────────────────────

class _MoodLabelChip extends StatelessWidget {
  final String text;
  const _MoodLabelChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: .60),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .50),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
