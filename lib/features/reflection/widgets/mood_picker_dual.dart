// [BASELINE] lib/features/reflection/widgets/mood_picker_dual.dart (Stand: 2025-11-07, v1.0.0)
// Kutsche 2 — Dual-Mood-Picker (mental + körperlich)
// -----------------------------------------------------------------------------
// • Dual-Picker (0–4) mit Labels „Kopf“ (mental) & „Körper“ (physisch)
// • A11y-Hints / Screen-Reader-freundliche Semantik
// • Sofortiger Save-Call: Sobald beide Werte gewählt sind → onSave(...) & pop()
// • Optionaler „Speichern“-Button als Tastatur/A11y-Fallback (deaktiviert bis vollständig)
// • Optik im Oxford-Zen-Stil via ZenGlassCard / ZenColors
// -----------------------------------------------------------------------------
//
// API:
//   final res = await showPandaDualMoodPicker(
//     context,
//     title: 'Wähle Kopf & Körper',
//     onSave: (mental, physical) async {
//       // z.B. MemoryService.saveMoodEntry(DateTime.now(), mental, physical);
//     },
//   );
//   // res?.mental, res?.physical enthalten die 0–4 Scores.
//
// Hinweise:
// – 0 = sehr schwer/angespannt, 2 = neutral/ausgeglichen, 4 = sehr leicht/locker
// – Keine direkte Abhängigkeit zu MemoryService: Callback injizieren.
//
// -----------------------------------------------------------------------------

library mood_picker_dual;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/zen_style.dart';
import '../../../shared/ui/zen_widgets.dart';

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
  int? _mental;   // 0–4
  int? _physical; // 0–4
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mental = widget.initialMental;
    _physical = widget.initialPhysical;
    // Falls beide schon gesetzt → sofort speichern (Edge-Case)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoSave();
    });
  }

  Future<void> _tryAutoSave() async {
    if (!widget.autoSave) return;
    if (_mental != null && _physical != null && !_saving) {
      await _saveAndClose();
    }
  }

  Future<void> _saveAndClose() async {
    if (_mental == null || _physical == null) return;
    setState(() => _saving = true);

    final mental = _mental!;
    final physical = _physical!;
    try {
      if (widget.onSave != null) {
        await widget.onSave!(mental, physical);
      }
    } finally {
      if (mounted) {
        Navigator.of(context).pop(DualMoodResult(
          mental: mental,
          physical: physical,
          mentalLabel: _scoreLabel(mental),
          physicalLabel: _scoreLabel(physical),
        ));
      }
    }
  }

  void _pickMental(int s) {
    HapticFeedback.selectionClick();
    setState(() => _mental = s);
    _tryAutoSave();
  }

  void _pickPhysical(int s) {
    HapticFeedback.selectionClick();
    setState(() => _physical = s);
    _tryAutoSave();
  }

  bool get _complete => _mental != null && _physical != null;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                        onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
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
                    onPick: _saving ? null : _pickMental,
                  ),
                  const SizedBox(height: 10),
                  // Körper (physisch)
                  _ScoreRow(
                    label: 'Körper',
                    semanticsGroupLabel: 'Körperliche Stimmung – Körper',
                    selected: _physical,
                    onPick: _saving ? null : _pickPhysical,
                  ),
                  const SizedBox(height: 14),
                  // Footer-Aktionen
                  Row(
                    children: [
                      Expanded(
                        child: ZenOutlineButton(
                          label: 'Abbrechen',
                          icon: Icons.arrow_back_rounded,
                          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
                          color: ZenColors.inkStrong,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ZenPrimaryButton(
                          label: _saving ? 'Speichere …' : 'Speichern',
                          icon: Icons.bookmark_added_rounded,
                          onPressed: (_complete && !_saving) ? _saveAndClose : null,
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
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final String semanticsGroupLabel;
  final int? selected;
  final ValueChanged<int>? onPick;

  const _ScoreRow({
    required this.label,
    required this.semanticsGroupLabel,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label: semanticsGroupLabel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
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
          ),
        ],
      ),
    );
  }
}

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
