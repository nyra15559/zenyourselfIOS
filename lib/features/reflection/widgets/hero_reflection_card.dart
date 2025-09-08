// lib/features/reflection/widgets/hero_reflection_card.dart
// -----------------------------------------------------------------------------
// HeroReflectionCard — Panda v2.6 (Oxford-Zen, hero-first, question-focused)
// -----------------------------------------------------------------------------
// Zweck
//  • Zentrale Hero-Karte für Runde 1 der Reflexion (und als Reader für Entwürfe).
//  • Stellt PandaHeader, Titel/Unterzeile, Draft (Nutzereingabe), Mirror,
//    Leitfrage, Followup-Chips, optional Safety-Hinweis und einen frei bestückbaren
//    Footer-Slot (z. B. Gate-Buttons) bereit.
//  • Keine API-Abhängigkeiten – nur UI-Bausteine.
//
// Design
//  • Die erste Runde bleibt in der Hero-Card (kein linker Thread).
//  • Frage ≤ 30 Wörter (Sanitizing erfolgt im Service/Model).
//  • Frage im Reflection-Screen darf kursiv sein; im Journal später nicht.
//  • A11y: Semantics-Labels, klare Hierarchie.
//
// Abhängigkeiten (im Projekt vorhanden):
//  • ZenGlassCard, PandaHeader, ZenColors, ZenRadii (shared/ui, shared/zen_style)
//  • (Optional) externe Widgets können in den Footer-Slot gesetzt werden.
//
// -----------------------------------------------------------------------------
// Lizenz: Internal / ZenYourself
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../shared/zen_style.dart' hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../../shared/ui/zen_widgets.dart' show ZenGlassCard, PandaHeader;

/// Öffentliche Hero-Karte für die Reflexion.
/// 
/// Typischer Einsatz im Reflection-Screen:
/// ```dart
/// HeroReflectionCard(
///   title: 'Ordne deine Gedanken',
///   subtitle: 'Ich bin hier.',
///   draftText: userDraft,
///   mirrorText: mq.mirror,
///   questionText: mq.question,
///   followups: mq.followups,
///   onPickFollowup: (s) => setInput(s),
///   safetyText: mq.risk ? emergencyHint(context) : null,
///   loading: isWaiting,
///   loadingHint: GuidanceService.instance.loadingHint,
///   footer: ReflectionGate( ... ),
/// )
/// ```
class HeroReflectionCard extends StatelessWidget {
  /// Titel im Header (z. B. „Ordne deine Gedanken“).
  final String title;

  /// Untertitel/Caption im Header (z. B. „Ich bin hier.“).
  final String? subtitle;

  /// Optionaler Intro-Fließtext (erscheint, wenn weder Mirror/Frage/Draft gesetzt sind).
  final String? introText;

  /// Erster Nutzereingabetext (Draft oder finaler O-Ton).
  final String? draftText;

  /// Empathischer Spiegel (2–6 Sätze, kein Rat).
  final String? mirrorText;

  /// Genau eine Leitfrage (≤ 30 Wörter). Im Reflection-Screen stilistisch kursiv.
  final String? questionText;

  /// Sanfte Followup-Vorschläge (max. ~3). Setzen Text in die Eingabe.
  final List<String> followups;

  /// Callback bei Auswahl eines Followups.
  final ValueChanged<String>? onPickFollowup;

  /// Optionaler Safety-Hinweis (z. B. Krisen-Notruf).
  final String? safetyText;

  /// Zeigt einen Ladezustand (Spinner + Hint) über der Karte an.
  final bool loading;

  /// Hinweistext während des Ladens (z. B. „ZenYourself zählt die Blümchen …“).
  final String? loadingHint;

  /// Frei bestückbarer Footer-Slot (z. B. Gate-Buttons oder Mood-Prompt).
  final Widget? footer;

  /// Maximale Kartenbreite (Layout-Hilfswert). Default: 560 (wie Reflection-Screen).
  final double maxWidth;

  /// Optionaler Außen-Padding für die Karte.
  final EdgeInsetsGeometry? outerPadding;

  /// Steuert, ob der Panda-Header gezeigt wird (Default: true).
  final bool showHeader;

  const HeroReflectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.introText,
    this.draftText,
    this.mirrorText,
    this.questionText,
    this.followups = const <String>[],
    this.onPickFollowup,
    this.safetyText,
    this.loading = false,
    this.loadingHint,
    this.footer,
    this.maxWidth = 560,
    this.outerPadding,
    this.showHeader = true,
  });

  bool get _hasDraft => (draftText ?? '').trim().isNotEmpty;
  bool get _hasMirror => (mirrorText ?? '').trim().isNotEmpty;
  bool get _hasQuestion => (questionText ?? '').trim().isNotEmpty;
  bool get _hasIntro => (introText ?? '').trim().isNotEmpty;
  bool get _hasSafety => (safetyText ?? '').trim().isNotEmpty;
  bool get _hasFollowups => followups.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;

    final labelStyle =
        tt.bodyMedium!.copyWith(fontWeight: FontWeight.w700, color: ZenColors.inkStrong);

    final userTextStyle = tt.bodyMedium!.copyWith(
      color: ZenColors.jade,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );

    final mirrorStyle = tt.bodyMedium!.copyWith(color: ZenColors.ink, height: 1.32);

    final questionStyle = tt.bodyMedium!.copyWith(
      color: ZenColors.inkStrong,
      fontStyle: FontStyle.italic, // Im Journal später normal – hier bewusst kursiv.
      height: 1.32,
    );

    final captionStyle = tt.bodySmall?.copyWith(color: ZenColors.inkSubtle);

    final card = ConstrainedBox(
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
            if (showHeader) ...[
              PandaHeader(
                title: title,
                caption: subtitle ?? '',
                pandaSize: MediaQuery.of(context).size.width < 470 ? 88 : 112,
                strongTitleGreen: true,
              ),
              const SizedBox(height: 8),
            ],

            // Intro-Body (nur wenn sonst nichts befüllt ist)
            if (!_hasDraft && !_hasMirror && !_hasQuestion && _hasIntro) ...[
              Text(introText!.trim(),
                  style: tt.bodyMedium?.copyWith(color: ZenColors.ink, height: 1.45)),
              const SizedBox(height: 10),
              if (captionStyle != null)
                Text(
                  'Kleiner Tipp: Deine Reflexionen kannst du ins Gedankenbuch eintragen.',
                  style: captionStyle,
                ),
            ],

            // Draft (Nutzereingabe)
            if (_hasDraft) ...[
              Text('Dein Gedanke', style: labelStyle, semanticsLabel: 'Dein Gedanke'),
              const SizedBox(height: 6),
              Text('„${draftText!.trim()}“',
                  style: userTextStyle, semanticsLabel: draftText!.trim()),
              const SizedBox(height: 12),
            ],

            // Mirror (Empathie)
            if (_hasMirror) ...[
              Text(
                mirrorText!.trim(),
                style: mirrorStyle,
                semanticsLabel: 'Spiegel',
              ),
              const SizedBox(height: 8),
            ],

            // Leitfrage
            if (_hasQuestion) ...[
              Text(
                questionText!,
                style: questionStyle,
                semanticsLabel: 'Frage',
              ),
              const SizedBox(height: 6),
              const _ReflectionHint(),
            ],

            // Followup-Chips
            if (_hasFollowups) ...[
              const SizedBox(height: 8),
              FollowupChips(
                suggestions: followups,
                onPick: onPickFollowup,
              ),
            ],

            // Safety
            if (_hasSafety) ...[
              const SizedBox(height: 12),
              SafetyNote(text: safetyText!),
            ],

            // Footer-Slot (Gate, Mood, Controls…)
            if (footer != null) ...[
              const SizedBox(height: 12),
              footer!,
            ],
          ],
        ),
      ),
    );

    if (!loading) {
      return Padding(
        padding: outerPadding ?? EdgeInsets.zero,
        child: card,
      );
    }

    // Ladezustand mit sanftem Overlay (Spinner + Hint).
    return Padding(
      padding: outerPadding ?? EdgeInsets.zero,
      child: Stack(
        children: [
          card,
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: ZenColors.surface.withValues(alpha: .55),
                  borderRadius: const BorderRadius.all(ZenRadii.l),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                  const SizedBox(height: 10),
                  if ((loadingHint ?? '').isNotEmpty)
                    Text(
                      loadingHint!.trim(),
                      style: tt.bodyMedium?.copyWith(color: ZenColors.ink),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kleiner, ruhiger Hinweis unter der Leitfrage.
class _ReflectionHint extends StatelessWidget {
  const _ReflectionHint();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: ZenColors.inkSubtle,
          height: 1.2,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.self_improvement, size: 16, color: ZenColors.inkSubtle),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Atme einmal ein. Lies die Frage kurz. Antworte in 1–2 Sätzen.',
            style: style,
          ),
        ),
      ],
    );
  }
}

/// Followup-Chip-Leiste (öffentlich nutzbar).
class FollowupChips extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String>? onPick;

  const FollowupChips({
    super.key,
    required this.suggestions,
    this.onPick,
  });

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
              shape: const StadiumBorder(
                side: BorderSide(color: ZenColors.sage, width: .6),
              ),
              backgroundColor: ZenColors.surface,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          )
          .toList(),
    );
  }
}

/// Safety-Hinweis (öffentlich nutzbar).
class SafetyNote extends StatelessWidget {
  final String text;
  const SafetyNote({super.key, required this.text});

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
          const Icon(Icons.health_and_safety_rounded, color: ZenColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.trim(),
              style: tt.bodySmall?.copyWith(color: ZenColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
