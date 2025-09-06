// lib/features/gedankenbuch/gedankenbuch_entry_screen.dart
//
// GedankenbuchEntryScreen — Oxford-Zen Composer v7.4 (Calm Single-Sheet)
// ----------------------------------------------------------------------
// Ziel: pures, ruhiges Schreiben – minimal, konsequent, fehlerverzeihend.
// • Ein Feld, eine Handlung: großes Schreibfeld auf einer Glas-Karte.
// • Leiste unten: Mood-Pille · Primär „Fertig“ · Overflow (…).
// • Speech-to-Text dezent: Mic-Puls, weicher Glow, klare Fehlermeldung.
// • Auto-Clean (debounced), verlustfrei: Spacing/Satzende/Kapitalisierung.
// • Overflow-Sheet: Als Reflexion speichern · Gedanken ordnen · Kopieren · Reflektieren · Löschen.
// • A11y: ESC stoppt Aufnahme/Back, Semantics-Counter versteckt; klare Live-Regionen.
// • Sanftes Saving-Overlay und „lokal“-Hinweis; weiche Haptik.
// • API exakt kompatibel: onSave, initialText/Mood, backgroundAsset, title*.
//
// Abhängigkeiten: ZenBackdrop, ZenGlassCard, ZenInfoBar, ZenToast, PandaHeader.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenGlassInput;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar, ZenInfoBar, ZenToast, PandaHeader;

import '../../models/journal_entries_provider.dart' show JournalEntriesProvider;
import '../reflection/reflection_screen.dart';
import '../../services/guidance_service.dart'
    show GuidanceService, StructuredThoughtResult;

class GedankenbuchEntryScreen extends StatefulWidget {
  const GedankenbuchEntryScreen({
    Key? key,
    this.onSave,
    this.initialText,
    this.initialMood,
    this.backgroundAsset = 'assets/schoen.png',
    this.titleNew = '',
    this.titleEdit = '',
  }) : super(key: key);

  final void Function(String text, String mood)? onSave;
  final String? initialText;
  final String? initialMood;
  final String backgroundAsset;
  final String titleNew;
  final String titleEdit;

  @override
  State<GedankenbuchEntryScreen> createState() =>
      _GedankenbuchEntryScreenState();
}

class _GedankenbuchEntryScreenState extends State<GedankenbuchEntryScreen>
    with TickerProviderStateMixin {
  // --- Text & Mood ---
  final _textController = TextEditingController();
  final _pageFocus = FocusNode();
  String? _selectedMood;

  // --- Dirty/Save Guard ---
  bool _saving = false;
  bool get _dirty =>
      (_textController.text.trim() != (widget.initialText ?? '').trim()) ||
      ((_selectedMood ?? 'Neutral') != (widget.initialMood ?? 'Neutral'));

  // --- Auto-Clean ---
  String _cleaned = '';
  bool _busyClean = false;
  Timer? _debounce;

  // --- Speech ---
  late final stt.SpeechToText _speech;
  bool _speechReady = false;
  bool _isListening = false;
  String _dictationBase = '';
  String? _micInfo; // Info/Fehlertext
  String? _localeId; // dynamisch ermittelte Locale

  // --- Animationen ---
  late final AnimationController _glowCtrl;
  static const _kAnimShort = Duration(milliseconds: 260);

  // --- Guidance (Gedanken ordnen) ---
  bool _structuring = false;

  // --- Limits ---
  static const int _kMaxChars = 2000;
  static const double _kMicGlowMin = 18.0;
  static const double _kMicGlowMax = 28.0;

  Color get _green => zs.ZenColors.deepSage;
  bool get _canSave =>
      !_saving && _textController.text.trim().isNotEmpty && !_structuring;
  bool get _micEnabled => _speechReady && !_saving;

  @override
  void initState() {
    super.initState();
    _textController.text = (widget.initialText ?? '').trim();
    _selectedMood = widget.initialMood;

    _speech = stt.SpeechToText();
    _initSpeech();

    _glowCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);

    _textController.addListener(() {
      setState(() {}); // Primary-Button + Counter aktualisieren
      _scheduleClean();
    });

    _scheduleClean(); // erste Runde
  }

  @override
  void dispose() {
    try {
      _speech.stop();
    } catch (_) {}
    _debounce?.cancel();
    _pageFocus.dispose();
    _textController.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  // ------------------- Speech -------------------
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
      _dictationBase = _textController.text.trim();
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

          _textController.value = TextEditingValue(
            text: next,
            selection:
                TextSelection.fromPosition(TextPosition(offset: next.length)),
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

  // ------------------- Auto-Clean -------------------
  void _scheduleClean() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _autoCleanNow);
  }

  Future<void> _autoCleanNow() async {
    final raw = _textController.text;
    setState(() => _busyClean = true);

    // 1) Lokale, verlustfreie Ordnung (keine Paraphrase)
    var cleaned = _basicNormalize(raw);

    // 2) Optionaler Remote-Hook (z. B. /normalize) – aktuell nicht aktiv
    try {
      final remote = await _tryRemoteNormalize(raw);
      if (remote != null && remote.trim().isNotEmpty) cleaned = remote;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _cleaned = cleaned;
      _busyClean = false;
    });
  }

  // Verlustfreie Normalisierung: Spacing, Satzende, Großschreibung am Satzanfang,
  // doppelte Leerzeichen/Zeilenumbrüche – ohne Umformulierungen.
  String _basicNormalize(String input) {
    var s = input.replaceAll('\r\n', '\n');

    // Zeilen trimmen + doppelte Spaces
    s = s.split('\n').map((l) => l.trim()).join('\n');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');

    // Leerzeichen bei Satzzeichen
    s = s.replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1');
    s = s.replaceAll(RegExp(r'([(\[]) '), r'$1');
    s = s.replaceAll(RegExp(r' ([)\]])'), r'$1');

    // Max. zwei Zeilenumbrüche
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

        // erster Buchstabe groß (ohne führende Zeichen zu verlieren)
        final m = RegExp(r'^(\W*)(\p{L})(.*)$', unicode: true).firstMatch(tt);
        if (m != null) {
          final lead = m.group(1)!;
          final first = m.group(2)!;
          final rest = m.group(3)!;
          tt = '$lead${first.toUpperCase()}$rest';
        }

        // Punkt, falls keiner vorhanden
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

  Future<String?> _tryRemoteNormalize(String raw) async {
    // Optional: GuidanceService.instance.normalize(raw)
    return null;
  }

  // ------------------- Save / Provider -------------------
  Future<void> _handleSave() async {
    if (!_canSave) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      await _stopListening();
      await _autoCleanNow();

      final text =
          _cleaned.isNotEmpty ? _cleaned : _textController.text.trim();
      final mood = _selectedMood ?? 'Neutral';

      if (widget.onSave != null) {
        widget.onSave!(text, mood);
      } else {
        context.read<JournalEntriesProvider>().addDiary(
              text: text,
              moodLabel: mood,
            );
      }

      if (!mounted) return;
      zw.ZenToast.show(context, 'Eintrag gespeichert');
      Navigator.of(context).maybePop(text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konnte nicht speichern. Bitte erneut versuchen.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleSaveReflection() async {
    if (!_canSave) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      await _stopListening();
      await _autoCleanNow();

      final text =
          _cleaned.isNotEmpty ? _cleaned : _textController.text.trim();
      final mood = _selectedMood ?? 'Neutral';

      context.read<JournalEntriesProvider>().addReflection(
            text: text,
            moodLabel: mood,
            aiQuestion: null,
          );

      if (!mounted) return;
      zw.ZenToast.show(context, 'Reflexion gespeichert');
      Navigator.of(context).maybePop(text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konnte nicht speichern. Bitte erneut versuchen.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------- Reflection (weiterführen) -------------------
  Future<void> _goToReflection() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await _stopListening();
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => ReflectionScreen(initialUserText: text)),
    );
  }

  // ------------------- Gedanken ordnen (Guidance) -------------------
  Future<void> _runStructureFlow() async {
    final input = _textController.text.trim();
    if (input.isEmpty) {
      zw.ZenToast.show(context, 'Bitte gib erst einen Gedanken ein.');
      return;
    }
    if (_structuring) return;

    setState(() => _structuring = true);
    try {
      final result =
          await GuidanceService.instance.structureThoughts(input);
      if (!mounted) return;
      await _showStructureSheet(result);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Konnte die Gedanken nicht ordnen. Versuche es später erneut.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _structuring = false);
    }
  }

  Future<void> _showStructureSheet(StructuredThoughtResult res) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(.35),
      builder: (ctx) {
        final offline = (res.source.toLowerCase() == 'offline');
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
              top: 12,
            ),
            child: zw.ZenGlassCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
              topOpacity: .30,
              bottomOpacity: .14,
              borderOpacity: .18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    height: 4,
                    width: 48,
                    margin:
                        const EdgeInsets.only(bottom: 12, top: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.10),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Gedanken geordnet',
                            style: Theme.of(ctx).textTheme.titleMedium),
                      ),
                      if (offline)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: zs.ZenColors.jade.withOpacity(.10),
                            border: Border.all(
                                color: zs.ZenColors.jade.withOpacity(.35)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Offline',
                            style: Theme.of(ctx)
                                .textTheme
                                .labelSmall!
                                .copyWith(
                                    color: zs.ZenColors.jade,
                                    fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _kv(ctx, 'Kerngedanke', res.coreIdea,
                      valueStyle: Theme.of(ctx).textTheme.bodyMedium!.copyWith(
                          color: zs.ZenColors.jade,
                          fontWeight: FontWeight.w600)),
                  if ((res.moodHint ?? '').trim().isNotEmpty)
                    _kv(ctx, 'Gefühls-Hinweis', res.moodHint!,
                        spacingTop: 10),
                  if (res.bullets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Stichpunkte',
                          style:
                              Theme.of(ctx).textTheme.labelLarge),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: res.bullets
                          .map((b) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('•  '),
                                    Expanded(child: Text(b)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                  if (res.nextSteps.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Nächste kleine Schritte',
                          style:
                              Theme.of(ctx).textTheme.labelLarge),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: res.nextSteps
                          .asMap()
                          .entries
                          .map((e) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 3),
                                child:
                                    Text('${e.key + 1}. ${e.value}'),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save_as_outlined),
                          label: const Text('Ordnen & speichern'),
                          onPressed: () async {
                            _applyStructuredToField(res);
                            Navigator.of(ctx).pop();
                            await _handleSave();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: zs.ZenColors.deepSage,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.all(zs.ZenRadii.m),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon:
                              const Icon(Icons.playlist_add_outlined),
                          label: const Text('Nur übernehmen'),
                          onPressed: () {
                            _applyStructuredToField(res);
                            Navigator.of(ctx).pop();
                            zw.ZenToast.show(context,
                                'Übernommen – du kannst noch anpassen.');
                          },
                          style: OutlinedButton.styleFrom(
                            shape: const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.all(zs.ZenRadii.m),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _kv(BuildContext ctx, String key, String value,
      {double spacingTop = 0, TextStyle? valueStyle}) {
    return Padding(
      padding: EdgeInsets.only(top: spacingTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(key, style: Theme.of(ctx).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(value,
              style: valueStyle ?? Theme.of(ctx).textTheme.bodySmall),
        ],
      ),
    );
  }

  void _applyStructuredToField(StructuredThoughtResult r) {
    final buf = StringBuffer();
    if (r.bullets.isNotEmpty) {
      for (final b in r.bullets) {
        buf.writeln('• $b');
      }
      buf.writeln();
    }
    buf.writeln('Kern: ${r.coreIdea}');
    if ((r.moodHint ?? '').trim().isNotEmpty) {
      buf.writeln('Gefühl: ${r.moodHint}');
    }
    if (r.nextSteps.isNotEmpty) {
      buf.writeln();
      buf.writeln('Nächste Schritte:');
      for (var i = 0; i < r.nextSteps.length; i++) {
        buf.writeln('${i + 1}. ${r.nextSteps[i]}');
      }
    }
    if (r.source.toLowerCase() == 'offline') {
      buf.writeln('\n(offline geordnet)');
    }
    var out = buf.toString().trimRight();
    if (out.length > _kMaxChars) out = out.substring(0, _kMaxChars);
    _textController.value = TextEditingValue(
      text: out,
      selection:
          TextSelection.fromPosition(TextPosition(offset: out.length)),
    );
  }

  // ------------------- UI -------------------
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 470;
    final kb = MediaQuery.of(context).viewInsets.bottom;

    return WillPopScope(
      onWillPop: () async {
        // ESC/Back: erst Aufnahme stoppen, dann ggf. Discard-Dialog
        if (_isListening) {
          await _stopListening();
          return false;
        }
        if (_saving || !_dirty) return true;
        final discard = await _confirmDiscard();
        return discard;
      },
      child: RawKeyboardListener(
        focusNode: _pageFocus,
        autofocus: true,
        onKey: _handleRawKeyEvent,
        child: Stack(
          children: [
            Scaffold(
              resizeToAvoidBottomInset: true,
              extendBodyBehindAppBar: true,
              appBar: const zw.ZenAppBar(
                title: null,
                showBack: true,
              ),
              body: Stack(
                children: [
                  Positioned.fill(
                    child: zw.ZenBackdrop(
                      asset: widget.backgroundAsset,
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
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        zs.ZenSpacing.m,
                        20,
                        zs.ZenSpacing.m,
                        kb > 0 ? kb + zs.ZenSpacing.m : zs.ZenSpacing.l,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // PandaHeader
                              zw.PandaHeader(
                                title: 'Dein Gedankenbuch',
                                caption:
                                    'Was möchtest du heute festhalten? Du kannst flüstern oder eintippen.',
                                pandaSize: isMobile ? 88.0 : 112.0,
                                strongTitleGreen: true,
                              ),
                              const SizedBox(height: 10),

                              // Glas-Karte: Editor
                              zw.ZenGlassCard(
                                padding: const EdgeInsets.fromLTRB(
                                    22, 18, 22, 20),
                                borderRadius: const BorderRadius.all(
                                    zs.ZenRadii.xl),
                                topOpacity: .30,
                                bottomOpacity: .14,
                                borderOpacity: .18,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Handle
                                    Container(
                                      height: 4,
                                      width: 48,
                                      margin: const EdgeInsets.only(
                                          bottom: 12, top: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withOpacity(.10),
                                        borderRadius:
                                            BorderRadius.circular(2),
                                      ),
                                    ),

                                    // TEXT-AREA (Mic + Text + Clean)
                                    _ComposerTextArea(
                                      controller: _textController,
                                      maxChars: _kMaxChars,
                                      micEnabled: _micEnabled,
                                      isListening: _isListening,
                                      onMicTap: !_micEnabled
                                          ? null
                                          : (_isListening
                                              ? _stopListening
                                              : _startListening),
                                      onCleanNow: _autoCleanNow,
                                      glowCtrl: _glowCtrl,
                                      green: _green,
                                      busyClean: _busyClean,
                                    ),

                                    // Länge (ruhige Leiste)
                                    const SizedBox(height: 8),
                                    _LengthMeter(
                                      current:
                                          _textController.text.length,
                                      max: _kMaxChars,
                                    ),
                                    const SizedBox(height: 8),

                                    // Mic-Status/Fehler bei Bedarf
                                    AnimatedSwitcher(
                                      duration: _kAnimShort,
                                      child: (!_speechReady ||
                                              _micInfo != null)
                                          ? Padding(
                                              padding:
                                                  const EdgeInsets.only(
                                                      top: 2),
                                              child: zw.ZenInfoBar(
                                                message: _micInfo ??
                                                    'Mikrofon nicht bereit. Prüfe Zugriffsrechte!',
                                                actionLabel:
                                                    'Erneut versuchen',
                                                onAction: _initSpeech,
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                    if (_structuring) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          SizedBox(
                                            height: 16,
                                            width: 16,
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 2),
                                          ),
                                          SizedBox(width: 8),
                                          Text('Ordne deine Gedanken …'),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 12),

                                    // BOTTOM-BAR: Mood-Pille · Fertig · …
                                    _ComposerBottomBar(
                                      selectedMood:
                                          _selectedMood ?? 'Neutral',
                                      onPickMood: (m) => setState(() {
                                        HapticFeedback.selectionClick();
                                        _selectedMood = m;
                                      }),
                                      onPrimary:
                                          _canSave ? _handleSave : null,
                                      onOverflow: () =>
                                          _openOverflowSheet(context),
                                    ),

                                    const SizedBox(height: 8),
                                    // Hinweis: lokal
                                    Text(
                                      'Bleibt lokal. Teilen ist optional.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color:
                                                zs.ZenColors.inkSubtle,
                                          ),
                                    ),

                                    // A11y Counter (unsichtbar)
                                    Semantics(
                                      label: 'Zeichenanzahl',
                                      value:
                                          '${_textController.text.length} von $_kMaxChars',
                                      child: const SizedBox(
                                          width: 1, height: 1),
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
                ],
              ),
            ),

            // Saving-Overlay (ruhig, zentriert)
            if (_saving)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(.06),
                    child: Center(
                      child: zw.ZenGlassCard(
                        padding: const EdgeInsets.fromLTRB(
                            22, 18, 22, 18),
                        borderRadius: const BorderRadius.all(
                            zs.ZenRadii.l),
                        topOpacity: .26,
                        bottomOpacity: .10,
                        borderOpacity: .18,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4),
                            ),
                            SizedBox(width: 12),
                            Text('Speichere …',
                                style: TextStyle(fontSize: 15.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- Keyboard Shortcuts ---
  void _handleRawKeyEvent(RawKeyEvent e) {
    if (e is! RawKeyDownEvent) return;

    if (e.logicalKey == LogicalKeyboardKey.escape) {
      if (_isListening) {
        _stopListening();
      } else {
        // Back: respektiert WillPopScope (Discard-Dialog)
        Navigator.of(context).maybePop();
      }
      return;
    }

    final withCtrlOrCmd = e.isControlPressed || e.isMetaPressed;
    final isEnter = e.logicalKey == LogicalKeyboardKey.enter;
    final isS = e.logicalKey == LogicalKeyboardKey.keyS;

    if (withCtrlOrCmd && (isEnter || isS)) {
      if (_canSave) _handleSave();
    }
  }

  // ------------------- Overflow & Mood Picker -------------------
  void _openOverflowSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.35),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: zw.ZenGlassCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              borderRadius:
                  const BorderRadius.all(zs.ZenRadii.xl),
              topOpacity: .28,
              bottomOpacity: .12,
              borderOpacity: .16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetItem(ctx, Icons.psychology_alt_rounded,
                      'Als Reflexion speichern',
                      onTap: _canSave
                          ? () async {
                              Navigator.pop(ctx);
                              await _handleSaveReflection();
                            }
                          : null),
                  _sheetItem(ctx, Icons.auto_fix_high_rounded,
                      'Gedanken ordnen',
                      onTap: _textController.text.trim().isNotEmpty &&
                              !_structuring
                          ? () async {
                              Navigator.pop(ctx);
                              await _runStructureFlow();
                            }
                          : null),
                  _sheetItem(ctx, Icons.copy_all_outlined, 'Kopieren',
                      onTap:
                          _textController.text.trim().isNotEmpty
                              ? () async {
                                  await Clipboard.setData(
                                      ClipboardData(
                                    text: _cleaned.isNotEmpty
                                        ? _cleaned
                                        : _textController.text,
                                  ));
                                  if (mounted) {
                                    zw.ZenToast.show(context,
                                        'In Zwischenablage kopiert');
                                  }
                                  Navigator.pop(ctx);
                                }
                              : null),
                  _sheetItem(ctx, Icons.psychology_alt_outlined,
                      'Weiter reflektieren',
                      onTap:
                          _textController.text.trim().isNotEmpty
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _goToReflection();
                                }
                              : null),
                  const Divider(height: 14),
                  _sheetItem(ctx, Icons.delete_outline_rounded,
                      'Löschen',
                      destructive: true,
                      onTap: (_textController.text.isNotEmpty ||
                              _selectedMood != null)
                          ? () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _textController.clear();
                                _selectedMood = null;
                                _dictationBase = '';
                                _cleaned = '';
                              });
                              Navigator.pop(ctx);
                            }
                          : null),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheetItem(BuildContext ctx, IconData icon, String label,
      {VoidCallback? onTap, bool destructive = false}) {
    final color =
        destructive ? Colors.redAccent : zs.ZenColors.jadeMid;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
              color: destructive
                  ? Colors.redAccent
                  : zs.ZenColors.inkStrong,
              fontWeight: FontWeight.w600,
            ),
      ),
      onTap: onTap,
      enabled: onTap != null,
    );
  }

  Future<bool> _confirmDiscard() async {
    final hasContent = _textController.text.trim().isNotEmpty;
    if (!hasContent && (_selectedMood ?? 'Neutral') == (widget.initialMood ?? 'Neutral')) {
      return true;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Änderungen verwerfen?'),
        content: const Text(
            'Dein Text ist noch nicht gespeichert. Möchtest du die Seite wirklich verlassen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zurück'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
            ),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _showMoodPicker(
      BuildContext ctx, String current, ValueChanged<String> onPick) {
    final all = ['Glücklich', 'Ruhig', 'Neutral', 'Traurig', 'Gestresst', 'Wütend'];
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: zw.ZenGlassCard(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            borderRadius:
                const BorderRadius.all(zs.ZenRadii.xl),
            topOpacity: .28,
            bottomOpacity: .12,
            borderOpacity: .16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in all)
                  ListTile(
                    leading: Text(_ComposerBottomBar.moodEmoji(m),
                        style: const TextStyle(fontSize: 20)),
                    title: Text(m),
                    trailing:
                        current == m ? const Icon(Icons.check_rounded) : null,
                    onTap: () {
                      onPick(m);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================== UI Sub-Widgets ===============================

class _ComposerTextArea extends StatelessWidget {
  final TextEditingController controller;
  final int maxChars;
  final bool micEnabled;
  final bool isListening;
  final VoidCallback? onMicTap;
  final VoidCallback onCleanNow;
  final AnimationController glowCtrl;
  final Color green;
  final bool busyClean;

  const _ComposerTextArea({
    required this.controller,
    required this.maxChars,
    required this.micEnabled,
    required this.isListening,
    required this.onMicTap,
    required this.onCleanNow,
    required this.glowCtrl,
    required this.green,
    required this.busyClean,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(.55),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: theme.colorScheme.outline.withOpacity(.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 10),
          // Mic (kompakt)
          GestureDetector(
            onTap: onMicTap,
            child: Opacity(
              opacity: micEnabled ? 1 : .5,
              child: AnimatedBuilder(
                animation: glowCtrl,
                builder: (_, __) {
                  final glow = _GedankenbuchEntryScreenState._kMicGlowMin +
                      (_GedankenbuchEntryScreenState._kMicGlowMax -
                              _GedankenbuchEntryScreenState._kMicGlowMin) *
                          glowCtrl.value;
                  return Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isListening ? green : Colors.transparent,
                      border: Border.all(
                        color: isListening
                            ? Colors.transparent
                            : green.withOpacity(.40),
                        width: 1.2,
                      ),
                      boxShadow: isListening
                          ? [
                              BoxShadow(
                                color: green.withOpacity(
                                    0.18 + 0.06 * glowCtrl.value),
                                blurRadius: glow,
                                spreadRadius: 1,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      isListening ? Icons.mic : Icons.mic_none,
                      size: 20,
                      color: isListening
                          ? Colors.white
                          : (micEnabled ? green : Colors.grey),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Textfeld
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 4,
              maxLines: 12,
              maxLength: maxChars,
              decoration: const InputDecoration(
                hintText: 'Schreibe hier in Ruhe …',
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.fromLTRB(0, 14, 0, 14),
              ),
              style: const TextStyle(
                fontFamily: 'ZenKalligrafie',
                fontSize: 17.3,
                color: zs.ZenColors.jade,
                height: 1.34,
              ),
              enableSuggestions: true,
              autocorrect: false,
            ),
          ),

          // Clean
          IconButton(
            tooltip: 'Jetzt ordnen',
            onPressed: onCleanNow,
            icon: const Icon(Icons.auto_fix_high_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _ComposerBottomBar extends StatelessWidget {
  final String selectedMood;
  final ValueChanged<String> onPickMood;
  final VoidCallback? onPrimary; // Fertig
  final VoidCallback onOverflow; // …

  const _ComposerBottomBar({
    required this.selectedMood,
    required this.onPickMood,
    required this.onPrimary,
    required this.onOverflow,
  });

  static String moodEmoji(String mood) {
    switch (mood) {
      case 'Glücklich':
        return '😊';
      case 'Ruhig':
        return '🧘';
      case 'Traurig':
        return '😔';
      case 'Gestresst':
        return '😱';
      case 'Wütend':
        return '😡';
      case 'Neutral':
      default:
        return '😐';
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = zs.ZenColors.deepSage;

    return Row(
      children: [
        // Mood-Pille
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => (context
                  .findAncestorStateOfType<_GedankenbuchEntryScreenState>())
              ?._showMoodPicker(context, selectedMood, onPickMood),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: green.withOpacity(.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: green.withOpacity(.28), width: 1.1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(moodEmoji(selectedMood),
                    style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  selectedMood,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: green,
                      ),
                )
              ],
            ),
          ),
        ),
        const Spacer(),

        // Primär: Fertig
        ElevatedButton.icon(
          icon: const Icon(Icons.check_rounded),
          label: const Text('Fertig'),
          onPressed: onPrimary,
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(zs.ZenRadii.m),
            ),
            elevation: 2,
          ),
        ),
        const SizedBox(width: 8),

        // Overflow
        IconButton(
          tooltip: 'Mehr',
          onPressed: onOverflow,
          icon: const Icon(Icons.more_horiz_rounded),
        ),
      ],
    );
  }
}

class _LengthMeter extends StatelessWidget {
  final int current;
  final int max;
  const _LengthMeter({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final p = (current / max).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: p,
        minHeight: 4,
        backgroundColor: Colors.black.withOpacity(.06),
        valueColor: AlwaysStoppedAnimation(
          zs.ZenColors.deepSage.withOpacity(.45),
        ),
      ),
    );
  }
}
