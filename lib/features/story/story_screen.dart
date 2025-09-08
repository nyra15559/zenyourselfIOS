// lib/features/story/story_screen.dart
//
// StoryScreen — Zen v6.29 · 2025-09-04
// -----------------------------------------------------------------------------
// • Manuelles Generieren erst nach Klick auf CTA (kein Auto-Generate).
// • AppBar ohne Titel (vermeidet „Kurzgeschichte“-Dopplung).
// • Panda-Header via Widgets: `zw.PandaHeader` (Glow, 88/112 je nach Breite).
// • Gate-Text (überarbeitet): Nur Instruktion, keine fette „Moment“-Headline.
// • CTA: dezent (Outlined, Jade). „Jetzt reflektieren“ bleibt Primary.
// • Lade-Overlay: zentriert (zw.ZenCenteredLoadingOverlay).
// • Ergebnis-Karte: klar, mit „Anhören/Kopieren/Als TXT/Speichern“.
// • NEU: „Kurzgeschichte speichern“ → speichert als Journal-Entry (EntryKind.story).
//

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

// Zen-Design (Tokens)
import '../../shared/zen_style.dart' as zs hide ZenBackdrop, ZenGlassCard, ZenAppBar;
// Zen-Widgets
import '../../shared/ui/zen_widgets.dart' as zw;

// Daten
import '../../providers/journal_entries_provider.dart';
import '../../models/journal_entry.dart' as jm;

// Services
import '../../services/guidance_service.dart';

// TTS
import '../../services/tts_service.dart' as tts;

// Für CTA "Reflektieren"
import '../reflection/reflection_screen.dart';

class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  static const int neededReflections = 5;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  StoryResult? _story; // aktuelles Ergebnis
  bool _loading = false;
  String? _error;

  // Save-Status
  bool _storySaved = false;
  String? _savedEntryId;

  // TTS
  bool _speaking = false;
  late final VoidCallback _speakingListener;

  @override
  void initState() {
    super.initState();
    _speakingListener = () {
      if (!mounted) return;
      setState(() => _speaking = tts.TtsService.instance.speaking.value);
    };
    tts.TtsService.instance.speaking.addListener(_speakingListener);
  }

  @override
  void dispose() {
    _stopSpeakingSilently();
    tts.TtsService.instance.speaking.removeListener(_speakingListener);
    super.dispose();
  }

  // ---- Progress / Daten -----------------------------------------------------
  int _progressCount(BuildContext context) {
    final prov = context.read<JournalEntriesProvider>();
    return prov.entries.where(_isReflection).length;
  }

  List<jm.JournalEntry> _lastNReflections(BuildContext context, int n) {
    final prov = context.read<JournalEntriesProvider>();
    final all = prov.entries.where(_isReflection).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.take(n).toList();
  }

  bool _isReflection(jm.JournalEntry e) {
    // Primär über 'kind' (EntryKind)
    try {
      return e.kind == jm.EntryKind.reflection;
    } catch (_) {
      // Optional: legacy Enum unterstützen, falls vorhanden
      try {
        // ignore: unnecessary_cast
        return e.type == jm.JournalType.reflection;
      } catch (_) {
        return false;
      }
    }
  }

  // ---- Story-Generierung ----------------------------------------------------
  Future<void> _generateStory() async {
    setState(() {
      _loading = true;
      _error = null;
      _storySaved = false;
      _savedEntryId = null;
    });

    try {
      final recent = _lastNReflections(context, StoryScreen.neededReflections);
      final topics = await _deriveTopics(recent);

      if (topics.isEmpty) {
        throw Exception('Nicht genug Inhalte für eine Kurzgeschichte.');
      }

      // sanfter Übergang / Teaser
      await Future<void>.delayed(const Duration(milliseconds: 650));

      final story = await GuidanceService.instance.story(
        entryIds: recent.map((e) => e.id).toList(),
        topics: topics,
        useServerIfAvailable: true,
      );

      if (!mounted) return;
      setState(() {
        _story = story;
        _loading = false;
      });

      zw.ZenToast.show(context, 'Geschichte erstellt');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<String>> _deriveTopics(List<jm.JournalEntry> entries) async {
    final set = <String>{};
    for (final e in entries) {
      final q = (e.aiQuestion ?? '').trim();
      if (q.isNotEmpty) set.add(_compact(q));

      // Content-Mix statt e.text:
      final content = [
        e.thoughtText,
        e.userAnswer,
        e.title,
        e.aiQuestion,
      ]
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join('\n');

      if (content.isEmpty) continue;

      try {
        final tags = await GuidanceService.instance.suggestTags(content);
        set.addAll(tags.map(_compact));
      } catch (_) {
        // Tags optional – robust gegen Ausfälle bleiben
      }
    }
    final topics = set.where((t) => t.length >= 2).take(6).toList();
    if (topics.isEmpty) topics.add('Selbstfürsorge');
    return topics;
  }

  String _compact(String s) => s
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\.!?]'), '')
      .trim();

  // ---- SAVE: Kurzgeschichte -> Journal (EntryKind.story) --------------------
  Future<void> _saveCurrentStory() async {
    final s = _story;
    if (s == null) return;

    if (_storySaved) {
      zw.ZenToast.show(context, 'Bereits gespeichert');
      return;
    }

    try {
      final prov = context.read<JournalEntriesProvider>();

      // Titel/Body sauber trimmen; Fallback-Titel falls leer
      final title = (s.title.trim().isEmpty) ? 'Kurzgeschichte' : s.title.trim();
      final body = s.body.trim();

      final saved = prov.addStory(
        title: title,
        body: body,
        moodLabel: 'Neutral', // neutraler Default; Mood ist bei Story optional
        ts: DateTime.now(),
      );

      setState(() {
        _storySaved = true;
        _savedEntryId = saved.id;
      });

      zw.ZenToast.show(context, 'Ins Gedankenbuch gespeichert');
      HapticFeedback.selectionClick();
    } catch (_) {
      zw.ZenToast.show(context, 'Konnte nicht speichern');
    }
  }

  // ---- TTS helpers ----------------------------------------------------------
  Future<void> _toggleSpeak() async {
    if (_speaking) {
      await _stopSpeaking();
      return;
    }
    final text = (_story?.title ?? '').trim().isEmpty
        ? (_story?.body ?? '')
        : '${_story!.title}. ${_story!.body}';
    if (text.trim().isEmpty) return;
    try {
      final ok = await tts.TtsService.instance.speak(text, lang: 'de-DE');
      if (!mounted) return;
      if (!ok) {
        zw.ZenToast.show(context, 'Sprachausgabe nicht verfügbar');
        return;
      }
    } catch (_) {
      if (!mounted) return;
      zw.ZenToast.show(context, 'Sprachausgabe nicht verfügbar');
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await tts.TtsService.instance.stop();
    } catch (_) {}
    if (mounted) setState(() => _speaking = false);
  }

  void _stopSpeakingSilently() {
    try {
      tts.TtsService.instance.stop();
    } catch (_) {}
  }

  // ---- UI -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final hasContent = _story != null &&
        (_story!.title.trim().isNotEmpty || _story!.body.trim().isNotEmpty);

    final isMobile = MediaQuery.of(context).size.width < 470;
    final pandaSize = isMobile ? 88.0 : 112.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        // Titel entfernt → kein „Kurzgeschichte“ ganz oben
        appBar: const zw.ZenAppBar(title: null, showBack: true),
        body: Stack(
          children: [
            const Positioned.fill(
              child: zw.ZenBackdrop(
                asset: 'assets/pro_screen.png',
                alignment: Alignment.center,
                glow: .34,
                vignette: .12,
                enableHaze: true,
                hazeStrength: .14,
                saturation: .94,
                wash: .10,
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: hasContent
                        // --- Ergebnisansicht (ohne Panda-Header) ---
                        ? _StoryCard(
                            title: _story!.title.trim(),
                            body: _story!.body.trim(),
                            loading: _loading,
                            speaking: _speaking,
                            saved: _storySaved,
                            onSave: _storySaved ? null : _saveCurrentStory,
                            onToggleSpeak: _story == null ? null : _toggleSpeak,
                            onStopSpeak: _speaking ? _stopSpeaking : null,
                          )
                        // --- Gate mit PandaHeader-Widget (keine fette Headline) ---
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              zw.PandaHeader(
                                title: 'Deine Kurzgeschichte',
                                caption: 'Zeit hat keine Eile.',
                                pandaSize: pandaSize,
                                strongTitleGreen: true,
                              ),
                              const SizedBox(height: 8),
                              _StoryGate(
                                progress: _progressCount(context),
                                loading: _loading,
                                error: _error,
                                onGenerate:
                                    _loading ? null : () => _generateStory(),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),

            // Lade-Overlay zentriert, überlagert den Inhalt dezent
            if (_loading) const zw.ZenCenteredLoadingOverlay(),
          ],
        ),
      ),
    );
  }
}

/// ====== EMPTY-STATE / PROGRESS-GATE ========================================
class _StoryGate extends StatelessWidget {
  final int progress;
  final bool loading;
  final String? error;
  final VoidCallback? onGenerate;

  static const int needed = StoryScreen.neededReflections;

  const _StoryGate({
    required this.progress,
    required this.loading,
    this.error,
    this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final done = progress >= needed;

    return zw.ZenGlassCard(
      borderRadius: const BorderRadius.all(zs.ZenRadii.l),
      topOpacity: .24,
      bottomOpacity: .10,
      borderOpacity: .16,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nur Instruktion – keine fette „Moment“-Headline mehr
          Text(
            done
                ? 'Drücke den Button, wenn du bereit bist. Aus deinen letzten Gedanken entsteht jetzt eine kleine, warme Geschichte.'
                : 'Sammle $needed kurze Reflexionen. Danach entsteht aus deinen Worten eine kleine, warme Geschichte nur für dich.',
            textAlign: TextAlign.center,
            style: zs.ZenTextStyles.body
                .copyWith(color: zs.ZenColors.ink, height: 1.45),
          ),
          const SizedBox(height: 16),
          _CapsuleProgress(total: needed, value: progress.clamp(0, needed)),
          const SizedBox(height: 10),
          Opacity(
            opacity: .9,
            child: Text(
              '${progress.clamp(0, needed)} / $needed Reflexionen',
              style: zs.ZenTextStyles.caption
                  .copyWith(color: zs.ZenColors.jadeMid),
            ),
          ),
          const SizedBox(height: 16),

          // CTA – dezent, gekürztes Label
          SizedBox(
            width: 320,
            child: done
                ? _DezenterCtaButton.icon(
                    icon: Icons.auto_stories_rounded,
                    label: 'Therapeutische Kurzgeschichte',
                    onPressed: loading ? null : onGenerate,
                  )
                : ElevatedButton.icon(
                    icon: const Icon(Icons.psychology_alt_rounded),
                    label: const Text('Jetzt reflektieren'),
                    onPressed: loading
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ReflectionScreen()),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(zs.ZenRadii.l),
                      ),
                    ),
                  ),
          ),

          if (error != null && error!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: zs.ZenTextStyles.caption
                  .copyWith(color: zs.ZenColors.cherry),
            ),
          ],
        ],
      ),
    );
  }
}

class _DezenterCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const _DezenterCtaButton({super.key, required this.label})
      : icon = null,
        onPressed = null;
  const _DezenterCtaButton.icon({required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: zs.ZenColors.jade, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: zs.ZenColors.jade,
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
              letterSpacing: 0.15,
            ),
          ),
        ),
      ],
    );

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: zs.ZenColors.jade.withValues(alpha: .75), width: 1.1),
        foregroundColor: zs.ZenColors.jade,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(zs.ZenRadii.l),
        ),
      ),
      child: child,
    );
  }
}

class _CapsuleProgress extends StatelessWidget {
  final int total;
  final int value;
  const _CapsuleProgress({required this.total, required this.value});

  @override
  Widget build(BuildContext context) {
    final filled = List<bool>.generate(total, (i) => i < value);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: 28,
            height: 14,
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 8),
            decoration: BoxDecoration(
              color: filled[i]
                  ? zs.ZenColors.jade.withValues(alpha: .22)
                  : zs.ZenColors.surfaceAlt,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: filled[i]
                    ? zs.ZenColors.jade.withValues(alpha: .55)
                    : zs.ZenColors.outline,
              ),
              boxShadow: filled[i]
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
          ),
      ],
    );
  }
}

/// ====== STORY-KARTE =========================================================
class _StoryCard extends StatelessWidget {
  final String title;
  final String body;
  final VoidCallback? onToggleSpeak;
  final VoidCallback? onStopSpeak;
  final VoidCallback? onSave;
  final bool loading;
  final bool speaking;
  final bool saved;

  const _StoryCard({
    required this.title,
    required this.body,
    required this.loading,
    this.onToggleSpeak,
    this.onStopSpeak,
    this.onSave,
    this.speaking = false,
    this.saved = false,
  });

  @override
  Widget build(BuildContext context) {
    return zw.ZenGlassCard(
      borderRadius: const BorderRadius.all(zs.ZenRadii.l),
      topOpacity: .24,
      bottomOpacity: .10,
      borderOpacity: .16,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: zs.ZenTextStyles.h2.copyWith(
                color: zs.ZenColors.jade,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            body,
            textAlign: TextAlign.left,
            style: zs.ZenTextStyles.body.copyWith(
              color: zs.ZenColors.inkStrong,
              fontSize: 17,
              height: 1.42,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              // NEU: Speichern
              _StoryAction(
                icon: saved ? Icons.bookmark_added_rounded : Icons.bookmark_add_rounded,
                label: saved ? 'Gespeichert' : 'Kurzgeschichte speichern',
                onTap: saved ? () {} : (onSave ?? () {}),
              ),
              _StoryAction(
                icon: speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                label: speaking ? 'Stopp' : 'Anhören',
                onTap: speaking ? (onStopSpeak ?? () {}) : (onToggleSpeak ?? () {}),
              ),
              _StoryAction(
                icon: Icons.copy_rounded,
                label: 'Kopieren',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: '$title\n\n$body'));
                  if (context.mounted) {
                    zw.ZenToast.show(context, 'Text kopiert');
                  }
                  HapticFeedback.selectionClick();
                },
              ),
              _StoryAction(
                icon: Icons.download_rounded,
                label: 'Als TXT',
                onTap: () async {
                  final path = await _saveAsTxt(title, body);
                  if (context.mounted) {
                    zw.ZenToast.show(context, 'Gespeichert: $path');
                  }
                  HapticFeedback.lightImpact();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Hinweis: Bleibt lokal. Teilen ist optional.',
            style: zs.ZenTextStyles.caption.copyWith(color: zs.ZenColors.inkSubtle),
          ),
        ],
      ),
    );
  }

  Future<String> _saveAsTxt(String title, String text) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = _sanitizeFileName(title);
    final file = File('${dir.path}/$safe.txt');
    await file.writeAsString('$title\n\n$text');
    return file.path;
  }

  String _sanitizeFileName(String s) {
    final trimmed = s.trim().isEmpty ? 'zenyourself_story' : s.trim();
    final base = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return base.length > 60 ? base.substring(0, 60) : base;
  }
}

// Kleiner Action-Button im Zen-Stil
class _StoryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _StoryAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: zs.ZenColors.jade),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: zs.ZenColors.jade,
          side: const BorderSide(color: zs.ZenColors.jade, width: 1.1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(zs.ZenRadii.m),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
        ),
      ),
    );
  }
}
