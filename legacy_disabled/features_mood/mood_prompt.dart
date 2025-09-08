// lib/features/mood/mood_prompt.dart
//
// MoodPrompt — ruhige 5er-Skala mit Zen-Optik (drop-in, a11y, keyboard)
// ---------------------------------------------------------------------
// • Skala 0..4: "Sehr schlecht" .. "Sehr gut"
// • Kompakte Glas-Karte, barrierefrei, Tastatur: ←/→, 1..5, Enter/Space
// • Callbacks: onScore(int), onSelected(int score, String label)
// • Vollständig gekapselt, kein globaler State
//
// Einbau (Beispiel):
// MoodPrompt(
//   initialScore: 2,
//   onSelected: (score, label) {
//     // z.B. ins ReflectionEntry schreiben, Provider updaten, etc.
//   },
// )

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Kollisionen vermeiden: ZenColors/Radii aus zen_style, Card aus zen_widgets.
import '../../shared/zen_style.dart' show ZenColors, ZenRadii;
import '../../shared/ui/zen_widgets.dart' show ZenGlassCard;

class MoodPrompt extends StatefulWidget {
  final int? initialScore; // 0..4 oder null
  final ValueChanged<int>? onScore; // nur Score
  final void Function(int score, String label)? onSelected; // Score + Label
  final String title;
  final String caption;
  final EdgeInsetsGeometry padding;
  final bool enabled;
  final bool autofocus;

  const MoodPrompt({
    super.key,
    this.initialScore,
    this.onScore,
    this.onSelected,
    this.title = 'Wie fühlst du dich gerade?',
    this.caption = 'Wähle kurz eine Stimmung – das hilft dir, den Verlauf zu sehen.',
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<MoodPrompt> createState() => _MoodPromptState();
}

class _MoodPromptState extends State<MoodPrompt> {
  static const List<String> _labels = <String>[
    'Sehr schlecht',
    'Eher schlecht',
    'Neutral',
    'Eher gut',
    'Sehr gut',
  ];

  int? _score;

  @override
  void initState() {
    super.initState();
    _score = (widget.initialScore != null &&
            widget.initialScore! >= 0 &&
            widget.initialScore! <= 4)
        ? widget.initialScore
        : null;
  }

  void _applyScore(int v) {
    if (!widget.enabled) return;
    setState(() => _score = v);
    widget.onScore?.call(v);
    widget.onSelected?.call(v, _labels[v]);
    // Optional leichtes haptisches Feedback (wenn Plattform unterstützt)
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final base = tt.bodyMedium!;
    final subtle = base.copyWith(color: ZenColors.inkSubtle);
    final strong = base.copyWith(color: ZenColors.inkStrong, fontWeight: FontWeight.w700);

    return Semantics(
      container: true,
      enabled: widget.enabled,
      label: 'Stimmungsabfrage',
      child: ZenGlassCard(
        padding: widget.padding,
        topOpacity: .26,
        bottomOpacity: .10,
        borderOpacity: .18,
        borderRadius: const BorderRadius.all(ZenRadii.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: strong),
            const SizedBox(height: 6),
            Text(widget.caption, style: subtle),
            const SizedBox(height: 12),
            _MoodScale(
              value: _score,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              onChanged: _applyScore,
            ),
            if (_score != null) ...[
              const SizedBox(height: 10),
              _MoodBadge(score: _score!, label: _labels[_score!]),
            ],
          ],
        ),
      ),
    );
  }
}

class _MoodScale extends StatefulWidget {
  final int? value; // 0..4
  final bool enabled;
  final bool autofocus;
  final ValueChanged<int> onChanged;

  const _MoodScale({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<_MoodScale> createState() => _MoodScaleState();
}

class _MoodScaleState extends State<_MoodScale> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'MoodScale');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, RawKeyEvent e) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (e is! RawKeyDownEvent) return KeyEventResult.ignored;

    int current = widget.value ?? 2; // neutral als Start
    int? next;

    // Ziffern 1..5 → 0..4
    if (e.logicalKey == LogicalKeyboardKey.digit1 ||
        e.logicalKey == LogicalKeyboardKey.numpad1) {
      next = 0;
    } else if (e.logicalKey == LogicalKeyboardKey.digit2 ||
             e.logicalKey == LogicalKeyboardKey.numpad2) next = 1;
    else if (e.logicalKey == LogicalKeyboardKey.digit3 ||
             e.logicalKey == LogicalKeyboardKey.numpad3) next = 2;
    else if (e.logicalKey == LogicalKeyboardKey.digit4 ||
             e.logicalKey == LogicalKeyboardKey.numpad4) next = 3;
    else if (e.logicalKey == LogicalKeyboardKey.digit5 ||
             e.logicalKey == LogicalKeyboardKey.numpad5) next = 4;

    // Pfeile ←/→
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      next = (current + 1).clamp(0, 4);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      next = (current - 1).clamp(0, 4);
    }

    // Enter/Space → bestätigen (keine Änderung nötig; triggert Callback mit aktuellem Wert)
    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter ||
        e.logicalKey == LogicalKeyboardKey.space) {
      next ??= current;
    }

    if (next != null) {
      widget.onChanged(next);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.value;
    final items = List.generate(5, (i) => i);

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onKey: _handleKey,
      child: Semantics(
        label: 'Stimmungsskala 0 bis 4',
        hint: 'Mit Pfeiltasten wählen oder 1 bis 5 drücken',
        value: selected == null ? 'keine Auswahl' : selected.toString(),
        enabled: widget.enabled,
        // A11y-Verbesserung: Screenreader-Aktionen für Slider-Änderungen.
        onIncrease: () {
          if (!widget.enabled) return;
          final v = ((selected ?? 2) + 1).clamp(0, 4);
          widget.onChanged(v);
        },
        onDecrease: () {
          if (!widget.enabled) return;
          final v = ((selected ?? 2) - 1).clamp(0, 4);
          widget.onChanged(v);
        },
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((i) => _MoodChip(
                    score: i,
                    selected: selected == i,
                    enabled: widget.enabled,
                    onTap: () => widget.onChanged(i),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  final int score; // 0..4
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _MoodChip({
    required this.score,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  String get _label {
    switch (score) {
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
      default:
        return 'Neutral';
    }
  }

  String get _emoji {
    switch (score) {
      case 0:
        return '😔';
      case 1:
        return '😕';
      case 2:
        return '😐';
      case 3:
        return '🙂';
      case 4:
        return '😄';
      default:
        return '😐';
    }
  }

  @override
  Widget build(BuildContext context) {
    const jade = ZenColors.jade;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final bg = selected ? jade.withValues(alpha: .10) : ZenColors.surface;
    final border = selected ? jade.withValues(alpha: .80) : jade.withValues(alpha: .50);
    final txt = base.copyWith(
      color: enabled ? jade : jade.withValues(alpha: .45),
      fontWeight: FontWeight.w700,
    );

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: 'Stimmung $_label',
      onTapHint: enabled ? 'Auswählen' : null,
      child: InkWell(
        borderRadius: const BorderRadius.all(ZenRadii.m),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.all(ZenRadii.m),
            border: Border.all(color: border, width: 1.6),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_emoji, style: base.copyWith(fontSize: 18)),
              const SizedBox(width: 8),
              Text(_label, style: txt),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoodBadge extends StatelessWidget {
  final int score;
  final String label;

  const _MoodBadge({required this.score, required this.label});

  @override
  Widget build(BuildContext context) {
    const jade = ZenColors.jade;
    final tt = Theme.of(context).textTheme;
    final text = tt.bodySmall?.copyWith(color: ZenColors.ink, height: 1.2);

    return Row(
      children: [
        const Icon(Icons.insights_rounded, size: 16, color: ZenColors.inkSubtle),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Gewählt: $label (${score.toString()}/4) – danke für dein Gefühl.',
            style: text,
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.check_circle_rounded, size: 18, color: jade),
      ],
    );
  }
}
