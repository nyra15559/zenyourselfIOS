// [UPDATED] lib/models/mood_entries_provider.dart — v1.3.1 (2025-11-08)
// MERGE SIGNAL: Kutsche-2 (Dual-Mood) — Tages-De-Dup (≤2/Tag), Trend-Selektoren, Sparkline, Robustheit
// -------------------------------------------------------------------------------------------------
// Neu in v1.3.1
// • Strong-mode Fixes: clamp(...) → .toInt() bei Rückgabe von int-Werten.
// • _avgBetween(): Zeitvergleich in lokaler Zeitbasis (timestamp.toLocal()), konsistent mit dayTag.
// -------------------------------------------------------------------------------------------------
//
// Neu in v1.3.0
// • Selektoren ergänzt: last(scoreOf), trend(scoreOf, days), series(days, scoreOf).
// • Trend-Ergebnis als Value-Objekt (MoodTrend) mit avgNow/avgPrev/delta/direction.
// • Stabilere Daily-Cap-Anwendung (neueste N je Tag), klarere Sort & Batch-Ops.
// • Kommentare/Docs geschärft; API rückwärtskompatibel (sparklineSeries bleibt).
//
// Hinweise zur Verwendung (Dual-Mood):
// • Nutze ScoreOf für unterschiedliche Skalen, z. B.
//     last(scoreOf: (e) => e.mental) / last(scoreOf: (e) => e.physical)
//     trend(scoreOf: (e) => e.mental, days: 7)
//     series(days: 14, scoreOf: (e) => e.physical)
// • Tages-De-Dup: upsertWithDailyCap(entry, maxPerDay: 2) behält je Tag die NEUESTEN 2.
//
// Sortierung: intern DESC nach timestamp (neueste zuerst).
// -------------------------------------------------------------------------------------------------

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../data/mood_entry.dart';

/// Liefert einen (optionalen) ganzzahligen Score zu einem Entry.
/// Beispielsweise: (e) => e.mental  oder  (e) => e.physical
typedef ScoreOf = int? Function(MoodEntry e);

/// Trend-Ergebnis für einen Mood-Score-Kanal (z. B. mental oder physical).
class MoodTrend {
  /// Durchschnitt der letzten [days] Tage (inkl. heute).
  final double averageNow;

  /// Durchschnitt der direkt davorliegenden [days] Tage.
  final double averagePrev;

  /// averageNow - averagePrev (>0 Verbesserung, <0 Verschlechterung).
  final double delta;

  /// Fenstergröße (Tage).
  final int days;

  /// Richtung: 'up' | 'down' | 'flat'
  final String direction;

  const MoodTrend({
    required this.averageNow,
    required this.averagePrev,
    required this.delta,
    required this.days,
    required this.direction,
  });

  @override
  String toString() =>
      'MoodTrend(days:$days, avgNow:${averageNow.toStringAsFixed(2)}, '
      'avgPrev:${averagePrev.toStringAsFixed(2)}, delta:${delta.toStringAsFixed(2)}, dir:$direction)';
}

class MoodEntriesProvider with ChangeNotifier {
  final List<MoodEntry> _moodEntries = [];

  // ----------------------------- Basics --------------------------------------

  /// Unmodifiable-Ansicht (keine versehentlichen Mutationen).
  List<MoodEntry> get entries => List.unmodifiable(_moodEntries);

  /// Schneller, nicht-kopierender View (READ-ONLY!).
  Iterable<MoodEntry> get view => _moodEntries;

  int get length => _moodEntries.length;
  bool get isEmpty => _moodEntries.isEmpty;
  bool get isNotEmpty => _moodEntries.isNotEmpty;

  /// Gibt es mindestens einen Eintrag für den (lokalen) Kalendertag?
  bool containsDay(String dayTag) => _moodEntries.any((e) => e.dayTag == dayTag);

  // --------------------------- CRUD / Upserts --------------------------------

  /// Fügt einen neuen Eintrag hinzu (wirft, wenn Tag schon existiert).
  /// Für Überschreiben/Limitierung: upsert()/upsertWithDailyCap() verwenden.
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

  /// Eintrag hinzufügen oder (pro Tag) ersetzen.
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

  /// Upsert mit Tages-Obergrenze (z. B. max 2/Tag) — behält je Tag die neuesten N.
  void upsertWithDailyCap(MoodEntry entry, {int maxPerDay = 2}) {
    if (maxPerDay < 1) {
      upsert(entry);
      return;
    }
    _moodEntries.add(entry);
    _applyDailyCap(maxPerDay: maxPerDay);
    _sort();
    notifyListeners();
  }

  /// Aktualisiert einen vorhandenen Tag (wirft, falls nicht vorhanden).
  void update(MoodEntry entry) {
    final idx = _moodEntries.indexWhere((e) => e.dayTag == entry.dayTag);
    if (idx == -1) {
      throw Exception('Kein MoodEntry für diesen Tag gefunden. Nutze add()/upsert().');
    }
    _moodEntries[idx] = entry;
    _sort();
    notifyListeners();
  }

  /// Löscht einen konkreten Eintrag.
  void remove(MoodEntry entry) {
    _moodEntries.remove(entry);
    notifyListeners();
  }

  /// Löscht alle MoodEntries eines (lokalen) Tages (z. B. "2025-08-17").
  void removeByDayTag(String dayTag) {
    _moodEntries.removeWhere((e) => e.dayTag == dayTag);
    notifyListeners();
  }

  /// Ersetzt ALLE Einträge (z. B. nach Restore).
  void setAll(List<MoodEntry> entries) {
    _moodEntries
      ..clear()
      ..addAll(entries);
    _sort();
    notifyListeners();
  }

  /// Entfernt alle Einträge.
  void clear() {
    _moodEntries.clear();
    notifyListeners();
  }

  /// Eintrag für bestimmten Tag (oder null).
  MoodEntry? entryForDay(String dayTag) {
    final i = _moodEntries.indexWhere((e) => e.dayTag == dayTag);
    return i == -1 ? null : _moodEntries[i];
  }

  /// Mehrere Operationen bündeln (ein notify, optional sort).
  void batch(void Function() run, {bool sort = true, bool notify = true}) {
    run();
    if (sort) _sort();
    if (notify) notifyListeners();
  }

  // --------------------------- Selektoren (K2) -------------------------------

  /// Letzter (neuester) nicht-null Score im Stream gemäß [scoreOf].
  int? last({required ScoreOf scoreOf}) {
    for (final e in _moodEntries) {
      final v = scoreOf(e);
      if (v != null) return v.clamp(0, 4).toInt();
    }
    return null;
  }

  /// Trend über [days] Tage (inkl. heute) gegenüber dem direkt davorliegenden Fenster.
  /// direction: 'up' (Δ>ε), 'down' (Δ<−ε), sonst 'flat'.
  MoodTrend trend({
    required ScoreOf scoreOf,
    int days = 7,
    double epsilon = 0.05,
  }) {
    if (_moodEntries.isEmpty || days <= 0) {
      return MoodTrend(
        averageNow: 0,
        averagePrev: 0,
        delta: 0,
        days: days,
        direction: 'flat',
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Fenster 1: letzte N Tage (inkl. heute)
    final start1 = today.subtract(Duration(days: days - 1));
    final avg1 = _avgBetween(start1, today, scoreOf);

    // Fenster 2: N Tage unmittelbar davor
    final end2 = start1.subtract(const Duration(days: 1));
    final start2 = end2.subtract(Duration(days: days - 1));
    final avg2 = _avgBetween(start2, end2, scoreOf);

    final delta = avg1 - avg2;
    final dir = delta > epsilon
        ? 'up'
        : (delta < -epsilon ? 'down' : 'flat');

    return MoodTrend(
      averageNow: avg1,
      averagePrev: avg2,
      delta: delta,
      days: days,
      direction: dir,
    );
  }

  /// Zeitreihe (0..4) über die letzten [days] Tage (chronologisch alt→neu).
  /// Tage ohne Eintrag werden ausgelassen.
  List<int> series({required int days, required ScoreOf scoreOf}) {
    if (days <= 0) return const [];
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));

    final byDay = latestByDay(); // neuester pro Tag
    final out = <int>[];

    for (int i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final tag = _toDayTag(d);
      final entry = byDay[tag];
      final s = entry == null ? null : scoreOf(entry);
      if (s != null) out.add(s.clamp(0, 4).toInt());
    }
    return out;
  }

  // Rückwärtskompatibler Alias (ältere Aufrufer).
  List<int> sparklineSeries({required int days, required ScoreOf scoreOf}) =>
      series(days: days, scoreOf: scoreOf);

  // ------------------------------ Stats/Heat ---------------------------------

  /// Durchschnitt über die letzten [days] Tage.
  double averageScore({required ScoreOf scoreOf, int days = 7}) =>
      averageLastNDays(days: days, scoreOf: scoreOf);

  /// Ø über die letzten N Tage.
  double averageLastNDays({required int days, required ScoreOf scoreOf}) {
    if (days <= 0 || _moodEntries.isEmpty) return 0;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    return _avgBetween(from, DateTime(now.year, now.month, now.day), scoreOf);
  }

  /// Trend-Delta (Kompatibilitäts-Helper): Ø(heute..N) − Ø(davor).
  double trendDelta({required ScoreOf scoreOf, int days = 7}) =>
      trend(scoreOf: scoreOf, days: days).delta;

  /// Streak-Länge: Tage in Folge, für die [predicate]==true (neuester pro Tag gewinnt).
  int streak({required bool Function(MoodEntry e) predicate}) {
    if (_moodEntries.isEmpty) return 0;

    final byDay = latestByDay();
    var current = DateTime.now();
    var streakLen = 0;

    while (true) {
      final tag = _toDayTag(current);
      final hit = byDay[tag];
      if (hit == null || !predicate(hit)) break;
      streakLen++;
      current = current.subtract(const Duration(days: 1));
    }
    return streakLen;
  }

  /// Heatmap-Daten: Map<dayTag, score> (neuester pro Tag).
  Map<String, int> heatmap({required int Function(MoodEntry e) scoreOf}) {
    final byDay = latestByDay();
    final out = <String, int>{};
    for (final e in byDay.values) {
      out[e.dayTag] = scoreOf(e).clamp(0, 4).toInt();
    }
    return out;
  }

  // ------------------------------ Import/Export ------------------------------

  /// Export als JSON-String.
  String exportJsonString({
    required Map<String, dynamic> Function(MoodEntry e) toJson,
    bool pretty = true,
  }) {
    final list = _moodEntries.map(toJson).toList(growable: false);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(list)
        : jsonEncode(list);
  }

  /// Import aus JSON-String (ersetzt alle Einträge).
  void importJsonString(
    String jsonString, {
    required MoodEntry Function(Map<String, dynamic> j) fromJson,
    bool capDaily = false,
    int maxPerDay = 2,
    bool notify = true,
  }) {
    final raw = jsonDecode(jsonString);
    if (raw is! List) throw const FormatException('JSON muss eine Liste sein');
    final list = raw
        .cast<Map>()
        .map((j) => fromJson(j.cast<String, dynamic>()))
        .toList();
    setAll(list);
    if (capDaily) ensureDailyCap(maxPerDay: maxPerDay);
    if (notify) notifyListeners();
  }

  /// Erzwingt nachträglich die Tages-Obergrenze (z. B. nach Bulk-Import/Sync).
  void ensureDailyCap({int maxPerDay = 2}) {
    _applyDailyCap(maxPerDay: maxPerDay);
    _sort();
    notifyListeners();
  }

  // ------------------------------- intern ------------------------------------

  void _sort() => _moodEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  /// Neuester Entry pro lokalem Tag.
  Map<String, MoodEntry> latestByDay() {
    final byDay = <String, MoodEntry>{};
    for (final e in _moodEntries) {
      final existing = byDay[e.dayTag];
      if (existing == null || e.timestamp.isAfter(existing.timestamp)) {
        byDay[e.dayTag] = e;
      }
    }
    return byDay;
  }

  /// Wendet die Tages-Obergrenze an und behält je Tag die neuesten [maxPerDay].
  void _applyDailyCap({required int maxPerDay}) {
    if (_moodEntries.isEmpty) return;

    final byDay = <String, List<MoodEntry>>{};
    for (final e in _moodEntries) {
      (byDay[e.dayTag] ??= <MoodEntry>[]).add(e);
    }

    final kept = <MoodEntry>[];
    for (final list in byDay.values) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // neueste zuerst
      kept.addAll(list.take(math.max(1, maxPerDay)));
    }

    _moodEntries
      ..clear()
      ..addAll(kept);
  }

  /// Durchschnitt im Intervall [from..to] (inklusive Grenzen, Tag-basiert).
  double _avgBetween(DateTime from, DateTime to, ScoreOf scoreOf) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);

    final window = _moodEntries.where((m) {
      final t = m.timestamp.toLocal(); // Konsistenz zu dayTag/local time
      return (t.isAtSameMomentAs(start) || t.isAfter(start)) &&
          (t.isAtSameMomentAs(end) || t.isBefore(end));
    });

    var sum = 0.0;
    var count = 0;
    for (final e in window) {
      final s = scoreOf(e);
      if (s != null) {
        sum += s;
        count++;
      }
    }
    return count == 0 ? 0.0 : (sum / count);
  }

  /// Day-Tag (yyyy-mm-dd) aus Datum (lokale Zeitbasis).
  String _toDayTag(DateTime dt) {
    final d = dt.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
