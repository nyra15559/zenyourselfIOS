// lib/features/reflection/reflection_screen.dart
//
// ReflectionScreen — Panda v3.0 (calm, talk-ready, typing, Undo, PandaMoodPicker)
// -----------------------------------------------------------------------------
// Kernideen:
// • Eine Reflexion = eine Bubble („Round“) mit beliebig vielen Panda-Schritten.
// • Schritt: Spiegel (2–6 Sätze, kein Rat) + genau 1 Leitfrage ODER kurzer Warm-Talk.
// • Followups: dezente Chips als Starthilfe (setzen Text in die Eingabe).
// • Flow: Deine Gedanken → Frage → Deine Antwort → Mood → Save.
// • Dedupe: Spiegel/Talk/Frage bereinigt, keine Dopplungen.
// • Typing: dezenter „Panda tippt…“-Indikator während loading.
// • Undo: Nach Antwort SnackBar mit „Rückgängig“.
// • Safe Ticker: Controller in initState erzeugt, in dispose entsorgt.
// • Mood: Panda-Mood-Picker (Bottom Sheet) → score 0..4 + Label.
//
// Abhängigkeiten im Projekt vorhanden:
//   ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, ZenColors, ZenRadii
//   GuidanceService (startSession/continueSession[+optional talk()])
//   SpeechService, JournalEntriesProvider / JournalEntry
//   PandaMood + PandaMoodPicker (lib/models/panda_mood.dart, lib/widgets/panda_mood_picker.dart)
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/zen_style.dart' hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart'
    show ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader;

// Panda-Moods
import '../../models/panda_mood.dart';
import '../../widgets/panda_mood_picker.dart';

// ⚠️ Wichtig: Auf das KANONISCHE Model wechseln (nicht mehr data/journal_entry.dart).
import '../../models/journal_entry.dart' as jm;
import '../../providers/journal_entries_provider.dart';

import '../../services/guidance_service.dart';
import '../../services/speech_service.dart';

// ---------------- Panda Step --------------------------------------------------
class _PandaStep {
  final String mirror;           // 2–6 Sätze, warm & kontexttreu
  final String question;         // genau 1 Frage (leer => Talk-only)
  final List<String> talkLines;  // 0–2 kurze Sätze (Warm-Talk)
  final bool risk;               // Safety-Flag
  final List<String> followups;  // dezente Vorschläge (setzen Text)
  String? answer;                // Nutzer-Antwort

  _PandaStep({
    required this.mirror,
    required this.question,
    this.talkLines = const [],
    this.followups = const [],
    this.risk = false,
    this.answer,
  });

  bool get hasAnswer => (answer ?? '').trim().isNotEmpty;
  bool get expectsAnswer => question.trim().isNotEmpty;
}

// ---------------- Round Model -------------------------------------------------
class ReflectionRound {
  final String id;
  final DateTime ts;
  final String mode;       // 'text' | 'voice'
  String userInput;        // O-Ton (Start der Runde)
  final List<_PandaStep> steps;
  String? entryId;

  // Mood nach Nutzer-Antwort (0..4) + Label
  int? moodScore;
  String? moodLabel;

  ReflectionRound({
    required this.id,
    required this.ts,
    required this.mode,
    required this.userInput,
    List<_PandaStep>? steps,
    this.entryId,
    this.moodScore,
    this.moodLabel,
  }) : steps = steps ?? <_PandaStep>[];

  bool get hasPendingQuestion {
    if (steps.isEmpty) return false;
    final last = steps.last;
    return last.expectsAnswer && !last.hasAnswer;
  }

  bool get answered => steps.any((s) => s.hasAnswer);
  bool get hasMood => moodScore != null;

  Set<String> get normalizedQuestions {
    final out = <String>{};
    for (final s in steps) {
      final q = s.question.trim();
      if (q.isNotEmpty) out.add(_ReflectionScreenState.normalizeForCompare(q));
    }
    return out;
  }
}

// ---------------- Optionaler Hook --------------------------------------------
typedef AddToGedankenbuch = void Function(
  String text,
  String mood, {
  bool isReflection,
  String? aiQuestion,
});

// ---------------- Screen ------------------------------------------------------
class ReflectionScreen extends StatefulWidget {
  final AddToGedankenbuch? onAddToGedankenbuch;
  final String? initialUserText;

  const ReflectionScreen({super.key, this.onAddToGedankenbuch, this.initialUserText});

  @override
  State<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends State<ReflectionScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _animShort = Duration(milliseconds: 240);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _pageFocus = FocusNode();
  final ScrollController _listCtrl = ScrollController();

  late final AnimationController _fadeSlideCtrl;

  final SpeechService _speech = SpeechService();
  StreamSubscription<String>? _finalSub;

  final List<ReflectionRound> _rounds = <ReflectionRound>[];
  ReflectionRound? get _current => _rounds.isEmpty ? null : _rounds.last;

  /// Worker-Session (GuidanceService.ReflectionSession ODER Map – dynamic für Toleranz)
  dynamic _session;
  bool loading = false;

  String get _errorHint => GuidanceService.instance.errorHint;
  String get _loadingHint => GuidanceService.instance.loadingHint;

  // Für Undo
  String? _lastSentAnswer; // zwischenspeichern
  int? _lastAnsweredStepIndex;

  @override
  void initState() {
    super.initState();

    _fadeSlideCtrl = AnimationController(vsync: this, duration: _animShort);

    // Live-Transkript → Eingabe
    _finalSub = _speech.transcript$.listen((t) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cur = _controller.text.trim();
        final joined = (cur.isEmpty ? t : '$cur\n$t').trim();
        _controller.text = joined;
        _controller.selection =
            TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
        FocusScope.of(context).requestFocus(_inputFocus);
      });
    });

    // Optionaler Auto-Start
    final seed = (widget.initialUserText ?? '').trim();
    if (seed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _startNewReflection(userText: seed, mode: 'text');
      });
    }
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
    // ESC → Mic stoppen
    if (e.logicalKey == LogicalKeyboardKey.escape && _speech.isRecording) {
      _toggleRecording();
      return KeyEventResult.handled;
    }

    final isEnter = e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter;
    final withCtrlOrCmd = e.isControlPressed || e.isMetaPressed;
    final withShift = e.isShiftPressed;

    // Cmd/Ctrl+Enter: immer senden
    if (withCtrlOrCmd && isEnter && !loading) {
      _send();
      return KeyEventResult.handled;
    }

    // Enter = Send, Shift+Enter = Zeilenumbruch
    if (isEnter && !withShift && !loading) {
      _send();
      return KeyEventResult.handled; // verhindert Newline
    }

    return KeyEventResult.ignored;
  }

  // ---------------- Actions ---------------------------------------------------
  Future<void> _toggleRecording() async {
    try {
      if (_speech.isRecording) {
        await _speech.stop();
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_inputFocus);
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
    final text = _controller.text.trim();
    if (text.isEmpty || loading) return;

    if (_current == null) {
      await _startNewReflection(userText: text, mode: _speech.isRecording ? 'voice' : 'text');
      return;
    }

    if (_current!.hasPendingQuestion) {
      // Antwort übernehmen + Undo anbieten
      setState(() {
        _current!.steps.last.answer = text;
        _lastSentAnswer = text;
        _lastAnsweredStepIndex = _current!.steps.length - 1;
        _controller.clear();
      });
      _scrollToBottom();
      _showUndoForAnswer();
      FocusScope.of(context).requestFocus(_inputFocus);
      return;
    }

    await _startNewReflection(userText: text, mode: _speech.isRecording ? 'voice' : 'text');
  }

  void _undoLastAnswer() {
    final r = _current;
    if (r == null) return;
    final i = _lastAnsweredStepIndex;
    if (i == null || i < 0 || i >= r.steps.length) return;

    final was = _lastSentAnswer ?? '';
    setState(() {
      r.steps[i].answer = null;
      _controller.text = was;
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    });
    FocusScope.of(context).requestFocus(_inputFocus);
  }

  void _showUndoForAnswer() {
    final snack = SnackBar(
      content: const Text('Antwort gespeichert'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: _undoLastAnswer,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(ZenRadii.m)),
      backgroundColor: ZenColors.deepSage,
    );
    ScaffoldMessenger.of(context).showSnackBar(snack);
  }

  // Talk-Push (Panda weiterreden)
  Future<void> _talkOnly() async {
    final r = _current;
    if (r == null || _session == null || loading) return;

    setState(() => loading = true);
    try {
      dynamic turn;
      final lastText = r.steps.isNotEmpty ? (r.steps.last.answer ?? r.userInput) : r.userInput;

      // bevorzugt: GuidanceService.talk(); Fallback: continueSession
      try {
        final dyn = GuidanceService.instance as dynamic;
        turn = await dyn.talk(
          session: _session,
          userText: lastText,
          locale: 'de',
          tz: 'Europe/Zurich',
        );
      } catch (_) {
        turn = await GuidanceService.instance.continueSession(
          session: _session,
          text: lastText,
          locale: 'de',
          tz: 'Europe/Zurich',
        );
      }

      final step = _buildStepFromTurn(
        turn,
        userText: r.userInput,
        round: r,
        smallTalkHint: false,
      );
      setState(() {
        _session = _turnSession(turn);
        r.steps.add(step);
      });

      _fadeSlideCtrl.forward(from: 0);
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // --- Start: neue Reflexion -------------------------------------------------
  Future<void> _startNewReflection({required String userText, required String mode}) async {
    setState(() => loading = true);
    try {
      final round = ReflectionRound(
        id: _makeId(),
        ts: DateTime.now(),
        mode: mode,
        userInput: userText,
      );
      setState(() {
        _rounds.add(round);
        _controller.clear();
      });
      _scrollToBottom();

      final bool smallTalk = _looksLikeSmallTalk(userText);

      dynamic turn;
      try {
        turn = await GuidanceService.instance.startSession(
          text: userText,
          locale: 'de',
          tz: 'Europe/Zurich',
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => round.steps.add(_PandaStep(
              mirror: _ensureMirrorSentences(_fallbackMirror(userText)),
              question: _limitWords(_errorHint, 30),
            )));
        return;
      }

      final step = _buildStepFromTurn(
        turn,
        userText: userText,
        round: round,
        smallTalkHint: smallTalk,
      );
      setState(() {
        _session = _turnSession(turn);
        round.steps.add(step);
      });

      _fadeSlideCtrl.forward(from: 0);
      _scrollToBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_inputFocus);
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // --- Continue in derselben Bubble ------------------------------------------
  Future<void> _continueWithinCurrent() async {
    final r = _current;
    if (r == null || _session == null) return;
    if (r.hasPendingQuestion) {
      _toast('Bitte zuerst kurz antworten.');
      return;
    }

    setState(() => loading = true);
    try {
      final lastAns = r.steps.last.answer?.trim() ?? '';
      dynamic turn;
      try {
        turn = await GuidanceService.instance.continueSession(
          session: _session,
          text: lastAns,
          locale: 'de',
          tz: 'Europe/Zurich',
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => r.steps.add(_PandaStep(
              mirror: _ensureMirrorSentences('Das stockt kurz. Ich bleibe geduldig bei dir.'),
              question: _limitWords(_errorHint, 30),
            )));
        return;
      }

      final step = _buildStepFromTurn(
        turn,
        userText: r.userInput,
        round: r,
        smallTalkHint: false,
      );
      setState(() {
        _session = _turnSession(turn);
        r.steps.add(step);
      });

      _fadeSlideCtrl.forward(from: 0);
      _scrollToBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_inputFocus);
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
    if (!r.hasMood) {
      _toast('Bitte wähle noch kurz deine Stimmung.');
      return;
    }

    final String lastAns = r.steps
        .map((e) => (e.answer ?? '').trim())
        .where((s) => s.isNotEmpty)
        .fold<String>('', (prev, cur) => cur.isNotEmpty ? cur : prev);

    final String textForCard = lastAns.isNotEmpty ? lastAns : r.userInput.trim();

    final String entryId = r.id;
    final DateTime ts = r.ts.toUtc();

    // Titel-Logik: zuerst Antwort, sonst Leitfrage, sonst Auto-Name
    final String title = _autoTitleForRound(r, fallback: _autoSessionName(r.userInput));

    // Tags: Reflection + Stimmung + Input-Modus (für Metriken & Filter)
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
      // String statt Map (Model erwartet String?)
      'sourceRef': 'reflection|session:${_session?.toString() ?? ''}',
    };

    final entry = jm.JournalEntry.fromMap(entryMap);

    final prov = context.read<JournalEntriesProvider>();
    final List<jm.JournalEntry> existing = List<jm.JournalEntry>.from(prov.entries);
    existing.add(entry);
    prov.replaceAll(existing);

    setState(() => r.entryId = entryId);
    widget.onAddToGedankenbuch?.call(
      textForCard,
      (r.moodLabel ?? 'Neutral').trim(),
      isReflection: true,
      aiQuestion: r.steps.isNotEmpty ? r.steps.first.question : null,
    );

    _toast('Ins Gedankenbuch gespeichert.');
  }

  // ---------------- Entwurf ---------------------------------------------------
  Future<void> _saveDraft(ReflectionRound r) async {
    final draftName = _autoSessionName(r.userInput);
    _toast('Als Entwurf gemerkt: "$draftName"');
  }

  String _autoTitleForRound(ReflectionRound r, {required String fallback}) {
    // 1) erste vorhandene Antwort
    for (final s in r.steps) {
      final a = (s.answer ?? '').trim();
      if (a.isNotEmpty) return _firstWords(a, 10);
    }
    // 2) Leitfrage
    if (r.steps.isNotEmpty && r.steps.first.question.trim().isNotEmpty) {
      return _firstWords(r.steps.first.question.trim(), 12);
    }
    // 3) Fallback
    return fallback;
  }

  String _autoSessionName(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'Reflexion';
    const max = 36;
    return clean.length <= max ? clean : '${clean.substring(0, max)}…';
  }

  String _firstWords(String s, int n) {
    final words = s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= n) return s.trim();
    return '${words.take(n).join(' ')}…';
  }

  // ---------------- Turn → Step Mapping --------------------------------------
  _PandaStep _buildStepFromTurn(
    dynamic t, {
    required String userText,
    required ReflectionRound round,
    required bool smallTalkHint,
  }) {
    // Rohdaten aus Turn
    final rawMirror = _turnMirror(t).trim();
    final rawTalk = _turnTalk(t);
    final questions = _turnQuestions(t);
    final followups = _turnFollowups(t);
    final out1 = _turnString(t, 'outputText');
    final out2 = _turnString(t, 'output_text');

    // Mirror
    final mirrorRaw = rawMirror.isNotEmpty ? rawMirror : _fallbackMirror(userText);
    var mirror = _ensureMirrorSentences(mirrorRaw);

    // Talk
    final List<String> talk = rawTalk.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    // Frage
    final String qRaw =
        (questions.isNotEmpty ? questions.first : (out1.isNotEmpty ? out1 : out2)).trim();
    String? sanitized = _sanitizeQuestion(qRaw);

    // Smalltalk-Hinweis
    final bool isSmallTalk = smallTalkHint || _looksLikeSmallTalk(userText);
    if (isSmallTalk && talk.isEmpty) {
      talk.addAll(<String>[
        'Mir geht’s gut. Danke, dass du fragst.',
        'Es klingt, als hättest du ein feines Gespür dafür.'
      ]);
      sanitized ??= 'Was hat dich heute dazu gebracht, gerade das zu fragen?';
    }

    // Fallback-Frage (empathisch, ohne Zitat „Wenn du auf …“)
    final String baseQuestion =
        sanitized ?? _contextualFallbackQuestion(userText, hintFromMirror: mirror);

    // Miniguard
    final String question = _makeUniqueQuestion(baseQuestion, round, userText, mirror);

    // DEDUPE: Spiegel/Talk/Frage aufräumen
    final cleanedTalk = _dedupeTalk(talk, mirror, question);
    mirror = _dedupeMirror(mirror, question, cleanedTalk);

    // Risk
    final riskLevel = _turnString(t, 'risk_level').toLowerCase();
    final flow = _turnFlow(t);
    final bool risk = _turnBool(t, 'risk') || riskLevel == 'high' || (flow?['risk_notice'] == 'safety');

    // Followups (sanft, max. 3, keine Duplikate zur Frage)
    final fu = followups
        .map(_sanitizeQuestion)
        .whereType<String>()
        .where((s) => normalizeForCompare(s) != normalizeForCompare(question))
        .toSet()
        .toList()
        .take(3)
        .toList();

    return _PandaStep(
      mirror: mirror,
      question: _limitWords(question, 30),
      talkLines: cleanedTalk,
      followups: fu,
      risk: risk,
    );
  }

  // ---------------- Safe Turn Accessors --------------------------------------
  String _turnString(dynamic t, String key) {
    if (t is Map && t[key] is String) return t[key] as String;
    try {
      final d = t as dynamic;
      switch (key) {
        case 'mirror':
          final s = d.mirror;
          if (s is String) return s;
          break;
        case 'outputText':
          final s = d.outputText;
          if (s is String) return s;
          break;
        case 'output_text':
          final s = d.output_text;
          if (s is String) return s;
          break;
        case 'risk_level':
          final s = d.risk_level;
          if (s is String) return s;
          break;
      }
    } catch (_) {}
    // try toJson
    try {
      final v = (t as dynamic).toJson?.call();
      if (v is Map && v[key] is String) return v[key] as String;
    } catch (_) {}
    return '';
  }

  List<String> _turnQuestions(dynamic t) {
    if (t is Map && t['questions'] is List) {
      return (t['questions'] as List).map((e) => e.toString()).toList();
    }
    try {
      final q = (t as dynamic).questions;
      if (q is List) return q.map((e) => e.toString()).toList();
    } catch (_) {}
    return const <String>[];
  }

  List<String> _turnFollowups(dynamic t) {
    if (t is Map) {
      final d = (t['followups'] ?? t['follow_up'] ?? t['followup_questions']);
      if (d is List) return d.map((e) => e.toString()).toList();
    }
    try {
      final f = (t as dynamic).followups;
      if (f is List) return f.map((e) => e.toString()).toList();
    } catch (_) {}
    return const <String>[];
  }

  String _turnMirror(dynamic t) => _turnString(t, 'mirror');

  List<String> _turnTalk(dynamic t) {
    if (t is Map && t['talk'] is List) {
      return (t['talk'] as List).map((e) => e.toString()).toList();
    }
    try {
      final tl = (t as dynamic).talk;
      if (tl is List) return tl.map((e) => e.toString()).toList();
    } catch (_) {}
    return const <String>[];
  }

  Map<String, dynamic>? _turnFlow(dynamic t) {
    if (t is Map && t['flow'] is Map) {
      return Map<String, dynamic>.from(t['flow'] as Map);
    }
    try {
      final f = (t as dynamic).flow;
      if (f is Map) return Map<String, dynamic>.from(f);
    } catch (_) {}
    return null;
  }

  dynamic _turnSession(dynamic t) {
    if (t is Map) return t['session'];
    try {
      return (t as dynamic).session;
    } catch (_) {
      return null;
    }
  }

  bool _turnBool(dynamic t, String key) {
    if (t is Map && t[key] is bool) return t[key] as bool;
    try {
      final d = t as dynamic;
      switch (key) {
        case 'risk':
          final b = d.risk;
          if (b is bool) return b;
          break;
      }
    } catch (_) {}
    return false;
  }

  // ---------------- Dedupe / Text-Hilfen -------------------------------------
  String _normalizeLine(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[„“"»«]'), '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<String> _splitSentences(String text) => text
      .replaceAll('\n', ' ')
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  String _dedupeMirror(String mirror, String question, List<String> talk) {
    final qn = _normalizeLine(question);
    final talkN = talk.map(_normalizeLine).toSet();
    final seen = <String>{};

    final parts = _splitSentences(mirror);
    final out = <String>[];
    for (final s in parts) {
      final n = _normalizeLine(s);
      if (n.isEmpty) continue;
      if (n == qn) continue;           // Frage gehört nicht in den Spiegel
      if (talkN.contains(n)) continue; // Talk nicht doppeln
      if (seen.add(n)) out.add(s);
    }

    if (out.isEmpty) {
      out.add('Ich höre dich.');
      out.add('Ich bleibe bei dir.');
    } else if (out.length == 1) {
      out.add('Ich lese das aufmerksam mit.');
    }
    if (out.length > 6) {
      return out.take(6).join(' ');
    }
    return out.join(' ');
  }

  List<String> _dedupeTalk(List<String> talk, String mirror, String question) {
    final mirrorSet = _splitSentences(mirror).map(_normalizeLine).toSet();
    final qn = _normalizeLine(question);
    final seen = <String>{};
    final out = <String>[];

    for (final line in talk) {
      final n = _normalizeLine(line);
      if (n.isEmpty) continue;
      if (n == qn) continue;                // keine Frage als Talk
      if (mirrorSet.contains(n)) continue;  // nicht Spiegel wiederholen
      if (seen.add(n)) out.add(line.trim());
      if (out.length >= 2) break;           // max. 2 Talk-Lines
    }
    return out;
  }

  // ---------------- Mirror / Frage / Limits ----------------------------------
  String _ensureMirrorSentences(String text) {
    final normalized = text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'Ich höre dich. Ich bleibe bei dir.';
    }
    final parts = _splitSentences(normalized);
    if (parts.length == 1) {
      parts.add('Ich lese das aufmerksam mit.');
    }
    final capped = parts.length <= 6 ? parts : parts.sublist(0, 6);
    return capped.join(' ');
  }

  String _fallbackMirror(String userText) {
    final s = userText.trim();
    if (s.isEmpty) return 'Klingt, als würde dich das gerade beschäftigen. Ich bin hier.';
    final short = s.replaceAll('\n', ' ').trim();
    final clipped = short.length > 120 ? '${short.substring(0, 120)}…' : short;
    return 'Ich höre: „$clipped“. Ich bleibe bei dir.';
  }

  String? _sanitizeQuestion(String? raw) {
    if (raw == null) return null;
    var txt = raw.trim();
    if (txt.isEmpty) return null;

    txt = txt.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Prefix-Schablonen (Neutralisierung)
    txt = txt.replaceFirst(
      RegExp(
        "^\\s*(im blick auf|bezogen auf|in bezug auf|im fokus|zum thema|thema|aspekt)\\s*[:\\-–—]?\\s*(?:[\"\\'])?.+?(?:[\"\\'])?\\s*[:,\\-–—]?\\s*",
        caseSensitive: false,
      ),
      '',
    );

    final lower = txt.toLowerCase();
    final bool generic = <RegExp>[
      RegExp(r'wie\s+fühlst\s+du\s+dich'),
      RegExp(r'wie\s+fühlt\s+ es\s+sich'),
      RegExp(r'wie\s+geht\s+es\s+dir'),
      RegExp(r'worum\s+geht\s+es\s+dir'),
      RegExp("^\\s*was\\s+ist\\s+dir\\s+an\\s+[\"\\']?.+?[\"\\']?\\s+(?:gerade\\s+)?am\\s+wichtigsten\\??\\s*\$"),
      RegExp("^\\s*was\\s+ist\\s+dir\\s+daran\\s+(?:gerade\\s+)?am\\s+wichtigsten\\??\\s*\$"),
    ].any((p) => p.hasMatch(lower));
    if (generic) return null;

    // Nebensatz-Klammern am Ende fein säubern
    txt = txt.replaceAll(
      RegExp("\\s*[—–\\-,:;]\\s*wenn\\s+du\\s+an\\s+.+?\\s+denkst\\s*\$", caseSensitive: false),
      '',
    );

    txt = _sanitizeDots(txt);
    if (!txt.endsWith('?') && !txt.endsWith('…')) txt = '$txt?';
    return txt.trim();
  }

  String _sanitizeDots(String s) {
    var x = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    final sentences =
        x.split(RegExp(r'(?<=[.!?])\s+')).where((t) => t.trim().isNotEmpty).toList();
    final capped = sentences.take(2).join(' ');
    final ell = capped
        .replaceAll(RegExp(r'\.{3,}'), '…')
        .replaceAll(RegExp(r'…{2,}'), '…');
    final cleaned = ell
        .replaceAllMapped(RegExp(r'\s+([?!.,;:])'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'([?!.,;:])(?!\s|$)'), (m) => '${m.group(1)} ');
    return cleaned.trim();
  }

  String _limitWords(String input, int maxWords) {
    final words = input.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= maxWords) return input.trim();
    return '${words.take(maxWords).join(' ')}…';
  }

  // Neue empathische Fallback-Frage, ohne Zitat-Klammer
  String _contextualFallbackQuestion(String userText, {required String hintFromMirror}) {
    final t = (userText.isNotEmpty ? userText : hintFromMirror).toLowerCase();

    final bool lowEnergy = RegExp(r'(erschöpft|überforder|müde|kraft\s*fehl|niedergeschlagen|nicht\s+so\s+toll)')
        .hasMatch(t);
    final bool anger = RegExp(r'(wut|ärger|sauer|genervt)').hasMatch(t);
    final bool anxiety = RegExp(r'(angst|sorge|nervös|unsicher|panik)').hasMatch(t);
    final bool positive = RegExp(r'(freu|stolz|dankbar|gut|leicht|hell)').hasMatch(t);

    if (lowEnergy) return 'Magst du erzählen, was dich gerade am meisten bedrückt?';
    if (anger) return 'Was genau daran hat dich am stärksten getroffen?';
    if (anxiety) return 'Welche Sorge meldet sich im Moment am deutlichsten?';
    if (positive) return 'Was daran tut dir gerade besonders gut?';
    return 'Was ist dir daran im Moment am wichtigsten?';
  }

  String _makeUniqueQuestion(String q, ReflectionRound round, String userText, String mirror) {
    final norm = normalizeForCompare(q);
    final used = round.normalizedQuestions;
    if (!used.contains(norm)) return q;

    final alt = _contextualFallbackQuestion(userText, hintFromMirror: mirror);
    final altNorm = normalizeForCompare(alt);
    if (!used.contains(altNorm)) return alt;

    final variants = <String>[
      'Welcher kleine nächste Schritt fühlt sich stimmig an?',
      'Was wäre ein hilfreicher erster Satz dazu?',
      'Womit möchtest du kurz beginnen?',
    ];
    for (final v in variants) {
      final vv = _sanitizeDots(_limitWords(v, 30));
      if (!used.contains(normalizeForCompare(vv))) return vv;
    }
    return q;
  }

  static String normalizeForCompare(String s) {
    final lower = s.toLowerCase();
    return lower.replaceAll(RegExp("[^a-z0-9\\u00C0-\\u017F]+"), '');
  }

  bool _looksLikeSmallTalk(String text) {
    final t = text.toLowerCase().trim();
    final hello = RegExp(r'\b(hallo|hey|hi|na)\b').hasMatch(t);
    final howAreYou =
        RegExp(r"(wie\s+geht(?:'|’)?s\s+dir|wie\s+geht\s+ es\s+dir|wie\s+geht\s+es\s+dir|alles\s+gut)").hasMatch(t);
    final pandaMention = RegExp(r'\bpanda\b').hasMatch(t);
    return howAreYou || (pandaMention && hello);
  }

  // ---------------- Misc ------------------------------------------------------
  String _makeId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = Random().nextInt(0xFFFF);
    return 'j_${now}_$r';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listCtrl.hasClients) return;
      _listCtrl.animateTo(
        _listCtrl.position.maxScrollExtent,
        duration: _animShort,
        curve: Curves.easeOut,
      );
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white),
        ),
        backgroundColor: ZenColors.deepSage,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(ZenRadii.m),
        ),
      ),
    );
  }

  // ---------------- Build -----------------------------------------------------
  String get _headerTitle => 'Ordne deine Gedanken';
  String get _headerSubtitle => 'Ich bin hier.';

  @override
  Widget build(BuildContext context) {
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final double w = MediaQuery.of(context).size.width;
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final double cardMaxW = _cardMaxWidthFor(w);

    final r = _current;

    final bool lastCanContinue =
        r != null && r.answered && !r.hasPendingQuestion && !loading;

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
          appBar: const ZenAppBar(title: '', showBack: true),
          body: Stack(
            children: [
              const Positioned.fill(
                child: ZenBackdrop(
                  asset: 'assets/flusspanda.png',
                  alignment: Alignment.centerRight,
                  glow: .38,
                  vignette: .12,
                  enableHaze: true,
                  hazeStrength: .16,
                  saturation: .94,
                  wash: .08,
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + (bottomInset > 0 ? 6 : 20)),
                  child: Column(
                    children: [
                      PandaHeader(
                        title: _headerTitle,
                        caption: _headerSubtitle,
                        pandaSize: w < 470 ? 88 : 112,
                        strongTitleGreen: true,
                      ),
                      const SizedBox(height: 10),

                      if (_rounds.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: cardMaxW),
                              child: const FractionallySizedBox(
                                widthFactor: 1,
                                child: _IntroCard(),
                              ),
                            ),
                          ),
                        ),

                      Expanded(
                        child: ListView.builder(
                          controller: _listCtrl,
                          padding: const EdgeInsets.only(bottom: 6),
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: _rounds.length,
                          itemBuilder: (context, index) {
                            final round = _rounds[index];
                            final isLast = index == _rounds.length - 1;

                            final canContinue = isLast ? lastCanContinue : false;
                            // Save erst nach Mood
                            final canSave = round.answered && round.hasMood;

                            return KeyedSubtree(
                              key: ValueKey(round.id),
                              child: FadeTransition(
                                opacity: _fadeSlideCtrl.drive(Tween(begin: 0.0, end: 1.0)),
                                child: SlideTransition(
                                  position: _fadeSlideCtrl.drive(
                                    Tween(begin: const Offset(-0.03, 0), end: Offset.zero),
                                  ),
                                  child: _RoundBubble(
                                    maxWidth: cardMaxW,
                                    round: round,
                                    onContinue: canContinue ? _continueWithinCurrent : null,
                                    onSave: canSave ? () => _saveRound(round) : null,
                                    onLater: round.answered ? () => _saveDraft(round) : null,
                                    safetyText: round.steps.isNotEmpty && round.steps.last.risk
                                        ? _emergencyHint(context)
                                        : null,
                                    onPickFollowup: (s) {
                                      _controller.text = s;
                                      _controller.selection = TextSelection.fromPosition(
                                        TextPosition(offset: _controller.text.length),
                                      );
                                      FocusScope.of(context).requestFocus(_inputFocus);
                                    },
                                    onMoodSelected: (score, label) {
                                      setState(() {
                                        round.moodScore = score;
                                        round.moodLabel = label;
                                      });
                                    },
                                    isTyping: isLast && loading, // << Panda tippt
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 8),

                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: cardMaxW),
                          child: _InputBar(
                            focusNode: _inputFocus,
                            controller: _controller,
                            hint: _inputHint(),
                            onSend:  loading ? null : _send,
                            onTalk:  loading ? null : _talkOnly,
                            canSend: !loading,
                            onMicTap: loading ? null : _toggleRecording,
                            isRecording: _speech.isRecording,
                            trailingHint: loading ? _loadingHint : null,
                          ),
                        ),
                      ),

                      if (loading)
                        Padding(
                          padding: EdgeInsets.only(top: bottomInset > 0 ? 6 : 10),
                          child: const Center(child: CircularProgressIndicator()),
                        ),

                      SizedBox(height: bottomInset > 0 ? 6 : 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _inputHint() {
    final r = _current;
    if (r == null) return 'Worüber möchtest du heute sprechen?';
    if (r.hasPendingQuestion) return 'Schreib deine Antwort …';
    return 'Neue Reflexion beginnen — oder oben „Weiter reflektieren“.';
  }

  double _cardMaxWidthFor(double screenW) {
    if (screenW < 380) return screenW - 24;
    if (screenW < 480) return 420;
    if (screenW < 720) return 520;
    return 560;
  }

  String _emergencyHint(BuildContext context) {
    final loc = Localizations.localeOf(context);
    final cc = (loc.countryCode ?? '').toUpperCase();
    if (cc == 'DE') {
      return 'Es klingt herausfordernd. Wenn es sich überwältigend anfühlt, hol dir bitte Unterstützung vor Ort. '
          'Deutschland: 112 (Notruf), 110 (Polizei), TelefonSeelsorge 0800 111 0 111 / 0800 111 0 222. Du bist nicht allein.';
    } else if (cc == 'CH') {
      return 'Es klingt herausfordernd. Wenn es sich überwältigend anfühlt, hol dir bitte Unterstützung vor Ort. '
          'Schweiz: 112 (Notruf), 144 (Sanität), Dargebotene Hand 143. Du bist nicht allein.';
    } else if (cc == 'AT') {
      return 'Es klingt herausfordernd. Wenn es sich überwältigend anfühlt, hol dir bitte Unterstützung vor Ort. '
          'Österreich: 112 (Notruf), 144 (Rettung), TelefonSeelsorge 142. Du bist nicht allein.';
    }
    return 'Es klingt herausfordernd. Wenn es sich überwältigend anfühlt, hol dir bitte Unterstützung vor Ort. '
        'EU-Notruf 112 · USA/Kanada 911. Du bist nicht allein.';
  }
}

// ---------------- Intro Card -------------------------------------------------
class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return const ZenGlassCard(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      topOpacity: .26,
      bottomOpacity: .10,
      borderOpacity: .18,
      borderRadius: BorderRadius.all(ZenRadii.l),
      child: Text(
        'Hallo, ich bin ZenYourself – dein Panda. '
        'Du kannst mir deine Gedanken schreiben oder flüstern. '
        'Ich helfe dir, deine Gedanken zu ordnen und dich selbst besser zu verstehen.\n\n'
        'Kleiner Tipp: Deine Reflexionen kannst du ins Gedankenbuch eintragen. '
        'Falls du eine Psychologin oder einen Psychologen hast, kannst du sie oder ihn später darauf aufmerksam machen und Einträge teilen.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, height: 1.45, color: ZenColors.ink),
      ),
    );
  }
}

// ---------------- Round Bubble ------------------------------------------------
class _RoundBubble extends StatelessWidget {
  final ReflectionRound round;
  final double maxWidth;

  final VoidCallback? onContinue;
  final VoidCallback? onSave;
  final VoidCallback? onLater;
  final String? safetyText;
  final ValueChanged<String>? onPickFollowup;
  final void Function(int score, String label)? onMoodSelected;
  final bool isTyping; // neu: Panda tippt

  const _RoundBubble({
    required this.round,
    required this.maxWidth,
    this.onContinue,
    this.onSave,
    this.onLater,
    this.safetyText,
    this.onPickFollowup,
    this.onMoodSelected,
    this.isTyping = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final base = tt.bodyMedium!;
    final timeStyle = base.copyWith(color: Colors.black.withOpacity(.55), fontSize: 12);

    // Label neutral & klein, nicht fett
    final labelStyle = base.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Colors.black.withOpacity(.55),
      letterSpacing: .3,
    );

    final userText = base.copyWith(
      color: ZenColors.jade,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );

    final pandaMirror = base.copyWith(color: ZenColors.ink, height: 1.32);

    // Frage NICHT kursiv im Screen (im Journal kann man entscheiden)
    final pandaQuestion = base.copyWith(
      color: ZenColors.inkStrong,
      height: 1.32,
    );

    final bool lastRisk = round.steps.isNotEmpty ? round.steps.last.risk : false;
    final bool awaitingAnswer = round.steps.isNotEmpty
        ? round.steps.last.expectsAnswer && !round.steps.last.hasAnswer
        : false;

    final lastFollowups =
        round.steps.isNotEmpty ? round.steps.last.followups : const <String>[];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ZenGlassCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            topOpacity: .30,
            bottomOpacity: .12,
            borderOpacity: .18,
            borderRadius: const BorderRadius.all(ZenRadii.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Text(_fmtDayTime(round.ts), style: timeStyle))]),
                const SizedBox(height: 8),

                if (round.userInput.trim().isNotEmpty) ...[
                  Text('Gedanke', style: labelStyle),
                  const SizedBox(height: 6),
                  Text('„${round.userInput.trim()}“', style: userText),
                  const SizedBox(height: 12),
                ],

                for (int i = 0; i < round.steps.length; i++) ...[
                  if (round.steps[i].mirror.trim().isNotEmpty) ...[
                    Text(round.steps[i].mirror.trim(), style: pandaMirror),
                    const SizedBox(height: 8),
                  ],
                  for (final line in round.steps[i].talkLines) ...[
                    Text(line.trim(), style: pandaMirror),
                    const SizedBox(height: 6),
                  ],
                  if (round.steps[i].question.trim().isNotEmpty) ...[
                    Text(round.steps[i].question, style: pandaQuestion),
                    const SizedBox(height: 6),
                  ],
                  if (awaitingAnswer && i == round.steps.length - 1) ...[
                    const _ReflectionHint(),
                    if (lastFollowups.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _FollowupChips(suggestions: lastFollowups, onPick: onPickFollowup),
                    ],
                  ],
                  if (round.steps[i].hasAnswer) ...[
                    const SizedBox(height: 10),
                    Text('Antwort', style: labelStyle),
                    const SizedBox(height: 6),
                    Text(round.steps[i].answer!.trim(), style: userText),
                    const SizedBox(height: 8),
                  ],
                ],

                // Panda tippt...
                if (isTyping) ...[
                  const SizedBox(height: 6),
                  const _TypingIndicator(),
                ],

                // Mood-Phase nach Antwort (vor Save)
                if (round.answered && !round.hasMood) ...[
                  const SizedBox(height: 6),
                  _MoodChooserInline(
                    onSelected: onMoodSelected,
                  ),
                ] else if (round.hasMood) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.insights_rounded, size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text(
                        'Stimmung: ${round.moodLabel} (${round.moodScore}/4)',
                        style: tt.bodySmall?.copyWith(color: ZenColors.ink),
                      ),
                    ],
                  ),
                ],

                if (lastRisk && (safetyText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SafetyNote(text: safetyText!),
                ],

                if (round.answered) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (onContinue != null)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.forward_rounded),
                          label: const Text('Weiter reflektieren'),
                          onPressed: onContinue!,
                        ),
                      if (onSave != null)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.bookmark_added_rounded),
                          label: const Text('Ins Gedankenbuch speichern'),
                          onPressed: onSave!,
                        ),
                      if (onLater != null)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.schedule_rounded),
                          label: const Text('Später weiterführen'),
                          onPressed: onLater!,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtDayTime(DateTime ts) {
    final l = ts.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mi = l.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${l.year}, $hh:$mi';
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.black54,
          height: 1.2,
        );
    return Row(
      children: [
        const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text('Panda tippt …', style: style),
      ],
    );
  }
}

class _ReflectionHint extends StatelessWidget {
  const _ReflectionHint();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.black54,
          height: 1.2,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.self_improvement, size: 16, color: Colors.black54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Lies die Frage kurz. Antworte in 1–2 Sätzen.',
            style: style,
          ),
        ),
      ],
    );
  }
}

class _FollowupChips extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String>? onPick;
  const _FollowupChips({required this.suggestions, this.onPick});

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: suggestions
          .map(
            (s) => ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 12)),
              onPressed: onPick == null ? null : () => onPick!(s),
              shape: const StadiumBorder(side: BorderSide(color: ZenColors.sage, width: .6)),
              backgroundColor: Colors.white,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          )
          .toList(),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  final String text;
  const _SafetyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      topOpacity: .20,
      bottomOpacity: .08,
      borderOpacity: .22,
      borderRadius: const BorderRadius.all(ZenRadii.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.health_and_safety_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall?.copyWith(color: ZenColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Mood Chooser (Inline) --------------------------------------
class _MoodChooserInline extends StatelessWidget {
  final void Function(int score, String label)? onSelected;
  const _MoodChooserInline({this.onSelected});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        const Icon(Icons.mood_rounded, size: 18, color: ZenColors.ink),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Wie fühlst du dich gerade?', style: tt.bodyMedium?.copyWith(color: ZenColors.ink)),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('Stimmung wählen'),
          onPressed: () async {
            final m = await showPandaMoodPicker(context, title: 'Wähle deine Stimmung');
            if (m != null && onSelected != null) {
              onSelected!( _scoreForMood(m), m.labelDe );
            }
          },
        ),
      ],
    );
  }

  // Simple Mapping: valence → 0..4 (negativ → 0, positiv → 4)
  static int _scoreForMood(PandaMood m) {
    final v = m.valence;
    if (v <= -0.60) return 0;
    if (v <= -0.20) return 1;
    if (v <  0.20)  return 2;
    if (v <  0.60)  return 3;
    return 4;
  }
}

// ---------------- Input ------------------------------------------------------
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final VoidCallback? onSend;
  final VoidCallback? onTalk; // Talk-Push
  final bool canSend;
  final VoidCallback? onMicTap;
  final bool isRecording;
  final String? trailingHint;

  const _InputBar({
    required this.controller,
    this.focusNode,
    required this.hint,
    this.onSend,
    this.onTalk,
    this.canSend = true,
    this.onMicTap,
    this.isRecording = false,
    this.trailingHint,
  });

  @override
  Widget build(BuildContext context) {
    const jade = ZenColors.jade;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trailingHint != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(trailingHint!, textAlign: TextAlign.center, style: baseText.copyWith(color: ZenColors.ink)),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.all(ZenRadii.l),
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
                textInputAction: TextInputAction.newline, // Shift+Enter = Newline via RawKeyListener
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: true,
                spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                style: baseText.copyWith(color: jade, fontWeight: FontWeight.w600),
                cursorColor: jade,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: hintStyle,
                  border: InputBorder.none,
                  isCollapsed: true,
                  suffixIconConstraints: const BoxConstraints.tightFor(width: 144, height: 40),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Panda weiterreden',
                        onPressed: onTalk,
                        icon: Icon(Icons.chat_bubble_outline_rounded, color: jade),
                      ),
                      IconButton(
                        tooltip: isRecording ? 'Aufnahme stoppen' : 'Sprechen',
                        onPressed: onMicTap,
                        icon: Icon(isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded, color: jade),
                      ),
                      IconButton(
                        tooltip: 'Senden (Enter)',
                        onPressed: (hasText && canSend && onSend != null) ? onSend : null,
                        icon: Icon(
                          Icons.send_rounded,
                          color: (hasText && canSend && onSend != null) ? jade : jade.withOpacity(0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
