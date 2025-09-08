// lib/features/journal/journal_entry_view.dart
//
// v9.1 — JournalEntryView (Oxford-Zen, Phase 2.6)
// ---------------------------------------------------------------------------
// • Vollbild-Viewer mit PandaHeader, ruhiger Glas-Karte und klarer Typo.
// • Typen: Journal (→ „Dein Gedanke“), Reflexion, Kurzgeschichte.
// • Journal: 1. nicht-leere Zeile als grüne Überschrift, Rest in Ink.
// • Reflexion: Frage kursiv, Labels in Ink, Inhalte in Jade.
// • Story: Titel + Text ruhig gesetzt (Titel grün, Text Ink).
// • Zeitformat: „Heute/Gestern, HH:MM“, sonst „DD.MM.YYYY, HH:MM“.
// • Mood: kleiner Chip rechts in der Meta-Zeile (falls vorhanden).
// • Actions: Kopieren (ZenToast), optional Bearbeiten.
// • A11y: Semantics-Labels, Tooltips, fokussierbare Buttons.
//
// Abhängigkeiten: ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, ZenToast, PandaMoodChip
// Dart-2.x-kompatibel, defensive Null-Checks.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, ZenToast, PandaMoodChip;

/// Viewer-spezifische Typen (bewusst lokal, damit es keine Enum-Kollision
/// mit dem Model-Enum gibt; in Aufrufern per Alias importieren: `as jv`).
enum EntryKind { journal, reflection, story }

class JournalEntryView extends StatelessWidget {
  final EntryKind kind;
  final DateTime createdAt;

  // JOURNAL
  final String? journalText;

  // REFLEXION
  final String? userThought; // „Dein Gedanke“
  final String? aiQuestion;  // Panda-Frage (kursiv)
  final String? userAnswer;  // „Deine Antwort“

  // STORY
  final String? storyTitle;
  final String? storyTeaser; // kurzer Auszug / erster Satz
  final String? storyBody;   // falls verfügbar, sonst Teaser nutzen

  // Optionales Meta
  final String? moodLabel;   // z. B. „Neutral“, „Erleichtert“, …

  // Optional: Sekundär-Aktion (z. B. Editor)
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

  // Grüne Nutzereingaben (Reflexion-Antwort)
  TextStyle get _userStyle => const TextStyle(
        fontFamily: 'ZenKalligrafie', // Fallback: System-Font wenn nicht registriert
        fontSize: 18,
        height: 1.30,
        color: zs.ZenColors.jade,
        fontWeight: FontWeight.w600,
      );

  TextStyle _labelStyle(BuildContext c) =>
      (Theme.of(c).textTheme.labelMedium ?? const TextStyle(fontSize: 12))
          .copyWith(color: zs.ZenColors.inkStrong, fontWeight: FontWeight.w700);

  TextStyle _questionStyle(BuildContext c) =>
      (Theme.of(c).textTheme.bodyMedium ?? const TextStyle(fontSize: 14))
          .copyWith(
            color: zs.ZenColors.inkStrong.withValues(alpha: .96),
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            height: 1.28,
          );

  TextStyle _captionStyle(BuildContext c) =>
      (Theme.of(c).textTheme.labelSmall ?? const TextStyle(fontSize: 12))
          .copyWith(color: Colors.black.withValues(alpha: .55));

  // Überschrift (grün) wie bei Story
  TextStyle _greenTitleStyle(BuildContext c) =>
      (Theme.of(c).textTheme.titleMedium ?? const TextStyle(fontSize: 18))
          .copyWith(
            fontWeight: FontWeight.w700,
            color: zs.ZenColors.jade,
            height: 1.22,
          );

  // Fließtext in Ink – ruhig, gut lesbar
  TextStyle _bodyInkStyle(BuildContext c) =>
      (Theme.of(c).textTheme.bodyMedium ?? const TextStyle(fontSize: 14.5))
          .copyWith(
            color: zs.ZenColors.inkStrong.withValues(alpha: .96),
            height: 1.30,
          );

  // ─────────────────────────────── Build ────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 470;

    final headerTitle = () {
      switch (kind) {
        case EntryKind.journal:
          return 'Dein Gedanke'; // <— gewünscht statt „Dein Eintrag“
        case EntryKind.reflection:
          return 'Deine Reflexion';
        case EntryKind.story:
          return 'Deine Kurzgeschichte';
      }
    }();

    final headerCaption = () {
      switch (kind) {
        case EntryKind.journal:
          return 'Ganz in Ruhe lesen.';
        case EntryKind.reflection:
          return 'Klarheit, Schritt für Schritt.';
        case EntryKind.story:
          return 'Eine kleine Reise in Worten.';
      }
    }();

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: const zw.ZenAppBar(title: null, showBack: true),
      body: Stack(
        children: [
          // Backdrop im Zen-Look (gleich wie auf den „perfekten“ Screens)
          const Positioned.fill(
            child: zw.ZenBackdrop(
              asset: 'assets/schoen.png',
              glow: .28,
              vignette: .12,
              saturation: .95,
              wash: .06,
              enableHaze: false,
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                zs.ZenSpacing.m, 20, zs.ZenSpacing.m, zs.ZenSpacing.l,
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
                      const SizedBox(height: 12),
                      _card(context),
                      const SizedBox(height: 14),
                      _actions(context),
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
    return Semantics(
      container: true,
      label: () {
        switch (kind) {
          case EntryKind.journal:
            return 'Eintrag';
          case EntryKind.reflection:
            return 'Reflexion';
          case EntryKind.story:
            return 'Kurzgeschichte';
        }
      }(),
      child: zw.ZenGlassCard(
        // Glas-Defaults gemäß Widgets (harmonisiert mit Story)
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
        borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
        topOpacity: .24,
        bottomOpacity: .10,
        borderOpacity: .14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // kleiner Handle
            Align(
              alignment: Alignment.center,
              child: Container(
                height: 4,
                width: 48,
                margin: const EdgeInsets.only(bottom: 12, top: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Typ-Badge (nur für Reflexion/Story – Journal bleibt bewusst ruhig)
            if (kind == EntryKind.reflection || kind == EntryKind.story)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                  decoration: BoxDecoration(
                    color: zs.ZenColors.mist.withValues(alpha: 0.80),
                    borderRadius: const BorderRadius.all(zs.ZenRadii.s),
                    border: Border.all(color: zs.ZenColors.jadeMid.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        kind == EntryKind.reflection
                            ? Icons.psychology_alt_outlined
                            : Icons.auto_stories_outlined,
                        color: zs.ZenColors.jadeMid,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        kind == EntryKind.reflection ? 'Reflexion' : 'Kurzgeschichte',
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
            if (kind == EntryKind.journal) _journalBlock(context)
            else if (kind == EntryKind.reflection) _reflectionBlock(context)
            else _storyBlock(context),

            const SizedBox(height: 12),
            _metaRow(context),
          ],
        ),
      ),
    );
  }

  // Journal: 1. nicht-leere Zeile als Überschrift (grün), Rest in Ink.
  Widget _journalBlock(BuildContext context) {
    final raw = (journalText ?? '').trim();
    if (raw.isEmpty) {
      return SelectableText('—', style: _greenTitleStyle(context));
    }

    final lines = raw.split(RegExp(r'\r?\n')).map((s) => s.trim()).toList();
    final nonEmpty = lines.where((s) => s.isNotEmpty).toList();

    final title = nonEmpty.isNotEmpty ? nonEmpty.first : '';
    final bodyLines = nonEmpty.length > 1 ? nonEmpty.sublist(1) : const <String>[];
    final body = bodyLines.join('\n').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: _greenTitleStyle(context)),
          if (body.isNotEmpty) const SizedBox(height: 10),
        ],
        if (body.isNotEmpty)
          SelectableText(body, style: _bodyInkStyle(context)),
      ],
    );
  }

  Widget _reflectionBlock(BuildContext context) {
    final hasThought = (userThought ?? '').trim().isNotEmpty;
    final hasQuestion = (aiQuestion ?? '').trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasThought) ...[
          Text('Dein Gedanke', style: _labelStyle(context)),
          const SizedBox(height: 4),
          SelectableText('„${userThought!.trim()}“', style: _userStyle),
          const SizedBox(height: 12),
        ],
        if (hasQuestion) ...[
          SelectableText(aiQuestion!.trim(), style: _questionStyle(context)),
          const SizedBox(height: 10),
        ],
        Text('Deine Antwort', style: _labelStyle(context)),
        const SizedBox(height: 4),
        SelectableText(
          (userAnswer ?? '').trim().isEmpty ? '—' : userAnswer!.trim(),
          style: _userStyle,
        ),
      ],
    );
  }

  Widget _storyBlock(BuildContext context) {
    final title = (storyTitle ?? '').trim();
    final body = (storyBody ?? '').trim();
    final teaser = (storyTeaser ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: _greenTitleStyle(context)),
          const SizedBox(height: 10),
        ],
        SelectableText(
          (body.isNotEmpty ? body : teaser).isEmpty
              ? '—'
              : (body.isNotEmpty ? body : teaser),
          style: _bodyInkStyle(context),
          textAlign: TextAlign.start,
        ),
      ],
    );
  }

  // ───────────────────────────── Meta & Actions ───────────────────────────

  Widget _metaRow(BuildContext context) {
    final ts = _formatDate(createdAt);
    final mood = (moodLabel ?? '').trim();

    return Row(
      children: [
        Text(ts, style: _captionStyle(context)),
        if (mood.isNotEmpty) ...[
          const SizedBox(width: 8),
          zw.PandaMoodChip(mood: mood, small: true),
        ],
        const Spacer(),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final canEdit = onEdit != null;

    String copyLabel() {
      switch (kind) {
        case EntryKind.journal:
          return 'Eintrag kopieren';
        case EntryKind.reflection:
          return 'Reflexion kopieren';
        case EntryKind.story:
          return 'Kurzgeschichte kopieren';
      }
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_all_outlined),
          label: Text(copyLabel()),
          onPressed: () async {
            final textToCopy = () {
              switch (kind) {
                case EntryKind.journal:
                  return (journalText ?? '').trim();
                case EntryKind.reflection:
                  return <String>[
                    if ((userThought ?? '').trim().isNotEmpty)
                      'Gedanke: ${userThought!.trim()}',
                    if ((aiQuestion ?? '').trim().isNotEmpty)
                      'Frage: ${aiQuestion!.trim()}',
                    if ((userAnswer ?? '').trim().isNotEmpty)
                      'Antwort: ${userAnswer!.trim()}',
                  ].where((s) => s.isNotEmpty).join('\n');
                case EntryKind.story:
                  final t = (storyTitle ?? '').trim();
                  final b = (storyBody ?? '').trim();
                  final z = (storyTeaser ?? '').trim();
                  return <String>[
                    if (t.isNotEmpty) 'Titel: $t',
                    (b.isNotEmpty ? b : z),
                  ].where((s) => s.trim().isNotEmpty).join('\n\n');
              }
            }();

            await Clipboard.setData(ClipboardData(text: textToCopy));
            zw.ZenToast.show(context, 'In Zwischenablage kopiert');
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(zs.ZenRadii.m),
            ),
          ),
        ),
        if (canEdit)
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Bearbeiten'),
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(zs.ZenRadii.m),
              ),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────── Utils ─────────────────────────────────

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
