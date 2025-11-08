// [BASELINE] lib/services/export/pdf_exporter.dart (Stand: 2025-11-07, v1.0.0)
// ZenYourself — PII-sicherer PDF-Export (on-device), Oxford-Zen-Typografie
// -----------------------------------------------------------------------------
// Zweck
// • Erstellt lokal (on-device) eine ruhige, datenschutzfreundliche PDF
//   mit Monatsrückblick: Titel, Kennzahlen, Stimmungs-Überblick, (optional)
//   Kurzgeschichte, sowie Datenschutz-Hinweis.
// • Keine Netzaufrufe, keine Identifikatoren, keine Roh-Transkripte.
// • Oxford-Zen-Stil (dezente Farben, viel Luft, klare Typo).
//
// Public API
// • PdfExporter.exportMonthlyReport(...): erstellt eine PDF und gibt den
//   Dateipfad zurück. Optional mit StoryResult (Titel+Body) und Privatsphäre-Modus.
//
// Privacy
// • ExportPrivacy.open   → keine Redaktion (nur nutzen, wenn Nutzer klar zustimmt)
// • ExportPrivacy.redact → E-Mail/Telefon/URLs/IDs werden maskiert (Default)
// • ExportPrivacy.strict → kein Freitext außer Story-Titel; Story-Body & Notizen
//                          werden stark gekürzt/neutralisiert.
//
// Hinweise
// • Setze in pubspec.yaml (bereits empfohlen im Projekt) geeignete Fonts als Assets,
//   z. B. NotoSans Regular/Bold. Fallback sind eingebaute Helvetica-Fonts.
// • Der Export ist robust und funktioniert auch ohne Fonts-Assets.
//
// Abhängigkeiten (pubspec):
//   pdf: ^3.10.0
//   path_provider: ^2.1.2
//
// Optional kann die aufrufende UI nach dem Export einen „Öffnen“- oder „Teilen“-
// Schritt anbieten (nicht Bestandteil dieses Services).

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Domain-Modelle (leicht genutzt, ohne Inhalte auszulesen)
import '../../data/mood_entry.dart';
import '../../data/reflection_entry.dart';
import '../../services/guidance/dtos.dart';

enum ExportPrivacy { open, redact, strict }

class PdfExporter {
  /// Erstellt einen PII-sicheren Monatsbericht und gibt den finalen Dateipfad zurück.
  static Future<String> exportMonthlyReport({
    required List<MoodEntry> moodEntries,
    required List<ReflectionEntry> reflectionEntries,
    StoryResult? story, // optional (Titel/Body). Body kann abhängig vom Privacy-Level gekürzt werden.
    required DateTime month, // beliebiges Datum im Zielmonat
    ExportPrivacy privacy = ExportPrivacy.redact,
    String? userDisplayName, // wird IMMER NICHT gedruckt (kein PII-Leak), dient nur Redaction-Heuristik
  }) async {
    // 1) Daten vorsortieren / filtern auf Monat
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd =
        DateTime(month.year, month.month + 1, 1).subtract(const Duration(days: 1));

    final moodsInWindow = _filterMoodsByDayTagOrGuess(moodEntries, monthStart, monthEnd);
    final reflectionsCount = _countReflectionsByDate(reflectionEntries, monthStart, monthEnd);

    // Stimmungs-KPIs
    final moodStats = _computeMoodStats(moodsInWindow);

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

          // Seitenfuß (wird im PageTheme nicht automatisch gezeichnet → manuell am Ende)
          return blocks;
        },
        footer: (ctx) => _Footer(palette: palette, typo: typo, page: ctx.pageNumber),
      ),
    );

    // 4) Speichern (on-device)
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'zenyourself_report_${monthStart.year}-${_pad2(monthStart.month)}.pdf';
    final path = '${dir.path}/$fileName';
    final bytes = await doc.save();
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
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
        if (sentences.isEmpty) return 'Eine kurze, warme Geschichte – ohne Details.';
        // Ersten Satz + optional zweiten neutralen Satz
        final main = sentences.first;
        final add =
            (sentences.length > 1) ? ' Ein ruhiger Ausblick ohne private Details.' : '';
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

  const _KpiRow({required this.palette, required this.typo, required this.items});

  @override
  pw.Widget build(pw.Context context) {
    final cells = items
        .map((k) => pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 10),
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
            ))
        .toList();

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        ...cells,
      ],
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
                font: typo.italic ?? typo.base,
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

pw.Widget _Footer({required _Palette palette, required _Typography typo, required int page}) {
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

Future<_Typography> _loadTypography() async {
  // Versuche Assets (NotoSans), fallback auf eingebaute Helvetica.
  try {
    final base = await _loadFontAsset('assets/fonts/NotoSans-Regular.ttf');
    final bold = await _loadFontAsset('assets/fonts/NotoSans-Bold.ttf');
    final italic = await _loadFontAsset('assets/fonts/NotoSans-Italic.ttf', optional: true);
    final boldItalic =
        await _loadFontAsset('assets/fonts/NotoSans-BoldItalic.ttf', optional: true);
    return _Typography(base: base, bold: bold, italic: italic, boldItalic: boldItalic);
  } catch (_) {
    // Fallback – systemnah, wirkt ruhig genug
    return _Typography(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );
  }
}

Future<pw.Font> _loadFontAsset(String path, {bool optional = false}) async {
  try {
    final data = await rootBundle.load(path);
    return pw.Font.ttf(data);
  } catch (e) {
    if (optional) {
      // ignoriere – der Aufrufer stellt einen Fallback bereit
      rethrow; // wird im _loadTypography try–catch gefangen
    }
    rethrow;
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
  r'(https?:\/\/|www\.)[^\s]+',
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
  // Leichte Telefon-Heuristik (filtert kurze Zahlenfolgen nicht aggressiv)
  s = s.replaceAllMapped(_rePhone, (m) {
    final v = m.group(0) ?? '';
    // Kurze 3-stellige Zahlen wie "100" durchlassen:
    return v.replaceAll(RegExp(r'\d'), '×');
  });
  s = s.replaceAll(_reIdLike, '[ID]');
  if (alsoRedactName != null && alsoRedactName.trim().isNotEmpty) {
    final name = RegExp(RegExp.escape(alsoRedactName.trim()), caseSensitive: false);
    s = s.replaceAll(name, '…');
  }
  return s;
}

List<String> _splitSentences(String s) {
  final parts = s.split(RegExp(r'(?<=[\.!?])\s+')).map((e) => e.trim()).toList();
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
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
  ];
  final name = months[d.month - 1];
  return '$name ${d.year}';
}

String _pad2(int v) => v.toString().padLeft(2, '0');

// ============================================================================
// MoodStats – reine Anzeige (keine PII)
// ============================================================================

class _MoodStats {
  final double avg; // −2..+2
  final double min;
  final double max;
  final int count;

  const _MoodStats({required this.avg, required this.min, required this.max, required this.count});

  factory _MoodStats.empty() => const _MoodStats(avg: 0, min: 0, max: 0, count: 0);

  bool get isEmpty => count == 0;

  String get avgDisplay => isEmpty ? '—' : avg.toStringAsFixed(2);
  String get rangeDisplay => isEmpty ? '—' : '${min.toStringAsFixed(1)} – ${max.toStringAsFixed(1)}';

  String get avgWord => _word(avg);
  String get minWord => _word(min);
  String get maxWord => _word(max);

  String _word(double v) {
    if (v >= 1.0) return 'hell';
    if (v >= 0.25) return 'ruhig';
    if (v <= -1.0) return 'schwer';
    if (v <= -0.25) return 'angespannt';
    return 'ausgeglichen';
  }
}
