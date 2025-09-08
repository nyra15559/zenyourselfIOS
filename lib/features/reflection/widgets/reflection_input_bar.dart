// lib/features/reflection/widgets/reflection_input_bar.dart
//
// ReflectionInputBar — Pro-Level Eingabeleiste (calm, accessible, talk-ready)
// -----------------------------------------------------------------------------
// • Sanfter Recording-Pulse (ohne Ticker)
// • Desktop/Web: Enter = Senden, Shift+Enter = neue Zeile
// • Optionaler Hinweistext über der Leiste
// • Weicher Zeichencounter (soft limit)
// • Talk-Push, Mic-Toggle, Send – einzeln deaktivier-/ausblendbar
// • ValueListenableBuilder für Live-Enable/Counter
// • A11y: Semantics/Tooltips, große Touch-Targets
//
// Abhängigkeiten:
//   import '../../../shared/ui/zen_style.dart' (ZenColors, ZenRadii)
//   Material 3 kompatibel

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/zen_style.dart' show ZenColors, ZenRadii;

class ReflectionInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;

  /// Placeholder/Hinweistext.
  final String hint;

  /// Senden (nur aktiv, wenn Text vorhanden & [canSend] true).
  final VoidCallback? onSend;

  /// Panda „weiterreden“ (optional).
  final VoidCallback? onTalk;

  /// Mikrofon starten/stoppen (optional).
  final VoidCallback? onMicTap;

  /// Aufnahme aktiv → visueller Pulse.
  final bool isRecording;

  /// Externer Enable-Guard fürs Senden (z. B. während Loading).
  final bool canSend;

  /// Optionaler Hinweis über der Leiste (z. B. „ZenYourself zählt die Blümchen …“).
  final String? trailingHint;

  /// Optionaler weicher Zeichencounter (z. B. 500) – nur Anzeige.
  final int? softMaxLength;

  /// Blendet Talk-Icon aus, wenn nicht gewünscht.
  final bool showTalk;

  /// Zeigt Kurzhinweis (Enter senden / Shift+Enter neue Zeile).
  final bool showShortcutHint;

  const ReflectionInputBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hint,
    this.onSend,
    this.onTalk,
    this.onMicTap,
    this.isRecording = false,
    this.canSend = true,
    this.trailingHint,
    this.softMaxLength,
    this.showTalk = true,
    this.showShortcutHint = true,
  });

  @override
  Widget build(BuildContext context) {
    const jade = ZenColors.jade;
    final baseText = Theme.of(context).textTheme.bodyMedium!;
    final hintStyle = baseText.copyWith(color: jade.withValues(alpha: 0.55));

    // sanfter „Pulse“ ohne AnimationController
    final List<BoxShadow> pulse = isRecording
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: jade.withValues(alpha: 0.28),
              blurRadius: 22,
              spreadRadius: 1.1,
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ];

    final bool hasTalk = showTalk && onTalk != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trailingHint != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              trailingHint!,
              textAlign: TextAlign.center,
              style: baseText.copyWith(color: ZenColors.ink),
            ),
          ),
        ],

        // Eingabeleiste
        Semantics(
          label: 'Eingabefeld für deine Reflexion',
          textField: true,
          child: Container(
            decoration: BoxDecoration(
              color: ZenColors.surface,
              borderRadius: const BorderRadius.all(ZenRadii.l),
              border: Border.all(color: jade.withValues(alpha: 0.75), width: 2),
              boxShadow: pulse,
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final String text = value.text;
                final bool hasText = text.trim().isNotEmpty;
                final bool sendEnabled = hasText && canSend && onSend != null;

                // --- Shortcuts: Enter = Senden, Shift+Enter = neue Zeile ---
                final shortcuts = <ShortcutActivator, Intent>{
                  const SingleActivator(LogicalKeyboardKey.enter):
                      const _SendIntent(),
                  const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                      const _NewlineIntent(),
                };

                void insertNewline() {
                  final sel = controller.selection;
                  final t = controller.text;
                  if (!sel.isValid) {
                    controller.text = '$t\n';
                    controller.selection =
                        TextSelection.collapsed(offset: controller.text.length);
                    return;
                  }
                  final before = t.substring(0, sel.start);
                  final after = t.substring(sel.end);
                  final next = '$before\n$after';
                  controller.text = next;
                  controller.selection =
                      TextSelection.collapsed(offset: before.length + 1);
                }

                return Shortcuts(
                  shortcuts: shortcuts,
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _SendIntent: CallbackAction<_SendIntent>(
                        onInvoke: (intent) {
                          if (sendEnabled) onSend?.call();
                          return null;
                        },
                      ),
                      _NewlineIntent: CallbackAction<_NewlineIntent>(
                        onInvoke: (intent) {
                          insertNewline();
                          return null;
                        },
                      ),
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // TextField + Actions
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Multiline Input
                            Expanded(
                              child: TextField(
                                focusNode: focusNode,
                                controller: controller,
                                maxLines: null,
                                textInputAction: TextInputAction.newline,
                                keyboardType: TextInputType.multiline,
                                autocorrect: false,
                                enableSuggestions: true,
                                spellCheckConfiguration:
                                    const SpellCheckConfiguration.disabled(),
                                style: baseText.copyWith(
                                  color: jade,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                                cursorColor: jade,
                                decoration: InputDecoration(
                                  hintText: hint,
                                  hintStyle: hintStyle,
                                  border: InputBorder.none,
                                  isCollapsed: true,
                                  contentPadding: const EdgeInsets.only(
                                    top: 6,
                                    bottom: 6,
                                    right: 8,
                                  ),
                                ),
                                // Sicherheitsnetz für „Senden“ auf Mobile-Softkeyboards:
                                onSubmitted: (_) {
                                  if (sendEnabled) onSend?.call();
                                },
                              ),
                            ),

                            // Actions (Talk / Mic / Send)
                            ConstrainedBox(
                              constraints: const BoxConstraints.tightFor(
                                width: 144,
                                height: 40,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasTalk)
                                    _ActionIconButton(
                                      tooltip: 'Panda weiterreden',
                                      icon: Icons.chat_bubble_outline_rounded,
                                      color: jade,
                                      onPressed: onTalk,
                                    ),
                                  if (onMicTap != null)
                                    _ActionIconButton(
                                      tooltip:
                                          isRecording ? 'Aufnahme stoppen' : 'Sprechen',
                                      icon: isRecording
                                          ? Icons.stop_circle_rounded
                                          : Icons.mic_rounded,
                                      color: jade,
                                      onPressed: onMicTap,
                                    ),
                                  _ActionIconButton(
                                    tooltip: 'Senden',
                                    icon: Icons.send_rounded,
                                    color: sendEnabled
                                        ? jade
                                        : jade.withValues(alpha: 0.45),
                                    onPressed: sendEnabled ? onSend : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Helper-Row: Counter + Shortcut-Hint
                        const SizedBox(height: 4),
                        _HelperRow(
                          text: text,
                          softMaxLength: softMaxLength,
                          showShortcutHint: showShortcutHint,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// --- Intents für Shortcuts ----------------------------------------------------
class _SendIntent extends Intent {
  const _SendIntent();
}

class _NewlineIntent extends Intent {
  const _NewlineIntent();
}

// --- Helper: kompakter IconButton mit größerem Hit-Target --------------------
class _ActionIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: IconButton(
          splashRadius: 22,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: color),
        ),
      ),
    );
  }
}

// --- Helper: Counter + Shortcut-Hinweis --------------------------------------
class _HelperRow extends StatelessWidget {
  final String text;
  final int? softMaxLength;
  final bool showShortcutHint;

  const _HelperRow({
    required this.text,
    required this.softMaxLength,
    required this.showShortcutHint,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final style = tt.bodySmall?.copyWith(
      color: ZenColors.inkSubtle,
      height: 1.1,
    );

    final counter = _CounterText(text: text, max: softMaxLength, style: style);

    return Row(
      children: [
        if (softMaxLength != null) counter,
        const Spacer(),
        if (showShortcutHint)
          Text('Enter senden · Shift+Enter neue Zeile', style: style),
      ],
    );
  }
}

class _CounterText extends StatelessWidget {
  final String text;
  final int? max;
  final TextStyle? style;

  const _CounterText({required this.text, required this.max, required this.style});

  @override
  Widget build(BuildContext context) {
    if (max == null) return const SizedBox.shrink();
    final len = text.characters.length;
    final over = len > max!;
    return Text(
      '$len/$max',
      style: (style ?? const TextStyle()).copyWith(
        color: over ? Colors.redAccent : style?.color,
      ),
    );
  }
}
