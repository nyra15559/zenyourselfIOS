// [PATCHED] lib/features/reflection/reflection_screen.dart — v6.8.1
// MERGE SIGNAL: Reflection v6.8.1 — Therapeutische Kernlinie, Worker-only Chips,
// Dual-Mood (🍃/🌿), UIEvent-Fix, History+Bridge via ReflectionController,
// Full-Session-Mode: Screen nutzt nur ReflectionController (kein direkter Worker-Call).
// + Voice-Flow v1: STT-Integration mit Partial-Transkription & fromVoice-Flag.
// v6.8.1a (2025-11-20):
//   • _inputReserve von 104 → 32 reduziert, damit neue Nachrichten wie bei WhatsApp
//     nah am unteren Rand bleiben und kein „leerer Bildschirm“ nach dem Senden entsteht.

library reflection_screen;

import 'dart:async';
import 'dart:math';

import '../../services/guidance/dtos.dart';

import 'package:flutter/services.dart'; // KeyEvent, Haptik
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Theme/Tokens
import '../../shared/zen_style.dart'
    hide ZenBackdrop, ZenGlassCard, ZenAppBar, ZenGlassInput;

// Zen-UI Widgets
import '../../shared/ui/zen_widgets.dart'
    show
        ZenBackdrop,
        ZenGlassCard,
        ZenAppBar,
        ZenGlassInput,
        PandaHeader,
        ZenPrimaryButton,
        ZenOutlineButton,
        ZenChipGhost;

// Panda-Moods (bestehender einfacher Picker bleibt importiert, Dual-Skala implementieren wir selbst)
import '../../models/panda_mood.dart';
import '../../widgets/panda_mood_picker.dart';

// Journal
import '../../models/journal_entry.dart' as jm;
import '../../providers/journal_entries_provider.dart';

// Services
import '../../services/guidance_service.dart';
import '../../services/speech_service.dart';
import '../../services/whisper_service.dart'; // STT-Engine (re-aktiviert)
import '../../services/core/api_service.dart'; // Mood speichern

// Memory-Layer
import '../../core/memory/memory_service.dart';

// Controller (History/Bridge/Typing Events)
import 'reflection_logic.dart' show ReflectionController, UIEvent, UIEventKind;

// CH Hotlines (Call-Buttons) + Launcher-Utilities
import '../../widgets/hotline_widget.dart'; // SwissHotlineCard / Section

// Parts (belassen)
part 'reflection_models.dart';
part 'reflection_widgets.dart';

// -----------------------------------------------------------------------------
// Config / Limits
// -----------------------------------------------------------------------------
const String kPandaHeaderAsset = 'assets/star_pa.png';

const int kMirrorMaxChars = 640; // weich, Worker steuert Länge
const int kQuestionMaxWords = 40; // weich, UI-Schutz

const int kInputSoftLimit = 500; // Anzeige im _InputBar
const int kInputHardLimit = 800;

// WICHTIG: kleinere Reserve, damit die letzte Bubble nah am Input bleibt
// und der Screen nach dem Senden nicht „leer“ wirkt.
const double _inputReserve = 32;

const Duration _animShort = Duration(milliseconds: 240);
const Duration _netTimeout = Duration(seconds: 18);

// ---------------- Optionaler Hook + Navigation --------------------------------
typedef AddToGedankenbuch = void Function(
  String text,
  String mood, {
  bool? isReflection,
  String? aiQuestion,
});

// ---------------- Interner UI-State ------------------------------------------
enum _ChipMode { starter, answer, none }

// ---- NEW: Dual-Mood Helper ---------------------------------------------------
class _DualMood {
  final int mental; // 0..4
  final int physical; // 0..4
  final String mentalLabel;
  final String physicalLabel;
  const _DualMood({
    required this.mental,
    required this.physical,
    required this.mentalLabel,
    required this.physicalLabel,
  });

  int get avg => ((mental + physical) / 2.0).round().clamp(0, 4);
  String get combinedLabel => 'Kopf: $mentalLabel / Körper: $physicalLabel';
}

// ---------------- Screen ------------------------------------------------------
class ReflectionScreen extends StatefulWidget {
  final AddToGedankenbuch? onAddToGedankenbuch;
  final String? initialUserText;

  /// Optional: Navigation-Callbacks fürs Post-Sheet (nur bei explizitem Tap).
  final VoidCallback? onOpenJournal;
  final VoidCallback? onGoHome;

  const ReflectionScreen({
    super.key,
    this.onAddToGedankenbuch,
    this.initialUserText,
    this.onOpenJournal,
    this.onGoHome,
  });

  @override
  State<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends State<ReflectionScreen>
    with SingleTickerProviderStateMixin {
  // Controllers / Focus / Animation
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _pageFocus = FocusNode();
  final ScrollController _listCtrl = ScrollController();

  // FIX: kein Lazy-Init → sauber in initState() erzeugen
  late final AnimationController _fadeSlideCtrl;

  // Speech
  final SpeechService _speech = SpeechService();
  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _finalSub;
  StreamSubscription<String>? _speechErrorSub;

  // STT-Context
  String _sttBaseText = '';
  bool _lastFromVoice = false;

  // Runden / Session
  final List<ReflectionRound> _rounds = <ReflectionRound>[];
  ReflectionRound? get _current => _rounds.isEmpty ? null : _rounds.last;

  // Flags
  bool loading = false;

  // Fehlermeldung aus GuidanceService (mikro-kurz, lokalisiert)
  String get _errorHint => GuidanceService.instance.errorHint;

  // Chips-State
  _ChipMode _chipMode = _ChipMode.starter;
  bool _textWasEmpty = true;

  // ---------------- NEW: Save→Mood Flow State --------------------------------
  bool _showConfirmBanner = false;
  String _confirmText =
      'Gespeichert. Deine Reflexion und Stimmung sind im Gedankenbuch.';

  // ---------------- [GUARD] Mood Prompt Guards -------------------------------
  bool _didPromptMood = false; // wurde für diese Runde schon aktiv gefragt?
  bool _isMoodOpen = false; // ist der Picker aktuell offen?

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  // ---------------- Memory Recall / Bridge -----------------------------------
  String? _bridgeText; // (aktuell unsichtbar; nur für Worker-Kontext)

  // Controller (History/Typing/Bridge)
  late final ReflectionController _ctrl;
  late final VoidCallback _ctrlListener;

  // Letzter gerenderter Panda-Vm-Stand (gegen Doppel-Rendering)
  String? _lastAssistantKey;

  // ---------------- Intro (dynamisch, einmalig) ------------------------------
  bool _hasShownIntro = false; // Guards: nur 1× pro Sitzung
  bool _showIntro = false;
  String _introText =
      'Schön, dass du wieder da bist. Schreib mir in 1–2 Sätzen, wie es dir heute geht.';

  // ---- NEW: pro Runde die Dual-Mood-Werte halten, ohne Models anzufassen ----
  final Map<String, _DualMood> _dualMoodsByRoundId = {};

  // Prefetch Recall (best effort, lokaler Fallback)
  Future<void> _prefetchRecall() async {
    try {
      final recall = await MemoryService.instance.recall(limit: 6);
      final text = _composeBridgeText(recall);
      if (!mounted) return;
      setState(() => _bridgeText = text);
    } catch (_) {}
  }

  /// Baut einen warmen, kurzen Brückensatz aus Recall-Items (nur intern).
  String? _composeBridgeText(dynamic recall) {
    if (recall == null) return null;
    final tokens = <String>[];

    void addToken(String? s) {
      final t = (s ?? '').trim();
      if (t.isEmpty) return;
      final key = t.toLowerCase();
      if (!tokens.any((x) => x.toLowerCase() == key)) tokens.add(t);
    }

    if (recall is List) {
      for (final it in recall) {
        if (it is String) {
          addToken(it);
          continue;
        }
        if (it is Map) {
          addToken((it['topic'] ?? it['tag'] ?? '').toString());
          final facets = (it['facets'] as List?)
                  ?.map((e) => e?.toString() ?? '')
                  .toList() ??
              const [];
          if (facets.isNotEmpty) addToken(facets.first);
          final line = (it['line'] ?? it['hint'] ?? '').toString();
          if (line.isNotEmpty && tokens.length < 2) addToken(line);
        }
      }
    }

    if (tokens.isEmpty) return null;
    final t1 = tokens[0];
    final t2 = tokens.length >= 2 ? tokens[1] : null;

    final body = t2 == null
        ? 'Ich erinnere mich an **$t1**.'
        : 'Ich erinnere mich an **$t1** und **$t2**.';
    return '$body Falls das heute noch mitschwingt – magst du dort anknüpfen?';
  }

  /// NEW: Bevorzugt Bridge-Text aus ReflectionController (History),
  /// fällt zurück auf lokalen Recall-Text (_bridgeText), wenn nichts da ist.
  String? get _effectiveBridgeText {
    String? fromCtrl;
    try {
      final dyn = _ctrl as dynamic;
      final val = dyn.bridgeText;
      if (val is String && val.trim().isNotEmpty) {
        fromCtrl = val.trim();
      }
    } catch (_) {
      // Kein bridgeText im Controller – still.
    }
    return fromCtrl ?? _bridgeText;
  }

  // ---------------- META: Builder --------------------------------------------
  // Hinweis: Meta wird hier aktuell nicht mehr an den Worker gesendet – der
  // Full-Session-Mode läuft komplett über ReflectionController. Diese Funktion
  // bleibt vorerst als Referenz bestehen.
  Map<String, dynamic> _buildMeta({
    String? userText,
    String? userAnswer,
    String? mode,
    bool isStart = false,
    bool isClosure = false,
    bool reopen = false, // derzeit ohne Verwendung
  }) {
    return {
      'flags': {
        'client_memory': true, // Merge-Signal / Handshake (immer an)
        if (reopen) 'reopen': true, // Closure-Recovery (Reserve)
      },
      'ui': {
        'screen': 'reflection',
        'version': '3.26.3',
        'platform': kIsWeb ? 'web' : 'flutter',
        'is_desktop': _isDesktop,
        'chip_mode': _chipMode.name,
        'answer_chips_min': 0, // keine lokalen Fallback-Chips
        'save_hint_after_rounds': 2,
      },
      'session': {
        'rounds': _rounds.length,
        'has_mood': _current?.hasMood ?? false,
        'allow_closure': _current?.allowClosure ?? false,
        'did_prompt_mood': _didPromptMood,
        'is_start': isStart,
        'is_closure': isClosure,
      },
      'memory': {
        // wichtig: Controller-Bridge (History) zuerst, dann Recall-Fallback
        'bridge': _effectiveBridgeText,
        'injected': {'present': false},
      },
      'input': {
        if (userText != null) 'user_text': userText,
        if (userAnswer != null) 'user_answer': userAnswer,
        if (mode != null) 'mode': mode,
        'initial_seed_present': (widget.initialUserText ?? '').trim().isNotEmpty,
      },
      'safety': {
        'region': 'CH',
        'hotlines_card': true,
      },
      'privacy': {
        'pii': false,
      },
      'tz': 'Europe/Zurich',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'telemetry': {
        'feature_flags': {
          'reflection.meta': true,
          'chips.worker_only': true,
          'memory.inject': true,
        },
      },
    };
  }

  void _attachSttEngine() {
    final bool simulate = kIsWeb || _isDesktop;
    _speech.attachWhisper(WhisperService(simulate: simulate));

    _speechErrorSub = _speech.error$.listen((msg) {
      if (!mounted) return;
      if ((msg).trim().isEmpty) return;
      _toast(msg);
    });
  }

  @override
  void initState() {
    super.initState();

    _fadeSlideCtrl = AnimationController(vsync: this, duration: _animShort)
      ..value = 1.0;

    _attachSttEngine();

    // Controller init + UIEvent-Anschluss
    _ctrl = ReflectionController();
    _ctrl.attachUiEventSink((UIEvent e) {
      if (!mounted) return;
      switch (e.kind) {
        case UIEventKind.appendUser:
          // NEU: User-Bubble kommt vollständig aus der Logic.
          final text = e.text?.trim() ?? '';
          if (text.isEmpty) break;

          setState(() {
            if (_rounds.isEmpty || !(_rounds.last.hasPendingQuestion)) {
              // Neue Runde starten
              final round = ReflectionRound(
                id: _makeId(),
                ts: DateTime.now(),
                mode: _lastFromVoice ? 'voice' : 'text',
                userInput: text,
                allowClosure: false,
              );
              _rounds.add(round);
            } else {
              // Antwort auf bestehende Panda-Frage
              final round = _rounds.last;
              if (round.steps.isNotEmpty) {
                round.steps.last.answer = text;
              } else {
                round.userInput = text;
              }
            }
            _chipMode = _ChipMode.none;
          });
          _scrollToBottom();
          break;
        case UIEventKind.insertTypingPlaceholder:
          setState(() => loading = true);
          _scrollToBottom();
          break;
        case UIEventKind.removeTypingPlaceholder:
          setState(() => loading = false);
          break;
        case UIEventKind.scrollToEnd:
          _scrollToBottom();
          break;
        case UIEventKind.openDualMoodPicker:
          // Öffnet den Dual-Mood-Picker deterministisch (ohne Closure-Phase),
          // speichert lokal bei 🍃/🌿 und postet an den Server nur bei 🌿.
          final r = _current;
          if (r == null || r.hasMood) break;
          _promptDualMoodOnce(
            context,
            title: 'Wie fühlst du dich gerade? (Kopf & Körper)',
          ).then((chosen) async {
            if (!mounted || chosen == null) return;
            setState(() {
              r.moodScore = chosen.avg;
              r.moodLabel = chosen.combinedLabel;
              _dualMoodsByRoundId[r.id] = chosen;
              _didPromptMood = true;
            });

            final ts = DateTime.now().toUtc();

            // Lokal speichern (🍃/🌿)
            unawaited(() async {
              try {
                if (_isLocalStoreAllowed()) {
                  final dyn = MemoryService.instance as dynamic;
                  await dyn.saveMoodEntry?.call(
                    ts,
                    chosen.mental,
                    chosen.physical,
                  );
                }
              } catch (_) {}
            }());

            // Server posten (nur 🌿)
            if (_isSharingEnabled()) {
              try {
                await ApiService.instance.mood(
                  entryId: r.id,
                  icon: chosen.avg,
                  note: null,
                );
              } catch (_) {}
            }

            // Controller: Closure-Turn auslösen (Full-Session-Mode)
            unawaited(
              _ctrl.completeClosureWithMood(
                chosen.mental,
                chosen.physical,
                when: ts,
              ),
            );
          });
          break;
      }
    });
    _ctrlListener = () {
      if (!mounted) return;
      _syncFromControllerVm();
    };

    _ctrl.addListener(_ctrlListener);
    _ctrl.wireSessionFromContext(context);

    // Identity warm-up (best effort)
    unawaited(() async {
      try {
        await (MemoryService.instance as dynamic).loadGreetingName?.call();
      } catch (_) {}
    }());

    // Memory-Recall (Fallback)
    unawaited(_prefetchRecall());
    // Controller-Bridge (History-basiert)
    unawaited(_ctrl.prefetchBridge());

    // Live-Transkript (partial) → direkt in Input einfügen
    _partialSub = _speech.partial$.listen((t) {
      if (!mounted) return;
      final partial = t.trim();
      if (partial.isEmpty) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final base = _sttBaseText.trim();
        final joined =
            base.isEmpty ? partial : ('$base\n$partial').trimRight();

        _controller
          ..text = joined
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: joined.length),
          );
        _maybeHideStarterChipsOnTyping();
      });
    });

    // Live-Transkript (final) → Input stabilisieren & fromVoice setzen
    _finalSub = _speech.transcript$.listen((t) async {
      if (!mounted) return;
      final spoken = t.trim();
      if (spoken.isEmpty) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final base = _sttBaseText.trim();
        final joined =
            base.isEmpty ? spoken : ('$base\n$spoken').trimRight();

        _controller
          ..text = joined
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: joined.length),
          );
        _maybeHideStarterChipsOnTyping();
        _focusInput();

        _lastFromVoice = true;
        _sttBaseText = joined;
      });
    });

    _controller.addListener(_maybeHideStarterChipsOnTyping);

    // S3.1: Intro *einmalig* nach erstem Frame prüfen
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowIntro());

    final seed = (widget.initialUserText ?? '').trim();
    if (seed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Full-Session-Start komplett über ReflectionController
        _ctrl.sendUser(seed, fromVoice: false, context: context);
      });
    }
  }

  /// S3.1 — entscheidet, ob die Intro-Bubble lokal einmalig gezeigt wird
  Future<void> _maybeShowIntro() async {
    if (!mounted) return;
    if (_hasShownIntro) return; // nur 1× pro Sitzung
    if (_rounds.isNotEmpty) return; // sobald Runde existiert → kein Intro
    if ((widget.initialUserText ?? '').trim().isNotEmpty) return; // Seed → Start

    String? name;
    bool consent = false;
    try {
      final dyn = MemoryService.instance as dynamic;
      // bevorzugt: freundlicher Anzeigename, nur wenn Nutzer zugestimmt hat
      name = await (dyn.loadGreetingName?.call());
      consent = (dyn.shareEnabled == true) || (dyn.memoryActive == true);
    } catch (_) {
      // still
    }

    String text;
    if (consent && (name != null) && name.toString().trim().isNotEmpty) {
      text =
          'Hey, ${name.toString().trim()}, schön, dass du wieder da bist. Schreib mir in 1–2 Sätzen, wie es dir heute geht.';
    } else {
      text =
          'Schön, dass du wieder da bist. Schreib mir in 1–2 Sätzen, wie es dir heute geht.';
    }

    if (!mounted) return;
    setState(() {
      _introText = text;
      _showIntro = true;
      _hasShownIntro = true;
    });
  }

  void _maybeHideStarterChipsOnTyping() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (_chipMode == _ChipMode.starter && hasText && _textWasEmpty) {
      setState(() => _chipMode = _ChipMode.none);
    }
    _textWasEmpty = !hasText;
  }

  @override
  void dispose() {
    _partialSub?.cancel();
    _finalSub?.cancel();
    _speechErrorSub?.cancel();
    _speech.dispose();
    _controller.dispose();
    _inputFocus.dispose();
    _pageFocus.dispose();
    _listCtrl.dispose();
    _fadeSlideCtrl.dispose();

    _ctrl.removeListener(_ctrlListener);
    _ctrl.detachUiEventSink();
    _ctrl.dispose();

    super.dispose();
  }

  // ---------------- Keyboard Shortcuts ---------------------------------------
  KeyEventResult _handleKey(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;

    if (e.logicalKey == LogicalKeyboardKey.escape && _speech.isRecording) {
      _toggleRecording();
      return KeyEventResult.handled;
    }

    final bool isEnter = e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter;
    final bool withCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final bool withShift = HardwareKeyboard.instance.isShiftPressed;

    if (withCtrlOrCmd && isEnter && !loading) {
      _send();
      return KeyEventResult.handled;
    }

    if (isEnter && !withShift && !loading) {
      _send();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------- Voice: Start/Stop ----------------------------------------

  Future<void> _toggleRecording() async {
    try {
      if (_speech.isRecording) {
        await _speech.stop();
        if (!mounted) return;
        _focusInput();
      } else {
        HapticFeedback.selectionClick();
        FocusScope.of(context).unfocus();
        _sttBaseText = _controller.text;
        _lastFromVoice = false;
        await _speech.start(locale: 'de-DE');
      }
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      _toast('Mikrofon nicht verfügbar. Bitte Berechtigung erlauben.');
    }
  }

  // ---------------- Sending (Text) -------------------------------------------

  Future<void> _send() async {
    if (loading) return;

    var text = _controller.text.trim();
    if (text.isEmpty) return;

    if (text.length > kInputHardLimit) {
      text = text.substring(0, kInputHardLimit);
      _toast('Dein Text wurde auf $kInputHardLimit Zeichen gekürzt.');
    }

    // Namenslernen (best-effort, lokal)
    unawaited(MemoryService.instance.learnNameFromText(text));

    setState(() {
      _chipMode = _ChipMode.none;
    });

    // Full-Session-Start/Next komplett über ReflectionController
    _ctrl.sendUser(
      text,
      fromVoice: _lastFromVoice,
      context: context,
    );

    _lastFromVoice = false;
    _controller.clear();
    _focusInput();
    HapticFeedback.lightImpact();
  }

  // ---------------- Session-Coercion (Legacy, ungenutzt im neuen Flow) -------
  ReflectionSession _coerceSession(dynamic turn) {
    try {
      if (turn is ReflectionTurn) return turn.session;
    } catch (_) {}

    dynamic s;
    if (turn is Map) {
      s = turn['session'];
    } else {
      try {
        final v = (turn as dynamic).toJson?.call();
        if (v is Map) s = v['session'];
      } catch (_) {}
      if (s == null) {
        try {
          s = (turn as dynamic)['session'];
        } catch (_) {}
      }
    }

    if (s is ReflectionSession) return s;

    if (s is Map) {
      final id = (s['id'] ?? s['thread_id'] ?? '').toString();
      final turnIdx = (s['turn'] is num)
          ? (s['turn'] as num).toInt()
          : (s['turn_index'] is num)
              ? (s['turn_index'] as num).toInt()
              : 0;
      final maxTurns =
          (s['max_turns'] is num) ? (s['max_turns'] as num).toInt() : 3;

      return ReflectionSession(
        threadId: id.isNotEmpty
            ? id
            : 'local_${DateTime.now().millisecondsSinceEpoch}',
        turnIndex: turnIdx,
        maxTurns: maxTurns,
      );
    }

    return ReflectionSession(
      threadId: 'local_${DateTime.now().millisecondsSinceEpoch}',
      turnIndex: 0,
      maxTurns: 3,
    );
  }

  // ---------------- Turn → Step (Legacy, für Fallback) -----------------------
  _PandaStep _buildStepFromTurn(dynamic t) {
    final bool isClosure = _safeBool(t, ['mood', 'prompt']) ||
        _safeBool(t, ['flow', 'mood_prompt']) ||
        _safeBool(t, ['flow', 'recommend_end']);

    final mirrorRaw = _coerceMirror(t).trim();
    final questionRaw = _coerceQuestion(t);
    // helperSuggestion wird nicht mehr UI-seitig verwendet
    final helperSuggestion = _coerceHelperSuggestion(t);

    final level = _safeString(t, ['risk_level']).toLowerCase();
    final risk = _safeBool(t, ['risk']) || level == 'high' || level == 'mild';

    // Nur Worker-answer_helpers (max 3). Keine lokalen Fallback-Chips.
    final helpers = isClosure
        ? <String>[]
        : _safeStringList(t, ['answer_helpers']).take(3).toList();

    final talk = _safeStringList(t, ['talk']).take(2).toList();

    final bool isFirstEverStep = !_rounds.any((rr) => rr.steps.isNotEmpty);
    final effectiveMirror = mirrorRaw.isNotEmpty
        ? mirrorRaw
        : (isFirstEverStep ? 'Ich höre dich. Ich bleibe bei dir.' : '');

    final q = isClosure ? '' : questionRaw;

    return _PandaStep(
      mirror: _capChars(effectiveMirror, kMirrorMaxChars),
      question: _limitWords((q.isNotEmpty ? q : ''), kQuestionMaxWords),
      talkLines: talk,
      risk: risk,
      followups: helpers,
      helperSuggestion: helperSuggestion.isNotEmpty ? helperSuggestion : null,
    );
  }

  // ---------------- SAVE→MOOD: deterministischer Dual-Flow -------------------

  bool _isSharingEnabled() {
    try {
      final dyn = MemoryService.instance as dynamic;
      return dyn.shareEnabled == true;
    } catch (_) {
      return false;
    }
  }

  // NEW: Gate für lokales Speichern (🍃/🌿), 🕊️ → false
  bool _isLocalStoreAllowed() {
    try {
      final dyn = MemoryService.instance as dynamic;
      // Voll (🌿) impliziert lokal okay:
      if (dyn.shareEnabled == true) return true;
      // Explizite lokale Schalter (verschiedene Implementationen abdecken):
      if (dyn.localEnabled == true) return true;
      if (dyn.memoryActive == true) return true;
      if (dyn.storeEnabled == true) return true;
      final level = (dyn.level is num)
          ? (dyn.level as num).toInt()
          : (dyn.memoryLevel is num)
              ? (dyn.memoryLevel as num).toInt()
              : null;
      if (level != null && level >= 1) return true; // 🍃/🌿
    } catch (_) {}
    return false; // 🕊️
  }

  Future<void> _onPressSaveRound(ReflectionRound r) async {
    if (r.entryId != null) {
      _toast('Bereits gespeichert.');
      return;
    }
    if (!r.answered) {
      _toast('Bitte zuerst deine Antwort schreiben.');
      return;
    }

    // WICHTIG:
    // KEINE Mood-Abfrage im Save-Flow. Mood nur, wenn der Worker flow.mood_prompt signalisiert.
    await _saveRoundCore(r);
  }

  Future<void> _saveRoundCore(ReflectionRound r) async {
    final String lastAns = r.steps
        .map((e) => (e.answer ?? '').trim())
        .where((s) => s.isNotEmpty)
        .fold<String>('', (prev, cur) => cur.isNotEmpty ? cur : prev);

    final String textForCard =
        lastAns.isNotEmpty ? lastAns : r.userInput.trim();

    final String entryId = r.id;
    final DateTime ts = r.ts.toUtcDateTime();

    final String title =
        _autoTitleForRound(r, fallback: _autoSessionName(r.userInput));

    // Zusätzliche Mood-Tags (Dual)
    final dual = _dualMoodsByRoundId[r.id];
    final tags = <String>[
      'reflection',
      if ((r.moodLabel ?? '').trim().isNotEmpty) 'mood:${r.moodLabel!.trim()}',
      if (r.moodScore != null) 'moodScore:${r.moodScore}',
      if (dual != null) ...[
        'moodMental:${dual.mental}',
        'moodPhysical:${dual.physical}',
      ],
      'input:${r.mode}',
    ];

    final Map<String, dynamic> entryMap = {
      'id': entryId,
      'kind': 'reflection',
      'createdAt': ts.toIso8601String(),
      'title': title,
      'thoughtText': r.userInput.trim(),
      'aiQuestion': r.steps.isNotEmpty ? r.steps.first.question.trim() : null,
      'userAnswer': lastAns.isNotEmpty ? lastAns : null,
      'hidden': false,
      'tags': tags,
      'sourceRef': 'reflection|session:',
    };

    final entry = jm.JournalEntry.fromMap(entryMap);

    final prov = context.read<JournalEntriesProvider>();
    final List<jm.JournalEntry> existing =
        List<jm.JournalEntry>.from(prov.entries);
    existing.add(entry);
    prov.replaceAll(existing);

    if (!mounted) return;
    setState(() => r.entryId = entryId);
    widget.onAddToGedankenbuch?.call(
      textForCard,
      (r.moodLabel ?? 'Neutral').trim(),
      isReflection: true,
      aiQuestion: r.steps.isNotEmpty ? r.steps.first.question : null,
    );

    _showCalmConfirm(
      'Gespeichert. Deine Reflexion und Stimmung sind im Gedankenbuch.',
    );

    _appendThankYouAfterSave(r);
  }

  // ---------------- Delete ----------------------------------------------------
  Future<void> _deleteRound(ReflectionRound r) async {
    setState(() {
      _rounds.removeWhere((x) => x.id == r.id);
    });
    setState(() {
      _chipMode = _rounds.isEmpty ? _ChipMode.starter : _ChipMode.none;
    });
    _toast('Gelöscht.');
  }

  // ---------------- Abschluss/Mood-Einleitung (Legacy) -----------------------
  Future<void> _requestClosureFromWorker({
    required ReflectionRound round,
    required String userAnswer,
  }) async {
    // Im neuen Full-Session-Mode läuft Closure über ReflectionController.completeClosureWithMood.
    // Diese Funktion bleibt als Fallback bestehen, wird aber aktuell nicht verwendet.
    if (!mounted) return;
  }

  // --- Coercion helpers -------------------------------------------------------
  String _coerceMirror(dynamic t) {
    final paths = <List<String>>[
      ['mirror'],
      ['reply'],
      ['text'],
      ['closure', 'text'],
      ['mood_intro', 'text'],
      ['primary', 'mirror'],
      ['primary', 'reply'],
      ['primary', 'text'],
      ['flow', 'mirror'],
      ['flow', 'reply'],
      ['flow', 'text'],
      ['reflection', 'mirror'],
      ['turn', 'mirror'],
    ];
    for (final p in paths) {
      final s = _safeString(t, p).trim();
      if (s.isNotEmpty) {
        final cleaned = _stripInstructionHints(s);
        if (cleaned.endsWith('?')) continue;
        return cleaned;
      }
    }
    return '';
  }

  String _stripInstructionHints(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final patterns = <RegExp>[
      RegExp(r'^\s*Unten\s+findest\s+du\s+Antwort[-\s]?Chips.*$', caseSensitive: false),
      RegExp(r'^\s*Unter\s+dem\s+Eingabefeld\s+findest\s+du\s+Antwort.*$', caseSensitive: false),
      RegExp(r'^\s*Wähle\s+einen\s+Antwort[-\s]?Chip.*$', caseSensitive: false),
      RegExp(r'^\s*You\s+can\s+use\s+the\s+answer\s+chips.*$', caseSensitive: false),
      RegExp(r"^\s*Below\s+you'll\s+find\s+answer\s+chips.*$", caseSensitive: false),
    ];

    bool matchesAny(String s) => patterns.any((p) => p.hasMatch(s));
    final kept = <String>[];
    for (final line in lines) {
      if (!matchesAny(line)) kept.add(line);
    }
    final joined = kept.join('\n').trim();
    return joined.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  String _coerceQuestion(dynamic t) {
    var q = _safeString(t, ['question']);
    if (q.isNotEmpty) return q;

    List<String> tryLists(dynamic obj) => [
          ..._safeStringList(obj, ['questions']),
        ];

    final fromTop = tryLists(t);
    if (fromTop.isNotEmpty) return fromTop.first;

    final primary = _extract(t, 'primary');
    if (primary != null) {
      q = _safeString(primary, ['question']);
      if (q.isNotEmpty) return q;
      final fromPrimary = tryLists(primary);
      if (fromPrimary.isNotEmpty) return fromPrimary.first;
    }

    final flow = _extract(t, 'flow');
    if (flow != null) {
      q = _safeString(flow, ['question']);
      if (q.isNotEmpty) return q;
      final fromFlow = tryLists(flow);
      if (fromFlow.isNotEmpty) return fromFlow.first;
    }

    return '';
  }

  String _coerceHelperSuggestion(dynamic t) {
    String pick(dynamic obj) {
      final s1 = _safeString(obj, ['helper_suggestion']).trim();
      if (s1.isNotEmpty) return s1;
      final s2 = _safeString(obj, ['helperSuggestion']).trim();
      return s2;
    }

    final top = pick(t);
    if (top.isNotEmpty) return top;

    final primary = _extract(t, 'primary');
    if (primary != null) {
      final p = pick(primary);
      if (p.isNotEmpty) return p;
    }

    final flow = _extract(t, 'flow');
    if (flow != null) {
      final f = pick(flow);
      if (f.isNotEmpty) return f;
    }

    return '';
  }

  // ---------------- Utils -----------------------------------------------------

  bool _talkContainsLengthHint(_PandaStep? step) {
    if (step == null) return false;
    final lines = step.talkLines.map((s) => s.toLowerCase()).toList();
    final patterns = <RegExp>[
      RegExp(r'\b1\s*[–-]?\s*2\s*sätz', caseSensitive: false),
      RegExp(r'\bein\s+1\s*(?:bis|–|-)\s*2\s*sätz', caseSensitive: false),
      RegExp(r'\bkurz[e]?\s*antwort\b', caseSensitive: false),
    ];
    return lines.any((l) => patterns.any((p) => p.hasMatch(l)));
  }

  String _autoTitleForRound(ReflectionRound r, {required String fallback}) {
    for (final s in r.steps) {
      final a = (s.answer ?? '').trim();
      if (a.isNotEmpty) return _firstWords(a, 10);
    }
    if (r.steps.isNotEmpty && r.steps.first.question.trim().isNotEmpty) {
      return _firstWords(r.steps.first.question.trim(), 12);
    }
    return fallback;
  }

  String _autoSessionName(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'Reflexion';
    const max = 36;
    return clean.length <= max
        ? clean
        : '${clean.substring(0, max).trimRight()}…';
  }

  String _firstWords(String s, int n) {
    final words =
        s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= n) return s.trim();
    return '${words.take(n).join(' ')}…';
  }

  String _capChars(String s, int maxChars) {
    final t = s.trim();
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars).trimRight()}…';
  }

  String _limitWords(String input, int maxWords) {
    final words =
        input.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= maxWords) return input.trim();
    return '${words.take(maxWords).join(' ')}…';
  }

  String _makeId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = Random().nextInt(0xFFFF);
    return 'j_${now}_$r';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listCtrl.hasClients) return;
      try {
        _listCtrl.animateTo(
          _listCtrl.position.maxScrollExtent,
          duration: _animShort,
          curve: Curves.easeOut,
        );
      } catch (_) {}
    });
  }

  void _focusInput() => FocusScope.of(context).requestFocus(_inputFocus);

  void _showRetryError(String msg, VoidCallback onRetry) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  color: Colors.black.withValues(alpha: .65)),
              const SizedBox(height: 10),
              Text(
                (msg.isNotEmpty ? msg : 'Verbindung gerade schwierig.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ZenOutlineButton(
                    label: 'Später',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  ZenPrimaryButton(
                    label: 'Nochmal senden',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onRetry();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    debugPrint('[Reflection] $msg');
    HapticFeedback.selectionClick();
  }

  void _showCalmConfirm(String text) async {
    setState(() {
      _confirmText = text;
      _showConfirmBanner = true;
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _showConfirmBanner = false);
  }

  // ---------------- Build -----------------------------------------------------
  String get _headerTitle => 'Ordne deine Gedanken';
  String get _headerSubtitle => '';

  @override
  Widget build(BuildContext context) {
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final size = MediaQuery.of(context).size;
    final double w = size.width;
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final double cardMaxW = _cardMaxWidthFor(w);

    final r = _current;

    final bool closureActive =
        r != null && r.allowClosure && !(r.hasPendingQuestion) && !(r.hasMood);

    final bool showAnswerHint = r != null &&
        r.hasPendingQuestion &&
        !closureActive &&
        !_talkContainsLengthHint(r.steps.isNotEmpty ? r.steps.last : null);

    final bool lastIsTyping = r != null && loading;

    final bool showStarter = _rounds.isEmpty && _chipMode == _ChipMode.starter;

    final bool showAnswerChips = !closureActive &&
        (r != null &&
            r.steps.isNotEmpty &&
            r.steps.last.followups.isNotEmpty) &&
        _chipMode == _ChipMode.answer;

    final List<String> rawTemplates = showAnswerChips
        ? r.steps.last.followups
        : (showStarter ? _starterChips() : const <String>[]);

    final lastQ = r?.steps.isNotEmpty == true ? r!.steps.last.question : '';
    final lastA =
        r?.steps.isNotEmpty == true ? (r!.steps.last.answer ?? '') : '';
    final List<String> answerTemplatesRefined =
        _refineChips(rawTemplates, question: lastQ, lastAnswer: lastA);

    // Keine lokalen Fallback-Chips generieren (Worker-only).
    final List<String> answerTemplates = answerTemplatesRefined;

    // Save-Hinweis soll explizit erst NACH 2 Runden erscheinen
    final bool canPermanentSave =
        r != null && r.answered && (r.entryId == null);
    final bool showSaveHint = canPermanentSave && _rounds.length >= 2;

    // S3.1: Intro nur zeigen, wenn explizit gesetzt UND noch keine Runde existiert
    final bool showIntroNow = _showIntro && _rounds.isEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: KeyboardListener(
        focusNode: _pageFocus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: const ZenAppBar(title: null, showBack: true),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                // Backdrop
                const Positioned.fill(
                  child: ZenBackdrop(
                    asset: 'assets/flusspanda.png',
                    alignment: Alignment.centerRight,
                    glow: .36,
                    vignette: .12,
                    saturation: .94,
                    wash: .08,
                    enableHaze: true,
                    hazeStrength: .16,
                    milk: .10,
                  ),
                ),

                // ---- Scrollarea
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            controller: _listCtrl,
                            physics: const BouncingScrollPhysics(),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              0,
                              0,
                              0,
                              12 + _inputReserve + bottomInset,
                            ),
                            children: [
                              // Header
                              _ReflectionHeader(
                                title: _headerTitle,
                                subtitle: _headerSubtitle,
                                pandaAsset: kPandaHeaderAsset,
                                pandaSize: w < 470 ? 100 : 126,
                              ),
                              const SizedBox(height: 10),

                              // Intro (dynamisch, lokal, einmalig)
                              if (showIntroNow)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          BoxConstraints(maxWidth: cardMaxW),
                                      child: ZenGlassCard(
                                        padding: const EdgeInsets.fromLTRB(
                                            14, 12, 14, 12),
                                        child: Text(
                                          _introText,
                                          style: const TextStyle(height: 1.35),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // Verlauf (mit CH-Risk-Actions unter der Runde)
                              for (int index = 0;
                                  index < _rounds.length;
                                  index++)
                                KeyedSubtree(
                                  key: ValueKey(_rounds[index].id),
                                  child: Builder(
                                    builder: (_) {
                                      final isLast =
                                          index == _rounds.length - 1;
                                      final isTyping = isLast && lastIsTyping;
                                      final hasRisk =
                                          _rounds[index].steps.isNotEmpty &&
                                              _rounds[index].steps.last.risk;

                                      final thread = _RoundThread(
                                        maxWidth: cardMaxW,
                                        round: _rounds[index],
                                        isLast: isLast,
                                        isTyping: isTyping,
                                        onSave: _rounds[index].answered
                                            ? () => _onPressSaveRound(
                                                _rounds[index])
                                            : null,
                                        onDelete: _rounds[index].entryId != null
                                            ? () => _deleteRound(_rounds[index])
                                            : null,
                                        onSelectMood: (score, label) async {
                                          // Dieser Callback wird bei der *einfachen* Mood-Auswahl genutzt.
                                          // Wir mappen ihn auf unseren Dual-Flow: set + save.
                                          final dual = _DualMood(
                                            mental: score,
                                            physical: score,
                                            mentalLabel: label,
                                            physicalLabel: label,
                                          );
                                          _dualMoodsByRoundId[_rounds[index].id] =
                                              dual;
                                          setState(() {
                                            _rounds[index].moodScore =
                                                dual.avg;
                                            _rounds[index].moodLabel =
                                                dual.combinedLabel;
                                            _didPromptMood = true;
                                          });

                                          // **Lokal speichern** nur wenn 🍃/🌿 aktiv
                                          unawaited(() async {
                                            try {
                                              if (_isLocalStoreAllowed()) {
                                                final dyn =
                                                    MemoryService.instance
                                                        as dynamic;
                                                await dyn.saveMoodEntry?.call(
                                                  // v6.7.7: DateTime statt ISO-String
                                                  DateTime.now().toUtc(),
                                                  dual.mental,
                                                  dual.physical,
                                                );
                                              }
                                            } catch (_) {}
                                          }());

                                          await _saveRoundCore(
                                              _rounds[index]);
                                        },
                                        safetyText: hasRisk
                                            ? _emergencyHint(context)
                                            : null,
                                      );

                                      final threadWithRisk = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          thread,
                                          if (hasRisk) ...[
                                            const SizedBox(height: 6),
                                            Center(
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                    maxWidth: cardMaxW),
                                                child: const SwissHotlineCard(),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );

                                      if (!isLast) {
                                        return threadWithRisk;
                                      }

                                      return FadeTransition(
                                        opacity: _fadeSlideCtrl
                                            .drive(Tween(begin: 0.0, end: 1.0)),
                                        child: SlideTransition(
                                          position: _fadeSlideCtrl.drive(
                                            Tween(
                                              begin: const Offset(-0.03, 0),
                                              end: Offset.zero,
                                            ),
                                          ),
                                          child: threadWithRisk,
                                        ),
                                      );
                                    },
                                  ),
                                ),

                              // Hinweis – nur wenn Frage offen & kein Abschluss
                              AnimatedSize(
                                duration: _animShort,
                                curve: Curves.easeOut,
                                child: AnimatedOpacity(
                                  duration: _animShort,
                                  opacity: showAnswerHint ? 1 : 0,
                                  child: showAnswerHint
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                              top: 4, bottom: 8),
                                          child: Center(
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                  maxWidth: cardMaxW),
                                              child: const _ReflectionHint(),
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),

                              // Save-Hinweis
                              AnimatedSize(
                                duration: _animShort,
                                curve: Curves.easeOut,
                                child: AnimatedOpacity(
                                  duration: _animShort,
                                  opacity: showSaveHint ? 1 : 0,
                                  child: showSaveHint
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                              top: 0, bottom: 8),
                                          child: Center(
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                  maxWidth: cardMaxW),
                                              child: const Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  ExcludeSemantics(
                                                    child: Icon(
                                                      Icons
                                                          .info_outline_rounded,
                                                      size: 16,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'Lies die Frage kurz, antworte in 1–2 Sätzen, speichere bitte deine Session …',
                                                      style: TextStyle(
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),

                              // (Consent-Hint wurde bewusst entfernt)

                              // CHIPS (Starter/Antwort) – nicht in Mood-Phase
                              AnimatedSize(
                                duration: _animShort,
                                curve: Curves.easeOut,
                                child: (showStarter ||
                                        (!closureActive &&
                                            _chipMode == _ChipMode.answer &&
                                            answerTemplates.isNotEmpty))
                                    ? Center(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                              maxWidth: cardMaxW),
                                          child: AnimatedSwitcher(
                                            duration: _animShort,
                                            switchInCurve: Curves.easeOut,
                                            switchOutCurve: Curves.easeIn,
                                            child: Padding(
                                              key: ValueKey(
                                                showStarter
                                                    ? 'starter'
                                                    : 'answers',
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 6),
                                              child: Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  for (final s
                                                      in answerTemplates)
                                                    ZenChipGhost(
                                                      label: s,
                                                      onPressed: () =>
                                                          _onTapChip(
                                                        s,
                                                        isAnswerTemplate:
                                                            !showStarter,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              // Permanenter Footer-Disclaimer
                              Padding(
                                padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        BoxConstraints(maxWidth: cardMaxW),
                                    child: Opacity(
                                      opacity: 0.72,
                                      child: Text(
                                        'Dies ist keine Therapie, sondern eine mentale Begleitungs-App.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              height: 1.25,
                                              color: Colors.black
                                                  .withValues(alpha: 0.72),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ---------- Permanente Save-Bar (immer sichtbar) ----------
                        SafeArea(
                          top: false,
                          bottom: false,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: cardMaxW),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ZenPrimaryButton(
                                        label: 'Speichern',
                                        onPressed: canPermanentSave && !loading
                                            ? () => _onPressSaveRound(_current!)
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Bottom-Input (fix)
                        SafeArea(
                          top: false,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: cardMaxW),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                                child: _InputBar(
                                  controller: _controller,
                                  focusNode: _inputFocus,
                                  hint: 'Antworte in 1–2 Sätzen.',
                                  onSend: loading ? null : _send,
                                  canSend: !loading,
                                  onMicTap: _toggleRecording,
                                  isRecording: _speech.isRecording,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Calm Confirm Banner (milchig, gläsern)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
                  child: IgnorePointer(
                    ignoring: true,
                    child: AnimatedSwitcher(
                      duration: _animShort,
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _showConfirmBanner
                          ? Center(
                              child: _CalmGlassBanner(text: _confirmText),
                            )
                          : const SizedBox.shrink(),
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

  // ---------------- Helpers: Chips / Width / Safety --------------------------
  List<String> _starterChips() => const [
        'Heute war ein stressiger Tag … ',
        'Ich hänge bei einem Thema fest … ',
        'Etwas beschäftigt mich seit Tagen … ',
      ];

  final _kBannedStarters = <RegExp>[
    RegExp(r'^\s*mir ist wichtig\b', caseSensitive: false),
    RegExp(r'^\s*im kern geht es\b', caseSensitive: false),
    RegExp(r'^\s*ein(?:er)?\s+kleiner\s+nächster\s+schritt\b', caseSensitive: false),
    RegExp(r'^\s*es fühlt sich an wie\b', caseSensitive: false),
  ];

  String _ensureEllipsisSuffix(String s) {
    var t = s
        .trim()
        .replaceAll(RegExp(r'[?。？？]+$'), '')
        .replaceAll(RegExp(r'\.\s*$'), '');
    if (t.endsWith('… ')) return t;
    if (t.endsWith('…')) return '$t ';
    return '$t … ';
  }

  List<String> _refineChips(
    List<String> chips, {
    required String question,
    String lastAnswer = '',
  }) {
    final qTokens = question
        .toLowerCase()
        .split(RegExp(r'[^a-zäöüß0-9]+'))
        .where((w) => w.length >= 3)
        .toSet();
    final aTokens = lastAnswer
        .toLowerCase()
        .split(RegExp(r'[^a-zäöüß0-9]+'))
        .where((w) => w.length >= 3)
        .toSet();
    final anchors = {...qTokens, ...aTokens};

    bool looksInAxis(String t) {
      if (anchors.isEmpty) return true;
      final toks = t
          .toLowerCase()
          .split(RegExp(r'[^a-zäöüß0-9]+'))
          .where((w) => w.length >= 3);
      return toks.any(anchors.contains);
    }

    final seen = <String>{};
    final kept = <String>[];

    for (var raw in chips) {
      var s = raw.trim();
      if (s.isEmpty) continue;
      if (_kBannedStarters.any((re) => re.hasMatch(s))) continue;
      if (!looksInAxis(s)) continue;
      final key = s.toLowerCase();
      if (!seen.add(key)) continue;
      kept.add(_ensureEllipsisSuffix(s));
      if (kept.length >= 3) break;
    }

    return kept;
  }

  void _onTapChip(String text, {required bool isAnswerTemplate}) {
    final original = text;
    final endsWithEllipsisSpace = RegExp(r'…\s$').hasMatch(original);
    var t = original.replaceAll(RegExp(r'[?？]+$'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (endsWithEllipsisSpace || t.endsWith('…')) t = '$t ';
    if (!endsWithEllipsisSpace && !t.endsWith('… ') && t.endsWith('…')) {
      t = '$t ';
    }

    final cur = _controller.text;
    final needsSpace = cur.isNotEmpty && !RegExp(r'\s$').hasMatch(cur);
    final next = (needsSpace ? '$cur ' : cur) + t;

    _controller
      ..text = next
      ..selection =
          TextSelection.fromPosition(TextPosition(offset: next.length));
    _focusInput();
    if (isAnswerTemplate) setState(() => _chipMode = _ChipMode.answer);
    if (_rounds.isEmpty) setState(() => _chipMode = _ChipMode.none);
  }

  double _cardMaxWidthFor(double w) {
    if (w < 420) return w - 24;
    if (w < 720) return min<double>(w - 24, 600);
    return 680;
  }

  String _emergencyHint(BuildContext context) {
    return 'Wenn es sich akut belastend anfühlt: In Notfällen rufe sofort 144 (Rettungsdienst) oder 112.';
  }

  // ---------------- JSON-safe helpers ----------------------------------------
  dynamic _extract(dynamic obj, String key) {
    if (obj == null) return null;
    if (obj is Map) return obj[key];
    try {
      final j = (obj as dynamic).toJson?.call();
      if (j is Map) return j[key];
    } catch (_) {}
    try {
      return (obj as dynamic)[key];
    } catch (_) {}
    return null;
  }

  dynamic _getPath(dynamic obj, List<String> path) {
    dynamic cur = obj;
    for (final k in path) {
      cur = _extract(cur, k);
      if (cur == null) break;
    }
    return cur;
  }

  String _safeString(dynamic obj, List<String> path) {
    final v = _getPath(obj, path);
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  bool _safeBool(dynamic obj, List<String> path) {
    final v = _getPath(obj, path);
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y';
    }
    return false;
  }

  double? _safeNum(dynamic obj, List<String> path) {
    final v = _getPath(obj, path);
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.trim().replaceAll(',', '.');
      final n = double.tryParse(s);
      return n;
    }
    return null;
  }

  List<String> _safeStringList(dynamic obj, List<String> path) {
    final v = _getPath(obj, path);
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  // ---------------- Mood Picker Integration ----------------------------------

  int _scoreForMoodLocal(PandaMood m) {
    final v = m.valence.clamp(-1.0, 1.0);
    final double mapped = ((v + 1.0) / 2.0) * 4.0;
    return mapped.round().clamp(0, 4);
  }

  // NEW: Dual-Skala Bottom-Sheet (Kopf/Körper)
  Future<_DualMood?> _showDualMoodSheet(
    BuildContext context, {
    required String title,
  }) async {
    int mental = 2;
    int physical = 2;

    String labelFor(int v) {
      switch (v) {
        case 0:
          return 'sehr schlecht';
        case 1:
          return 'eher schlecht';
        case 2:
          return 'neutral';
        case 3:
          return 'eher gut';
        case 4:
          return 'sehr gut';
      }
      return 'neutral';
    }

    return await showModalBottomSheet<_DualMood>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final bottom = mq.viewInsets.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + bottom),
            child: StatefulBuilder(
              builder: (ctx, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Kopf',
                          style: Theme.of(ctx)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Slider(
                      value: mental.toDouble(),
                      min: 0,
                      max: 4,
                      divisions: 4,
                      label: labelFor(mental),
                      onChanged: (v) => setState(() => mental = v.round()),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Körper',
                          style: Theme.of(ctx)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Slider(
                      value: physical.toDouble(),
                      min: 0,
                      max: 4,
                      divisions: 4,
                      label: labelFor(physical),
                      onChanged: (v) => setState(() => physical = v.round()),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ZenPrimaryButton(
                        label: 'Speichern',
                        onPressed: () {
                          Navigator.of(ctx).pop(_DualMood(
                            mental: mental,
                            physical: physical,
                            mentalLabel: labelFor(mental),
                            physicalLabel: labelFor(physical),
                          ));
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // NEW (deterministisch): Mood nur bei flow.mood_prompt && !closure anzeigen
  Future<_DualMood?> _promptDualMoodOnce(
    BuildContext context, {
    required String title,
  }) async {
    if (_isMoodOpen) return null; // Guard gegen Doppelöffnen
    _isMoodOpen = true;
    try {
      return await _showDualMoodSheet(context, title: title);
    } finally {
      _isMoodOpen = false;
    }
  }

  // NEW (v6.7.6): Mood nur bei flow.mood_prompt && !closure anzeigen
  Future<void> _maybeAskMood(
    BuildContext context, {
    required ReflectionRound round,
    required bool moodPrompt,
    bool afterClosure = false,
  }) async {
    // Guards
    if (!moodPrompt) return; // nur wenn der Worker es wünscht
    if (afterClosure) return; // nie in der Closure-Phase
    if (round.hasMood) return; // bereits vorhanden

    final hasRisk = round.steps.isNotEmpty ? round.steps.last.risk : false;
    final title = hasRisk
        ? 'Wenn du magst: Wie fühlst du dich? (Kopf & Körper)'
        : 'Wie fühlst du dich gerade? (Kopf & Körper)';

    final chosen = await _promptDualMoodOnce(context, title: title);
    if (chosen == null) return;

    _didPromptMood = true;

    // UI-Status setzen
    setState(() {
      round.moodScore = chosen.avg;
      round.moodLabel = chosen.combinedLabel;
      _dualMoodsByRoundId[round.id] = chosen;
    });

    // **Lokal speichern** nur wenn 🍃/🌿 aktiv
    unawaited(() async {
      try {
        if (_isLocalStoreAllowed()) {
          final dyn = MemoryService.instance as dynamic;
          await dyn.saveMoodEntry?.call(
            // v6.7.7: DateTime statt ISO-String
            DateTime.now().toUtc(),
            chosen.mental,
            chosen.physical,
          );
        }
      } catch (_) {}
    }());

    // **Server posten** nur wenn Teilen erlaubt (🌿)
    if (_isSharingEnabled()) {
      try {
        await ApiService.instance.mood(
          entryId: round.id,
          icon: chosen.avg,
          note: null,
        );
      } catch (_) {
        // still
      }
    }
  }

  void _appendThankYouAfterSave(ReflectionRound r) {
    if (!mounted) return;
    const thankYou = 'Danke dir fürs Speichern und Reflektieren. 💛\n'
        'Möchtest du weiterreden? Wenn nicht, wünsche ich dir einen ruhigen Tag.';
    final step = _PandaStep(
      mirror: _capChars(thankYou, kMirrorMaxChars),
      question: '',
      talkLines: const <String>[],
      risk: r.steps.isNotEmpty ? r.steps.last.risk : false,
      // Hinweis: diese beiden Chips sind bewusst leicht – sie dienen nur der Navigation nach dem Speichern.
      followups: const <String>[
        'Ja, ich möchte weiterreden … ',
        'Für heute reicht es mir, danke … ',
      ],
    );
    setState(() {
      if (r.steps.isEmpty || r.steps.last.mirror != step.mirror) {
        r.steps.add(step);
      }
      _chipMode = _ChipMode.answer;
    });
    _fadeSlideCtrl.forward(from: 0);
    _scrollToBottom();
  }

  // ---------------- Sync aus ReflectionController ----------------------------

  /// Übernimmt den aktuellen ReflectionVM aus dem Controller in die lokale
  /// Rundendarstellung (_rounds). Dadurch bleibt der Screen reines UI und
  /// der Full-Session-Flow liegt in reflection_logic.dart.
  void _syncFromControllerVm() {
    final vmDyn = _ctrl.vm;
    if (vmDyn == null) return;

    final sess = _ctrl.session;
    final key =
        '${sess?.id ?? ''}::${vmDyn.mirror}::${vmDyn.question}::${vmDyn.hopeText ?? ''}::${vmDyn.talkLines.join('|')}';

    if (key == _lastAssistantKey) {
      // Kein neuer Panda-Turn → nur UI refreshen, falls nötig
      setState(() {});
      return;
    }
    _lastAssistantKey = key;

    final step = _PandaStep(
      mirror: _capChars(vmDyn.mirror, kMirrorMaxChars),
      question: _limitWords(vmDyn.question, kQuestionMaxWords),
      talkLines: vmDyn.talkLines,
      risk: vmDyn.risk,
      followups: vmDyn.answerChips,
      helperSuggestion:
          (vmDyn.helperSuggestion ?? '').trim().isNotEmpty
              ? vmDyn.helperSuggestion
              : null,
    );

    setState(() {
      if (_rounds.isEmpty) {
        _rounds.add(
          ReflectionRound(
            id: _makeId(),
            ts: DateTime.now(),
            mode: 'text',
            userInput: '',
            allowClosure: vmDyn.allowClosure,
          ),
        );
      }

      final round = _rounds.last;

      if (round.steps.isEmpty) {
        round.steps.add(step);
      } else {
        final last = round.steps.last;
        if (last.mirror == step.mirror &&
            last.question == step.question &&
            listEquals(last.talkLines, step.talkLines)) {
          round.steps[round.steps.length - 1] = step;
        } else {
          round.steps.add(step);
        }
      }

      round.allowClosure = vmDyn.allowClosure;
    });

    _fadeSlideCtrl.forward(from: 0);
    _scrollToBottom();
  }
}

// ============================== Calm Glass Banner =============================
class _CalmGlassBanner extends StatelessWidget {
  final String text;
  const _CalmGlassBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            offset: const Offset(0, 8),
            color: Colors.black.withValues(alpha: .10),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, height: 1.25),
      ),
    );
  }
}

// ============================== Extensions ===================================
extension _Utc on DateTime {
  DateTime toUtcDateTime() => isUtc ? this : toUtc();
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
