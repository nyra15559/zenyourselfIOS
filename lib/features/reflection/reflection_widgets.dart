// [BASELINE] lib/features/reflection/reflection_widgets.dart (Stand: 29.10., v6.3.2)
// lib/features/reflection/reflection_widgets.dart
// Part: UI-Widgets (library: reflection_screen)
// -----------------------------------------------------------------------------
// Oxford–Zen v6.11 — Reflection UI (calm type & fixes, 2025-appear)
// - Intro-Text angepasst (Hallo – wie geht es dir? … Schreib’s mir in 1–2 Sätzen …)
// - Typing-Row: Punkte NACH dem Text, kein führendes „…“
// - Leitfrage: gleicher ruhiger Stil wie Mirror (keine Bold-Überschrift)
// - Memory/RecentTopics vorhanden (Kompat.), Screen zeigt sie aber nicht an
// - Hope Slot integriert (kurzer, hoffnungsvoller Satz unter der Frage)
// - v6.10.1: Hope-Compat (s.hopeText → s.hopeTextCompat()) + withValues-Fixes
// - v6.11: Kleiner Dev-Indikator (nur Debug) – dezenter Punkt mit Tooltip
// - v6.3.2 (29.10.): A11y/Copy-Tooltips verlässlich, leichte Const/Spacing-Polish
// -----------------------------------------------------------------------------
//
// + v6.12 (neu):
//   • PandaBubbleFooter(actions): Footer-Aktionen (max. 2 + Overflow „Mehr“)
//   • SkillCardList(cards): horizontale Skill-/Info-Karten (Glas), mit Demo-Fallback
//   • ContextPinBar(...): „sticky“ nutzbar (durch Parent), Outline-Pills mit klarer
//     Abgrenzung zu Antwort-Chips; A11y-Labels, Fokus-Reihenfolge & Ellipsis.
//
// -----------------------------------------------------------------------------

part of 'reflection_screen.dart';

// Tokens / constants
const _kRadius14 = BorderRadius.all(Radius.circular(14));
const _kRadius16 = BorderRadius.all(Radius.circular(16));
const _kRadius18 = BorderRadius.all(Radius.circular(18));

const _kGlassTop = .20;
const _kGlassBottom = .20;
const _kGlassBorder = .22;

const _kInk = ZenColors.ink;
const _kInkStrong = ZenColors.inkStrong;
const _kJade = ZenColors.jade;

const _kAnimShort = Duration(milliseconds: 240);

bool get _isDesktop {
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return true;
    default:
      return false;
  }
}

/// ---------------------------------------------------------------------------
/// 2025-Level: sanfte Appear-Animation (Fade + Slide + minimal Scale)
/// ---------------------------------------------------------------------------
class _ZenAppear extends StatefulWidget {
  final Widget child;
  final Duration? delay;

  /// Von -> nach; Standard: leicht von unten (zartes Auftauchen).
  final Offset slide;

  /// Start-Skalierung für minimalen „Pop“.
  final double beginScale;

  const _ZenAppear({
    required this.child,
    this.delay,
    this.slide = const Offset(0, 0.02), // ✅ Default
    this.beginScale = 0.98, // ✅ Default
  });

  @override
  State<_ZenAppear> createState() => _ZenAppearState();
}

class _ZenAppearState extends State<_ZenAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _kAnimShort);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slideAnim = Tween<Offset>(
    begin: widget.slide,
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_c);
  late final Animation<double> _scale = Tween<double>(
    begin: widget.beginScale,
    end: 1.0,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_c);

  @override
  void initState() {
    super.initState();
    if (widget.delay == null || widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay!, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slideAnim,
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}

// Header
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
    return _ZenAppear(
      // explizit setzen ⇒ vermeidet "optional parameter ... isn't ever given"
      slide: const Offset(0, 0.02),
      beginScale: 0.98,
      child: PandaHeader(
        title: title,
        caption: subtitle.trim().isEmpty ? null : subtitle,
        pandaSize: pandaSize,
        strongTitleGreen: true,
      ),
    );
  }
}

// Intro
class _IntroBubble extends StatelessWidget {
  const _IntroBubble();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: const RepaintBoundary(
          child: ZenGlassCard(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
            topOpacity: _kGlassTop,
            bottomOpacity: _kGlassBottom,
            borderOpacity: _kGlassBorder,
            borderRadius: _kRadius16,
            child: SelectableText(
              'Hallo – wie geht es dir? Was bewegt dich gerade? '
              'Schreib’s mir in 1–2 Sätzen. '
              'Du entscheidest, ob es gespeichert wird – dann steht es im Gedankenbuch.',
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.42,
                color: Color(0xDE000000), // ruhiges Ink @.87
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Thread
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

  void _showCopyToast(BuildContext context, [String msg = 'Kopiert']) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        backgroundColor: ZenColors.deepSage,
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    final message = text.trim();
    if (message.isEmpty) return;
    Clipboard.setData(ClipboardData(text: message));
    _showCopyToast(context);
    HapticFeedback.selectionClick();
  }

  // User bubble
  Widget _buildUserBubble(BuildContext context, String title, String body) {
    final tt = Theme.of(context).textTheme;
    final tooltip =
        _isDesktop ? 'Rechtsklick zum Kopieren' : 'Lange drücken zum Kopieren';

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: _ZenAppear(
          // User-Bubble leicht schneller
          delay: const Duration(milliseconds: 60),
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              onLongPress: () => _copyToClipboard(context, body),
              onSecondaryTap: () => _copyToClipboard(context, body),
              child: Semantics(
                label: '$title: $body',
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: _kRadius18,
                    border: Border.all(
                      color: Colors.black.withValue(alpha: .06),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.labelSmall?.copyWith(
                          color: _kInk.withValue(alpha: .75),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        body,
                        style: tt.bodyLarge?.copyWith(
                          color: _kInkStrong,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Panda card
  Widget _buildPandaStepCard(
    BuildContext context,
    _PandaStep s, {
    required bool showTyping, // ✅ wird bewusst als Trigger behalten
    bool suppressQuestion = false,
    Duration appearDelay = Duration.zero,
  }) {
    // bewusstes no-op, damit Analyzer keinen unused_element_parameter meldet
    if (showTyping) {
      // Typing-Indicator wird an anderer Stelle gehandhabt.
    }

    final tooltip =
        _isDesktop ? 'Rechtsklick zum Kopieren' : 'Lange drücken zum Kopieren';

    final buffer = StringBuffer();
    if (s.mirror.trim().isNotEmpty) buffer.writeln(s.mirror.trim());
    for (final t in s.talkLines) {
      final line = t.trim();
      if (line.isNotEmpty) buffer.writeln(line);
    }
    if (!suppressQuestion && s.question.trim().isNotEmpty) {
      buffer.writeln(s.question.trim());
    }
    if (!suppressQuestion && (s.helperSuggestion ?? '').trim().isNotEmpty) {
      buffer.writeln((s.helperSuggestion ?? '').trim());
    }
    // Hope nicht in die Kopie erzwingen – bleibt kurz/optional in der UI.
    final copyAll = buffer.toString();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: _ZenAppear(
          delay: appearDelay,
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              onLongPress: () => _copyToClipboard(context, copyAll),
              onSecondaryTap: () => _copyToClipboard(context, copyAll),
              child: const RepaintBoundary(
                child: ZenGlassCard(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
                  topOpacity: _kGlassTop,
                  bottomOpacity: _kGlassBottom,
                  borderOpacity: _kGlassBorder,
                  borderRadius: _kRadius18,
                  child: _PandaCardInner(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // Abschluss-Phase aktiv? -> suppressQuestion für die letzte Panda-Karte setzen
    final bool closureActive = round.answered &&
        round.allowClosure &&
        !round.hasPendingQuestion &&
        !round.hasMood;

    // Benutzer-Gedanke
    final userText = round.userInput.trim();
    if (userText.isNotEmpty) {
      children.add(_buildUserBubble(context, 'Gedanke', userText));
      children.add(const SizedBox(height: 10));
    }

    // Panda-Schritte (mit leichtem Stagger)
    for (int i = 0; i < round.steps.length; i++) {
      final s = round.steps[i];
      final isLastStep = i == round.steps.length - 1;
      final stagger = Duration(milliseconds: 60 * (i.clamp(0, 3)));

      children.add(
        _PandaStepScope(
          step: s,
          suppressQuestion: closureActive && isLastStep,
          timeStamp: _fmtDayTime(round.ts),
          child: _buildPandaStepCard(
            context,
            s,
            showTyping: isLast && isTyping && isLastStep,
            suppressQuestion: closureActive && isLastStep,
            appearDelay: stagger,
          ),
        ),
      );

      if (s.hasAnswer) {
        children
          ..add(const SizedBox(height: 8))
          ..add(_buildUserBubble(context, 'Antwort', s.answer!.trim()));
      }

      children.add(const SizedBox(height: 10));
    }

    // Placeholder beim ersten Turn
    if (round.steps.isEmpty && isTyping) {
      children
        ..add(
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: const RepaintBoundary(
                child: ZenGlassCard(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                  topOpacity: _kGlassTop,
                  bottomOpacity: _kGlassBottom,
                  borderOpacity: _kGlassBorder,
                  borderRadius: _kRadius18,
                  child: _TypingRow(),
                ),
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 10));
    }

    // Abschluss → Stimmung (gated)
    if (closureActive) {
      // Optional: mood_intro-Blase vor dem Abschluss
      final intro = (round.moodIntro ?? '').trim();
      if (intro.isNotEmpty) {
        children
          ..add(
            _ZenAppear(
              delay: const Duration(milliseconds: 60),
              child: _MoodIntroBubble(text: intro, maxWidth: maxWidth),
            ),
          )
          ..add(const SizedBox(height: 10));
      }

      children
        ..add(
          _ZenAppear(
            delay: const Duration(milliseconds: 100),
            child: _CompletionCard(maxWidth: maxWidth),
          ),
        )
        ..add(const SizedBox(height: 10))
        ..add(
          _ZenAppear(
            delay: const Duration(milliseconds: 140),
            child: _MoodChooserInline(
              onSelected: onSelectMood,
              maxWidth: maxWidth,
            ),
          ),
        )
        ..add(const SizedBox(height: 10));
    }

    // Actions nach Mood
    if (round.answered && round.hasMood) {
      children.add(
        _ZenAppear(
          delay: const Duration(milliseconds: 80),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Wrap(
              key: ValueKey('actions_${round.id}'),
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (onSave != null)
                  ZenPrimaryButton(
                    label: 'Ins Gedankenbuch speichern',
                    icon: Icons.bookmark_added_rounded,
                    onPressed: onSave!,
                  ),
                if (onDelete != null)
                  ZenOutlineButton(
                    label: 'Löschen',
                    icon: Icons.delete_outline_rounded,
                    onPressed: onDelete!,
                    color: _kInkStrong,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Safety
    if ((safetyText ?? '').isNotEmpty) {
      children
        ..add(const SizedBox(height: 10))
        ..add(
          _ZenAppear(
            delay: const Duration(milliseconds: 60),
            child: _SafetyNote(text: safetyText!, maxWidth: maxWidth),
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  String _fmtDayTime(DateTime ts) {
    final l = ts.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year}, ${two(l.hour)}:${two(l.minute)}';
  }
}

// Kleinzeug & restliche Widgets
class _DividerThin extends StatelessWidget {
  const _DividerThin();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        color: Colors.black.withValue(alpha: .10),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _ReflectionHint extends StatelessWidget {
  const _ReflectionHint();
  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: Icon(Icons.self_improvement, size: 16, color: Colors.black54),
        ),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'Lies die Frage kurz. Antworte in 1–2 Sätzen.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

class _SafetyNote extends StatelessWidget {
  final String text;
  final double maxWidth;
  const _SafetyNote({required this.text, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sicherheits-Hinweis',
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: RepaintBoundary(
            child: ZenGlassCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              topOpacity: _kGlassTop,
              bottomOpacity: _kGlassBottom - .12,
              borderOpacity: _kGlassBorder,
              borderRadius: _kRadius14,
              child: _SafetyScope(
                text: text,
                child: const _SafetyRow(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  final double maxWidth;
  const _CompletionCard({required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: const RepaintBoundary(
          child: ZenGlassCard(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
            topOpacity: _kGlassTop,
            bottomOpacity: _kGlassBottom,
            borderOpacity: _kGlassBorder,
            borderRadius: _kRadius16,
            child: _CompletionRow(),
          ),
        ),
      ),
    );
  }
}

// Mood Chooser
class _MoodChooserInline extends StatelessWidget {
  final void Function(int score, String label)? onSelected;
  final double maxWidth;
  const _MoodChooserInline({this.onSelected, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: RepaintBoundary(
          child: ZenGlassCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            topOpacity: _kGlassTop,
            bottomOpacity: _kGlassBottom,
            borderOpacity: _kGlassBorder,
            borderRadius: _kRadius16,
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(Icons.mood_rounded, size: 18, color: _kInk),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Zum Speichern: Stimmung wählen',
                    style: tt.bodyMedium?.copyWith(color: _kInk),
                  ),
                ),
                ZenPrimaryButton(
                  label: 'Speichern',
                  icon: Icons.bookmark_added_rounded,
                  onPressed: () async {
                    final m = await showPandaMoodPicker(
                      context,
                      title: 'Wähle deine Stimmung',
                    );
                    if (m != null && onSelected != null) {
                      onSelected!(_scoreForMood(m), m.labelDe);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _scoreForMood(PandaMood m) {
    final v = m.valence;
    if (v <= -0.60) return 0;
    if (v <= -0.20) return 1;
    if (v < 0.20) return 2;
    if (v < 0.60) return 3;
    return 4;
  }
}

// Input
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
    final tt = Theme.of(context).textTheme;

    final List<BoxShadow> pulse = isRecording
        ? [
            const BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: _kJade.withValue(alpha: 0.30),
              blurRadius: 22,
              spreadRadius: 1.2,
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x15000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final suffixW = constraints.maxWidth < 360 ? 108.0 : 140.0;

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: pulse),
                ),
              ),
            ),
            ZenGlassInput(
              borderRadius: _kRadius16,
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final trimmed = value.text.trim();
                  final hasText = trimmed.isNotEmpty;
                  final used = trimmed.length;
                  final overSoft = used > kInputSoftLimit;

                  return TextField(
                    focusNode: focusNode,
                    controller: controller,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: true,
                    spellCheckConfiguration:
                        const SpellCheckConfiguration.disabled(),
                    style: tt.bodyMedium!.copyWith(
                      color: _kInkStrong,
                      fontWeight: FontWeight.w600,
                    ),
                    cursorColor: _kJade,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: tt.bodyMedium!
                          .copyWith(color: _kInk.withValue(alpha: .55)),
                      border: InputBorder.none,
                      isCollapsed: true,
                      suffixIconConstraints:
                          BoxConstraints.tightFor(width: suffixW, height: 40),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 180),
                              style: tt.bodySmall!.copyWith(
                                fontSize: 12,
                                color: overSoft
                                    ? Colors.redAccent.withValue(alpha: .85)
                                    : _kInk.withValue(alpha: .65),
                                fontWeight: FontWeight.w600,
                              ),
                              child: Text(
                                '$used/$kInputSoftLimit',
                                semanticsLabel:
                                    'Zeichen: $used von $kInputSoftLimit',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip:
                                isRecording ? 'Aufnahme stoppen' : 'Sprechen',
                            onPressed: onMicTap,
                            icon: Icon(
                              isRecording
                                  ? Icons.stop_circle_rounded
                                  : Icons.mic_rounded,
                              color: _kJade,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Senden (Enter)',
                            onPressed: (hasText && canSend && onSend != null)
                                ? onSend
                                : null,
                            icon: Icon(
                              Icons.send_rounded,
                              color: (hasText && canSend && onSend != null)
                                  ? _kJade
                                  : _kJade.withValue(alpha: 0.45),
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
      },
    );
  }
}

// Typing dots
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

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
          double n(int i) => (sin((_c.value * 2 * pi) + (i * .8)) + 1) / 2;
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
                  color: Colors.black.withValue(alpha: op0),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 4,
                height: 4 + 3 * n(1),
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValue(alpha: op1),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 4,
                height: 4 + 3 * n(2),
                decoration: BoxDecoration(
                  color: Colors.black.withValue(alpha: op2),
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

class _TypingRow extends StatelessWidget {
  const _TypingRow();
  @override
  Widget build(BuildContext context) {
    // Fix: Punkte gehören ans ENDE – Text ohne Ellipsis, Dots folgen danach.
    return const Row(
      children: [
        Text('Panda tippt', style: TextStyle(color: Colors.black54)),
        SizedBox(width: 6),
        _TypingDots(),
      ],
    );
  }
}

// Mood-Intro Bubble (optional)
class _MoodIntroBubble extends StatelessWidget {
  final String text;
  final double maxWidth;
  const _MoodIntroBubble({required this.text, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: RepaintBoundary(
          child: ZenGlassCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            topOpacity: _kGlassTop,
            bottomOpacity: _kGlassBottom,
            borderOpacity: _kGlassBorder,
            borderRadius: _kRadius16,
            child: _MoodIntroScope(
              text: text,
              child: const _MoodIntroRow(),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------- NEU: PandaBridgeBubble ---------------------------

/// Warme, kurze Brücke aus dem Memory-Recall.
/// Hinweis: Screen zeigt diese Bubble nicht mehr an.
class PandaBridgeBubble extends StatelessWidget {
  final String text;
  final IconData icon;

  const PandaBridgeBubble({
    super.key,
    required this.text,
    this.icon = Icons.link_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final display = text.replaceAll('**', '').trim();
    final tooltip =
        _isDesktop ? 'Rechtsklick zum Kopieren' : 'Lange drücken zum Kopieren';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _ZenAppear(
          delay: const Duration(milliseconds: 40),
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              onLongPress: () =>
                  Clipboard.setData(ClipboardData(text: display)),
              onSecondaryTap: () =>
                  Clipboard.setData(ClipboardData(text: display)),
              child: Semantics(
                label: 'Brücke: $display',
                child: RepaintBoundary(
                  child: ZenGlassCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    topOpacity: _kGlassTop,
                    bottomOpacity: _kGlassBottom,
                    borderOpacity: _kGlassBorder,
                    borderRadius: _kRadius16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ExcludeSemantics(
                          child:
                              Icon(Icons.link_rounded, size: 18, color: _kInk),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            display,
                            style: tt.bodyMedium?.copyWith(
                              color: _kInk.withValue(alpha: .87),
                              height: 1.33,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------- Small inner widgets -----------------------------

class _PandaCardInner extends StatelessWidget {
  const _PandaCardInner();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scope = _PandaStepScope.of(context);

    final s = scope.step;
    final suppressQuestion = scope.suppressQuestion;

    final children = <Widget>[];

    if (s.mirror.trim().isNotEmpty) {
      children.add(
        SelectableText(
          s.mirror.trim(),
          style: tt.bodyMedium?.copyWith(
            color: _kInk.withValue(alpha: .87),
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
    }

    for (final line in s.talkLines) {
      final t = line.trim();
      if (t.isEmpty) continue;
      children.add(
        SelectableText(
          t,
          style: tt.bodyMedium?.copyWith(
            color: _kInk.withValue(alpha: .87),
            height: 1.34,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
      children.add(const SizedBox(height: 6));
    }

    if (!suppressQuestion && s.question.trim().isNotEmpty) {
      children.add(const _DividerThin());
      children.add(const SizedBox(height: 8));
      // Calm question — gleicher Stil wie Mirror (keine Bold-Überschrift)
      children.add(
        SelectableText(
          s.question.trim(),
          style: tt.bodyMedium?.copyWith(
            color: _kInkStrong,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    // HelperSuggestion: nur zeigen, wenn Frage sichtbar (gleiche Achse, sanfter Satz)
    if (!suppressQuestion && (s.helperSuggestion ?? '').trim().isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child:
                  Icon(Icons.tips_and_updates_rounded, size: 18, color: _kInk),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                (s.helperSuggestion ?? '').trim(),
                style: tt.bodySmall?.copyWith(
                  color: _kInk.withValue(alpha: .87),
                  height: 1.30,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ---------------------- Hope Slot (optional) ----------------------
    // Kurzer, hoffnungsvoller Satz unterhalb der Frage/HelperSuggestion.
    final hope = s.hopeTextCompat();
    if (!suppressQuestion && (hope ?? '').trim().isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.auto_awesome_rounded, size: 18, color: _kInk),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                (hope ?? '').trim(),
                style: tt.bodySmall?.copyWith(
                  color: _kInk.withValue(alpha: .87),
                  height: 1.30,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Timestamp + (nur Debug) kleiner Dev-Indikator
    children.add(const SizedBox(height: 6));
    children.add(
      const Row(
        children: [
          _DevIndicator(), // zeigt in Release NICHTS
          Spacer(),
          ExcludeSemantics(
            child: Opacity(
              opacity: .55,
              child: _TimeStampText(),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _TimeStampText extends StatelessWidget {
  const _TimeStampText();
  @override
  Widget build(BuildContext context) {
    final scope = _PandaStepScope.of(context);
    final tt = Theme.of(context).textTheme;
    return Text(
      scope.timeStamp,
      style: tt.bodySmall?.copyWith(fontSize: 12, color: _kInk),
    );
  }
}

// --- Kleiner Dev-Indikator (nur Debug) ---------------------------------------

class _DevIndicator extends StatelessWidget {
  const _DevIndicator();

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final scope = _PandaStepScope.of(context);
    final s = scope.step;

    final hasQ = s.question.trim().isNotEmpty;
    final helpers = s.followups.length;
    final risk = s.risk;
    final hope = (s.hopeTextCompat() ?? '').trim().isNotEmpty;
    final talk = s.talkLines.length;
    final mirrorLen = s.mirror.trim().length;

    // Farb-Codierung: Risk > Helpers > Neutral
    final Color dotColor = risk
        ? Colors.orange
        : (helpers > 0 ? _kJade : Colors.black.withValue(alpha: .45));

    final tooltip =
        'm:$mirrorLen  q:${hasQ ? 1 : 0}  h:$helpers  talk:$talk  hope:${hope ? 1 : 0}';

    return Tooltip(
      message: 'DEV $tooltip',
      child: ExcludeSemantics(
        child: Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withValue(alpha: .10),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodIntroRow extends StatelessWidget {
  const _MoodIntroRow();
  @override
  Widget build(BuildContext context) {
    final scope = _MoodIntroScope.maybeOf(context);
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(
          child: Icon(Icons.spa_rounded, size: 18, color: _kInk),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            scope?.text ?? '',
            style: tt.bodyMedium?.copyWith(
              color: _kInk.withValue(alpha: .87),
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow();
  @override
  Widget build(BuildContext context) {
    final scope = _SafetyScope.maybeOf(context);
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(
          child: Icon(Icons.health_and_safety_rounded,
              color: Colors.orange, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            scope?.text ?? '',
            style: tt.bodySmall?.copyWith(color: _kInk),
          ),
        ),
      ],
    );
  }
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow();
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        ExcludeSemantics(
          child: Icon(Icons.check_circle_rounded, color: _kJade, size: 20),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Gut gemacht 🐼✨ — du hast das Wichtigste festgehalten.',
            style: TextStyle(
              // Calm tone; Farbe kommt vom DefaultTextStyle außen
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------- Chips (neu) ----------------------------------

// Reusable Ghost-Chip mit Jade-Rand
class _GhostChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  const _GhostChip({
    required this.label,
    this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final text = label.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValue(alpha: .66),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kJade.withValue(alpha: .65), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: _kInkStrong,
          height: 1.15,
        ),
      ),
    );

    return Semantics(
      button: true,
      label: semanticsLabel ?? text,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

/// Chips: „Letzte Themen“ (Memory) – Screen blendet sie nicht mehr ein.
// ignore: unused_element
class _RecentTopicsChips extends StatelessWidget {
  final List<String> topics;
  final void Function(String topic)? onPick;
  final double maxWidth;
  const _RecentTopicsChips({
    required this.topics,
    required this.maxWidth,
    // ignore: unused_element_parameter
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final items = topics
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(3)
        .toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    final tt = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: _ZenAppear(
          delay: const Duration(milliseconds: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Zuletzt bewegt:',
                style: tt.labelSmall?.copyWith(
                  color: _kInk.withValue(alpha: .75),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in items)
                    _GhostChip(
                      label: t,
                      semanticsLabel: 'Thema: $t',
                      onTap: onPick == null
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              onPick!(t);
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
}

/// Chips: „Antwort-Chips“ (answer_helpers vom Worker)
// ignore: unused_element
class _AnswerHelperChips extends StatelessWidget {
  final List<String> helpers; // max. 3
  final void Function(String text)? onPick;
  final double maxWidth;
  const _AnswerHelperChips({
    required this.helpers,
    required this.maxWidth,
    // ignore: unused_element_parameter
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final items = helpers
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.endsWith('?'))
        .take(3)
        .toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: _ZenAppear(
          delay: const Duration(milliseconds: 60),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in items)
                _GhostChip(
                  label: h,
                  semanticsLabel: 'Antwort-Vorschlag: $h',
                  onTap: onPick == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onPick!(h);
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------- Inherited Scopes ----------------------------

class _PandaStepScope extends InheritedWidget {
  final _PandaStep step;
  final bool suppressQuestion;
  final String timeStamp;

  const _PandaStepScope({
    required this.step,
    required this.suppressQuestion,
    required this.timeStamp,
    required super.child,
  });

  static _PandaStepScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PandaStepScope>()!;

  @override
  bool updateShouldNotify(_PandaStepScope oldWidget) =>
      oldWidget.step != step ||
      oldWidget.suppressQuestion != suppressQuestion ||
      oldWidget.timeStamp != timeStamp;
}

class _MoodIntroScope extends InheritedWidget {
  final String text;
  const _MoodIntroScope({
    required this.text,
    required super.child,
  });

  static _MoodIntroScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MoodIntroScope>();

  @override
  bool updateShouldNotify(_MoodIntroScope oldWidget) => oldWidget.text != text;
}

class _SafetyScope extends InheritedWidget {
  final String text;
  const _SafetyScope({
    required this.text,
    required super.child,
  });

  static _SafetyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SafetyScope>();

  @override
  bool updateShouldNotify(_SafetyScope oldWidget) => oldWidget.text != text;
}

// -----------------------------------------------------------------------------
// Kompatibilitäts-Extension für Hope-Text (_PandaStep.hopeTextCompat())
// Liest robust aus alten/neuen Feldern oder aus speech_sequence (type == "hope").
// -----------------------------------------------------------------------------
extension _PandaStepCompatExt on _PandaStep {
  String? hopeTextCompat() {
    // 1) Legacy: direkter Getter/Feld "hopeText"
    try {
      final v = (this as dynamic).hopeText;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}

    // 2) Neues Feld "hope"
    try {
      final v = (this as dynamic).hope;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}

    // 3) Sequenz durchsuchen
    try {
      final seq = (this as dynamic).speechSequence;
      if (seq is List) {
        for (final e in seq) {
          if (e is Map && e['type'] == 'hope' && e['text'] is String) {
            final t = (e['text'] as String).trim();
            if (t.isNotEmpty) return t;
          } else {
            try {
              final t = (e as dynamic).type;
              final txt = (e as dynamic).text;
              if (t == 'hope' && txt is String && txt.trim().isNotEmpty) {
                return txt.trim();
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return null;
  }
}

// ============================================================================
// v6.12 — NEU: Footer-Aktionen (max. 2 + Overflow), SkillCardList, ContextPinBar
// ============================================================================

/// Datenobjekt für Footer-Aktionen (klar getrennt von Antwort-Chips).
class PandaFooterAction {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? semanticsLabel;

  const PandaFooterAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.semanticsLabel,
  });
}

/// Outline-Pill (klarer Outline-Look; unterscheidet sich bewusst von Ghost-Chips).
class _OutlinePillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticsLabel;

  const _OutlinePillButton({
    required this.label,
    required this.icon,
    this.onPressed,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 118, minHeight: 40),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape:
                const StadiumBorder(side: BorderSide(color: ZenColors.outline)),
            side: const BorderSide(color: ZenColors.outline, width: 1.0),
            foregroundColor: _kInkStrong,
            textStyle: tt.labelLarge?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer unter einer Panda-Karte. Zeigt max. 2 Primär-Aktionen; Rest im Overflow.
class PandaBubbleFooter extends StatelessWidget {
  final List<PandaFooterAction> actions;
  final double maxWidth;
  final String overflowLabel;
  final IconData overflowIcon;

  const PandaBubbleFooter({
    super.key,
    required this.actions,
    this.maxWidth = 680,
    this.overflowLabel = 'Mehr',
    this.overflowIcon = Icons.more_horiz_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final visible = actions.take(2).toList(growable: false);
    final overflow = actions.length > 2 ? actions.sublist(2) : const <PandaFooterAction>[];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: _ZenAppear(
          delay: const Duration(milliseconds: 80),
          child: RepaintBoundary(
            child: ZenGlassCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              topOpacity: _kGlassTop,
              bottomOpacity: _kGlassBottom,
              borderOpacity: _kGlassBorder,
              borderRadius: _kRadius16,
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (int i = 0; i < visible.length; i++)
                      FocusTraversalOrder(
                        order: NumericFocusOrder(i.toDouble()),
                        child: _OutlinePillButton(
                          label: visible[i].label,
                          icon: visible[i].icon,
                          onPressed: visible[i].onPressed,
                          semanticsLabel:
                              visible[i].semanticsLabel ?? visible[i].label,
                        ),
                      ),
                    if (overflow.isNotEmpty)
                      FocusTraversalOrder(
                        order: NumericFocusOrder(visible.length.toDouble()),
                        child: _OverflowPillMenu(
                          label: overflowLabel,
                          icon: overflowIcon,
                          items: overflow,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverflowPillMenu extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<PandaFooterAction> items;

  const _OverflowPillMenu({
    required this.label,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '$label – weitere Aktionen',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 118, minHeight: 40),
        child: PopupMenuButton<int>(
          tooltip: label,
          position: PopupMenuPosition.under,
          itemBuilder: (ctx) => [
            for (int i = 0; i < items.length; i++)
              PopupMenuItem<int>(
                value: i,
                child: Row(
                  children: [
                    Icon(items[i].icon, size: 18, color: _kInkStrong),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _kInkStrong,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onSelected: (i) {
            if (i >= 0 && i < items.length) items[i].onPressed();
          },
          // Wichtig: Kein "deaktivierter" Button als Child, damit es visuell nicht disabled wirkt.
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: ShapeDecoration(
              shape: StadiumBorder(
                side: BorderSide(color: ZenColors.outline),
                ),
              color: Colors.transparent,
              shadows: const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: _kInkStrong),
                const SizedBox(width: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelLarge?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kInkStrong,
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

/// Datenmodell für eine Skill-/Info-Karte.
class SkillCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  const SkillCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.semanticsLabel,
  });
}

/// Horizontale Liste kleiner Glas-Karten (klar getrennt von Antwort-Chips).
class SkillCardList extends StatelessWidget {
  final List<SkillCardData> cards;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final bool dense;

  const SkillCardList({
    super.key,
    required this.cards,
    this.maxWidth = 680,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
    this.dense = true,
  });

  /// Bequemer Demo-Ctor mit Platzhalterdaten.
  factory SkillCardList.demo({double maxWidth = 680}) {
    return SkillCardList(
      maxWidth: maxWidth,
      cards: const [
        SkillCardData(
          icon: Icons.tips_and_updates_rounded,
          title: 'Kleiner Tipp',
          subtitle: 'Atme einmal ruhig aus, bevor du antwortest.',
        ),
        SkillCardData(
          icon: Icons.bookmark_border_rounded,
          title: 'Gedankenbuch',
          subtitle: 'Du entscheidest, was gespeichert wird.',
        ),
        SkillCardData(
          icon: Icons.lock_rounded,
          title: 'Datenschutz',
          subtitle: 'Ghost-Mode lässt alles lokal.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemW = dense ? 220.0 : 260.0;
    final itemH = dense ? 84.0 : 100.0;

    if (cards.isEmpty) return const SizedBox.shrink();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: _ZenAppear(
          delay: const Duration(milliseconds: 60),
          child: SizedBox(
            height: itemH,
            child: ListView.separated(
              padding: padding,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final c = cards[i];
                return _SkillCard(
                  data: c,
                  width: itemW,
                  height: itemH,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final SkillCardData data;
  final double width;
  final double height;

  const _SkillCard({
    required this.data,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final card = SizedBox(
      width: width,
      height: height,
      child: ZenGlassCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        topOpacity: _kGlassTop,
        bottomOpacity: _kGlassBottom,
        borderOpacity: _kGlassBorder,
        borderRadius: _kRadius14,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(data.icon, size: 20, color: _kInkStrong),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelLarge?.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: _kInkStrong,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: _kInk.withValue(alpha: .85),
                      height: 1.22,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (data.onTap == null) {
      return card;
    }

    return Semantics(
      button: true,
      label: data.semanticsLabel ?? data.title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: _kRadius14,
          onTap: data.onTap,
          child: card,
        ),
      ),
    );
  }
}

/// Kontext-Leiste mit Outline-Pills (z. B. Name/Consent/Modus). „Sticky“ über
/// Parent (z. B. SliverPersistentHeader) nutzbar; hier nur der visuelle Block.
class ContextPinBar extends StatelessWidget {
  final List<Widget> pills;
  final double maxWidth;
  final bool elevated;
  final EdgeInsetsGeometry padding;
  final String? semanticsLabel;

  const ContextPinBar({
    super.key,
    required this.pills,
    this.maxWidth = 680,
    this.elevated = true,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 8),
    this.semanticsLabel,
  });

  /// Bequeme Fabrik mit einfachen Text-Pills (Outline-Stil).
  factory ContextPinBar.simple({
    required List<String> labels,
    double maxWidth = 680,
    bool elevated = true,
  }) {
    return ContextPinBar(
      maxWidth: maxWidth,
      elevated: elevated,
      pills: labels
          .map((t) => _OutlineTextPill(label: t))
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shadow = elevated
        ? const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            )
          ]
        : const <BoxShadow>[];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: _ZenAppear(
          delay: const Duration(milliseconds: 60),
          child: Semantics(
            container: true,
            header: true,
            label: semanticsLabel ?? 'Kontextleiste',
            child: RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  color: ZenColors.surface.withValue(alpha: .88),
                  borderRadius: _kRadius16,
                  border: Border.all(color: ZenColors.outline),
                  boxShadow: shadow,
                ),
                padding: padding,
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        for (int i = 0; i < pills.length; i++) ...[
                          FocusTraversalOrder(
                            order: NumericFocusOrder(i.toDouble()),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: pills[i],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineTextPill extends StatelessWidget {
  final String label;
  const _OutlineTextPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ZenColors.surfaceAlt.withValue(alpha: .66),
          border: Border.all(color: ZenColors.outline),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: _kInkStrong,
            height: 1.10,
          ),
        ),
      ),
    );
  }
}
