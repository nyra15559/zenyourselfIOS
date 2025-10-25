// lib/features/reflection/reflection_screen.dart
//
// ReflectionScreen — Panda v3.24.0 (Oxford level; CH risk actions; no auto-nav)
// -----------------------------------------------------------------------------
// In diesem Build:
// • Meta-Ebene: Alle Worker-Calls (start/next/closure) bekommen ein `meta`-Objekt
//   mitgegeben (Memory-Bridge/Recall, UI/Session/Safety/Telemetry).
// • **Memory-Integration (Phase 1):**
//   – Vor jedem Call wird best-effort `MemoryStore.pickFor(userInput)` (oder
//     Fallback via MemoryService) aufgerufen und als `memories` + `memoryConsent`
//     an den Worker durchgereicht (snake_case).
//   – Nach dem Turn wird – **nur bei Themen-Overlap** und **nur bei Einsicht** –
//     `recordAcknowledge()` (best-effort) getriggert, um kein Memory-Spam zu erzeugen.
//   – Keine PII im Logging/Meta (nur anonyme Zähler / Flags).
// • Fallbacks bleiben erhalten: Wenn die API keine `meta`/`memories`/`memoryConsent`
//   kennt, wird automatisch auf die alte Signatur zurückgefallen (NoSuchMethodError).
// • Intro-Bubble "pinned", Save→Mood-Flow deterministisch, min. 2 Antwortchips,
//   CH-Hotlines, Enter-/Shift+Enter-Handling, kein Auto-Navigate.
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
import '../../services/whisper_service.dart'; // STT-Engine
import '../../services/core/api_service.dart'; // Mood speichern

// Memory-Layer
import '../../core/memory/memory_service.dart';
import '../../core/memory/memory_store.dart' show MemoryStore; // pickFor()/enabled (dyn tolerant)

// CH Hotlines (Call-Buttons) + Launcher-Utilities
import '../../widgets/hotline_widget.dart'; // SwissHotlineCard / Section

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

// ---------------- Intern: Picked Memories ------------------------------------
class _PickedMem {
  final dynamic payload; // beliebig; wird 1:1 an Worker gegeben
  final bool consent;
  final List<String> keys; // extrahierte Facetten/Tags (lowercased) für Overlap
  final Map<String, dynamic> metaSafe; // nur anonyme Zähler fürs Meta
  const _PickedMem({
    required this.payload,
    required this.consent,
    required this.keys,
    required this.metaSafe,
  });
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
  StreamSubscription<String>? _finalSub;
  StreamSubscription<String>? _speechErrorSub;

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

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  // ---------------- Memory Recall / Bridge (visuell unsichtbar) --------------
  String? _bridgeText; // (nicht angezeigt; nur für Worker-Kontext)

  // Track: bereits acknowledged pro Runde → kein Doppel-Ack
  final Set<String> _ackRounds = <String>{};

  Future<void> _prefetchRecall() async {
    // Best-effort: Recall laden, UI bleibt nie blockiert.
    try {
      final recall = await MemoryService.instance.recall(limit: 6);
      final text = _composeBridgeText(recall);
      if (!mounted) return;
      setState(() => _bridgeText = text);
    } catch (_) {
      // Fehlende Memory-Implementierung darf niemals bremsen
    }
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

  // ---------------- META: Builder --------------------------------------------
  /// Sammelt Meta-Infos für den Worker. Wird an alle Calls (start/next/closure) angehängt,
  /// sofern die jeweilige API die Named-Param `meta` akzeptiert.
  Map<String, dynamic> _buildMeta({
    String? userText,
    String? userAnswer,
    String? mode,
    bool isStart = false,
    bool isClosure = false,
    Map<String, dynamic>? memorySummary, // nur anonyme Zähler/Flags
  }) {
    return {
      'ui': {
        'screen': 'reflection',
        'version': '3.24.0',
        'platform': kIsWeb ? 'web' : 'flutter',
        'is_desktop': _isDesktop,
        'chip_mode': _chipMode.name,
        'answer_chips_min': 2,
        'save_hint_after_rounds': 2,
      },
      'session': {
        'thread_id': _session?.threadId,
        'turn_index': _session?.turnIndex,
        'rounds': _rounds.length,
        'has_mood': _current?.hasMood ?? false,
        'allow_closure': _current?.allowClosure ?? false,
        'did_prompt_mood': _didPromptMood,
        'is_start': isStart,
        'is_closure': isClosure,
      },
      'memory': {
        'bridge': _bridgeText,
        if (memorySummary != null) ...{
          'injected': {
            'present': true,
            ...memorySummary, // z. B. {facets_count, tags_count, consent}
          }
        } else
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
          'chips.min2': true,
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

    _fadeSlideCtrl =
        AnimationController(vsync: this, duration: _animShort)..value = 1.0;

    _attachSttEngine();

    // Memory-Recall vorab laden (nur für Worker-Kontext; UI zeigt nichts an)
    unawaited(_prefetchRecall());

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

    _controller.addListener(_maybeHideStarterChipsOnTyping);

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
    _speechErrorSub?.cancel();
    _speech.dispose();
    _controller.dispose();
    _inputFocus.dispose();
    _pageFocus.dispose();
    _listCtrl.dispose();
    _fadeSlideCtrl.dispose();
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
    final bool withCtrlOrCmd =
        HardwareKeyboard.instance.isControlPressed ||
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
        await _speech.start(locale: 'de-DE');
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

    if (text.length > kInputHardLimit) {
      text = text.substring(0, kInputHardLimit);
      _toast('Dein Text wurde auf $kInputHardLimit Zeichen gekürzt.');
    }

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

  // --- Memory Picking ---------------------------------------------------------
  Future<_PickedMem?> _pickMemoriesFor(String userText) async {
    final input = (userText).trim();
    if (input.isEmpty) return null;

    // 1) Primär: MemoryStore.pickFor(userText) – dyn tolerant
    try {
      await MemoryStore.instance.init();
      final bool consent = MemoryStore.instance.isEnabled;
      final dyn = MemoryStore.instance as dynamic;
      final dynamic res = await dyn.pickFor?.call(input);
      if (res != null) {
        final keys = _extractFacetKeys(res);
        final metaSafe = {
          'facets_count': keys.length,
          'consent': consent,
        };
        return _PickedMem(payload: res, consent: consent, keys: keys, metaSafe: metaSafe);
      }
    } catch (_) {
      // ignore
    }

    // 2) Fallback: kompakter Kontext-Hint aus MemoryService
    try {
      final hint = MemoryService.instance.buildContextHint(
        maxFacets: 3,
        maxTags: 5,
        maxAgeDays: 14,
      );
      if (hint != null) {
        final payload = <String, dynamic>{
          if ((hint.facets as List?)?.isNotEmpty ?? false)
            'recent_facets': List<String>.from((hint.facets as List).map((e) => e.toString())),
          if ((hint.tags as List?)?.isNotEmpty ?? false)
            'recent_tags': List<String>.from((hint.tags as List).map((e) => e.toString())),
          if ((hint.topics as List?)?.isNotEmpty ?? false)
            'last_themes': List<String>.from((hint.topics as List).map((e) => e.toString())),
        };
        final keys = _extractFacetKeys(payload);
        return _PickedMem(
          payload: payload,
          consent: true,
          keys: keys,
          metaSafe: {'facets_count': keys.length, 'consent': true},
        );
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  List<String> _extractFacetKeys(dynamic src) {
    final out = <String>{};

    void addStr(String? s) {
      final t = (s ?? '').trim();
      if (t.isEmpty) return;
      out.add(t.toLowerCase());
    }

    void addList(dynamic v) {
      if (v is List) {
        for (final e in v) {
          if (e is Map) {
            addStr((e['label'] ?? e['key'] ?? e['topic'] ?? e['tag'] ?? '').toString());
          } else {
            addStr(e?.toString());
          }
        }
      }
    }

    if (src is Map) {
      // v2 camelCase Objects
      addList(src['contextFacets']);   // [{label,...}]
      addList(src['facets']);          // [String]
      // snake_case Context-Hint
      addList(src['context_facets']);  // [{label,...}] or [String]
      addList(src['recent_facets']);   // [String]
      addList(src['recent_tags']);     // [String]
      addList(src['last_themes']);     // [String]
      addList(src['recent_topics']);   // [String]
    }

    return out.toList(growable: false);
  }

  bool _hasTopicOverlap(_PickedMem pick, dynamic turn) {
    if (pick.keys.isEmpty) return false;

    final mem = pick.keys.toSet();

    final tags = _safeStringList(turn, ['tags']).map((e) => e.toLowerCase());
    final ctx = _safeStringList(turn, ['context']).map((e) => e.toLowerCase());
    final facs = _safeStringList(turn, ['understanding', 'facets'])
        .map((e) => e.toLowerCase()); // normalized UI-Facetten

    final q = _coerceQuestion(turn).toLowerCase();
    final qTokens = q.split(RegExp(r'[^a-zäöüß0-9]+')).where((w) => w.length >= 3);

    final set = {...tags, ...ctx, ...facs, ...qTokens};
    return set.any(mem.contains);
  }

  bool _hasInsight(dynamic turn) {
    // a) normalized: top-level insight_score
    final double? sTop = _safeNum(turn, ['insight_score']);
    if (sTop != null && sTop >= 0.5) return true;

    // b) older/worker: flow.insight_score
    final double? sFlow = _safeNum(turn, ['flow', 'insight_score']);
    if (sFlow != null && sFlow >= 0.5) return true;

    // c) typed DTO: TurnAnalysis.insightScore
    try {
      if (turn is ReflectionTurn) {
        final v = turn.analysis?.insightScore;
        if (v != null && v >= 0.5) return true;
      }
    } catch (_) {/* tolerant */}

    // d) heuristischer Fallback
    final hasMirror = _coerceMirror(turn).trim().isNotEmpty;
    final hasQ = _coerceQuestion(turn).trim().isNotEmpty;
    return hasMirror && hasQ;
  }

  Future<void> _acknowledgeIfInsight({
    required ReflectionRound round,
    required dynamic turn,
    _PickedMem? picked,
  }) async {
    if (picked == null) return;
    if (_ackRounds.contains(round.id)) return; // pro Runde nur ein Ack
    if (!_hasInsight(turn)) return;
    if (!_hasTopicOverlap(picked, turn)) return;

    final double? score =
        _safeNum(turn, ['insight_score']) ??
        _safeNum(turn, ['flow', 'insight_score']) ??
        (() {
          try {
            if (turn is ReflectionTurn) return turn.analysis?.insightScore;
          } catch (_) {}
          return null;
        }());

    final ack = {
      'round_id': round.id,
      'session_id': _session?.threadId,
      'insight_score': score,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'facets_keys': picked.keys.take(6).toList(), // klein halten
    };

    try {
      // bevorzugt Service (dyn tolerant)
      final dyn = MemoryService.instance as dynamic;
      await dyn.recordAcknowledge?.call(ack);
    } catch (_) {
      try {
        final dynStore = MemoryStore.instance as dynamic;
        await dynStore.recordAcknowledge?.call(ack);
      } catch (_) {/* ignore */}
    }

    _ackRounds.add(round.id);
  }

  // --- Start: neue Reflexion -------------------------------------------------
  Future<void> _startNewReflection({
    required String userText,
    required String mode,
  }) async {
    setState(() {
      loading = true;
      _chipMode = _ChipMode.none;
      _didPromptMood = false;
      _isMoodOpen = false;
    });

    // NEU: Memories picken (best-effort)
    final _PickedMem? picked = await _pickMemoriesFor(userText);

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
      final meta = _buildMeta(
        userText: userText,
        mode: mode,
        isStart: true,
        memorySummary: picked?.metaSafe,
      );

      try {
        // 1) Neuer Endpunkt mit Meta + Memories (dyn tolerant)
        turn = await (GuidanceService.instance as dynamic)
            .startSessionFull(
              text: userText,
              locale: 'de',
              tz: 'Europe/Zurich',
              meta: meta,
              memories: picked?.payload,
              memoryConsent: picked?.consent ?? false,
            )
            .timeout(_netTimeout);
      } on NoSuchMethodError {
        try {
          // 2) Alter Endpunkt ohne Meta, aber evtl. Memories
          turn = await (GuidanceService.instance as dynamic)
              .startSessionFull(
                text: userText,
                locale: 'de',
                tz: 'Europe/Zurich',
                memories: picked?.payload,
                memoryConsent: picked?.consent ?? false,
              )
              .timeout(_netTimeout);
        } on NoSuchMethodError {
          // 3) Ganz alter Fallback → ohne Extras
          turn = await GuidanceService.instance
              .startSessionFull(text: userText, locale: 'de', tz: 'Europe/Zurich')
              .timeout(_netTimeout);
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

      // NEU: bei Einsicht + Overlap → Acknowledge
      unawaited(_acknowledgeIfInsight(round: round, turn: turn, picked: picked));

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

    // NEU: Memories picken für die Antwort (aktualisierte Achse)
    final _PickedMem? picked = await _pickMemoriesFor(userAnswer);

    dynamic turn;
    final meta = _buildMeta(userAnswer: userAnswer, memorySummary: picked?.metaSafe);

    try {
      if (_session != null) {
        try {
          // 1) Neuer Endpunkt (nextTurnFull) mit Meta + Memories
          turn = await (GuidanceService.instance as dynamic)
              .nextTurnFull(
                session: _session!,
                text: userAnswer,
                locale: 'de',
                tz: 'Europe/Zurich',
                meta: meta,
                memories: picked?.payload,
                memoryConsent: picked?.consent ?? false,
              )
              .timeout(_netTimeout);
        } on NoSuchMethodError {
          try {
            // 2) Älterer Name (reflectFull) mit Meta + Memories (dyn)
            turn = await (GuidanceService.instance as dynamic)
                .reflectFull(
                  session: _session!,
                  text: userAnswer,
                  locale: 'de',
                  tz: 'Europe/Zurich',
                  meta: meta,
                  memories: picked?.payload,
                  memoryConsent: picked?.consent ?? false,
                )
                .timeout(_netTimeout);
          } on NoSuchMethodError {
            // 3) Fallback ohne Meta/Memories
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
        // Keine Session bekannt → (re)start
        try {
          turn = await (GuidanceService.instance as dynamic)
              .startSessionFull(
                text: userAnswer,
                locale: 'de',
                tz: 'Europe/Zurich',
                meta: meta,
                memories: picked?.payload,
                memoryConsent: picked?.consent ?? false,
              )
              .timeout(_netTimeout);
        } on NoSuchMethodError {
          turn = await GuidanceService.instance
              .startSessionFull(
                text: userAnswer,
                locale: 'de',
                tz: 'Europe/Zurich',
              )
              .timeout(_netTimeout);
        }
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

    // NEU: bei Einsicht + Overlap → Acknowledge
    unawaited(_acknowledgeIfInsight(round: round, turn: turn, picked: picked));

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

    final fromSvc = _safeStringList(t, ['answer_helpers']).take(3).toList();
    final helpers = isClosure
        ? <String>[]
        : (fromSvc.isNotEmpty
            ? fromSvc
            : _coerceAnswerHelpers(t).take(3).toList());

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

  Future<void> _onPressSaveRound(ReflectionRound r) async {
    if (r.entryId != null) {
      _toast('Bereits gespeichert.');
      return;
    }
    if (!r.answered) {
      _toast('Bitte zuerst deine Antwort schreiben.');
      return;
    }

    if (!r.hasMood) {
      if (_isMoodOpen) return;
      _isMoodOpen = true;
      final chosen = await showPandaMoodPicker(
        context,
        title: 'Wie fühlst du dich gerade?',
      );
      _isMoodOpen = false;
      if (chosen == null) return;
      _didPromptMood = true;

      final score = _scoreForMoodLocal(chosen);
      final label = chosen.labelDe;
      setState(() {
        r.moodScore = score;
        r.moodLabel = label;
      });

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

  // ---------------- Abschluss/Mood-Einleitung (Worker-kompatibel) -----------
  Future<void> _requestClosureFromWorker({
    required ReflectionRound round,
    required String userAnswer,
  }) async {
    if (!mounted) return;
    setState(() => loading = true);
    _scrollToBottom();

    dynamic res;
    final meta = _buildMeta(userAnswer: userAnswer, isClosure: true);

    try {
      // 1) Neuer Closure-Endpunkt mit Meta
      res = await (GuidanceService.instance as dynamic)
          .closureFull(
            session: _session,
            answer: userAnswer,
            locale: 'de',
            tz: 'Europe/Zurich',
            meta: meta,
          )
          .timeout(_netTimeout);
    } on NoSuchMethodError {
      try {
        // 2) Fallback ohne Meta
        res = await GuidanceService.instance
            .closureFull(
              session: _session,
              answer: userAnswer,
              locale: 'de',
              tz: 'Europe/Zurich',
            )
            .timeout(_netTimeout);
      } on NoSuchMethodError {
        // Ältestes System: kein closure-Support → einfach aussteigen
        if (mounted) setState(() => loading = false);
        return;
      }
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

    setState(() {
      round.moodIntro = _capChars(closure, kMirrorMaxChars);
      round.allowClosure = true;
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
    s = s.replaceAll(RegExp(r'\s*[:：]\s*$'), ''); // trailing ':' entfernen
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
        (r != null && r.steps.isNotEmpty && r.steps.last.followups.isNotEmpty) &&
        _chipMode == _ChipMode.answer;

    final List<String> rawTemplates = showAnswerChips
        ? r.steps.last.followups
        : (showStarter ? _starterChips() : const <String>[]);

    final lastQ = r?.steps.isNotEmpty == true ? r!.steps.last.question : '';
    final lastA = r?.steps.isNotEmpty == true ? (r!.steps.last.answer ?? '') : '';
    final List<String> answerTemplatesRefined =
        _refineChips(rawTemplates, question: lastQ, lastAnswer: lastA);

    // --- NEU: Mindestens 2 Chips (sanfter Fallback)
    final List<String> answerTemplates =
        _ensureMinTwoChips(answerTemplatesRefined, lastQ, lastA);

    // Save-Hinweis soll explizit erst NACH 2 Runden erscheinen
    final bool canPermanentSave =
        r != null && r.answered && (r.entryId == null);
    final bool showSaveHint = canPermanentSave && _rounds.length >= 2;

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

                              // Intro (pinned) – bleibt als Anker sichtbar
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
                                        onSave: _rounds[index].answered
                                            ? () => _onPressSaveRound(
                                                _rounds[index])
                                            : null,
                                        onDelete: _rounds[index].entryId != null
                                            ? () =>
                                                _deleteRound(_rounds[index])
                                            : null,
                                        onSelectMood: (score, label) async {
                                          setState(() {
                                            _rounds[index].moodScore = score;
                                            _rounds[index].moodLabel = label;
                                            _didPromptMood = true;
                                          });
                                          await _saveRoundCore(_rounds[index]);
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

                              // ------------------ (Bridge bewusst entfernt) ------------------

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

                              // NEU: Save-Hinweis, sobald Speichern möglich **und nach 2 Runden**
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
                                                      Icons.info_outline_rounded,
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

  // NEU: sorge für mind. 2 Chips – generischer Zusatz bei nur 1
  List<String> _ensureMinTwoChips(List<String> chips, String q, String a) {
    if (chips.length >= 2) return chips;
    final List<String> out = List<String>.from(chips);
    // Sanfter, universeller Satzstarter
    const fallback = 'Noch etwas dazu … ';
    // Falls Frage Kontext gibt, baue einen neutralen Starter daraus
    String fromQ(String qq) {
      final s = qq.trim();
      if (s.isEmpty) return fallback;
      // sehr neutraler Ableitungs-Text:
      return 'Wichtig ist mir außerdem … ';
    }
    out.add(_ensureEllipsisSuffix(fromQ(q)));
    return out;
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

  Future<void> _maybeAskMood(
    BuildContext context, {
    required ReflectionRound round,
    required bool moodPrompt,
    bool afterClosure = false,
  }) async {
    if (!moodPrompt) return;
    if (!mounted) return;
    if (round.hasMood) return;
    if (_didPromptMood || _isMoodOpen) return;

    _isMoodOpen = true;
    final title =
        afterClosure ? 'Wie fühlst du dich jetzt?' : 'Wie fühlst du dich gerade?';

    final chosen = await showPandaMoodPicker(
      context,
      title: title,
    );
    _isMoodOpen = false;
    if (chosen == null) return;

    final score = _scoreForMoodLocal(chosen);
    final label = chosen.labelDe;

    if (!mounted) return;
    setState(() {
      round.moodScore = score;
      round.moodLabel = label;
      _didPromptMood = true;
    });

    try {
      await ApiService.instance.mood(
        entryId: round.id,
        icon: score,
        note: null,
      );
    } catch (_) {/* ignore */}
  }

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
