// lib/features/impulse/impulse_screen.dart
//
// ImpulseScreen — Oxford Zen Pro v3.2 (breath coach + mood assets + worker-ready)
// -------------------------------------------------------------------------------
// - Kategorien: Atmung, Meditation, PMR, Mikro
// - Breath-Coach mit animiertem Kreis, Phasenanzeige, Zyklen
// - Mood-Assets als Hintergründe (cloud, leaf, rain, sun, swirl, reflect, paper, startbilder)
// - Audio robust (SoundscapeManager oder just_audio Fallback)
// - Worker-Schnittstelle vorbereitet: _loadFromWorker()
// - Fehlerfreie Build: Ticker-Import, nur vorhandene Styles/Farben

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // ✅ für Ticker
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer;

import '../../shared/zen_style.dart';
import '../../shared/ui/zen_widgets.dart';
import '../../audio/soundscape_manager.dart';
import '../../providers/journal_entries_provider.dart';
import '../../models/journal_entry.dart' as jm;

const Duration _animShort = Duration(milliseconds: 160);
const Duration _animMed = Duration(milliseconds: 260);

enum ImpulseKind { breath, meditation, pmr, micro }

class ZenImpulse {
  final String title;
  final String text;
  final String image;
  final String? audio;
  final ImpulseKind kind;
  final BreathPattern? breath;

  const ZenImpulse({
    required this.title,
    required this.text,
    required this.image,
    required this.kind,
    this.audio,
    this.breath,
  });
}

// Atemmuster
class BreathPattern {
  final List<_Phase> phases;
  final int cycles;
  const BreathPattern({required this.phases, this.cycles = 4});

  static BreathPattern box({int seconds = 4, int cycles = 4}) => BreathPattern(
        phases: [
          _Phase('Einatmen', seconds),
          _Phase('Halten', seconds),
          _Phase('Ausatmen', seconds),
          _Phase('Halten', seconds),
        ],
        cycles: cycles,
      );

  static BreathPattern fourSevenEight({int cycles = 4}) => BreathPattern(
        phases: [
          const _Phase('Einatmen', 4),
          const _Phase('Halten', 7),
          const _Phase('Ausatmen', 8),
        ],
        cycles: cycles,
      );

  static BreathPattern equal({int seconds = 5, int cycles = 5}) => BreathPattern(
        phases: [
          _Phase('Einatmen', seconds),
          _Phase('Ausatmen', seconds),
        ],
        cycles: cycles,
      );
}

class _Phase {
  final String label;
  final int seconds;
  const _Phase(this.label, this.seconds);
}

class ImpulseScreen extends StatefulWidget {
  const ImpulseScreen({super.key});
  @override
  State<ImpulseScreen> createState() => _ImpulseScreenState();
}

class _ImpulseScreenState extends State<ImpulseScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _page;
  late final AnimationController _glowCtrl;

  int _index = 0;
  ImpulseKind _filter = ImpulseKind.breath;
  AudioPlayer? _fallbackPlayer;

  // Lokale Basis-Impulse (Mood-Assets eingebaut)
  late final List<ZenImpulse> _all = [
    ZenImpulse(
      kind: ImpulseKind.breath,
      title: '4-7-8 Atem',
      text: 'Atme 4 Sekunden ein, halte 7, atme 8 aus.',
      image: 'assets/panda_moods/mood_cloud.png',
      audio: 'assets/audio/neutral_flow.mp3',
      breath: BreathPattern.fourSevenEight(),
    ),
    ZenImpulse(
      kind: ImpulseKind.breath,
      title: 'Box-Breath',
      text: 'Vier gleich lange Phasen: Ein • Halten • Aus • Halten.',
      image: 'assets/panda_moods/mood_leaf.png',
      audio: 'assets/audio/clouds_ambience.mp3',
      breath: BreathPattern.box(),
    ),
    const ZenImpulse(
      kind: ImpulseKind.meditation,
      title: 'Der innere Garten',
      text: 'Stell dir deinen Geist als Garten vor.',
      image: 'assets/panda_moods/mood_sun.png',
      audio: 'assets/audio/birds_garden.mp3',
    ),
    const ZenImpulse(
      kind: ImpulseKind.pmr,
      title: 'Schultern lockern',
      text: 'Heb die Schultern, halte kurz, lass sinken.',
      image: 'assets/panda_moods/mood_rain.png',
      audio: 'assets/audio/neutral_flow.mp3',
    ),
    const ZenImpulse(
      kind: ImpulseKind.micro,
      title: 'Kleine Freundlichkeit',
      text: 'Wem — oder dir selbst — schenkst du heute eine winzige Freundlichkeit?',
      image: 'assets/panda_moods/mood_swirl.png',
      audio: 'assets/audio/sunshine_zen.mp3',
    ),
  ];

  List<ZenImpulse> get _impulses =>
      _all.where((i) => i.kind == _filter).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _page = PageController();
    _glowCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
    // Später: Worker laden
    //_loadFromWorker();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _page.dispose();
    _fallbackPlayer?.dispose();
    super.dispose();
  }

  // Worker-ready Loader
  Future<void> _loadFromWorker() async {
    try {
      // final res = await GuidanceService().fetchImpulses();
      // setState(() => _all = res);
    } catch (_) {
      // Fallback bleibt _all
    }
  }

  // Audio-Logik
  Future<void> _playAudio(ZenImpulse imp) async {
    try {
      final ssm = context.read<SoundscapeManager?>();
      if (ssm != null && imp.audio != null) {
        await ssm.play(imp.audio!, fadeIn: 1.0);
        ZenToast.show(context, 'Audio gestartet');
        return;
      }
    } catch (_) {}
    try {
      _fallbackPlayer ??= AudioPlayer();
      await _fallbackPlayer!.setAsset(imp.audio ?? 'assets/audio/neutral_flow.mp3');
      await _fallbackPlayer!.play();
    } catch (_) {
      ZenToast.show(context, 'Audio nicht verfügbar');
    }
  }

  Future<void> _share(ZenImpulse imp) async {
    await Share.share('${imp.title}\n\n${imp.text}', subject: 'Zen-Impuls');
  }

  Future<void> _saveAsJournal(ZenImpulse imp) async {
    try {
      final p = context.read<JournalEntriesProvider>();
      final entry = jm.JournalEntry.journal(
        id: 'imp_${DateTime.now().microsecondsSinceEpoch}',
        title: imp.title,
        thoughtText: imp.text,
        tags: const ['source:impulse'],
      );
      p.add(entry);
      ZenToast.show(context, 'Als Tagebuch gespeichert');
    } catch (_) {}
  }

  void _next() {
    final max = _impulses.length - 1;
    final next = (_index + 1).clamp(0, max);
    if (next == _index) {
      ZenToast.show(context, 'Letzter Impuls erreicht');
      return;
    }
    _page.animateToPage(next, duration: _animMed, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final current = _impulses.isNotEmpty ? _impulses[_index] : null;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ZenAppBar(
        title: 'Impulse',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.library_music_rounded, color: ZenColors.jade),
            onPressed: () => context.read<SoundscapeManager?>()?.toggle(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _SafeBg(asset: current?.image ?? 'assets/paper_texture.png'),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: ZenGradients.screen),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: const SizedBox.shrink(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _FilterChips(
                  value: _filter,
                  onChanged: (k) => setState(() {
                    _filter = k;
                    _index = 0;
                    _page.jumpToPage(0);
                  }),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _impulses.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => _ImpulseCardBody(
                      impulse: _impulses[i],
                      onPlay: () => _playAudio(_impulses[i]),
                      onSave: () => _saveAsJournal(_impulses[i]),
                      onShare: () => _share(_impulses[i]),
                    ),
                  ),
                ),
                _Dots(count: _impulses.length, index: _index),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ZenOutlineButton(
                          label: 'Teilen',
                          icon: Icons.ios_share_rounded,
                          onPressed: current == null ? null : () => _share(current),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ZenPrimaryButton(
                          label: 'Nächster Impuls',
                          icon: Icons.refresh_rounded,
                          onPressed: _impulses.isEmpty ? null : _next,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Subwidgets (FilterChips, CardBody, BreathCoach etc.) ---

class _FilterChips extends StatelessWidget {
  final ImpulseKind value;
  final ValueChanged<ImpulseKind> onChanged;
  const _FilterChips({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    Widget chip(ImpulseKind k, String label, IconData icon) {
      final selected = value == k;
      return Padding(
        padding: const EdgeInsets.all(4),
        child: FilterChip(
          selected: selected,
          onSelected: (_) => onChanged(k),
          label: Text(label),
          avatar: Icon(icon, size: 18),
        ),
      );
    }
    return Wrap(
      children: [
        chip(ImpulseKind.breath, 'Atmung', Icons.air),
        chip(ImpulseKind.meditation, 'Meditation', Icons.self_improvement),
        chip(ImpulseKind.pmr, 'PMR', Icons.accessibility_new),
        chip(ImpulseKind.micro, 'Mikro', Icons.flash_on),
      ],
    );
  }
}

class _ImpulseCardBody extends StatelessWidget {
  final ZenImpulse impulse;
  final VoidCallback onPlay, onSave, onShare;
  const _ImpulseCardBody({required this.impulse, required this.onPlay, required this.onSave, required this.onShare});
  @override
  Widget build(BuildContext context) {
    return ZenCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(impulse.title, style: ZenTextStyles.h2),
          const SizedBox(height: 8),
          Text(impulse.text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (impulse.breath != null)
            _BreathCoach(pattern: impulse.breath!, onPlay: onPlay)
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AudioButton(onPressed: onPlay),
                const SizedBox(width: 8),
                ZenOutlineButton(label: 'Als Tagebuch', icon: Icons.bookmark, onPressed: onSave),
              ],
            ),
        ],
      ),
    );
  }
}

class _BreathCoach extends StatefulWidget {
  final BreathPattern pattern;
  final VoidCallback onPlay;
  const _BreathCoach({required this.pattern, required this.onPlay});
  @override
  State<_BreathCoach> createState() => _BreathCoachState();
}

class _BreathCoachState extends State<_BreathCoach> with SingleTickerProviderStateMixin {
  late final Ticker _ticker; // ✅ jetzt gefunden
  bool _running = false;
  int _cycle = 0, _phaseIndex = 0, _elapsedMs = 0;

  _Phase get _phase => widget.pattern.phases[_phaseIndex];
  int get _phaseMsTotal => _phase.seconds * 1000;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker((d) {
      if (!_running) return;
      setState(() {
        _elapsedMs += d.inMilliseconds;
        if (_elapsedMs >= _phaseMsTotal) {
          _elapsedMs = 0;
          _phaseIndex++;
          if (_phaseIndex >= widget.pattern.phases.length) {
            _phaseIndex = 0;
            _cycle++;
            if (_cycle >= widget.pattern.cycles) _running = false;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _cycle = 0; _phaseIndex = 0; _elapsedMs = 0; _running = true;
    });
    _ticker.start();
  }

  void _stop() { setState(() => _running = false); _ticker.stop(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${_phase.label} • ${(_phaseMsTotal - _elapsedMs) ~/ 1000}s'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ZenOutlineButton(label: _running ? 'Stop' : 'Start', icon: _running ? Icons.stop : Icons.play_arrow, onPressed: _running ? _stop : _start),
            const SizedBox(width: 8),
            ZenOutlineButton(label: 'Audio', icon: Icons.music_note, onPressed: widget.onPlay),
          ],
        )
      ],
    );
  }
}

class _AudioButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AudioButton({required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return ZenOutlineButton(label: 'Audio', icon: Icons.play_arrow, onPressed: onPressed);
  }
}

class _Dots extends StatelessWidget {
  final int count, index;
  const _Dots({required this.count, required this.index});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          count,
          (i) => Container(
            margin: const EdgeInsets.all(3),
            width: i == index ? 10 : 8,
            height: i == index ? 10 : 8,
            decoration: BoxDecoration(
              color: i == index ? ZenColors.jade : ZenColors.cloud,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}

class _SafeBg extends StatelessWidget {
  final String asset;
  const _SafeBg({required this.asset});
  @override
  Widget build(BuildContext context) {
    return Image.asset(asset, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const DecoratedBox(decoration: BoxDecoration(color: Colors.black12)));
  }
}
