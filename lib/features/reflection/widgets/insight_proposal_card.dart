// [MERGE] lib/features/reflection/widgets/insight_proposal_card.dart
// InsightProposalCard v1.2.2 — Kutsche 4 (Aha-Fakten) · 2025-11-09
// -----------------------------------------------------------------------------
// • Card „Festhalten?“ mit sanfter Paraphrase (No-Quote-Mirror) — 1 Satz, ≤160 Zeichen.
// • Tag-Picker (optional), begrenzte Auswahl (max 3 Tags), schlanke A11y-Labels.
// • Buttons: „Speichern“ (paraphrasierte Zeile + Tags) / „Später“ (Dismiss).
// • Robust: Trim/Whitespace-Fix, Trigger-Umschreibungen (wertlos→„sehr harte Selbstkritik“ usw.).
// • Doppel-Tap-Schutz: kurzer Cooldown (Standard 700 ms), Haptik-Feedback.
// • Keine Folgefragen; UI gibt nur Bestärkung & Entscheidung (Speichern/Später).
//
// Empfohlene Verwendung:
// InsightProposalCard(
//   line: proposal['line'],
//   initialTags: (proposal['tags'] as List?)?.cast<String>(),
//   onSave: (line, tags) => memoryService.saveInsight(line: line, tags: tags),
//   onLater: () => controller.skipMemoryProposal(),
//   showTagPicker: true,
// )
//
// Leitplanken-Bezug:
// – No-Quote-Mirror: vermeidet 4+-Wort-Zitatketten; sanfte Paraphrase + Trigger-Umschreibung.
// – Byte-Budget/Brücke wird NICHT hier erzwungen (erfolgt in MemoryService / ApiService).
// – Safety-Ton: neutral, bestärkend.
//
// Abhängigkeiten: nur Flutter (Material + Services).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InsightProposalCard extends StatefulWidget {
  /// Rohzeile, z. B. vom Worker („Ich bin wertlos…“) – wird sanft paraphrasiert.
  final String line;

  /// Vorbelegung für Tags.
  final List<String>? initialTags;

  /// Callback bei Speichern (liefert paraphrasierte Zeile + ausgewählte Tags).
  final void Function(String line, List<String> selectedTags)? onSave;

  /// Callback bei „Später“ (Dismiss).
  final VoidCallback? onLater;

  /// Optionaler Tag-Picker.
  final bool showTagPicker;

  /// Optionale Tag-Liste (Default s. unten).
  final List<String>? tagOptions;

  /// Max. Anzahl wählbarer Tags.
  final int maxTags;

  /// Doppel-Tap-Cooldown in Millisekunden (Default: 700 ms).
  final int cooldownMs;

  /// Max. Länge des 1-Satz-Textes (Default: 160 Zeichen).
  final int maxChars;

  const InsightProposalCard({
    super.key,
    required this.line,
    this.initialTags,
    this.onSave,
    this.onLater,
    this.showTagPicker = true,
    this.tagOptions,
    this.maxTags = 3,
    this.cooldownMs = 700,
    this.maxChars = 160,
  });

  @override
  State<InsightProposalCard> createState() => _InsightProposalCardState();
}

class _InsightProposalCardState extends State<InsightProposalCard> {
  static const List<String> _defaultTags = <String>[
    'Selbstfürsorge',
    'Ressource',
    'Grenze',
  ];

  // Trigger-Umschreibungen (No-Quote-Mirror – weichere Begriffe)
  static const Map<String, String> _softMap = {
    'wertlos': 'sehr harte Selbstkritik',
    'schuld': 'starke Selbstvorwürfe',
    'einsam': 'sehr allein',
    'einsamkeit': 'sehr allein',
    'angst': 'starke Sorge',
    'ängste': 'starke Sorgen',
    'überfordert': 'unter Druck',
    'erschöpft': 'sehr müde',
    'hilflos': 'ohne Kraft',
  };

  late final Set<String> _selected =
      {...(widget.initialTags ?? const <String>[])};

  late String _display =
      _paraphraseOneSentence(widget.line, maxChars: widget.maxChars);

  bool _busy = false;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(Duration(milliseconds: widget.cooldownMs), () {
      if (mounted) setState(() => _busy = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tags = widget.tagOptions ?? _defaultTags;

    return Semantics(
      container: true,
      label: 'Einsicht vorschlagen',
      child: Card(
        elevation: 0.8,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: cs.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titelzeile
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Festhalten?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Tooltip(
                    message: 'Vorgeschlagener Aha-Fakt',
                    child: Icon(Icons.push_pin_outlined,
                        size: 18, color: cs.onSurface.withOpacity(0.48)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 1-Satz-Fakt (sanft paraphrasiert)
              Semantics(
                label: 'Vorgeschlagener Satz',
                child: Text(
                  _display,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
                ),
              ),

              if (widget.showTagPicker) ...[
                const SizedBox(height: 10),
                _TagPicker(
                  options: tags,
                  selected: _selected,
                  maxTags: widget.maxTags,
                  onChanged: (sel) => setState(() {
                    _selected
                      ..clear()
                      ..addAll(sel);
                  }),
                ),
              ],

              const SizedBox(height: 10),

              // Buttons: Speichern / Später
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ZenActionChip(
                    icon: Icons.check_rounded,
                    label: 'Speichern',
                    color: cs.primaryContainer.withOpacity(0.26),
                    enabled: !_busy && (widget.onSave != null),
                    semanticsLabel: 'Einsicht speichern',
                    onPressed: () {
                      if (_busy || widget.onSave == null) return;
                      setState(() => _busy = true);
                      HapticFeedback.lightImpact();
                      try {
                        widget.onSave!.call(_display, _selected.toList());
                      } catch (_) {
                        // weich scheitern; Cooldown dennoch laufen lassen
                      } finally {
                        _startCooldown();
                      }
                    },
                  ),
                  _ZenActionChip(
                    icon: Icons.schedule,
                    label: 'Später',
                    color: cs.surfaceVariant.withOpacity(0.35),
                    enabled: !_busy && (widget.onLater != null),
                    semanticsLabel: 'Später entscheiden',
                    onPressed: () {
                      if (_busy) return;
                      setState(() => _busy = true);
                      HapticFeedback.selectionClick();
                      try {
                        widget.onLater?.call();
                      } catch (_) {
                        // weich scheitern
                      } finally {
                        _startCooldown();
                      }
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

  // --- Helpers ----------------------------------------------------------------

  /// Paraphrasiert sanft: entfernt Anführungszeichen, säubert Whitespace,
  /// ersetzt harte Trigger-Wörter (_softMap), formuliert neutral um und kürzt
  /// auf einen Satz (maxChars). Vermeidet 4+ Wort-„Zitatgefühle“, indem
  /// neutrale Einleiter verwendet und problematische Segmente entschärft werden.
  String _paraphraseOneSentence(String raw, {required int maxChars}) {
    var s = (raw).trim();

    // 1) Anführungszeichen & Guillemets entfernen
    s = s.replaceAll(RegExp(r'[„“"”‘’`´]'), '');
    s = s.replaceAll(RegExp(r'«([^»]{1,200})»'), r'\1');

    // 2) Whitespace säubern
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 3) Grobe Erstformulierung: neutraler Einleiter, um Direktzitate zu vermeiden
    s = _neutralLeadIn(s);

    // 4) Trigger-Wörter weich umschreiben (case-insensitive)
    s = _softenTerms(s, _softMap);

    // 5) Auf EINEN Satz reduzieren
    final split = RegExp(r'(?<=[\.\!\?])\s+');
    if (split.hasMatch(s)) {
      s = s.split(split).first.trim();
    }

    // 6) Satzende ggf. ergänzen
    if (!RegExp(r'[\.!\?]$').hasMatch(s)) {
      s = '$s.';
    }

    // 7) Sanft kürzen
    if (s.length > maxChars) {
      final cut = s.substring(0, maxChars);
      final idx = cut.lastIndexOf(' ');
      s = (idx >= 60 ? cut.substring(0, idx) : cut).trimRight();
      if (!RegExp(r'[\.!\?]$').hasMatch(s)) s = '$s…';
    }

    // 8) Minimalfallback
    if (s.isEmpty) s = 'Kleine Einsicht für dich.';

    return s;
  }

  String _neutralLeadIn(String text) {
    // Neutrale Einleitungen reduzieren das Risiko langer Direktzitate.
    // Beispiele: „Es zeigt sich, dass …“, „Kurz gefasst: …“, „Wesentlich ist: …“
    final t = text.trim();

    // Wenn bereits ein neutraler Lead vorhanden, nicht doppeln.
    final hasLead = RegExp(
      r'^(Kurz gefasst|Wesentlich ist|Es zeigt sich|Im Kern):',
      caseSensitive: false,
    ).hasMatch(t);
    if (hasLead) return t;

    // Leichte Heuristik: Bei „Ich …/Mir …/Mich …/Mein…“ → entpersonalisieren.
    final lower = t.toLowerCase();
    if (lower.startsWith('ich ') ||
        lower.startsWith('mir ') ||
        lower.startsWith('mich ') ||
        lower.startsWith('mein ') ||
        lower.startsWith('meine ')) {
      return 'Im Kern: ${_decoupleFirstPerson(t)}';
    }
    return 'Kurz gefasst: $t';
  }

  String _decoupleFirstPerson(String s) {
    // Entkoppelt „Ich…“ leicht in eine neutrale Form.
    // Beispiel: „Ich fühle mich überfordert“ → „Gefühl von Druck ist präsent“
    var out = s;

    // Häufige Muster
    out = out.replaceFirst(RegExp(r'^(Ich|ich)\s+bin\s+'), 'Es wirkt ');
    out = out.replaceFirst(RegExp(r'^(Ich|ich)\s+fühle\s+mich\s+'), 'Gefühlt ');
    out = out.replaceFirst(RegExp(r'^(Ich|ich)\s+hab(e)?\s+das\s+Gefühl\s+'),
        'Gefühlt ');
    out = out.replaceFirst(RegExp(r'^(Mir|mir)\s+ist\s+'), 'Es ist ');
    out = out.replaceFirst(RegExp(r'^(Mich|mich)\s+'), '');

    // Rest säubern
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  String _softenTerms(String s, Map<String, String> dict) {
    // Wortweise Ersetzung (case-insensitive), vermeidet aggressive Begriffe.
    return s.replaceAllMapped(RegExp(r'\b([A-Za-zÄÖÜäöüß]+)\b'), (m) {
      final w = m.group(1)!;
      final lw = w.toLowerCase();
      final repl = dict[lw];
      if (repl == null) return w;
      // Erhalte Großschreibung am Wortanfang, wenn nötig
      if (w[0].toUpperCase() == w[0]) {
        return repl.isEmpty ? w : repl[0].toUpperCase() + repl.substring(1);
      }
      return repl;
    });
  }
}

// -- Reusable ActionChip (mit A11y & Enable-State) -----------------------------

class _ZenActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semanticsLabel;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  const _ZenActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    required this.semanticsLabel,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: semanticsLabel,
      enabled: enabled,
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: enabled ? onPressed : null,
        backgroundColor: color,
        elevation: 0,
        pressElevation: 0,
        labelStyle: theme.textTheme.labelLarge,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// -- Mini Tag-Picker -----------------------------------------------------------

class _TagPicker extends StatefulWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final int maxTags;

  const _TagPicker({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.maxTags = 3,
  });

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late Set<String> _sel = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final opt in widget.options)
          FilterChip(
            label: Text(opt),
            selected: _sel.contains(opt),
            onSelected: (v) {
              setState(() {
                if (v) {
                  // Kappung: maxTags
                  if (_sel.length < widget.maxTags) {
                    _sel.add(opt);
                  }
                } else {
                  _sel.remove(opt);
                }
              });
              widget.onChanged(_sel);
            },
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            labelStyle: theme.textTheme.labelMedium,
            selectedColor: cs.primaryContainer.withOpacity(0.35),
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: cs.outlineVariant, width: 0.7),
          ),
      ],
    );
  }
}
