// lib/models/mood_entries_provider.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/mood_entry.dart';

/// Provider für Mood-Tracking-Einträge.
/// - Bewahrt deine bestehende API (add / upsert / update / remove …)
/// - Helpers: batch(), containsDay(), inRange(), latestN(), averageScore(), streak(), heatmap()
/// - Export/Import JSON
typedef ScoreOf = int? Function(MoodEntry e);

class MoodEntriesProvider with ChangeNotifier {
  final List<MoodEntry> _moodEntries = [];

  /// Unmodifiable-Zugriff (verhindert versehentliche Mutationen)
  List<MoodEntry> get entries => List.unmodifiable(_moodEntries);

  /// Schnelle View ohne Kopie (nur lesen! nicht mutieren)
  Iterable<MoodEntry> get view => _moodEntries;

  int get length => _moodEntries.length;
  bool get isEmpty => _moodEntries.isEmpty;
  bool get isNotEmpty => _moodEntries.isNotEmpty;

  /// Gibt es bereits einen Eintrag für den Tag?
  bool containsDay(String dayTag) => _moodEntries.any((e) => e.dayTag == dayTag);

  /// Neuen MoodEntry hinzufügen (wirft Exception, falls Tag schon existiert)
  void add(MoodEntry entry) {
    if (containsDay(entry.dayTag)) {
      throw Exception(
        'Ein MoodEntry für diesen Tag existiert bereits! Nutze update() oder upsert().',
      );
    }
    _moodEntries.add(entry);
    _sort();
    notifyListeners();
  }

  /// Eintrag hinzufügen ODER überschreiben (upsert)
  void upsert(MoodEntry entry) {
    final idx = _moodEntries.indexWhere((e) => e.dayTag == entry.dayTag);
    if (idx != -1) {
      _moodEntries[idx] = entry;
    } else {
      _moodEntries.add(entry);
    }
    _sort();
    notifyListeners();
  }

  /// MoodEntry eines Tages aktualisieren (wirft Exception, falls nicht vorhanden)
  void update(MoodEntry entry) {
    final idx = _moodEntries.indexWhere((e) => e.dayTag == entry.dayTag);
    if (idx == -1) {
      throw Exception('Kein MoodEntry für diesen Tag gefunden. Nutze add() oder upsert().');
    }
    _moodEntries[idx] = entry;
    _sort();
    notifyListeners();
  }

  /// Löscht einen MoodEntry (by Object)
  void remove(MoodEntry entry) {
    _moodEntries.remove(entry);
    notifyListeners();
  }

  /// Löscht MoodEntry anhand dayTag (z. B. "2025-08-17")
  void removeByDayTag(String dayTag) {
    _moodEntries.removeWhere((e) => e.dayTag == dayTag);
    notifyListeners();
  }

  /// Ersetzt ALLE MoodEntries (z. B. beim Sync oder Restore)
  void setAll(List<MoodEntry> entries) {
    _moodEntries
      ..clear()
      ..addAll(entries);
    _sort();
    notifyListeners();
  }

  /// Löscht alle MoodEntries
  void clear() {
    _moodEntries.clear();
    notifyListeners();
  }

  /// Eintrag für bestimmten Tag (oder null)
  MoodEntry? entryForDay(String dayTag) {
    final i = _moodEntries.indexWhere((e) => e.dayTag == dayTag);
    return i == -1 ? null : _moodEntries[i];
  }

  /// Mehrere Operationen bündeln (ein notify, optional sort)
  void batch(void Function() run, {bool sort = true, bool notify = true}) {
    run();
    if (sort) _sort();
    if (notify) notifyListeners();
  }

  /// Einträge in Datumsspanne [start, end] (inklusive by default)
  List<MoodEntry> inRange(DateTime start, DateTime end, {bool inclusive = true}) {
    final s = start.isBefore(end) ? start : end;
    final e = end.isAfter(start) ? end : start;
    return _moodEntries.where((m) {
      final t = m.timestamp;
      return inclusive
          ? (t.isAtSameMomentAs(s) || t.isAfter(s)) &&
              (t.isAtSameMomentAs(e) || t.isBefore(e))
          : t.isAfter(s) && t.isBefore(e);
    }).toList(growable: false);
  }

  /// Neueste N Einträge (bereits nach timestamp sortiert)
  List<MoodEntry> latestN(int n) {
    if (n <= 0 || _moodEntries.isEmpty) return const [];
    final end = math.min(n, _moodEntries.length);
    return _moodEntries.sublist(0, end);
  }

  /// Durchschnitt über die letzten [days] Tage.
  /// `scoreOf` darf null liefern → wird ignoriert.
  double averageScore({required ScoreOf scoreOf, int days = 7}) {
    if (days <= 0 || _moodEntries.isEmpty) return 0;
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days - 1));
    final window = inRange(DateTime(from.year, from.month, from.day), now);
    if (window.isEmpty) return 0;

    var sum = 0;
    var count = 0;
    for (final e in window) {
      final s = scoreOf(e);
      if (s != null) {
        sum += s;
        count++;
      }
    }
    return count == 0 ? 0 : (sum / count);
  }

  /// Streak-Länge (wie viele Tage in Folge predicate==true)
  int streak({required bool Function(MoodEntry e) predicate}) {
    if (_moodEntries.isEmpty) return 0;

    // nach dayTag gruppieren (ein Eintrag pro Tag)
    final byDay = <String, MoodEntry>{};
    for (final e in _moodEntries) {
      byDay[e.dayTag] = e; // letzter gewinnt
    }

    var current = DateTime.now();
    var streak = 0;

    while (true) {
      final tag = _toDayTag(current);
      final hit = byDay[tag];
      if (hit == null || !predicate(hit)) break;
      streak++;
      current = current.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Heatmap-Data: Map<dayTag, score>
  Map<String, int> heatmap({required int Function(MoodEntry e) scoreOf}) {
    final out = <String, int>{};
    for (final e in _moodEntries) {
      out[e.dayTag] = scoreOf(e);
    }
    return out;
  }

  /// Export als JSON-String
  String exportJsonString({
    required Map<String, dynamic> Function(MoodEntry e) toJson,
    bool pretty = true,
  }) {
    final list = _moodEntries.map(toJson).toList(growable: false);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(list)
        : jsonEncode(list);
  }

  /// Import aus JSON-String
  void importJsonString(
    String jsonString, {
    required MoodEntry Function(Map<String, dynamic> j) fromJson,
    bool notify = true,
  }) {
    final raw = jsonDecode(jsonString);
    if (raw is! List) throw const FormatException('JSON muss eine Liste sein');
    final list = raw
        .cast<Map>()
        .map((j) => fromJson(j.cast<String, dynamic>()))
        .toList();
    setAll(list);
    if (notify) notifyListeners();
  }

  // ---- intern ---------------------------------------------------------------

  void _sort() => _moodEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  /// Day-Tag (yyyy-mm-dd) aus Datum
  String _toDayTag(DateTime dt) {
    final d = dt.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
