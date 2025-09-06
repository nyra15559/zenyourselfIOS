// lib/features/story/story_view_screen.dart
//
// StoryViewScreen — Therapeutische Kurzgeschichte (Oxford-Zen, 3 klare Aktionen)
// -----------------------------------------------------------------------------
// Aktionen:
//   • Anhören/Stoppen  (TTS)      → onPlay / onStop
//   • Speichern                    → onSave
//   • Papierflieger (löschen)      → onDelete (mit Confirm)
// Entfernt: Kopieren, Export als Textdatei.
//
// Hinweis: TTS/Save/Delete sind via Callbacks entkoppelt, damit dein bestehendes
// System (Sound/TTS/Provider) ohne neue Abhängigkeiten weiter funktioniert.

import 'package:flutter/material.dart';
import '../../shared/zen_style.dart' as zs
    hide ZenBackdrop, ZenGlassCard, ZenAppBar;
import '../../shared/ui/zen_widgets.dart' as zw
    show ZenBackdrop, ZenGlassCard, ZenAppBar, PandaHeader, ZenToast;

class StoryViewScreen extends StatefulWidget {
  final String title;
  final String storyText;
  final DateTime createdAt;

  /// Optional Callbacks, um projektinterne Services zu nutzen.
  final Future<void> Function()? onPlay;
  final Future<void> Function()? onStop;
  final Future<void> Function()? onSave;
  final Future<void> Function()? onDelete;

  /// Startet der Screen bereits mit laufender Wiedergabe?
  final bool initiallyPlaying;

  const StoryViewScreen({
    Key? key,
    required this.title,
    required this.storyText,
    required this.createdAt,
    this.onPlay,
    this.onStop,
    this.onSave,
    this.onDelete,
    this.initiallyPlaying = false,
  }) : super(key: key);

  @override
  State<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends State<StoryViewScreen> {
  bool _isPlaying = false;
  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.initiallyPlaying;
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      if (widget.onStop != null) await widget.onStop!.call();
      setState(() => _isPlaying = false);
    } else {
      if (widget.onPlay != null) await widget.onPlay!.call();
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _save() async {
    if (widget.onSave == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave!.call();
      if (mounted) {
        zw.ZenToast.show(context, 'Gespeichert');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    if (widget.onDelete == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wegschicken?'),
        content: const Text(
          'Papierflieger loslassen und diesen Entwurf verwerfen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Wegschicken'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _isDeleting = true);
    try {
      await widget.onDelete!.call();
      if (mounted) {
        Navigator.of(context).maybePop();
        zw.ZenToast.show(context, 'Gesendet & verworfen');
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  String _humanTime(DateTime dt) {
    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final yesterday = now.subtract(const Duration(days: 1));

    final time = TimeOfDay.fromDateTime(dt);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');

    if (sameDay(dt, now)) return 'Heute, $hh:$mm';
    if (sameDay(dt, yesterday)) return 'Gestern, $hh:$mm';
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year}, $hh:$mm';
    }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: zw.ZenAppBar(
          title: 'Kurzgeschichte',
          actions: const [],
        ),
      ),
      body: Stack(
        children: [
          const zw.ZenBackdrop(),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                zw.PandaHeader(
                  title: widget.title,
                  subtitle: _humanTime(widget.createdAt),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: zw.ZenGlassCard(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                      child: SelectableText(
                        widget.storyText.trim(),
                        textAlign: TextAlign.left,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.35,
                        ),
                        cursorWidth: 2,
                        cursorRadius: const Radius.circular(2),
                        enableInteractiveSelection: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _ActionBar(
                      isPlaying: _isPlaying,
                      isSaving: _isSaving,
                      isDeleting: _isDeleting,
                      onTogglePlay: _togglePlay,
                      onSave: _save,
                      onDelete: _confirmDelete,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool isPlaying;
  final bool isSaving;
  final bool isDeleting;
  final VoidCallback onTogglePlay;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  const _ActionBar({
    Key? key,
    required this.isPlaying,
    required this.isSaving,
    required this.isDeleting,
    required this.onTogglePlay,
    required this.onSave,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final btnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isDeleting || isSaving ? null : onTogglePlay,
            icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            label: Text(isPlaying ? 'Stoppen' : 'Anhören'),
            style: ElevatedButton.styleFrom(
              shape: btnShape,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isDeleting || isPlaying ? null : onSave,
            icon: isSaving
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : const Icon(Icons.bookmark_add_outlined),
            label: Text(isSaving ? 'Sichern...' : 'Speichern'),
            style: OutlinedButton.styleFrom(
              shape: btnShape,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          onPressed: isDeleting ? null : onDelete,
          icon: isDeleting
              ? const SizedBox(
                  height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          tooltip: 'Papierflieger',
          style: IconButton.styleFrom(
            shape: btnShape,
            minimumSize: const Size(56, 48),
          ),
        ),
      ],
    );
  }
}
