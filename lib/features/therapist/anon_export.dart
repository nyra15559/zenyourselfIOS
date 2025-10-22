// lib/features/therapist/anon_export.dart
//
// AnonExportWidget — Oxford Calm & Privacy Edition (v2.2 · 2025-10-22)
// ---------------------------------------------------------------------
// • Export: CSV (Mood) / JSON (voll) / JSON (redacted) — nie UI-blockierend.
// • Redaction: entfernt Freitexte/Audio; Metrics basieren IMMER auf redacted.
// • ExportMetricsRedacted: counts, range, moodDist, topFacet, reflectionsIncluded.
// • Analytics-Hooks: export_started / export_succeeded / export_failed.
// • Memorystore: speichert „letzter Export“ (Zeit/Kanal/Top-Facet/Pfad).
// • Schweizer Disclaimer im UI (PrivacyTexts.chDisclaimerShort).
//
// Abhängigkeiten: path_provider, shared_preferences (bereits im Projekt vorhanden).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/zen_style.dart';
import '../../data/mood_entry.dart';
import '../../data/reflection_entry.dart';
import '../../core/privacy/privacy_texts.dart';

// ─────────────────────────────── Analytics (Hook) ──────────────────────────────
// Externe Integrationen können den Logger setzen: `AnonExportAnalytics.logger = ...;`
typedef _AnalyticsLogger = FutureOr<void> Function(
  String event,
  Map<String, Object?> params,
);

class AnonExportAnalytics {
  static _AnalyticsLogger logger = (_, __) {};
}

// ─────────────────────────────── Memorystore (SP) ─────────────────────────────
class _Memorystore {
  static const _ns = 'anonexport';
  static String _k(String k) => '$_ns::$k';

  static Future<void> saveLastExport({
    required String kind,
    required DateTime when,
    String? path,
    String? topFacet,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k('last_kind'), kind);
    await sp.setString(_k('last_when'), when.toIso8601String());
    if (path != null) await sp.setString(_k('last_path'), path);
    if (topFacet != null) await sp.setString(_k('last_top_facet'), topFacet);
  }

  static Future<Map<String, String?>> loadLastExport() async {
    final sp = await SharedPreferences.getInstance();
    return {
      'kind': sp.getString(_k('last_kind')),
      'when': sp.getString(_k('last_when')),
      'path': sp.getString(_k('last_path')),
      'topFacet': sp.getString(_k('last_top_facet')),
    };
  }
}

// ─────────────────────────────── Widget ───────────────────────────────────────
class AnonExportWidget extends StatefulWidget {
  final List<MoodEntry> moodEntries;
  final List<ReflectionEntry>? reflectionEntries;

  /// Optional: Start-Auswahl & Optionen preset’en (z. B. für "PDF"-Soft-Gate)
  final _ExportKind initialKind;
  final bool initialIncludeReflections;

  const AnonExportWidget({
    super.key,
    required this.moodEntries,
    this.reflectionEntries,
    this.initialKind = _ExportKind.csvMood,
    this.initialIncludeReflections = true,
  });

  /// Convenience: kleines Dialog-Sheet für CSV-Export
  static Future<void> exportAsCSV(
    BuildContext context,
    List<MoodEntry> moods,
  ) async {
    // soft, non-blocking UI
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: AnonExportWidget(
          moodEntries: moods,
          initialKind: _ExportKind.csvMood,
          initialIncludeReflections: false,
        ),
      ),
    );
  }

  /// Back-compat Shim für frühere API:
  /// Öffnet den Export-Dialog direkt im JSON-(redacted)-Modus.
  /// (Soft-Gate: PDF nativ ggf. später; Offline-Flows bleiben ungehindert.)
  static Future<void> exportAsPDF(
    BuildContext context,
    List<MoodEntry> moods, [
    List<ReflectionEntry>? reflections,
  ]) async {
    // Dialog öffnen mit JSON (red.) als Start – blockiert keine Flows
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: AnonExportWidget(
          moodEntries: moods,
          reflectionEntries: reflections,
          initialKind: _ExportKind.jsonRedacted,
          initialIncludeReflections: true,
        ),
      ),
    );

    // Freundlicher Hinweis (soft): „PDF direkt nicht verfügbar“
    // → Nutzer*in kann JSON/CSV exportieren oder später PDF nutzen.
    // keine harte Abhängigkeit, kein Blocker.
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'PDF-Export ist momentan nicht direkt verfügbar. '
          'Nutze JSON (red.) oder CSV – beides anonym & lokal.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  State<AnonExportWidget> createState() => _AnonExportWidgetState();
}

enum _ExportKind { csvMood, jsonFull, jsonRedacted }

class _AnonExportWidgetState extends State<AnonExportWidget> {
  bool _exporting = false;
  String? _exportMsg;
  late _ExportKind _kind;
  late bool _includeReflections; // nur relevant für JSON
  String? _lastPath;

  // letzte (redacted) Metrics für UI-Hinweis
  Map<String, Object?>? _lastMetrics;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _includeReflections = widget.initialIncludeReflections;
  }

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
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Exportiere deine Daten', style: ZenTextStyles.title),
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
                      activeThumbColor: ZenColors.jade,
                      onChanged: (v) => setState(() => _includeReflections = v),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
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
                    onPressed:
                        _exporting ? null : () => Navigator.of(context).maybePop(),
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
                        ? Colors.red.withValues(alpha: 0.08)
                        : ZenColors.bamboo.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _exportMsg!.startsWith('Fehler')
                          ? Colors.red.withValues(alpha: 0.32)
                          : ZenColors.bamboo.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _exportMsg!,
                    style: ZenTextStyles.body.copyWith(
                      color: _exportMsg!.startsWith('Fehler')
                          ? Colors.red.shade800
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

              if (_lastMetrics != null) ...[
                const SizedBox(height: 8),
                _MetricsInline(metrics: _lastMetrics!),
              ],

              const SizedBox(height: 8),
              Text(
                PrivacyTexts.chDisclaimerShort,
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
      setState(() {
        _exportMsg =
            'Fehler: Direkter Dateiexport im Web nicht verfügbar (nutze App/Desktop).';
        _lastPath = null;
      });
      return;
    }

    setState(() {
      _exporting = true;
      _exportMsg = null;
      _lastPath = null;
      _lastMetrics = null;
    });

    final now = DateTime.now();
    final kindLabel = _kind.name;

    try {
      // ---- Analytics: start
      await AnonExportAnalytics.logger('export_started', {
        'kind': kindLabel,
        'moods': widget.moodEntries.length,
        'reflections': widget.reflectionEntries?.length ?? 0,
        'ts': now.toIso8601String(),
      });

      // Vorbereitungen: serialisierbare Maps für compute
      final moodMaps = widget.moodEntries.map((e) => e.toJson()).toList();
      final reflMaps = (_includeReflections
              ? (widget.reflectionEntries ?? const <ReflectionEntry>[])
              : const <ReflectionEntry>[])
          .map((e) => e.toJson())
          .toList();

      late final File file;
      late Map<String, Object?> metrics;

      if (_kind == _ExportKind.csvMood) {
        final csv = await compute(_buildCsvString, moodMaps);
        file = await _saveFile(csv, _timestamped('zenyourself_mood', 'csv'));
        // Metrics (redacted) nur aus moods
        metrics = await compute(_buildRedactedMetrics, {
          'moods': moodMaps,
          'reflections': <Map<String, Object?>>[],
        });
      } else {
        final redacted = _kind == _ExportKind.jsonRedacted;

        final payload = await compute(_buildJsonPayload, {
          'moods': moodMaps,
          'reflections': reflMaps,
          'redacted': redacted,
        });
        final jsonStr = payload['json'] as String;
        metrics = payload['metrics'] as Map<String, Object?>;

        file = await _saveFile(jsonStr, _timestamped('zenyourself_export', 'json'));
      }

      final topFacet = (metrics['topFacet'] as Map?)?['label'] as String?;
      await _Memorystore.saveLastExport(
        kind: kindLabel,
        when: now,
        path: file.path,
        topFacet: topFacet,
      );

      if (mounted) {
        setState(() {
          _exportMsg = 'Export erfolgreich.';
          _lastPath = file.path;
          _lastMetrics = metrics;
        });
      }

      // ---- Analytics: success (nur redacted-Zusammenfassung)
      await AnonExportAnalytics.logger('export_succeeded', {
        'kind': kindLabel,
        'ts': DateTime.now().toIso8601String(),
        'metrics': metrics, // bereits redacted
      });
    } catch (e) {
      if (mounted) {
        setState(() => _exportMsg = 'Fehler beim Export: $e');
      }
      await AnonExportAnalytics.logger('export_failed', {
        'kind': kindLabel,
        'ts': DateTime.now().toIso8601String(),
        'error': e.toString().substring(0, e.toString().length.clamp(0, 240)),
      });
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
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
    return '${base}_$y$m${d}_$hh$mm$ss.$ext';
  }

  Future<File> _saveFile(String content, String filename) async {
    // Primär: App-Dokumentenordner (benutzerfreundlich)
    Directory? dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
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

// ─────────────────────────────── UI: Metrics Inline ───────────────────────────
class _MetricsInline extends StatelessWidget {
  final Map<String, Object?> metrics;
  const _MetricsInline({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final moods = metrics['moods'] as int? ?? 0;
    final refl = metrics['reflections'] as int? ?? 0;
    final tf = (metrics['topFacet'] as Map?)?['label'] as String?;
    final period = metrics['period'] as Map<String, Object?>?;
    final start = period?['start'] as String?;
    final end = period?['end'] as String?;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ZenColors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZenColors.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _kv('Einträge', '$moods Mood, $refl Refl'),
          if (tf != null) _kv('Top-Facette', tf),
          if (start != null && end != null) _kv('Zeitraum', '$start – $end'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k: ', style: ZenTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
          Text(v, style: ZenTextStyles.caption),
        ],
      );
}

// ─────────────────────────────── Isolate-Funktionen ───────────────────────────
// Alle Argumente/Rückgaben müssen JSON-serialisierbar (Map/List/primitive) sein.

String _csvEscape(String v) => '"${v.replaceAll('"', '""')}"';

String _buildCsvString(List<dynamic> moodMapsDyn) {
  // FIX: generics/typing (vorher >>> Tippfehler)
  final moods = List<Map<String, Object?>>.from(moodMapsDyn);
  final b = StringBuffer();
  b.writeln('Timestamp,DayTag,MoodScore,MoodLabel,Note,Extra');
  for (final e in moods) {
    b
      ..write(_csvEscape((e['timestamp'] ?? '').toString()))
      ..write(',')
      ..write(_csvEscape((e['dayTag'] ?? '').toString()))
      ..write(',')
      ..write((e['moodScore'] ?? '').toString())
      ..write(',')
      ..write(_csvEscape((e['moodLabel'] ?? '').toString()))
      ..write(',')
      ..write(_csvEscape((e['note'] ?? '').toString()))
      ..write(',')
      ..writeln(_csvEscape((e['extra'] ?? '').toString()));
  }
  return b.toString();
}

/// Baut JSON (evtl. redacted) + redacted Metrics.
Map<String, Object?> _buildJsonPayload(Map<String, Object?> args) {
  final List<Map<String, Object?>> moods =
      List<Map<String, Object?>>.from(args['moods'] as List);
  final List<Map<String, Object?>> refl =
      List<Map<String, Object?>>.from(args['reflections'] as List);
  final bool redacted = args['redacted'] == true;

  final List<Map<String, Object?>> redactedRefl =
      refl.map<Map<String, Object?>>(_redactReflectionMap).toList();

  final metrics = _buildRedactedMetrics({
    'moods': moods,
    'reflections': redactedRefl,
  });

  final payload = <String, Object?>{
    '_version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'exportMetricsRedacted': metrics,
    'moodEntries': moods,
    'reflections':
        redacted ? redactedRefl : refl, // aber: Metrics bleiben redacted
  };

  final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
  return {'json': jsonStr, 'metrics': metrics};
}

/// Entfernt PII-haltige Felder aus einer Reflection-Map.
Map<String, Object?> _redactReflectionMap(Map<String, Object?> r) {
  final copy = Map<String, Object?>.from(r);

  // Entferne verbreitete Freitext-/Audio-/Inhaltsfelder (ohne Fehlwurf)
  for (final k in [
    'content',
    'aiSummary',
    'userInput',
    'userResponse',
    'notes',
    'voiceFile',
    'audioPath',
    'transcript',
  ]) {
    copy.remove(k);
  }

  // Falls verschachtelte Strukturen PII enthalten:
  final meta = copy['metadata'];
  if (meta is Map) {
    final m = Map<String, Object?>.from(meta);
    for (final k in ['rawText', 'snippet', 'piiNotes']) {
      m.remove(k);
    }
    copy['metadata'] = m;
  }

  return copy;
}

/// Redacted-Metriken inkl. Top-Facet aus tags/facets.
Map<String, Object?> _buildRedactedMetrics(Map<String, Object?> args) {
  final List<Map<String, Object?>> moods =
      List<Map<String, Object?>>.from(args['moods'] as List);
  final List<Map<String, Object?>> refl =
      List<Map<String, Object?>>.from(args['reflections'] as List);

  // Zeitraum
  DateTime? minT, maxT;
  void accTs(String? iso) {
    if (iso == null || iso.isEmpty) return;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return;
    minT = (minT == null || dt.isBefore(minT!)) ? dt : minT;
    maxT = (maxT == null || dt.isAfter(maxT!)) ? dt : maxT;
  }

  for (final m in moods) accTs(m['timestamp']?.toString());
  for (final r in refl) accTs(r['timestamp']?.toString());

  // Mood-Verteilung
  final Map<String, int> moodDist = {};
  for (final m in moods) {
    final label = (m['moodLabel'] ?? '').toString();
    if (label.isEmpty) continue;
    moodDist[label] = (moodDist[label] ?? 0) + 1;
  }

  // Top-Facet aus Reflections (tags/facets/metadata.facets)
  final Map<String, int> facetCount = {};
  for (final r in refl) {
    void addAll(dynamic vals) {
      if (vals is List) {
        for (final v in vals) {
          final s = v?.toString().trim();
          if (s == null || s.isEmpty) continue;
          facetCount[s] = (facetCount[s] ?? 0) + 1;
        }
      }
    }

    if (r['tags'] != null) addAll(r['tags']);
    if (r['facets'] != null) addAll(r['facets']);

    final meta = r['metadata'];
    if (meta is Map && meta['facets'] != null) addAll(meta['facets']);
  }

  String? topFacetLabel;
  int topFacetCount = 0;
  facetCount.forEach((k, v) {
    if (v > topFacetCount) {
      topFacetCount = v;
      topFacetLabel = k;
    }
  });

  return {
    'moods': moods.length,
    'reflections': refl.length,
    'period': {
      'start': minT?.toIso8601String(),
      'end': maxT?.toIso8601String(),
    },
    'moodDistribution': moodDist,
    'topFacet': topFacetLabel == null
        ? null
        : {
            'label': topFacetLabel,
            'count': topFacetCount,
          },
  };
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
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => ZenColors.surface,
        ),
        foregroundColor: const WidgetStatePropertyAll(ZenColors.inkStrong),
      ),
    );
  }
}
