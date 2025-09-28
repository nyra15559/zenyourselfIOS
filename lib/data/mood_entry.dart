// lib/data/mood_entry.dart
//
// MoodEntry — ZenYourself (Next-Gen, UI-agnostisch)
// -------------------------------------------------
// • Schlankes, zukunftsfestes Datenmodell für Stimmungseinträge
// • Null-safe, tolerantes JSON (Millis/Sekunden/ISO, int/double/String)
// • Mood clamping (0..4), Whitespace-Cleanups
// • Helpers: dayTag (lokal), emoji, label (DE/EN), CSV-Export
// • Converter für Journal-Labels (z. B. „Wütend“, „Ruhig“, „Glücklich“)
// • UI-agnostisch (nur dart:ui Color) + Backward-Compat-Getter:
//   - moodLabel  (DE)  → für ältere Aufrufer
//   - moodColor  (Color) alias auf color

import 'dart:ui' show Color;

class MoodEntry {
  /// Zeitpunkt der Stimmungserfassung (UTC empfohlen).
  final DateTime timestamp;

  /// Zen-Skala: 0 = sehr schlecht … 4 = sehr gut.
  final int moodScore;

  /// Optional: Eigene Notiz (kurzer Tagebuchsatz).
  final String? note;

  /// Optional: Tag/Label (z. B. „Arbeit“, „Therapie“, „Urlaub“).
  final String? extra;

  /// Optional: AI-Kurzfazit / emotionale Resonanz.
  final String? aiSummary;

  MoodEntry({
    required this.timestamp,
    required int moodScore,
    String? note,
    String? extra,
    String? aiSummary,
  })  : moodScore = _clampMood(moodScore),
        note = _clean(note),
        extra = _clean(extra),
        aiSummary = _clean(aiSummary);

  // -----------------------
  // JSON (tolerant & schlank)
  // -----------------------
  factory MoodEntry.fromJson(Map<String, dynamic> json) => MoodEntry(
        timestamp: _parseDate(json['timestamp'] ?? json['ts'] ?? json['createdAt']),
        moodScore: _toInt(json['moodScore']) ?? 2,
        note: json['note'] as String?,
        extra: json['extra'] as String?,
        aiSummary: json['aiSummary'] as String?,
      );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'moodScore': moodScore,
      'note': note,
      'extra': extra,
      'aiSummary': aiSummary,
    };
    map.removeWhere((_, v) => v == null);
    return map;
  }

  /// Utility: Liste tolerant parsen.
  static List<MoodEntry> listFromJson(Iterable<dynamic>? arr) {
    if (arr == null) return const [];
    return [
      for (final e in arr)
        if (e is Map<String, dynamic>) MoodEntry.fromJson(e)
    ];
  }

  // -----------------------
  // Derivative / UI-neutrale Helpers
  // -----------------------

  /// Gruppierungstag in Lokalzeit (YYYY-MM-DD) – für Heatmaps/Timeline.
  String get dayTag {
    final local = timestamp.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// Beschreibendes Label (DE).
  String get moodLabelDe {
    switch (moodScore) {
      case 0:
        return 'Sehr schlecht';
      case 1:
        return 'Schlecht';
      case 2:
        return 'Neutral';
      case 3:
        return 'Gut';
      case 4:
        return 'Sehr gut';
      default:
        return 'Unbekannt';
    }
  }

  /// Beschreibendes Label (EN).
  String get moodLabelEn {
    switch (moodScore) {
      case 0:
        return 'Very bad';
      case 1:
        return 'Bad';
      case 2:
        return 'Neutral';
      case 3:
        return 'Good';
      case 4:
        return 'Very good';
      default:
        return 'Unknown';
    }
  }

  /// Backward-Compat: von älteren Call-Sites erwarteter Getter (DE als Default).
  String get moodLabel => moodLabelDe;

  /// Emoji – synchron zur Heatmap (Wetter-Metapher).
  String get emoji {
    switch (moodScore) {
      case 0:
        return '🌫️';
      case 1:
        return '🌦️';
      case 2:
        return '⛅';
      case 3:
        return '🌤️';
      case 4:
        return '🌞';
      default:
        return '…';
    }
  }

  /// Brand-neutrale Farbskala (optional für Call-Sites).
  Color get color {
    switch (moodScore) {
      case 0:
        return const Color(0xFFD0DFE2); // Nebelgrau
      case 1:
        return const Color(0xFFE9E4CC); // Pastell-Sand
      case 2:
        return const Color(0xFFF7EDD6); // Sanftbeige
      case 3:
        return const Color(0xFFDFF2E6); // Hellgrün  (FIX: 0xFFDFF2E6)
      case 4:
        return const Color(0xFFC2E5CF); // Zen-Grün
      default:
        return const Color(0xFFEFEFEF);
    }
  }

  /// Backward-Compat: ältere Screens greifen auf `moodColor` zu.
  Color get moodColor => color;

  // Schnelle Auswertung
  bool get isPositive => moodScore >= 3;
  bool get isNegative => moodScore <= 1;
  bool get isNeutral => moodScore == 2;

  // -----------------------
  // CSV (sicher escapen)
  // -----------------------
  String toCsv() => [
        _csv(timestamp.toIso8601String()),
        moodScore.toString(),
        _csv(note),
        _csv(extra),
        _csv(aiSummary),
      ].join(',');

  // -----------------------
  // Factorys / Mapping
  // -----------------------

  /// Demo-Generator für Previews.
  static MoodEntry demo(String key) {
    final now = DateTime.now().toUtc();
    switch (key) {
      case 'sun':
        return MoodEntry(timestamp: now, moodScore: 4, note: 'Sehr gut (Demo)');
      case 'cloud':
        return MoodEntry(timestamp: now, moodScore: 2, note: 'Neutral (Demo)');
      case 'rain':
        return MoodEntry(timestamp: now, moodScore: 1, note: 'Schlecht (Demo)');
      case 'leaf':
        return MoodEntry(timestamp: now, moodScore: 3, note: 'Gut (Demo)');
      case 'swirl':
        return MoodEntry(timestamp: now, moodScore: 0, note: 'Sehr schlecht (Demo)');
      default:
        return MoodEntry(timestamp: now, moodScore: 2, note: 'Demo');
    }
  }

  /// Mapping freier Label → Score (DE+EN Varianten, **kein const**, eindeutige Keys).
  static MoodEntry fromLabel(String label, {DateTime? atUtc}) {
    final now = (atUtc ?? DateTime.now().toUtc());
    final normalized = label.trim();
    final Map<String, int> map = {
      // DE
      'Sehr schlecht': 0,
      'Regnerisch': 0,
      'Schlecht': 1,
      'Wolkig': 1,
      'Neutral': 2,
      'Gemischt': 2,
      'Gut': 3,
      'Grün': 3,
      'Sehr gut': 4,
      'Sonnig': 4,
      // EN
      'Very bad': 0,
      'Rainy': 0,
      'Bad': 1,
      'Cloudy': 1,
      'Mixed': 2,
      'Good': 3,
      'Green': 3,
      'Very good': 4,
      'Sunny': 4,
    };
    final score = map[normalized] ?? 2;
    return MoodEntry(timestamp: now, moodScore: score, note: normalized);
  }

  /// Mapping unserer Journal-Mood-Labels (MoodScreen) → Score.
  static int scoreFromJournalLabel(String label) {
    switch (label.trim()) {
      case 'Wütend':
        return 0;
      case 'Gestresst':
      case 'Traurig':
        return 1;
      case 'Neutral':
        return 2;
      case 'Ruhig':
        return 3;
      case 'Glücklich':
        return 4;
      default:
        return 2;
    }
  }

  /// Direkt von Score erzeugen (z. B. für Saves ohne Mapping).
  static MoodEntry fromScore(int score,
      {DateTime? atUtc, String? note, String? extra, String? aiSummary}) {
    return MoodEntry(
      timestamp: (atUtc ?? DateTime.now().toUtc()),
      moodScore: score,
      note: note,
      extra: extra,
      aiSummary: aiSummary,
    );
  }

  // -----------------------
  // Mutation / Sort / Equality
  // -----------------------
  MoodEntry copyWith({
    DateTime? timestamp,
    int? moodScore,
    String? note,
    String? extra,
    String? aiSummary,
  }) =>
      MoodEntry(
        timestamp: timestamp ?? this.timestamp,
        moodScore: moodScore ?? this.moodScore,
        note: note ?? this.note,
        extra: extra ?? this.extra,
        aiSummary: aiSummary ?? this.aiSummary,
      );

  int compareTo(MoodEntry other) => other.timestamp.compareTo(timestamp);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoodEntry &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          moodScore == other.moodScore &&
          note == other.note &&
          extra == other.extra &&
          aiSummary == other.aiSummary;

  @override
  int get hashCode => Object.hash(
        timestamp,
        moodScore,
        note,
        extra,
        aiSummary,
      );

  @override
  String toString() =>
      'MoodEntry(${timestamp.toIso8601String()}, score:$moodScore, '
      'note:${note ?? "-"}, extra:${extra ?? "-"}, ai:${aiSummary ?? "-"})';

  // ======================
  // Intern: Normalisierung
  // ======================
  static int _clampMood(int v) {
    if (v < 0) return 0;
    if (v > 4) return 4;
    return v;
  }

  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? null : t;
  }

  static DateTime _parseDate(dynamic v) {
    if (v is DateTime) return v.toUtc();
    if (v is num) {
      final n = v.toInt().abs();
      if (n <= 9999999999) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      }
    }
    if (v is String) {
      final s = v.trim();
      final asNum = int.tryParse(s);
      if (asNum != null) return _parseDate(asNum);
      try {
        return DateTime.parse(s).toUtc();
      } catch (_) {
        return DateTime.now().toUtc();
      }
    }
    return DateTime.now().toUtc();
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  static String _csv(String? s) {
    final v = s ?? '';
    final escaped = v.replaceAll('"', '""');
    return '"$escaped"';
  }
}
