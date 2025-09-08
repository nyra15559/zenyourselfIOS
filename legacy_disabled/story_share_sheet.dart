// lib/features/story/story_share_sheet.dart
//
// StoryShareSheet — Oxford Zen Pro
// ---------------------------------
// Zweck:
//  • Sanftes Bottom-Sheet zum Teilen/Exportieren einer erzeugten Story.
//  • Ohne neue Dependencies (Clipboard + unser BackupExportService).
//  • Optionen: In Zwischenablage kopieren, als JSON speichern, als GZip-JSON speichern,
//    Audio-Link kopieren (falls vorhanden).
//
// Integration:
//  • Aufrufen via: await StoryShareSheet.show(context, story: storyResult);
//  • Erwartet: StoryResult (aus guidance_service.dart).
//
// UX-Notizen:
//  • Konsistente Zen-Optik, klare Labels, Semantics, Haptik.
//  • Defensive Fehlerbehandlung, freundliche Snackbars.
//  • Kein Network-Download – wir speichern JSON (und optional gzipped JSON) lokal,
//    die konkrete Dateiausleitung übernimmt BackupExportService.
//
// Abhängigkeiten im Projekt:
//  • shared/zen_style.dart (Design Tokens)
//  • services/backup_export_service.dart (writeJson, writeGzip)
//  • services/guidance_service.dart (StoryResult mit toJson)

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/zen_style.dart';
import '../../services/backup_export_service.dart';
import '../../services/guidance_service.dart' show StoryResult;

class StoryShareSheet extends StatefulWidget {
  final StoryResult story;

  const StoryShareSheet({super.key, required this.story});

  /// Komfort: Sheet anzeigen
  static Future<void> show(
    BuildContext context, {
    required StoryResult story,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StoryShareSheet(story: story),
    );
  }

  @override
  State<StoryShareSheet> createState() => _StoryShareSheetState();
}

class _StoryShareSheetState extends State<StoryShareSheet> {
  bool _busy = false;

  StoryResult get _story => widget.story;

  @override
  Widget build(BuildContext context) {
    final bodyPreview = _story.body.trim().isEmpty
        ? '— (kein Inhalt) —'
        : _story.body.trim();

    return Stack(
      children: [
        // Click-through overlay für soften Blur/Dim
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(color: Colors.black.withValues(alpha: 0.18)),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.52,
          minChildSize: 0.42,
          maxChildSize: 0.92,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: ZenColors.surface,
                borderRadius: const BorderRadius.vertical(top: ZenRadii.xl),
                border: Border.all(color: ZenColors.border, width: 1),
                boxShadow: ZenShadows.sheet,
              ),
              padding: const EdgeInsets.fromLTRB(
                ZenSpacing.padBubble,
                10,
                ZenSpacing.padBubble,
                ZenSpacing.padBubble,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _dragHandle(),
                  const SizedBox(height: 4),
                  _header(),
                  const SizedBox(height: 10),
                  _storyPreview(bodyPreview, controller),
                  const SizedBox(height: 12),
                  _actionButtonsRow1(),
                  const SizedBox(height: 8),
                  _actionButtonsRow2(),
                  if (_story.audioUrl != null && _story.audioUrl!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _audioRow(),
                  ],
                  const SizedBox(height: 4),
                  _hintRow(),
                ],
              ),
            );
          },
        ),
        if (_busy)
          const Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: _BusyOverlay(),
            ),
          ),
      ],
    );
  }

  Widget _dragHandle() {
    return Center(
      child: Container(
        width: 36,
        height: 4.5,
        decoration: BoxDecoration(
          color: ZenColors.jadeMid.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Icon(Icons.auto_stories_rounded, color: ZenColors.jadeMid),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Story teilen & exportieren',
            style: ZenTextStyles.title.copyWith(
              fontWeight: FontWeight.w800,
              color: ZenColors.inkStrong,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Schließen',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded, color: ZenColors.jadeMid),
        ),
      ],
    );
  }

  Widget _storyPreview(String bodyPreview, ScrollController controller) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: ZenColors.surfaceAlt,
          borderRadius: const BorderRadius.all(ZenRadii.lg),
          border: Border.all(color: ZenColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(12),
        child: ListView(
          controller: controller,
          children: [
            Text(
              _story.title.trim().isEmpty ? 'Kurzgeschichte' : _story.title.trim(),
              style: ZenTextStyles.h3.copyWith(
                color: ZenColors.jade,
                fontSize: 18.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              bodyPreview,
              style: ZenTextStyles.body.copyWith(height: 1.35, fontSize: 15.5),
            ),
          ],
        ),
      ),
    );
  }

  // Row 1: In Zwischenablage kopieren / JSON in Clipboard
  Widget _actionButtonsRow1() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.content_copy_rounded),
            label: const Text('Text kopieren'),
            onPressed: _copyStoryText,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.data_object_rounded),
            label: const Text('JSON kopieren'),
            onPressed: _copyStoryJson,
          ),
        ),
      ],
    );
  }

  // Row 2: JSON speichern / GZip speichern
  Widget _actionButtonsRow2() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Als JSON speichern'),
            onPressed: _saveJson,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.archive_rounded),
            label: const Text('Als JSON (.gz)'),
            onPressed: _saveGzip,
          ),
        ),
      ],
    );
  }

  Widget _audioRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.audiotrack_rounded),
            label: const Text('Audio-Link kopieren'),
            onPressed: _copyAudioLink,
          ),
        ),
      ],
    );
  }

  Widget _hintRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'Hinweis: Dateien werden plattformspezifisch gespeichert. '
        'Der Speicherort wird vom Backup-Export-Service verwaltet.',
        style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ---------------------------
  // Actions
  // ---------------------------

  Future<void> _copyStoryText() async {
    HapticFeedback.selectionClick();
    try {
      final text = _formatPlainText(_story);
      await Clipboard.setData(ClipboardData(text: text));
      _toast('Story in die Zwischenablage kopiert');
    } catch (_) {
      _toast('Kopieren fehlgeschlagen.');
    }
  }

  Future<void> _copyStoryJson() async {
    HapticFeedback.selectionClick();
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(_story.toJson());
      await Clipboard.setData(ClipboardData(text: jsonStr));
      _toast('JSON in die Zwischenablage kopiert');
    } catch (_) {
      _toast('JSON konnte nicht erstellt werden.');
    }
  }

  Future<void> _saveJson() async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final name = _safeFileName('${_story.title.isEmpty ? "story" : _story.title}.json');
      await BackupExportService().writeJson(name, _story.toJson());
      _toast('JSON gespeichert');
    } catch (_) {
      _toast('Speichern fehlgeschlagen.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveGzip() async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final name = _safeFileName('${_story.title.isEmpty ? "story" : _story.title}.json.gz');
      await BackupExportService().writeGzip(name, _story.toJson());
      _toast('GZip-JSON gespeichert');
    } catch (_) {
      _toast('GZip-Speichern fehlgeschlagen.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _copyAudioLink() async {
    final url = _story.audioUrl?.trim();
    if (url == null || url.isEmpty) {
      _toast('Kein Audio-Link vorhanden.');
      return;
    }
    HapticFeedback.selectionClick();
    try {
      await Clipboard.setData(ClipboardData(text: url));
      _toast('Audio-Link kopiert');
    } catch (_) {
      _toast('Kopieren fehlgeschlagen.');
    }
  }

  // ---------------------------
  // Helpers
  // ---------------------------

  String _formatPlainText(StoryResult s) {
    final title = s.title.trim().isEmpty ? 'Kurzgeschichte' : s.title.trim();
    final body = s.body.trim();
    final audio = (s.audioUrl?.trim().isNotEmpty ?? false) ? '\n\nAudio: ${s.audioUrl!.trim()}' : '';
    return '$title\n\n$body$audio';
  }

  String _safeFileName(String raw) {
    // Entfernt problematische Zeichen und kürzt sanft.
    var name = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (name.isEmpty) name = 'story.json';
    if (name.length > 72) {
      final extIndex = name.lastIndexOf('.');
      if (extIndex > 0) {
        final base = name.substring(0, extIndex);
        final ext = name.substring(extIndex);
        final shortBase = base.substring(0, 60);
        name = '${shortBase}_$ext';
      } else {
        name = name.substring(0, 70);
      }
    }
    return name;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: .07),
      child: const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}
