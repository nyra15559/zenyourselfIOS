// lib/data/mood_entry.dart
//
// MERGE SIGNAL: MoodEntry v1.3.1 — sichere String-Casts, mehr Label-Aliase,
// toleranter listFromJson; keine Breaking Changes.
//
// MoodEntry — ZenYourself (Next-Gen, UI-agnostisch)
// -------------------------------------------------
// • Schlankes, zukunftsfestes Datenmodell für Stimmungseinträge
// • Null-safe, tolerantes JSON (Millis/Sekunden/ISO, int/double/String)
// • Aliase: timestamp=[timestamp|ts|createdAt|created_at|time|date|datetime|ts_ms|tsMillis|ts_millis|ts_s|tsSec|ts_sec]
//           moodScore=[moodScore|score|mood|value]
// • Fallback: Wenn nur Label/Emoji mitkommt → Mapping zu Score
// • Mood clamping (0..4), Whitespace-Cleanups
// • Helpers: dayTag (lokal), emoji, label (DE/EN), CSV-Export (+header), normalizedScore
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
  factory MoodEntry.fromJson(Map<String, dynamic> json) {
    // Timestamp-Aliase
    final tsRaw = json['timestamp'] ??
        json['ts'] ??
        json['createdAt'] ??
        json['created_at'] ??
        json['time'] ??
        json['date'] ??
        json['datetime'] ??
        json['ts_ms'] ??
        json['tsMillis'] ??
        json['ts_millis'] ??
        json['ts_s'] ??
        json['tsSec'] ??
        json['ts_sec'];

    // Labels (breitere Aliase, sicher zu String)
    final labelAny = json['label'] ??
        json['moodLabel'] ??
        json['journalLabel'] ??
        json['mood_label'] ??
        json['label_de'] ??
        json['label_en'];
    final String? labelRaw = _asString(labelAny);

    // Score-Aliase (+ direkter Versuch aus LabelAny)
    int? score = _toInt(json['moodScore']) ??
        _toInt(json['score']) ??
        _toInt(json['mood']) ??
        _toInt(json['value']) ??
        _toInt(labelAny);

    // Label/Emoji → Score Fallback (wenn kein numerischer Score vorhanden)
    if (score == null && labelRaw != null && labelRaw.trim().isNotEmpty) {
      score = scoreFromJournalLabel(labelRaw);
    }

    // aiSummary Aliase (sicher zu String)
    final String? aiSummary =
        _asString(json['aiSummary'] ?? json['ai_summary'] ?? json['summary']);

    // extra Aliase (bewahrt ggf. das Label/Tag; sicher zu String)
    final String? extra = _asString(json['extra'] ?? json['tag'] ?? labelRaw);

    return MoodEntry(
      timestamp: _parseDate(tsRaw),
      moodScore: score ?? 2,
      note: _asString(json['note']),
      extra: extra,
      aiSummary: aiSummary,
    );
  }

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
    if (arr == null) return <MoodEntry>[];
    final out = <MoodEntry>[];
    for (final e in arr) {
      if (e is MoodEntry) {
        out.add(e);
      } else if (e is Map) {
        out.add(MoodEntry.fromJson(e.cast<String, dynamic>()));
      }
      // sonst ignorieren
    }
    return out;
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

  /// true, wenn beide Zeitpunkte am selben lokalen Kalendertag liegen.
  bool isSameLocalDay(DateTime other) {
    final a = timestamp.toLocal();
    final b = other.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Normierter Score (0.0 … 1.0) – nützlich für Charts/Sparklines.
  double get normalizedScore => (moodScore.clamp(0, 4) as num) / 4.0;

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
        return const Color(0xFFDFF2E6); // Hellgrün
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
  static String csvHeader() => 'timestamp,moodScore,note,extra,aiSummary';

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
        return MoodEntry(
          timestamp: now,
          moodScore: 0,
          note: 'Sehr schlecht (Demo)',
        );
      default:
        return MoodEntry(timestamp: now, moodScore: 2, note: 'Demo');
    }
  }

  /// Mapping freier Label → Score (DE+EN Varianten, case-insensitive, Umlaut-Faltung).
  static MoodEntry fromLabel(String label, {DateTime? atUtc}) {
    final now = (atUtc ?? DateTime.now().toUtc());
    final normalized = label.trim();
    final score = scoreFromJournalLabel(normalized);
    return MoodEntry(timestamp: now, moodScore: score, note: normalized);
  }

  /// Mapping unserer Journal-/freien Mood-Labels (MoodScreen) → Score.
  /// Case-insensitive, einfache Umlaut-Faltung, Emoji-Fallback.
  static int scoreFromJournalLabel(String label) {
    final raw = label.trim();
    final k = _fold(raw);

    // Direkte Map (case-insensitive durch Faltung)
    const map = <String, int>{
      // DE
      'sehr schlecht': 0,
      'regnerisch': 0,
      'wutend': 0, // "Wütend"
      'schlecht': 1,
      'wolkig': 1,
      'gestresst': 1,
      'traurig': 1,
      'neutral': 2,
      'gemischt': 2,
      'gut': 3,
      'grun': 3, // "Grün"
      'ruhig': 3,
      'sehr gut': 4,
      'sonnig': 4,
      'glucklich': 4, // "Glücklich"
      // EN
      'very bad': 0,
      'rainy': 0,
      'angry': 0,
      'bad': 1,
      'cloudy': 1,
      'stressed': 1,
      'sad': 1,
      'mixed': 2,
      'neutral ': 2, // toleriert, da trim() + _fold() oben
      'good': 3,
      'green': 3,
      'calm': 3,
      'very good': 4,
      'sunny': 4,
      'happy': 4,
    };

    final fromMap = map[k];
    if (fromMap != null) return fromMap;

    // Emoji-Fallback (Wetter-Metapher)
    final emojiScore = _emojiToScore(raw);
    if (emojiScore != null) return emojiScore;

    // Weitere generische Fallbacks (DE/EN)
    final l = k;
    if (l == 'sehr schlecht' || l == 'very bad' || l == 'rainy') return 0;
    if (l == 'schlecht' || l == 'bad' || l == 'cloudy') return 1;
    if (l == 'gemischt' || l == 'mixed') return 2;
    if (l == 'gut' || l == 'good' || l == 'green' || l == 'calm') return 3;
    if (l == 'sehr gut' || l == 'very good' || l == 'sunny' || l == 'happy') return 4;

    return 2;
  }

  /// Direkt von Score erzeugen (z. B. für Saves ohne Mapping).
  static MoodEntry fromScore(
    int score, {
    DateTime? atUtc,
    String? note,
    String? extra,
    String? aiSummary,
  }) {
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

  /// Absteigend nach Zeit (neu → alt).
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
      final n = v.toInt();
      final absN = n.abs();
      // Heuristik: Sekunden vs Millisekunden
      if (absN <= 9999999999) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      }
    }
    if (v is String) {
      final s = v.trim();
      // ts_ms / ts_s können als String kommen
      final asInt = int.tryParse(s);
      if (asInt != null) return _parseDate(asInt);
      final asDouble = double.tryParse(s);
      if (asDouble != null) return _parseDate(asDouble);
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
    // Strings wie "3" oder "3.0"
    final s = v.toString().trim();
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    return d?.toInt();
  }

  static String _csv(String? s) {
    final v = s ?? '';
    final escaped = v.replaceAll('"', '""');
    return '"$escaped"';
  }

  /// Einfache Umlaut-/Akzent-Faltung + Kleinschreibung.
  static String _fold(String input) {
    return input
        .toLowerCase()
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ß', 'ss')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Emoji → Score (Wetter-Metapher)
  static int? _emojiToScore(String s) {
    if (s.contains('🌞')) return 4;
    if (s.contains('🌤️') || s.contains('🌤')) return 3;
    if (s.contains('⛅')) return 2;
    if (s.contains('🌦️') || s.contains('🌦')) return 1;
    if (s.contains('🌫️') || s.contains('🌫')) return 0;
    return null;
  }

  /// Sicherer String-Cast.
  static String? _asString(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? null : t;
    }
}
