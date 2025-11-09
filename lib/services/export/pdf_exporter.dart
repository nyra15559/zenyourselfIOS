// [MERGE SIGNAL] lib/services/export/pdf_exporter.dart (Stand: 2025-11-08, v1.2.1+insights)
// ZenYourself — PII-sicherer PDF-Export (on-device), Oxford-Zen-Typografie
// -----------------------------------------------------------------------------
// Zweck
// • Erstellt lokal (on-device) eine ruhige, datenschutzfreundliche PDF
//   mit Monatsrückblick: Titel, Kennzahlen, Stimmungs-Überblick, (optional)
//   Kurzgeschichte, Timeline (letzte 5 Marker, 30 Tage) sowie Datenschutz-Hinweis.
// • Keine Netzaufrufe, keine Identifikatoren, keine Roh-Transkripte.
// • Oxford-Zen-Stil (dezente Farben, viel Luft, klare Typo).
//
// Public API
// • PdfExporter.exportMonthlyReport(...): erstellt eine PDF und gibt den
//   Dateipfad zurück. Optional mit StoryResult (Titel+Body), Privatsphäre-Modus,
//   und (neu) Timeline-Marker-Liste.
// • NEU: Optionaler Block „Erkenntnisse (Auszug)“ mit 3–5 Bullet-Points
//   (strict: stark gekürzt). Übergabe via `insightBullets`.
//
// Privacy
// • ExportPrivacy.open   → keine Redaktion (nur nutzen, wenn Nutzer klar zustimmt)
// • ExportPrivacy.redact → E-Mail/Telefon/URLs/IDs werden maskiert (Default)
// • ExportPrivacy.strict → kein Freitext außer stark gekürzten Auszügen;
//                          Story-Body & Erkenntnisse werden neutralisiert/komprimiert.
//
// Abhängigkeiten (pubspec):
//   pdf: ^3.11.3
//   path_provider: ^2.1.2
//
// Änderungen
// • v1.1.0+timeline: Timeline-Abschnitt (30 Tage, max. 5 Zeilen).
// • v1.2.0+insights: Block „Erkenntnisse (Auszug)“ (3–5 Bullets, strict=kompakt).
// • v1.2.1: Compile-Safety (Bullet.margin statt bulletMargin; TableBorder inside-Sides).
//
// -----------------------------------------------------------------------------
// Hinweise
// • Setze in pubspec.yaml geeignete Fonts als Assets (z. B. NotoSans Regular/Bold).
//   Fallback sind eingebaute Helvetica-Fonts.
// • Optional kann die aufrufende UI nach dem Export einen „Öffnen“/„Teilen“-
//   Schritt anbieten (nicht Bestandteil dieses Services).

library pdf_exporter;

import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Domain-Modelle (leicht genutzt, ohne Inhalte auszulesen)
import '../../data/mood_entry.dart';
import '../../data/reflection_entry.dart';
import '../guidance/dtos.dart'; // TimelineMarker, StoryResult

enum ExportPrivacy { open, redact, strict }

class PdfExporter {
  /// Erstellt einen PII-sicheren Monatsbericht und gibt den finalen Dateipfad zurück.
  static Future<String> exportMonthlyReport({
    required List<MoodEntry> moodEntries,
    required List<ReflectionEntry> reflectionEntries,
    StoryResult? story, // optional (Titel/Body). Body kann abhängig vom Privacy-Level gekürzt werden.
    required DateTime month, // beliebiges Datum im Zielmonat
    ExportPrivacy privacy = ExportPrivacy.redact,
    String? userDisplayName, // wird NICHT gedruckt (kein PII-Leak), dient nur Redaction-Heuristik
    // NEU: optionale Timeline-Marker (Client-seitig erzeugt)
    List<TimelineMarker>? timelineMarkers,
    // NEU: optionale Erkenntnisse (3–5 Bullet-Points; strict: stark gekürzt)
    List<String>? insightBullets,
  }) async {
    // 1) Daten vorsortieren / filtern auf Monat
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd =
        DateTime(month.year, month.month + 1, 1).subtract(const Duration(days: 1));

    final moodsInWindow =
        _filterMoodsByDayTagOrGuess(moodEntries, monthStart, monthEnd);
    final reflectionsCount =
        _countReflectionsByDate(reflectionEntries, monthStart, monthEnd);

    // Stimmungs-KPIs
    final moodStats = _computeMoodStats(moodsInWindow);

    // 30-Tage-Zeitraum für Timeline (endet am Monatsende)
    final thirtyStart = monthEnd.subtract(const Duration(days: 29));

    // Timeline-Zeilen vorbereiten
    final timelineRows = _buildTimelineRows(
      markers: timelineMarkers,
      moods: moodEntries,
      windowStart: thirtyStart,
      windowEnd: monthEnd,
      redactName: userDisplayName,
    );

    // Erkenntnisse aufbereiten (3–5 Bullets; strict: 2–3, stark gekürzt)
    final insights = _prepareInsights(
      raw: insightBullets,
      privacy: privacy,
      redactName: userDisplayName,
    );

    // 2) Dokument & Typo / Farben
    final doc = pw.Document();
    final typo = await _loadTypography(); // Fonts, Styles
    final palette = _Palette.oxfordZen();

    // 3) Seiten aufbauen
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.fromLTRB(36, 42, 36, 48),
          theme: pw.ThemeData.withFont(
            base: typo.base,
            bold: typo.bold,
            italic: typo.italic,
            boldItalic: typo.boldItalic,
          ),
        ),
        build: (ctx) {
          final blocks = <pw.Widget>[];

          // Cover / Titel
          blocks.add(_HeaderBlock(
            title: 'Monatsrückblick',
            subtitle: _formatMonthLabel(monthStart),
            palette: palette,
            typo: typo,
          ));

          blocks.add(pw.SizedBox(height: 12));

          // Kennzahlen
          blocks.add(_KpiRow(
            palette: palette,
            typo: typo,
            items: [
              Kpi(label: 'Reflexionen', value: '$reflectionsCount'),
              Kpi(label: 'Ø Stimmung', value: moodStats.avgDisplay),
              Kpi(label: 'Spanne', value: moodStats.rangeDisplay),
            ],
          ));

          blocks.add(pw.SizedBox(height: 16));

          // Stimmung – kurzer Text
          blocks.add(_MoodSummaryBlock(
            palette: palette,
            typo: typo,
            stats: moodStats,
          ));

          // Erkenntnisse (Auszug) – klein & ruhig
          if (insights.isNotEmpty) {
            blocks.add(pw.SizedBox(height: 16));
            blocks.add(_InsightsBlock(
              palette: palette,
              typo: typo,
              bullets: insights,
              caption: 'Erkenntnisse (Auszug)',
            ));
          }

          // NEU: Timeline (nur bei vorhandenen Zeilen anzeigen)
          if (timelineRows.isNotEmpty) {
            blocks.add(pw.SizedBox(height: 16));
            blocks.add(_TimelineSection(
              palette: palette,
              typo: typo,
              rows: timelineRows,
              caption: 'Themen-Verlauf (30 Tage)',
            ));
          }

          // Optional: Kurzgeschichte
          if (story != null) {
            blocks.add(pw.SizedBox(height: 18));
            blocks.add(_StoryBlock(
              palette: palette,
              typo: typo,
              title: _safeStoryTitle(story.title),
              body: _prepareStoryBody(story.body, privacy, userDisplayName),
              privacy: privacy,
            ));
          }

          // Datenschutz-Hinweis
          blocks.add(pw.SizedBox(height: 22));
          blocks.add(_PrivacyFootnote(palette: palette, typo: typo, level: privacy));

          return blocks;
        },
        footer: (ctx) =>
            _Footer(palette: palette, typo: typo, page: ctx.pageNumber),
      ),
    );

    // 4) Speichern (on-device)
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'zenyourself_report_${monthStart.year}-${_pad2(monthStart.month)}.pdf';
    final path = '${dir.path}/$fileName';
    final bytes = await doc.save();
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ---------- Helpers: Insights (Bullets) ------------------------------------

  static List<String> _prepareInsights({
    required List<String>? raw,
    required ExportPrivacy privacy,
    required String? redactName,
  }) {
    final cleaned = (raw ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return const <String>[];

    // Deduplizieren (case-insensitive)
    final seen = <String>{};
    final dedup = <String>[];
    for (final s in cleaned) {
      final k = s.toLowerCase();
      if (seen.add(k)) dedup.add(s);
    }

    // Auf 3–5 begrenzen (strict: 2–3)
    final maxCount = (privacy == ExportPrivacy.strict) ? 3 : 5;
    final limited = dedup.take(maxCount).toList();

    // Redaction + ggf. starke Kürzung
    final out = <String>[];
    for (final s in limited) {
      final red = _redactCommon(s, alsoRedactName: redactName);
      if (privacy == ExportPrivacy.strict) {
        // sehr kompakt (≈ 80 Zeichen)
        out.add(_truncate(red, 80));
      } else {
        // normal kompakt (≈ 160 Zeichen)
        out.add(_truncate(red, 160));
      }
    }

    return out.take(maxCount).toList();
  }

  // ---------- Helpers: Story-Body mit Redaction ------------------------------

  static String _prepareStoryBody(String raw, ExportPrivacy level, String? name) {
    var text = raw.trim();
    if (text.isEmpty) return text;

    switch (level) {
      case ExportPrivacy.open:
        return text;
      case ExportPrivacy.redact:
        return _redactCommon(text, alsoRedactName: name);
      case ExportPrivacy.strict:
        // Nur kurze, generische Zusammenfassung lassen (max. ~2 Sätze)
        final red = _redactCommon(text, alsoRedactName: name);
        final sentences = _splitSentences(red);
        if (sentences.isEmpty) {
          return 'Eine kurze, warme Geschichte – ohne Details.';
        }
        final main = sentences.first;
        final add = (sentences.length > 1)
            ? ' Ein ruhiger Ausblick ohne private Details.'
            : '';
        return _truncate(main, 220) + add;
    }
  }

  static String _safeStoryTitle(String raw) {
    final t = raw.trim().isEmpty ? 'Deine kleine Geschichte' : raw.trim();
    return _redactCommon(t);
  }

  // ---------- Helpers: Mood-Fenster, Stats -----------------------------------

  static List<MoodEntry> _filterMoodsByDayTagOrGuess(
    List<MoodEntry> list,
    DateTime start,
    DateTime end,
  ) {
    // Wir versuchen DayTags "YYYY-MM-DD" zu verwenden; sonst heuristisch createdAt/ts.
    final out = <MoodEntry>[];
    for (final e in list) {
      DateTime? dt;

      // 1) DayTag → 2025-11-07
      try {
        final tag = (e.dayTag as String?);
        if (tag != null && tag.contains('-')) {
          final parts = tag.split('-');
          if (parts.length == 3) {
            final y = int.parse(parts[0]);
            final m = int.parse(parts[1]);
            final d = int.parse(parts[2]);
            dt = DateTime(y, m, d);
          }
        }
      } catch (_) {}

      // 2) createdAt / ts (falls vorhanden)
      if (dt == null) {
        try {
          final created = (e.createdAt as DateTime?);
          if (created != null) dt = created;
        } catch (_) {}
      }

      // 3) Fallback: nehme alles (besser etwas mehr als nichts)
      dt ??= start;

      if (!dt.isBefore(start) && !dt.isAfter(end)) out.add(e);
    }
    return out;
  }

  static _MoodStats _computeMoodStats(List<MoodEntry> list) {
    if (list.isEmpty) return _MoodStats.empty();

    final vals = <double>[];
    for (final e in list) {
      try {
        final score0to4 = (e.moodScore is num)
            ? (e.moodScore as num).toDouble().clamp(0, 4)
            : 2.0;
        // Align auf −2..+2 (wie App)
        vals.add((score0to4 - 2.0).clamp(-2.0, 2.0));
      } catch (_) {
        // wenn Entry unvollständig ist, ignorieren
      }
    }
    if (vals.isEmpty) return _MoodStats.empty();

    vals.sort();
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return _MoodStats(
      avg: avg,
      min: vals.first,
      max: vals.last,
      count: vals.length,
    );
  }

  static int _countReflectionsByDate(
    List<ReflectionEntry> list,
    DateTime start,
    DateTime end,
  ) {
    // Ohne PII: nur zählen, ggf. createdAt nutzen. Bei unbekanntem Feld → inkl.
    int n = 0;
    for (final r in list) {
      DateTime? dt;
      try {
        dt = (r.createdAt as DateTime?);
      } catch (_) {}
      if (dt == null || (!dt.isBefore(start) && !dt.isAfter(end))) n++;
    }
    return n;
  }

  // ---------- NEU: Timeline-Aufbereitung ------------------------------------

  /// Baut Tabellenzeilen (Datum | Thema | Stimmung) für die letzten 30 Tage.
  /// Maximal 5 Einträge, neueste zuerst.
  static List<List<String>> _buildTimelineRows({
    required List<TimelineMarker>? markers,
    required List<MoodEntry> moods,
    required DateTime windowStart,
    required DateTime windowEnd,
    String? redactName,
  }) {
    // Mood-Lookup pro Tag (für Fallback von Marker.moodLabel)
    final moodByDay = _buildMoodLookupByDay(moods);

    // 1) Wenn Marker vorhanden, daraus Zeilen bauen
    final rows = <List<String>>[];
    if (markers != null && markers.isNotEmpty) {
      final inWin = <({DateTime date, TimelineMarker m})>[];
      for (final m in markers) {
        final d = _parseIsoDate(m.dateIso);
        if (d == null) continue;
        if (!d.isBefore(windowStart) && !d.isAfter(windowEnd)) {
          inWin.add((date: d, m: m));
        }
      }
      inWin.sort((a, b) => b.date.compareTo(a.date)); // neueste zuerst

      for (final e in inWin.take(5)) {
        final d = _formatDateDmy(e.date);
        final topic = _redactCommon(e.m.topic?.trim() ?? '—', alsoRedactName: redactName);
        final mood = _redactCommon(
          (e.m.moodLabel?.trim().isNotEmpty ?? false)
              ? e.m.moodLabel!.trim()
              : (moodByDay[_isoOf(e.date)]?.label ?? '—'),
          alsoRedactName: redactName,
        );
        rows.add([d, topic, mood]);
      }
      if (rows.isNotEmpty) return rows;
    }

    // 2) Fallback: Aus Stimmungswerten die letzten 5 Tage innerhalb des Fensters
    final days = moodByDay.keys.toList()..sort((a, b) => b.compareTo(a)); // neueste zuerst
    for (final day in days) {
      final d = _parseIsoDate(day);
      if (d == null) continue;
      if (d.isBefore(windowStart) || d.isAfter(windowEnd)) continue;
      final moodWord = moodByDay[day]?.label ?? '—';
      rows.add([_formatDateDmy(d), '—', moodWord]);
      if (rows.length >= 5) break;
    }
    return rows;
  }

  static DateTime? _parseIsoDate(String? iso) {
    final s = (iso ?? '').trim();
    if (s.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
      try {
        final y = int.parse(s.substring(0, 4));
        final m = int.parse(s.substring(5, 7));
        final d = int.parse(s.substring(8, 10));
        return DateTime(y, m, d);
      } catch (_) {}
    }
    return null;
  }

  static String _isoOf(DateTime d) => '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

  static String _formatDateDmy(DateTime d) => '${_pad2(d.day)}.${_pad2(d.month)}.${d.year}';

  static Map<String, _MoodDay> _buildMoodLookupByDay(List<MoodEntry> moods) {
    final map = <String, List<double>>{};
    for (final e in moods) {
      // Tag bestimmen
      String? iso;
      try {
        final tag = (e.dayTag as String?);
        if (tag != null && tag.contains('-')) iso = tag.trim();
      } catch (_) {}
      if (iso == null) {
        try {
          final created = (e.createdAt as DateTime?);
          if (created != null) iso = _isoOf(created);
        } catch (_) {}
      }
      iso ??= ''; // ignorieren, wenn leer
      if (iso.isEmpty) continue;

      // Score 0..4 → −2..+2 mappen
      double? val;
      try {
        if (e.moodScore is num) {
          final s = (e.moodScore as num).toDouble().clamp(0, 4);
          val = (s - 2.0).clamp(-2.0, 2.0);
        }
      } catch (_) {}
      val ??= 0.0;

      (map[iso] ??= <double>[]).add(val);
    }

    final out = <String, _MoodDay>{};
    map.forEach((iso, vals) {
      if (vals.isEmpty) return;
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      out[iso] = _MoodDay(avg, _wordFromMood(avg));
    });
    return out;
  }

  static String _wordFromMood(double v) {
    if (v >= 1.0) return 'hell';
    if (v >= 0.25) return 'ruhig';
    if (v <= -1.0) return 'schwer';
    if (v <= -0.25) return 'angespannt';
    return 'ausgeglichen';
  }
}

// ============================================================================
// Layout-Bausteine
// ============================================================================

class _HeaderBlock extends pw.StatelessWidget {
  final String title;
  final String subtitle;
  final _Palette palette;
  final _Typography typo;

  const _HeaderBlock({
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.typo,
  });

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ZenYourself',
            style: pw.TextStyle(
              font: typo.bold,
              fontSize: 12,
              color: palette.sage,
              letterSpacing: 0.3,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            title,
            style: pw.TextStyle(
              font: typo.bold,
              fontSize: 22,
              color: palette.deepSage,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            subtitle,
            style: pw.TextStyle(
              font: typo.base,
              fontSize: 12,
              color: palette.jade,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: palette.hairline),
        ],
      ),
    );
  }
}

class Kpi {
  final String label;
  final String value;
  const Kpi({required this.label, required this.value});
}

class _KpiRow extends pw.StatelessWidget {
  final _Palette palette;
  final _Typography typo;
  final List<Kpi> items;

  const _KpiRow({
    required this.palette,
    required this.typo,
    required this.items,
  });

  @override
  pw.Widget build(pw.Context context) {
    final cells = items
        .map(
          (k) => pw.Expanded(
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: pw.BoxDecoration(
                color: palette.card,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: palette.border, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    k.value,
                    style: pw.TextStyle(
                      font: typo.bold,
                      fontSize: 16,
                      color: palette.deepSage,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    k.label,
                    style: pw.TextStyle(
                      font: typo.base,
                      fontSize: 10.5,
                      color: palette.inkSubtle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .toList();

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [...cells],
    );
  }
}

class _MoodSummaryBlock extends pw.StatelessWidget {
  final _Palette palette;
  final _Typography typo;
  final _MoodStats stats;

  const _MoodSummaryBlock({
    required this.palette,
    required this.typo,
    required this.stats,
  });

  @override
  pw.Widget build(pw.Context context) {
    final text = stats.isEmpty
        ? 'Für diesen Zeitraum liegen noch keine Stimmungswerte vor.'
        : 'Die durchschnittliche Stimmung war ${stats.avgWord}. '
            'Die Spanne reichte von ${stats.minWord} bis ${stats.maxWord}. '
            'Insgesamt gingen ${stats.count} Werte ein.';

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: palette.card,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: palette.border, width: 0.7),
      ),
      padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 16,
            height: 16,
            decoration: pw.BoxDecoration(
              color: palette.jade,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              text,
              style: pw.TextStyle(
                font: typo.base,
                fontSize: 11.5,
                color: palette.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// NEU: Insights-Section (klein & ruhig)
class _InsightsBlock extends pw.StatelessWidget {
  final _Palette palette;
  final _Typography typo;
  final List<String> bullets;
  final String caption;

  const _InsightsBlock({
    required this.palette,
    required this.typo,
    required this.bullets,
    required this.caption,
  });

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: palette.card,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border, width: 0.7),
      ),
      padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            caption,
            style: pw.TextStyle(
              font: typo.bold,
              fontSize: 12.5,
              color: palette.jade,
            ),
          ),
          pw.SizedBox(height: 8),
          ...bullets.map(
            (b) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Bullet(
                bulletSize: 3,
                margin: const pw.EdgeInsets.only(right: 6),
                text: b.isEmpty ? '—' : b,
                style: pw.TextStyle(
                  font: typo.base,
                  fontSize: 11,
                  color: palette.ink,
                  height: 1.32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Timeline-Section
class _TimelineSection extends pw.StatelessWidget {
  final _Palette palette;
  final _Typography typo;
  final List<List<String>> rows; // [ [Datum, Thema, Stimmung], ... ]
  final String caption;

  const _TimelineSection({
    required this.palette,
    required this.typo,
    required this.rows,
    required this.caption,
  });

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: palette.card,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border, width: 0.7),
      ),
      padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            caption,
            style: pw.TextStyle(
              font: typo.bold,
              fontSize: 12.5,
              color: palette.jade,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder(
              horizontalInside:
                  pw.BorderSide(color: palette.hairline, width: 0.5),
              verticalInside:
                  pw.BorderSide(color: palette.hairline, width: 0.5),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.9),
              1: const pw.FlexColumnWidth(1.8),
              2: const pw.FlexColumnWidth(1.0),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: palette.card),
                children: [
                  _cellHeader('Datum'),
                  _cellHeader('Thema'),
                  _cellHeader('Stimmung'),
                ],
              ),
              ...rows.map(
                (r) => pw.TableRow(
                  children: [
                    _cell(r[0]),
                    _cell(r[1]),
                    _cell(r[2]),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _cellHeader(String s) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: pw.Text(
          s,
          style: pw.TextStyle(
            font: typo.bold,
            fontSize: 10.5,
            color: palette.deepSage,
          ),
        ),
      );

  pw.Widget _cell(String s) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: pw.Text(
          s.isEmpty ? '—' : s,
          style: pw.TextStyle(
            font: typo.base,
            fontSize: 10.5,
            color: palette.ink,
            height: 1.25,
          ),
        ),
      );
}

class _StoryBlock extends pw.StatelessWidget {
  final _Palette palette;
  final _Typography typo;
  final String title;
  final String body;
  final ExportPrivacy privacy;

  const _StoryBlock({
    required this.palette,
    required this.typo,
    required this.title,
    required this.body,
    required this.privacy,
  });

  @override
  pw.Widget build(pw.Context context) {
    final hint = (privacy == ExportPrivacy.open)
        ? null
        : 'Hinweis: Text ist datenschutzfreundlich ${privacy == ExportPrivacy.redact ? "maskiert" : "gekürzt"}.';

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: palette.card,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border, width: 0.7),
      ),
      padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              font: typo.bold,
              fontSize: 14.5,
              color: palette.jade,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            body.isEmpty ? '—' : body,
            style: pw.TextStyle(
              font: typo.base,
              fontSize: 11.8,
              color: palette.ink,
              height: 1.38,
            ),
          ),
          if (hint != null) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              hint,
              style: pw.TextStyle(
                font: (typo.italic ?? typo.base),
                fontSize: 9.8,
                color: palette.inkSubtle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrivacyFootnote extends pw.StatelessWidget {
  final _Palette palette;
  final _Typography typo;
  final ExportPrivacy level;

  const _PrivacyFootnote({
    required this.palette,
    required this.typo,
    required this.level,
  });

  @override
  pw.Widget build(pw.Context context) {
    final line = switch (level) {
      ExportPrivacy.open =>
        'Exportmodus: Offen. Beachte: Inhalte können persönliche Daten enthalten.',
      ExportPrivacy.redact =>
        'Exportmodus: Reduziert. E-Mails, Telefonnummern, URLs und IDs sind maskiert.',
      ExportPrivacy.strict =>
        'Exportmodus: Streng. Keine Identifikatoren, Freitexte stark gekürzt.',
    };

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        '$line  ·  Daten bleiben lokal (on-device).',
        style: pw.TextStyle(
          font: typo.base,
          fontSize: 9.5,
          color: palette.inkSubtle,
        ),
      ),
    );
  }
}

pw.Widget _Footer({
  required _Palette palette,
  required _Typography typo,
  required int page,
}) {
  return pw.Container(
    alignment: pw.Alignment.centerRight,
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.Text(
      'Seite $page   ·   ZenYourself',
      style: pw.TextStyle(
        font: typo.base,
        fontSize: 9.5,
        color: palette.inkSubtle,
      ),
    ),
  );
}

// ============================================================================
// Farben & Typo
// ============================================================================

class _Palette {
  final PdfColor deepSage;
  final PdfColor sage;
  final PdfColor jade;
  final PdfColor ink;
  final PdfColor inkSubtle;
  final PdfColor card;
  final PdfColor border;
  final PdfColor hairline;

  _Palette({
    required this.deepSage,
    required this.sage,
    required this.jade,
    required this.ink,
    required this.inkSubtle,
    required this.card,
    required this.border,
    required this.hairline,
  });

  factory _Palette.oxfordZen() {
    // Approx. Oxford-Zen harmonische Palette
    final deepSage = PdfColor.fromHex('#2F5F49');
    final sage = PdfColor.fromHex('#78C2A4');
    final jade = PdfColor.fromHex('#7CB89A');
    final ink = PdfColor.fromHex('#222222');
    final inkSubtle = PdfColor.fromHex('#666666');
    final card = PdfColor.fromHex('#FFFFFF').withOpacity(0.94);
    final border = PdfColor.fromHex('#000000').withOpacity(0.10);
    final hairline = PdfColor.fromHex('#000000').withOpacity(0.12);
    return _Palette(
      deepSage: deepSage,
      sage: sage,
      jade: jade,
      ink: ink,
      inkSubtle: inkSubtle,
      card: card,
      border: border,
      hairline: hairline,
    );
  }
}

class _Typography {
  final pw.Font base;
  final pw.Font bold;
  final pw.Font? italic;
  final pw.Font? boldItalic;

  _Typography({
    required this.base,
    required this.bold,
    this.italic,
    this.boldItalic,
  });
}

// Robustes Font-Laden: optionale Fonts fehlen → kein Total-Fallback
Future<_Typography> _loadTypography() async {
  final base = await _tryLoadFont('assets/fonts/NotoSans-Regular.ttf');
  final bold = await _tryLoadFont('assets/fonts/NotoSans-Bold.ttf');
  final italic = await _tryLoadFont('assets/fonts/NotoSans-Italic.ttf');
  final boldItalic = await _tryLoadFont('assets/fonts/NotoSans-BoldItalic.ttf');

  if (base != null && bold != null) {
    return _Typography(
      base: base,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    );
  }

  // Fallback – systemnah, wirkt ruhig genug
  return _Typography(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    italic: pw.Font.helveticaOblique(),
    boldItalic: pw.Font.helveticaBoldOblique(),
  );
}

Future<pw.Font?> _tryLoadFont(String path) async {
  try {
    final data = await rootBundle.load(path);
    return pw.Font.ttf(data);
  } catch (_) {
    return null;
  }
}

// ============================================================================
// Redaction-Utilities (PII)
// ============================================================================

final _reEmail = RegExp(
  r'([a-zA-Z0-9._%+\-]+)@([a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
  multiLine: true,
);
final _rePhone = RegExp(
  r'(?:(?:\+\d{1,3}[\s\-]?)?(?:\(?\d{2,4}\)?[\s\-]?)?\d{3,4}[\s\-]?\d{3,4})',
  multiLine: true,
);
final _reUrl = RegExp(
  r'(?:https?:\/\/|www\.)[^\s]+',
  caseSensitive: false,
  multiLine: true,
);
final _reIdLike = RegExp(
  r'\b[A-Z]{1,3}[\-_:]?\d{3,}\b',
  multiLine: true,
);

String _redactCommon(String text, {String? alsoRedactName}) {
  var s = text;
  s = s.replaceAll(_reEmail, '[E-MAIL]');
  s = s.replaceAll(_reUrl, '[URL]');
  // Telefon-Heuristik: nur Sequenzen mit >=6 Ziffern maskieren (kurze Zahlen bleiben lesbar)
  s = s.replaceAllMapped(_rePhone, (m) {
    final v = m.group(0) ?? '';
    final digits = v.replaceAll(RegExp(r'\D'), '').length;
    if (digits < 6) return v; // kurze Nummernfolgen durchlassen
    return v.replaceAll(RegExp(r'\d'), '×');
  });
  s = s.replaceAll(_reIdLike, '[ID]');
  if (alsoRedactName != null && alsoRedactName.trim().isNotEmpty) {
    final name =
        RegExp(RegExp.escape(alsoRedactName.trim()), caseSensitive: false);
    s = s.replaceAll(name, '…');
  }
  return s;
}

List<String> _splitSentences(String s) {
  final parts =
      s.split(RegExp(r'(?<=[\.!?])\s+')).map((e) => e.trim()).toList();
  return parts.where((e) => e.isNotEmpty).toList();
}

String _truncate(String s, int max) {
  if (s.length <= max) return s;
  return s.substring(0, max - 1).trimRight() + '…';
}

// ============================================================================
// Small Utils
// ============================================================================

String _formatMonthLabel(DateTime d) {
  // z. B. „November 2025“
  const months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember'
  ];
  final name = months[d.month - 1];
  return '$name ${d.year}';
}

String _pad2(int v) => v.toString().padLeft(2, '0');

// ============================================================================
//
// MoodStats – reine Anzeige (keine PII) & MoodDay für Timeline
//
// ============================================================================

class _MoodStats {
  final double avg; // −2..+2
  final double min;
  final double max;
  final int count;

  const _MoodStats({
    required this.avg,
    required this.min,
    required this.max,
    required this.count,
  });

  factory _MoodStats.empty() =>
      const _MoodStats(avg: 0, min: 0, max: 0, count: 0);

  bool get isEmpty => count == 0;

  String get avgDisplay => isEmpty ? '—' : avg.toStringAsFixed(2);
  String get rangeDisplay =>
      isEmpty ? '—' : '${min.toStringAsFixed(1)} – ${max.toStringAsFixed(1)}';

  String get avgWord => PdfExporter._wordFromMood(avg);
  String get minWord => PdfExporter._wordFromMood(min);
  String get maxWord => PdfExporter._wordFromMood(max);
}

class _MoodDay {
  final double value; // −2..+2
  final String label; // Wort (hell/ruhig/ausgeglichen/…)
  _MoodDay(this.value, this.label);
}
