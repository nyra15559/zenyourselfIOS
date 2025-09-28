// lib/features/reflection/reflection_screen.dart
//
// ReflectionScreen — Panda v3.16.1 (Worker v12.1.3-ready)
// -----------------------------------------------------------------------------
// • Error-Path: KEINE Frage/Chips bei Worker/Netz-Fehler (robust path).
// • Closure-Respect: Wenn Worker mood_prompt/recommend_end → Frage leer lassen.
// • Worker-Chips: nutzt answer_helpers (sanitisiert, max 3).
// • talk[] aus Worker wird übernommen (optionale Anzeige).
// • JSON-Helper: _safeBool/_safeString/_safeStringList/_extract/_getPath.
// • nextTurnFull nur mit non-null Session; sonst Fallback startSessionFull.
// • Chips: ZenChipGhost.onPressed (kein onTap). Satzstarter, keine Fragen.
// • Input: nutzt _InputBar – kompatibel zu ZenGlassInput.
// • Undo für Antworten, Snackbar „Antwort erfasst“.
// • Neu 6 Punkte in v3.16.x:
//   (1) Mirror-Säuberung: Instruktionssatz „Unten findest du Antwort-Chips …“ wird gefiltert.
//   (2) Abschluss-Gate im Screen: Keine Hints/Chips, wenn Closure aktiv (Mood-Phase).
//   (3) Chips behalten „… “ inkl. Space beim Einfügen (Worker v12.1.3).
//   (4) Dedupe-Hint: UI-Hinweis („Antworte in 1–2 Sätzen.“) wird unterdrückt, wenn der Worker ihn in talk[] liefert.
//   (5) Mirror-Fix: Kein Fallback mehr aus output_text/Frage; reine Fragen werden nicht als Mirror angezeigt.
//   (6) **Neu**: risk_level "mild" triggert Safety-Hinweis wie "high"; permanenter Footer-Disclaimer („keine Therapie…“).
// -----------------------------------------------------------------------------
// Hinweis: Frage-Typografie & Blasen-Styling liegen im Widgets-Part (no italics).
// -----------------------------------------------------------------------------
library reflection_screen;

import 'dart:async';
import 'dart:math';

import '../../services/guidance/dtos.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// Parts
part 'reflection_models.dart';
part 'reflection_widgets.dart';

// -----------------------------------------------------------------------------
// Config / Limits
// -----------------------------------------------------------------------------
const String kPandaHeaderAsset = 'assets/star_pa.png';

const int kMirrorMaxChars = 640; // weicher, Worker steuert Länge
const int kQuestionMaxWords = 40; // weicher, nur UI-Schutz

const int kInputSoftLimit = 500; // für UI-Indikator im _InputBar
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

  /// Optional: Navigation-Callbacks fürs Post-Sheet
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
  late final AnimationController _fadeSlideCtrl =
      AnimationController(vsync: this, duration: _animShort)..value = 1.0;

  // Speech
  final SpeechService _speech = SpeechService();
  StreamSubscription<String>? _finalSub;

  // Runden / Session
  final List<ReflectionRound> _rounds = <ReflectionRound>[];
  ReflectionRound? get _current => _rounds.isEmpty ? null : _rounds.last;
  ReflectionSession? _session; // typisiert

  // Flags
  bool loading = false; // auch genutzt für kurzen Tipp-Impuls

  // Fehlermeldung aus GuidanceService (mikro-kurz, lokalisiert)
  String get _errorHint => GuidanceService.instance.errorHint;

  // Undo (Antwort)
  String? _lastSentAnswer;
  int? _lastAnsweredStepIndex;

  // Chips-State
  _ChipMode _chipMode = _ChipMode.starter;
  bool _textWasEmpty = true;

  @override
  void initState() {
    super.initState();

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
    _fadeSlideCtrl.dispose();
    super.dispose();
  }

  // ---------------- Keyboard Shortcuts ---------------------------------------
  KeyEventResult _handleKey(RawKeyEvent e) {
    if (e is! RawKeyDownEvent) return KeyEventResult.ignored;

    // ESC → Mic stoppen
    if (e.logicalKey == LogicalKeyboardKey.escape && _speech.isRecording) {
      _toggleRecording();
      return KeyEventResult.handled;
    }

    final bool isEnter = e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter;
    final bool withCtrlOrCmd = e.isControlPressed || e.isMetaPressed;
    final bool withShift = e.isShiftPressed;

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
        if (!mounted) return;
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
        _lastSentAnswer = text;
        _lastAnsweredStepIndex = _current!.steps.length - 1;
        _controller.clear();
        _chipMode = _ChipMode.none;
      });
      _scrollToBottom();
      _showUndoForAnswer();
      _focusInput();
      HapticFeedback.lightImpact();

      // → nächste Spiegelung + genau 1 Leitfrage vom Worker
      unawaited(_continueReflectionFromWorker(round: _current!, userAnswer: text));
      return;
    }

    await _startNewReflection(
      userText: text,
      mode: _speech.isRecording ? 'voice' : 'text',
    );
  }

  void _undoLastAnswer() {
    final r = _current;
    if (r == null) return;
    final i = _lastAnsweredStepIndex;
    if (i == null || i < 0 || i >= r.steps.length) return;

    final was = _lastSentAnswer ?? '';
    setState(() {
      r.steps[i].answer = null;
      _controller
        ..text = was
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      _chipMode = _ChipMode.answer;
    });
    _focusInput();
  }

  void _showUndoForAnswer() {
    final snack = SnackBar(
      content: const Text('Antwort erfasst'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: _undoLastAnswer,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      backgroundColor: ZenColors.deepSage,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(snack);
  }

  // ---------------- Session-Coercion -----------------------------------------
  /// Zieht eine ReflectionSession aus beliebigen Turn-Objekten.
  ReflectionSession _coerceSession(dynamic turn) {
    // 1) Native Typen
    try {
      if (turn is ReflectionTurn) return turn.session;
    } catch (_) {}

    dynamic s;
    // 2) Top-Level Map
    if (turn is Map) {
      s = turn['session'];
    } else {
      // 3) toJson / Indexer
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

    // Fallback – nie null zurückgeben
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
    });

    try {
      final round = ReflectionRound(
        id: _makeId(),
        ts: DateTime.now(),
        mode: mode,
        userInput: userText,
        allowClosure: false, // am Anfang nie Abschluss zeigen
      );

      setState(() {
        _rounds.add(round);
        _controller.clear();
      });
      _scrollToBottom();

      dynamic turn;
      try {
        // Bevorzugt: neuer Worker-Contract (/reflect_full)
        turn = await GuidanceService.instance
            .startSessionFull(text: userText, locale: 'de', tz: 'Europe/Zurich')
            .timeout(_netTimeout);
      } on NoSuchMethodError {
        // Fallback: ältere GuidanceService-Version
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
        return;
      } catch (_) {
        if (!mounted) return;
        _handleTurnError(round);
        return;
      }

      final step = _buildStepFromTurn(turn);
      setState(() {
        _session = _coerceSession(turn); // Session setzen
        round.steps.add(step);

        // Abschluss nur, wenn Worker es will
        final bool wantClosure =
            _safeBool(turn, ['mood', 'prompt']) ||
            _safeBool(turn, ['flow', 'mood_prompt']) ||
            _safeBool(turn, ['flow', 'recommend_end']);
        round.allowClosure = wantClosure;

        final hasHelpers = step.followups.isNotEmpty; // helpers only
        _chipMode = (step.expectsAnswer || hasHelpers)
            ? _ChipMode.answer
            : _ChipMode.none;
      });
      _fadeSlideCtrl.forward(from: 0);
      _scrollToBottom();
      _focusInput();

      // Falls der Worker direkt Abschluss empfiehlt → Closure holen
      final bool wantClosure =
          _safeBool(turn, ['mood', 'prompt']) ||
          _safeBool(turn, ['flow', 'mood_prompt']) ||
          _safeBool(turn, ['flow', 'recommend_end']);
      if (wantClosure) {
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
      // Nur wenn wir eine valide Session haben → nextTurnFull
      if (_session != null) {
        try {
          turn = await GuidanceService.instance
              .nextTurnFull(
                session: _session!, // non-null
                text: userAnswer,
                locale: 'de',
                tz: 'Europe/Zurich',
              )
              .timeout(_netTimeout);
        } on NoSuchMethodError {
          // Fallback-Kaskade für ältere Services
          try {
            turn = await (GuidanceService.instance as dynamic)
                .reflectFull(
                    session: _session!,
                    text: userAnswer,
                    locale: 'de',
                    tz: 'Europe/Zurich')
                .timeout(_netTimeout);
          } on NoSuchMethodError {
            // letzte Option: neue Session starten, aber Kontext mitgeben
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
        // Keine Session vorhanden → sichere Neuaufnahme
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
      _toast(_errorHint);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      _toast(_errorHint);
      return;
    }

    if (!mounted) return;

    final step = _buildStepFromTurn(turn);
    setState(() {
      _session = _coerceSession(turn); // Session updaten
      if (round.shouldAppendStep(step)) {
        round.steps.add(step);
      }

      // Worker-gesteuerter Abschluss
      final bool wantClosure =
          _safeBool(turn, ['mood', 'prompt']) ||
          _safeBool(turn, ['flow', 'mood_prompt']) ||
          _safeBool(turn, ['flow', 'recommend_end']);
      if (wantClosure) round.allowClosure = true;

      final hasHelpers = step.followups.isNotEmpty;
      _chipMode = (step.expectsAnswer || hasHelpers)
          ? _ChipMode.answer
          : _ChipMode.none;
    });

    _fadeSlideCtrl.forward(from: 0);
    _scrollToBottom();
    _focusInput();

    // Nur wenn der Worker es möchte → Abschluss anfordern (Mood anzeigen)
    final bool wantClosure =
        _safeBool(turn, ['mood', 'prompt']) ||
        _safeBool(turn, ['flow', 'mood_prompt']) ||
        _safeBool(turn, ['flow', 'recommend_end']);
    if (wantClosure) {
      unawaited(
          _requestClosureFromWorker(round: round, userAnswer: userAnswer));
    }

    setState(() => loading = false);
  }

  void _handleTurnError(ReflectionRound round) {
    // Robuster Fehlerpfad: keine Frage stellen, keine Chips – nur kurzer Mirror
    _toast(_errorHint);
    const fallbackMirror = 'Ich höre dich. Ich bleibe bei dir.';
    final step = _PandaStep(
      mirror: _capChars(fallbackMirror, kMirrorMaxChars),
      question: '', // KEINE Frage im Fehlerpfad
      talkLines: const <String>[],
      risk: false,
      followups: const <String>[],
    );
    setState(() {
      round.steps.add(step);
      round.allowClosure = false; // Fallback: nie sofort abschließen
      _chipMode = _ChipMode.none; // keine Antwortchips im Fehlerpfad
    });
    _fadeSlideCtrl.forward(from: 0);
    _scrollToBottom();
  }

  // ---------------- Turn → Step (direkt & schlank) ---------------------------
  _PandaStep _buildStepFromTurn(dynamic t) {
    // Closure-Signal respektieren: keine Frage/Chips, wenn Worker Abschluss möchte
    final bool isClosure =
        _safeBool(t, ['mood', 'prompt']) ||
        _safeBool(t, ['flow', 'mood_prompt']) ||
        _safeBool(t, ['flow', 'recommend_end']);

    final mirrorRaw = _coerceMirror(t).trim();
    final questionRaw = _coerceQuestion(t);

    final level = _safeString(t, ['risk_level']).toLowerCase();
    // Treat "mild" like "high" for UI safety hint (per v12.1.3 policy)
    final risk = _safeBool(t, ['risk']) || level == 'high' || level == 'mild';

    // Answer-Helpers vom Worker holen (präferiert), sonst leer
    final helpers = isClosure ? <String>[] : _coerceAnswerHelpers(t).take(3).toList();

    // talk[] optional mitnehmen (Anzeige abhängig von Widgets-Part)
    final talk = _safeStringList(t, ['talk']).take(2).toList();

    // Nur beim allerersten Schritt weich fallbacken,
    // sonst lieber keinen generischen Mirror zeigen.
    final bool isFirstEverStep = !_rounds.any((rr) => rr.steps.isNotEmpty);
    final effectiveMirror = mirrorRaw.isNotEmpty
        ? mirrorRaw
        : (isFirstEverStep ? 'Ich höre dich. Ich bleibe bei dir.' : '');

    // Frage nur setzen, wenn Worker nicht in Closure ist
    final q = isClosure ? '' : questionRaw;

    return _PandaStep(
      mirror: _capChars(effectiveMirror, kMirrorMaxChars),
      question: _limitWords(
        (q.isNotEmpty ? q : ''), // kein generischer Frage-Fallback mehr
        kQuestionMaxWords,
      ),
      talkLines: talk,
      risk: risk,
      followups: helpers,
    );
  }

  // ---------------- Speichern (JournalEntry) ---------------------------------
  Future<void> _saveRound(ReflectionRound r) async {
    if (r.entryId != null) {
      _toast('Bereits gespeichert.');
      return;
    }
    if (!r.answered) {
      _toast('Bitte zuerst deine Antwort schreiben.');
      return;
    }
    if (!r.allowClosure) {
      _toast('Wir sind noch nicht ganz fertig. Gleich geht’s weiter.');
      return;
    }
    if (!r.hasMood) {
      _toast('Bitte wähle noch kurz deine Stimmung.');
      return;
    }

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

    _toast('Im Gedankenbuch gespeichert.');
    _showPostSheet();
  }

  // ---------------- Löschen ---------------------------------------------------
  Future<void> _deleteRound(ReflectionRound r) async {
    setState(() {
      _rounds.removeWhere((x) => x.id == r.id);
      _chipMode = _rounds.isEmpty ? _ChipMode.starter : _ChipMode.none;
    });
    _toast('Gelöscht.');
  }

  // ---------------- Abschluss/Mood-Einleitung: vom Worker --------------------
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

    if (closure.isEmpty) {
      // Selbst wenn kein Text kam, lassen wir allowClosure an, wenn der Worker es wollte.
      round.allowClosure = true;
      return;
    }

    final _PandaStep closureStep = _PandaStep(
      mirror: _capChars(closure, kMirrorMaxChars),
      question: '', // keine Erwartung – Worker steuert Mood danach
      talkLines: const <String>[],
      risk: risk || (round.steps.isNotEmpty ? round.steps.last.risk : false),
    );

    setState(() {
      round.steps.add(closureStep);
      round.allowClosure = true; // endgültig freigeben
    });
    _fadeSlideCtrl.forward(from: 0);
    _scrollToBottom();
  }

  // --- Coercion helpers -------------------------------------------------------
  String _coerceMirror(dynamic t) {
    // Robuster Pfad-Satz über gängige Worker-Varianten (keine output_text-Fallbacks)
    final paths = <List<String>>[
      // Primärfelder, die echte Spiegel enthalten
      ['mirror'],
      ['reply'],

      // Abwärtskompatible Varianten früherer Worker
      ['text'],
      ['closure', 'text'],
      ['mood_intro', 'text'],

      // verschachtelte Altformen
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
        // Fragen sind kein Mirror → überspringen
        if (cleaned.endsWith('?')) continue;
        return cleaned;
      }
    }
    return '';
  }

  /// Entfernt nur Instruktions-Zeilen (z. B. „Unten findest du Antwort-Chips …“),
  /// ohne den eigentlichen Inhalt zu beschneiden.
  String _stripInstructionHints(String raw) {
    // Zeilenweise prüfen; nur bekannte Muster filtern.
    final lines = raw.split(RegExp(r'\r?\n'));
    final patterns = <RegExp>[
      // DE-Varianten
      RegExp(r'^\s*Unten\s+findest\s+du\s+Antwort[-\s]?Chips.*$', caseSensitive: false),
      RegExp(r'^\s*Unter\s+dem\s+Eingabefeld\s+findest\s+du\s+Antwort.*$', caseSensitive: false),
      RegExp(r'^\s*Wähle\s+einen\s+Antwort[-\s]?Chip.*$', caseSensitive: false),
      // EN-Varianten
      RegExp(r'^\s*You\s+can\s+use\s+the\s+answer\s+chips.*$', caseSensitive: false),
      RegExp(r"^\s*Below\s+you'll\s+find\s+answer\s+chips.*$", caseSensitive: false),
    ];

    bool matchesAny(String s) => patterns.any((p) => p.hasMatch(s));

    final kept = <String>[];
    for (final line in lines) {
      if (!matchesAny(line)) kept.add(line);
    }

    // Überzählige Leerzeilen normalisieren
    final joined = kept.join('\n').trim();
    return joined.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  String _coerceQuestion(dynamic t) {
    var q = _safeString(t, ['question']);
    if (q.isNotEmpty) return q;

    // Nur echte Fragenlisten berücksichtigen – keine followups/choices
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

  // Answer-Helpers (keine Fragen!)
  List<String> _coerceAnswerHelpers(dynamic t) {
    List<String> acc = [];
    void addAll(dynamic obj) {
      if (obj == null) return;

      // Primäre, worker-seitige Felder (bevorzugt)
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

    // Sanft säubern & deduplizieren (keine Quotes/?, max 72c, ohne Punkt)
    acc = acc.map(_sanitizeHelperText).where((s) => s.isNotEmpty).toList();

    final seen = <String>{};
    final deduped = <String>[];
    for (final s in acc) {
      if (seen.add(s.toLowerCase())) deduped.add(s);
      if (deduped.length >= 3) break; // max. 3 Chips
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

  // ---------------- Utils (minimal) ------------------------------------------

  /// Prüft, ob talk[] bereits einen 1–2-Sätze-Hinweis enthält.
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(color: Colors.white),
        ),
        backgroundColor: ZenColors.deepSage,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _showPostSheet() async {
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

    // NEW: Abschluss aktiv? (Mood-Phase UI-only Gate)
    // Policy v12.1.3: KEIN "answered" precondition.
    final bool closureActive = r != null &&
        r.allowClosure &&
        !(r.hasPendingQuestion) &&
        !(r.hasMood);

    final bool showAnswerHint =
        r != null &&
        r.hasPendingQuestion &&
        !closureActive &&
        !_talkContainsLengthHint(r.steps.isNotEmpty ? r.steps.last : null);

    final bool lastIsTyping = r != null && loading;

    final bool showStarter = _rounds.isEmpty && _chipMode == _ChipMode.starter;

    // Chips = Answer-Helpers (vom Worker); in der Mood-Phase strikt unterdrücken
    final bool showAnswerChips = !closureActive &&
        (r != null &&
            r.steps.isNotEmpty &&
            r.steps.last.followups.isNotEmpty) &&
        _chipMode == _ChipMode.answer;

    // Auswahl: Worker-Helpers → Fallback → Starter
    final List<String> answerTemplates = showAnswerChips
        ? r.steps.last.followups
        : ((!closureActive && (r?.hasPendingQuestion ?? false)) &&
                _chipMode == _ChipMode.answer)
            ? _fallbackAnswerHelpers()
            : (showStarter ? _starterChips() : const <String>[]);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: RawKeyboardListener(
        focusNode: _pageFocus,
        autofocus: true,
        onKey: _handleKey,
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
                // Backdrop (ruhig, weich)
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
                              0, 0, 0, 12 + _inputReserve + bottomInset,
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

                              // Intro – Single Bubble
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

                              // Verlauf
                              for (int index = 0;
                                  index < _rounds.length;
                                  index++)
                                KeyedSubtree(
                                  key: ValueKey(_rounds[index].id),
                                  child: Builder(
                                    builder: (_) {
                                      final child = _RoundThread(
                                        maxWidth: cardMaxW,
                                        round: _rounds[index],
                                        isLast: index == _rounds.length - 1,
                                        isTyping: index == _rounds.length - 1 &&
                                            lastIsTyping,
                                        onSave: (_rounds[index].answered &&
                                                _rounds[index].hasMood)
                                            ? () => _saveRound(_rounds[index])
                                            : null,
                                        onDelete: _rounds[index].answered &&
                                                _rounds[index].hasMood
                                            ? () => _deleteRound(
                                                _rounds[index])
                                            : null,
                                        onSelectMood: (score, label) async {
                                          setState(() {
                                            _rounds[index].moodScore = score;
                                            _rounds[index].moodLabel = label;
                                          });
                                          await _saveRound(_rounds[index]);
                                        },
                                        safetyText: _rounds[index]
                                                    .steps
                                                    .isNotEmpty &&
                                                _rounds[index]
                                                    .steps
                                                    .last
                                                    .risk
                                            ? _emergencyHint(context)
                                            : null,
                                      );

                                      if (index !=
                                          _rounds.length - 1) {
                                        return child;
                                      }

                                      return FadeTransition(
                                        opacity: _fadeSlideCtrl.drive(
                                          Tween(begin: 0.0, end: 1.0),
                                        ),
                                        child: SlideTransition(
                                          position: _fadeSlideCtrl.drive(
                                            Tween(
                                              begin:
                                                  const Offset(-0.03, 0),
                                              end: Offset.zero,
                                            ),
                                          ),
                                          child: child,
                                        ),
                                      );
                                    },
                                  ),
                                ),

                              // Hinweis (sanft) — nur wenn Frage offen & kein Abschluss
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

                              // CHIPS (Starter oder Antwort-Hilfen) – nicht in der Mood-Phase
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

                              // Permanenter Footer-Disclaimer (immer sichtbar)
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

                        // Bottom-Input (fix) – nutzt _InputBar aus Widgets-Part
                        SafeArea(
                          top: false,
                          child: Center(
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(maxWidth: cardMaxW),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    0, 6, 0, 8),
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

  // Fallback-Antwortchips als Satzstarter (keine Fragen)
  List<String> _fallbackAnswerHelpers() => const [
        'Ich merke gerade, dass … ',
        'Der schwierigste Moment war … ',
        'Ein kleiner nächster Schritt wäre … ',
      ];

  // Chip-Text einfügen: „… “ (Ellipsis + Space) am Ende bewahren/erzwingen
  void _onTapChip(String text, {required bool isAnswerTemplate}) {
    // Fragezeichen entfernen, Innenräume normalisieren – Ending „… “ bewahren/setzen.
    final original = text;
    final endsWithEllipsisSpace = RegExp(r'…\s$').hasMatch(original);
    var t = original.replaceAll(RegExp(r'[?？]+$'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (endsWithEllipsisSpace || t.endsWith('…')) t = '$t ';
    // Guard: falls Library-Chip nur „…“ ohne Space liefert.
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
    return 680; // Reflection max width
  }

  String _emergencyHint(BuildContext context) {
    return 'Wenn es sich akut belastend anfühlt: Sprich mit jemandem, '
        'dem du vertraust. In Notfällen wende dich sofort an lokale '
        'Hilfsangebote oder den Notruf.';
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
}

// ============================== Extensions ===================================
extension _Utc on DateTime {
  DateTime toUtcDateTime() => isUtc ? this : toUtc();
}
