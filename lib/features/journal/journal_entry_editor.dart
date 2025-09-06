// lib/features/journal/journal_entry_editor.dart
//
// v8 — JournalEntryEditor (Oxford-Zen)
// -----------------------------------------------------------------------------
// Ziel
// - Ruhiger Editor für Tagebuch-Einträge (nur „note“, keine Reflexion).
// - Bottom-Input (Mic + Text): kurzes Feld zum Anfügen; Transkripte landen dort.
// - Hauptfeld: großer Multi-Line-Editor in Glas-Karte.
// - Auto-Clean-Pipeline: vorsichtige Korrektur (Whitespace, Satzzeichen,
//   Ellipsen, Dashes, ein paar sehr häufige DE-Tippfehler) — *ohne Paraphrase*.
// - Speichern in JournalEntriesProvider (Dart-2.x-kompatibel).
//
// Abhängigkeiten im Projekt vorhanden:
//   ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, ZenColors, ZenRadii, ZenToast
//   JournalEntriesProvider / JournalEntry
//   SpeechService (transcript$ / start() / stop() / isRecording)
//
// UX-Hinweise
// - „Korrigieren“ ist idempotent und defensiv (kein Umformulieren).
// - Mic-Transkript wird in das *untere* Inputfeld geschrieben; per Senden
//   (↩︎-Icon oder Ctrl/Cmd+Enter) wird es an den großen Editor angefügt.
// - Speichern legt/aktualisiert einen JournalEntry (type: note).
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/zen_style.dart' as zs hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, ZenToast;

import '../../models/journal_entries_provider.dart';
import '../../data/journal_entry.dart';
import '../../services/speech_service.dart';

class JournalEntryEditor extends StatefulWidget {
  /// Optional: vorhandener Eintrag zum Bearbeiten.
  final JournalEntry? existing;

  /// Optionaler Seed-Text (z. B. aus einem Prompt oder einer Selektion).
  final String? initialText;

  /// Optionales Label (wird *nicht* persistiert, nur Überschrift im UI).
  final String? title;

  /// Callback nach erfolgreichem Speichern.
  final VoidCallback? onSaved;

  const JournalEntryEditor({
    Key? key,
    this.existing,
    this.initialText,
    this.title,
    this.onSaved,
  }) : super(key: key);

  @override
  State<JournalEntryEditor> createState() => _JournalEntryEditorState();
}

class _JournalEntryEditorState extends State<JournalEntryEditor> {
  static const Duration _animShort = Duration(milliseconds: 200);

  final TextEditingController _editorCtrl = TextEditingController();
  final TextEditingController _quickCtrl  = TextEditingController();

  final FocusNode _editorFocus = FocusNode();
  final FocusNode _quickFocus  = FocusNode();
  final FocusNode _pageFocus   = FocusNode();

  final ScrollController _scroll = ScrollController();
  late final AnimationController _fadeCtrl;

  final SpeechService _speech = SpeechService();
  StreamSubscription<String>? _speechSub;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: _TickerProvider(this), duration: _animShort);

    // Seed
    final seed = (widget.existing?.text ?? widget.initialText ?? '').trim();
    if (seed.isNotEmpty) _editorCtrl.text = seed;

    // Mic → quick input
    _speechSub = _speech.transcript$.listen((t) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cur = _quickCtrl.text.trim();
        final joined = (cur.isEmpty ? t : '$cur\n$t').trim();
        _quickCtrl.text = joined;
        _quickCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _quickCtrl.text.length),
        );
        FocusScope.of(context).requestFocus(_quickFocus);
      });
    });

    _fadeCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _speechSub?.cancel();
    _speech.dispose();
    _editorCtrl.dispose();
    _quickCtrl.dispose();
    _editorFocus.dispose();
    _quickFocus.dispose();
    _pageFocus.dispose();
    _scroll.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ---------------- Keyboard Shortcuts ---------------------------------------

  KeyEventResult _handleKey(RawKeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.escape && _speech.isRecording) {
      _toggleMic();
      return KeyEventResult.handled;
    }
    final isEnter = e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter;
    final withCtrlOrCmd = e.isControlPressed || e.isMetaPressed;
    if (withCtrlOrCmd && isEnter) {
      // Ctrl/Cmd+Enter → Quick anfügen
      _appendQuick();
      return KeyEventResult.handled;
    }
    if (withCtrlOrCmd && e.logicalKey == LogicalKeyboardKey.keyS) {
      _save();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------- Actions ---------------------------------------------------

  void _appendQuick() {
    final add = _quickCtrl.text.trim();
    if (add.isEmpty) return;
    final base = _editorCtrl.text.trimRight();
    final next = base.isEmpty ? add : '$base\n\n$add';
    setState(() => _editorCtrl.text = next);
    _editorCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _editorCtrl.text.length),
    );
    _quickCtrl.clear();
    _scrollToBottom();
    HapticFeedback.selectionClick();
  }

  Future<void> _toggleMic() async {
    try {
      if (_speech.isRecording) {
        await _speech.stop();
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_quickFocus);
      } else {
        HapticFeedback.selectionClick();
        FocusScope.of(context).unfocus();
        await _speech.start();
      }
      if (mounted) setState(() {});
    } catch (_) {
      zw.ZenToast.show(context, 'Mikrofon nicht verfügbar. Erlaube bitte den Zugriff.');
    }
  }

  void _autoClean() {
    final before = _editorCtrl.text;
    final after  = _autoCleanPipeline(before);
    if (after != before) {
      setState(() => _editorCtrl.text = after);
      _editorCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _editorCtrl.text.length),
      );
    }
    HapticFeedback.selectionClick();
    zw.ZenToast.show(context, 'Text vorsichtig korrigiert');
  }

  Future<void> _save() async {
    if (_saving) return;
    final raw = _editorCtrl.text.trim();
    if (raw.isEmpty) {
      zw.ZenToast.show(context, 'Schreibe erst etwas in deinen Eintrag.');
      FocusScope.of(context).requestFocus(_editorFocus);
      return;
    }

    setState(() => _saving = true);
    try {
      final cleaned = _autoCleanPipeline(raw);
      final prov = context.read<JournalEntriesProvider>();

      // Bestehenden ersetzen oder neuen anlegen
      final String id = widget.existing?.id ?? _makeId();
      final DateTime createdUtc = (widget.existing?.createdAt ?? DateTime.now()).toUtc();

      final Map<String, dynamic> v = <String, dynamic>{
        'id': id,
        'ts': createdUtc.toIso8601String(),
        'createdAt': createdUtc.toIso8601String(),
        'type': 'note',
        'text': cleaned,
        'label': (widget.title ?? '').trim().isEmpty ? null : widget.title!.trim(),
        'answer': null,
        'analysis': null,
        'reflection': null,
        'links': {'story_id': null},
        'isReflection': false,
        'aiQuestion': null,
        'kind': 'note',
      };

      final entry = JournalEntry.fromJson(v);

      // Provider aktualisieren (defensiv, kompatibel zu v8)
      final current = List<JournalEntry>.from(prov.entries);
      final idx = current.indexWhere((e) => (e.id ?? '') == id);
      if (idx >= 0) {
        current[idx] = entry;
      } else {
        current.add(entry);
      }
      prov.replaceAll(current);

      zw.ZenToast.show(context, 'Eintrag gespeichert');
      widget.onSaved?.call();
      if (mounted) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------- Auto-Clean Pipeline --------------------------------------

  /// Vorsichtige, idempotente Pipeline:
  /// - Zeilenenden normalisieren, überflüssige Leerzeichen entfernen
  /// - Max. 2 aufeinanderfolgende Leerzeilen
  /// - Interpunktions-Spacing ("," "." "!" "?" ":" ";" vor/nach)
  /// - Ellipsen → „…“, Mehrfach-Ellipsen zu einer
  /// - Dashes: " - " → " – " (Gedankenstrich) zwischen Wörtern
  /// - Ein paar *sehr häufige* DE-Tippfehler per Wort-Mapping (word boundary)
  ///   (keine Grammatik-„Korrekturen“, kein Paraphrasieren)
  String _autoCleanPipeline(String input) {
    var s = input;

    // Normalisieren von CRLF / CR → LF
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Trim Whitespace an Zeilenenden
    s = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]+$'), '')).join('\n');

    // Mehrfach-Leerzeilen → max. 2
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // Innen-Whitespace: Mehrfach-Spaces → Single (aber Tabs/Neue Zeilen bleiben)
    s = s.replaceAll(RegExp(r'[ ]{2,}'), ' ');

    // Spacing vor Satzzeichen korrigieren: „Hallo , Welt !“ → „Hallo, Welt!“
    s = s.replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1');

    // Fehlendes Space nach Satzzeichen (falls Buchstabe/Zahl folgt)
    s = s.replaceAllMapped(RegExp(r'([,.!?;:])(?!\s|\n|$)'), (m) => '${m.group(1)} ');

    // Ellipsen: "..." oder "… …" → "…"
    s = s.replaceAll(RegExp(r'\.{3,}'), '…');
    s = s.replaceAll(RegExp(r'…{2,}'), '…');

    // Dashes: " - " (zwischen Wörtern) → " – "
    s = s.replaceAll(RegExp(r'(?<=\w)\s-\s(?=\w)'), ' – ');

    // Doppelte Satzzeichen (z. B. „!! !“) aufräumen
    s = s.replaceAll(RegExp(r'([!?])\s+\1'), r'$1$1');

    // Häufige DE-Tippfehler (sehr konservativ)
    final Map<RegExp, String> typo = <RegExp, String>{
      RegExp(r'\bvieleicht\b', caseSensitive: false): 'vielleicht',
      RegExp(r'\bdefinitv\b', caseSensitive: false): 'definitiv',
      RegExp(r'\bstandart\b', caseSensitive: false): 'Standard',
      RegExp(r'\bseperat\b', caseSensitive: false): 'separat',
      RegExp(r'\binterres+', caseSensitive: false): 'interess',
      RegExp(r'\bwiederspiegeln\b', caseSensitive: false): 'widerspiegeln',
      RegExp(r'\bgramatik\b', caseSensitive: false): 'Grammatik',
      RegExp(r'\bacc?ept\b', caseSensitive: false): 'accept', // falls EN-Fetzen
    };
    typo.forEach((rx, repl) {
      s = s.replaceAllMapped(rx, (m) {
        final g = m.group(0) ?? '';
        // Großschreibung am Wortanfang erhalten
        if (g.isNotEmpty && g[0].toUpperCase() == g[0]) {
          // Capitalize erste Letter im Replacement
          return repl.isEmpty ? repl : '${repl[0].toUpperCase()}${repl.substring(1)}';
        }
        return repl;
      });
    });

    // Letzte kosmetische Korrekturen
    s = s.replaceAll(RegExp(r'[ \t]+\n'), '\n'); // Space vor Zeilenumbruch
    s = s.trimRight();

    return s;
  }

  // ---------------- UI -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final isMobile = MediaQuery.of(context).size.width < 560;
    final pandaSize = MediaQuery.of(context).size.width < 470 ? 88.0 : 112.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: RawKeyboardListener(
        focusNode: _pageFocus,
        autofocus: true,
        onKey: _handleKey,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: const zw.ZenAppBar(title: null, showBack: true),
          body: Stack(
            children: [
              const Positioned.fill(
                child: zw.ZenBackdrop(
                  asset: 'assets/schoen.png',
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
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: zs.ZenSpacing.m,
                        right: zs.ZenSpacing.m,
                        top: isMobile ? 16 : 20,
                        bottom: 10,
                      ),
                      child: zw.PandaHeader(
                        title: widget.existing == null
                            ? (widget.title?.trim().isNotEmpty == true
                                ? widget.title!.trim()
                                : 'Neuer Eintrag')
                            : 'Eintrag bearbeiten',
                        caption: 'Schreibe in Ruhe. Ich bin hier.',
                        pandaSize: pandaSize,
                        strongTitleGreen: true,
                      ),
                    ),

                    // Editor Karte
                    Expanded(
                      child: FadeTransition(
                        opacity: _fadeCtrl.drive(Tween(begin: 0.0, end: 1.0)),
                        child: ListView(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(
                            zs.ZenSpacing.m, 0, zs.ZenSpacing.m, zs.ZenSpacing.s,
                          ),
                          children: [
                            zw.ZenGlassCard(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
                              topOpacity: .30,
                              bottomOpacity: .14,
                              borderOpacity: .18,
                              child: _EditorTextField(
                                controller: _editorCtrl,
                                focusNode: _editorFocus,
                                hint: 'Schreib, was du festhalten möchtest …',
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Action Row: Korrigieren + Speichern
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _autoClean,
                                  icon: const Icon(Icons.spellcheck),
                                  label: const Text('Korrigieren'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 42),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(zs.ZenRadii.m),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18, height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.bookmark_added_rounded),
                                  label: Text(_saving ? 'Speichern …' : 'Speichern'),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 42),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(zs.ZenRadii.m),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                // kleine Legende
                                Tooltip(
                                  message: 'Tipp: Ctrl/Cmd+S speichert',
                                  child: Icon(Icons.info_outline,
                                      size: 18, color: Colors.black.withOpacity(.45)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),

                    // Bottom-Input (Mic + Text → anfügen)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        zs.ZenSpacing.m, 0, zs.ZenSpacing.m, zs.ZenSpacing.s,
                      ),
                      child: _QuickAppendBar(
                        controller: _quickCtrl,
                        focusNode: _quickFocus,
                        isRecording: _speech.isRecording,
                        onMicToggle: _toggleMic,
                        onSend: _appendQuick,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: _animShort,
        curve: Curves.easeOut,
      );
    });
  }

  String _makeId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = Random().nextInt(0xFFFF);
    return 'n_${now}_$r';
  }
}

// ---------------- Widgets (intern) -------------------------------------------

class _EditorTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;

  const _EditorTextField({
    Key? key,
    required this.controller,
    this.focusNode,
    required this.hint,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium!;
    return TextField(
      focusNode: focusNode,
      controller: controller,
      keyboardType: TextInputType.multiline,
      maxLines: null,
      minLines: 10,
      textInputAction: TextInputAction.newline,
      autocorrect: true,
      enableSuggestions: true,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      style: base.copyWith(
        color: zs.ZenColors.jade,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: zs.ZenColors.jade,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: base.copyWith(
          color: zs.ZenColors.jade.withOpacity(.55),
          fontWeight: FontWeight.w500,
        ),
        border: InputBorder.none,
        isCollapsed: true,
      ),
    );
  }
}

class _QuickAppendBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSend;
  final VoidCallback onMicToggle;
  final bool isRecording;

  const _QuickAppendBar({
    Key? key,
    required this.controller,
    this.focusNode,
    required this.onSend,
    required this.onMicToggle,
    required this.isRecording,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const jade = zs.ZenColors.jade;
    final baseText = Theme.of(context).textTheme.bodyMedium!;
    final hintStyle = baseText.copyWith(color: jade.withOpacity(0.55));

    final List<BoxShadow> pulse = isRecording
        ? [
            BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 4)),
            BoxShadow(color: jade.withOpacity(0.30), blurRadius: 22, spreadRadius: 1.2),
          ]
        : [
            const BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
          ];

    return Container(
      decoration: BoxDecoration(
        color: zs.ZenColors.white,
        borderRadius: const BorderRadius.all(zs.ZenRadii.l),
        border: Border.all(color: jade.withOpacity(0.75), width: 2),
        boxShadow: pulse,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          return TextField(
            focusNode: focusNode,
            controller: controller,
            maxLines: null,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: true,
            spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
            style: baseText.copyWith(color: jade, fontWeight: FontWeight.w600),
            cursorColor: jade,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Schnell notieren … (Ctrl/Cmd+Enter fügt an)',
              hintStyle: hintStyle,
              border: InputBorder.none,
              isCollapsed: true,
              suffixIconConstraints: const BoxConstraints.tightFor(width: 128, height: 40),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: isRecording ? 'Aufnahme stoppen' : 'Sprechen',
                    child: IconButton(
                      onPressed: onMicToggle,
                      icon: Icon(
                        isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                        color: jade,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Anfügen',
                    child: IconButton(
                      onPressed: hasText ? onSend : null,
                      icon: Icon(
                        Icons.keyboard_return_rounded,
                        color: hasText ? jade : jade.withOpacity(.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------- Kleiner lokaler TickerProvider -----------------------------
// (vermeidet Ancestor-Lookups für AnimationController)

class _TickerProvider extends ChangeNotifier implements TickerProvider {
  _TickerProvider(this._state);
  final State _state;
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
