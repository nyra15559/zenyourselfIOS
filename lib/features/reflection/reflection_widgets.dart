// lib/features/reflection/reflection_widgets.dart
// Part: UI-Widgets (library: reflection_screen)
// -----------------------------------------------------------------------------
// Oxford–Zen v6.6 — Reflection UI (closure-gated, calm type)
// - Completion/Mood nur wenn round.allowClosure == true && !round.hasPendingQuestion
// - Letzte Leitfrage wird unterdrückt, sobald Abschluss aktiv (Mood-Phase)
// - Optional: mood_intro-Blase vor Abschluss-Karte, falls vorhanden
// - Verbesserungen:
//   • Beruhigte Typografie (keine Kursiv-Frage), konsistente Weights/Sizes
//   • RepaintBoundary an zentralen Cards (ohne const-Fehler)
//   • Tooltips + Kopieren via Long-Press/Right-Click, barrierearme Semantics
//   • Stabilere Text-Layouts (maxWidth, TextScale-Clamp bei Chips)
// -----------------------------------------------------------------------------
part of reflection_screen;

// Tokens / constants
const _kRadiusPill = BorderRadius.all(Radius.circular(999));
const _kRadius14   = BorderRadius.all(Radius.circular(14));
const _kRadius16   = BorderRadius.all(Radius.circular(16));
const _kRadius18   = BorderRadius.all(Radius.circular(18));

const _kGlassTop    = .20;
const _kGlassBottom = .20;
const _kGlassBorder = .22;

const _kInk       = ZenColors.ink;
const _kInkStrong = ZenColors.inkStrong;
const _kJade      = ZenColors.jade;

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
    return PandaHeader(
      title: title,
      caption: subtitle.trim().isEmpty ? null : subtitle,
      pandaSize: pandaSize,
      strongTitleGreen: true,
    );
  }
}

// Intro
class _IntroBubble extends StatelessWidget {
  const _IntroBubble();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

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
              'Hi, ich bin dein Zen Panda. Erzähl mir in 1–2 Sätzen, was dich gerade beschäftigt. '
              'Deine Reflexion findest du später im Gedankenbuch — gespeichert wird nur, wenn du es willst.',
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
    final tooltip = _isDesktop ? 'Rechtsklick zum Kopieren' : 'Lange drücken zum Kopieren';

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
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
                  border: Border.all(color: Colors.black.withOpacity(.06), width: 1),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 10)),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.labelSmall?.copyWith(
                        color: _kInk.withOpacity(.75),
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
    );
  }

  // Panda card
  Widget _buildPandaStepCard(
    BuildContext context,
    _PandaStep s, {
    required bool showTyping,
    bool suppressQuestion = false,
  }) {
    final tt = Theme.of(context).textTheme;
    final tooltip = _isDesktop ? 'Rechtsklick zum Kopieren' : 'Lange drücken zum Kopieren';

    final buffer = StringBuffer();
    if (s.mirror.trim().isNotEmpty) buffer.writeln(s.mirror.trim());
    for (final t in s.talkLines) {
      final line = t.trim();
      if (line.isNotEmpty) buffer.writeln(line);
    }
    if (!suppressQuestion && s.question.trim().isNotEmpty) {
      buffer.writeln(s.question.trim());
    }
    final copyAll = buffer.toString();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // Abschluss-Phase aktiv? -> suppressQuestion für die letzte Panda-Karte setzen
    final bool closureActive =
        round.answered &&
        round.allowClosure &&
        !round.hasPendingQuestion &&
        !round.hasMood;

    // Benutzer-Gedanke
    final userText = round.userInput.trim();
    if (userText.isNotEmpty) {
      children.add(_buildUserBubble(context, 'Gedanke', userText));
      children.add(const SizedBox(height: 10));
    }

    // Panda-Schritte
    for (int i = 0; i < round.steps.length; i++) {
      final s = round.steps[i];
      final isLastStep = i == round.steps.length - 1;

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
          ..add(_MoodIntroBubble(text: intro, maxWidth: maxWidth))
          ..add(const SizedBox(height: 10));
      }

      children
        ..add(_CompletionCard(maxWidth: maxWidth))
        ..add(const SizedBox(height: 10))
        ..add(_MoodChooserInline(onSelected: onSelectMood, maxWidth: maxWidth))
        ..add(const SizedBox(height: 10));
    }

    // Actions nach Mood
    if (round.answered && round.hasMood) {
      children.add(
        AnimatedSwitcher(
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
      );
    }

    // Safety
    if ((safetyText ?? '').isNotEmpty) {
      children
        ..add(const SizedBox(height: 10))
        ..add(_SafetyNote(text: safetyText!, maxWidth: maxWidth));
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
        color: Colors.black.withOpacity(.10),
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
        ExcludeSemantics(child: Icon(Icons.self_improvement, size: 16, color: Colors.black54)),
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
    final tt = Theme.of(context).textTheme;
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
    final tt = Theme.of(context).textTheme;
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
                    final m = await showPandaMoodPicker(context, title: 'Wähle deine Stimmung');
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
    if (v <  0.20)  return 2;
    if (v <  0.60)  return 3;
    return 4;
  }
}

// Chips
class _ChipsWrap extends StatelessWidget {
  final List<String> items;
  final void Function(String) onTap;

  const _ChipsWrap({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.of(context).textScaleFactor.clamp(0.9, 1.1);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale.toDouble())),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final t in items)
            ZenChipGhost(
              label: t.replaceAll(RegExp(r'\s*:\s*$'), ''),
              onPressed: () => onTap(t),
            ),
        ],
      ),
    );
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
            const BoxShadow(color: Color(0x1A000000), blurRadius: 14, offset: Offset(0, 4)),
            BoxShadow(color: _kJade.withOpacity(0.30), blurRadius: 22, spreadRadius: 1.2),
          ]
        : const [
            BoxShadow(color: Color(0x15000000), blurRadius: 14, offset: Offset(0, 6)),
          ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final suffixW = constraints.maxWidth < 360 ? 108.0 : 140.0;

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(decoration: BoxDecoration(boxShadow: pulse)),
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
                    spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                    style: tt.bodyMedium!.copyWith(
                      color: _kInkStrong,
                      fontWeight: FontWeight.w600,
                    ),
                    cursorColor: _kJade,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: tt.bodyMedium!.copyWith(color: _kInk.withOpacity(.55)),
                      border: InputBorder.none,
                      isCollapsed: true,
                      suffixIconConstraints: BoxConstraints.tightFor(width: suffixW, height: 40),
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
                                    ? Colors.redAccent.withOpacity(.85)
                                    : _kInk.withOpacity(.65),
                                fontWeight: FontWeight.w600,
                              ),
                              child: Text(
                                '$used/$kInputSoftLimit',
                                semanticsLabel: 'Zeichen: $used von $kInputSoftLimit',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: isRecording ? 'Aufnahme stoppen' : 'Sprechen',
                            onPressed: onMicTap,
                            icon: Icon(
                              isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                              color: _kJade,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Senden (Enter)',
                            onPressed: (hasText && canSend && onSend != null) ? onSend : null,
                            icon: Icon(
                              Icons.send_rounded,
                              color: (hasText && canSend && onSend != null)
                                  ? _kJade
                                  : _kJade.withOpacity(0.45),
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

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
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
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return Container(
                width: 4,
                height: 4 + 3 * n(i),
                margin: EdgeInsets.only(right: i == 2 ? 0 : 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity((.35 + n(i) * .65) * .6),
                  shape: BoxShape.circle,
                ),
              );
            }),
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
    return const Row(
      children: [
        _TypingDots(),
        SizedBox(width: 8),
        Text('Panda tippt …', style: TextStyle(color: Colors.black54)),
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
    final tt = Theme.of(context).textTheme;
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
            color: _kInk.withOpacity(.87),
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
            color: _kInk.withOpacity(.87),
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
      children.add(
        SelectableText(
          s.question.trim(),
          // Calm question — no italics
          style: tt.titleMedium?.copyWith(
            color: _kInkStrong,
            height: 1.32,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Timestamp bottom-right
    children.add(const SizedBox(height: 6));
    children.add(
      const Align(
        alignment: Alignment.bottomRight,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: .55,
            child: _TimeStampText(),
          ),
        ),
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
              color: _kInk.withOpacity(.87),
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
          child: Icon(Icons.health_and_safety_rounded, color: Colors.orange, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(scope?.text ?? '', style: tt.bodySmall?.copyWith(color: _kInk))),
      ],
    );
  }
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow();
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
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
              // TextStyle kann const bleiben, Farbe nicht aus _kInkStrong ziehen:
              // Wir überschreiben Farbe unten via DefaultTextStyle.merge
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingRowLegacy extends StatelessWidget {
  const _TypingRowLegacy();
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _TypingDots(),
        SizedBox(width: 8),
        Text('Panda tippt …', style: TextStyle(color: Colors.black54)),
      ],
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
    required super.child, // <— erwartet ein Widget, kein Builder-Callback
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
