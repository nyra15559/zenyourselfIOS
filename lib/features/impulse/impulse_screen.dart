// lib/features/impulse/impulse_screen.dart
//
// ImpulseScreen — Oxford Zen Pro v3.5 (breath coach + mood assets + worker-ready)
// -------------------------------------------------------------------------------
// Changes (v3.5):
// • Provider: sicheres `_maybeRead<T>()` statt nicht vorhandenem `Provider.maybeOf`.
// • Import-Konflikt gelöst: `zen_style.dart` alias `zs`, `ZenGlassCard` nur aus ui.
// • Stable Flutter APIs: überall `.withOpacity(...)`.
// • PageView reset nur bei nicht-leerer Liste.
// • BreathCoach: createTicker() + sauberes stop()/dispose().
//

import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // Ticker
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer;

import '../../shared/zen_style.dart' as zs hide ZenGlassCard; // ← Konflikt vermeiden
import '../../shared/ui/zen_widgets.dart'
    show ZenBackdrop, ZenGlassCard, ZenAppBar, ZenToast;
import '../../audio/soundscape_manager.dart';
import '../../providers/journal_entries_provider.dart';

const Duration _animShort = Duration(milliseconds: 160);
const Duration _animMed = Duration(milliseconds: 260);

enum ImpulseKind { breath, meditation, pmr, micro }

class ZenImpulse {
  final String title;
  final String text;
  final String image; // Asset-Pfad
  final String? audio; // Asset-Pfad (optional)
  final ImpulseKind kind;
  final BreathPattern? breath;

  ZenImpulse({
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
  BreathPattern({required this.phases, this.cycles = 4});

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
    ZenImpulse(
      kind: ImpulseKind.meditation,
      title: 'Der innere Garten',
      text: 'Stell dir deinen Geist als Garten vor. Gehe langsam durch ihn.',
      image: 'assets/panda_moods/mood_sun.png',
      audio: 'assets/audio/birds_garden.mp3',
    ),
    ZenImpulse(
      kind: ImpulseKind.pmr,
      title: 'Schultern lockern',
      text: 'Heb die Schultern, halte kurz, lass sinken. Wiederhole sanft.',
      image: 'assets/panda_moods/mood_rain.png',
      audio: 'assets/audio/neutral_flow.mp3',
    ),
    ZenImpulse(
      kind: ImpulseKind.micro,
      title: 'Kleine Freundlichkeit',
      text:
          'Wem — oder dir selbst — schenkst du heute eine winzige Freundlichkeit?',
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
    // Optional: Worker lädt dynamische Impulse → ersetzt _all
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

  // provider optional lesen (Null, wenn nicht registriert)
  T? _maybeRead<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  // Audio-Logik
  Future<void> _playAudio(ZenImpulse imp) async {
    try {
      final ssm = _maybeRead<SoundscapeManager>(context);
      if (ssm != null && imp.audio != null) {
        await ssm.play(imp.audio!, fadeIn: 1.0);
        ZenToast.show(context, 'Audio gestartet');
        return;
      }
    } catch (_) {}
    try {
      if ((imp.audio ?? '').isEmpty) {
        ZenToast.show(context, 'Kein Audio verfügbar');
        return;
      }
      _fallbackPlayer ??= AudioPlayer();
      await _fallbackPlayer!.setAsset(imp.audio!);
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
      final p = Provider.of<JournalEntriesProvider>(context, listen: false);
      final merged = '${imp.title}\n\n${imp.text}'.trim();
      p.addDiary(text: merged);
      ZenToast.show(context, 'Als Tagebuch gespeichert');
      HapticFeedback.selectionClick();
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
            tooltip: 'Soundscape',
            icon: const Icon(Icons.library_music_rounded, color: zs.ZenColors.jade),
            onPressed: () {
              final ssm = _maybeRead<SoundscapeManager>(context);
              ssm?.toggle();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Stimmungs-Asset als Hintergrund
          Positioned.fill(
            child: _SafeBg(asset: current?.image ?? 'assets/paper_texture.png'),
          ),
          // Dezent gefärbter Screen-Gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(.82),
                    Colors.white.withOpacity(.66),
                    Colors.white.withOpacity(.58),
                  ],
                ),
              ),
            ),
          ),
          // Sanfter Blur (non-const, da ImageFilter.blur nicht const ist)
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
                  onChanged: (k) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _filter = k;
                      _index = 0;
                      if (_impulses.isNotEmpty) {
                        _page.jumpToPage(0);
                      }
                    });
                  },
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
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.ios_share_rounded),
                          label: const Text('Teilen'),
                          onPressed:
                              current == null ? null : () => _share(current),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: zs.ZenColors.jade,
                            side: const BorderSide(
                                color: zs.ZenColors.jade, width: 1.1),
                            shape: const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.all(zs.ZenRadii.m),
                            ),
                            minimumSize: const Size(0, 44),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Nächster Impuls'),
                          onPressed: _impulses.isEmpty ? null : _next,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            shape: const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.all(zs.ZenRadii.m),
                            ),
                          ),
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

// ─────────────────────────── Subwidgets ───────────────────────────

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
          showCheckmark: false,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color:
                      selected ? zs.ZenColors.jade : zs.ZenColors.jadeMid),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
          selectedColor: zs.ZenColors.jade.withOpacity(.10),
          side: BorderSide(
            color: selected
                ? zs.ZenColors.jade.withOpacity(.55)
                : zs.ZenColors.outline,
          ),
          shape: const StadiumBorder(),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          chip(ImpulseKind.breath, 'Atmung', Icons.air),
          chip(ImpulseKind.meditation, 'Meditation', Icons.self_improvement),
          chip(ImpulseKind.pmr, 'PMR', Icons.accessibility_new),
          chip(ImpulseKind.micro, 'Mikro', Icons.flash_on),
        ],
      ),
    );
  }
}

class _ImpulseCardBody extends StatelessWidget {
  final ZenImpulse impulse;
  final VoidCallback onPlay, onSave, onShare;

  const _ImpulseCardBody({
    required this.impulse,
    required this.onPlay,
    required this.onSave,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ZenGlassCard(
        borderRadius: const BorderRadius.all(zs.ZenRadii.xl),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        topOpacity: .26,
        bottomOpacity: .10,
        borderOpacity: .18,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              impulse.title,
              style: zs.ZenTextStyles.h2.copyWith(
                color: zs.ZenColors.deepSage,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              impulse.text,
              style: tt.bodyMedium?.copyWith(
                color: zs.ZenColors.inkStrong,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),

            // Breath-Coach oder Standard-Actions
            if (impulse.breath != null)
              _BreathCoach(pattern: impulse.breath!, onPlay: onPlay)
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.music_note),
                    label: const Text('Audio'),
                    onPressed: onPlay,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: zs.ZenColors.jade,
                      side: const BorderSide(
                          color: zs.ZenColors.jade, width: 1.1),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(zs.ZenRadii.m),
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Als Tagebuch'),
                    onPressed: onSave,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: zs.ZenColors.jade,
                      side: const BorderSide(
                          color: zs.ZenColors.jade, width: 1.1),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(zs.ZenRadii.m),
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Teilen'),
                    onPressed: onShare,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: zs.ZenColors.jade,
                      side: const BorderSide(
                          color: zs.ZenColors.jade, width: 1.1),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(zs.ZenRadii.m),
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                ],
              ),
          ],
        ),
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

class _BreathCoachState extends State<_BreathCoach>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _running = false;
  int _cycle = 0, _phaseIndex = 0, _elapsedMs = 0;

  _Phase get _phase => widget.pattern.phases[_phaseIndex];
  int get _phaseMsTotal => _phase.seconds * 1000;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      if (!_running) return;
      setState(() {
        _elapsedMs += d.inMilliseconds;
        if (_elapsedMs >= _phaseMsTotal) {
          _elapsedMs = 0;
          _phaseIndex++;
          if (_phaseIndex >= widget.pattern.phases.length) {
            _phaseIndex = 0;
            _cycle++;
            if (_cycle >= widget.pattern.cycles) {
              _running = false;
              ZenToast.show(context, 'Atemrunde beendet');
              // sauber stoppen, damit kein Leerlauf-Ticker weiterläuft
              _ticker.stop();
            }
          }
        }
      });
    });
  }

  @override
  void dispose() {
    try {
      _ticker.stop();
      _ticker.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _start() {
    HapticFeedback.selectionClick();
    setState(() {
      _cycle = 0;
      _phaseIndex = 0;
      _elapsedMs = 0;
      _running = true;
    });
    if (!_ticker.isActive) _ticker.start();
  }

  void _stop() {
    setState(() => _running = false);
    _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final leftSec = ((_phaseMsTotal - _elapsedMs) / 1000).ceil();
    final progress = _phaseMsTotal == 0
        ? 0.0
        : (_elapsedMs.clamp(0, _phaseMsTotal) / _phaseMsTotal);

    return Column(
      children: [
        // animierter Kreis
        SizedBox(
          width: 164,
          height: 164,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: _animShort,
            builder: (_, v, __) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _CirclePainter(progress: v),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_phase.label,
                            style: zs.ZenTextStyles.subtitle
                                .copyWith(color: zs.ZenColors.inkStrong)),
                        const SizedBox(height: 4),
                        Text('$leftSec s',
                            style: zs.ZenTextStyles.caption
                                .copyWith(color: zs.ZenColors.jadeMid)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text('Zyklus ${_cycle + 1} / ${widget.pattern.cycles}',
            style:
                zs.ZenTextStyles.caption.copyWith(color: zs.ZenColors.inkSubtle)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              icon: Icon(_running ? Icons.stop : Icons.play_arrow),
              label: Text(_running ? 'Stop' : 'Start'),
              onPressed: _running ? _stop : _start,
              style: OutlinedButton.styleFrom(
                foregroundColor: zs.ZenColors.jade,
                side: const BorderSide(color: zs.ZenColors.jade, width: 1.1),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(zs.ZenRadii.m),
                ),
                minimumSize: const Size(0, 44),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.music_note),
              label: const Text('Audio'),
              onPressed: widget.onPlay,
              style: OutlinedButton.styleFrom(
                foregroundColor: zs.ZenColors.jade,
                side: const BorderSide(color: zs.ZenColors.jade, width: 1.1),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(zs.ZenRadii.m),
                ),
                minimumSize: const Size(0, 44),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double progress; // 0..1
  _CirclePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;

    final bg = Paint()
      ..color = zs.ZenColors.mist.withOpacity(.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;

    final fg = Paint()
      ..color = zs.ZenColors.jade
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;

    // Außenkreis (ruhig)
    canvas.drawCircle(c, r, bg);

    // Fortschritt (0..1 → Winkel)
    final sweep = 2 * math.pi * progress;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fg);
  }

  @override
  bool shouldRepaint(covariant _CirclePainter old) =>
      old.progress != progress;
}

class _Dots extends StatelessWidget {
  final int count, index;
  const _Dots({required this.count, required this.index});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            count,
            (i) => AnimatedContainer(
              duration: _animShort,
              margin: const EdgeInsets.all(3),
              width: i == index ? 10 : 8,
              height: i == index ? 10 : 8,
              decoration: BoxDecoration(
                color: i == index ? zs.ZenColors.jade : zs.ZenColors.cloud,
                shape: BoxShape.circle,
              ),
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
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const DecoratedBox(decoration: BoxDecoration(color: Colors.white)),
    );
  }
}
