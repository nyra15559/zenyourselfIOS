// lib/models/reflection_entries_provider.dart
//
// ZenYourself — ReflectionEntriesProvider (v6.30, session-aware, rock-solid)
// -------------------------------------------------------------------------
// - Bewahrt die bestehende API (add/addAll/upsert/updateAt/updateById/remove/...)
// - O(1)-Lookups via ID-Index; stabile Sortierung: timestamp DESC, tie-break by id DESC
// - Batch-Commits (batch), koaleszierte Persistenz (_schedulePersist) ohne UI-Jank
// - Robuste Restore-/Import-Pfade (keine Throws in die UI)
// - Ephemerer Session-Flow (Thread-IDs, Turn-Zähler, recommend_end-Gating) getrennt vom Persist-Schema
// - Komfort-APIs: upsertAll, updateManyById, applyTurn, purgeStaleSessions

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/reflection_entry.dart';

typedef ReflectionLoad = Future<List<ReflectionEntry>> Function();
typedef ReflectionSave = Future<void> Function(List<ReflectionEntry> entries);

/// Ephemerer Status einer laufenden Reflexions-Session (Thread)
class ReflectionSessionState {
  final String threadId;
  final String? boundEntryId; // optional: zu welchem Entry gehört der Chat
  final int turnIndex;
  final int maxTurns;
  final bool recommendEnd; // vom Worker vorgeschlagenes Session-Ende
  final DateTime startedAt;

  const ReflectionSessionState({
    required this.threadId,
    required this.turnIndex,
    required this.maxTurns,
    required this.recommendEnd,
    required this.startedAt,
    this.boundEntryId,
  });

  ReflectionSessionState copyWith({
    String? threadId,
    String? boundEntryId,
    int? turnIndex,
    int? maxTurns,
    bool? recommendEnd,
    DateTime? startedAt,
  }) {
    return ReflectionSessionState(
      threadId: threadId ?? this.threadId,
      boundEntryId: boundEntryId ?? this.boundEntryId,
      turnIndex: turnIndex ?? this.turnIndex,
      maxTurns: maxTurns ?? this.maxTurns,
      recommendEnd: recommendEnd ?? this.recommendEnd,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}

/// Provider für ReflectionEntry-Objekte (Reflexionsfluss).
/// - Dedupe by ID (letztes Vorkommen gewinnt)
/// - O(1)-Lookups via Index
/// - Batch-Updates & koaleszierte Persistenz (Save-Hook) stabil
/// - Sortierung: timestamp DESC, tie-break by id DESC
/// - Ephemer: Session-Flow (activeThreadId, Sessions-Map)
class ReflectionEntriesProvider with ChangeNotifier {
  // Interner Speicher (DESC nach timestamp; bei Gleichstand: id DESC)
  final List<ReflectionEntry> _items = [];

  /// ID → Index (O(1)-Lookups). Nach Sortierungen neu aufgebaut.
  final Map<String, int> _idIndex = {};

  // Optional: Persistence Hooks
  ReflectionLoad? _loadHook;
  ReflectionSave? _saveHook;

  // Koaleszierte Persistenz
  bool _saveScheduled = false;

  // Batch-Flag (mehrere Mutationen als ein Commit)
  int _batchDepth = 0;
  bool get _isBatching => _batchDepth > 0;

  /// Ephemerer Session-Store
  final Map<String, ReflectionSessionState> _sessionsByThread = {}; // threadId -> state
  String? _activeThreadId; // aktuell im UI aktive Session

  // ---------- Public Read-only Views ----------

  List<ReflectionEntry> get reflections => List.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  // ---------- Session (ephemer) ----------

  /// Aktive Thread-ID für den Chat-Container (optional).
  String? get activeThreadId => _activeThreadId;

  /// Setzt/entfernt die aktive Thread-ID (UI-Fokus).
  void setActiveThread(String? threadId, {bool notify = true}) {
    _activeThreadId = threadId;
    if (notify && !_isBatching) notifyListeners();
  }

  /// Liefert Session-State zu einer Thread-ID (oder null).
  ReflectionSessionState? sessionByThread(String threadId) =>
      _sessionsByThread[threadId];

  /// Bindet eine Session an einen Entry (z. B. wenn der Chat zu einem Eintrag gehört).
  void bindSessionToEntry({
    required String threadId,
    required String entryId,
    bool notify = true,
  }) {
    final s = _sessionsByThread[threadId];
    if (s == null) return;
    _sessionsByThread[threadId] = s.copyWith(boundEntryId: entryId);
    if (notify && !_isBatching) notifyListeners();
  }

  /// Erzeugt/aktualisiert Session-State (z. B. nach /reflect).
  void upsertSession(ReflectionSessionState state, {bool notify = true}) {
    _sessionsByThread[state.threadId] = state;
    _activeThreadId ??= state.threadId;
    if (notify && !_isBatching) notifyListeners();
  }

  /// Aktualisiert Turn & recommend_end (Flow-Gating).
  void advanceSession({
    required String threadId,
    int? turnIndex,
    bool? recommendEnd,
    int? maxTurns,
    bool notify = true,
  }) {
    final s = _sessionsByThread[threadId];
    if (s == null) return;
    _sessionsByThread[threadId] = s.copyWith(
      turnIndex: turnIndex ?? (s.turnIndex + 1),
      recommendEnd: recommendEnd ?? s.recommendEnd,
      maxTurns: maxTurns ?? s.maxTurns,
    );
    if (notify && !_isBatching) notifyListeners();
  }

  /// Beendet eine Session (entfernt ephemeren State).
  void endSession(String threadId, {bool notify = true}) {
    _sessionsByThread.remove(threadId);
    if (_activeThreadId == threadId) _activeThreadId = null;
    if (notify && !_isBatching) notifyListeners();
  }

  /// True, wenn Session ein natürliches Ende empfiehlt (Buttons am Ende zeigen).
  bool recommendEndFor(String threadId) =>
      _sessionsByThread[threadId]?.recommendEnd ?? false;

  /// Entfernt alte Sessions (z. B. nach App-Restart), Default 12h.
  void purgeStaleSessions({
    Duration maxAge = const Duration(hours: 12),
    bool notify = true,
  }) {
    final now = DateTime.now();
    _sessionsByThread.removeWhere((_, s) => now.difference(s.startedAt) > maxAge);
    if (notify && !_isBatching) notifyListeners();
  }

  /// Session-Debug (optional)
  Map<String, dynamic> debugSessions() => _sessionsByThread.map(
        (k, v) => MapEntry(k, {
          'entryId': v.boundEntryId,
          'turnIndex': v.turnIndex,
          'maxTurns': v.maxTurns,
          'recommendEnd': v.recommendEnd,
          'startedAt': v.startedAt.toIso8601String(),
        }),
      );

  // ---------- Persistence (optional) ----------

  Future<void> attachPersistence({
    ReflectionLoad? load,
    ReflectionSave? save,
    bool loadNow = true,
  }) async {
    _loadHook = load;
    _saveHook = save;
    if (loadNow && _loadHook != null) {
      await restore();
    }
  }

  Future<void> restore() async {
    if (_loadHook == null) return;
    try {
      final loaded = await _loadHook!.call();
      replaceAll(loaded);
    } catch (e, st) {
      debugPrint('ReflectionEntriesProvider.restore error: $e\n$st');
    }
  }

  void _schedulePersist() {
    final saver = _saveHook;
    if (saver == null || _saveScheduled) return;
    _saveScheduled = true;
    // Koaleszieren auf eine Microtask pro Mutations-„Welle“
    scheduleMicrotask(() async {
      _saveScheduled = false;
      try {
        await saver.call(List<ReflectionEntry>.unmodifiable(_items));
      } catch (e, st) {
        debugPrint('ReflectionEntriesProvider.save error: $e\n$st');
      }
    });
  }

  // ---------- CRUD ----------

  /// Fügt einen Eintrag hinzu. Bei gleicher ID wird ersetzt (Dedupe).
  void add(ReflectionEntry entry, {bool sort = true, bool notify = true}) {
    final i = _idIndex[entry.id];
    if (i == null) {
      _items.add(entry);
      _idIndex[entry.id] = _items.length - 1;
    } else {
      _items[i] = entry;
    }
    _afterMutation(sort: sort, notify: notify, persist: true);
  }

  /// Mehrere Einträge hinzufügen (Dedupe by ID, letztes Vorkommen gewinnt).
  void addAll(Iterable<ReflectionEntry> entries, {bool sort = true, bool notify = true}) {
    for (final e in entries) {
      final i = _idIndex[e.id];
      if (i == null) {
        _items.add(e);
        _idIndex[e.id] = _items.length - 1;
      } else {
        _items[i] = e;
      }
    }
    _afterMutation(sort: sort, notify: notify, persist: true);
  }

  /// Upsert anhand der ID (existiert -> ersetzen, sonst hinzufügen).
  void upsert(ReflectionEntry entry, {bool sort = true, bool notify = true}) {
    add(entry, sort: sort, notify: notify);
  }

  /// Upsert für viele (stabil & schnell).
  void upsertAll(Iterable<ReflectionEntry> entries, {bool sort = true, bool notify = true}) {
    for (final e in entries) {
      final i = _idIndex[e.id];
      if (i == null) {
        _items.add(e);
        _idIndex[e.id] = _items.length - 1;
      } else {
        _items[i] = e;
      }
    }
    _afterMutation(sort: sort, notify: notify, persist: true);
  }

  /// Aktualisiert per Index (bewahrt API).
  /// Auto-Resort, wenn sich der timestamp ändert oder [sort] true ist.
  void updateAt(
    int index,
    ReflectionEntry updated, {
    bool sort = false,
    bool notify = true,
  }) {
    if (index < 0 || index >= _items.length) return;
    final prev = _items[index];
    _items[index] = updated;
    // ID kann sich (theoretisch) ändern → Index aktualisieren
    if (prev.id != updated.id) {
      _idIndex.remove(prev.id);
      _idIndex[updated.id] = index;
    }
    final needsSort = sort || updated.timestamp != prev.timestamp;
    _afterMutation(sort: needsSort, notify: notify, persist: true);
  }

  /// Aktualisiert per ID (liefert true, wenn gefunden).
  /// Auto-Resort, wenn sich der timestamp ändert oder [sort] true ist.
  bool updateById(
    String id,
    ReflectionEntry Function(ReflectionEntry) mutate, {
    bool sort = false,
    bool notify = true,
  }) {
    final i = _idIndex[id];
    if (i == null) return false;
    final prev = _items[i];
    final next = mutate(prev);
    _items[i] = next;
    // Falls die ID mutiert wurde (ungewöhnlich), Index anpassen
    if (next.id != id) {
      _idIndex.remove(id);
      _idIndex[next.id] = i;
    }
    final needsSort = sort || next.timestamp != prev.timestamp;
    _afterMutation(sort: needsSort, notify: notify, persist: true);
    return true;
  }

  /// Batch-Update vieler IDs.
  void updateManyById(
    Iterable<String> ids,
    ReflectionEntry Function(ReflectionEntry) mutate, {
    bool sort = false,
    bool notify = true,
  }) {
    var changed = false;
    for (final id in ids) {
      final i = _idIndex[id];
      if (i == null) continue;
      final prev = _items[i];
      final next = mutate(prev);
      _items[i] = next;
      if (prev.id != next.id) {
        _idIndex.remove(prev.id);
        _idIndex[next.id] = i;
      }
      changed = true;
    }
    if (changed) {
      _afterMutation(sort: sort, notify: notify, persist: true);
    }
  }

  /// Entfernt per Objekt.
  void remove(ReflectionEntry entry, {bool notify = true}) {
    final i = _idIndex[entry.id];
    if (i == null) return;
    _items.removeAt(i);
    _reindex(); // Indizes verschoben → komplett neu aufbauen
    _afterMutation(sort: false, notify: notify, persist: true);
    // falls Session an diesen Entry gebunden war → trennen
    _sessionsByThread.updateAll(
      (_, s) => s.boundEntryId == entry.id ? s.copyWith(boundEntryId: null) : s,
    );
  }

  /// Entfernt per ID (liefert true, wenn etwas entfernt wurde).
  bool removeById(String id, {bool notify = true}) {
    final i = _idIndex[id];
    if (i == null) return false;
    _items.removeAt(i);
    _reindex();
    _afterMutation(sort: false, notify: notify, persist: true);
    _sessionsByThread.updateAll(
      (_, s) => s.boundEntryId == id ? s.copyWith(boundEntryId: null) : s,
    );
    return true;
  }

  /// Entfernt via Prädikat (für Aufräumjobs).
  void removeWhere(bool Function(ReflectionEntry) test, {bool notify = true}) {
    if (_items.isEmpty) return;
    _items.removeWhere(test);
    _reindex();
    _afterMutation(sort: false, notify: notify, persist: true);
  }

  /// Setzt komplette Liste (z. B. Import/Sync).
  void setAll(List<ReflectionEntry> entries, {bool sort = true, bool notify = true}) {
    replaceAll(entries, sort: sort, notify: notify);
  }

  /// Ersetzt alle Einträge. Dedupe by ID (letztes Vorkommen gewinnt) + Sort DESC.
  void replaceAll(Iterable<ReflectionEntry> items, {bool sort = true, bool notify = true}) {
    _items
      ..clear()
      ..addAll(_dedupById(items));
    _reindex();
    _afterMutation(sort: sort, notify: notify, persist: true);
  }

  /// Leert alle Einträge (Sessions bleiben unberührt).
  void clear({bool notify = true}) {
    _items.clear();
    _idIndex.clear();
    _afterMutation(sort: false, notify: notify, persist: true);
  }

  // ---------- Lookup ----------

  ReflectionEntry? entryAt(int idx) {
    if (idx < 0 || idx >= _items.length) return null;
    return _items[idx];
  }

  ReflectionEntry? entryById(String id) {
    final i = _idIndex[id];
    if (i == null) return null;
    if (i < 0 || i >= _items.length) return null;
    return _items[i];
  }

  int indexOfId(String id) => _idIndex[id] ?? -1;

  bool containsId(String id) => _idIndex.containsKey(id);

  // ---------- Queries / Analytics ----------

  /// Neueste N Einträge (setzt DESC-Sortierung voraus).
  List<ReflectionEntry> latestN(int n) =>
      n <= 0 ? const [] : _items.take(n).toList(growable: false);

  /// Einträge in Datumsspanne [start, end] (inklusive).
  /// Nutzt frühes Abbrechen, da _items DESC sortiert sind.
  List<ReflectionEntry> inRange(DateTime start, DateTime end, {bool inclusive = true}) {
    final s = start.isBefore(end) ? start : end;
    final e = end.isAfter(start) ? end : start;
    final out = <ReflectionEntry>[];

    for (final x in _items) {
      final t = x.timestamp;
      final inLower = inclusive ? !t.isBefore(s) : t.isAfter(s);
      final inUpper = inclusive ? !t.isAfter(e) : t.isBefore(e);
      if (inLower && inUpper) { // <-- FIX: 'und' -> '&&'
        out.add(x);
      }
      // Da DESC: sobald t < s (untere Grenze), können wir abbrechen
      if (t.isBefore(s)) break;
    }
    return out;
  }

  /// Ø-MoodScore (0..4) über die letzten [days] Tage (auf 2 Nachkommastellen).
  double averageMoodScore({int days = 7}) {
    if (days <= 0 || _items.isEmpty) return 0;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final list = inRange(from, now);
    int sum = 0, count = 0;
    for (final e in list) {
      final s = e.moodScore;
      if (s != null) {
        sum += s;
        count++;
      }
    }
    if (count == 0) return 0;
    return double.parse((sum / count).toStringAsFixed(2));
  }

  /// Tag-Häufigkeiten (für Filter/Chips).
  Map<String, int> countByTag() {
    final out = <String, int>{};
    for (final e in _items) {
      for (final t in e.tags) {
        out[t] = (out[t] ?? 0) + 1;
      }
    }
    return out;
  }

  /// Sparkline der letzten [days] Tage (Ø pro Tag; ältestes → neuestes).
  List<double> moodSparkline({int days = 7}) {
    if (days <= 0) return const [];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));

    final bucketSum = <int, int>{}; // dayKey -> sum of moodScore
    final bucketN = <int, int>{};   // dayKey -> count

    for (final e in _items) {
      final d = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      if (d.isBefore(start)) break; // DESC
      final key = d.year * 10000 + d.month * 100 + d.day;
      final s = e.moodScore;
      if (s == null) continue;
      bucketSum[key] = (bucketSum[key] ?? 0) + s;
      bucketN[key] = (bucketN[key] ?? 0) + 1;
    }

    final series = <double>[];
    for (int i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final key = d.year * 10000 + d.month * 100 + d.day;
      final n = bucketN[key] ?? 0;
      final avg = n == 0 ? 0.0 : (bucketSum[key]! / n);
      series.add(double.parse(avg.toStringAsFixed(2)));
    }
    return series;
  }

  // ---------- Import/Export ----------

  /// Export als JSON (nutzt ReflectionEntry.toJson()).
  String exportJsonString({bool pretty = true}) {
    final data = _items.map((e) => e.toJson()).toList(growable: false);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  /// Import aus JSON-String (ersetzen).
  void importJsonString(String jsonString, {bool sort = true, bool notify = true}) {
    try {
      final raw = jsonDecode(jsonString);
      if (raw is! List) {
        throw const FormatException('Reflection JSON muss eine Liste sein.');
      }
      final list = raw
          .cast<Map>()
          .map((j) => ReflectionEntry.fromJson(j.cast<String, dynamic>()))
          .toList();
      replaceAll(list, sort: sort, notify: notify);
    } catch (e) {
      // bewusst keine Exception weiterwerfen – Provider soll die UI nicht crashen lassen
      debugPrint('Reflection import failed: $e');
    }
  }

  /// Batch-Update: fasst mehrere Mutationen zusammen.
  void batch(void Function() run, {bool sort = true, bool notify = true}) {
    _batchDepth++;
    try {
      run();
    } finally {
      _batchDepth--;
      if (!_isBatching) {
        _afterMutation(sort: sort, notify: notify, persist: true);
      }
    }
  }

  // ---------- AI-Turn-Anbindung (ohne Model-Zwang) ----------

  /// Wendet ein AI-Turn-Ergebnis auf einen bestehenden Entry an.
  /// *Mapper* kapselt die konkrete Feldbelegung, damit dieses Provider
  /// unabhängig vom genauen ReflectionEntry-Schema bleibt.
  bool applyTurn({
    required String entryId,
    required ReflectionTurnLike turn,
    required ReflectionEntry Function(ReflectionEntry old, ReflectionTurnLike turn) mapper,
    bool notify = true,
  }) {
    final ok = updateById(
      entryId,
      (prev) => mapper(prev, turn),
      sort: true,
      notify: notify,
    );
    if (ok) {
      // Session-Info ephemer nachführen
      final threadId = turn.sessionThreadId ?? (turn.meta['thread_id']?.toString() ?? '');
      if (threadId.isNotEmpty) {
        upsertSession(
          ReflectionSessionState(
            threadId: threadId,
            boundEntryId: entryId,
            turnIndex: turn.sessionTurnIndex ?? 0,
            maxTurns: turn.sessionMaxTurns ?? 3,
            recommendEnd: turn.recommendEnd ?? false,
            startedAt: DateTime.now(),
          ),
          notify: notify,
        );
      }
    }
    return ok;
  }

  // ---------- intern ----------

  void _afterMutation({required bool sort, required bool notify, required bool persist}) {
    if (sort) {
      _items.sort((a, b) {
        final c = b.timestamp.compareTo(a.timestamp);
        if (c != 0) return c;
        // stabiler Tie-Break, damit die Reihenfolge deterministisch bleibt
        return b.id.compareTo(a.id);
      });
      _reindex();
    } else if (_idIndex.length != _items.length) {
      // Safety: falls Index out-of-sync (z. B. removeWhere)
      _reindex();
    }
    if (!_isBatching) {
      if (notify) notifyListeners();
      if (persist) _schedulePersist();
    }
  }

  void _reindex() {
    _idIndex
      ..clear()
      ..addEntries(Iterable.generate(
        _items.length,
        (i) => MapEntry(_items[i].id, i),
      ));
  }

  /// Dedupe Liste anhand der ID (letztes Vorkommen gewinnt).
  List<ReflectionEntry> _dedupById(Iterable<ReflectionEntry> items) {
    final map = <String, ReflectionEntry>{};
    for (final e in items) {
      map[e.id] = e;
    }
    final list = map.values.toList();
    list.sort((a, b) {
      final c = b.timestamp.compareTo(a.timestamp);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });
    return list;
  }
}

// ===========================================================================
//  Lightweight „Turn“-Interface (damit Provider entkoppelt von API-Modellen bleibt)
// ===========================================================================
class ReflectionTurnLike {
  /// Primärfrage aus /reflect (UI-Primary)
  final String outputText;

  /// Optional: kurzer Spiegel-Satz
  final String? mirror;

  /// 0–2 kurze Kontext-Phrasen
  final List<String> context;

  /// 0–2 Mini-Fragen
  final List<String> followups;

  /// Flow-Marker
  final bool? recommendEnd;

  /// Session-Metadaten
  final String? sessionThreadId;
  final int? sessionTurnIndex;
  final int? sessionMaxTurns;

  /// Zusatz-Meta (frei)
  final Map<String, dynamic> meta;

  const ReflectionTurnLike({
    required this.outputText,
    this.mirror,
    this.context = const [],
    this.followups = const [],
    this.recommendEnd,
    this.sessionThreadId,
    this.sessionTurnIndex,
    this.sessionMaxTurns,
    this.meta = const {},
  });
}
