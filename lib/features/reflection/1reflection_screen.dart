// lib/features/reflection/reflection_screen.dart
//
// ReflectionScreen — Panda v3.4
// Update: 2025-09-14
// -----------------------------------------------------------------------------
// Neu/Änderungen ggü. v3.3:
// • Vorschlags-Chips hübscher (Pill mit leichtem Schatten, kompaktere Typo).
// • Mood-Speicherstreifen wieder aktiv, als Glas-Karte mit klarem „Speichern“-Button.
// • Datum/Uhrzeit in die Panda-Bubble integriert (unten rechts), externe Zeitreihe entfernt.
// • „Panda tippt …“: wieder sichtbar – auch als Platzhalter, wenn noch keine Panda-Bubble existiert.
// • All-in-one ListView bleibt (Overflow-frei).
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/zen_style.dart' hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart'
    show ZenBackdrop, ZenGlassCard, ZenAppBar;

// Panda-Moods
import '../../models/panda_mood.dart';
import '../../widgets/panda_mood_picker.dart';

// Journal
import '../../models/journal_entry.dart' as jm;
import '../../providers/journal_entries_provider.dart';

// Services
import '../../services/guidance_service.dart';
import '../../services/speech_service.dart';

// -----------------------------------------------------------------------------
// Config
// -----------------------------------------------------------------------------
const String kPandaHeaderAsset = 'assets/panda-header.png';

// ---------------- Panda Step --------------------------------------------------
class _PandaStep {
  final String mirror;           // 2–6 Sätze, warm & kontexttreu
  final String question;         // genau 1 Frage (leer => Talk-only)
  final List<String> talkLines;  // 0–2 kurze Sätze (Warm-Talk)
  final bool risk;               // Safety-Flag
  String? answer;                // Nutzer-Antwort

  _PandaStep({
    required this.mirror,
    required this.question,
    this.talkLines = const [],
    this.risk = false,
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

// ---------------- Optionaler Hook + Navigation --------------------------------
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
  static const Duration _animShort = Duration(milliseconds: 240);
  static const double _inputReserve = 104; // Platz für die Input-Bar

  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _pageFocus = FocusNode();
  final ScrollController _listCtrl = ScrollController();

  late final AnimationController _fadeSlideCtrl;

  final SpeechService _speech = SpeechService();
  StreamSubscription<String>? _finalSub;

  final List<ReflectionRound> _rounds = <ReflectionRound>[];
  ReflectionRound? get _current => _rounds.isEmpty ? null : _rounds.last;

  dynamic _session;
  bool loading = false;

  String get _errorHint => GuidanceService.instance.errorHint;

  // Undo
  String? _lastSentAnswer;
  int? _lastAnsweredStepIndex;

  // Chips-State ---------------------------------------------------------------
  // modes: 'starter' | 'answer' | 'none'
  String _chipMode = 'starter';
  bool _textWasEmpty = true;

  @override
  void initState() {
    super.initState();

    _fadeSlideCtrl = AnimationController(vsync: this, duration: _animShort)
      ..value = 1.0; // nichts initial unsichtbar

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
        _maybeHideStarterChipsOnTyping();
        FocusScope.of(context).requestFocus(_inputFocus);
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
    if (_chipMode == 'starter' && hasText && _textWasEmpty) {
      setState(() => _chipMode = 'none');
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
        _chipMode = 'none'; // Antwortchips weg
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
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _chipMode = 'answer'; // Antwortchips wieder zeigen
    });
    FocusScope.of(context).requestFocus(_inputFocus);
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
    ScaffoldMessenger.of(context).showSnackBar(snack);
  }

  // --- Start: neue Reflexion -------------------------------------------------
  Future<void> _startNewReflection({required String userText, required String mode}) async {
    setState(() {
      loading = true;
      _chipMode = 'none'; // Starterchips weg
    });
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
        if (step.expectsAnswer) {
          _chipMode = 'answer'; // Antwortchips ein
        }
      });

      _fadeSlideCtrl.forward(from: 0); // animiert die neue Panda-Bubble
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

    final String title = _autoTitleForRound(r, fallback: _autoSessionName(r.userInput));

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

    _toast('Im Gedankenbuch gespeichert.');
    _showPostSheet(); // direkt danach Optionen anbieten
  }

  // ---------------- Löschen ---------------------------------------------------
  Future<void> _deleteRound(ReflectionRound r) async {
    setState(() {
      _rounds.removeWhere((x) => x.id == r.id);
      _chipMode = _rounds.isEmpty ? 'starter' : 'none';
    });
    _toast('Gelöscht.');
  }

  // ---------------- Entwurf (optional) ---------------------------------------
  Future<void> _saveDraft(ReflectionRound r) async {
    final draftName = _autoSessionName(r.userInput);
    _toast('Als Entwurf gemerkt: "$draftName"');
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
    final rawMirror = _turnMirror(t).trim();
    final rawTalk = _turnTalk(t);
    final questions = _turnQuestions(t);
    final out1 = _turnString(t, 'outputText');
    final out2 = _turnString(t, 'output_text');

    final mirrorRaw = rawMirror.isNotEmpty ? rawMirror : _fallbackMirror(userText);
    var mirror = _ensureMirrorSentences(mirrorRaw);

    final List<String> talk = rawTalk.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final String qRaw =
        (questions.isNotEmpty ? questions.first : (out1.isNotEmpty ? out1 : out2)).trim();
    String? sanitized = _sanitizeQuestion(qRaw);

    final bool isSmallTalk = smallTalkHint || _looksLikeSmallTalk(userText);
    if (isSmallTalk && talk.isEmpty) {
      talk.addAll(<String>[
        'Mir geht’s gut – wichtiger ist, wie es dir geht.',
        'Ich bleibe bei dir.'
      ]);
      sanitized ??= 'Was hat dich heute dazu gebracht, gerade das zu fragen?';
    }

    final String baseQuestion =
        sanitized ?? _contextualFallbackQuestion(userText, hintFromMirror: mirror);

    final String question = _makeUniqueQuestion(baseQuestion, round, userText, mirror);

    final cleanedTalk = _dedupeTalk(talk, mirror, question);
    mirror = _dedupeMirror(mirror, question, cleanedTalk);

    final riskLevel = _turnString(t, 'risk_level').toLowerCase();
    final flow = _turnFlow(t);
    final bool risk = _turnBool(t, 'risk') || riskLevel == 'high' || (flow?['risk_notice'] == 'safety');

    return _PandaStep(
      mirror: mirror,
      question: _limitWords(question, 30),
      talkLines: cleanedTalk,
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
      RegExp(r'wie\s+fühlt\s+es\s+sich'),
      RegExp(r'wie\s+geht\s+es\s+dir'),
      RegExp(r'worum\s+geht\s+es\s+dir'),
      RegExp("^\\s*was\\s+ist\\s+dir\\s+an\\s+[\"\\']?.+?[\"\\']?\\s+(?:gerade\\s+)?am\\s+wichtigsten\\??\\s*\$"),
      RegExp("^\\s*was\\s+ist\\s+dir\\s+daran\\s+(?:gerade\\s+)?am\\s+wichtigsten\\??\\s*\$"),
    ].any((p) => p.hasMatch(lower));
    if (generic) return null;

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
        RegExp(r"(wie\s+geht(?:'|’)?s\s+dir|wie\s+geht\s+es\s+dir|alles\s+gut)").hasMatch(t);
    final pandaMention = RegExp(r'\bpanda\b').hasMatch(t);
    return howAreYou || (pandaMention && hello);
  }

  // ---------------- Chips: Logik ---------------------------------------------
  List<String> _starterChips() => const [
        'Heute war ein stressiger Tag.',
        'Heute geht es mir nicht so gut, weil …',
        'Ich schiebe etwas vor mir her.',
      ];

  List<String> _answerChipsFor(String question) {
    final q = question.toLowerCase();

    if (RegExp(r'anstrengend').hasMatch(q)) {
      return ['Besonders anstrengend war …', 'Schwer gefallen ist mir …'];
    }
    if (RegExp(r'wut|ärger|genervt|sauer').hasMatch(q)) {
      return ['Getriggert hat mich …', 'Am meisten geärgert hat mich …'];
    }
    if (RegExp(r'angst|sorge|unsicher|nervös|panik').hasMatch(q)) {
      return ['Am meisten sorgt mich …', 'Ich befürchte, dass …'];
    }
    if (RegExp(r'gut|freu|stolz|dankbar|leicht').hasMatch(q)) {
      return ['Besonders gut tat mir …', 'Darüber freue ich mich …'];
    }
    if (RegExp(r'wichtigsten').hasMatch(q)) {
      return ['Am wichtigsten ist mir …', 'Gerade zählt für mich …'];
    }
    if (RegExp(r'schritt|anfang|beginnen').hasMatch(q)) {
      return ['Mein kleiner nächster Schritt ist …', 'Heute starte ich mit …'];
    }

    return ['Es war …', 'Wesentlich ist für mich …'];
  }

  void _onChipTapped(String template) {
    HapticFeedback.selectionClick();
    setState(() => _chipMode = 'none'); // Chips verschwinden
    final cur = _controller.text.trim();
    final next =
        cur.isEmpty ? template : (cur.endsWith(' ') ? '$cur$template' : '$cur $template');
    _controller.text = next;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    FocusScope.of(context).requestFocus(_inputFocus);
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
                    color: Colors.black.withValues(alpha: .12),
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
  String get _headerSubtitle => 'Ich bin hier.';

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

    final bool showAnswerHint = r != null && r.hasPendingQuestion;
    final bool lastIsTyping = r != null && loading;

    final bool showStarter = _rounds.isEmpty && _chipMode == 'starter';
    final bool showAnswerChips = (r?.hasPendingQuestion ?? false) && _chipMode == 'answer';

    final List<String> answerTemplates =
        showAnswerChips ? _answerChipsFor(r!.steps.last.question) : const [];

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
          appBar: ZenAppBar(title: '', showBack: true),
          body: Stack(
            children: [
              Positioned.fill(
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

              // ---- Alles oberhalb der Input-Bar in EINER scrollbaren ListView
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          controller: _listCtrl,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            0, 0, 0,
                            12 + _inputReserve + bottomInset,
                          ),
                          children: [
                            // Header
                            _ReflectionHeader(
                              title: _headerTitle,
                              subtitle: _headerSubtitle,
                              pandaAsset: kPandaHeaderAsset,
                              pandaSize: w < 470 ? 86 : 110,
                            ),
                            const SizedBox(height: 10),

                            // Intro (nur bei erster Runde)
                            if (_rounds.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        BoxConstraints(maxWidth: cardMaxW),
                                    child: const _IntroTwoCards(),
                                  ),
                                ),
                              ),

                            // Verlauf (alle Runden)
                            for (int index = 0; index < _rounds.length; index++)
                              KeyedSubtree(
                                key: ValueKey(_rounds[index].id),
                                child: FadeTransition(
                                  opacity: _fadeSlideCtrl.drive(
                                      Tween(begin: 0.0, end: 1.0)),
                                  child: SlideTransition(
                                    position: _fadeSlideCtrl.drive(
                                      Tween(
                                        begin: const Offset(-0.03, 0),
                                        end: Offset.zero,
                                      ),
                                    ),
                                    child: _RoundThread(
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
                                          ? () => _deleteRound(_rounds[index])
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
                                              _rounds[index].steps.last.risk
                                          ? _emergencyHint(context)
                                          : null,
                                    ),
                                  ),
                                ),
                              ),

                            // Hinweis nur wenn Antwort erwartet
                            if (showAnswerHint) ...[
                              const SizedBox(height: 4),
                              Center(
                                child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(maxWidth: cardMaxW),
                                  child: const _ReflectionHint(),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ] else
                              const SizedBox(height: 6),

                            // CHIPS (Starter oder Antwort)
                            if (showStarter || showAnswerChips)
                              Center(
                                child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(maxWidth: cardMaxW),
                                  child: AnimatedSwitcher(
                                    duration: _animShort,
                                    child: Padding(
                                      key: ValueKey(
                                          '${showStarter ? 'starter' : 'answer'}-chips'),
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: _ChipsWrap(
                                        items: showStarter
                                            ? _starterChips()
                                            : answerTemplates,
                                        onTap: _onChipTapped,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Eingabe (fix am Boden)
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: cardMaxW),
                          child: _InputBar(
                            focusNode: _inputFocus,
                            controller: _controller,
                            hint: _inputHint(),
                            onSend: loading ? null : _send,
                            canSend: !loading,
                            onMicTap: loading ? null : _toggleRecording,
                            isRecording: _speech.isRecording,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
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
    if (r.hasPendingQuestion) return 'Antwort in 1–2 Sätzen …';
    return 'Neue Reflexion beginnen — oder deine Antwort schreiben.';
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

// ---------------- Header (Titel → Panda → Untertitel) ------------------------
class _ReflectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String pandaAsset;
  final double pandaSize;

  const _ReflectionHeader({
    required this.title,
    required this.subtitle,
    required this.pandaAsset,
    required this.pandaSize,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: tt.headlineMedium!.copyWith(
            color: ZenColors.deepSage,
            fontWeight: FontWeight.w900,
            letterSpacing: .2,
            shadows: [
              Shadow(
                blurRadius: 8,
                color: Colors.black.withValues(alpha: .08),
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Image.asset(
          pandaAsset,
          width: pandaSize,
          height: pandaSize,
          fit: BoxFit.contain,
          semanticLabel: 'Panda',
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: tt.labelLarge?.copyWith(
            fontStyle: FontStyle.italic,
            color: ZenColors.deepSage.withValues(alpha: .9),
          ),
        ),
      ],
    );
  }
}

// ---------------- Intro: zwei kleine Panda-Bubbles ---------------------------
class _IntroTwoCards extends StatelessWidget {
  const _IntroTwoCards();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _IntroCardA(),
        SizedBox(height: 8),
        _IntroCardB(),
      ],
    );
  }
}

class _IntroCardA extends StatelessWidget {
  const _IntroCardA();

  @override
  Widget build(BuildContext context) {
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      topOpacity: .26,
      bottomOpacity: .10,
      borderOpacity: .18,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: const Text(
        'Hallo, ich bin ZenYourself – dein Panda. '
        'Du kannst mir deine Gedanken schreiben oder flüstern. '
        'Ich helfe dir, deine Gedanken zu ordnen und dich selbst besser zu verstehen.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, height: 1.45, color: ZenColors.ink),
      ),
    );
  }
}

class _IntroCardB extends StatelessWidget {
  const _IntroCardB();

  @override
  Widget build(BuildContext context) {
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      topOpacity: .24,
      bottomOpacity: .10,
      borderOpacity: .18,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: const Text(
        'Kleiner Tipp: Deine Reflexionen findest du später im Gedankenbuch. '
        'Dort kannst du sie in Ruhe ansehen, ordnen – und nur wenn du willst – teilen.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, height: 1.45, color: ZenColors.ink),
      ),
    );
  }
}

// ---------------- Gesprächs-Thread (User + Panda getrennt) -------------------
class _RoundThread extends StatelessWidget {
  final ReflectionRound round;
  final double maxWidth;
  final bool isLast;
  final bool isTyping;

  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final String? safetyText;
  final void Function(int score, String label)? onSelectMood;

  const _RoundThread({
    required this.round,
    required this.maxWidth,
    required this.isLast,
    required this.isTyping,
    this.onSave,
    this.onDelete,
    this.safetyText,
    this.onSelectMood,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final base = tt.bodyMedium!;
    final timeStyle = base.copyWith(color: Colors.black.withValues(alpha: .45), fontSize: 12);

    final labelStyle = base.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Colors.white.withValues(alpha: .9),
      letterSpacing: .3,
    );

    // User-Bubble
    final userText = base.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
    final Color userBg = ZenColors.jade.withValues(alpha: .92);

    // Panda-Bubble
    final pandaMirror = base.copyWith(color: ZenColors.ink, height: 1.32);
    final pandaQuestion = base.copyWith(color: ZenColors.inkStrong, height: 1.32);

    final children = <Widget>[
      // (Externe Zeitreihe entfernt – Zeit wandert in die Bubble)

      // User-Bubble (Gedanke)
      if (round.userInput.trim().isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              decoration: BoxDecoration(
                color: userBg,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(color: Color(0x19000000), blurRadius: 14, offset: Offset(0, 6)),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gedanke', style: labelStyle),
                  const SizedBox(height: 6),
                  Text('„${round.userInput.trim()}“', style: userText),
                ],
              ),
            ),
          ),
        ),

      const SizedBox(height: 10),

      // Panda-Bubbles (Mirror/Talk/Frage)
      for (int i = 0; i < round.steps.length; i++) ...[
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ZenGlassCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              topOpacity: .30,
              bottomOpacity: .12,
              borderOpacity: .18,
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  ],

                  // „Panda tippt …“ in/unter letzter Panda-Bubble
                  if (isLast && isTyping && i == round.steps.length - 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Panda tippt …', style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ],

                  // Zeitstempel in der Panda-Bubble (unten rechts)
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(_fmtDayTime(round.ts), style: timeStyle),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Antwort-Bubble (User)
        if (round.steps[i].hasAnswer) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                decoration: BoxDecoration(
                  color: userBg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Color(0x19000000), blurRadius: 14, offset: Offset(0, 6)),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Antwort', style: labelStyle),
                    const SizedBox(height: 6),
                    Text(round.steps[i].answer!.trim(), style: userText),
                  ],
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 10),
      ],

      // Wenn noch keine Panda-Bubble existiert & wir warten → Platzhalter
      if (round.steps.isEmpty && isTyping) ...[
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ZenGlassCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              topOpacity: .28,
              bottomOpacity: .10,
              borderOpacity: .18,
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              child: Row(
                children: const [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Panda tippt …', style: TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],

      // Stimmung: erst wählen → Speicherstreifen (hübscher)
      if (round.answered && !round.hasMood) ...[
        _MoodChooserInline(onSelected: onSelectMood),
        const SizedBox(height: 10),
      ],

      // Nach Mood vorhanden: optionale Buttons
      if (round.answered && round.hasMood) Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (onSave != null)
            ElevatedButton.icon(
              icon: const Icon(Icons.bookmark_added_rounded),
              label: const Text('Ins Gedankenbuch speichern'),
              onPressed: onSave!,
            ),
          if (onDelete != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Löschen'),
              onPressed: onDelete!,
            ),
        ],
      ),

      if ((safetyText ?? '').isNotEmpty) ...[
        const SizedBox(height: 10),
        _SafetyNote(text: safetyText!),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
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

// ---------------- Kleinzeug --------------------------------------------------
class _ReflectionHint extends StatelessWidget {
  const _ReflectionHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: const [
        Icon(Icons.self_improvement, size: 16, color: Colors.black54),
        SizedBox(width: 6),
        Expanded(child: Text('Lies die Frage kurz. Antworte in 1–2 Sätzen.', style: TextStyle(color: Colors.black54))),
      ],
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
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.health_and_safety_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: tt.bodySmall?.copyWith(color: ZenColors.ink))),
        ],
      ),
    );
  }
}

// ---------------- Mood Chooser (Inline, hübscher) ----------------------------
class _MoodChooserInline extends StatelessWidget {
  final void Function(int score, String label)? onSelected;
  const _MoodChooserInline({this.onSelected});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      topOpacity: .22,
      bottomOpacity: .10,
      borderOpacity: .20,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.mood_rounded, size: 18, color: ZenColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Zum Speichern: Stimmung wählen',
              style: tt.bodyMedium?.copyWith(color: ZenColors.ink),
            ),
          ),
          FilledButton.icon(
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(ZenColors.jade),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
            ),
            icon: const Icon(Icons.bookmark_added_rounded),
            label: const Text('Speichern'),
            onPressed: () async {
              final m = await showPandaMoodPicker(context, title: 'Wähle deine Stimmung');
              if (m != null && onSelected != null) {
                onSelected!(_scoreForMood(m), m.labelDe); // Auto-Save danach
              }
            },
          ),
        ],
      ),
    );
  }

  static int _scoreForMood(PandaMood m) {
    final v = m.valence;
    if (v <= -0.60) return 0;
    if (v <= -0.20) return 1;
    if (v <  0.20)  return 2;
    if (v <  0.60)  return 3;
    return 4;
  }
}

// ---------------- Chips UI (schöner) -----------------------------------------
class _ChipsWrap extends StatelessWidget {
  final List<String> items;
  final void Function(String) onTap;

  const _ChipsWrap({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Textgröße für Chips leicht zügeln
    final scale = MediaQuery.of(context).textScaleFactor.clamp(0.9, 1.1);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaleFactor: scale),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in items)
            _ChipPill(
              label: t,
              onTap: () => onTap(t),
            ),
        ],
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ChipPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pillColor = Colors.white.withValues(alpha: .96);
    final border = ZenColors.jade.withValues(alpha: .55);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Ink(
          decoration: BoxDecoration(
            color: pillColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: 1.4),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34, minWidth: 32),
              child: Text(
                label.replaceAll(RegExp(r'\s*:\s*$'), ''), // kein Doppelpunkt am Ende
                softWrap: true,
                overflow: TextOverflow.visible,
                style: const TextStyle(
                  color: ZenColors.jade,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Input ------------------------------------------------------
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final VoidCallback? onSend;
  final bool canSend;
  final VoidCallback? onMicTap;
  final bool isRecording;

  const _InputBar({
    required this.controller,
    this.focusNode,
    required this.hint,
    this.onSend,
    this.canSend = true,
    this.onMicTap,
    this.isRecording = false,
  });

  @override
  Widget build(BuildContext context) {
    const jade = ZenColors.jade;
    final baseText = Theme.of(context).textTheme.bodyMedium!;
    final hintStyle = baseText.copyWith(color: jade.withValues(alpha: 0.55));

    final List<BoxShadow> pulse = isRecording
        ? [
            BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 4)),
            BoxShadow(color: jade.withValues(alpha: 0.30), blurRadius: 22, spreadRadius: 1.2),
          ]
        : [
            const BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
          ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: jade.withValues(alpha: 0.75), width: 2),
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
            textInputAction: TextInputAction.newline,
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
              suffixIconConstraints: const BoxConstraints.tightFor(width: 96, height: 40),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      color: (hasText && canSend && onSend != null) ? jade : jade.withValues(alpha: 0.45),
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
