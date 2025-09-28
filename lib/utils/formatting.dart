// lib/utils/formatting.dart
//
// Kleine, zentrale Format-Helper – Oxford-Zen v1.2 · 2025-09-13
// -----------------------------------------------------------------------------
// • Kein intl-Paket notwendig (keine Abhängigkeit).
// • Locale: de_DE-ähnliche Ausgabe (Mo./Di./… + dd.MM. + HH:mm).
// • Robuste Kurztexte (firstWords) mit Whitespace-Normalisierung.
// • Kompatibel zu bisherigen Aufrufen.
//
// Hinweis: Für weitere Format-Helfer existiert zusätzlich ZenFormat in
// lib/shared/zen_style.dart (ohne intl). Dieses File hält bewusst nur
// superleichte Utilities, die überall importiert werden können.

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

/// Erste [n] Wörter aus [text]. Fügt bei Kürzung eine Ellipse („…“) an.
/// Optionaler [prefix] wird unverändert vorangestellt.
String firstWords(String text, int n, {String prefix = ''}) {
  final safeN = n <= 0 ? 1 : n;
  final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return prefix.trim();
  final parts = normalized.split(' ');
  final take = parts.take(safeN).join(' ');
  final ellipsis = parts.length > safeN ? '…' : '';
  return '$prefix$take$ellipsis';
}

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
