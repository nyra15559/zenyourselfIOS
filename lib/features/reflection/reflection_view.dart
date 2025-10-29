//[BASELINE]lib/features/reflection/reflection_view.dart(Stand: 28.10.) 
// lib/features/reflection/reflection_view.dart
//
// ReflectionView — reine Layout-Schicht (Plan v6.2.2 + v6.3.x VM-Wiring)
// ---------------------------------------------------------------------
// Rendert:
// • Header, Intro/Pitch-Bubble, Bridge-Bubble
// • Frage + helperSuggestion, Talk-Zeilen
// • Verlauf (Thread), Answer-Chips (insert-only), Topic-Chips (optional)
// • Abschluss-/Mood-CTA (allowClosure/moodPrompt), Risk/Hotline-Banner
// • Composer (unten) + Footer-Disclaimer
//
// Rückwärtskompatibel: alle neuen Props sind optional.
//

import 'package:flutter/material.dart';

// Zen-UI Widgets (wie im Projekt genutzt)
// (zen_style.dart entfernt – war ungenutzt)
import '../../shared/ui/zen_widgets.dart'
    show ZenBackdrop, ZenGlassCard, ZenChipGhost;
// Risk/Hotline: Wir verwenden eine lokale, leichte Karte (_SafetyHotlineCard)
// import '../../widgets/hotline_widget.dart';  // entfällt (API-Divergenz)

class ReflectionViewProps {
  // Header / dekorativ
  final String headerTitle;
  final String? headerSubtitle;
  final String pandaAsset;

  // Bubbles oben
  final String? introText;   // Pitch/Intro (oben, pinned-ähnlich)
  final String? bridgeText;  // Bridge/Recall (optional, unter Intro)

  // Leitfrage-Block (neu v6.3)
  final String? question;            // Leitfrage (mit Fragezeichen)
  final String? helperSuggestion;    // 0–1 Satz unter der Frage
  final List<String> talkLines;      // kleine Talk-Zeilen (≤2)

  // Verlauf (bereits vorgerendert vom Orchestrator)
  final List<Widget> thread;

  // Chips
  final List<String> chips;          // Answer-Chips (insert-only)
  final List<String> topicChips;     // Redirect-Themen (optional)
  final ValueChanged<String>? onChipTap; // optional: externer Chip-Tap-Handler

  // Composer unten
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool canSend;
  final VoidCallback? onSend;
  final VoidCallback? onMicTap;
  final bool isRecording;

  // Abschluss/Mood-CTA (neu v6.3)
  final bool allowClosure;
  final bool moodPrompt;
  final VoidCallback? onClosureTap;

  // Risk/Hotline
  final bool risk;

  // Hope-Slot (kleiner, warmer Hinweis unter den Chips)
  final String? hopeText;    // einfacher Text
  final Widget? hopeWidget;  // alternativ: kompletter Widget-Slot

  // Footer-Disclaimer
  final String footerDisclaimer;

  // Optional: zusätzliche Abstände
  final double maxCardWidth;

  const ReflectionViewProps({
    this.headerTitle = 'Ordne deine Gedanken',
    this.headerSubtitle,
    this.pandaAsset = 'assets/star_pa.png',
    this.introText,
    this.bridgeText,
    this.question,
    this.helperSuggestion,
    this.talkLines = const <String>[],
    required this.thread,
    required this.chips,
    this.topicChips = const <String>[],
    this.onChipTap,
    required this.controller,
    this.focusNode,
    required this.canSend,
    this.onSend,
    this.onMicTap,
    this.isRecording = false,
    this.allowClosure = false,
    this.moodPrompt = false,
    this.onClosureTap,
    this.risk = false,
    this.hopeText,
    this.hopeWidget,
    this.footerDisclaimer =
        'Dies ist keine Therapie, sondern eine mentale Begleitungs-App.',
    this.maxCardWidth = 680,
  });
}

class ReflectionView extends StatelessWidget {
  final ReflectionViewProps props;
  const ReflectionView({super.key, required this.props});

  bool get _showIntro => (props.introText ?? '').trim().isNotEmpty;
  bool get _showBridge => (props.bridgeText ?? '').trim().isNotEmpty;
  bool get _showQuestion => (props.question ?? '').trim().isNotEmpty;
  bool get _showChips => props.chips.isNotEmpty;
  bool get _showTopicChips => props.topicChips.isNotEmpty;
  bool get _showHope  => (props.hopeText ?? '').trim().isNotEmpty || props.hopeWidget != null;
  bool get _showClosureCta => props.allowClosure || props.moodPrompt;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final cardMaxW = _cardMaxWidthFor(w, props.maxCardWidth);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Sanfter Hintergrund
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

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        0, 0, 0,
                        12 + _kInputReserve + bottomInset,
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

                        // Intro / Pitch Bubble (pinned-ähnlich)
                        if (_showIntro)
                          _BubbleCard(
                            maxWidth: cardMaxW,
                            child: Text(
                              props.introText!.trim(),
                              style: const TextStyle(height: 1.35),
                            ),
                          ),

                        // Bridge Bubble (Memory/Recall)
                        if (_showBridge)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _BubbleCard(
                              emoji: '🪄',
                              maxWidth: cardMaxW,
                              child: _Markdownish(props.bridgeText!.trim()),
                            ),
                          ),

                        // Frage + helperSuggestion + Talk-Zeilen
                        if (_showQuestion)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: cardMaxW),
                                child: _QuestionCard(
                                  question: props.question!.trim(),
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
                        ...props.thread.map((w) => Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: cardMaxW),
                                  child: w,
                                ),
                              ),
                            )),

                        // Antwort-Chips
                        if (_showChips)
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

                        // Topic-Chips (Redirect-Ideen)
                        if (_showTopicChips)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: cardMaxW),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        'Themenvorschläge',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: Colors.black.withValues(alpha: .74),
                                            ),
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final t in props.topicChips)
                                          ZenChipGhost(
                                            label: _normalizeChip(t),
                                            onPressed: () => _onTapTopicChip(context, t),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Hope Slot (kleiner, warmer Mutmacher)
                        if (_showHope)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: cardMaxW),
                                child: props.hopeWidget ??
                                    _HopeBubble(text: props.hopeText!.trim()),
                              ),
                            ),
                          ),

                        // Abschluss-/Mood-CTA
                        if (_showClosureCta)
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
                                    label: Text(
                                      props.moodPrompt
                                          ? 'Stimmung teilen'
                                          : 'Abschluss & Stimmung',
                                    ),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      height: 1.25,
                                      color: Colors.black.withValues(alpha: .72),
                                    ),
                              ),
                            ),
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
                            hint: 'Antworte in 1–2 Sätzen.',
                            canSend: props.canSend,
                            onSend: props.onSend,
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

  void _onTapChip(BuildContext context, String raw) {
    final normalized = _normalizeChip(raw);
    // Externer Handler? → bevorzugen
    if (props.onChipTap != null) {
      props.onChipTap!(normalized);
      return;
    }
    // Insert-only ins Textfeld
    final cur = props.controller.text;
    final needsSpace = cur.isNotEmpty && !RegExp(r'\s$').hasMatch(cur);
    final withEllipsis = _ensureEllipsisSpaceSuffix(normalized);
    final next = (needsSpace ? '$cur ' : cur) + withEllipsis;
    props.controller
      ..text = next
      ..selection = TextSelection.fromPosition(TextPosition(offset: next.length));
    if (props.focusNode != null) {
      FocusScope.of(context).requestFocus(props.focusNode);
    }
  }

  void _onTapTopicChip(BuildContext context, String topic) {
    // sanfter Satzstarter fürs Redirect
    final starter = 'Zum Thema ${_normalizeChip(topic)}… ';
    _onTapChip(context, starter);
  }

  String _normalizeChip(String s) {
    var t = s.trim().replaceAll(RegExp(r'[?？]+$'), '');
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
    if (w < 420) return w - 24;
    if (w < 720) return w - 24 > max ? max : w - 24;
    return max;
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
                    Text(title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          height: 1.15,
                        )),
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
            // Entfernt: theme.textWidgetTheme?.style (existiert nicht in ThemeData)
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ],
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
            tooltip: isRecording ? 'Aufnahme stoppen' : 'Sprachaufnahme starten',
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
              decoration: const InputDecoration(
                hintText: 'Antworte in 1–2 Sätzen.',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
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
    // sehr leichte, sichere Formatierung für fett **…**
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*[^*]+\*\*)');
    final parts = text.split(regex);
    for (final part in parts) {
      if (part.startsWith('**') && part.endsWith('**')) {
        spans.add(TextSpan(
          text: part.substring(2, part.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
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
          Text('Wenn es dir nicht gut geht',
              style: theme.textTheme.titleSmall?.copyWith(height: 1.25)),
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

// --------------------------- Consts ------------------------------------------

const double _kInputReserve = 104;
