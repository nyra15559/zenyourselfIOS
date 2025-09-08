// lib/features/journal/widgets/journal_entry_card.dart
//
// JournalEntryCard — Oxford-Zen Glass v10.5 (SenStyleDart, ruhig & konsistent)
// -----------------------------------------------------------------------------
// • Glasige Karte (ZenGlassCard) gemäß zen_style.dart Tokens.
// • Header: Titel (DeepSage) + optional trailing + Menü (…).
// • Meta: nutzt entry.metaLine() → „Do., 07.09., 19:05 — <Typ>“.
// • Preview: Reflexion (Frage kursiv, Antwort DeepSage) | sonst Plaintext.
// • CTA nur bei Reflexion: „Erneut reflektieren“.
// • Typ-Icon links (Chip entfällt) – ruhiger, einheitlicher Look.
// • Animation ohne projektexterne Tokens (Duration/Curve lokal).

import 'package:flutter/material.dart';
import '../../../models/journal_entry.dart';
import '../../../shared/zen_style.dart' as zs;

class JournalEntryCard extends StatefulWidget {
  final JournalEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onContinue; // nur Reflexion
  final VoidCallback? onEdit;
  final VoidCallback? onHide;
  final VoidCallback? onDelete;
  final Widget? trailing;

  const JournalEntryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.onContinue,
    this.onEdit,
    this.onHide,
    this.onDelete,
    this.trailing,
  });

  @override
  State<JournalEntryCard> createState() => _JournalEntryCardState();
}

class _JournalEntryCardState extends State<JournalEntryCard> {
  bool _expanded = false;

  bool get _isReflection => widget.entry.kind == EntryKind.reflection;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry.withAutoTitle(); // sicherer Titel
    final badge = e.badge;                  // {label, icon}
    final title = e.computedTitle;

    return Semantics(
      container: true,
      label: 'Journaleintrag: ${badge.label}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: zs.ZenGlassCard(
            borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
            topOpacity: .30,
            bottomOpacity: .12,
            borderOpacity: .18,
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeIcon(icon: badge.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Titel + optional trailing + Menü
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _titleStyle(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (widget.trailing != null) widget.trailing!,
                          _MenuButton(
                            isReflection: _isReflection,
                            onContinue:
                                _isReflection ? widget.onContinue : null,
                            onEdit: widget.onEdit,
                            onHide: widget.onHide,
                            onDelete: widget.onDelete,
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Meta
                      Text(
                        e.metaLine(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: zs.ZenColors.inkSubtle
                                  .withValues(alpha: .90),
                            ),
                      ),

                      // Tags (dezent, max. 3; ohne interne/technische Tags)
                      _finalTags(e.tags),

                      const SizedBox(height: 8),

                      // Preview (expandable)
                      _ExpandablePreview(
                        isReflection: _isReflection,
                        question: e.aiQuestion ?? '',
                        answer: e.userAnswer ?? '',
                        plainText: e.previewText(),
                        expanded: _expanded,
                        onToggle: () =>
                            setState(() => _expanded = !_expanded),
                      ),

                      // CTA nur bei Reflexionen
                      if (_isReflection && widget.onContinue != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: widget.onContinue,
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: const Text('Erneut reflektieren'),
                            style: TextButton.styleFrom(
                              foregroundColor: zs.ZenColors.jade,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── helpers ───────────────────────────

  Widget _finalTags(List<String> tags) {
    final chips = _tagChips(tags);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  TextStyle _titleStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.titleMedium ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    return base.copyWith(
      color: zs.ZenColors.deepSage,
      fontWeight: FontWeight.w700,
    );
  }

  /// Filtert Debug-/Meta-/System-Tags raus und zeigt max. 3 Stück.
  List<Widget> _tagChips(List<String> tags) {
    if (tags.isEmpty) return const [];
    const bannedKeys = <String>{
      'mood',
      'moodscore',
      'emotion',
      'input',
      'answer',
      'user',
      'ai',
      'ai_question',
      'question',
      'type',
      'kind',
      'source',
      'sourceref',
    };
    const bannedFlat = <String>{
      'reflection',
      'reflexion',
      'journal',
      'story',
    };

    final filtered = tags.where((t) {
      final s = t.trim();
      if (s.isEmpty) return false;
      final sl = s.toLowerCase();
      if (bannedFlat.contains(sl)) return false;
      if (sl.contains(':')) {
        final key = sl.split(':').first.trim();
        if (bannedKeys.contains(key)) return false;
      }
      return true;
    }).take(3);

    return filtered.map((t) => _TagChip(text: t)).toList(growable: false);
  }
}

// ─────────────────────────── Subwidgets ───────────────────────────

class _TypeIcon extends StatelessWidget {
  final IconData icon;
  const _TypeIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = zs.ZenColors.deepSage;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: c.withValues(alpha: 0.07),
      ),
      child: Icon(icon, size: 20, color: c.withValues(alpha: 0.90)),
    );
  }
}

class _ExpandablePreview extends StatelessWidget {
  final bool isReflection;
  final String question;
  final String answer;
  final String plainText;
  final bool expanded;
  final VoidCallback onToggle;

  const _ExpandablePreview({
    required this.isReflection,
    required this.question,
    required this.answer,
    required this.plainText,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14.5);
    final green = zs.ZenColors.deepSage.withValues(alpha: .95);
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ?? zs.ZenColors.ink;

    InlineSpan span;

    if (isReflection) {
      final q = question.trim();
      final a = answer.trim();
      if (q.isEmpty && a.isEmpty) {
        span = TextSpan(
          text: 'Reflexion',
          style: base.copyWith(color: zs.ZenColors.inkSubtle),
        );
      } else {
        span = TextSpan(children: [
          if (q.isNotEmpty)
            TextSpan(
              text: '„$q“ ',
              style: base.copyWith(
                fontStyle: FontStyle.italic,
                color: textColor.withValues(alpha: 0.75),
              ),
            ),
          if (a.isNotEmpty)
            TextSpan(
              text: a,
              style: base.copyWith(
                fontWeight: FontWeight.w600,
                color: green,
              ),
            ),
        ]);
      }
    } else {
      span = TextSpan(text: plainText, style: base.copyWith(color: textColor));
    }

    return _ExpandableRichText(
      span: span,
      expanded: expanded,
      onToggle: onToggle,
      collapsedMaxLines: 3,
    );
  }
}

class _ExpandableRichText extends StatelessWidget {
  final InlineSpan span;
  final bool expanded;
  final VoidCallback onToggle;
  final int collapsedMaxLines;

  const _ExpandableRichText({
    required this.span,
    required this.expanded,
    required this.onToggle,
    this.collapsedMaxLines = 3,
  });

  static const _animDur = Duration(milliseconds: 220);
  static const _animCurve = Curves.easeInOut;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final tp = TextPainter(
        text: span,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        maxLines: collapsedMaxLines,
        ellipsis: '…',
      )..layout(maxWidth: constraints.maxWidth);

      final overflow = tp.didExceedMaxLines;

      return AnimatedSize(
        duration: _animDur,
        curve: _animCurve,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              span,
              maxLines: expanded ? null : collapsedMaxLines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (overflow)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      expanded ? 'Weniger' : 'Mehr anzeigen',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: zs.ZenColors.jade,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  const _TagChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final bg = Colors.black.withValues(alpha: .04);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(zs.ZenRadii.s),
        border: Border.all(color: Colors.black.withValues(alpha: .08), width: 1),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final VoidCallback? onContinue;
  final VoidCallback? onEdit;
  final VoidCallback? onHide;
  final VoidCallback? onDelete;
  final bool isReflection;

  const _MenuButton({
    this.onContinue,
    this.onEdit,
    this.onHide,
    this.onDelete,
    required this.isReflection,
  });

  @override
  Widget build(BuildContext context) {
    final hasAny =
        onContinue != null || onEdit != null || onHide != null || onDelete != null;
    if (!hasAny) return const SizedBox.shrink();

    return PopupMenuButton<_Action>(
      tooltip: 'Mehr',
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<_Action>>[];
        if (isReflection && onContinue != null) {
          items.add(const PopupMenuItem(
            value: _Action.continueFlow,
            child: Text('Erneut reflektieren'),
          ));
          items.add(const PopupMenuDivider(height: 6));
        }
        if (onEdit != null) {
          items.add(const PopupMenuItem(
            value: _Action.edit,
            child: Text('Bearbeiten'),
          ));
        }
        if (onHide != null) {
          items.add(const PopupMenuItem(
            value: _Action.hide,
            child: Text('Ausblenden'),
          ));
        }
        if (onDelete != null) {
          items.add(const PopupMenuDivider(height: 6));
          items.add(const PopupMenuItem(
            value: _Action.delete,
            child: Text('Löschen'),
          ));
        }
        return items;
      },
      onSelected: (act) {
        switch (act) {
          case _Action.continueFlow:
            onContinue?.call();
            break;
          case _Action.edit:
            onEdit?.call();
            break;
          case _Action.hide:
            onHide?.call();
            break;
          case _Action.delete:
            onDelete?.call();
            break;
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(
          Icons.more_horiz,
          size: 22,
          color: Theme.of(context).iconTheme.color?.withValues(alpha: .80),
        ),
      ),
    );
  }
}

enum _Action { continueFlow, edit, hide, delete }
