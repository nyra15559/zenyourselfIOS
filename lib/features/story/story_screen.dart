// lib/features/story/story_screen.dart
//
// StoryScreen — Zen v6.54 (Oxford polish · StartScreen-Matching · Top-Anchor)
// Update: 2025-09-15
// -----------------------------------------------------------------------------
// • Hero-Panda wie im StartScreen (160/200 px), identische Typo-Abstände.
// • NEU: Top-Anchor statt Zentrierung → Panda steht im oberen Drittel
//   (viewport-abhängig: ~12% Höhe, mit Min/Max-Klammern).
// • Anordnung: Panda → Titel → Tagline → Gate-Karte (wie StartScreen).
// • Keine Breaking Changes (Public API unverändert).
// • A11y/Robustheit: Semantics, mounted-Guards, defensive errorBuilder.
//

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../services/guidance/dtos.dart';




// Zen-Design (Tokens)
import '../../shared/zen_style.dart' as zs hide ZenBackdrop, ZenGlassCard, ZenAppBar;
// Zen-Widgets
import '../../shared/ui/zen_widgets.dart' as zw;

// Daten
import '../../providers/journal_entries_provider.dart';
import '../../models/journal_entry.dart' as jm;

// Services
import '../../services/guidance_service.dart';
import '../../services/local_storage.dart';

// TTS
import '../../services/tts_service.dart' as tts;

// Für CTA "Reflektieren"
import '../reflection/reflection_screen.dart';

const String kStoryPandaAsset = 'assets/story_panda_final.png';

// Feintuning für die vertikale Verankerung des Heros.
// Passe factor/min/max bei Bedarf minimal an.
const double _kHeroTopAnchorFactor = 0.01; // 12% der Höhe
const double _kHeroTopAnchorMin = -10;      // min. 36 px
const double _kHeroTopAnchorMax = 60;     // max. 120 px

class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  static const int neededReflections = 5;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen>
    with SingleTickerProviderStateMixin {
  StoryResult? _story; // aktuelles Ergebnis
  bool _loading = false;
  String? _error;

  // Save-Status
  bool _storySaved = false;
  String? _savedEntryId;

  // Fortschritts-Reset (Persistenz)
  static const String _kResetAtKey = 'story:lastResetAt';
  final LocalStorageService _store = LocalStorageService();
  DateTime? _lastResetAt; // UTC ISO aus Prefs (null = noch nie zurückgesetzt)

  // TTS
  bool _speaking = false;
  late final VoidCallback _speakingListener;

  // Micro-Transition
  late final AnimationController _anim;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);

    _speakingListener = () {
      if (!mounted) return;
      setState(() => _speaking = tts.TtsService.instance.speaking.value);
    };
    tts.TtsService.instance.speaking.addListener(_speakingListener);
  }

  Future<void> _initPrefs() async {
    await _store.init();
    final s = await _store.loadSetting<String>(_kResetAtKey);
    if (!mounted) return;
    setState(() {
      _lastResetAt = (s == null || s.trim().isEmpty) ? null : DateTime.tryParse(s);
    });
  }

  @override
  void dispose() {
    _stopSpeakingSilently();
    tts.TtsService.instance.speaking.removeListener(_speakingListener);
    _anim.dispose();
    super.dispose();
  }

  // ---- Progress / Daten -----------------------------------------------------

  int _progressFrom(JournalEntriesProvider journal) {
    final List<jm.JournalEntry> all = journal.entries.where(_isReflection).toList();
    if (_lastResetAt == null) {
      return all.length.clamp(0, StoryScreen.neededReflections);
    }
    final n = all.where((e) => e.createdAt.isAfter(_lastResetAt!)).length;
    return n.clamp(0, StoryScreen.neededReflections);
  }

  List<jm.JournalEntry> _lastNReflectionsSinceReset(
    JournalEntriesProvider prov,
    int n,
  ) {
    final all = prov.entries.where(_isReflection).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (_lastResetAt == null) {
      return all.take(n).toList();
    }
    final afterReset = all.where((e) => e.createdAt.isAfter(_lastResetAt!)).toList();
    return afterReset.take(n).toList();
  }

  bool _isReflection(jm.JournalEntry e) => e.kind == jm.EntryKind.reflection;

  // ---- Story-Generierung ----------------------------------------------------
  Future<void> _generateStory() async {
    if (!mounted) return;

    final prov = context.read<JournalEntriesProvider>();
    final progress = _progressFrom(prov);
    if (progress < StoryScreen.neededReflections) {
      HapticFeedback.selectionClick();
      setState(() => _error =
          'Noch nicht genug Reflexionen ($progress/${StoryScreen.neededReflections}).');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _storySaved = false;
      _savedEntryId = null;
    });

    try {
      await _feelDelay(200);

      final recent = _lastNReflectionsSinceReset(prov, StoryScreen.neededReflections);
      final topics = await _deriveTopics(recent);

      if (!mounted) return;
      if (topics.isEmpty || recent.length < StoryScreen.neededReflections) {
        throw Exception('Nicht genug Inhalte für eine Kurzgeschichte.');
      }

      await _feelDelay(420);

      final story = await GuidanceService.instance.story(
        entryIds: recent.map((e) => e.id).toList(),
        topics: topics,
        useServerIfAvailable: true,
      );

      if (!mounted) return;

      final ok = ((story.title.trim().isNotEmpty) || (story.body.trim().isNotEmpty));
      if (!ok) {
        throw Exception('Story-Service ohne Inhalt geantwortet.');
      }

      setState(() {
        _story = story;
        _loading = false;
      });

      zw.ZenToast.show(context, 'Geschichte erstellt');
      HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<List<String>> _deriveTopics(List<jm.JournalEntry> entries) async {
    final set = <String>{};
    for (final e in entries) {
      final q = (e.aiQuestion ?? '').trim();
      if (q.isNotEmpty) set.add(_compact(q));

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
        final dynamic svc = GuidanceService.instance;
        final tags = await (svc.suggestTags(content) as Future<List<String>>);
        set.addAll(tags.map(_compact));
      } catch (_) {/* optional */}
    }
    final topics = set.where((t) => t.length >= 2).take(6).toList();
    if (topics.isEmpty) topics.add('Selbstfürsorge');
    return topics;
  }

  String _compact(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[\.!?]'), '').trim();

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('Nicht genug Inhalte')) {
      return 'Nicht genug Inhalte für eine Kurzgeschichte.';
    }
    return 'Da hakte etwas. Bitte versuch’s gleich nochmal.';
  }

  Future<void> _feelDelay(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  // ---- SAVE: Kurzgeschichte -> Journal -------------------------------------
  Future<void> _saveCurrentStory() async {
    final s = _story;
    if (s == null) return;

    if (_storySaved) {
      zw.ZenToast.show(context, 'Bereits gespeichert');
      return;
    }

    try {
      final prov = context.read<JournalEntriesProvider>();

      final title = (s.title.trim().isEmpty) ? 'Kurzgeschichte' : s.title.trim();
      final body = s.body.trim();

      if (body.isEmpty && title.isEmpty) {
        zw.ZenToast.show(context, 'Kein Inhalt zum Speichern');
        return;
      }

      final saved = prov.addStory(
        title: title,
        body: body,
        moodLabel: 'Neutral',
        ts: DateTime.now(),
      );

      final nowIso = DateTime.now().toUtc().toIso8601String();
      await _store.saveSetting<String>(_kResetAtKey, nowIso);

      if (!mounted) return;
      setState(() {
        _storySaved = true;
        _savedEntryId = saved.id;
        _lastResetAt = DateTime.tryParse(nowIso);
      });

      zw.ZenToast.show(context, 'Ins Gedankenbuch gespeichert');
      HapticFeedback.selectionClick();
    } catch (_) {
      if (!mounted) return;
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

    // Live-Progress
    final prov = context.watch<JournalEntriesProvider>();
    final progress = _progressFrom(prov);

    // Top-Anchor wie im StartScreen (Panda sitzt sichtbar höher als Center)
    final size = MediaQuery.of(context).size;
    final double anchorTop = (size.height * _kHeroTopAnchorFactor)
        .clamp(_kHeroTopAnchorMin, _kHeroTopAnchorMax);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
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
            // WICHTIG: nicht zentrieren, sondern nach oben verankern
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, anchorTop, 16, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: FadeTransition(
                      opacity: _fadeIn,
                      child: hasContent
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
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _StoryHeroTitle(),
                                // Abstand wie im StartScreen (zwischen Tagline und Content)
                                SizedBox(
                                  height: size.width < 420 ? 12 : 16,
                                ),
                                _StoryGate(
                                  progress: progress,
                                  loading: _loading,
                                  error: _error,
                                  onGenerate: _loading ? null : _generateStory,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),

            if (_loading) const _LoadingOverlay(),
          ],
        ),
      ),
    );
  }
}

/// ====== HERO (Panda & Typo wie im StartScreen) ==============================
class _StoryHeroTitle extends StatelessWidget {
  const _StoryHeroTitle();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final narrow = width < 420;
    final double pandaSize = narrow ? 160 : 200;

    return Column(
      children: [
        Semantics(
          image: true,
          label: 'Panda mit Lesebrille liest ein Buch',
          child: Container(
            margin: EdgeInsets.only(bottom: narrow ? 10 : 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: zs.ZenColors.deepSage.withOpacity(.14),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Image.asset(
              kStoryPandaAsset,
              width: pandaSize,
              height: pandaSize,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
        // Titel + Tagline exakt wie im StartScreen
        Text(
          'Deine Kurzgeschichte',
          textAlign: TextAlign.center,
          style: zs.ZenTextStyles.h2.copyWith(
            fontWeight: FontWeight.w800,
            color: zs.ZenColors.deepSage,
          ),
        ),
        SizedBox(height: narrow ? 4 : 6),
        Text(
          'Zeit hat keine Eile.',
          textAlign: TextAlign.center,
          style: zs.ZenTextStyles.subtitle.copyWith(
            color: zs.ZenColors.jade,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ],
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
          Semantics(
            container: true,
            liveRegion: true,
            label: done
                ? 'Genug Reflexionen vorhanden. Du kannst deine Kurzgeschichte erstellen.'
                : 'Noch ${needed - progress} Reflexionen bis zur Kurzgeschichte.',
            child: Text(
              done
                  ? 'Wenn du bereit bist, entsteht aus deinen letzten Worten eine kleine, warme Geschichte.'
                  : 'Sammle $needed kurze Reflexionen. Danach entsteht aus deinen Worten eine kleine, warme Geschichte nur für dich.',
              textAlign: TextAlign.center,
              style: zs.ZenTextStyles.body
                  .copyWith(color: zs.ZenColors.ink, height: 1.45),
            ),
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
          SizedBox(
            width: 320,
            child: done
                ? _DezenterCtaButton.icon(
                    icon: Icons.auto_stories_rounded,
                    label: 'Kurzgeschichte erstellen',
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
                              MaterialPageRoute(builder: (_) => const ReflectionScreen()),
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
            Semantics(
              liveRegion: true,
              label: 'Fehler',
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: zs.ZenTextStyles.caption
                    .copyWith(color: zs.ZenColors.cherry),
              ),
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

  const _DezenterCtaButton({required this.label})
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
        side: BorderSide(color: zs.ZenColors.jade.withOpacity(.75), width: 1.1),
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
    return Semantics(
      label: 'Fortschritt $value von $total',
      value: '$value',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < total; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: 28,
              height: 14,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 8),
              decoration: BoxDecoration(
                color: filled[i]
                    ? zs.ZenColors.jade.withOpacity(.22)
                    : zs.ZenColors.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: filled[i]
                      ? zs.ZenColors.jade.withOpacity(.55)
                      : zs.ZenColors.outline,
                ),
                boxShadow: filled[i]
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// ====== LOADING OVERLAY =====================================================
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withOpacity(.06),
          alignment: Alignment.center,
          child: const zw.ZenGlassCard(
            borderRadius: BorderRadius.all(zs.ZenRadii.l),
            topOpacity: .26,
            bottomOpacity: .10,
            borderOpacity: .18,
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'ZenYourself holt sein Buch heraus …',
                  style: TextStyle(fontSize: 14.5, color: zs.ZenColors.inkStrong),
                ),
              ],
            ),
          ),
        ),
      ),
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: zs.ZenColors.inkSubtle),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Tipp: Speichere die Kurzgeschichte ins Gedankenbuch – sonst ist sie später nicht mehr sichtbar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: zs.ZenColors.inkSubtle),
                ),
              ),
            ],
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
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
        ),
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
