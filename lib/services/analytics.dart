// lib/services/analytics.dart
//
// AnalyticsService — ZenYourself Statistik-Zentrale (Oxford-Zen, v2)
// ------------------------------------------------------------------
// • Stabil sortierte Timelines (ASC) bei Insert/Batch/SetAll
// • Side-effect-freie Getter (Unmodifiable Views)
// • Klinik-ready Fenster-/Range-Analysen (Ø-Mood, Heatmaps, Counts)
// • Sanfte Trends (Up/Down/Stable + Regressions-Slope)
// • Streaks & Aktivitäts-Kennzahlen
// • PII-bewusste Exporte (voll / redacted)
// • Robustere JSON-Import-Pfade (tolerant ggü. dynamischen Maps)

import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:zenyourself/data/mood_entry.dart';
import 'package:zenyourself/data/reflection_entry.dart';

class AnalyticsService with ChangeNotifier {
  final List<MoodEntry> _moodEntries = <MoodEntry>[];
  final List<ReflectionEntry> _reflections = <ReflectionEntry>[];

  // ===========
  //  CRUD / Add
  // ===========
  /// Mood-Eintrag hinzufügen (hält Timeline sortiert, ASC).
  void addMoodEntry(MoodEntry entry, {bool notify = true}) {
    _insertSortedMood(entry);
    if (notify) notifyListeners();
  }

  /// Reflexion hinzufügen (hält Timeline sortiert, ASC).
  void addReflection(ReflectionEntry entry, {bool notify = true}) {
    _insertSortedReflection(entry);
    if (notify) notifyListeners();
  }

  /// Batch-Add (ein notify, stabile Sortierung).
  void addAll({
    Iterable<MoodEntry> moods = const [],
    Iterable<ReflectionEntry> reflections = const [],
    bool notify = true,
  }) {
    if (moods.isNotEmpty) {
      _moodEntries.addAll(moods);
      _moodEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    if (reflections.isNotEmpty) {
      _reflections.addAll(reflections);
      _reflections.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    if (notify) notifyListeners();
  }

  /// Kompletten Satz ersetzen (z. B. bei Import/Restore).
  void setAll({
    List<MoodEntry> moods = const [],
    List<ReflectionEntry> reflections = const [],
    bool notify = true,
  }) {
    _moodEntries
      ..clear()
      ..addAll(moods);
    _reflections
      ..clear()
      ..addAll(reflections);
    _moodEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _reflections.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (notify) notifyListeners();
  }

  /// Reset – löscht alle Daten, z. B. bei Profil-Wechsel.
  void clearAll({bool notify = true}) {
    _moodEntries.clear();
    _reflections.clear();
    if (notify) notifyListeners();
  }

  // ===========
  //  Read-only Views
  // ===========
  /// Stimmungs-Einträge (ASC, unveränderbar).
  UnmodifiableListView<MoodEntry> get moodEntries =>
      UnmodifiableListView(_moodEntries);

  /// Reflexions-Einträge (ASC, unveränderbar).
  UnmodifiableListView<ReflectionEntry> get reflections =>
      UnmodifiableListView(_reflections);

  int get moodCount => _moodEntries.length;
  int get reflectionCount => _reflections.length;

  // ===========
  //  Kern-Kennzahlen
  // ===========
  /// Durchschnittliche Stimmung (0..4). UI kann runden.
  double get avgMood {
    if (_moodEntries.isEmpty) return 0.0;
    final sum = _moodEntries.fold<int>(0, (a, e) => a + e.moodScore);
    return sum / _moodEntries.length;
  }

  /// Durchschnitt über die letzten [days] Tage (inkl. heute).
  double averageMoodLastDays(int days) {
    if (days <= 0 || _moodEntries.isEmpty) return 0.0;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    var sum = 0, count = 0;
    for (final e in _moodEntries) {
      if (!e.timestamp.isBefore(start)) {
        sum += e.moodScore;
        count++;
      }
    }
    return count == 0 ? 0.0 : sum / count;
  }

  /// Durchschnitt für Zeitraum [start, end] (inkl.).
  double averageMoodRange(DateTime start, DateTime end) {
    if (_moodEntries.isEmpty) return 0.0;
    final s = start.isBefore(end) ? start : end;
    final e = end.isAfter(start) ? end : start;
    var sum = 0, count = 0;
    for (final m in _moodEntries) {
      final t = m.timestamp;
      final inRange = (t.isAtSameMomentAs(s) || t.isAfter(s)) &&
          (t.isAtSameMomentAs(e) || t.isBefore(e));
      if (inRange) {
        sum += m.moodScore;
        count++;
      }
    }
    return count == 0 ? 0.0 : sum / count;
  }

  /// Mood-Trend (letzte 2 Einträge): "Up" | "Down" | "Stable".
  String get moodTrend {
    if (_moodEntries.length < 2) return 'Stable';
    final last = _moodEntries[_moodEntries.length - 1].moodScore;
    final prev = _moodEntries[_moodEntries.length - 2].moodScore;
    if (last > prev) return 'Up';
    if (last < prev) return 'Down';
    return 'Stable';
  }

  /// Sanfter Trend als Regressions-Slope über die letzten [n] Einträge.
  /// > 0 = aufwärts, < 0 = abwärts, 0 = neutral.
  double moodSlope(int n) {
    if (_moodEntries.isEmpty || n <= 1) return 0.0;
    final take = n.clamp(2, _moodEntries.length);
    final recent = _moodEntries.sublist(_moodEntries.length - take);
    // einfache lineare Regression y = a + b*x, x=0..(k-1)
    final k = recent.length;
    final xs = List<int>.generate(k, (i) => i);
    final meanX = (k - 1) / 2.0;
    final meanY = recent.fold<double>(0.0, (a, e) => a + e.moodScore) / k;
    var num = 0.0, den = 0.0;
    for (var i = 0; i < k; i++) {
      final dx = xs[i] - meanX;
      final dy = recent[i].moodScore - meanY;
      num += dx * dy;
      den += dx * dx;
    }
    return den == 0 ? 0.0 : num / den;
  }

  /// Reflexionsfrequenz/Woche (Events pro 7 Tage) über die gesamte Historie.
  double get reflectionFrequencyPerWeek {
    if (_reflections.isEmpty) return 0.0;
    final first = _reflections.first.timestamp;
    final last = _reflections.last.timestamp;
    final days = last.difference(first).inDays + 1;
    if (days <= 0) return _reflections.length.toDouble();
    return (_reflections.length * 7) / days;
  }

  // ===========
  //  Aktivität / Streaks
  // ===========
  /// Anzahl aktiver Tage mit *mindestens* einem Mood-Eintrag.
  int get moodActiveDays {
    final set = <String>{};
    for (final m in _moodEntries) {
      set.add(_dayTagOf(m.timestamp));
    }
    return set.length;
  }

  /// Anzahl aktiver Tage mit *mindestens* einer Reflexion.
  int get reflectionActiveDays {
    final set = <String>{};
    for (final r in _reflections) {
      set.add(_dayTagOf(r.timestamp));
    }
    return set.length;
  }

  /// Aktuelle Reflexions-Streak in Tagen (inkl. heute, wenn vorhanden).
  int get currentReflectionStreakDays {
    if (_reflections.isEmpty) return 0;
    final days = _reflections.map((r) => _dayTagOf(r.timestamp)).toSet();
    var streak = 0;
    var cursor = DateTime.now();
    while (true) {
      final tag = _dayTagOf(cursor);
      if (days.contains(tag)) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  // ===========
  //  Zeitreihen / Heatmap / Counts
  // ===========
  /// Vollständiger Mood-Zeitverlauf (ASC), für Graphen.
  List<int> get moodTimeline =>
      _moodEntries.map((e) => e.moodScore).toList(growable: false);

  /// Mood Scores der letzten [n] Einträge.
  List<int> getRecentMoodScores(int n) {
    if (n <= 0) return const [];
    final start = (moodCount - n).clamp(0, moodCount);
    return _moodEntries.sublist(start).map((e) => e.moodScore).toList();
    }

  /// Mood-Heatmap-Daten für die letzten [days] Tage.
  /// Map: DayTag (yyyy-MM-dd) → MoodScore (0..4).
  Map<String, int> getMoodHeatmapData(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final out = <String, int>{};
    for (final e in _moodEntries) {
      if (!e.timestamp.isBefore(start)) {
        out[e.dayTag] = e.moodScore;
      }
    }
    return out;
  }

  /// Mood-Heatmap im Datumsbereich [start, end] (inklusive).
  Map<String, int> getMoodHeatmapRange(DateTime start, DateTime end) {
    final s = start.isBefore(end) ? start : end;
    final e = end.isAfter(start) ? end : start;
    final out = <String, int>{};
    for (final m in _moodEntries) {
      final t = m.timestamp;
      final inRange = (t.isAtSameMomentAs(s) || t.isAfter(s)) &&
          (t.isAtSameMomentAs(e) || t.isBefore(e));
      if (inRange) out[m.dayTag] = m.moodScore;
    }
    return out;
  }

  /// Reflexions-Counts pro Tag (DayTag → Anzahl) für die letzten [days] Tage.
  Map<String, int> getReflectionCounts(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final out = <String, int>{};
    for (final r in _reflections) {
      if (!r.timestamp.isBefore(start)) {
        final tag = _dayTagOf(r.timestamp);
        out[tag] = (out[tag] ?? 0) + 1;
      }
    }
    return out;
  }

  /// Mood-Einträge im Zeitraum [start, end] (inklusive).
  List<MoodEntry> moodsInRange(DateTime start, DateTime end) {
    final s = start.isBefore(end) ? start : end;
    final e = end.isAfter(start) ? end : start;
    return _moodEntries.where((m) {
      final t = m.timestamp;
      return (t.isAtSameMomentAs(s) || t.isAfter(s)) &&
          (t.isAtSameMomentAs(e) || t.isBefore(e));
    }).toList(growable: false);
  }

  /// Reflexions-Einträge im Zeitraum [start, end] (inklusive).
  List<ReflectionEntry> reflectionsInRange(DateTime start, DateTime end) {
    final s = start.isBefore(end) ? start : end;
    final e = end.isAfter(start) ? end : start;
    return _reflections.where((r) {
      final t = r.timestamp;
      return (t.isAtSameMomentAs(s) || t.isAfter(s)) &&
          (t.isAtSameMomentAs(e) || t.isBefore(e));
    }).toList(growable: false);
  }

  // ===========
  //  Tags / Themen
  // ===========
  /// Top-N Reflexions-Tags (häufigste Themen).
  Map<String, int> topReflectionTags({int top = 3}) {
    final counts = <String, int>{};
    for (final r in _reflections) {
      final tags = r.tags.toList() ?? const [];
      for (final t in tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(top));
  }

  // ===========
  //  Export / Import
  // ===========
  /// Vollständiger Export (PII-enthält: Inhalte & Timestamps).
  Map<String, dynamic> exportAllData() => {
        'moodEntries': _moodEntries.map((e) => e.toJson()).toList(),
        'reflections': _reflections.map((e) => e.toJson()).toList(),
      };

  /// PII-armer Export (z. B. für Support/Telemetrie).
  /// Entfernt Freitextfelder und lässt nur Metriken/Tags.
  Map<String, dynamic> exportMetricsRedacted() {
    final moods = _moodEntries
        .map((e) => <String, dynamic>{
              'dayTag': e.dayTag,
              'moodScore': e.moodScore,
              'ts': e.timestamp.toUtc().toIso8601String(),
            })
        .toList();

    final refl = _reflections
        .map((r) => <String, dynamic>{
              'id': r.id,
              'ts': r.timestamp.toUtc().toIso8601String(),
              'moodScore': r.moodScore,
              'tags': r.tags.toList(),
              // KEIN userInput/userResponse/aiSummary etc.
            }..removeWhere((_, v) => v == null))
        .toList();

    return {
      'moodEntries': moods,
      'reflections': refl,
    };
  }

  /// JSON-Export als String.
  String exportJsonString({bool pretty = true}) {
    final data = exportAllData();
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  /// JSON-Import (ersetzen). Erwartet kompatible `fromJson`-Factories.
  void importFromJson(Map<String, dynamic> json, {bool notify = true}) {
    final rawMoods = (json['moodEntries'] as List? ?? const <dynamic>[])
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final rawRefl = (json['reflections'] as List? ?? const <dynamic>[])
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final moods = rawMoods.map((j) => MoodEntry.fromJson(j)).toList();
    final refl = rawRefl.map((j) => ReflectionEntry.fromJson(j)).toList();

    setAll(moods: moods, reflections: refl, notify: notify);
  }

  // ===========
  //  Interna
  // ===========
  void _insertSortedMood(MoodEntry entry) {
    // Binäre Insert-Position (ASC)
    int lo = 0, hi = _moodEntries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_moodEntries[mid].timestamp.isBefore(entry.timestamp)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _moodEntries.insert(lo, entry);
  }

  void _insertSortedReflection(ReflectionEntry entry) {
    int lo = 0, hi = _reflections.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_reflections[mid].timestamp.isBefore(entry.timestamp)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _reflections.insert(lo, entry);
  }

  String _dayTagOf(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
