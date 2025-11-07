// [BASELINE] lib/features/pro/pro_screen.dart (Stand: 2025-11-07)
// P2-S10.4 — Settings-Zahnrad neben Range-Bubbles (statt AppBar); Graph-Switch @200px
// ProScreen — Oxford Journey Board (v4.8.9 · 2025-11-07)
// ------------------------------------------------------------------
// v4.8.9 (S10.4):
// • Zahnrad aus der AppBar entfernt und in die Range-Bubble rechts gesetzt.
// • _RangeBubble erhält onOpenSettings; IconButton mit Tooltip & A11y.
// • Layout bleibt auf kleinen Screens stabil (Chips können umbrechen).
//
// v4.8.8 (S10.3):
// • Back-Button & Settings-Zahnrad über ZenAppBar (actions) – wie Journey.
// • Graph-Ansicht: Switch-Schwelle jetzt bei 200 px statt 410 px.
// • UTF-8 Fix: entferntes unsichtbares Zeichen vor "Widget build" in _MemoryCard.
//
// v4.8.7 (S10.2):
// • Back-Button & Settings-Zahnrad über zw.ZenAppBar(actions:[...]) realisiert.
// • Entfernt: manuell positioniertes Zahnrad im Body-Stack (Z-Reihenfolge/Taps).
//
// v4.8.6 (S10.1):
// • Export-Dialog: auf kleinen Screens als BottomSheet (scrollbar, SafeArea),
//   auf größeren als Dialog mit MaxBreite + Scroll → keine Überläufer mehr.
// • AppBar-Back konsistent via ZenAppBar(showBack:true).
//
// Abhängigkeiten: fl_chart, provider, http, eigene Zen-UI.

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

// Shared UI & Design (Alias-Imports → keine Namenskollisionen)
import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar;

// Domain (Legacy-Fallback)
import '../../data/mood_entry.dart';
import '../../data/reflection_entry.dart';

// Journal (kanonisches Modell)
import '../../providers/journal_entries_provider.dart';

// Export (AnonExportWidget)
import '../therapist/anon_export.dart';

// Settings (Dark-Mode & Gedächtnis)
import '../../models/app_settings.dart';

// ------------------------------------------------------------------

enum _Range { d7, d30, d90 }

extension on _Range {
  int get days =>
      switch (this) { _Range.d7 => 7, _Range.d30 => 30, _Range.d90 => 90 };
  String get label => switch (this) {
        _Range.d7 => '7',
        _Range.d30 => '30',
        _Range.d90 => '90'
      };
}

// Gedächtnis-Modi (Sheet)
enum _MemoryMode { off, light, full }

class ProScreen extends StatefulWidget {
  /// Legacy-Props bleiben für Export/Fallback erhalten.
  final List<MoodEntry> moodEntries;
  final List<ReflectionEntry> reflectionEntries;

  /// Öffnet die Settings – Zahnrad (optional überschreibbar).
  final VoidCallback? onOpenSettings;

  /// Falls du Host/Calls extern überschreiben willst:
  final Future<int?> Function()? loadCommunityHelpCount;
  final Future<int?> Function()? loadCommunityTalkCount;
  final Future<void> Function()? sendCommunityHelpAck;

  const ProScreen({
    super.key,
    required this.moodEntries,
    required this.reflectionEntries,
    this.onOpenSettings,
    this.loadCommunityHelpCount,
    this.loadCommunityTalkCount,
    this.sendCommunityHelpAck,
  });

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen>
    with SingleTickerProviderStateMixin {
  // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  // Cloudflare-Worker Host (deiner):
  static const String _HOST =
      'https://nameless-breeze-87fb.edcvaultcom.workers.dev';
  // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  _Range _range = _Range.d30;

  late final AnimationController _appearCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260))
    ..forward();

  // ---- Community State -------------------------------------------------------
  int? _communityHelpCount; // globaler Zähler „geholfen“
  bool _communityLoading = false;
  bool _sendingAck = false;
  bool _ackSentThisSession = false;

  int? _talkCount; // globaler Zähler „mit Panda geredet“
  bool _talkLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCommunityCount();
    _loadTalkCount();
  }

  // -------------------------- Community Calls (direct) -----------------------

  Future<int?> _fetchCount(String path, String field) async {
    try {
      final uri = Uri.parse('$_HOST$path');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body);
        if (m is Map<String, dynamic>) {
          final v = m[field];
          if (v is int) return v;
          if (v is num) return v.toInt();
        }
      }
    } catch (_) {/* swallow */}
    return null;
  }

  Future<int?> _postAndGetCount(String path, String field) async {
    try {
      final uri = Uri.parse('$_HOST$path');
      final res = await http.post(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body);
        if (m is Map<String, dynamic>) {
          final v = m[field];
          if (v is int) return v;
          if (v is num) return v.toInt();
        }
      }
    } catch (_) {/* swallow */}
    return null;
  }

  Future<void> _loadCommunityCount() async {
    if (!mounted) return;
    setState(() => _communityLoading = true);
    try {
      final loader = widget.loadCommunityHelpCount ??
          (() => _fetchCount('/v1/community/help-total', 'help_total'));
      final v = await loader();
      if (!mounted) return;
      setState(() => _communityHelpCount = v);
    } finally {
      if (mounted) setState(() => _communityLoading = false);
    }
  }

  Future<void> _loadTalkCount() async {
    if (!mounted) return;
    setState(() => _talkLoading = true);
    try {
      final loader = widget.loadCommunityTalkCount ??
          (() => _fetchCount(
              '/v1/community/conversations-total', 'conversations_total'));
      final v = await loader();
      if (!mounted) return;
      setState(() => _talkCount = v);
    } finally {
      if (mounted) setState(() => _talkLoading = false);
    }
  }

  Future<void> _sendHelpAck() async {
    if (_sendingAck) return;
    if (!mounted) return;
    setState(() => _sendingAck = true);
    try {
      if (widget.sendCommunityHelpAck != null) {
        await widget.sendCommunityHelpAck!.call();
        await _loadCommunityCount();
      } else {
        final v =
            await _postAndGetCount('/v1/community/help-ack', 'help_total');
        if (!mounted) return;
        _communityHelpCount = v ?? (_communityHelpCount ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() => _ackSentThisSession = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Danke! Deine anonyme Stimme wurde gezählt.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Konnte das gerade nicht teilen. Versuche es später erneut.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingAck = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Settings-Sheet (Oxford-Zen) – mit Panda-Gedächtnis-Modus (AppSettings)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _openZenSettingsSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (ctx) {
        final isMobile = MediaQuery.of(ctx).size.width < 560;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                12, 0, 12, 12 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: zw.ZenGlassCard(
                      topOpacity: .26,
                      bottomOpacity: .10,
                      borderOpacity: .16,
                      borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                      padding: EdgeInsets.fromLTRB(
                          isMobile ? 14 : 18, 14, isMobile ? 14 : 18, 14),
                      child: Consumer<AppSettings>(
                        builder: (c, settings, _) {
                          final mode = _modeFromSettings(settings);
                          final busy = !settings.isHydrated;
                          return _SettingsContent(
                            isBusy: busy,
                            currentMode: mode,
                            onSelectMode: (m) => _applyMemoryMode(settings, m),
                            darkModeValue: settings.darkMode,
                            onDarkModeChanged: (v) =>
                                settings.toggleDarkMode(v),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  _MemoryMode _modeFromSettings(AppSettings s) {
    if (!s.memoryEnabled && !s.memoryShareEnabled) return _MemoryMode.off;
    if (s.memoryEnabled && !s.memoryShareEnabled) return _MemoryMode.light;
    return _MemoryMode.full;
  }

  Future<void> _applyMemoryMode(AppSettings s, _MemoryMode m) async {
    switch (m) {
      case _MemoryMode.off:
        await s.setMemoryModeOff();
        break;
      case _MemoryMode.light:
        await s.setMemoryModeLight();
        break;
      case _MemoryMode.full:
        await s.setMemoryModeFull();
        break;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Panda-Gedächtnis aktualisiert')),
      );
    }
  }

  @override
  void dispose() {
    _appearCtrl.dispose();
    super.dispose();
  }

  // **************************
  // Export-Dialog (clean)
  // **************************
  Future<void> _openExportDialogClean(BuildContext context) async {
    final w = MediaQuery.of(context).size.width;
    final isSmall = w < 430;

    if (isSmall) {
      // BottomSheet: passt sich Höhe an, vertikal scrollbar → keine Überläufer
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: zw.ZenGlassCard(
                    topOpacity: .24,
                    bottomOpacity: .10,
                    borderOpacity: .16,
                    borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: AnonExportWidget(
                        moodEntries: widget.moodEntries,
                        reflectionEntries: widget.reflectionEntries,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    // Dialog mit MaxBreite + Scroll → keine Überläufer
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0)),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: SingleChildScrollView(
                child: AnonExportWidget(
                  moodEntries: widget.moodEntries,
                  reflectionEntries: widget.reflectionEntries,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Zentraler Settings-Opener (für Bubble & Fallback)
  void _openProSettings() {
    if (widget.onOpenSettings != null) {
      widget.onOpenSettings!.call();
    } else {
      _openZenSettingsSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 470;
    final isNarrow200 = size.width <= 200; // ← neue Schwelle
    final isPhoneTall = size.height > 720;

    // ---- Provider (optional) -------------------------------------------------
    final prov = context.watch<JournalEntriesProvider?>();
    final hasProv = prov != null;

    // Serie & Kennzahlen
    final series = hasProv
        ? _seriesFromProvider(prov!, days: _range.days)
        : _fallbackSeriesFromMoodEntries(widget.moodEntries)
            .takeLast(_range.days);

    final avgMood = hasProv
        ? _averageMoodFromProvider(prov!, window: Duration(days: _range.days))
        : _fallbackAvgMoodFromMoodEntries(widget.moodEntries,
            days: _range.days);

    final reflectionsCount =
        hasProv ? prov!.reflections.length : widget.reflectionEntries.length;

    final activeDays = hasProv
        ? _activeDaysCountFromProvider(prov!)
        : widget.moodEntries.map((e) => e.dayTag).toSet().length;

    final streak = hasProv
        ? _streakFromProvider(prov!)
        : _streakFromLegacy(widget.moodEntries);

    final last7MoodLegacy = widget.moodEntries.takeLast(7);
    final last7FromSeries = series.takeLast(7);

    final showMoodGraph =
        (series.length >= 4) && !isNarrow200 && size.width > 0 && size.height > 0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      // AppBar: nur Back (Zahnrad ist jetzt in der Range-Bubble)
      appBar: const zw.ZenAppBar(
        title: null,
        showBack: true,
      ),
      body: Stack(
        children: [
          // 0) Einheitlicher Backdrop (extra milchig)
          const Positioned.fill(
            child: zw.ZenBackdrop(
              asset: 'assets/pro_screen.png',
              alignment: Alignment.center,
              glow: .38,
              vignette: .14,
              enableHaze: true,
              hazeStrength: .18,
              saturation: .92,
              wash: .12,
            ),
          ),

          // 1) Inhalt
          FadeTransition(
            opacity: _appearCtrl
                .drive(Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic))),
            child: SlideTransition(
              position: _appearCtrl
                  .drive(Tween(begin: const Offset(0, .02), end: Offset.zero)
                      .chain(CurveTween(curve: Curves.easeOutCubic))),
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 20,
                    vertical: isMobile ? 20 : 36,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Panda & Titel
                        Column(
                          children: [
                            AnimatedPandaGlow(size: isMobile ? 88 : 112),
                            const SizedBox(height: 6),
                            Text(
                              'Deine Reise',
                              textAlign: TextAlign.center,
                              style: tt.headlineMedium!.copyWith(
                                fontSize: 28,
                                color: zs.ZenColors.deepSage,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.1,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.black.withValue(alpha: .08),
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Opacity(
                              opacity: 0.92,
                              child: Text(
                                _randomMantra(reflectionsCount),
                                textAlign: TextAlign.center,
                                style: tt.bodySmall!.copyWith(
                                  fontSize: 14.5,
                                  fontStyle: FontStyle.italic,
                                  color: zs.ZenColors.sage,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),

                        // Range Switcher + Zahnrad rechts
                        _RangeBubble(
                          range: _range,
                          onChange: (r) => setState(() => _range = r),
                          isMobile: isMobile,
                          onOpenSettings: _openProSettings,
                        ),

                        const SizedBox(height: 12),

                        // Mood-Trend
                        ClipRRect(
                          borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: zw.ZenGlassCard(
                              padding: EdgeInsets.symmetric(
                                horizontal: isNarrow200 ? 14 : 20,
                                vertical: isNarrow200 ? 12 : 16,
                              ),
                              topOpacity: .26,
                              bottomOpacity: .10,
                              borderOpacity: .18,
                              borderRadius:
                                  const BorderRadius.all(zs.ZenRadii.l),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                          Icons.stacked_line_chart_rounded,
                                          size: 18,
                                          color: zs.ZenColors.jadeMid),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Stimmung – letzte ${_range.label} Tage',
                                        style: tt.bodyMedium!.copyWith(
                                          color: zs.ZenColors.deepSage,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (series.isNotEmpty)
                                    (showMoodGraph
                                        ? ZenMoodGraphSeries(series: series)
                                        : (last7FromSeries.isNotEmpty
                                            ? _ZenMoodBarSeries(
                                                last7: last7FromSeries)
                                            : _ZenMoodBar(
                                                last7: last7MoodLegacy)))
                                  else
                                    const _EmptyRowHint(
                                      icon: Icons.data_thresholding_rounded,
                                      text:
                                          'Noch keine Daten in diesem Zeitraum.',
                                    ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Ø Stimmung: ${avgMood.toStringAsFixed(2)}',
                                      style: tt.bodyMedium!.copyWith(
                                        color: zs.ZenColors.deepSage,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Statistiken
                        Semantics(
                          label: 'Statistiken',
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: zw.ZenGlassCard(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 10),
                                topOpacity: .24,
                                bottomOpacity: .10,
                                borderOpacity: .16,
                                borderRadius:
                                    const BorderRadius.all(zs.ZenRadii.l),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _ProStatTile(
                                      label: 'Reflexionen',
                                      value: '$reflectionsCount',
                                      icon: Icons.psychology_alt_rounded,
                                    ),
                                    const _vSep(),
                                    _ProStatTile(
                                      label: 'Aktive Tage',
                                      value: '$activeDays',
                                      icon: Icons.calendar_today_rounded,
                                    ),
                                    const _vSep(),
                                    _ProStatTile(
                                      label: 'Streak',
                                      value: '$streak',
                                      icon: Icons.local_fire_department_rounded,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Live-Werte für Stats nachtragen (separater Build pass)
                        Builder(builder: (context) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 0),
                            child: IgnorePointer(
                              ignoring: true,
                              child: Opacity(
                                opacity: 0.0,
                                child: Text(
                                    '$reflectionsCount $activeDays $streak'),
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 16),

                        // Community — „Panda hat mir geholfen“ (anonym)
                        ClipRRect(
                          borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: zw.ZenGlassCard(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              topOpacity: .24,
                              bottomOpacity: .10,
                              borderOpacity: .16,
                              borderRadius:
                                  const BorderRadius.all(zs.ZenRadii.l),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.favorite_rounded,
                                          size: 18, color: zs.ZenColors.jade),
                                      const SizedBox(width: 8),
                                      Text(
                                        'So vielen Menschen hat Panda geholfen',
                                        style: tt.bodyMedium!.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: zs.ZenColors.deepSage,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    switchInCurve: Curves.easeOutBack,
                                    child: _communityLoading
                                        ? const _CountSkeleton()
                                        : Text(
                                            _communityHelpCount == null
                                                ? '— — —'
                                                : _communityHelpCount!
                                                    .toString(),
                                            key: ValueKey(_communityHelpCount),
                                            style: tt.headlineSmall?.copyWith(
                                              color: zs.ZenColors.deepSage,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 10),
                                  _CommunityAckButton(
                                    busy: _sendingAck,
                                    done: _ackSentThisSession,
                                    onPressed: _sendHelpAck,
                                  ),
                                  const SizedBox(height: 8),
                                  Opacity(
                                    opacity: .78,
                                    child: Text(
                                      'Anonym & ohne Inhalte. Nur ein stilles Zeichen.',
                                      textAlign: TextAlign.center,
                                      style: tt.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Community – „Gespräche mit Panda (gesamt)“
                        ClipRRect(
                          borderRadius: const BorderRadius.all(zs.ZenRadii.l),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: zw.ZenGlassCard(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              topOpacity: .20,
                              bottomOpacity: .08,
                              borderOpacity: .14,
                              borderRadius:
                                  const BorderRadius.all(zs.ZenRadii.l),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.chat_bubble_rounded,
                                          size: 16, color: zs.ZenColors.sage),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Gespräche mit Panda (gesamt)',
                                        style: tt.bodyMedium!.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: zs.ZenColors.deepSage,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    switchInCurve: Curves.easeOutBack,
                                    child: _talkLoading
                                        ? const _CountSkeleton()
                                        : Text(
                                            _talkCount == null
                                                ? '— — —'
                                                : _talkCount!.toString(),
                                            key: ValueKey(_talkCount),
                                            style: tt.titleLarge?.copyWith(
                                              color: zs.ZenColors.deepSage,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 6),
                                  Opacity(
                                    opacity: .78,
                                    child: Text(
                                      'Nur ein Aggregat. Keine Inhalte, keine IDs.',
                                      textAlign: TextAlign.center,
                                      style: tt.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Export-Bereich
                        ClipRRect(
                          borderRadius: const BorderRadius.all(zs.ZenRadii.m),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: zw.ZenGlassCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              topOpacity: .22,
                              bottomOpacity: .10,
                              borderOpacity: .14,
                              borderRadius:
                                  const BorderRadius.all(zs.ZenRadii.m),
                              child: Column(
                                children: [
                                  Text(
                                    'Monatsdaten exportieren',
                                    textAlign: TextAlign.center,
                                    style: tt.titleMedium!.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: zs.ZenColors.sage,
                                      fontSize: isMobile ? 15.1 : 15.9,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _ProExportCircleButton(
                                        icon: Icons.picture_as_pdf_rounded,
                                        label: 'PDF',
                                        semanticsLabel:
                                            'Monatsdaten exportieren',
                                        onTap: () async {
                                          try {
                                            await _openExportDialogClean(
                                                context);
                                          } catch (_) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Export nicht möglich. Bitte später erneut versuchen.',
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 18),
                                      _ProExportCircleButton(
                                        icon: Icons.grid_on_rounded,
                                        label: 'CSV',
                                        semanticsLabel:
                                            'Monatsdaten als CSV exportieren',
                                        onTap: () {
                                          try {
                                            AnonExportWidget.exportAsCSV(
                                              context,
                                              widget.moodEntries,
                                            );
                                          } catch (_) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'CSV-Export nicht möglich. Bitte später erneut versuchen.',
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Opacity(
                                    opacity: .85,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _privacyRow(
                                            'Daten bleiben lokal & anonym', tt),
                                        _privacyRow(
                                            'Export jederzeit möglich', tt),
                                        _privacyRow(
                                            'Deine Reflexionen gehören nur dir',
                                            tt),
                                        _privacyRow(
                                            'Keine Werbung, maximale Kontrolle',
                                            tt),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Affirmation
                        if (isPhoneTall) const SizedBox(height: 6),
                        Opacity(
                          opacity: 0.96,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.spa_rounded,
                                  color: zs.ZenColors.sage, size: 21),
                              const SizedBox(width: 7),
                              Text(
                                'Du darfst einfach da sein.',
                                style: tt.bodyMedium!.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: zs.ZenColors.deepSage,
                                  fontSize: isMobile ? 14.1 : 15.2,
                                  letterSpacing: 0.02,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('🤍',
                                  style: TextStyle(fontSize: 16.5)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _randomMantra(int idx) {
    const lines = [
      'Du darfst einfach da sein.',
      'Zeit hat keine Eile.',
      'Heute genügt.',
      'Hier ist Raum für dich.',
      'Alles darf sein, wie es ist.',
      'Atme. Mehr braucht es nicht.',
      'Sanft ist stark genug.',
      'Kleine Wellen, stilles Wasser.',
      'Dein Tempo ist willkommen.',
    ];
    return lines[idx % lines.length];
  }
}

// ---------- Settings-Sheet Inhalt --------------------------------------------

class _SettingsContent extends StatefulWidget {
  final bool isBusy;
  final _MemoryMode? currentMode;
  final Future<void> Function(_MemoryMode) onSelectMode; // async safe
  final bool darkModeValue;
  final ValueChanged<bool> onDarkModeChanged;

  const _SettingsContent({
    required this.isBusy,
    required this.currentMode,
    required this.onSelectMode,
    required this.darkModeValue,
    required this.onDarkModeChanged,
  });

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  late _MemoryMode _mode = widget.currentMode ?? _MemoryMode.light;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _SettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentMode != null && widget.currentMode != _mode) {
      _mode = widget.currentMode!;
    }
  }

  Future<void> _setMode(_MemoryMode m) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSelectMode(m);
      if (mounted) setState(() => _mode = m);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isBusy = widget.isBusy || _saving;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.settings_rounded,
                color: zs.ZenColors.deepSage, size: 20),
            const SizedBox(width: 8),
            Text('Einstellungen',
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: zs.ZenColors.deepSage,
                )),
            const Spacer(),
            if (isBusy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Panda-Gedächtnis
        const _ZenSectionHeader(
            icon: Icons.memory_rounded, text: 'Panda-Gedächtnis'),
        const SizedBox(height: 8),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MemoryCard(
              title: 'Aus',
              subtitle: 'Ohne Erinnerungen.\nNichts wird gespeichert.',
              icon: Icons.block,
              selected: _mode == _MemoryMode.off,
              onTap: () => _setMode(_MemoryMode.off),
            ),
            _MemoryCard(
              title: 'Leicht',
              subtitle: 'On-Device-Gedächtnis.\nKein Teilen mit Panda.',
              icon: Icons.eco_rounded,
              selected: _mode == _MemoryMode.light,
              onTap: () => _setMode(_MemoryMode.light),
            ),
            _MemoryCard(
              title: 'Voll',
              subtitle: 'Panda mit Notizbuch.\nKontext teilen (opt-in).',
              icon: Icons.menu_book_rounded,
              selected: _mode == _MemoryMode.full,
              onTap: () => _setMode(_MemoryMode.full),
            ),
          ],
        ),

        const SizedBox(height: 8),
        Opacity(
          opacity: .85,
          child: Text(
            'Ghost-Mode ist Standard: Inhalte bleiben auf deinem Gerät. '
            'Bei „Voll“ teilt Panda nur kuratierten Kontext – nie Rohtexte.',
            style: tt.bodySmall,
          ),
        ),

        const SizedBox(height: 16),
        const _ZenSectionHeader(
            icon: Icons.brightness_4_rounded, text: 'Darstellung'),
        const SizedBox(height: 6),
        _ZenSwitchTile(
          title: 'Dunkles Design',
          subtitle: 'Sanft für die Augen – Oxford-Zen bei Nacht.',
          value: widget.darkModeValue,
          onChanged: (v) => widget.onDarkModeChanged(v),
        ),
      ],
    );
  }
}

// Oxford-Zen Memory Card
class _MemoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MemoryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bg = selected
        ? zs.ZenColors.deepSage.withValue(alpha: .14)
        : Colors.white.withValue(alpha: .10);
    final border = selected
        ? zs.ZenColors.deepSage.withValue(alpha: .42)
        : Colors.black.withValue(alpha: .12);
    final shadow = selected
        ? [
            BoxShadow(
              color: zs.ZenColors.deepSage.withValue(alpha: .12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ]
        : <BoxShadow>[];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        constraints: const BoxConstraints(minWidth: 170),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
          boxShadow: shadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: zs.ZenColors.sage.withValue(alpha: .18),
              child: Icon(icon, size: 18, color: zs.ZenColors.deepSage),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: zs.ZenColors.deepSage,
                      )),
                  const SizedBox(height: 2),
                  Opacity(
                    opacity: .85,
                    child: Text(
                      subtitle,
                      style: tt.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selected)
              const Icon(Icons.check_rounded,
                  size: 18, color: zs.ZenColors.deepSage),
          ],
        ),
      ),
    );
  }
}

// ---------- Widgets: Range ---------------------------------------------------

class _RangeBubble extends StatelessWidget {
  final _Range range;
  final ValueChanged<_Range> onChange;
  final bool isMobile;
  final VoidCallback? onOpenSettings;

  const _RangeBubble({
    required this.range,
    required this.onChange,
    required this.isMobile,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: const BorderRadius.all(zs.ZenRadii.s),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: zw.ZenGlassCard(
          topOpacity: .18,
          bottomOpacity: .08,
          borderOpacity: .12,
          borderRadius: const BorderRadius.all(zs.ZenRadii.s),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              // zentrierter Block mit den Chips (+ optionalem Text)
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RangeChip(
                      label: '7 Tage',
                      selected: range == _Range.d7,
                      onTap: () => onChange(_Range.d7),
                    ),
                    const SizedBox(width: 6),
                    _RangeChip(
                      label: '30 Tage',
                      selected: range == _Range.d30,
                      onTap: () => onChange(_Range.d30),
                    ),
                    const SizedBox(width: 6),
                    _RangeChip(
                      label: '90 Tage',
                      selected: range == _Range.d90,
                      onTap: () => onChange(_Range.d90),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 10),
                      Opacity(
                        opacity: .75,
                        child: Text('Ansicht verfeinern', style: tt.bodySmall),
                      ),
                    ],
                  ],
                ),
              ),
              // Zahnrad rechts (wie markiert)
              SizedBox(
                height: 28,
                width: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  tooltip: 'Einstellungen',
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? zs.ZenColors.deepSage.withValue(alpha: .15)
        : Colors.white.withValue(alpha: .12);
    final border = selected
        ? zs.ZenColors.deepSage.withValue(alpha: .40)
        : Colors.black.withValue(alpha: .14);
    final fg = selected ? zs.ZenColors.deepSage : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: border),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: zs.ZenColors.deepSage.withValue(alpha: .10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Row(
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded,
                  size: 14, color: zs.ZenColors.deepSage),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.8,
              ).copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Widgets: Community ----------------------------------------------

class _CommunityAckButton extends StatelessWidget {
  final bool busy;
  final bool done;
  final VoidCallback onPressed;

  const _CommunityAckButton({
    required this.busy,
    required this.done,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: busy || done ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.volunteer_activism_rounded),
        label: Text(
          done ? 'Danke – gezählt' : 'Ja, teilen (anonym)',
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CountSkeleton extends StatelessWidget {
  const _CountSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.black.withValue(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

// ---------- Widgets: Settings-Fallback Helpers -------------------------------

class _ZenSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ZenSwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValue(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValue(alpha: .08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: zs.ZenColors.deepSage,
                    )),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Opacity(
                    opacity: .80,
                    child: Text(subtitle!, style: tt.bodySmall),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ZenSectionHeader extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ZenSectionHeader({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: zs.ZenColors.sage),
        const SizedBox(width: 8),
        Text(
          text,
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: zs.ZenColors.deepSage,
          ),
        ),
      ],
    );
  }
}

// ---------- Widgets: Misc ----------------------------------------------------

class _EmptyRowHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyRowHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Opacity(
        opacity: .85,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.black54),
            const SizedBox(width: 6),
            Text(text, style: tt.bodySmall),
          ],
        ),
      ),
    );
  }
}

class AnimatedPandaGlow extends StatefulWidget {
  final double size;
  const AnimatedPandaGlow({this.size = 68, super.key});

  @override
  State<AnimatedPandaGlow> createState() => _AnimatedPandaGlowState();
}

class _AnimatedPandaGlowState extends State<AnimatedPandaGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(top: 16, bottom: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: zs.ZenColors.deepSage
                  .withValue(alpha: 0.10 + 0.17 * _glowController.value),
              blurRadius: 30 + 16 * _glowController.value,
              spreadRadius: 4 + 5 * _glowController.value,
            ),
          ],
        ),
        child: Image.asset(
          'assets/star_pa.png',
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.pets, color: zs.ZenColors.deepSage, size: 42),
        ),
      ),
    );
  }
}

// MoodBar für kleine Screens (Legacy-Fallback)
class _ZenMoodBar extends StatelessWidget {
  final List<MoodEntry> last7;
  const _ZenMoodBar({required this.last7});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final e = i < last7.length ? last7[i] : null;
        final Color barColor = e == null
            ? Colors.grey.withValue(alpha: 0.30)
            : e.color.withValue(alpha: 0.96);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 18 + (e?.moodScore ?? 1) * 5.0,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: (e?.color ?? Colors.grey).withValue(alpha: 0.10),
                blurRadius: 9,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: (e?.color ?? Colors.grey).withValue(alpha: 0.35),
              width: 1.1,
            ),
          ),
        );
      }),
    );
  }
}

// Alternative MoodBar für Provider-Serie (−2..+2) für kleine Screens
class _ZenMoodBarSeries extends StatelessWidget {
  final List<double> last7; // −2..+2
  const _ZenMoodBarSeries({required this.last7});

  @override
  Widget build(BuildContext context) {
    // Normiere −2..+2 → 0..4 für die gleiche Visualhöhe
    final norm = last7.map((v) => (v + 2.0).clamp(0.0, 4.0)).toList(); // 0..4
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final double? val = i < norm.length ? norm[i] : null;
        final base = val ?? 1.0;
        final color = val == null
            ? Colors.grey.withValue(alpha: 0.30)
            : (base >= 3.0
                ? zs.ZenColors.deepSage
                : (base >= 2.0 ? zs.ZenColors.sage : Colors.grey));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 18 + base * 5.0,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValue(alpha: 0.96),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: color.withValue(alpha: 0.10),
                blurRadius: 9,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: color.withValue(alpha: 0.35),
              width: 1.1,
            ),
          ),
        );
      }),
    );
  }
}

// MoodGraph (fl_chart) – Provider-Serie (−2 … +2) in Glas-Bubble
class ZenMoodGraphSeries extends StatelessWidget {
  final List<double> series; // −2 … +2; ältestes → neuestes
  const ZenMoodGraphSeries({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final data = series.takeLast(90);
    if (data.isEmpty) return const SizedBox(height: 124);

    // Glatte Tageslinie + 7-Tage-Average
    final smoothed = _smooth(data, strength: 0.35);
    final avg7 = _movingAverage(data, 7);

    return SizedBox(
      height: 124,
      child: LineChart(
        LineChartData(
          minY: -2,
          maxY: 2,
          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            drawVerticalLine: false,
            checkToShowHorizontalLine: (value) =>
                value == -1 || value == 0 || value == 1,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) {
              final isZero = value.abs() < 0.001;
              return FlLine(
                color: isZero
                    ? Colors.black.withValue(alpha: .12)
                    : Colors.black.withValue(alpha: .07),
                strokeWidth: isZero ? 1.2 : 0.9,
              );
            },
          ),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((t) => LineTooltipItem(
                        'Stimmung: ${t.y.toStringAsFixed(2)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                  avg7.length, (i) => FlSpot(i.toDouble(), avg7[i])),
              isCurved: true,
              color: zs.ZenColors.sage,
              barWidth: 3.4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
            LineChartBarData(
              spots: List.generate(
                  smoothed.length, (i) => FlSpot(i.toDouble(), smoothed[i])),
              isCurved: true,
              color: zs.ZenColors.deepSage,
              barWidth: 3.8,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  static List<double> _smooth(List<double> d, {double strength = 0.3}) {
    if (d.isEmpty) return const [];
    final s = <double>[];
    double prev = d.first;
    for (final v in d) {
      prev = prev + (v - prev) * (0.2 + strength * 0.6);
      s.add(prev.clamp(-2.0, 2.0));
    }
    return s;
  }

  static List<double> _movingAverage(List<double> d, int window) {
    if (d.isEmpty || window <= 1) return List<double>.from(d);
    final out = <double>[];
    double sum = 0;
    int start = 0;
    for (int i = 0; i < d.length; i++) {
      sum += d[i];
      if (i - start + 1 > window) {
        sum -= d[start];
        start++;
      }
      final len = (i - start + 1);
      out.add((sum / len).clamp(-2.0, 2.0));
    }
    return out;
  }
}

// vertikale Trennlinie
class _vSep extends StatelessWidget {
  const _vSep();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1.6,
      height: 37,
      color: zs.ZenColors.sage.withValue(alpha: 0.18),
    );
  }
}

// Statistik-Kachel
class _ProStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ProStatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: zs.ZenColors.sage.withValue(alpha: .18),
          radius: 20.5,
          child: Icon(icon, color: zs.ZenColors.sage, size: 20.5),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: tt.bodyMedium!.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2.5),
        Text(
          label,
          style: tt.bodySmall!.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

// Export-Button als Zen-Kreis (mit A11y/Tooltips)
class _ProExportCircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback onTap;

  const _ProExportCircleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      child: Column(
        children: [
          Tooltip(
            message: label,
            child: GestureDetector(
              onTap: onTap,
              child: CircleAvatar(
                backgroundColor: zs.ZenColors.deepSage,
                radius: 19.5,
                child: Icon(icon, color: Colors.white, size: 18.5),
              ),
            ),
          ),
          const SizedBox(width: 0, height: 3.5),
          Text(
            label,
            style: tt.bodySmall!.copyWith(
              fontWeight: FontWeight.w600,
              color: zs.ZenColors.sage,
            ),
          ),
        ],
      ),
    );
  }
}

// kleine Helferzeile für Datenschutz-Hinweise
Widget _privacyRow(String text, TextTheme tt) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded,
              size: 14, color: zs.ZenColors.sage),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: tt.bodySmall)),
        ],
      ),
    );

// takeLast-Extension
extension ListTakeLast<T> on List<T> {
  List<T> takeLast(int count) =>
      skip(length > count ? length - count : 0).toList();
}

// ---- Helper zur Provider-Analyse -------------------------------------------

const Map<String, double> _moodScoreMap = {
  'glücklich': 2.0,
  'ruhig': 1.0,
  'neutral': 0.0,
  'traurig': -1.0,
  'gestresst': -1.0,
  'wütend': -2.0,
};

double? _scoreFromTags(List<String> tags) {
  for (final t in tags) {
    final s = t.trim();
    if (s.startsWith('moodScore:')) {
      final n = int.tryParse(s.substring(10));
      if (n != null) return (n.clamp(0, 4) * 1.0) - 2.0;
    }
  }
  for (final t in tags) {
    final s = t.trim();
    if (s.startsWith('mood:')) {
      final key = s.substring(5).trim().toLowerCase();
      final v = _moodScoreMap[key];
      if (v != null) return v;
    }
  }
  return null;
}

List<double> _seriesFromProvider(JournalEntriesProvider prov,
    {required int days}) {
  if (prov.entries.isEmpty) return const [];

  final now = DateTime.now().toUtc();
  final start = now.subtract(Duration(days: days));
  final byDay = <String, List<double>>{};

  for (final e in prov.entries) {
    final t = e.createdAt.toUtc();
    if (t.isBefore(start)) continue; // robust gegen unsortierte Quellen
    final score = _scoreFromTags(e.tags);
    if (score == null) continue;
    final key =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    (byDay[key] ??= <double>[]).add(score);
  }

  if (byDay.isEmpty) return const [];

  // nach Datum aufsteigend sortieren und Tagesmittel bilden
  final keys = byDay.keys.toList()..sort((a, b) => a.compareTo(b));
  return keys.map((k) {
    final list = byDay[k]!;
    final avg =
        list.isEmpty ? 0.0 : (list.reduce((a, b) => a + b) / list.length);
    return avg.clamp(-2.0, 2.0);
  }).toList();
}

double _averageMoodFromProvider(JournalEntriesProvider prov,
    {Duration window = const Duration(days: 30)}) {
  if (prov.entries.isEmpty) return 0.0;
  final now = DateTime.now().toUtc();
  final start = now.subtract(window);
  final vals = <double>[];

  for (final e in prov.entries) {
    final t = e.createdAt.toUtc();
    if (t.isBefore(start)) continue;
    final score = _scoreFromTags(e.tags);
    if (score != null) vals.add(score);
  }
  if (vals.isEmpty) return 0.0;
  return vals.reduce((a, b) => a + b) / vals.length;
}

int _activeDaysCountFromProvider(JournalEntriesProvider prov) {
  final set = <String>{};
  for (final e in prov.entries) {
    final t = e.createdAt.toUtc();
    set.add('${t.year}-${t.month}-${t.day}');
  }
  return set.length;
}

// ---------- DayTag/Date Helfer ----------------------------------------------

String _toDayTag(DateTime dtUtc) => '${dtUtc.year}-${dtUtc.month}-${dtUtc.day}';

DateTime? _parseDayTag(String tag) {
  try {
    final parts = tag.split('-');
    if (parts.length != 3) return null;
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime.utc(y, m, d);
  } catch (_) {
    return null;
  }
}

// ---------- Streak & Fallback-Berechnungen ----------------------------------

int _streakFromProvider(JournalEntriesProvider prov) {
  // Sammle alle aktiven Tage als Tags
  final days = <String>{};
  for (final e in prov.entries) {
    final t = e.createdAt.toUtc();
    days.add(_toDayTag(t));
  }
  if (days.isEmpty) return 0;

  // Zähle von heute rückwärts, bis ein Tag fehlt
  int streak = 0;
  DateTime cursor = DateTime.now().toUtc();
  while (true) {
    final tag = _toDayTag(cursor);
    if (days.contains(tag)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

List<double> _fallbackSeriesFromMoodEntries(List<MoodEntry> list) {
  if (list.isEmpty) return const [];
  // Heuristik: Liste ist (meist) chronologisch; bilde tägliche Mittelwerte,
  // sofern dayTag verfügbar, sonst direkte Sequenzabbildung (ohne Datum).
  final byDay = <String, List<double>>{};
  final seq = <double>[];

  for (final e in list) {
    final score0to4 = (e.moodScore is num)
        ? (e.moodScore as num).toDouble().clamp(0, 4)
        : 2.0;
    final v = (score0to4 - 2.0).clamp(-2.0, 2.0); // → −2..+2
    final hasTag = (e.dayTag is String) && (e.dayTag as String).isNotEmpty;
    if (hasTag) {
      (byDay[e.dayTag as String] ??= <double>[]).add(v);
    } else {
      seq.add(v);
    }
  }

  if (byDay.isEmpty) {
    // Keine Tag-Infos → Sequenz direkt zurück
    return List<double>.from(seq);
  }

  // Mit Tag-Infos: nach Datum sortieren und Tagesmittel bilden
  final dated = <DateTime, double>{};
  for (final entry in byDay.entries) {
    final dt = _parseDayTag(entry.key);
    if (dt == null) continue;
    final vals = entry.value;
    final avg =
        vals.isEmpty ? 0.0 : (vals.reduce((a, b) => a + b) / vals.length);
    dated[dt] = avg.clamp(-2.0, 2.0);
  }
  final keys = dated.keys.toList()..sort((a, b) => a.compareTo(b));
  return keys.map((k) => dated[k]!).toList();
}

double _fallbackAvgMoodFromMoodEntries(List<MoodEntry> list, {int days = 30}) {
  if (list.isEmpty) return 0.0;

  // Wenn DayTags vorhanden, filtere letztes Fenster; sonst nimm die letzten N Einträge
  final now = DateTime.now().toUtc();
  final start = now.subtract(Duration(days: days));
  final vals = <double>[];

  final hasAnyTag =
      list.any((e) => (e.dayTag is String) && (e.dayTag as String).isNotEmpty);

  if (hasAnyTag) {
    for (final e in list) {
      final tag = (e.dayTag as String?) ?? '';
      final dt = _parseDayTag(tag);
      if (dt == null || dt.isBefore(start)) continue;
      final score0to4 = (e.moodScore is num)
          ? (e.moodScore as num).toDouble().clamp(0, 4)
          : 2.0;
      vals.add((score0to4 - 2.0).clamp(-2.0, 2.0));
    }
  } else {
    final slice = list.takeLast(days);
    for (final e in slice) {
      final score0to4 = (e.moodScore is num)
          ? (e.moodScore as num).toDouble().clamp(0, 4)
          : 2.0;
      vals.add((score0to4 - 2.0).clamp(-2.0, 2.0));
    }
  }

  if (vals.isEmpty) return 0.0;
  return vals.reduce((a, b) => a + b) / vals.length;
}

int _streakFromLegacy(List<MoodEntry> list) {
  if (list.isEmpty) return 0;

  // Nur DayTags verwenden; wenn keine vorhanden → minimaler Fallback.
  final set = <String>{};
  for (final e in list) {
    if (e.dayTag is String && (e.dayTag as String).isNotEmpty) {
      set.add(e.dayTag as String);
    }
  }
  if (set.isEmpty) {
    // Fallback ohne Datumsinfos: mindestens 1, wenn überhaupt Einträge
    return 1;
  }

  int streak = 0;
  DateTime cursor = DateTime.now().toUtc();
  while (true) {
    final tag = _toDayTag(cursor);
    if (set.contains(tag)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}
