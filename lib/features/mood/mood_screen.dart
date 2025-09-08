// lib/features/mood/mood_screen.dart
//
// MoodScreen — Oxford-Zen (7-Icon Picker + optional Notiz)
// --------------------------------------------------------
// • Ultraschnell: Tippen auf Icon, optional kurze Notiz, Speichern.
// • UX: Glas-Karte, A11y-Labels, Haptik, Keyboard: Esc (clear), Cmd/Ctrl+Enter (save).
// • Daten: speichert als JournalEntry (moodLabel konsistent zu Timeline-Emojis).
// • Provider-first: JournalEntriesProvider.addDiary(...); Legacy-Fallback (MoodEntriesProvider) best-effort.
// • Keine ∞-Breiten: Buttons mit klaren Minbreiten.
//
// Abhängigkeiten: ZenAppBar/ZenGlassCard/ZenColors/ZenTextStyles (shared/ui/zen_widgets.dart, zen_style.dart)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/zen_style.dart';
import '../../shared/ui/zen_widgets.dart' hide ZenBackdrop, ZenGlassCard, ZenGlassInput;
import '../../models/journal_entries_provider.dart' show JournalEntriesProvider;

class MoodScreen extends StatefulWidget {
  /// Optionaler Callback (falls kein Provider vorhanden oder für Custom-Flows)
  final Future<void> Function(String moodLabel, {String? note})? onSave;

  const MoodScreen({super.key, this.onSave});

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodOption {
  final String emoji;
  final String label;
  final Color color;
  const _MoodOption(this.emoji, this.label, this.color);
}

class _MoodScreenState extends State<MoodScreen> {
  // Konsistente Labels (müssen zu JournalEntriesProvider._moodMap passen)
  static const _moods = <_MoodOption>[
    _MoodOption('😡', 'Wütend',    Color(0xFFD67873)), // Warm Rust
    _MoodOption('😱', 'Gestresst', Color(0xFFB2B8CB)), // Mist Blue
    _MoodOption('😔', 'Traurig',   Color(0xFF95A3B3)), // Blue Gray
    _MoodOption('😐', 'Neutral',   Color(0xFFB5B5B5)), // Neutral
    _MoodOption('🧘', 'Ruhig',     Color(0xFFA5CBA1)), // Soft Sage
    _MoodOption('😊', 'Glücklich', Color(0xFFF7CE84)), // Golden Mist
  ];

  final TextEditingController _noteCtrl = TextEditingController();
  final FocusNode _pageFocus = FocusNode();
  final FocusNode _noteFocus = FocusNode();

  String? _selected;
  bool _saving = false;

  static const _kMaxChars = 400;

  bool get _canSave => !_saving && _selected != null;

  @override
  void initState() {
    super.initState();
    _noteCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _pageFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  bool _handleKeys(RawKeyEvent e) {
    if (e is! RawKeyDownEvent) return false;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      HapticFeedback.selectionClick();
      setState(() {
        _selected = null;
        _noteCtrl.clear();
      });
      return true;
    }
    final withCtrlOrCmd = e.isControlPressed || e.isMetaPressed;
    final isEnter = e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (withCtrlOrCmd && isEnter) {
      if (_canSave) _save();
      return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);

    final mood = _selected!;
    final note = _noteCtrl.text.trim();
    final text = note.isNotEmpty ? note : 'Stimmungs-Check-in';

    try {
      var providerOk = false;
      // 1) Provider-first → Journal speichern (als Tagebuch, MoodLabel gesetzt)
      try {
        context.read<JournalEntriesProvider>().addDiary(
          text: text,
          moodLabel: mood,
          createdAt: DateTime.now(),
        );
        providerOk = true;
      } catch (_) {}

      // 2) Optionaler Legacy-Fallback (falls MoodEntriesProvider existiert)
      if (!providerOk) {
        try {
          // dynamisch, um harte Abhängigkeitskette zu vermeiden
          // ignore: avoid_dynamic_calls
          final dynamic moodProv = context.read<dynamic>();
          // Erwartete API (best-effort): add(label, note)
          // ignore: avoid_dynamic_calls
          moodProv.add(mood, note);
          providerOk = true;
        } catch (_) {}
      }

      // 3) Externer Callback (falls gesetzt)
      if (!providerOk && widget.onSave != null) {
        await widget.onSave!.call(mood, note: note.isEmpty ? null : note);
        providerOk = true;
      }

      if (!mounted) return;
      if (!providerOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konnte nicht speichern. Bitte Provider/Callback prüfen.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _saving = false);
        return;
      }

      ZenToast.show(context, 'Stimmung gespeichert');
      Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: RawKeyboardListener(
        focusNode: _pageFocus,
        autofocus: true,
        onKey: _handleKeys,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: const ZenAppBar(title: 'Wie fühlst du dich?', showBack: true),
          body: Stack(
            children: [
              // Einheits-Backdrop
              const Positioned.fill(
                child: ZenBackdrop(
                  asset: 'assets/voice_panda.png',
                  alignment: Alignment.center,
                  glow: .36,
                  vignette: .12,
                  enableHaze: true,
                  hazeStrength: .12,
                  saturation: .94,
                  wash: .08,
                ),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
                      child: ZenGlassCard(
                        borderRadius: const BorderRadius.all(ZenRadii.xl),
                        topOpacity: .30,
                        bottomOpacity: .12,
                        borderOpacity: .16,
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Ein kurzer Check-in.',
                              style: ZenTextStyles.h3.copyWith(color: ZenColors.jade, fontSize: 20),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tippe deine Stimmung. Eine Notiz ist optional.',
                              textAlign: TextAlign.center,
                              style: ZenTextStyles.caption.copyWith(
                                color: ZenColors.jadeMid.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Mood-Icons
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 10,
                              children: _moods.map((m) {
                                final selected = _selected == m.label;
                                return Semantics(
                                  label: 'Stimmung ${m.label}',
                                  button: true,
                                  selected: selected,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: _saving ? null : () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _selected = m.label);
                                    },
                                    child: AnimatedContainer(
                                      duration: animShort,
                                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? m.color.withValues(alpha: 0.18)
                                            : ZenColors.white.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: selected ? m.color : ZenColors.jade.withValues(alpha: 0.10),
                                          width: selected ? 2 : 1.1,
                                        ),
                                        boxShadow: selected
                                            ? [BoxShadow(color: m.color.withValues(alpha: 0.11), blurRadius: 8)]
                                            : const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(m.emoji, style: TextStyle(fontSize: selected ? 30 : 24)),
                                          const SizedBox(width: 10),
                                          Text(
                                            m.label,
                                            style: ZenTextStyles.caption.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: selected ? ZenColors.jade : ZenColors.jadeMid,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 18),

                            // Notizfeld
                            Focus(
                              focusNode: _noteFocus,
                              child: ZenGlassInput(
                                borderRadius: BorderRadius.circular(16),
                                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                                child: TextField(
                                  controller: _noteCtrl,
                                  minLines: 2,
                                  maxLines: 5,
                                  maxLength: _kMaxChars,
                                  textCapitalization: TextCapitalization.sentences,
                                  style: ZenTextStyles.body.copyWith(
                                    fontSize: 16.5,
                                    color: ZenColors.jade,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    counterText: '',
                                    hintText: 'Optional: kurze Notiz (z. B. „Spaziergang tat gut“)…',
                                    hintStyle: ZenTextStyles.caption.copyWith(
                                      color: ZenColors.jadeMid.withValues(alpha: 0.45),
                                      fontSize: 14.8,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    suffixIcon: _noteCtrl.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Text löschen',
                                            icon: const Icon(Icons.clear_rounded,
                                                size: 20, color: ZenColors.jadeMid),
                                            onPressed: () {
                                              HapticFeedback.selectionClick();
                                              _noteCtrl.clear();
                                              _noteFocus.requestFocus();
                                            },
                                          ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Actions
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Speichern'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: ZenColors.deepSage,
                                      foregroundColor: Colors.white,
                                      textStyle: ZenTextStyles.button.copyWith(fontSize: 16),
                                      minimumSize: const Size(170, 46),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      elevation: 3,
                                    ),
                                    onPressed: _canSave ? _save : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 46,
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: ZenColors.jadeMid,
                                      minimumSize: const Size(120, 46),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    onPressed: () => Navigator.of(context).maybePop(),
                                    child: const Text('Abbrechen'),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),
                            Text(
                              'Shortcut: Cmd/Ctrl + Enter',
                              style: ZenTextStyles.caption.copyWith(
                                color: ZenColors.jade.withValues(alpha: 0.55),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_saving)
                const IgnorePointer(
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
