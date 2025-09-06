// lib/features/journal/entry_editor.dart
//
// EntryEditor — Zen v6.6 (Story-like Composer, "Loslassen")
// -----------------------------------------------------------------------------
// • Vollbild-Composer mit PandaHeader (wie Pro/Kurzgeschichte).
// • Felder: Überschrift (einzeilig) + großer Textbereich (ZenGlassInput).
// • Dezente Tool-Leiste im Feld (Mic + Magic), kein Top-Handle.
// • Mood-Auswahl (ChoiceChips).
// • Copy-Zeile „Bleibt lokal. Teilen ist optional.“
// • Aktionen: ① Loslassen (Primary) ② Als Reflexion speichern (Outlined).
// • Provider: addDiary / addReflection.
// • Spellcheck aus; ruhige, warme Typo; Save-Overlay.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Zen-Design (Tokens)
import '../../shared/zen_style.dart' as zs
    show ZenColors, ZenTextStyles, ZenRadii;

// Zen-Widgets
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenAppBar, ZenGlassCard, ZenGlassInput, PandaHeader;

// Daten/Provider
import '../../models/journal_entries_provider.dart';

class EntryEditor extends StatefulWidget {
  final String? initialTitle;
  final String? initialText;
  final String? initialMood; // 'Glücklich' | 'Ruhig' | 'Neutral' | 'Traurig' | 'Gestresst' | 'Wütend'

  const EntryEditor({
    super.key,
    this.initialTitle,
    this.initialText,
    this.initialMood,
  });

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _titleNode = FocusNode();
  final _textNode = FocusNode();

  String _mood = 'Neutral';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = (widget.initialTitle ?? '').trim();
    _textCtrl.text  = (widget.initialText  ?? '').trim();
    _mood = (widget.initialMood ??
        ((_textCtrl.text.isEmpty && _titleCtrl.text.isEmpty) ? 'Neutral' : 'Ruhig'));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    _titleNode.dispose();
    _textNode.dispose();
    super.dispose();
  }

  bool get _canSave => _textCtrl.text.trim().isNotEmpty;

  Future<void> _save({required bool asReflection}) async {
    if (_saving || !_canSave) return;
    setState(() => _saving = true);

    try {
      final p     = context.read<JournalEntriesProvider>();
      final text  = _textCtrl.text.trim();
      final title = _titleCtrl.text.trim();
      final body  = _composeBody(title, text);
      final mood  = _mood;

      if (asReflection) {
        p.addReflection(text: body, moodLabel: mood, aiQuestion: null);
      } else {
        p.addDiary(text: body, moodLabel: mood);
      }

      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(asReflection ? 'Reflexion gespeichert' : 'Eintrag gespeichert')),
      );
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konnte nicht speichern. Bitte erneut versuchen.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _composeBody(String title, String body) {
    if (title.isEmpty) return body;
    return '$title\n\n$body';
  }

  // --- Text säubern (ohne Paraphrasieren; nur Whitespaces/Zeichensetzung) ---
  void _cleanText() {
    var s = _textCtrl.text;

    // Erhalte Leerzeilen, säubere pro Zeile einfache Leerzeichen
    final lines = s.split('\n').map((line) {
      var t = line;
      // Doppel-Spaces -> Single
      t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
      // Space vor Satzzeichen entfernen
      t = t.replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1');
      // Space nach Satzzeichen sicherstellen (außer am Zeilenende)
      t = t.replaceAllMapped(RegExp(r'([,.;:!?])(?!\s|$)'), (m) => '${m[1]} ');
      return t.trimRight();
    }).toList();

    s = lines.join('\n').trimRight();

    // Mehrfache Leerzeilen auf max. 2 begrenzen
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    _textCtrl.value = _textCtrl.value.copyWith(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
      composing: TextRange.empty,
    );
    HapticFeedback.selectionClick();
  }

  // --- (UI) Mic-Button Stub: keine Abhängigkeit, nur freundliche Info -------
  void _onMicTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mikrofon kommt – Voice-Input wird hier eingebaut.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final isMobile = MediaQuery.of(context).size.width < 470;
    final pandaSize = isMobile ? 88.0 : 112.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: const zw.ZenAppBar(title: null, showBack: true),
        body: Stack(
          children: [
            // Ruhiger, konsistenter Backdrop
            const Positioned.fill(
              child: zw.ZenBackdrop(
                asset: 'assets/pro_screen.png',
                alignment: Alignment.center,
                glow: .32,
                vignette: .12,
                enableHaze: true,
                hazeStrength: .14,
                saturation: .94,
                wash: .10,
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Panda-Header (wie Pro/Kurzgeschichte)
                        zw.PandaHeader(
                          title: 'Dein Gedankenbuch',
                          caption: 'Zeit hat keine Eile.',
                          pandaSize: pandaSize,
                          strongTitleGreen: true,
                        ),

                        // Eingabe-Karte (wie Story-Karte, aber editierbar)
                        zw.ZenGlassCard(
                          borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                          topOpacity: .24,
                          bottomOpacity: .10,
                          borderOpacity: .16,
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Überschrift
                              Semantics(
                                label: 'Überschrift',
                                textField: true,
                                child: TextField(
                                  controller: _titleCtrl,
                                  focusNode: _titleNode,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _textNode.requestFocus(),
                                  spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                                  autocorrect: false,
                                  enableSuggestions: true,
                                  decoration: const InputDecoration(
                                    hintText: 'Überschrift',
                                    border: InputBorder.none,
                                  ),
                                  style: zs.ZenTextStyles.h2.copyWith(
                                    color: zs.ZenColors.jade,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Großer Textbereich im Glas-Rahmen + Tool-Leiste
                              zw.ZenGlassInput(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(minHeight: 160),
                                      child: Semantics(
                                        label: 'Gedanken Textfeld',
                                        textField: true,
                                        child: TextField(
                                          controller: _textCtrl,
                                          focusNode: _textNode,
                                          maxLines: null,
                                          minLines: 6,
                                          keyboardType: TextInputType.multiline,
                                          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                                          autocorrect: false,
                                          enableSuggestions: true,
                                          decoration: const InputDecoration(
                                            hintText: 'Schreibe hier deine Gedanken …',
                                            border: InputBorder.none,
                                          ),
                                          style: zs.ZenTextStyles.body.copyWith(
                                            color: zs.ZenColors.inkStrong,
                                            fontSize: 17,
                                            height: 1.42,
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    // Tool-Leiste (dezent, nicht am Rand)
                                    Row(
                                      children: [
                                        _ToolButton(
                                          icon: Icons.mic_none_rounded,
                                          label: 'Voice',
                                          onTap: _onMicTap,
                                        ),
                                        const SizedBox(width: 6),
                                        _ToolButton(
                                          icon: Icons.auto_fix_high_rounded,
                                          label: 'Magic',
                                          onTap: _cleanText,
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${_textCtrl.text.trim().length} Zeichen',
                                          style: zs.ZenTextStyles.caption.copyWith(
                                            color: zs.ZenColors.inkSubtle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Mood-Auswahl (dezent)
                              _MoodRow(
                                selected: _mood,
                                onSelect: (m) => setState(() => _mood = m),
                                compact: isMobile,
                              ),

                              const SizedBox(height: 10),

                              // Hinweiszeile (lokal)
                              Align(
                                alignment: Alignment.center,
                                child: Text(
                                  'Bleibt lokal. Teilen ist optional.',
                                  style: zs.ZenTextStyles.caption
                                      .copyWith(color: zs.ZenColors.inkSubtle),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Aktionen
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  // Primary: Loslassen
                                  SizedBox(
                                    width: 280,
                                    child: ElevatedButton.icon(
                                      onPressed: _canSave && !_saving
                                          ? () => _save(asReflection: false)
                                          : null,
                                      icon: const Icon(Icons.check_circle_rounded),
                                      label: const Text('Loslassen'),
                                    ),
                                  ),
                                  // Outlined: Als Reflexion speichern
                                  SizedBox(
                                    width: 280,
                                    child: OutlinedButton.icon(
                                      onPressed: _canSave && !_saving
                                          ? () => _save(asReflection: true)
                                          : null,
                                      icon: const Icon(Icons.psychology_alt_rounded),
                                      label: const Text('Als Reflexion speichern'),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: zs.ZenColors.jade.withOpacity(.75),
                                          width: 1.1,
                                        ),
                                        foregroundColor: zs.ZenColors.jade,
                                        minimumSize: const Size(0, 52),
                                      ),
                                    ),
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
              ),
            ),

            if (_saving) const _CenteredSavingOverlay(),
          ],
        ),
      ),
    );
  }
}

// ---- kleine Tool-Buttons ----------------------------------------------------

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: zs.ZenColors.ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: zs.ZenTextStyles.caption.copyWith(
                  color: zs.ZenColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Mood-Reihe -------------------------------------------------------------

class _MoodRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final bool compact;

  const _MoodRow({
    required this.selected,
    required this.onSelect,
    this.compact = false,
  });

  static const List<String> _moods = <String>[
    'Glücklich',
    'Ruhig',
    'Neutral',
    'Traurig',
    'Gestresst',
    'Wütend',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: _moods.map((m) {
        final isSel = m == selected;
        return ChoiceChip(
          label: Text(m),
          selected: isSel,
          onSelected: (_) => onSelect(m),
          visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selectedColor: zs.ZenColors.jade.withOpacity(.10),
          side: BorderSide(
            color: isSel ? zs.ZenColors.jade.withOpacity(.55) : zs.ZenColors.jade.withOpacity(.22),
          ),
          shape: const StadiumBorder(),
        );
      }).toList(),
    );
  }
}

// ---- Speichern-Overlay (zentriert, nicht über Back-Pfeil) ------------------

class _CenteredSavingOverlay extends StatelessWidget {
  const _CenteredSavingOverlay();

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: Container(
          color: Colors.black.withOpacity(0.08),
          padding: EdgeInsets.only(top: topPad),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              child: zw.ZenGlassCard(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Speichere …',
                      style: TextStyle(fontSize: 15.5),
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
