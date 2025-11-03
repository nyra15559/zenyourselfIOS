// lib/utils/formatting.dart
//
// Kleine, zentrale Format-Helper – Oxford-Zen v1.5 · 2025-10-22
// -----------------------------------------------------------------------------
// Ziele
// • Null-Abhängigkeiten (kein intl)
// • Konsequent deutsch-ähnliche Kurzformate
// • Robuste Kurztexte & Ellipsen
// • Zusätzliche Helfer für DayTags & relative Zeiten
//
// Kompatibilität
// • Bestehende Funktionen bleiben API-kompatibel:
//   - formatDateTimeShort(DateTime)
//   - firstWords(String, int, {prefix})
//
// Neu (opt-in):
//   - formatDateShort(DateTime)        → „Do., 04.09.“
//   - formatTimeShort(DateTime)        → „22:41“
//   - formatDayTag(DateTime)           → „YYYY-MM-DD“
//   - parseDayTag(String)              → DateTime? (lokal, 00:00)
//   - neatEllipsis(String, int)        → saubere Ellipse
//   - normalizeWhitespace(String)      → einheitliche Whitespaces
//   - relativeTimeShort(DateTime, {reference})
//       z. B. „gerade eben“, „vor 5 Min“, „vor 2 Std“, „gestern“,
//       „vor 3 Tg“, „vor 2 Wo“, „vor 3 Mon“, „vor 1 J“ / Future: „in …“
//   - (S7.1) timeBucketOf(DateTime)    → Zeit-Bucket (Nacht/Morgen/...)
// -----------------------------------------------------------------------------

/// „Do., 04.09., 22:41“ (lokal, deutsch-ähnlich ohne intl)
String formatDateTimeShort(DateTime dt) {
  final l = dt.toLocal();
  final wd = _weekdayShortDe(l.weekday); // Mo./Di./…/So.
  final dd = _two(l.day);
  final mm = _two(l.month);
  final hh = _two(l.hour);
  final min = _two(l.minute);
  return '$wd, $dd.$mm., $hh:$min';
}

/// „Do., 04.09.“ (lokal)
String formatDateShort(DateTime dt) {
  final l = dt.toLocal();
  final wd = _weekdayShortDe(l.weekday);
  final dd = _two(l.day);
  final mm = _two(l.month);
  return '$wd, $dd.$mm.';
}

/// „22:41“ (lokal)
String formatTimeShort(DateTime dt) {
  final l = dt.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// Erste [n] Wörter aus [text]. Fügt bei Kürzung eine Ellipse („…“) an.
/// Optionaler [prefix] wird unverändert vorangestellt.
String firstWords(String text, int n, {String prefix = ''}) {
  final safeN = n <= 0 ? 1 : n;
  final normalized = normalizeWhitespace(text);
  if (normalized.isEmpty) return prefix.trim();
  final parts = normalized.split(' ');
  final take = parts.take(safeN).join(' ');
  final ellipsis = parts.length > safeN ? '…' : '';
  return '$prefix$take$ellipsis';
}

/// DayTag im Format „YYYY-MM-DD“ (lokales Datum).
String formatDayTag(DateTime dt) {
  final d = dt.toLocal();
  final y = d.year.toString().padLeft(4, '0');
  final m = _two(d.month);
  final day = _two(d.day);
  return '$y-$m-$day';
}

/// Parst einen DayTag „YYYY-MM-DD“ als lokales Datum (00:00). Ungültig → null.
DateTime? parseDayTag(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  try {
    return DateTime(y, mo, d);
  } catch (_) {
    return null;
  }
}

/// Saubere Ellipse mit Wortgrenze, ohne harte Abschneidung mitten im Wort.
/// Schneidet bei [maxChars] und hängt „…“ an (nur wenn nötig).
String neatEllipsis(String s, int maxChars) {
  final t = normalizeWhitespace(s);
  if (t.length <= maxChars) return t;
  final cut = t.substring(0, maxChars);
  final lastSpace = cut.lastIndexOf(' ');
  final safe = lastSpace > 40 ? cut.substring(0, lastSpace) : cut;
  return '${safe.trim()}…';
}

/// Normalisiert Whitespaces (CR/LF/Tabs/Mehrfach-Spaces → einfache Leerzeichen)
String normalizeWhitespace(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Relative Zeit in kurz-deutscher Form (Vergangenheit/Future).
/// Beispiele:
///   now-3s  → „gerade eben“
///   now-5m  → „vor 5 Min“
///   now-2h  → „vor 2 Std“
///   gestern → „gestern“
///   now-3d  → „vor 3 Tg“
///   now-2w  → „vor 2 Wo“
///   now-3mo → „vor 3 Mon“
///   now-1y  → „vor 1 J“
///   in 5m   → „in 5 Min“
String relativeTimeShort(DateTime when, {DateTime? reference}) {
  final now = (reference ?? DateTime.now()).toLocal();
  final t = when.toLocal();
  final diff = t.difference(now);
  final abs = diff.abs();

  if (abs.inSeconds < 15) {
    return diff.isNegative ? 'gerade eben' : 'gleich';
  }

  String past(String u, int n) => 'vor $n $u';
  String future(String u, int n) => 'in $n $u';

  String fmt(String u, int n) => diff.isNegative ? past(u, n) : future(u, n);

  if (abs.inMinutes < 60) {
    final n = abs.inMinutes == 0 ? 1 : abs.inMinutes;
    return fmt('Min', n);
  }
  if (abs.inHours < 24) {
    final n = abs.inHours;
    return fmt('Std', n);
  }

  // „gestern“ / „morgen“ Sonderfall
  final dNow = DateTime(now.year, now.month, now.day);
  final dWhen = DateTime(t.year, t.month, t.day);
  final days = dWhen.difference(dNow).inDays;
  if (days == -1) return 'gestern';
  if (days == 1) return 'morgen';

  if (abs.inDays < 14) {
    return fmt('Tg', abs.inDays);
  }
  if (abs.inDays < 56) {
    final weeks = (abs.inDays / 7).round();
    return fmt('Wo', weeks == 0 ? 1 : weeks);
  }
  if (abs.inDays < 365) {
    final months = (abs.inDays / 30).round();
    return fmt('Mon', months == 0 ? 1 : months);
  }
  final years = (abs.inDays / 365).round();
  return fmt('J', years == 0 ? 1 : years);
}

// ─────────────────────────── S7.1: Zeit-Buckets ───────────────────────────
/// Spezifikation:
/// Nacht(22–05), Morgen(05–11), Mittag(11–14), Nachmittag(14–18), Abend(18–22).
/// Grenzen sind inkl./exkl. wie folgt:
///   • Nacht:        h >= 22  ODER h < 5
///   • Morgen:       5  ≤ h < 11
///   • Mittag:       11 ≤ h < 14
///   • Nachmittag:   14 ≤ h < 18
///   • Abend:        18 ≤ h < 22
enum DaytimeBucket { night, morning, midday, afternoon, evening }

/// Ermittelt den Zeit-Bucket für [dt]. Standard: lokales System-Timezone-Mapping.
DaytimeBucket timeBucketOf(DateTime dt, {bool useLocal = true}) {
  final d = useLocal ? dt.toLocal() : dt;
  final h = d.hour; // 0..23
  if (h >= 22 || h < 5) return DaytimeBucket.night;
  if (h < 11) return DaytimeBucket.morning;
  if (h < 14) return DaytimeBucket.midday;
  if (h < 18) return DaytimeBucket.afternoon;
  return DaytimeBucket.evening; // 18–21
}

/// Deutsches Kurzlabel für den Bucket.
String timeBucketLabelDe(DaytimeBucket b) {
  switch (b) {
    case DaytimeBucket.night:
      return 'Nacht';
    case DaytimeBucket.morning:
      return 'Morgen';
    case DaytimeBucket.midday:
      return 'Mittag';
    case DaytimeBucket.afternoon:
      return 'Nachmittag';
    case DaytimeBucket.evening:
      return 'Abend';
  }
}

/// Stabiler Key (z. B. für Telemetrie/Worker-Payload).
String timeBucketKey(DaytimeBucket b) {
  switch (b) {
    case DaytimeBucket.night:
      return 'night';
    case DaytimeBucket.morning:
      return 'morning';
    case DaytimeBucket.midday:
      return 'midday';
    case DaytimeBucket.afternoon:
      return 'afternoon';
    case DaytimeBucket.evening:
      return 'evening';
  }
}

/// Direktes Label für gegebenes Datum.
String formatTimeBucketShort(DateTime dt, {bool useLocal = true}) =>
    timeBucketLabelDe(timeBucketOf(dt, useLocal: useLocal));

/// Prüft, ob zwei Zeitpunkte im selben Bucket liegen.
bool isSameTimeBucket(DateTime a, DateTime b, {bool useLocal = true}) =>
    timeBucketOf(a, useLocal: useLocal) == timeBucketOf(b, useLocal: useLocal);

// ─────────────────────────── intern ───────────────────────────

String _two(int n) => n.toString().padLeft(2, '0');

/// DateTime.weekday: 1 = Montag … 7 = Sonntag
String _weekdayShortDe(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'Mo.';
    case DateTime.tuesday:
      return 'Di.';
    case DateTime.wednesday:
      return 'Mi.';
    case DateTime.thursday:
      return 'Do.';
    case DateTime.friday:
      return 'Fr.';
    case DateTime.saturday:
      return 'Sa.';
    case DateTime.sunday:
    default:
      return 'So.';
  }
}
