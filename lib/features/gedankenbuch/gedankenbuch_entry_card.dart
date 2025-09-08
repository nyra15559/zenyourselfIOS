// lib/features/_legacy_gedankenbuch/gedankenbuch_entry_card.dart
//
// GedankenbuchEntryCard — Glasige Entry-Karte (ruhig, wertig, fokussiert)
// -----------------------------------------------------------------------
// • Vollwertige Karte für BottomSheet/Embed: Text + Mic + Mood-Chips + Actions.
// • Sanftes "Ordnen" (Spacing, Satzende, Großschreibung) – ohne Paraphrase.
// • Speech-to-Text (speech_to_text) mit dezentem Glow beim Aufnehmen.
// • Auto-Locale für STT (Systemsprache, Fallback de_DE).
// • Desktop-Shortcut: Ctrl/Cmd + Enter speichert.
// • API-kompatibel: EntryType, initialText/Mood, aiQuestion, onSave bleiben.
//
// Design: ruhige Glaskarte, begrenzte Höhe, klare Abstände, weiche Schatten.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../shared/zen_style.dart' as zs;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenGlassCard, ZenPrimaryButton, ZenOutlineButton, ZenGhostButtonDanger, ZenInfoBar;

/// Öffentliche API bleibt erhalten
enum EntryType { journal, reflexion }

class GedankenbuchEntryCard extends StatefulWidget {
  final void Function(
    String text,
    String mood, {
    String? aiQuestion,
    bool isReflection,
  })? onSave;

  final String? initialText;
  final String? initialMood;
  final String? aiQuestion;
  final EntryType entryType;

  const GedankenbuchEntryCard({
    super.key,
    this.onSave,
    this.initialText,
    this.initialMood,
    this.aiQuestion,
    this.entryType = EntryType.journal,
  });

  @override
  State<GedankenbuchEntryCard> createState() => _GedankenbuchEntryCardState();
}

class _GedankenbuchEntryCardState extends State<GedankenbuchEntryCard>
    with TickerProviderStateMixin {
  // --- Text/Mood ---
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _selectedMood;
  static const _kMaxChars = 2000;

  // --- Speech ---
  late final stt.SpeechToText _speech;
  bool _speechReady = false;
  bool _isListening = false;
  String _dictationBase = '';
  String? _micInfo;
  String? _localeId; // dynamisch ermittelte Locale
  late final AnimationController _glowCtrl;

  // --- Auto-Ordnen (debounced) ---
  Timer? _debounce;
  bool _busyClean = false;

  Color get _green => zs.ZenColors.deepSage;
  bool get _canSave => _controller.text.trim().isNotEmpty;
  bool get _micEnabled => _speechReady;

  final List<_MoodOption> _moods = const [
    _MoodOption('😊', 'Glücklich'),
    _MoodOption('🧘', 'Ruhig'),
    _MoodOption('😐', 'Neutral'),
    _MoodOption('😔', 'Traurig'),
    _MoodOption('😱', 'Gestresst'),
    _MoodOption('😡', 'Wütend'),
  ];

  bool get _isReflection => widget.entryType == EntryType.reflexion;

  @override
  void initState() {
    super.initState();
    _controller.text = (widget.initialText ?? '').trim();
    _selectedMood = widget.initialMood;

    _speech = stt.SpeechToText();
    _initSpeech();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _controller.addListener(() {
      setState(() {}); // Counter etc.
      _scheduleClean();
    });
    _scheduleClean();
  }

  @override
  void dispose() {
    try {
      _speech.stop();
    } catch (_) {}
    _debounce?.cancel();
    _controller.dispose();
    _glowCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------- Speech ----------------
  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') _stopListening();
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _speechReady = false;
            _isListening = false;
            _micInfo = 'Spracherkennung nicht verfügbar (${e.errorMsg}).';
          });
        },
      );

      String? chosenLocale;
      try {
        // System-Locale priorisieren, sonst erster passender 'de_*', sonst 'de_DE'
        final sys = await _speech.systemLocale();
        final locales = await _speech.locales();
        final sysId = sys?.localeId;
        if (sysId != null && locales.any((l) => l.localeId == sysId)) {
          chosenLocale = sysId;
        } else {
          final de = locales.firstWhere(
            (l) => l.localeId.toLowerCase().startsWith('de_'),
            orElse: () =>
                locales.isNotEmpty ? locales.first : stt.LocaleName('de_DE', 'German (DE)'),
          );
          chosenLocale = de.localeId;
        }
      } catch (_) {
        chosenLocale ??= 'de_DE';
      }

      if (!mounted) return;
      setState(() {
        _speechReady = ok;
        _localeId = chosenLocale;
        _micInfo = ok ? null : 'Mikrofon/Spracherkennung nicht verfügbar.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechReady = false;
        _micInfo = 'Mikrofon nicht bereit. Prüfe Zugriffsrechte.';
      });
    }
  }

  Future<void> _startListening() async {
    if (!_micEnabled || _isListening) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isListening = true;
      _micInfo = null;
      _dictationBase = _controller.text.trim();
    });

    try {
      await _speech.listen(
        localeId: _localeId ?? 'de_DE',
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 6),
        partialResults: true,
        onResult: (r) {
          if (!mounted) return;
          final recognized = r.recognizedWords.trim();
          if (recognized.isEmpty) return;
          var next =
              _dictationBase.isEmpty ? recognized : '$_dictationBase $recognized';
          next = next.trim();
          if (next.length > _kMaxChars) next = next.substring(0, _kMaxChars);
          _controller.value = TextEditingValue(
            text: next,
            selection: TextSelection.fromPosition(
              TextPosition(offset: next.length),
            ),
          );
          if (r.finalResult) _dictationBase = next;
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _micInfo = 'Konnte nicht aufnehmen. Bitte erneut versuchen.';
      });
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;
    try {
      await _speech.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isListening = false);
  }

  // --------------- Auto-Ordnen ---------------
  void _scheduleClean() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _cleanNow);
  }

  Future<void> _cleanNow() async {
    setState(() => _busyClean = true);
    final raw = _controller.text;

    // sanfte, verlustfreie Ordnung – kein Umschreiben!
    final cleaned = _basicNormalize(raw);

    if (!mounted) return;
    setState(() {
      _busyClean = false;
      // Nur übernehmen, wenn Text tatsächlich sauberer ist (keine Paraphrase)
      if (cleaned != raw) {
        final pos = cleaned.length;
        _controller.value = TextEditingValue(
          text: cleaned,
          selection: TextSelection.collapsed(offset: pos),
        );
      }
    });
  }

  String _basicNormalize(String input) {
    var s = input.replaceAll('\r\n', '\n');
    s = s.split('\n').map((l) => l.trim()).join('\n');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1');
    s = s.replaceAll(RegExp(r'([(\[]) '), r'$1');
    s = s.replaceAll(RegExp(r' ([)\]])'), r'$1');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    final paras =
        s.split('\n\n').map((p) => p.trim()).where((p) => p.isNotEmpty);
    final fixed = <String>[];
    for (final para in paras) {
      final sentences = _splitIntoSentences(para);
      final out = <String>[];
      for (var t in sentences) {
        var tt = t.trim();
        if (tt.isEmpty) continue;

        final m = RegExp(r'^(\W*)(\p{L})(.*)$', unicode: true).firstMatch(tt);
        if (m != null) {
          final lead = m.group(1)!;
          final first = m.group(2)!;
          final rest = m.group(3)!;
          tt = '$lead${first.toUpperCase()}$rest';
        }
        if (!RegExp(r'[.!?…]$').hasMatch(tt)) {
          tt = '$tt.';
        }
        out.add(tt);
      }
      fixed.add(out.join(' '));
    }
    return fixed.join('\n\n');
  }

  List<String> _splitIntoSentences(String text) {
    final r = RegExp(r'(?<=[.!?…])\s+');
    final parts =
        text.split(r).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [text];
    return parts;
  }

  // --------------- Save ---------------
  Future<void> _save() async {
    if (!_canSave) return;
    HapticFeedback.lightImpact();
    await _stopListening();
    await _cleanNow();

    final text = _controller.text.trim();
    final mood = _selectedMood ?? 'Neutral';

    // API-kompatibel: onSave aufrufen
    widget.onSave?.call(
      text,
      mood,
      aiQuestion: _isReflection ? widget.aiQuestion : null,
      isReflection: _isReflection,
    );
  }

  // --------------- Keyboard Shortcuts ---------------
  Map<ShortcutActivator, Intent> get _shortcuts {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return <ShortcutActivator, Intent>{
      // Cmd+Enter (macOS) / Ctrl+Enter (Win/Linux)
      SingleActivator(
        LogicalKeyboardKey.enter,
        control: !isMac,
        meta: isMac,
      ): const _SaveIntent(),
    };
  }

  Map<Type, Action<Intent>> get _actions => <Type, Action<Intent>>{
        _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) {
          if (_canSave) _save();
          return null;
        }),
      };

  @override
  Widget build(BuildContext context) {
    const jade = zs.ZenColors.jade;
    final isNearingLimit = _controller.text.length > _kMaxChars * 0.9;

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          autofocus: true,
          child: zw.ZenGlassCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
            topOpacity: .30,
            bottomOpacity: .12,
            borderOpacity: .18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      _isReflection
                          ? Icons.psychology_alt_rounded
                          : Icons.menu_book_rounded,
                      size: 20,
                      color: jade,
                      semanticLabel: _isReflection ? 'Reflexion' : 'Tagebuch',
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isReflection ? 'Reflexion' : 'Neuer Tagebucheintrag',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: zs.ZenColors.deepSage,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    // "Jetzt ordnen"
                    Tooltip(
                      message: 'Text sanft ordnen (ohne umzuschreiben)',
                      child: IconButton(
                        onPressed: _busyClean ? null : _cleanNow,
                        icon: _busyClean
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_fix_high_rounded),
                        color: jade,
                      ),
                    ),
                  ],
                ),

                if (_isReflection &&
                    (widget.aiQuestion ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.aiQuestion!.trim(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: zs.ZenColors.inkStrong,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Inputzeile (Mic + Text)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .55),
                    border: Border.all(
                      color: zs.ZenColors.jadeMid.withValues(alpha: .20),
                    ),
                    borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                    boxShadow: const [
                      BoxShadow(color: Color(0x12000000), blurRadius: 10)
                    ],
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      // Mic
                      Tooltip(
                        message: _isListening
                            ? 'Aufnahme stoppen'
                            : (!_micEnabled
                                ? 'Mikrofon nicht bereit'
                                : 'Einsprechen'),
                        child: Semantics(
                          button: true,
                          label: _isListening ? 'Aufnahme stoppen' : 'Einsprechen',
                          child: GestureDetector(
                            onTap: !_micEnabled
                                ? null
                                : (_isListening ? _stopListening : _startListening),
                            child: AnimatedBuilder(
                              animation: _glowCtrl,
                              builder: (_, __) {
                                final glow = 18 + (28 - 18) * _glowCtrl.value;
                                final borderColor = _micEnabled
                                    ? _green.withValues(alpha: _isListening ? 0.00 : 0.40)
                                    : Colors.grey.withValues(alpha: 0.35);
                                return Opacity(
                                  opacity: _micEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isListening ? _green : Colors.transparent,
                                      boxShadow: _isListening
                                          ? [
                                              BoxShadow(
                                                color: _green.withOpacity(
                                                    0.22 + 0.10 * _glowCtrl.value),
                                                blurRadius: glow,
                                                spreadRadius: 1.0,
                                              ),
                                            ]
                                          : [],
                                      border: Border.all(color: borderColor, width: 1.2),
                                    ),
                                    child: Icon(
                                      _isListening ? Icons.mic : Icons.mic_none,
                                      size: 20,
                                      color: _isListening
                                          ? Colors.white
                                          : (_micEnabled ? _green : Colors.grey),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Text
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 2,
                          maxLines: 5,
                          maxLength: _kMaxChars,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText: 'Deine Worte … (du kannst auch sprechen)',
                            counterText: '',
                            border: InputBorder.none,
                          ),
                          enableSuggestions: true,
                          autocorrect: false,
                          onEditingComplete:
                              () {}, // Enter: keine Aktion, nur neue Zeile
                        ),
                      ),
                      // Clear
                      if (_controller.text.isNotEmpty)
                        Tooltip(
                          message: 'Text löschen',
                          child: IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            color: zs.ZenColors.jadeMid,
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _controller.clear();
                                _dictationBase = '';
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // Mic/Info
                if (!_speechReady || _micInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: zw.ZenInfoBar(
                      message: _micInfo ??
                          'Mikrofon nicht bereit. Prüfe Zugriffsrechte!',
                      actionLabel: 'Erneut versuchen',
                      onAction: _initSpeech,
                    ),
                  ),

                const SizedBox(height: 12),

                // Mood-Chips
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: _moods.map((m) {
                    final selected = _selectedMood == m.label;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedMood = m.label);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? _green.withValues(alpha: 0.10)
                              : zs.ZenColors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? _green.withValues(alpha: 0.55)
                                : Colors.transparent,
                            width: 1.2,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 6,
                                  )
                                ]
                              : [],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(m.emoji,
                                style: TextStyle(fontSize: selected ? 22 : 18)),
                            const SizedBox(width: 8),
                            Text(
                              m.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: selected ? _green : zs.ZenColors.jadeMid,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.1,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),

                // Aktionen
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    zw.ZenPrimaryButton(
                      label: _isReflection
                          ? 'Reflexion speichern'
                          : 'Eintrag speichern',
                      icon: Icons.check_rounded,
                      height: 46,
                      onPressed: _canSave ? _save : null,
                    ),
                    zw.ZenOutlineButton(
                      label: 'Kopieren',
                      icon: Icons.copy_all_outlined,
                      height: 46,
                      onPressed: _controller.text.trim().isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: _controller.text.trim()),
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('In Zwischenablage kopiert')),
                              );
                            },
                    ),
                    zw.ZenGhostButtonDanger(
                      label: 'Löschen',
                      onPressed:
                          (_controller.text.isNotEmpty || _selectedMood != null)
                              ? () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _controller.clear();
                                    _selectedMood = null;
                                    _dictationBase = '';
                                  });
                                }
                              : null,
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_controller.text.length}/$_kMaxChars',
                    // Material 3 (caption → bodySmall)
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isNearingLimit
                              ? Colors.redAccent.withValues(alpha: 0.85)
                              : _green.withValues(alpha: 0.52),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _MoodOption {
  final String emoji;
  final String label;
  const _MoodOption(this.emoji, this.label);
}
