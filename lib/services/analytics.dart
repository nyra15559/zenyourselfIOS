// lib/services/analytics.dart
//
// AnalyticsService — ZenYourself Statistik-Zentrale (Oxford-Zen, v3)
// ------------------------------------------------------------------
// • Events: app.start, reflection.answer, entry.save, mood.set
// • Stabil sortierte Timelines (ASC) bei Insert/Batch/SetAll
// • Side-effect-freie Getter (Unmodifiable Views)
// • Klinik-ready Fenster-/Range-Analysen (Ø-Mood, Heatmaps, Counts)
// • Sanfte Trends (Up/Down/Stable + Regressions-Slope)
// • Streaks & Aktivitäts-Kennzahlen
// • PII-bewusste Exporte (voll / redacted), Events separat
// • Robustere JSON-Import-Pfade (tolerant ggü. dynamischen Maps)

import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';

// Verwende relative Imports, um mit normalen Flutter-Projekten sicher zu sein.
import '../data/mood_entry.dart';
import '../data/reflection_entry.dart';

@immutable
class AnalyticsEvent {
  final String name; // z. B. "app.start"
  final DateTime ts;
  final Map<String, Object?> props;

  const AnalyticsEvent({
    required this.name,
    required this.ts,
    this.props = const <String, Object?>{},
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'ts': ts.toUtc().toIso8601String(),
        if (props.isNotEmpty) 'props': props,
      };

  static AnalyticsEvent fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? 'event.unknown').toString();
    final tsRaw = (j['ts'] ?? DateTime.now().toUtc().toIso8601String()).toString();
    final DateTime ts = DateTime.tryParse(tsRaw)?.toUtc() ?? DateTime.now().toUtc();
    final props = (j['props'] is Map)
        ? Map<String, Object?>.from(j['props'] as Map)
        : const <String, Object?>{};
    return AnalyticsEvent(name: name, ts: ts, props: props);
  }
}

class AnalyticsService with ChangeNotifier {
  final List<MoodEntry> _moodEntries = <MoodEntry>[];
  final List<ReflectionEntry> _reflections = <ReflectionEntry>[];
  final List<AnalyticsEvent> _events = <AnalyticsEvent>[];

  // ===========
  //  EVENTS (öffentliche Kurz-APIs)
  // ===========
  /// App-Start (z. B. im AppRoot/Main aufrufen).
  void trackAppStart({String? source, String? version, String? platform}) {
    logEvent(
      'app.start',
      props: <String, Object?>{
        if (source != null) 'source': source,
        if (version != null) 'version': version,
        if (platform != null) 'platform': platform,
      },
    );
  }

  /// Antwort/Reflexion wurde erstellt/gespeichert.
  void trackReflectionAnswer({
    String? id,
    int? moodScore, // 0..4
    int? textChars,
    List<String>? tags,
  }) {
    logEvent(
      'reflection.answer',
      props: <String, Object?>{
        if (id != null) 'id': id,
        if (moodScore != null) 'moodScore': moodScore,
        if (textChars != null) 'textChars': textChars,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
      },
    );
  }

  /// Speichern eines Eintrags (journal/reflection/story etc.).
  void trackEntrySave({
    required String kind, // "journal" | "reflection" | "story"
    int? textChars,
    String? moodLabel,
  }) {
    logEvent(
      'entry.save',
      props: <String, Object?>{
        'kind': kind,
        if (textChars != null) 'textChars': textChars,
        if (moodLabel != null && moodLabel.trim().isNotEmpty) 'moodLabel': moodLabel.trim(),
      },
    );
  }

  /// Setzen/Loggen einer Stimmung (0..4).
  void trackMoodSet({required int moodScore, String? moodLabel}) {
    logEvent(
      'mood.set',
      props: <String, Object?>{
        'moodScore': moodScore,
        if (moodLabel != null && moodLabel.trim().isNotEmpty) 'moodLabel': moodLabel.trim(),
      },
    );
  }

  /// Low-level Event Logger (ASC einsortiert).
  void logEvent(String name, {Map<String, Object?> props = const <String, Object?>{}, DateTime? when, bool notify = true}) {
    final ev = AnalyticsEvent(name: name, ts: (when ?? DateTime.now().toUtc()), props: props);
    _insertSortedEvent(ev);
    if (notify) notifyListeners();
  }

  // ===========
  //  CRUD / Add  (Mood & Reflection)
  // ===========
  /// Mood-Eintrag hinzufügen (hält Timeline sortiert, ASC).
  /// trackEvent: ob automatisch ein mood.set Event geloggt wird.
  void addMoodEntry(MoodEntry entry, {bool notify = true, bool trackEvent = true}) {
    _insertSortedMood(entry);
    if (trackEvent) {
      trackMoodSet(moodScore: entry.moodScore, moodLabel: entry.moodLabel);
    }
    if (notify) notifyListeners();
  }

  /// Reflexion hinzufügen (hält Timeline sortiert, ASC).
  /// trackEvent: ob automatisch reflection.answer geloggt wird.
  void addReflection(ReflectionEntry entry, {bool notify = true, bool trackEvent = true}) {
    _insertSortedReflection(entry);
    if (trackEvent) {
      final ui = _getUserInput(entry);
      final ur = _getUserResponse(entry);
      final tags = _getTags(entry).toList();

      trackReflectionAnswer(
        id: entry.id,
        moodScore: entry.moodScore,
        textChars: ui.length + ur.length,
        tags: tags,
      );

      trackEntrySave(
        kind: 'reflection',
        textChars: ui.length,
        moodLabel: _getMoodLabel(entry),
      );
    }
    if (notify) notifyListeners();
  }

  /// Batch-Add (ein notify, stabile Sortierung).
  void addAll({
    Iterable<MoodEntry> moods = const [],
    Iterable<ReflectionEntry> reflections = const [],
    Iterable<AnalyticsEvent> events = const [],
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
    if (events.isNotEmpty) {
      _events.addAll(events);
      _events.sort((a, b) => a.ts.compareTo(b.ts));
    }
    if (notify) notifyListeners();
  }

  /// Kompletten Satz ersetzen (z. B. bei Import/Restore).
  void setAll({
    List<MoodEntry> moods = const [],
    List<ReflectionEntry> reflections = const [],
    List<AnalyticsEvent> events = const [],
    bool notify = true,
  }) {
    _moodEntries
      ..clear()
      ..addAll(moods);
    _reflections
      ..clear()
      ..addAll(reflections);
    _events
      ..clear()
      ..addAll(events);
    _moodEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _reflections.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _events.sort((a, b) => a.ts.compareTo(b.ts));
    if (notify) notifyListeners();
  }

  /// Reset – löscht alle Daten (z. B. bei Profil-Wechsel).
  void clearAll({bool notify = true}) {
    _moodEntries.clear();
    _reflections.clear();
    _events.clear();
    if (notify) notifyListeners();
  }

  // ===========
  //  Read-only Views
  // ===========
  UnmodifiableListView<MoodEntry> get moodEntries =>
      UnmodifiableListView(_moodEntries);
  UnmodifiableListView<ReflectionEntry> get reflections =>
      UnmodifiableListView(_reflections);
  UnmodifiableListView<AnalyticsEvent> get events =>
      UnmodifiableListView(_events);

  int get moodCount => _moodEntries.length;
  int get reflectionCount => _reflections.length;
  int get eventCount => _events.length;

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
    final start = (moodCount - n).clamp(0, moodCount) as int;
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
      final Iterable<String> tags = _getTags(r);
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
  /// Vollständiger Export (PII-enthält: Inhalte & Timestamps + Events).
  Map<String, dynamic> exportAllData() => {
        'moodEntries': _moodEntries.map((e) => e.toJson()).toList(),
        'reflections': _reflections.map((e) => e.toJson()).toList(),
        'events': _events.map((e) => e.toJson()).toList(),
      };

  /// PII-armer Export (z. B. für Support/Telemetrie).
  /// Entfernt Freitextfelder, behält Metriken/Tags.
  Map<String, dynamic> exportMetricsRedacted() {
    final moods = _moodEntries
        .map((e) => <String, dynamic>{
              'dayTag': e.dayTag,
              'moodScore': e.moodScore,
              'ts': e.timestamp.toUtc().toIso8601String(),
            })
        .toList();

    final refl = _reflections
        .map((r) {
          final map = <String, dynamic>{
            'id': r.id,
            'ts': r.timestamp.toUtc().toIso8601String(),
            'moodScore': r.moodScore,
            'tags': _getTags(r).toList(),
          };
          map.removeWhere((_, v) => v == null);
          return map;
        })
        .toList();

    // Events können i. d. R. komplett übertragen werden (keine Freitexte).
    final evs = _events.map((e) => e.toJson()).toList();

    return {
      'moodEntries': moods,
      'reflections': refl,
      'events': evs,
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

    final rawEvents = (json['events'] as List? ?? const <dynamic>[])
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final moods = rawMoods.map((j) => MoodEntry.fromJson(j)).toList();
    final refl = rawRefl.map((j) => ReflectionEntry.fromJson(j)).toList();
    final evs = rawEvents.map((j) => AnalyticsEvent.fromJson(j)).toList();

    setAll(moods: moods, reflections: refl, events: evs, notify: notify);
  }

  // ===========
  //  Interna
  // ===========
  void _insertSortedMood(MoodEntry entry) {
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

  void _insertSortedEvent(AnalyticsEvent ev) {
    int lo = 0, hi = _events.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_events[mid].ts.isBefore(ev.ts)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _events.insert(lo, ev);
  }

  String _dayTagOf(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Iterable<String> _safeTags(dynamic maybeTags) {
    if (maybeTags is Iterable) {
      return maybeTags.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty);
    }
    return const <String>[];
  }

  // ---- ReflectionEntry-Kompatibilität (robuste Fallbacks) -------------------

  String _getUserInput(ReflectionEntry r) {
    final dyn = r as dynamic;
    String? pick;

    T? _try<T>(T Function() f) { try { final v = f(); return v is T ? v : null; } catch (_) { return null; } }

    pick = _try<String>(() => dyn.userInput) ??
           _try<String>(() => dyn.prompt) ??
           _try<String>(() => dyn.question) ??
           _try<String>(() => dyn.input) ??
           _try<String>(() => dyn.text) ??
           _try<String>(() => dyn.content) ??
           _try<String>(() => dyn.userText);

    pick = (pick ?? '').trim();
    return pick!;
  }

  String _getUserResponse(ReflectionEntry r) {
    final dyn = r as dynamic;
    String? pick;

    T? _try<T>(T Function() f) { try { final v = f(); return v is T ? v : null; } catch (_) { return null; } }

    pick = _try<String>(() => dyn.userResponse) ??
           _try<String>(() => dyn.response) ??
           _try<String>(() => dyn.answer) ??
           _try<String>(() => dyn.reply) ??
           _try<String>(() => dyn.output) ??
           _try<String>(() => dyn.textAnswer);

    pick = (pick ?? '').trim();
    return pick!;
  }

  String? _getMoodLabel(ReflectionEntry r) {
    final dyn = r as dynamic;
    String? pick;

    T? _try<T>(T Function() f) { try { final v = f(); return v is T ? v : null; } catch (_) { return null; } }

    pick = _try<String>(() => dyn.moodLabel) ??
           _try<String>(() => dyn.mood) ??
           _try<String>(() => dyn.mood_text) ??
           _try<String>(() => dyn.moodName);

    pick = (pick ?? '').trim();
    return (pick!.isEmpty) ? null : pick;
  }

  Iterable<String> _getTags(ReflectionEntry r) {
    final dyn = r as dynamic;
    dynamic raw;

    T? _try<T>(T Function() f) { try { final v = f(); return v is T ? v : null; } catch (_) { return null; } }

    raw = _try<Iterable>(() => dyn.tags) ??
          _try<Iterable>(() => dyn.topics) ??
          _try<Iterable>(() => dyn.labels) ??
          _try<Iterable>(() => dyn.categories);

    return _safeTags(raw);
  }
}
