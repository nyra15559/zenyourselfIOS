// lib/features/therapist/anon_export.dart
//
// AnonExportWidget — Oxford Calm & Privacy Edition
// ------------------------------------------------
// • Lokaler, anonymer Export (CSV / JSON, optional redacted)
// • Robuste CSV-Escapes, Zeitstempel-Dateinamen, klares Status-Feedback
// • Keine zusätzlichen Dependencies (Share/Open sind bewusst optional)
// • UI im ZenYourself-Stil (ruhig, barrierearm)

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../shared/zen_style.dart';
import '../../data/mood_entry.dart';
import '../../data/reflection_entry.dart';

class AnonExportWidget extends StatefulWidget {
  final List<MoodEntry> moodEntries;
  final List<ReflectionEntry>? reflectionEntries;

  const AnonExportWidget({
    super.key,
    required this.moodEntries,
    this.reflectionEntries,
  });

  /// Convenience: CSV-Export als modales Dialogchen öffnen
  static Future<void> exportAsCSV(
    BuildContext context,
    List<MoodEntry> moods,
  ) async {
    final widget = AnonExportWidget(moodEntries: moods);
    // ignore: use_build_context_synchronously
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: widget,
      ),
    );
  }

  /// Platzhalter: Später PDF-Export via `pdf`-Package
  static Future<void> exportAsPDF(
    BuildContext context,
    List<MoodEntry> moods,
    List<ReflectionEntry> reflections,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF-Export ist in Entwicklung.')),
    );
  }

  @override
  State<AnonExportWidget> createState() => _AnonExportWidgetState();
}

enum _ExportKind { csvMood, jsonFull, jsonRedacted }

class _AnonExportWidgetState extends State<AnonExportWidget> {
  bool _exporting = false;
  String? _exportMsg;
  _ExportKind _kind = _ExportKind.csvMood;
  bool _includeReflections = true; // nur relevant für JSON
  String? _lastPath;

  @override
  Widget build(BuildContext context) {
    final hasReflections = (widget.reflectionEntries?.isNotEmpty ?? false);

    return Card(
      elevation: 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: ZenColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Exportiere deine Daten', style: ZenTextStyles.title),
              const SizedBox(height: 10),

              // Auswahl Exportart
              _ExportSelector(
                kind: _kind,
                onChanged: (k) => setState(() => _kind = k),
                hasReflections: hasReflections,
              ),

              // Option: Reflexionen einbeziehen (nur JSON)
              if (_kind != _ExportKind.csvMood && hasReflections) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Switch(
                      value: _includeReflections,
                      activeColor: ZenColors.jade,
                      onChanged: (v) => setState(() => _includeReflections = v),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Reflexionen einbeziehen',
                        style: ZenTextStyles.body,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Buttons
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: Text(_primaryLabel),
                    onPressed: _exporting ? null : _handleExport,
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Schließen'),
                    onPressed: _exporting ? null : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              if (_exporting) const LinearProgressIndicator(),

              if (_exportMsg != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _exportMsg!.startsWith('Fehler')
                        ? Colors.red.withOpacity(0.08)
                        : ZenColors.bamboo.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _exportMsg!.startsWith('Fehler')
                          ? Colors.red.withOpacity(0.32)
                          : ZenColors.bamboo.withOpacity(0.25),
                    ),
                  ),
                  child: Text(
                    _exportMsg!,
                    style: ZenTextStyles.body.copyWith(
                      color: _exportMsg!.startsWith('Fehler')
                          ? Colors.red[800]
                          : ZenColors.inkStrong,
                    ),
                  ),
                ),
              ],

              if (_lastPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Gespeichert unter:',
                  style: ZenTextStyles.caption.copyWith(color: ZenColors.inkSubtle),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _lastPath!,
                  style: ZenTextStyles.caption,
                ),
              ],

              const SizedBox(height: 8),
              Text(
                'Exportierte Dateien werden anonym und offline auf deinem Gerät gespeichert. '
                'Teilen ist optional — deine Privatsphäre bleibt geschützt.',
                style: ZenTextStyles.caption.copyWith(color: ZenColors.inkSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _primaryLabel {
    switch (_kind) {
      case _ExportKind.csvMood:
        return 'CSV (Stimmungen) exportieren';
      case _ExportKind.jsonFull:
        return 'JSON (vollständig) exportieren';
      case _ExportKind.jsonRedacted:
        return 'JSON (redacted) exportieren';
    }
  }

  Future<void> _handleExport() async {
    if (kIsWeb) {
      // Im Web exportieren wir hier bewusst nicht (kein Filesystem über path_provider).
      setState(() {
        _exportMsg = 'Fehler: Export im Web nicht verfügbar.';
        _lastPath = null;
      });
      return;
    }

    setState(() {
      _exporting = true;
      _exportMsg = null;
      _lastPath = null;
    });

    try {
      late final File file;

      if (_kind == _ExportKind.csvMood) {
        final csv = _moodEntriesToCSV(widget.moodEntries);
        file = await _saveFile(csv, _timestamped('zenyourself_mood', 'csv'));
      } else {
        final Map<String, dynamic> jsonData = {
          'moodEntries': widget.moodEntries.map((e) => e.toJson()).toList(),
        };

        if (_includeReflections && (widget.reflectionEntries?.isNotEmpty ?? false)) {
          final refl = widget.reflectionEntries!;
          if (_kind == _ExportKind.jsonRedacted) {
            jsonData['reflections'] = refl.map(_redactReflection).toList();
          } else {
            jsonData['reflections'] = refl.map((r) => r.toJson()).toList();
          }
        }

        final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonData);
        file = await _saveFile(jsonStr, _timestamped('zenyourself_export', 'json'));
      }

      if (!mounted) return;
      setState(() {
        _exportMsg = 'Export erfolgreich.';
        _lastPath = file.path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _exportMsg = 'Fehler beim Export: $e');
    } finally {
      if (!mounted) return;
      setState(() => _exporting = false);
    }
  }

  // ---------- Helpers ----------

  /// Zeitstempel-Dateiname, z. B. zenyourself_mood_2025{mm}{dd}_hhmmss.csv
  String _timestamped(String base, String ext) {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '${base}_${y}${m}${d}_$hh$mm$ss.$ext';
  }

  /// CSV robust quoten (RFC4180-ish): " -> "", Feld in Anführungszeichen.
  String _csvField(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  String _moodEntriesToCSV(List<MoodEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('Timestamp,DayTag,MoodScore,MoodLabel,Note,Extra');
    for (final e in entries) {
      buffer
        ..write(_csvField(e.timestamp.toIso8601String()))
        ..write(',')
        ..write(_csvField(e.dayTag))
        ..write(',')
        ..write(e.moodScore.toString())
        ..write(',')
        ..write(_csvField(e.moodLabel))
        ..write(',')
        ..write(_csvField(e.note ?? ''))
        ..write(',')
        ..writeln(_csvField(e.extra ?? ''));
    }
    return buffer.toString();
  }

  /// Reduziert ReflectionEntry auf PII-arme Metriken (keine Freitexte/Audio).
  Map<String, dynamic> _redactReflection(ReflectionEntry r) {
    final map = r.toJson();

    // Entferne potenziell sensible Inhalte:
    map.remove('content');     // gesamter Freitext/Q&A
    map.remove('aiSummary');   // KI-Zusammenfassung könnte PII enthalten
    map.remove('audioPath');   // Verweis auf lokale Datei
    // (Optional, falls alternative Keys existieren)
    map.remove('userInput');
    map.remove('userResponse');
    map.remove('voiceFile');

    // Belassen: timestamp, moodScore, moodDayTag, tags, category, source …
    return map;
  }

  Future<File> _saveFile(String content, String filename) async {
    // Primär: App-Dokumentenordner (benutzerfreundlich)
    Directory? dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      // Desktop: ggf. Downloads (kann null sein)
      try {
        // ignore: deprecated_member_use
        dir = await getDownloadsDirectory();
      } catch (_) {}
    }
    dir ??= await getTemporaryDirectory();

    final file = File('${dir.path}/$filename');
    await file.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }
}

// -------------------------------- UI-Subwidget: Export-Auswahl --------------------------------

class _ExportSelector extends StatelessWidget {
  final _ExportKind kind;
  final ValueChanged<_ExportKind> onChanged;
  final bool hasReflections;

  const _ExportSelector({
    required this.kind,
    required this.onChanged,
    required this.hasReflections,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_ExportKind>(
      segments: const [
        ButtonSegment(
          value: _ExportKind.csvMood,
          icon: Icon(Icons.table_chart_outlined),
          label: Text('CSV (Mood)'),
        ),
        ButtonSegment(
          value: _ExportKind.jsonFull,
          icon: Icon(Icons.code_rounded),
          label: Text('JSON'),
        ),
        ButtonSegment(
          value: _ExportKind.jsonRedacted,
          icon: Icon(Icons.privacy_tip_outlined),
          label: Text('JSON (red.)'),
        ),
      ],
      selected: {kind},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith(
          (states) => ZenColors.surface, // kein surfaceAlt → build-safe
        ),
        foregroundColor: MaterialStateProperty.all(ZenColors.inkStrong),
      ),
    );
  }
}
