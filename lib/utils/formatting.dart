// lib/utils/formatting.dart
//
// Kleine, zentrale Format-Helper – Oxford-Zen v1.1
// ------------------------------------------------
// Falls du kein intl-Paket nutzt, kannst du das hier minimal lokal halten.

import 'package:intl/intl.dart';

/// „Do., 04.09., 22:41“ (lokal, deutsch)
String formatDateTimeShort(DateTime dt) {
  final local = dt.toLocal();
  final wd = DateFormat.E('de_DE').format(local);        // Do.
  final d  = DateFormat('dd.MM.', 'de_DE').format(local); // 04.09.
  final t  = DateFormat.Hm('de_DE').format(local);       // 22:41
  return '$wd, $d, $t';
}

/// Erste n Wörter (mit Ellipse).
String firstWords(String text, int n, {String prefix = ''}) {
  final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return prefix.isNotEmpty ? prefix.trim() : '';
  final parts = normalized.split(' ');
  final take = parts.take(n).join(' ');
  return prefix + take + (parts.length > n ? '…' : '');
}
