// [UPDATED] lib/features/reflection/widgets/mood_picker_dual.dart (Stand: 2025-11-08, v1.3.0)
// MERGE SIGNAL: Dual-Mood-Picker v1.3.0 — A11y, Keyboard, Auto-Save, Guarding & UX Polish
// -----------------------------------------------------------------------------
// Neu in v1.3.0
// • Stabilere Auto-Save-Guards (kein Doppel-Pop, kein Doppel-Save).
// • Klarere Semantics (Gruppen-Labels, toggled-States, Tooltips).
// • Keyboard-Navigation verfeinert (Ziffern 0–4, ENTER speichert, ESC schließt,
//   ←/→ justieren, ↑/↓ Achsenwechsel mit visuellem „aktiv“-Badge).
// • Oxford-Zen UI (ZenGlassCard, ZenButtons), barrierColor dezent.
// • API unverändert: showPandaDualMoodPicker(...) → DualMoodResult?
//
// Kutsche 2 — Dual-Mood (Kopf & Körper)
// -----------------------------------------------------------------------------
// • Zwei Skalen 0–4, Labels „Kopf“ (mental) & „Körper“ (physisch).
// • Sobald beide Werte gesetzt sind → optional Auto-Save (onSave) & close().
// • Optionaler „Speichern“-Button als A11y/Keyboard-Fallback.
// • Keine direkte Abhängigkeit zu MemoryService — onSave wird injiziert.
//
// Öffentliche API:
//
//   final res = await showPandaDualMoodPicker(
//     context,
//     title: 'Wie fühlst du dich? (Kopf & Körper)',
//     initialMental: 2,
//     initialPhysical: 2,
//     onSave: (mental, physical) async {
//       // z.B. MemoryService.saveMoodEntry(DateTime.now().toUtc(), mental, physical);
//     },
//     autoSave: true,
//   );
//   // res?.mental / res?.physical (0..4)
//
// Hinweise:
// – 0 = sehr schwer/angespannt, 2 = neutral/ausgeglichen, 4 = sehr leicht/locker
// – Fokusreihenfolge: Header → Kopf-Reihe → Körper-Reihe → Footer-Buttons
// -----------------------------------------------------------------------------

library mood_picker_dual;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/zen_style.dart';
import '../../../shared/ui/zen_widgets.dart';

// Ergebnisobjekt für den Aufrufer
class DualMoodResult {
  final int mental;   // Kopf   (0–4)
  final int physical; // Körper (0–4)
  final String mentalLabel;
  final String physicalLabel;

  const DualMoodResult({
    required this.mental,
    required this.physical,
    required this.mentalLabel,
    required this.physicalLabel,
  });

  @override
  String toString() => 'DualMoodResult(mental:$mental, physical:$physical)';
}

/// Öffnet den Dual-Mood-Picker als Bottom-Sheet.
/// Gibt bei Erfolg ein [DualMoodResult] zurück, sonst `null`.
Future<DualMoodResult?> showPandaDualMoodPicker(
  BuildContext context, {
  String title = 'Mentale & körperliche Stimmung',
  int? initialMental,
  int? initialPhysical,
  Future<void> Function(int mental, int physical)? onSave,
  bool autoSave = true,
}) async {
  return showModalBottomSheet<DualMoodResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .35),
    builder: (ctx) {
      return _DualPickerSheet(
        title: title,
        initialMental: initialMental,
        initialPhysical: initialPhysical,
        onSave: onSave,
        autoSave: autoSave,
      );
    },
  );
}

class _DualPickerSheet extends StatefulWidget {
  final String title;
  final int? initialMental;
  final int? initialPhysical;
  final Future<void> Function(int mental, int physical)? onSave;
  final bool autoSave;

  const _DualPickerSheet({
    required this.title,
    this.initialMental,
    this.initialPhysical,
    this.onSave,
    this.autoSave = true,
  });

  @override
  State<_DualPickerSheet> createState() => _DualPickerSheetState();
}

class _DualPickerSheetState extends State<_DualPickerSheet> {
  int? _mental;   // 0..4
  int? _physical; // 0..4

  bool _saving = false;   // verhindert Doppel-Saves
  bool _closing = false;  // verhindert Doppel-Pops
  int _activeAxis = 0;    // 0 = mental, 1 = physical (für Keyboard)

  @override
  void initState() {
    super.initState();
    _mental = _clampOrNull(widget.initialMental);
    _physical = _clampOrNull(widget.initialPhysical);

    // Edge-Case: wenn beide initial gesetzt, direkt versuchen zu speichern
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoSave());
  }

  int? _clampOrNull(int? v) => v == null ? null : v.clamp(0, 4);

  bool get _complete => _mental != null && _physical != null;

  // ---------------------------- Save / Close ---------------------------------

  Future<void> _tryAutoSave() async {
    if (!widget.autoSave) return;
    if (!_complete) return;
    await _saveAndClose();
  }

  Future<void> _saveAndClose() async {
    if (!_complete || _saving || _closing) return;
    setState(() => _saving = true);

    final mental = _mental!;
    final physical = _physical!;

    try {
      if (widget.onSave != null) {
        await widget.onSave!(mental, physical);
      }
      HapticFeedback.mediumImpact();
    } finally {
      if (!mounted) return;
      // Doppel-Pop verhindern
      if (_closing) return;
      _closing = true;

      Navigator.of(context).pop(DualMoodResult(
        mental: mental,
        physical: physical,
        mentalLabel: _scoreLabel(mental),
        physicalLabel: _scoreLabel(physical),
      ));
    }
  }

  // ---------------------------- Mutators -------------------------------------

  void _pickMental(int s) {
    if (_saving || _closing) return;
    HapticFeedback.selectionClick();
    setState(() {
      _mental = s.clamp(0, 4);
      _activeAxis = 1; // nach Wahl von Kopf → Fokus logisch auf Körper
    });
    _tryAutoSave();
  }

  void _pickPhysical(int s) {
    if (_saving || _closing) return;
    HapticFeedback.selectionClick();
    setState(() {
      _physical = s.clamp(0, 4);
      _activeAxis = 0; // nach Wahl von Körper → Fokus zurück zu Kopf
    });
    _tryAutoSave();
  }

  // ---------------------------- Keyboard layer -------------------------------

  void _handleDigit(int digit) {
    if (digit < 0 || digit > 4) return;
    if (_activeAxis == 0) {
      _pickMental(digit);
    } else {
      _pickPhysical(digit);
    }
  }

  void _nudge(int delta) {
    if (_activeAxis == 0) {
      final v = (_mental ?? 2) + delta;
      _pickMental(v.clamp(0, 4));
    } else {
      final v = (_physical ?? 2) + delta;
      _pickPhysical(v.clamp(0, 4));
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;

    final key = e.logicalKey;

    // ESC → schließen
    if (key == LogicalKeyboardKey.escape) {
      if (!_saving && !_closing) {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }

    // ENTER → speichern (falls vollständig)
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_complete && !_saving && !_closing) {
        _saveAndClose();
      }
      return KeyEventResult.handled;
    }

    // Ziffern 0..4
    const keyMap = {
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.numpad0: 0,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
    };
    if (keyMap.containsKey(key)) {
      _handleDigit(keyMap[key]!);
      return KeyEventResult.handled;
    }

    // Pfeile: links/rechts justieren; hoch/runter Achse wechseln
    if (key == LogicalKeyboardKey.arrowLeft) {
      _nudge(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _nudge(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _activeAxis = 0);
      HapticFeedback.selectionClick();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _activeAxis = 1);
      HapticFeedback.selectionClick();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------- Build ----------------------------------------

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Focus(
              autofocus: true,
              onKeyEvent: _onKey,
              child: ZenGlassCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                topOpacity: .20,
                bottomOpacity: .20,
                borderOpacity: .22,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        const ExcludeSemantics(
                          child: Icon(Icons.spa_rounded, color: ZenColors.ink, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ZenColors.inkStrong,
                              height: 1.22,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Schließen',
                          onPressed: (_saving || _closing)
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded, color: ZenColors.ink),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Infozeile
                    Row(
                      children: [
                        const ExcludeSemantics(
                          child: Icon(Icons.info_outline_rounded,
                              size: 16, color: ZenColors.ink),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '0 = schwer, 2 = neutral, 4 = leicht · Werte gelten jeweils für Kopf & Körper.',
                            style: tt.bodySmall?.copyWith(
                              color: ZenColors.ink.withValues(alpha: .75),
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Kopf (mental)
                    _ScoreRow(
                      label: 'Kopf',
                      semanticsGroupLabel: 'Mentale Stimmung – Kopf',
                      selected: _mental,
                      highlight: _activeAxis == 0,
                      onPick: (_saving || _closing) ? null : _pickMental,
                    ),

                    const SizedBox(height: 10),

                    // Körper (physisch)
                    _ScoreRow(
                      label: 'Körper',
                      semanticsGroupLabel: 'Körperliche Stimmung – Körper',
                      selected: _physical,
                      highlight: _activeAxis == 1,
                      onPick: (_saving || _closing) ? null : _pickPhysical,
                    ),

                    const SizedBox(height: 14),

                    // Footer-Aktionen
                    Row(
                      children: [
                        Expanded(
                          child: ZenOutlineButton(
                            label: 'Abbrechen',
                            icon: Icons.arrow_back_rounded,
                            onPressed: (_saving || _closing)
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            color: ZenColors.inkStrong,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ZenPrimaryButton(
                            label: _saving ? 'Speichere …' : 'Speichern',
                            icon: Icons.bookmark_added_rounded,
                            onPressed: (_complete && !_saving && !_closing)
                                ? _saveAndClose
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------- Score-Zeile -------------------------------------

class _ScoreRow extends StatelessWidget {
  final String label;
  final String semanticsGroupLabel;
  final int? selected;
  final bool highlight;
  final ValueChanged<int>? onPick;

  const _ScoreRow({
    required this.label,
    required this.semanticsGroupLabel,
    required this.selected,
    required this.onPick,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final headline = Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            textAlign: TextAlign.left,
            style: tt.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: ZenColors.inkStrong,
            ),
          ),
        ),
        if (highlight) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: ShapeDecoration(
              color: ZenColors.jade.withValues(alpha: .10),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'aktiv',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: ZenColors.jade,
                height: 1.0,
              ),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      label: semanticsGroupLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headline,
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (int s = 0; s <= 4; s++)
                _ScorePill(
                  score: s,
                  selected: selected == s,
                  onTap: onPick == null ? null : () => onPick!(s),
                  semanticsLabel:
                      '$label: ${_scoreSpeak(s)} ($s von 4) – ${selected == s ? "ausgewählt" : "nicht ausgewählt"}',
                  tooltip: '$label – ${_scoreLabel(s)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------- Pill-Button ------------------------------------

class _ScorePill extends StatelessWidget {
  final int score; // 0–4
  final bool selected;
  final VoidCallback? onTap;
  final String semanticsLabel;
  final String tooltip;

  const _ScorePill({
    required this.score,
    required this.selected,
    required this.onTap,
    required this.semanticsLabel,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? ZenColors.jade.withValues(alpha: .18)
        : Colors.white.withValues(alpha: .66);
    final border = selected ? ZenColors.jade : ZenColors.outline;
    final fg = selected ? ZenColors.jade : ZenColors.inkStrong;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: border, width: 1.2)),
        color: bg,
        shadows: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        '$score',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: fg,
          height: 1.0,
          fontSize: 15,
        ),
      ),
    );

    return Semantics(
      button: true,
      toggled: selected,
      label: semanticsLabel,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            onTap: onTap,
            child: pill,
          ),
        ),
      ),
    );
  }
}

// ---------------------- Helpers: Labels & A11y-Texte -------------------------

String _scoreLabel(int s) {
  switch (s) {
    case 0:
      return 'sehr schwer';
    case 1:
      return 'eher schwer';
    case 2:
      return 'neutral';
    case 3:
      return 'eher leicht';
    case 4:
      return 'sehr leicht';
    default:
      return 'unbekannt';
  }
}

String _scoreSpeak(int s) {
  // Für Screen-Reader etwas ausführlicher.
  switch (s) {
    case 0:
      return 'sehr schwer, 0';
    case 1:
      return 'eher schwer, 1';
    case 2:
      return 'neutral, 2';
    case 3:
      return 'eher leicht, 3';
    case 4:
      return 'sehr leicht, 4';
    default:
      return 'unbekannt';
  }
}
