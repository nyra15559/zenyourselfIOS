// lib/providers/journal_entries_provider.dart
//
// JournalEntriesProvider — Oxford-Zen Pro v9.0 (kanonisch, zusammengeführt)
// ----------------------------------------------------------------------
// • Ein Store für ALLE Entry-Typen (EntryKind-first), DESC by createdAt
// • CRUD/Upsert/Batch + Persistence-Hooks (load/save) mit Microtask-Save
// • Komfort-APIs: addDiary/addReflection/addFromReflection/addStory/addRichReflectionV6
// • Dupe-Guard (5s-Fenster) via Fingerprint
// • Filter/Counts/Soft-Hide (session-lokal), sichtbare Liste & Tages-Gruppierung
// • Pro-Metriken (activeDays, reflectionsCount, averageMood, sparkline)
// • Suche, Range, Export/Import (tolerant)
// • Stabil: O(1)-Lookup per ID-Index, stabile Sortierung

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/journal_entry.dart';

typedef JournalLoad = Future<List<JournalEntry>> Function();
typedef JournalSave = Future<void> Function(List<JournalEntry> entries);

/// Filterauswahl für die Timeline/UI.
enum JournalFilterKind { all, reflection, journal, story }

class JournalEntriesProvider with ChangeNotifier {
  final _uuid = const Uuid();

  // ───────────────────────── State ─────────────────────────

  /// Interner Speicher (immer DESC nach createdAt gehalten)
  final List<JournalEntry> _entries = <JournalEntry>[];

  /// ID → Index für O(1)-Lookups, wird nach Sort/Mutationen neu aufgebaut.
  final Map<String, int> _idIndex = <String, int>{};

  /// Session-lokales Soft-Hide (nicht persistent)
  final Set<String> _hiddenIds = <String>{};

  /// Aktiver UI-Filter
  JournalFilterKind _filter = JournalFilterKind.all;

  // Persistence-Hooks (optional)
  JournalLoad? _loadHook;
  JournalSave? _saveHook;

  // Batch-Flag
  int _batchDepth = 0;
  bool get _isBatching => _batchDepth > 0;

  // Anti-Dupe-Zeitfenster
  static const Duration _dupeWindow = Duration(seconds: 5);

  // ─────────────────────── Read-only Views ───────────────────────

  List<JournalEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  List<JournalEntry> get diaries =>
      _entries.where((e) => e.kind == EntryKind.journal).toList(growable: false);

  List<JournalEntry> get reflections =>
      _entries.where((e) => e.kind == EntryKind.reflection).toList(growable: false);

  List<JournalEntry> get stories =>
      _entries.where((e) => e.kind == EntryKind.story).toList(growable: false);

  JournalEntry? get latest => _entries.isEmpty ? null : _entries.first;

  JournalEntry? get latestReflection {
    for (final e in _entries) {
      if (e.kind == EntryKind.reflection) return e;
    }
    return null;
  }

  JournalEntry? byId(String id) {
    final i = _idIndex[id];
    if (i == null || i < 0 || i >= _entries.length) return null;
    return _entries[i];
  }

  bool containsId(String id) => _idIndex.containsKey(id);
  int indexOfId(String id) => _idIndex[id] ?? -1;

  List<JournalEntry> latestN(int n) =>
      n <= 0 ? const [] : _entries.take(n).toList(growable: false);

  // ─────────────────────── Filter/Counts/Soft-Hide ───────────────────────

  JournalFilterKind get filterKind => _filter;

  void setFilter(JournalFilterKind kind, {bool notify = true}) {
    _filter = kind;
    if (notify && !_isBatching) notifyListeners();
  }

  Map<JournalFilterKind, int> countsByKind() {
    int r = 0, j = 0, s = 0;
    for (final e in _entries) {
      switch (e.kind) {
        case EntryKind.reflection: r++; break;
        case EntryKind.journal:    j++; break;
        case EntryKind.story:      s++; break;
      }
    }
    return {
      JournalFilterKind.all: _entries.length,
      JournalFilterKind.reflection: r,
      JournalFilterKind.journal: j,
      JournalFilterKind.story: s,
    };
  }

  bool _passesFilter(JournalEntry e) {
    switch (_filter) {
      case JournalFilterKind.all:        return true;
      case JournalFilterKind.reflection: return e.kind == EntryKind.reflection;
      case JournalFilterKind.journal:    return e.kind == EntryKind.journal;
      case JournalFilterKind.story:      return e.kind == EntryKind.story;
    }
  }

  /// Sichtbare (nicht session-versteckte) Liste gemäß aktivem Filter
  List<JournalEntry> listVisible() {
    if (_entries.isEmpty) return const <JournalEntry>[];
    final out = <JournalEntry>[];
    for (final e in _entries) {
      if (_hiddenIds.contains(e.id)) continue;
      if (_passesFilter(e)) out.add(e);
    }
    return out;
  }

  /// Gruppierung nach Tag (LOKALE Zeit) für die UI, nur sichtbare Items
  List<_DayGroup> groupByDayVisible() {
    final src = listVisible();
    if (src.isEmpty) return const <_DayGroup>[];
    final groups = <int, List<JournalEntry>>{};
    for (final e in src) {
      final d = e.createdAtLocal;
      final key = d.year * 10000 + d.month * 100 + d.day;
      (groups[key] ??= <JournalEntry>[]).add(e);
    }
    final out = <_DayGroup>[];
    groups.forEach((key, list) {
      list.sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
      final y = key ~/ 10000;
      final m = (key % 10000) ~/ 100;
      final d = key % 100;
      out.add(_DayGroup(DateTime(y, m, d), List.unmodifiable(list)));
    });
    out.sort((a, b) => b.dateOnly.compareTo(a.dateOnly));
    return out;
  }

  // Soft-Hide (session-lokal)
  void hide(String id, {bool notify = true}) {
    _hiddenIds.add(id);
    if (notify && !_isBatching) notifyListeners();
  }
  void hideMany(Iterable<String> ids, {bool notify = true}) {
    _hiddenIds.addAll(ids);
    if (notify && !_isBatching) notifyListeners();
  }
  void unhide(String id, {bool notify = true}) {
    _hiddenIds.remove(id);
    if (notify && !_isBatching) notifyListeners();
  }
  bool isHidden(String id) => _hiddenIds.contains(id);
  void clearHidden({bool notify = true}) {
    _hiddenIds.clear();
    if (notify && !_isBatching) notifyListeners();
  }

  // ─────────────────────── Persistence (optional) ───────────────────────

  Future<void> attachPersistence({
    JournalLoad? load,
    JournalSave? save,
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
      replaceAll(loaded, persist: false); // beim Laden nicht sofort wieder speichern
    } catch (e, st) {
      debugPrint('JournalEntriesProvider.restore error: $e\n$st');
    }
  }

  void _persistSafely() {
    final saver = _saveHook;
    if (saver == null) return;
    // Microtask, um UI-Thread nicht zu blockieren; Fehler werden geloggt.
    scheduleMicrotask(() async {
      try {
        await saver.call(List<JournalEntry>.unmodifiable(_entries));
      } catch (e, st) {
        debugPrint('JournalEntriesProvider.save error: $e\n$st');
      }
    });
  }

  // ───────────────────────── Core Mutations ─────────────────────────

  /// Fügt ein Entry hinzu oder ersetzt per ID (Upsert). Sortiert & persisted.
  void add(JournalEntry entry) {
    final idx = _idIndex[entry.id];
    if (idx == null) {
      _entries.add(entry);
      _idIndex[entry.id] = _entries.length - 1;
    } else {
      _entries[idx] = entry;
    }
    _afterMutation(sort: true, notify: true, persist: true);
  }

  /// Fügt mehrere Einträge hinzu/ersetzt sie per ID (Upsert). Sortiert & persisted.
  void addAll(Iterable<JournalEntry> items) {
    for (final it in items) {
      final idx = _idIndex[it.id];
      if (idx == null) {
        _entries.add(it);
        _idIndex[it.id] = _entries.length - 1;
      } else {
        _entries[idx] = it;
      }
    }
    _afterMutation(sort: true, notify: true, persist: true);
  }

  /// Generisches Add nach EntryKind – mit Dupe-Check (5s).
  JournalEntry addEntry({
    required EntryKind kind,
    required DateTime createdAt,
    String id = '',
    String? title,
    String? subtitle,
    String? thoughtText,
    String? aiQuestion,
    String? userAnswer,
    String? storyTitle,
    String? storyTeaser,
    List<String> tags = const <String>[],
    bool hidden = false,
    String? sourceRef,
  }) {
    final tsUtc = createdAt.toUtc();

    // Dupe-Check nur wenn keine ID vorgegeben ist
    final hasCustomId = id.trim().isNotEmpty;
    if (!hasCustomId) {
      final dupe = _findRecentDuplicate(
        kind: kind,
        thoughtText: thoughtText,
        aiQuestion: aiQuestion,
        userAnswer: userAnswer,
        storyTitle: storyTitle,
        storyTeaser: storyTeaser,
        tags: tags,
        sinceUtc: tsUtc.subtract(_dupeWindow),
      );
      if (dupe != null) return dupe;
    }

    final newId = hasCustomId ? id.trim() : _uuid.v4();

    final entry = JournalEntry(
      id: newId,
      kind: kind,
      createdAt: tsUtc,
      title: title ?? '',
      subtitle: subtitle,
      thoughtText: thoughtText,
      aiQuestion: aiQuestion,
      userAnswer: userAnswer,
      storyTitle: storyTitle,
      storyTeaser: storyTeaser,
      tags: tags,
      hidden: hidden,
      sourceRef: sourceRef,
    );

    final idx = _idIndex[newId];
    if (idx != null) {
      _entries[idx] = entry;
    } else {
      _entries.add(entry);
      _idIndex[newId] = _entries.length - 1;
    }

    _afterMutation(sort: true, notify: true, persist: true);
    return _entries[_idIndex[newId]!] ;
  }

  // ───────────────────────── Komfort-APIs ─────────────────────────

  void addDiary({
    required String text,
    String moodLabel = 'Neutral',
    DateTime? ts,
  }) {
    final created = (ts ?? DateTime.now()).toUtc();
    addEntry(
      kind: EntryKind.journal,
      createdAt: created,
      thoughtText: text.trim(),
      tags: _tagsWithMood(moodLabel),
    );
  }

  void addReflection({
    required String text,
    String moodLabel = 'Neutral',
    String? aiQuestion,
    DateTime? ts,
  }) {
    final created = (ts ?? DateTime.now()).toUtc();
    addEntry(
      kind: EntryKind.reflection,
      createdAt: created,
      aiQuestion: _cleanStr(aiQuestion),
      userAnswer: text.trim(),
      tags: _tagsWithMood(moodLabel),
    );
  }

  void addFromReflection({
    required String thoughts,
    required String question,
    String? answer,
    String moodLabel = 'Neutral',
    DateTime? ts,
  }) {
    final created = (ts ?? DateTime.now()).toUtc();
    final ans = _cleanStr(answer);
    addEntry(
      kind: EntryKind.reflection,
      createdAt: created,
      thoughtText: thoughts.trim().isEmpty ? null : thoughts.trim(),
      aiQuestion: question.trim(),
      userAnswer: ans,
      tags: _tagsWithMood(moodLabel),
    );
  }

  JournalEntry addStory({
    required String title,
    required String body,
    String moodLabel = 'Neutral',
    DateTime? ts,
    String? id,
  }) {
    final created = (ts ?? DateTime.now()).toUtc();
    final teaser = _firstChars(body.trim(), 280);
    return addEntry(
      id: id ?? '',
      kind: EntryKind.story,
      createdAt: created,
      storyTitle: title.trim(),
      storyTeaser: teaser,
      tags: _tagsWithMood(moodLabel),
    );
  }

  JournalEntry addRichReflectionV6({
    required String thoughts,
    List<String> questions = const [],
    String? mirror,
    String riskLevel = 'none',
    String? answer,
    int? moodIcon,
    String? moodNote,
    String moodLabel = 'Neutral',
    String? id,
    DateTime? ts,
    String inputMode = 'text',
    int? inputDurationSec,
  }) {
    final created = (ts ?? DateTime.now()).toUtc();
    final joinedQuestions = _normalizeQuestions(questions);
    final ans = _cleanStr(answer);

    final tags = <String>{
      ..._tagsWithMood(moodLabel),
      if (riskLevel.trim().isNotEmpty) 'risk:$riskLevel',
      if ((moodNote ?? '').trim().isNotEmpty) 'moodNote:${moodNote!.trim()}',
      if (moodIcon != null) 'moodIcon:$moodIcon',
      if (inputMode.trim().isNotEmpty) 'input:$inputMode',
      if (inputDurationSec != null) 'inputDur:$inputDurationSec',
      if ((mirror ?? '').trim().isNotEmpty)
        'mirror:${_compactOneLine(mirror!.trim(), limit: 120)}',
    }.toList(growable: false);

    return addEntry(
      id: id ?? '',
      kind: EntryKind.reflection,
      createdAt: created,
      thoughtText: thoughts.trim().isEmpty ? null : thoughts.trim(),
      aiQuestion: joinedQuestions.isNotEmpty ? joinedQuestions : null,
      userAnswer: ans,
      tags: tags,
    );
  }

  bool appendAnswerAndMood(
    String id, {
    required String answer,
    int? moodIcon,
    String? moodNote,
    String moodLabel = 'Neutral',
    DateTime? ts,
  }) {
    final idx = _idIndex[id];
    if (idx == null) return false;

    final cur = _entries[idx];
    final tags = <String>{
      ...cur.tags,
      ..._tagsWithMood(moodLabel),
      if (moodIcon != null) 'moodIcon:$moodIcon',
      if ((moodNote ?? '').trim().isNotEmpty) 'moodNote:${moodNote!.trim()}',
    }.toList(growable: false);

    final updated = cur.copyWith(
      createdAt: (ts ?? DateTime.now()).toUtc(),
      userAnswer: answer.trim(),
      tags: tags,
    );

    _entries[idx] = updated;
    _afterMutation(sort: true, notify: true, persist: true);
    return true;
  }

  bool updateReflectionAnalysis(
    String id, {
    List<String>? questions,
    String? mirror,
    String? riskLevel, // 'none' | 'mild' | 'high'
    DateTime? ts,
  }) {
    final idx = _idIndex[id];
    if (idx == null) return false;

    final cur = _entries[idx];

    // aiQuestion aktualisieren (joined)
    String? nextQ = cur.aiQuestion;
    if (questions != null) {
      final joined = _normalizeQuestions(questions);
      nextQ = joined.isNotEmpty ? joined : null;
    }

    // Tags anreichern/aktualisieren
    final tags = <String>{...cur.tags};
    tags.removeWhere((t) => t.startsWith('mirror:') || t.startsWith('risk:'));
    if ((mirror ?? '').trim().isNotEmpty) {
      tags.add('mirror:${_compactOneLine(mirror!.trim(), limit: 120)}');
    }
    if ((riskLevel ?? '').trim().isNotEmpty) {
      tags.add('risk:${riskLevel!.trim()}');
    }

    final updated = cur.copyWith(
      createdAt: (ts ?? cur.createdAt).toUtc(),
      aiQuestion: nextQ,
      tags: tags.toList(growable: false),
    );

    _entries[idx] = updated;
    _afterMutation(sort: true, notify: true, persist: true);
    return true;
  }

  // ───────────────────────── Updates / Remove ─────────────────────────

  bool updateById(
    String id, {
    String? title,
    String? subtitle,
    String? thoughtText,
    String? aiQuestion,
    String? userAnswer,
    String? storyTitle,
    String? storyTeaser,
    List<String>? tags,
    EntryKind? kind,
    DateTime? createdAt,
    bool? hidden,
    String? sourceRef,
  }) {
    final idx = _idIndex[id];
    if (idx == null) return false;

    final cur = _entries[idx];
    final updated = cur.copyWith(
      title: title ?? cur.title,
      subtitle: subtitle ?? cur.subtitle,
      thoughtText: thoughtText ?? cur.thoughtText,
      aiQuestion: aiQuestion ?? cur.aiQuestion,
      userAnswer: userAnswer ?? cur.userAnswer,
      storyTitle: storyTitle ?? cur.storyTitle,
      storyTeaser: storyTeaser ?? cur.storyTeaser,
      tags: tags ?? cur.tags,
      kind: kind ?? cur.kind,
      createdAt: (createdAt ?? cur.createdAt).toUtc(),
      hidden: hidden ?? cur.hidden,
      sourceRef: sourceRef ?? cur.sourceRef,
    );

    _entries[idx] = updated;
    _afterMutation(sort: true, notify: true, persist: true);
    return true;
  }

  bool removeById(String id) {
    final idx = _idIndex[id];
    if (idx == null) return false;

    _entries.removeAt(idx);
    _reindex();

    _hiddenIds.remove(id);
    _afterMutation(sort: false, notify: true, persist: true);
    return true;
  }

  bool remove(String id) => removeById(id);

  int removeWhere(bool Function(JournalEntry e) test) {
    final before = _entries.length;
    _entries.removeWhere(test);
    _reindex();
    _afterMutation(sort: false, notify: true, persist: true);
    return before - _entries.length;
  }

  void clear() {
    _entries.clear();
    _idIndex.clear();
    _hiddenIds.clear();
    _afterMutation(sort: false, notify: true, persist: true);
  }

  void replaceAll(Iterable<JournalEntry> items, {bool persist = true}) {
    _entries
      ..clear()
      ..addAll(_dedupById(items));
    _reindex();
    _afterMutation(sort: true, notify: true, persist: persist);
  }

  void batch(void Function() run) {
    _batchDepth++;
    try {
      run();
    } finally {
      _batchDepth--;
      if (!_isBatching) {
        _afterMutation(sort: true, notify: true, persist: true);
      }
    }
  }

  // ───────────────────────── Timeline (lokale Tage) ─────────────────────────

  List<JournalDayGroup> groupedByDay({int? limitDays}) {
    final nowLocal = DateTime.now();
    final Map<int, List<JournalEntry>> buckets = {};

    for (final e in _entries) {
      final local = e.createdAt.toLocal();
      if (limitDays != null) {
        final daysDiff =
            nowLocal.difference(DateTime(local.year, local.month, local.day)).inDays;
        if (daysDiff > limitDays) continue;
      }
      final key = _dayKeyLocal(local);
      (buckets[key] ??= []).add(e);
    }

    final groups = <JournalDayGroup>[];
    final sortedKeys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final k in sortedKeys) {
      final day = _keyToLocalDay(k);
      final items = buckets[k]!..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      groups.add(JournalDayGroup(
        day: day,
        label: _dayLabel(day, nowLocal),
        entries: List.unmodifiable(items),
      ));
    }
    return groups;
  }

  List<JournalEntry> entriesForLocalDay(DateTime dayLocal) {
    final key = _dayKeyLocal(dayLocal);
    return _entries
        .where((e) => _dayKeyLocal(e.createdAt.toLocal()) == key)
        .toList(growable: false);
  }

  // ───────────────────────── Pro-Metriken ─────────────────────────

  int activeDaysCount({Duration window = const Duration(days: 30)}) {
    if (_entries.isEmpty) return 0;
    final nowLocal = DateTime.now();
    final cutLocal = nowLocal.subtract(window);
    final set = <int>{};

    for (final e in _entries) {
      final local = e.createdAt.toLocal();
      if (local.isBefore(cutLocal)) break;
      set.add(_dayKeyLocal(local));
    }
    return set.length;
  }

  int reflectionsCount({Duration? window}) {
    if (window == null) {
      return _entries.where((e) => e.kind == EntryKind.reflection).length;
    }
    final nowLocal = DateTime.now();
    final cutLocal = nowLocal.subtract(window);
    int n = 0;
    for (final e in _entries) {
      final local = e.createdAt.toLocal();
      if (local.isBefore(cutLocal)) break;
      if (e.kind == EntryKind.reflection && local.isAfter(cutLocal)) n++;
    }
    return n;
  }

  double averageMood({Duration window = const Duration(days: 30)}) {
    if (_entries.isEmpty) return 0;
    final nowLocal = DateTime.now();
    final cutLocal = nowLocal.subtract(window);
    double sum = 0;
    int n = 0;
    for (final e in _entries) {
      final local = e.createdAt.toLocal();
      if (local.isBefore(cutLocal)) break;
      final s = _moodScoreFromTags(e.tags);
      if (s != null) {
        sum += s;
        n++;
      }
    }
    return n == 0 ? 0 : double.parse((sum / n).toStringAsFixed(2));
  }

  List<double> moodSparkline({int days = 7}) {
    if (days <= 0) return const [];
    final nowLocal = DateTime.now();
    final start = DateTime(nowLocal.year, nowLocal.month, nowLocal.day)
        .subtract(Duration(days: days - 1));

    final bucketSum = <int, double>{};
    final bucketN = <int, int>{};

    for (final e in _entries) {
      final local = e.createdAt.toLocal();
      if (local.isBefore(start)) break;
      final key = _dayKeyLocal(local);
      final s = _moodScoreFromTags(e.tags);
      if (s == null) continue;
      bucketSum[key] = (bucketSum[key] ?? 0) + s;
      bucketN[key] = (bucketN[key] ?? 0) + 1;
    }

    final series = <double>[];
    for (int i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final key = _dayKeyLocal(d);
      final n = bucketN[key] ?? 0;
      final avg = n == 0 ? 0.0 : (bucketSum[key]! / n);
      series.add(double.parse(avg.toStringAsFixed(2)));
    }
    return series;
  }

  // ───────────────────────── Suche & Range ─────────────────────────

  List<JournalEntry> search(String query, {int limit = 50}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <JournalEntry>[];
    for (final e in _entries) {
      if (out.length >= limit) break;
      final hay = <String?>[
        e.title,
        e.subtitle,
        e.thoughtText,
        e.aiQuestion,
        e.userAnswer,
        e.storyTitle,
        e.storyTeaser,
        e.tags.join(' '),
      ].whereType<String>().join(' ').toLowerCase();
      if (hay.contains(q)) out.add(e);
    }
    return out;
  }

  List<JournalEntry> range({
    required DateTime fromLocal,
    required DateTime toLocal,
    bool reflectionsOnly = false,
    bool diariesOnly = false,
  }) {
    assert(!(reflectionsOnly && diariesOnly), 'reflectionsOnly XOR diariesOnly');
    final out = <JournalEntry>[];
    for (final e in _entries) {
      final l = e.createdAt.toLocal();
      if (l.isBefore(fromLocal)) break;
      final inWindow = !l.isBefore(fromLocal) && l.isBefore(toLocal);
      if (!inWindow) continue;
      if (reflectionsOnly && e.kind != EntryKind.reflection) continue;
      if (diariesOnly && e.kind != EntryKind.journal) continue;
      out.add(e);
    }
    return out;
  }

  // ───────────────────────── Export / Import ─────────────────────────

  String exportJsonString({bool pretty = true}) {
    final data = _entries.map((e) => e.toMap()).toList(growable: false);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  void importJsonString(String jsonString) {
    try {
      final raw = jsonDecode(jsonString);
      if (raw is! List) {
        throw const FormatException('Journal JSON muss eine Liste sein.');
      }
      final list = <JournalEntry>[];
      for (final item in raw) {
        try {
          if (item is Map) {
            list.add(JournalEntry.fromMap(item.cast<String, dynamic>()));
          } else if (item is String) {
            final m = jsonDecode(item);
            if (m is Map<String, dynamic>) {
              list.add(JournalEntry.fromMap(m));
            }
          }
        } catch (_) {/* einzelnes Item tolerant überspringen */}
      }
      replaceAll(list);
    } catch (e) {
      debugPrint('Journal import failed: $e');
    }
  }

  // ───────────────────────── Internals ─────────────────────────

  void _afterMutation({
    required bool sort,
    required bool notify,
    required bool persist,
  }) {
    if (sort) {
      _entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _reindex();
    } else if (_idIndex.length != _entries.length) {
      _reindex();
    }
    if (!_isBatching) {
      if (notify) notifyListeners();
      if (persist) _persistSafely();
    }
  }

  void _reindex() {
    _idIndex
      ..clear()
      ..addEntries(Iterable.generate(
        _entries.length,
        (i) => MapEntry(_entries[i].id, i),
      ));
  }

  static int _dayKeyLocal(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static DateTime _keyToLocalDay(int key) =>
      DateTime(key ~/ 10000, (key % 10000) ~/ 100, key % 100);

  static String _dayLabel(DateTime dayLocal, DateTime nowLocal) {
    final isToday = dayLocal.year == nowLocal.year &&
        dayLocal.month == nowLocal.month &&
        dayLocal.day == nowLocal.day;

    final yesterday =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day).subtract(const Duration(days: 1));

    final isYesterday = dayLocal.year == yesterday.year &&
        dayLocal.month == yesterday.month &&
        dayLocal.day == yesterday.day;

    if (isToday) return 'Heute';
    if (isYesterday) return 'Gestern';

    final dd = dayLocal.day.toString().padLeft(2, '0');
    final mm = dayLocal.month.toString().padLeft(2, '0');
    return '$dd.$mm.${dayLocal.year}';
  }

  static const Map<String, double> _moodMap = {
    'Wütend': -2.0,
    'Gestresst': -1.0,
    'Traurig': -1.0,
    'Neutral': 0.0,
    'Ruhig': 1.0,
    'Glücklich': 2.0,
  };

  static double? _moodScoreFromTags(List<String> tags) {
    // 1) moodScore:<n> priorisieren (0..4 → -2..+2)
    for (final t in tags) {
      final s = t.trim();
      if (s.startsWith('moodScore:')) {
        final n = int.tryParse(s.substring(10));
        if (n != null) return (-2 + (n.clamp(0, 4) * 1.0));
      }
    }
    // 2) mood:<Label>
    for (final t in tags) {
      final s = t.trim();
      if (s.startsWith('mood:')) {
        final label = s.substring(5);
        return _moodMap[label];
      }
    }
    return null;
  }

  static List<String> _tagsWithMood(String moodLabel) {
    final m = (moodLabel).toString().trim();
    return m.isEmpty ? const <String>[] : <String>['mood:$m'];
  }

  static String _cleanStr(String? v) => (v ?? '').trim().isEmpty ? '' : v!.trim();

  static String _firstChars(String s, int n) =>
      s.length <= n ? s : (s.substring(0, n).trimRight() + '…');

  static String _compactOneLine(String s, {int limit = 120}) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > limit) t = '${t.substring(0, limit - 1).trimRight()}…';
    return t;
  }

  List<JournalEntry> _dedupById(Iterable<JournalEntry> items) {
    final map = <String, JournalEntry>{};
    for (final e in items) {
      map[e.id] = e;
    }
    final list = map.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  String _norm(String? s) {
    if (s == null) return '';
    final t = s.trim();
    if (t.isEmpty) return '';
    return t.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _fingerprintFor({
    required EntryKind kind,
    String? thoughtText,
    String? aiQuestion,
    String? userAnswer,
    String? storyTitle,
    String? storyTeaser,
    List<String> tags = const <String>[],
  }) {
    String kindCode = kind == EntryKind.journal ? 'j'
                     : kind == EntryKind.reflection ? 'r' : 's';

    String core;
    if (kind == EntryKind.journal) {
      core = _norm(thoughtText);
    } else if (kind == EntryKind.reflection) {
      core = [_norm(aiQuestion), _norm(userAnswer)].where((e) => e.isNotEmpty).join('|');
    } else {
      core = [_norm(storyTitle), _norm(storyTeaser)].where((e) => e.isNotEmpty).join('|');
    }

    String moodKey = '';
    for (final t in tags) {
      if (t.startsWith('mood:') || t.startsWith('moodScore:')) {
        moodKey = t;
        break;
      }
    }

    return [kindCode, core, _norm(moodKey)].join('|');
  }

  JournalEntry? _findRecentDuplicate({
    required EntryKind kind,
    String? thoughtText,
    String? aiQuestion,
    String? userAnswer,
    String? storyTitle,
    String? storyTeaser,
    List<String> tags = const <String>[],
    required DateTime sinceUtc,
  }) {
    final fp = _fingerprintFor(
      kind: kind,
      thoughtText: thoughtText,
      aiQuestion: aiQuestion,
      userAnswer: userAnswer,
      storyTitle: storyTitle,
      storyTeaser: storyTeaser,
      tags: tags,
    );

    for (final e in _entries) {
      if (e.createdAt.isBefore(sinceUtc)) break;
      final efp = _fingerprintFor(
        kind: e.kind,
        thoughtText: e.thoughtText,
        aiQuestion: e.aiQuestion,
        userAnswer: e.userAnswer,
        storyTitle: e.storyTitle,
        storyTeaser: e.storyTeaser,
        tags: e.tags,
      );
      if (efp == fp) return e;
    }
    return null;
  }

  String _normalizeQuestions(List<String> qs) {
    if (qs.isEmpty) return '';
    final seen = <String>{};
    final clean = <String>[];
    for (final raw in qs) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      final key = _norm(s);
      if (seen.contains(key)) continue;
      seen.add(key);
      clean.add(s);
    }
    if (clean.isEmpty) return '';
    if (clean.length == 1) return clean.first;
    return clean.map((e) => '– $e').join('\n');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gruppierungs-Datenträger (öffentlich für Features/Widgets)
class JournalDayGroup {
  final DateTime day;               // lokaler Tagesstart (kein UTC!)
  final String label;               // „Heute“ / „Gestern“ / „TT.MM.JJJJ“
  final List<JournalEntry> entries; // DESC nach createdAt (UTC) sortiert

  const JournalDayGroup({
    required this.day,
    required this.label,
    required this.entries,
  });
}

// Interner Datenträger für listVisible() UI-Gruppierung
class _DayGroup {
  final DateTime dateOnly; // Mit 00:00:00
  final List<JournalEntry> items;
  const _DayGroup(this.dateOnly, this.items);
}
