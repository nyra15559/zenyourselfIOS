// [UPDATED] lib/features/reflection/reflection_view.dart (Stand: 2025-11-20, v6.8.3g)
// ReflectionView — reine Layout-Schicht (Plan v6.2.2 + v6.3.x VM-Wiring)
// + v6.4 AutoScroll v1 (2025-10-31):
//   • Stateful (ScrollController, extentAfter-Heuristik, Jump-to-Bottom FAB)
//   • onSend wird lokal „gewrapped“ → force scroll nach Senden
//   • Auto-Scroll bei neuem Content (didUpdateWidget Signature-Vergleich)
//   • sanfter Scroll bei Keyboard-Änderung (bottomInset-Änderung)
// ---------------------------------------------------------------------
// Rendert:
// • Header, Intro/Pitch-Bubble, Smalltalk-Bubble, Bridge-Bubble
// • Frage + helperSuggestion, Talk-Zeilen
// • Verlauf (Thread), **Answer-Chips (insert-only)**   ← nur Worker-Helpers
// • **Mood-CTA ausschließlich, wenn flow.mood_prompt==true**
// • Risk/Hotline-Banner
// • Composer (unten) + Footer-Disclaimer
// • Optional: Dev-Mem-Badge („Mem ON (n)“ / „Mem OFF“)
//
// Hinweis: Ehemalige Tool-/Topic-Chips („Thema wechseln“, „Essenz“, „Beispiel“)
// sind entfernt. topicChips bleibt als Prop für API-Stabilität (no-op).
//
// v6.4.1 (S2.2 Typing Inline):
//   • Neues Prop `isTyping` → Typing-Indicator direkt unter der letzten User-Bubble.
//   • Kein Overlay: Indicator als normaler Listeneintrag innerhalb des Threads.
//
// v6.7 Patch (2025-11-04):
//   • Mood-Gate strikt an `moodPrompt` gebunden (kein CTA bei allowClosure-only).
//   • Kleinere Robustheits-Fixes (Width-Clamp, Null-Guards), Analyzer-clean.
//
// v6.7.2 (2025-11-07):
//   • BUGFIX: Composer verwendete konstanten Hint-Text; jetzt `hint`-Prop korrekt genutzt.
//   • Kleinere Mikro-Polishes (sanftere Auto-Scroll-Signatur, Null-Guards).
//
// v6.8.3b (2025-11-08):
//   • Neues Prop `composerHint` in ReflectionViewProps (Default: „Antworte in 1–2 Sätzen.“).
//   • Composer nutzt nun konsequent `props.composerHint` statt konstantem String.
//   • Sonst keine Logik-Änderungen (stabil zu ReflectionLogic v6.8.3b).
//
// v6.8.3c (2025-11-19):
//   • ScrollController-Init in initState (kein this-Zugriff im Field-Init, sauberer Lifecycle).
//   • _effectiveBottomInset: clamp-Ergebnis explizit nach double gecastet (kein num→double-Noise).
//   • Sonst keinerlei Logik- oder API-Änderungen (Drop-in-kompatibel).
//
// v6.8.3d (2025-11-19):
//   • TypingDots-AnimationController in initState initialisiert (kein this im Field-Init).
//   • Sonst keinerlei Logik-/API-Änderungen (Drop-in-kompatibel zu v6.8.3c).
//
// v6.8.3e (2025-11-19):
//   • DevMemBadge zeigt jetzt den Text „Mem ON (n)“ / „Mem OFF“ neben dem Icon.
//   • Keine weiteren Änderungen (reines UI-Micro-Polishing).
//
// v6.8.3f (2025-11-20):
//   • Scroll-Reserve `_kInputReserve` deutlich reduziert, damit neue Nachrichten wie bei WhatsApp
//     nah am unteren Rand sichtbar bleiben (kein „Loch“ unter der letzten Bubble).
//   • ZenBackdrop-Aufruf syntaktisch korrigiert (kein Verhaltensänderung).
//
// v6.8.3g (2025-11-20):
//   • WICHTIGER FIX: ListView bekommt unten **kein Keyboard-Inset** mehr, sondern nur eine kleine
//     Reserve. Dadurch bleibt die letzte Nachricht direkt über dem Composer sichtbar – kein
//     „leerer Bildschirm nach Senden“ mehr, auch nicht mit offener Tastatur.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

// Zen-UI Widgets (wie im Projekt genutzt)
import '../../shared/ui/zen_widgets.dart'
    show ZenBackdrop, ZenGlassCard, ZenChipGhost;

class ReflectionViewProps {
  // Header / dekorativ
  final String headerTitle;
  final String? headerSubtitle;
  final String pandaAsset;

  // Bubbles oben
  final String? introText; // Pitch/Intro (oben, pinned-ähnlich)
  final String? smalltalkText; // kurzer Smalltalk des Panda (unter Intro)
  final String? bridgeText; // Bridge/Recall (optional, unter Smalltalk)

  // Leitfrage-Block
  final String? question; // Leitfrage (mit Fragezeichen)
  final String? helperSuggestion; // 0–1 Satz unter der Frage
  final List<String> talkLines; // kleine Talk-Zeilen (≤2)

  // Verlauf (bereits vorgerendert vom Orchestrator)
  final List<Widget> thread;

  // Typing-Indicator State (wird unter dem letzten User-Item gerendert)
  final bool isTyping;

  // Chips
  final List<String> chips; // Answer-Chips (insert-only; nur Worker-Helpers)
  final List<String> topicChips; // (deprecated/no-op) – wird nicht mehr gezeigt
  final ValueChanged<String>? onChipTap; // optional: externer Chip-Tap-Handler

  // Composer unten
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool canSend;
  final VoidCallback? onSend;
  final VoidCallback? onMicTap;
  final bool isRecording;
  final String composerHint; // NEU v6.8.3b – z.B. Fragebezogener Hint

  // Abschluss/Mood-CTA
  final bool allowClosure; // kompatibel belassen, aber UI gate nur über moodPrompt!
  final bool moodPrompt; // **allein maßgeblich** für CTA-Sichtbarkeit
  final VoidCallback? onClosureTap;

  // Risk/Hotline
  final bool risk;

  // Hope-Slot (kleiner, warmer Hinweis unter den Chips)
  final String? hopeText; // einfacher Text
  final Widget? hopeWidget; // alternativ: kompletter Widget-Slot

  // Footer-Disclaimer
  final String footerDisclaimer;

  // Optional: zusätzliche Abstände
  final double maxCardWidth;

  // Optional: Dev-Badge (Mem ON/OFF)
  final bool showDevMemBadge; // zeigt kleines Badge oben rechts
  final bool memoryOn; // true → „Mem ON“
  final int memoryCount; // n in „Mem ON (n)“

  const ReflectionViewProps({
    this.headerTitle = 'Ordne deine Gedanken',
    this.headerSubtitle,
    this.pandaAsset = 'assets/star_pa.png',
    this.introText,
    this.smalltalkText,
    this.bridgeText,
    this.question,
    this.helperSuggestion,
    this.talkLines = const <String>[],
    required this.thread,
    this.isTyping = false,
    required this.chips,
    this.topicChips = const <String>[], // no-op
    this.onChipTap,
    required this.controller,
    this.focusNode,
    required this.canSend,
    this.onSend,
    this.onMicTap,
    this.isRecording = false,
    this.composerHint = 'Antworte in 1–2 Sätzen.', // Default-Hint
    this.allowClosure = false,
    this.moodPrompt = false,
    this.onClosureTap,
    this.risk = false,
    this.hopeText,
    this.hopeWidget,
    this.footerDisclaimer =
        'Dies ist keine Therapie, sondern eine mentale Begleitungs-App.',
    this.maxCardWidth = 680,
    this.showDevMemBadge = false,
    this.memoryOn = false,
    this.memoryCount = 0,
  });
}

class ReflectionView extends StatefulWidget {
  final ReflectionViewProps props;
  const ReflectionView({super.key, required this.props});

  @override
  State<ReflectionView> createState() => _ReflectionViewState();
}

class _ReflectionViewState extends State<ReflectionView> {
  late final ScrollController _scroll;
  bool _stickToBottom = true; // auto-scroll nur, wenn Nutzer nahe unten ist
  bool _hasPendingNew = false; // zeigt Jump-to-Bottom FAB
  int _lastSignature = 0; // Content-Signatur für didUpdateWidget
  double _lastBottomInset = 0; // Keyboard-Änderungen erkennen

  // ——— Plattform-Helfer ———
  bool get _isDesktop {
    final p = defaultTargetPlatform;
    if (kIsWeb) return true; // Web wie Desktop behandeln
    return p == TargetPlatform.linux ||
        p == TargetPlatform.macOS ||
        p == TargetPlatform.windows ||
        p == TargetPlatform.fuchsia;
  }

  ScrollPhysics get _platformPhysics =>
      _isDesktop ? const ClampingScrollPhysics() : const BouncingScrollPhysics();

  double _effectiveBottomInset(double raw) {
    // Auf Desktop/Web kein Keyboard-Inset → 0; auf Mobile sanft klammern
    if (_isDesktop) return 0;
    final clamped = raw.clamp(0.0, 320.0);
    return clamped is double ? clamped : (clamped as num).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_onScroll);
    _lastSignature = _calcSignature(widget.props);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleAutoScroll(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant ReflectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSig = _calcSignature(widget.props);
    if (nextSig != _lastSignature) {
      _scheduleAutoScroll();
      _lastSignature = nextSig;
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // ————— Auto-Scroll Kernlogik —————

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // „Nahe unten“: noch <80 px Inhalt unterhalb
    final stick = _scroll.position.extentAfter < 80;
    if (stick != _stickToBottom) {
      setState(() => _stickToBottom = stick);
      if (stick && _hasPendingNew) {
        setState(() => _hasPendingNew = false);
      }
    }
  }

  void _jumpToEnd({bool animated = true}) {
    if (!_scroll.hasClients) return;
    final to = _scroll.position.maxScrollExtent;
    if (to <= 0) return; // Nichts zu scrollen
    if (animated) {
      _scroll.animateTo(
        to,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(to);
    }
  }

  void _scheduleAutoScroll({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (force || _stickToBottom) {
        _jumpToEnd(animated: true);
        if (_hasPendingNew) {
          setState(() => _hasPendingNew = false);
        }
      } else {
        if (!_hasPendingNew) setState(() => _hasPendingNew = true);
      }
    });
  }

  // Sehr simpler Content-Fingerprint, um Append zu erkennen
  int _calcSignature(ReflectionViewProps p) {
    int sig = 17;
    sig = 31 * sig + p.thread.length;
    sig = 31 * sig + (p.isTyping ? 1 : 0); // Typing-State beachten
    sig = 31 * sig + p.chips.length;
    sig = 31 * sig + (p.question ?? '').length;
    sig = 31 * sig + (p.helperSuggestion ?? '').length;
    sig = 31 * sig + p.talkLines.length;
    sig = 31 * sig + (p.smalltalkText ?? '').length;
    sig = 31 * sig + (p.bridgeText ?? '').length;
    sig = 31 * sig + (p.hopeText ?? '').length;
    sig = 31 * sig + (p.moodPrompt ? 1 : 0);
    return sig & 0x7fffffff;
  }

  // Wrapped onSend: ruft Caller und scrollt danach sicher nach unten
  VoidCallback? get _onSendWrapped {
    if (!widget.props.canSend || widget.props.onSend == null) return null;
    return () {
      widget.props.onSend!.call();
      _scheduleAutoScroll(force: true);
    };
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final w = size.width;
    final rawBottomInset = mq.viewInsets.bottom;

    // Debounce für Keyboard-Inset → weniger „Springen“ auf Android
    if ((_lastBottomInset - rawBottomInset).abs() > 6.0) {
      _lastBottomInset = rawBottomInset;
      _scheduleAutoScroll(); // sanft nachregeln
    }
    final bottomInset = _effectiveBottomInset(_lastBottomInset);
    // bottomInset wird weiterhin für sanftes Auto-Scrollen berücksichtigt,
    // aber NICHT mehr als zusätzlicher Padding-Abstand in der ListView genutzt.

    final cardMaxW = _cardMaxWidthFor(w, widget.props.maxCardWidth);
    final props = widget.props;

    final bool _showIntro = (props.introText ?? '').trim().isNotEmpty;
    final bool _showSmalltalk = (props.smalltalkText ?? '').trim().isNotEmpty;
    final bool _showBridge = (props.bridgeText ?? '').trim().isNotEmpty;
    final bool _showQuestion = (props.question ?? '').trim().isNotEmpty;
    final bool _showChips = props.chips.isNotEmpty;
    final bool _showHope =
        (props.hopeText ?? '').trim().isNotEmpty || props.hopeWidget != null;
    // Mood-CTA **nur** wenn moodPrompt==true
    final bool _showMoodCta = props.moodPrompt;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Solider Farb-Fallback (verhindert „Leerbildschirm“, falls Backdrop/Asset hakt)
          Positioned.fill(
            child: ColoredBox(color: Theme.of(context).colorScheme.surface),
          ),
          // Sanfter Hintergrund
          Positioned.fill(
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

          // Optionales Mini-Dev-Badge (oben rechts)
          if (props.showDevMemBadge)
            Positioned(
              top: 8,
              right: 8,
              child: _DevMemBadge(
                on: props.memoryOn,
                count: props.memoryCount,
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        // Desktop: Scrollbar sichtbar; Mobile: kein Thumb
                        ScrollConfiguration(
                          behavior: const _NoGlowScrollBehavior(),
                          child: _isDesktop
                              ? Scrollbar(
                                  controller: _scroll,
                                  thumbVisibility: true,
                                  child: _buildListView(
                                    cardMaxW,
                                    w,
                                    props,
                                    showIntro: _showIntro,
                                    showSmalltalk: _showSmalltalk,
                                    showBridge: _showBridge,
                                    showQuestion: _showQuestion,
                                    showChips: _showChips,
                                    showHope: _showHope,
                                    showMoodCta: _showMoodCta,
                                  ),
                                )
                              : _buildListView(
                                  cardMaxW,
                                  w,
                                  props,
                                  showIntro: _showIntro,
                                  showSmalltalk: _showSmalltalk,
                                  showBridge: _showBridge,
                                  showQuestion: _showQuestion,
                                  showChips: _showChips,
                                  showHope: _showHope,
                                  showMoodCta: _showMoodCta,
                                ),
                        ),

                        // „Nach unten“-FAB (nur zeigen, wenn neue Items da sind und User nicht unten ist)
                        if (_hasPendingNew && !_stickToBottom)
                          Positioned(
                            right: 12,
                            bottom: 96, // oberhalb der ComposerBar
                            child: FloatingActionButton.small(
                              onPressed: () {
                                setState(() => _hasPendingNew = false);
                                _jumpToEnd();
                              },
                              child: const Icon(Icons.arrow_downward_rounded),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Composer (unten, fix)
                  SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: cardMaxW),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
                          child: _ComposerBar(
                            controller: props.controller,
                            focusNode: props.focusNode,
                            hint: props.composerHint, // jetzt aus Props
                            canSend: props.canSend,
                            onSend: _onSendWrapped, // ← wrapped!
                            onMicTap: props.onMicTap,
                            isRecording: props.isRecording,
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
    );
  }

  Widget _buildListView(
    double cardMaxW,
    double w,
    ReflectionViewProps props, {
    required bool showIntro,
    required bool showSmalltalk,
    required bool showBridge,
    required bool showQuestion,
    required bool showChips,
    required bool showHope,
    required bool showMoodCta,
  }) {
    return ListView(
      controller: _scroll,
      physics: _platformPhysics,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      cacheExtent: 512,
      padding: const EdgeInsets.fromLTRB(
        0,
        0,
        0,
        12 + _kInputReserve,
      ),
      children: [
        // Header
        _Header(
          title: props.headerTitle,
          subtitle: props.headerSubtitle,
          pandaAsset: props.pandaAsset,
          pandaSize: w < 470 ? 100 : 126,
          maxWidth: cardMaxW,
        ),
        const SizedBox(height: 10),

        // Intro / Pitch Bubble
        if (showIntro)
          _BubbleCard(
            maxWidth: cardMaxW,
            child: Text(
              (props.introText ?? '').trim(),
              style: const TextStyle(height: 1.35),
            ),
          ),

        // Smalltalk-Bubble (kurz, neutral-warm)
        if (showSmalltalk)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _BubbleCard(
              emoji: '💬',
              maxWidth: cardMaxW,
              child: Text(
                (props.smalltalkText ?? '').trim(),
                style: const TextStyle(height: 1.35),
              ),
            ),
          ),

        // Bridge Bubble (Memory/Recall)
        if (showBridge)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _BubbleCard(
              emoji: '🪄',
              maxWidth: cardMaxW,
              child: _Markdownish((props.bridgeText ?? '').trim()),
            ),
          ),

        // Frage + helperSuggestion + Talk-Zeilen
        if (showQuestion)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardMaxW),
                child: _QuestionCard(
                  question: (props.question ?? '').trim(),
                  helperSuggestion:
                      (props.helperSuggestion ?? '').trim().isNotEmpty
                          ? props.helperSuggestion!.trim()
                          : null,
                  talkLines: props.talkLines.take(2).toList(),
                ),
              ),
            ),
          ),

        // Verlauf / Thread (bereits vorgerendert vom Orchestrator)
        ...props.thread.map(
          (w) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardMaxW),
                child: w,
              ),
            ),
          ),
        ),

        // Typing-Indicator direkt unter der letzten User-Bubble
        if (props.isTyping)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardMaxW),
                child: const _TypingBubble(),
              ),
            ),
          ),

        // Antwort-Chips (nur Worker-Helpers; Insert-only)
        if (showChips)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardMaxW),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in props.chips)
                      ZenChipGhost(
                        label: _normalizeChip(s),
                        onPressed: () => _onTapChip(context, s),
                      ),
                  ],
                ),
              ),
            ),
          ),

        // Hope Slot (kleiner, warmer Mutmacher)
        if (showHope)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardMaxW),
                child: props.hopeWidget ??
                    _HopeBubble(text: (props.hopeText ?? '').trim()),
              ),
            ),
          ),

        // Mood-CTA (nur wenn moodPrompt==true)
        if (showMoodCta)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardMaxW),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: props.onClosureTap,
                    icon: const Icon(Icons.emoji_emotions_rounded),
                    label: const Text('Stimmung teilen'),
                  ),
                ),
              ),
            ),
          ),

        // Risk/Hotline-Banner (leichtgewichtig, lokal)
        if (props.risk)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardMaxW),
                child: const _SafetyHotlineCard(),
              ),
            ),
          ),

        // Permanenter Footer-Disclaimer
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cardMaxW),
              child: Text(
                props.footerDisclaimer,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.25,
                      color: Colors.black.withValues(alpha: .72),
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onTapChip(BuildContext context, String raw) {
    final normalized = _normalizeChip(raw);
    // Externer Handler? → bevorzugen (z. B. direktes Senden)
    if (widget.props.onChipTap != null) {
      widget.props.onChipTap!(normalized);
      _scheduleAutoScroll();
      return;
    }
    // Insert-only ins Textfeld
    final cur = widget.props.controller.text;
    final needsSpace = cur.isNotEmpty && !RegExp(r'\s$').hasMatch(cur);
    final withEllipsis = _ensureEllipsisSpaceSuffix(normalized);
    final next = (needsSpace ? '$cur ' : cur) + withEllipsis;
    widget.props.controller
      ..text = next
      ..selection =
          TextSelection.fromPosition(TextPosition(offset: next.length));
    if (widget.props.focusNode != null) {
      FocusScope.of(context).requestFocus(widget.props.focusNode);
    }
    _scheduleAutoScroll();
  }

  String _normalizeChip(String s) {
    var t = s.trim().replaceAll(RegExp(r'[?؟]+$'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 72) t = '${t.substring(0, 72).trimRight()}…';
    t = t.replaceAll(RegExp(r'[.。]+$'), '').trim();
    return t;
  }

  String _ensureEllipsisSpaceSuffix(String s) {
    if (RegExp(r'…\s$').hasMatch(s)) return s;
    if (s.endsWith('…')) return '$s ';
    return '$s … ';
  }

  double _cardMaxWidthFor(double w, double max) {
    final inner = (w - 24).clamp(180.0, max); // nie <180, nie >max
    return inner is double ? inner : (inner as num).toDouble();
  }
}

// --------------------------- Header ------------------------------------------

class _Header extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String pandaAsset;
  final double pandaSize;
  final double maxWidth;
  const _Header({
    required this.title,
    required this.subtitle,
    required this.pandaAsset,
    required this.pandaSize,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Textblock links
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        height: 1.15,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          subtitle!.trim(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.28,
                            color: Colors.black.withValues(alpha: .72),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Panda rechts
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  pandaAsset,
                  width: pandaSize,
                  height: pandaSize,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------- Frage-Card --------------------------------------

class _QuestionCard extends StatelessWidget {
  final String question;
  final String? helperSuggestion;
  final List<String> talkLines;
  const _QuestionCard({
    required this.question,
    this.helperSuggestion,
    this.talkLines = const <String>[],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: theme.textTheme.titleMedium?.copyWith(height: 1.28),
          ),
          if ((helperSuggestion ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              helperSuggestion!.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.28,
                color: Colors.black.withValues(alpha: .70),
              ),
            ),
          ],
          if (talkLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TalkHints(lines: talkLines),
          ],
        ],
      ),
    );
  }
}

class _TalkHints extends StatelessWidget {
  final List<String> lines;
  const _TalkHints({required this.lines});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines.take(2))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💬 ', style: TextStyle(height: 1.35)),
                Expanded(
                  child: Text(
                    l.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// --------------------------- Bubbles -----------------------------------------

class _BubbleCard extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final String? emoji; // optionaler Akzent
  const _BubbleCard({required this.child, required this.maxWidth, this.emoji});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ZenGlassCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _HopeBubble extends StatelessWidget {
  final String text;
  const _HopeBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🌱', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------- Typing Bubble -----------------------------------

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: const [
          Text('Panda tippt', style: TextStyle(color: Colors.black54)),
          SizedBox(width: 6),
          _TypingDots(),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          double n(int i) =>
              (math.sin((_c.value * 2 * math.pi) + (i * .8)) + 1) / 2;
          final op0 = ((.35 + n(0) * .65) * .6).clamp(0.0, 1.0);
          final op1 = ((.35 + n(1) * .65) * .6).clamp(0.0, 1.0);
          final op2 = ((.35 + n(2) * .65) * .6).clamp(0.0, 1.0);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 4 + 3 * n(0),
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: op0),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 4,
                height: 4 + 3 * n(1),
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: op1),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 4,
                height: 4 + 3 * n(2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: op2),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// --------------------------- Composer ----------------------------------------

class _ComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final bool canSend;
  final VoidCallback? onSend;
  final VoidCallback? onMicTap;
  final bool isRecording;

  const _ComposerBar({
    required this.controller,
    this.focusNode,
    required this.hint,
    required this.canSend,
    this.onSend,
    this.onMicTap,
    this.isRecording = false,
  });

  @override
  Widget build(BuildContext context) {
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          // Mic
          IconButton(
            tooltip:
                isRecording ? 'Aufnahme stoppen' : 'Sprachaufnahme starten',
            onPressed: onMicTap,
            icon: Icon(
              isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
            ),
          ),
          const SizedBox(width: 4),
          // Input
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canSend) onSend?.call();
              },
              decoration: InputDecoration(
                hintText: hint, // nutzt jetzt das Prop
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          // Send
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Senden',
            onPressed: canSend ? onSend : null,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

// --------------------------- Mini Markdownish --------------------------------

class _Markdownish extends StatelessWidget {
  final String text;
  const _Markdownish(this.text);

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*[^*]+\*\*)');
    final parts = text.split(regex);
    for (final part in parts) {
      if (part.startsWith('**') && part.endsWith('**')) {
        spans.add(
          TextSpan(
            text: part.substring(2, part.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      } else {
        spans.add(TextSpan(text: part));
      }
    }
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(height: 1.35),
        children: spans,
      ),
    );
  }
}

// --------------------------- Safety Hotline (lokal) ---------------------------

class _SafetyHotlineCard extends StatelessWidget {
  const _SafetyHotlineCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ZenGlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wenn es dir nicht gut geht',
            style: theme.textTheme.titleSmall?.copyWith(height: 1.25),
          ),
          const SizedBox(height: 6),
          Text(
            'Du bist nicht allein. In akuten Krisen wende dich bitte an lokale Notfallnummern '
            'oder vertraute Menschen in deiner Nähe.',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.28,
              color: Colors.black.withValues(alpha: .72),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------- Dev Badge ---------------------------------------

class _DevMemBadge extends StatelessWidget {
  final bool on;
  final int count;
  const _DevMemBadge({required this.on, required this.count});

  @override
  Widget build(BuildContext context) {
    final bg = on
        ? const Color(0xFF2E7D32).withValues(alpha: .90)
        : Colors.black.withValues(alpha: .60);
    const fg = Colors.white;
    final label = on ? 'Mem ON (${count.clamp(0, 999)})' : 'Mem OFF';
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.memory_rounded,
              size: 16,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: fg,
                fontSize: 11,
                height: 1.2,
                letterSpacing: .1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------- ScrollBehavior (kein Glow) -----------------------

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

// --------------------------- Consts ------------------------------------------

const double _kInputReserve = 32;
