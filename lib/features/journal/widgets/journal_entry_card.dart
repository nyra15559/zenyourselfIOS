// lib/features/journal/widgets/journal_entry_card.dart
//
// JournalEntryCard — Oxford-Zen v9.2
// -----------------------------------------------------------------------------
// • Header: Titel (farblich je Typ) + kleiner Typ-Chip + Menü (…)
// • Meta: „Do., 07.09., 19:05 — <Typ>“
// • Body-Preview: max. 3 Zeilen; bei Reflection: Frage kursiv, Antwort ruhig grün
// • CTA nur bei Reflexion: „Erneut reflektieren“
// • A11y: Semantics-Container

import 'package:flutter/material.dart';
import '../../../models/journal_entry.dart';

class JournalEntryCard extends StatefulWidget {
  final JournalEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onContinue; // nur Reflexion
  final VoidCallback? onEdit;
  final VoidCallback? onHide;
  final VoidCallback? onDelete;
  final Widget? trailing;

  const JournalEntryCard({
    Key? key,
    required this.entry,
    this.onTap,
    this.onContinue,
    this.onEdit,
    this.onHide,
    this.onDelete,
    this.trailing,
  }) : super(key: key);

  @override
  State<JournalEntryCard> createState() => _JournalEntryCardState();
}

class _JournalEntryCardState extends State<JournalEntryCard> {
  bool _expanded = false;

  bool get _isReflection => widget.entry.kind == EntryKind.reflection;
  bool get _isStory => widget.entry.kind == EntryKind.story;
  bool get _isJournal => widget.entry.kind == EntryKind.journal;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final badge = e.badge; // {label, icon}
    final title = e.computedTitle;

    // Datum + Uhrzeit + Typ (bewusst ausführlich, Header „Heute“ darf bleiben)
    final meta = _metaLine(e.createdAt, badge.label);

    final cardBorder = Theme.of(context).dividerColor.withOpacity(0.14);

    return Semantics(
      container: true,
      label: 'Journaleintrag: ${badge.label}',
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cardBorder, width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: Padding(
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
                            onContinue: _isReflection ? widget.onContinue : null,
                            onEdit: widget.onEdit,
                            onHide: widget.onHide,
                            onDelete: widget.onDelete,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Typ-Chip
                      _TypeBadge(label: badge.label, icon: badge.icon),
                      const SizedBox(height: 6),

                      // Meta
                      Text(
                        meta,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: (Theme.of(context).textTheme.bodySmall?.color ??
                                      Theme.of(context).hintColor)
                                  .withOpacity(0.70),
                            ),
                      ),

                      // Tags (dezent, max. 3, ohne interne/technische Tags)
                      finalTags(e.tags),

                      const SizedBox(height: 8),

                      // Preview (expandable)
                      _ExpandablePreview(
                        isReflection: _isReflection,
                        question: e.aiQuestion ?? '',
                        answer: e.userAnswer ?? '',
                        plainText: e.previewText(),
                        expanded: _expanded,
                        onToggle: () => setState(() => _expanded = !_expanded),
                      ),

                      // Sichtbarer CTA nur bei Reflexionen
                      if (_isReflection && widget.onContinue != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: widget.onContinue,
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: const Text('Erneut reflektieren'),
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

  Widget finalTags(List<String> tags) {
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

    if (_isStory) {
      const moka = Color(0xFFA0785A); // ruhiges Bronze/Mokka
      return base.copyWith(color: moka, fontWeight: FontWeight.w700);
    }
    if (_isReflection) {
      final green = Theme.of(context).colorScheme.primary; // Deep-Sage
      return base.copyWith(color: green, fontWeight: FontWeight.w700);
    }
    return base.copyWith(fontWeight: FontWeight.w700); // Journal neutral
  }

  /// Filtert Debug-/Meta-/System-Tags raus (z. B. „reflection“, „input:text“,
  /// „type:*“, „ai:*“, „mood:*“, „emotion:*“) und zeigt max. 3 Stück.
  List<Widget> _tagChips(List<String> tags) {
    if (tags.isEmpty) return const [];
    const bannedKeys = <String>{
      'mood', 'moodscore', 'emotion',
      'input', 'answer', 'user', 'ai', 'ai_question', 'question',
      'type', 'kind', 'source', 'sourceref'
    };
    const bannedFlat = <String>{'reflection', 'reflexion', 'journal', 'story'};

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

  /// Wochentag + Datum + Uhrzeit + Typ
  String _metaLine(DateTime ts, String typeLabel) {
    final wd = _weekdayShort(ts.weekday);
    final dd = _two(ts.day);
    final mm = _two(ts.month);
    final hh = _two(ts.hour);
    final mi = _two(ts.minute);
    return '$wd, $dd.$mm., $hh:$mi — $typeLabel';
  }

  String _weekdayShort(int w) {
    switch (w) {
      case DateTime.monday:
        return 'Mo.';
      case DateTime.tuesday:
        return 'Di.';
      case DateTime.wednesday:
        return 'Mi.';
      case DateTime.thursday:
        return 'Do.';
      case DateTime.friday:
        return 'Fr.';
      case DateTime.saturday:
        return 'Sa.';
      case DateTime.sunday:
        return 'So.';
      default:
        return '';
    }
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';
}

// ─────────────────────────── Subwidgets ───────────────────────────

class _TypeIcon extends StatelessWidget {
  final IconData icon;
  const _TypeIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: c.withOpacity(0.07),
      ),
      child: Icon(icon, size: 20, color: c.withOpacity(0.90)),
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
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14.5);
    final green = Theme.of(context).colorScheme.primary.withOpacity(0.95);
    final textColor = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87;

    InlineSpan span;

    if (isReflection) {
      final q = question.trim();
      final a = answer.trim();
      if (q.isEmpty && a.isEmpty) {
        span = TextSpan(text: 'Reflexion', style: base.copyWith(color: Colors.black54));
      } else {
        span = TextSpan(children: [
          if (q.isNotEmpty)
            TextSpan(
              text: '„$q“ ',
              style: base.copyWith(
                fontStyle: FontStyle.italic,
                color: textColor.withOpacity(0.75),
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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
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
                            color: Theme.of(context).colorScheme.primary,
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

class _TypeBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  const _TypeBadge({Key? key, required this.label, required this.icon}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  const _TagChip({Key? key, required this.text}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bg = Colors.black.withOpacity(.04);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withOpacity(.08), width: 1),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
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
    Key? key,
    this.onContinue,
    this.onEdit,
    this.onHide,
    this.onDelete,
    required this.isReflection,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasAny = onContinue != null || onEdit != null || onHide != null || onDelete != null;
    if (!hasAny) return const SizedBox.shrink();

    return PopupMenuButton<_Action>(
      tooltip: 'Mehr',
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<_Action>>[];
        if (isReflection && onContinue != null) {
          items.add(const PopupMenuItem(value: _Action.continueFlow, child: Text('Erneut reflektieren')));
          items.add(const PopupMenuDivider(height: 6));
        }
        if (onEdit != null) {
          items.add(const PopupMenuItem(value: _Action.edit, child: Text('Bearbeiten')));
        }
        if (onHide != null) {
          items.add(const PopupMenuItem(value: _Action.hide, child: Text('Ausblenden')));
        }
        if (onDelete != null) {
          items.add(const PopupMenuDivider(height: 6));
          items.add(const PopupMenuItem(value: _Action.delete, child: Text('Löschen')));
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
          color: Theme.of(context).iconTheme.color?.withOpacity(0.80),
        ),
      ),
    );
  }
}

enum _Action { continueFlow, edit, hide, delete }
