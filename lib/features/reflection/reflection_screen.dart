// lib/features/reflection/reflection_screen.dart
//
// ReflectionScreen — Panda v3.21.0 (Oxford level; CH risk actions; no auto-nav)
// -----------------------------------------------------------------------------
// Änderungen in diesem Build:
// • helperSuggestion: Worker-Feld 'helper_suggestion' wird gelesen und an _PandaStep übergeben.
// • closureFull: mood_intro-Text wird in round.moodIntro gespeichert (Bubble in Widgets),
//   kein zusätzlicher Panda-Step für den Intro-Text.
// • Sonstiges: kleine Robustheits-/Style-Anpassungen, keine Verhaltensänderung im Kern.
// -----------------------------------------------------------------------------
// Garantien / Änderungen (unverändert):
// • KEIN automatisches Zurück ins Hauptmenü beim Mood-Wählen ODER Speichern.
// • Save-Flow deterministisch: Button → (falls Mood fehlt) Picker → Persist → Calm Confirm → Panda-Danke.
// • Closure-Respect: flow.mood_prompt / recommend_end → Leitfrage unterdrückt, Mood-Phase.
// • Worker-Chips ONLY: nutzt answer_helpers (sanitisiert, max 3). KEINE abgeleiteten Heuristik-Chips.
// • Error-Path ruhig: BottomSheet mit „Nochmal senden“; kein generisches Debug-Toast.
// • talk[] optional, Safety bei risk_level mild/high.
// • Footer-Disclaimer bleibt sichtbar.
// • [GUARD] Mood-Guard: Picker max. 1× pro Runde, keine Doppel-Öffnungen.
// • NEU (CH): Bei Risiko werden Schweizer Hilfenummern angezeigt (143/147/144/112/117) –
//   als milder Safety-Text + eigene Card mit Call-Buttons (SwissHotlineCard).
//
// -----------------------------------------------------------------------------
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

// Panda-Moods
import '../../models/panda_mood.dart';
import '../../widgets/panda_mood_picker.dart';

// Journal
import '../../models/journal_entry.dart' as jm;
import '../../providers/journal_entries_provider.dart';

// Services
import '../../services/guidance_service.dart';
import '../../services/speech_service.dart';
import '../../services/core/api_service.dart'; // Mood speichern

// CH Hotlines (Call-Buttons) + Launcher-Utilities
import '../../widgets/hotline_widget.dart'; // SwissHotlineCard / Section
import '../../shared/launching.dart'; // (nicht direkt hier genutzt; in Card verwendet)

// Parts
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

const Duration _animShort = Duration(milliseconds: 240);
const Duration _netTimeout = Duration(seconds: 18);
const double _inputReserve = 104;

// ---------------- Optionaler Hook + Navigation --------------------------------
typedef AddToGedankenbuch = void Function(
  String text,
  String mood, {
  bool isReflection,
  String? aiQuestion,
});

// ---------------- Interner UI-State ------------------------------------------
enum _ChipMode { starter, answer, none }

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
  StreamSubscription<String>? _finalSub;

  // Runden / Session
  final List<ReflectionRound> _rounds = <ReflectionRound>[];
  ReflectionRound? get _current => _rounds.isEmpty ? null : _rounds.last;
  ReflectionSession? _session;

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

  @override
  void initState() {
    super.initState();

    // AnimationController früh anlegen (verhindert Crash bei dispose)
    _fadeSlideCtrl =
        AnimationController(vsync: this, duration: _animShort)..value = 1.0;

    // Live-Transkript → Eingabe
    _finalSub = _speech.transcript$.listen((t) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cur = _controller.text.trim();
        final joined = (cur.isEmpty ? t : '$cur\n$t').trim();
        _controller
          ..text = joined
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        _maybeHideStarterChipsOnTyping();
        _focusInput();
      });
    });

    // Tippen-Listener: Starterchips ausblenden, sobald der User selbst schreibt
    _controller.addListener(_maybeHideStarterChipsOnTyping);

    // Optionaler Auto-Start
    final seed = (widget.initialUserText ?? '').trim();
    if (seed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _startNewReflection(userText: seed, mode: 'text');
      });
    }
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
    _finalSub?.cancel();
    _speech.dispose();
    _controller.dispose();
    _inputFocus.dispose();
    _pageFocus.dispose();
    _listCtrl.dispose();
    _fadeSlideCtrl.dispose(); // sicher, da in initState erzeugt
    super.dispose();
  }

  // ---------------- Keyboard Shortcuts ---------------------------------------
  KeyEventResult _handleKey(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;

    // ESC → Mic stoppen
    if (e.logicalKey == LogicalKeyboardKey.escape && _speech.isRecording) {
      _toggleRecording();
      return KeyEventResult.handled;
    }

    final bool isEnter = e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter;
    final bool withCtrlOrCmd =
        HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
    final bool withShift = HardwareKeyboard.instance.isShiftPressed;

    // Cmd/Ctrl+Enter: immer senden
    if (withCtrlOrCmd && isEnter && !loading) {
      _send();
      return KeyEventResult.handled;
    }

    // Enter = Senden, Shift+Enter = Zeilenumbruch
    if (isEnter && !withShift && !loading) {
      _send();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------- Actions ---------------------------------------------------
  Future<void> _toggleRecording() async {
    try {
      if (_speech.isRecording) {
        await _speech.stop();
        if (!context.mounted) return;
        _focusInput();
      } else {
        HapticFeedback.selectionClick();
        FocusScope.of(context).unfocus();
        await _speech.start();
      }
      if (mounted) setState(() {});
    } catch (_) {
      _toast('Mikrofon nicht verfügbar. Bitte Berechtigung erlauben.');
    }
  }

  Future<void> _send() async {
    if (loading) return;

    var text = _controller.text.trim();
    if (text.isEmpty) return;

    // Hard-Limit.
    if (text.length > kInputHardLimit) {
      text = text.substring(0, kInputHardLimit);
      _toast('Dein Text wurde auf $kInputHardLimit Zeichen gekürzt.');
    }

    // Startet neue Runde oder beantwortet die letzte Frage (Multi-Turn)
    if (_current == null) {
      await _startNewReflection(
        userText: text,
        mode: _speech.isRecording ? 'voice' : 'text',
      );
      return;
    }

    if (_current!.hasPendingQuestion) {
      setState(() {
        _current!.steps.last.answer = text;
        _controller.clear();
        _chipMode = _ChipMode.none;
      });
      _scrollToBottom();
      _focusInput();
      HapticFeedback.lightImpact();

      // → nächste Spiegelung + genau 1 Leitfrage vom Worker
      unawaited(
        _continueReflectionFromWorker(round: _current!, userAnswer: text),
      );
      return;
    }

    await _startNewReflection(
      userText: text,
      mode: _speech.isRecording ? 'voice' : 'text',
    );
  }

  // ---------------- Session-Coercion -----------------------------------------
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
          : (s['turn_index'] is num) ? (s['turn_index'] as num).toInt() : 0;
      final maxTurns =
          (s['max_turns'] is num) ? (s['max_turns'] as num).toInt() : 3;

      return ReflectionSession(
        threadId:
            id.isNotEmpty ? id : 'local_${DateTime.now().millisecondsSinceEpoch}',
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

  // --- Start: neue Reflexion -------------------------------------------------
  Future<void> _startNewReflection({
    required String userText,
    required String mode,
  }) async {
    setState(() {
      loading = true;
      _chipMode = _ChipMode.none;
      // [GUARD] neue Runde → Guards zurücksetzen
      _didPromptMood = false;
      _isMoodOpen = false;
    });

    try {
      final round = ReflectionRound(
        id: _makeId(),
        ts: DateTime.now(),
        mode: mode,
        userInput: userText,
        allowClosure: false,
      );

      setState(() {
        _rounds.add(round);
        _controller.clear();
      });
      _scrollToBottom();

      dynamic turn;
      try {
        turn = await GuidanceService.instance
            .startSessionFull(text: userText, locale: 'de', tz: 'Europe/Zurich')
            .timeout(_netTimeout);
      } on NoSuchMethodError {
        try {
          turn = await GuidanceService.instance
              .startSession(text: userText, locale: 'de', tz: 'Europe/Zurich')
              .timeout(_netTimeout);
        } catch (_) {
          rethrow;
        }
      } on TimeoutException {
        if (!mounted) return;
        _handleTurnError(round);
        _showRetryError(_errorHint, () {
          if (!mounted) return;
          unawaited(_startNewReflection(userText: userText, mode: mode));
        });
        return;
      } catch (_) {
        if (!mounted) return;
        _handleTurnError(round);
        _showRetryError(_errorHint, () {
          if (!mounted) return;
          unawaited(_startNewReflection(userText: userText, mode: mode));
        });
        return;
      }

      // Flags aus Turn
      final bool flagMoodPrompt =
          _safeBool(turn, ['mood', 'prompt']) ||
          _safeBool(turn, ['flow', 'mood_prompt']);
      final bool flagRecommendEnd = _safeBool(turn, ['flow', 'recommend_end']);

      final step = _buildStepFromTurn(turn);
      setState(() {
        _session = _coerceSession(turn);
        round.steps.add(step);

        final bool wantClosure = flagMoodPrompt || flagRecommendEnd;
        round.allowClosure = wantClosure;

        final hasHelpers = step.followups.isNotEmpty;
        _chipMode =
            (step.expectsAnswer || hasHelpers) ? _ChipMode.answer : _ChipMode.none;
      });

      _fadeSlideCtrl.forward(from: 0);
      _scrollToBottom();
      _focusInput();

      // → Mood-Picker nur via Guard
      if (flagMoodPrompt) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _maybeAskMood(context,
              round: round, moodPrompt: true, afterClosure: false);
        });
      }

      // Abschluss?
      if (flagRecommendEnd) {
        unawaited(_requestClosureFromWorker(round: round, userAnswer: ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // --- Continue: weitere Spiegelung/Frage per /reflect_full ------------------
  Future<void> _continueReflectionFromWorker({
    required ReflectionRound round,
    required String userAnswer,
  }) async {
    if (!mounted) return;
    setState(() => loading = true);
    _scrollToBottom();

    dynamic turn;
    try {
      if (_session != null) {
        try {
          turn = await GuidanceService.instance
              .nextTurnFull(
                session: _session!,
                text: userAnswer,
                locale: 'de',
                tz: 'Europe/Zurich',
              )
              .timeout(_netTimeout);
        } on NoSuchMethodError {
          try {
            turn = await (GuidanceService.instance as dynamic)
                .reflectFull(
                    session: _session!,
                    text: userAnswer,
                    locale: 'de',
                    tz: 'Europe/Zurich')
                .timeout(_netTimeout);
          } on NoSuchMethodError {
            turn = await GuidanceService.instance
                .startSessionFull(
                  text: userAnswer,
                  locale: 'de',
                  tz: 'Europe/Zurich',
                  session: _session!,
                )
                .timeout(_netTimeout);
          }
        }
      } else {
        turn = await GuidanceService.instance
            .startSessionFull(
              text: userAnswer,
              locale: 'de',
              tz: 'Europe/Zurich',
            )
            .timeout(_netTimeout);
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => loading = false);
      _showRetryError(_errorHint, () {
        if (!mounted) return;
        unawaited(_continueReflectionFromWorker(
            round: round, userAnswer: userAnswer));
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      _showRetryError(_errorHint, () {
        if (!mounted) return;
        unawaited(_continueReflectionFromWorker(
            round: round, userAnswer: userAnswer));
      });
      return;
    }

    if (!mounted) return;

    final bool flagMoodPrompt =
        _safeBool(turn, ['mood', 'prompt']) ||
        _safeBool(turn, ['flow', 'mood_prompt']);
    final bool flagRecommendEnd = _safeBool(turn, ['flow', 'recommend_end']);

    final step = _buildStepFromTurn(turn);
    setState(() {
      _session = _coerceSession(turn);
      if (round.shouldAppendStep(step)) {
        round.steps.add(step);
      }

      if (flagMoodPrompt || flagRecommendEnd) round.allowClosure = true;

      final hasHelpers = step.followups.isNotEmpty;
      _chipMode =
          (step.expectsAnswer || hasHelpers) ? _ChipMode.answer : _ChipMode.none;
    });

    _fadeSlideCtrl.forward(from: 0);
    _scrollToBottom();
    _focusInput();

    if (flagMoodPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeAskMood(context,
            round: round, moodPrompt: true, afterClosure: false);
      });
    }

    if (flagRecommendEnd) {
      unawaited(
          _requestClosureFromWorker(round: round, userAnswer: userAnswer));
    }

    setState(() => loading = false);
  }

  void _handleTurnError(ReflectionRound round) {
    // Ruhig bleiben, Mini-Mirror ohne Frage, keine Chips
    const fallbackMirror = 'Ich höre dich. Ich bleibe bei dir.';
    final step = _PandaStep(
      mirror: _capChars(fallbackMirror, kMirrorMaxChars),
      question: '',
      talkLines: const <String>[],
      risk: false,
      followups: const <String>[],
    );
    setState(() {
      round.steps.add(step);
      round.allowClosure = false;
      _chipMode = _ChipMode.none;
    });
    _fadeSlideCtrl.forward(from: 0);
    _scrollToBottom();
  }

  // ---------------- Turn → Step ----------------------------------------------
  _PandaStep _buildStepFromTurn(dynamic t) {
    final bool isClosure =
        _safeBool(t, ['mood', 'prompt']) ||
        _safeBool(t, ['flow', 'mood_prompt']) ||
        _safeBool(t, ['flow', 'recommend_end']);

    final mirrorRaw = _coerceMirror(t).trim();
    final questionRaw = _coerceQuestion(t);
    final helperSuggestion = _coerceHelperSuggestion(t);

    final level = _safeString(t, ['risk_level']).toLowerCase();
    final risk = _safeBool(t, ['risk']) || level == 'high' || level == 'mild';

    final helpers =
        isClosure ? <String>[] : _coerceAnswerHelpers(t).take(3).toList();

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
      helperSuggestion:
          helperSuggestion.isNotEmpty ? helperSuggestion : null,
    );
  }

  // ---------------- SAVE→MOOD: deterministischer Flow ------------------------

  /// Öffnet (falls nötig) den Mood-Picker und speichert danach sofort.
  /// WICHTIG: Keine Navigation (kein pop/go) – nur Persist + Bestätigung + Dankesstep.
  Future<void> _onPressSaveRound(ReflectionRound r) async {
    if (r.entryId != null) {
      _toast('Bereits gespeichert.');
      return;
    }
    if (!r.answered) {
      _toast('Bitte zuerst deine Antwort schreiben.');
      return;
    }

    // Mood fehlt → Picker öffnen (einmalig, mit Guard)
    if (!r.hasMood) {
      if (_isMoodOpen) return; // [GUARD]
      _isMoodOpen = true; // [GUARD]
      final chosen = await showPandaMoodPicker(
        context,
        title: 'Wie fühlst du dich gerade?',
      );
      _isMoodOpen = false; // [GUARD]
      if (chosen == null) return; // User abgebrochen
      _didPromptMood = true; // [GUARD] – Mood wurde entschieden

      final score = _scoreForMoodLocal(chosen);
      final label = chosen.labelDe;
      setState(() {
        r.moodScore = score;
        r.moodLabel = label;
      });

      // optional best-effort an Worker melden (ohne UI-Abhängigkeit)
      try {
        await ApiService.instance.mood(
          entryId: r.id,
          icon: score,
          note: null,
        );
      } catch (_) {/* ignore */}
    }

    await _saveRoundCore(r);
  }

  /// Core-Persist + ruhige, milchige Bestätigungsleiste + Panda-Danke-Step.
  /// KEINE Navigation.
  Future<void> _saveRoundCore(ReflectionRound r) async {
    // Build Entry
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

    final tags = <String>[
      'reflection',
      if ((r.moodLabel ?? '').trim().isNotEmpty) 'mood:${r.moodLabel!.trim()}',
      if (r.moodScore != null) 'moodScore:${r.moodScore}',
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
      'sourceRef': 'reflection|session:${_session?.threadId ?? ''}',
    };

    final entry = jm.JournalEntry.fromMap(entryMap);

    // Persist via Provider
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

    // Ruhige Bestätigung (milchige Glas-Leiste)
    _showCalmConfirm(
      'Gespeichert. Deine Reflexion und Stimmung sind im Gedankenbuch.',
    );

    // Panda bedankt sich und fragt freundlich nach Fortsetzung.
    _appendThankYouAfterSave(r);
  }

  // ---------------- Delete ----------------------------------------------------
  Future<void> _deleteRound(ReflectionRound r) async {
    setState(() {
      _rounds.removeWhere((x) => x.id == r.id);
    });
    // Falls nun keine Runden mehr → zurück zu Starterchips
    setState(() {
      _chipMode = _rounds.isEmpty ? _ChipMode.starter : _ChipMode.none;
    });
    _toast('Gelöscht.');
  }

  // ---------------- Abschluss/Mood-Einleitung (Worker-kompatibel) -----------
  Future<void> _requestClosureFromWorker({
    required ReflectionRound round,
    required String userAnswer,
  }) async {
    if (!mounted) return;
    setState(() => loading = true);
    _scrollToBottom();

    dynamic res;
    try {
      res = await GuidanceService.instance
          .closureFull(
            session: _session,
            answer: userAnswer,
            locale: 'de',
            tz: 'Europe/Zurich',
          )
          .timeout(_netTimeout);
    } on NoSuchMethodError {
      if (mounted) setState(() => loading = false);
      return;
    } on TimeoutException {
      if (mounted) setState(() => loading = false);
      return;
    } catch (_) {
      if (mounted) setState(() => loading = false);
      return;
    }

    if (!mounted) return;

    final closure = _safeString(res, ['closure', 'mood_intro', 'text']).trim();
    final level = _safeString(res, ['risk_level']).toLowerCase();
    final risk =
        _safeBool(res, ['risk']) || level == 'high' || level == 'mild';

    setState(() => loading = false);

    // Wenn kein Text vom Worker: direkt in die Mood-Phase wechseln
    if (closure.isEmpty) {
      setState(() {
        round.allowClosure = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeAskMood(context,
            round: round, moodPrompt: true, afterClosure: true);
      });
      return;
    }

    // → Intro-Bubble befüllen, keine zusätzliche Panda-Karte
    setState(() {
      round.moodIntro = _capChars(closure, kMirrorMaxChars);
      round.allowClosure = true;
      // Safety-Flag: falls Worker hier Risiko meldet, in letzter Step-Card mitschwingen lassen
      if (round.steps.isNotEmpty) {
        final last = round.steps.last;
        if (risk && !last.risk) {
          round.steps[round.steps.length - 1] =
              last.copyWith(risk: true);
        }
      }
    });
    _fadeSlideCtrl.forward(from: 0);
    _scrollToBottom();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeAskMood(context, round: round, moodPrompt: true, afterClosure: true);
    });
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
    // tolerant: top-level und innerhalb von primary/flow prüfen
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

  // Answer-Helpers (keine Fragen!)
  List<String> _coerceAnswerHelpers(dynamic t) {
    List<String> acc = [];
    void addAll(dynamic obj) {
      if (obj == null) return;
      acc.addAll(_safeStringList(obj, [
        'answer_helpers',
        'answer_scaffolds',
        'answer_templates',
        'answer_suggestions',
        'chips',
        'helpers',
        'answers',
      ]));
    }

    addAll(t);
    addAll(_extract(t, 'primary'));
    addAll(_extract(t, 'flow'));

    acc = acc.map(_sanitizeHelperText).where((s) => s.isNotEmpty).toList();

    final seen = <String>{};
    final deduped = <String>[];
    for (final s in acc) {
      if (seen.add(s.toLowerCase())) deduped.add(s);
      if (deduped.length >= 3) break;
    }
    return deduped;
  }

  String _sanitizeHelperText(String raw) {
    var s = raw.toString().trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'^[„“"»«]+|[„“"»«]+$'), '');
    s = s.replaceAll(RegExp(r'[?？]+$'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 72) s = '${s.substring(0, 72).trimRight()}…';
    s = s.replaceAll(RegExp(r'[.。]+$'), '').trim();
    return s;
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
    return clean.length <= max ? clean : '${clean.substring(0, max).trimRight()}…';
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

  // Ruhiger „Retry“-BottomSheet
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
                  color: Colors.black.withOpacity(.65)),
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

  // Silent "Toast" – dezentes Haptic + Log
  void _toast(String msg) {
    debugPrint('[Reflection] $msg');
    HapticFeedback.selectionClick();
  }

  // Ruhige, milchige Bestätigungsleiste
  void _showCalmConfirm(String text) async {
    setState(() {
      _confirmText = text;
      _showConfirmBanner = true;
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _showConfirmBanner = false);
  }

  Future<void> _showPostSheet() async {
    // Nur auf explizite Aktion; KEIN Auto-Open von Mood/Save.
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: const Text('Weiter reflektieren'),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
                ListTile(
                  leading: const Icon(Icons.apps_rounded),
                  title: const Text('Hauptmenü'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (widget.onGoHome != null) {
                      widget.onGoHome!();
                    } else {
                      // Achtung: KEIN auto-pop irgendwo sonst — nur hier auf expliziten Tap.
                      Navigator.of(context).maybePop();
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.book_rounded),
                  title: const Text('Gedankenbuch öffnen'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (widget.onOpenJournal != null) {
                      widget.onOpenJournal!();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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

    // Abschluss aktiv? (Mood-Phase)
    final bool closureActive =
        r != null && r.allowClosure && !(r.hasPendingQuestion) && !(r.hasMood);

    final bool showAnswerHint = r != null &&
        r.hasPendingQuestion &&
        !closureActive &&
        !_talkContainsLengthHint(r.steps.isNotEmpty ? r.steps.last : null);

    final bool lastIsTyping = r != null && loading;

    final bool showStarter = _rounds.isEmpty && _chipMode == _ChipMode.starter;

    // Nur Worker-Chips (keine Client-Heuristiken)
    final bool showAnswerChips = !closureActive &&
        (r != null && r.steps.isNotEmpty && r.steps.last.followups.isNotEmpty) &&
        _chipMode == _ChipMode.answer;

    // --- Chip-Quellen
    final List<String> _rawTemplates = showAnswerChips
        ? r!.steps.last.followups
        : (showStarter ? _starterChips() : const <String>[]);

    // Sanfter, modell-freundlicher Filter (kein Erfinden)
    final lastQ = r?.steps.isNotEmpty == true ? r!.steps.last.question : '';
    final lastA = r?.steps.isNotEmpty == true ? (r!.steps.last.answer ?? '') : '';
    final List<String> answerTemplates =
        _refineChips(_rawTemplates, question: lastQ, lastAnswer: lastA);

    final bool canPermanentSave =
        r != null && r.answered && (r.entryId == null);

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

                              // Intro
                              if (_rounds.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          BoxConstraints(maxWidth: cardMaxW),
                                      child: const _IntroBubble(),
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
                                      final isLast = index == _rounds.length - 1;
                                      final isTyping = isLast && lastIsTyping;
                                      final hasRisk = _rounds[index]
                                              .steps
                                              .isNotEmpty &&
                                          _rounds[index].steps.last.risk;

                                      final thread = _RoundThread(
                                        maxWidth: cardMaxW,
                                        round: _rounds[index],
                                        isLast: isLast,
                                        isTyping: isTyping,
                                        // Rundeninterner Save (weiterhin erlaubt)
                                        onSave: _rounds[index].answered
                                            ? () => _onPressSaveRound(
                                                _rounds[index])
                                            : null,
                                        onDelete: _rounds[index].entryId != null
                                            ? () =>
                                                _deleteRound(_rounds[index])
                                            : null,
                                        onSelectMood: (score, label) async {
                                          // Explizites Mood-Setzen aus Rundencard → KEINE Navigation.
                                          setState(() {
                                            _rounds[index].moodScore = score;
                                            _rounds[index].moodLabel = label;
                                            _didPromptMood = true; // [GUARD]
                                          });
                                          await _saveRoundCore(_rounds[index]);
                                        },
                                        safetyText: hasRisk
                                            ? _emergencyHint(context)
                                            : null,
                                      );

                                      // Darunter (falls Risiko) CH-Call-Card einblenden
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

                                      // Sanftes Appear nur für letzte Runde
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
                                                      onPressed: () => _onTapChip(
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
                                                  .withOpacity(0.72),
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
                                padding:
                                    const EdgeInsets.fromLTRB(0, 0, 0, 8),
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

  // --- Chip Refinement (sanft, modell-freundlich; keine Erfindungen) ---------
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
    final qTokens =
        question.toLowerCase().split(RegExp(r'[^a-zäöüß0-9]+')).where((w) => w.length >= 3).toSet();
    final aTokens =
        lastAnswer.toLowerCase().split(RegExp(r'[^a-zäöüß0-9]+')).where((w) => w.length >= 3).toSet();
    final anchors = {...qTokens, ...aTokens};

    bool looksInAxis(String t) {
      if (anchors.isEmpty) return true;
      final toks =
          t.toLowerCase().split(RegExp(r'[^a-zäöüß0-9]+')).where((w) => w.length >= 3);
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

    return kept.isNotEmpty
        ? kept
        : chips.map(_ensureEllipsisSuffix).take(3).toList();
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
      ..selection = TextSelection.fromPosition(TextPosition(offset: next.length));
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
    // Straff: nur 144 & 112 im Text (Details in SwissHotlineCard darunter).
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

  /// Mappt valence [-1..+1] linear auf Score 0..4.
  int _scoreForMoodLocal(PandaMood m) {
    final v = m.valence.clamp(-1.0, 1.0);
    final double mapped = ((v + 1.0) / 2.0) * 4.0;
    return mapped.round().clamp(0, 4);
  }

  /// Fragt ggf. die Stimmung ab (Worker-Hinweis) — OHNE Navigation.
  Future<void> _maybeAskMood(
    BuildContext context, {
    required ReflectionRound round,
    required bool moodPrompt,
    bool afterClosure = false,
  }) async {
    if (!moodPrompt) return;
    if (!mounted) return;
    if (round.hasMood) return; // Mood schon gesetzt → nichts tun
    if (_didPromptMood || _isMoodOpen) return; // [GUARD]

    _isMoodOpen = true; // [GUARD]
    final title =
        afterClosure ? 'Wie fühlst du dich jetzt?' : 'Wie fühlst du dich gerade?';

    final chosen = await showPandaMoodPicker(
      context,
      title: title,
    );
    _isMoodOpen = false; // [GUARD]
    if (chosen == null) return;

    final score = _scoreForMoodLocal(chosen);
    final label = chosen.labelDe;

    if (!mounted) return;
    setState(() {
      round.moodScore = score;
      round.moodLabel = label;
      _didPromptMood = true; // [GUARD]
    });

    // Best-effort Speichern (kein Snackbar, keine Navigation)
    try {
      await ApiService.instance.mood(
        entryId: round.id,
        icon: score, // nutzt den Score 0..4
        note: null,
      );
    } catch (_) {/* ignore */}
  }

  // ---------------- Panda-Danke-Step nach Save --------------------------------
  void _appendThankYouAfterSave(ReflectionRound r) {
    if (!mounted) return;
    const thankYou =
        'Danke dir fürs Speichern und Reflektieren. 💛\n'
        'Möchtest du weiterreden? Wenn nicht, wünsche ich dir einen ruhigen Tag.';
    final step = _PandaStep(
      mirror: _capChars(thankYou, kMirrorMaxChars),
      question: '',
      talkLines: const <String>[],
      risk: r.steps.isNotEmpty ? r.steps.last.risk : false,
      // sanfte Antwort-Chips als Satzstarter
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
        color: Colors.white.withOpacity(.20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.22)),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            offset: const Offset(0, 8),
            color: Colors.black.withOpacity(.10),
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
