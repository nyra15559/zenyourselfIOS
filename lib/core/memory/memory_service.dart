// [PATCHED] lib/core/memory/memory_service.dart — v7.2.3
// ZenYourself — MemoryService (Lokales Kontext-Gedächtnis, Ghost-Mode by default)
// ============================================================================
// MERGE SIGNAL • v7.2.3 (Hotfix)
// • Fix: Tippfehler in recall()-Scoring korrigiert: startswith → startsWith (Dart String API).
// • Beibehaltung aller v7.2.2-Änderungen (K2/K3/K4/K5 Logik, Caches, Export/Bridge).
// ============================================================================

library memory_service;

import 'dart:convert' show jsonEncode, jsonDecode, utf8;
import 'dart:math' as math;

import '../models/insight_models.dart' show MemoryFact, FactType, Facet;
import 'memory_entry.dart';
import 'memory_mapper.dart';
import 'memory_store.dart';

// ---- kleine Convenience-Extension ------------------------------------------
extension _TakeLastList<T> on List<T> {
  List<T> takeLast(int n) {
    if (n <= 0) return <T>[];
    if (length <= n) return List<T>.from(this);
    return sublist(length - n);
  }
}

// -----------------------------------------------------------------------------
// Context-Hint (sync, klein)
// -----------------------------------------------------------------------------

class MemoryContextHint {
  final List<String>? facets;
  final List<String>? tags;
  final List<String>? topics;

  // Identity/Profile (rein lokal)
  final String? identityName;
  final String? profileUserName;
  final List<String>? profileNicknames;

  // Pins
  final String? activeFacet;
  final String? topicPin;

  const MemoryContextHint({
    this.facets,
    this.tags,
    this.topics,
    this.identityName,
    this.profileUserName,
    this.profileNicknames,
    this.activeFacet,
    this.topicPin,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (facets != null && facets!.isNotEmpty) 'facets': facets,
        if (tags != null && tags!.isNotEmpty) 'tags': tags,
        if (topics != null && topics!.isNotEmpty) 'topics': topics,
        if ((identityName ?? '').toString().trim().isNotEmpty)
          'identity': {'name': identityName!.trim()},
        if ((profileUserName ?? '').toString().trim().isNotEmpty ||
            (profileNicknames?.isNotEmpty ?? false))
          'profile': <String, dynamic>{
            if ((profileUserName ?? '').toString().trim().isNotEmpty)
              'user_name': profileUserName!.trim(),
            if (profileNicknames != null && profileNicknames!.isNotEmpty)
              'nicknames': profileNicknames,
          },
        if ((activeFacet ?? '').toString().trim().isNotEmpty)
          'active_facet': activeFacet!.trim(),
        if ((topicPin ?? '').toString().trim().isNotEmpty)
          'topic_pin': topicPin!.trim(),
      };
}

// -----------------------------------------------------------------------------
// Location (PII-schonend)
// -----------------------------------------------------------------------------

class LocationBreadcrumb {
  final String? label;
  final double? lat;
  final double? lon;
  final double? accuracy;
  final String? source;
  final DateTime tsUtc;

  const LocationBreadcrumb({
    this.label,
    this.lat,
    this.lon,
    this.accuracy,
    this.source,
    required this.tsUtc,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'kind': 'location',
        if ((label ?? '').trim().isNotEmpty) 'label': label!.trim(),
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (accuracy != null) 'accuracy': accuracy,
        if ((source ?? '').trim().isNotEmpty) 'source': source!.trim(),
        'ts': tsUtc.toIso8601String(),
      };

  static LocationBreadcrumb? fromMap(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    DateTime? _ts(dynamic x) {
      try {
        final s = x?.toString().trim();
        if (s == null || s.isEmpty) return null;
        return DateTime.parse(s).toUtc();
      } catch (_) {
        return null;
      }
    }

    double? _num(dynamic x) {
      if (x is num) return x.toDouble();
      if (x is String) return double.tryParse(x.trim());
      return null;
    }

    final ts = _ts(m['ts']) ?? DateTime.now().toUtc();
    return LocationBreadcrumb(
      label: m['label']?.toString(),
      lat: _num(m['lat']),
      lon: _num(m['lon']),
      accuracy: _num(m['accuracy']),
      source: m['source']?.toString(),
      tsUtc: ts,
    );
  }
}

// -----------------------------------------------------------------------------
// KUTSCHE 1/2 — Mood (dual)
// -----------------------------------------------------------------------------

class MoodEntry {
  final String id;
  final DateTime tsUtc;
  final int mental; // 1..5
  final int physical; // 1..5
  final String? note;

  MoodEntry({
    required this.id,
    required this.tsUtc,
    required this.mental,
    required this.physical,
    this.note,
  });

  String get dayKey => MemoryService._ymd(tsUtc);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'kind': 'mood',
        'id': id,
        'ts': tsUtc.toIso8601String(),
        'date': MemoryService._ymd(tsUtc),
        'mental': mental,
        'physical': physical,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      };

  static MoodEntry? fromMap(dynamic v) {
    if (v is! Map) return null;
    try {
      final m = Map<String, dynamic>.from(v);
      final tsRaw =
          (m['ts'] ?? m['date'] ?? m['created_at'] ?? m['createdAt'])?.toString();
      final ts = (tsRaw == null || tsRaw.trim().isEmpty)
          ? DateTime.now().toUtc()
          : DateTime.tryParse(tsRaw)?.toUtc() ?? DateTime.now().toUtc();
      int? _int(dynamic x) {
        if (x is int) return x;
        if (x is num) return x.toInt();
        if (x is String) return int.tryParse(x.trim());
        return null;
      }

      final mentalRaw = _int(m['mental'] ?? m['mind'] ?? m['m']) ?? _int(m['value']) ?? 3;
      final physicalRaw = _int(m['physical'] ?? m['body'] ?? m['p']) ?? 3;

      final id = (m['id'] ?? 'm_${ts.millisecondsSinceEpoch}').toString();
      final note = (m['note'] ?? m['line'])?.toString();
      return MoodEntry(
        id: id,
        tsUtc: ts,
        mental: MemoryService._clampInt(mentalRaw, 1, 5),
        physical: MemoryService._clampInt(physicalRaw, 1, 5),
        note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      );
    } catch (_) {
      return null;
    }
  }
}

class MoodPoint {
  final String date; // YYYY-MM-DD
  final int mental; // 1..5
  final int physical; // 1..5

  const MoodPoint({required this.date, required this.mental, required this.physical});

  double get avg => ((mental + physical) / 2.0);

  Map<String, dynamic> toJson() => {
        'date': date,
        'mental': mental,
        'physical': physical,
        'avg': double.parse(avg.toStringAsFixed(avg % 1 == 0 ? 0 : 1)),
      };

  static MoodPoint fromEntry(MoodEntry e) =>
      MoodPoint(date: MemoryService._ymd(e.tsUtc), mental: e.mental, physical: e.physical);
}

class MoodTrend {
  final int days;
  final double mentalDelta;
  final double physicalDelta;
  final String dir; // up|down|flat
  const MoodTrend({required this.days, required this.mentalDelta, required this.physicalDelta, required this.dir});
  Map<String, dynamic> toJson() => {
        'days': days,
        'mental_delta': MemoryService._round1(mentalDelta),
        'physical_delta': MemoryService._round1(physicalDelta),
        'dir': dir,
      };
}

// -----------------------------------------------------------------------------
// KUTSCHE 3 — Timeline
// -----------------------------------------------------------------------------

class TimelineMarker {
  final String id;
  final DateTime tsUtc;
  final String topic; // kompakt (z. B. "arbeit")
  final String? tag;  // "arbeit|schlaf|familie|selbstwert"
  final int valence;  // -2..+2
  final String? source; // "user" | "panda" | "worker" | "journal"
  final int count; // Merge-Zähler

  TimelineMarker({
    required this.id,
    required this.tsUtc,
    required this.topic,
    this.tag,
    required this.valence,
    this.source,
    this.count = 1,
  });

  String get dayKey => MemoryService._ymd(tsUtc);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'kind': 'timeline',
        'id': id,
        'ts': tsUtc.toIso8601String(),
        'date': MemoryService._ymd(tsUtc),
        'topic': topic,
        if ((tag ?? '').trim().isNotEmpty) 'tag': tag!.trim(),
        'valence': valence,
        if ((source ?? '').trim().isNotEmpty) 'source': source!.trim(),
        'count': count,
      };

  static TimelineMarker? fromMap(dynamic v) {
    if (v is! Map) return null;
    try {
      final m = Map<String, dynamic>.from(v);
      final tsRaw =
          (m['ts'] ?? m['date'] ?? m['created_at'] ?? m['createdAt'])?.toString();
      final ts = (tsRaw == null || tsRaw.trim().isEmpty)
          ? DateTime.now().toUtc()
          : DateTime.tryParse(tsRaw)?.toUtc() ?? DateTime.now().toUtc();

      String topic = (m['topic'] ?? m['label'] ?? '').toString().trim();
      if (topic.isEmpty) return null;
      final tag = (m['tag'] ?? '').toString().trim().isEmpty ? null : m['tag'].toString().trim();

      int _val(dynamic x) {
        if (x is int) return x;
        if (x is num) return x.toInt();
        if (x is String) return int.tryParse(x.trim()) ?? 0;
        return 0;
      }

      final id = (m['id'] ?? 't_${ts.millisecondsSinceEpoch}').toString();
      final valence = MemoryService._clampValence(_val(m['valence']));
      final source =
          (m['source'] ?? '').toString().trim().isEmpty ? null : m['source'].toString().trim();
      final count = _val(m['count']);
      return TimelineMarker(
        id: id,
        tsUtc: ts,
        topic: topic,
        tag: tag,
        valence: valence,
        source: source,
        count: count <= 0 ? 1 : count,
      );
    } catch (_) {
      return null;
    }
  }
}

// -----------------------------------------------------------------------------
// KUTSCHE 5 — Recall
// -----------------------------------------------------------------------------

class RecallSummary {
  final int days;
  final Map<String, dynamic> trend; // {dir, delta}
  final List<String> topTopics; // ≤3
  const RecallSummary({required this.days, required this.trend, required this.topTopics});
  Map<String, dynamic> toJson() => {
        'days': days,
        'trend': {
          'dir': (trend['dir'] ?? 'flat').toString(),
          'delta': MemoryService._round1((trend['delta'] as num? ?? 0).toDouble()),
        },
        'top_topics': topTopics.take(3).toList(growable: false),
      };
}

// --------------------------------- INTERNAL ----------------------------------

class _InsightLite {
  final String? id;
  final String? line;
  final double? score;
  final DateTime tsUtc;
  const _InsightLite({this.id, this.line, this.score, required this.tsUtc});

  static _InsightLite? fromMap(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final line = (m['line'] ?? m['text'] ?? m['value'] ?? '').toString();
    if (line.trim().isEmpty) return null;
    double? score;
    final rawScore = m['score'] ?? m['confidence'] ?? m['rank'];
    if (rawScore is num) score = rawScore.toDouble();
    if (rawScore is String) score = double.tryParse(rawScore);
    final tsRaw = (m['ts'] ?? m['created_at'] ?? m['createdAt'] ?? m['date'])?.toString();
    final ts = (tsRaw == null || tsRaw.trim().isEmpty)
        ? DateTime.now().toUtc()
        : DateTime.tryParse(tsRaw)?.toUtc() ?? DateTime.now().toUtc();
    return _InsightLite(id: (m['id'] ?? '').toString().isEmpty ? null : m['id'].toString(), line: line.trim(), score: score, tsUtc: ts);
  }
}

class _LastMood {
  final String? value;
  final DateTime? date;
  const _LastMood(this.value, this.date);
}

// -----------------------------------------------------------------------------
// MemoryService
// -----------------------------------------------------------------------------

class MemoryService {
  MemoryService._internal();
  static final MemoryService instance = MemoryService._internal();

  final MemoryStore _store = MemoryStore.instance;

  // Flags
  bool _enabled = true;      // lokales Gedächtnis
  bool _shareEnabled = false; // Therapist-Mode / Teilen erlaubt

  // Memory-Bridge Aktivierung + Trial-Fenster
  bool _memoryActive = true;
  DateTime? _memoryExpiryUtc;

  bool get enabled => _enabled;
  bool get shareEnabled => _shareEnabled;
  bool get memoryActive => _memoryActive && !_isExpired();
  bool get isActive => memoryActive;
  DateTime? get memoryExpiryUtc => _memoryExpiryUtc;

  // Caches
  MemoryContextHint? _lastHint;
  DateTime? _lastHintTs;

  List<String>? _latestTopicsCache;
  DateTime? _latestTopicsTs;
  List<Facet>? _topFacetsCache;
  DateTime? _topFacetsTs;

  String? _identityNameCache;
  String? get identityNameSync => _identityNameCache;
  String? _profileUserNameCache;
  List<String>? _profileNicknamesCache;
  bool? _greetByNameCache;

  String? _lastLocationLabelCache;
  DateTime? _lastLocationTsCache;

  // Opt-Keys
  static const String _kLastTopic = 'last.topic';
  static const String _kLastMood = 'last.mood';
  static const String _kLastDate = 'last.date';

  // Mood Opt-Keys
  static const String _kMoodLastMental = 'mood.last.mental';
  static const String _kMoodLastPhysical = 'mood.last.physical';
  static const String _kMoodLastDate = 'mood.last.date';

  // Timeline Konstanten
  static const Set<String> _knownTags = {'arbeit', 'schlaf', 'familie', 'selbstwert'};
  static const int _timelineExportDays = 3;
  static const int _timelinePerDayExport = 1;
  static const int _timelineCapPerDay = 3;
  static const int _timelineCapPerTagPerDay = 2;
  static const int _timelineHardCapTotal = 300;

  // Insights (K4)
  static const int _insightDedupDaysPrimary = 30;
  static const int _insightDedupDaysFallback = 90;
  static const int _insightsExportDays = 14;
  static const int _insightsExportMax = 2;

  bool get profileHasNicknamesSync => (_profileNicknamesCache?.isNotEmpty ?? false);
  String? get profileUserNameSync => _profileUserNameCache;
  List<String> get profileNicknamesSync =>
      List.unmodifiable(_profileNicknamesCache ?? const <String>[]);

  String? latestUserNameSync({bool preferIdentity = true}) {
    final a = preferIdentity ? _identityNameCache : _profileUserNameCache;
    return (a != null && a.trim().isNotEmpty)
        ? a
        : (preferIdentity ? _profileUserNameCache : _identityNameCache);
  }

  String? latestNicknameSync() =>
      (_profileNicknamesCache != null && _profileNicknamesCache!.isNotEmpty)
          ? _profileNicknamesCache!.first
          : null;

  bool get canShareNameSync =>
      _shareEnabled && (_greetByNameCache == true) && ((_identityNameCache ?? '').trim().isNotEmpty);

  ({String? name, bool greetByName}) greetingNameSync({bool requireConsent = false}) {
    final name = (_identityNameCache ?? '').trim().isEmpty ? null : _identityNameCache!.trim();
    final greet = _greetByNameCache == true;
    final ok = requireConsent ? (greet && _shareEnabled) : greet;
    return (name: ok ? name : null, greetByName: ok);
  }

  Future<({String? name, bool greetByName})> ensureGreetingNameLoaded(
      {bool requireConsent = false}) async {
    if ((_identityNameCache ?? '').trim().isEmpty || _greetByNameCache == null) {
      final r = await loadGreetingName();
      return requireConsent
          ? ((r.greetByName && _shareEnabled) ? r : (name: null, greetByName: false))
          : r;
    }
    final r = (name: _identityNameCache, greetByName: _greetByNameCache == true);
    return requireConsent
        ? ((r.greetByName && _shareEnabled) ? r : (name: null, greetByName: false))
        : r;
  }

  // TTLs
  static const _hintTtlDays = 14;
  static const _topicsTtlSec = 30;
  static const _facetsTtlSec = 30;

  // Storage-Keys
  static const String _kIdentityName = 'identity.name';
  static const String _kIdentityGreetByName = 'identity.greet_by_name';
  static const String _kShareEnabled = 'share_enabled';
  static const String _kMemoryActive = 'memory.active';
  static const String _kMemoryExpiry = 'memory.expiry_utc';
  static const String _kProfileUserName = 'profile.user_name';
  static const String _kProfileNicknames = 'profile.nicknames'; // JSON-Array
  static const String _kGeoLastLabel = 'geo.last_label';
  static const String _kGeoLastTs = 'geo.last_ts';
  static const String _kGeoLastLat = 'geo.last_lat';
  static const String _kGeoLastLon = 'geo.last_lon';
  static const String _kGeoLastAcc = 'geo.last_acc';

  // ---------------- Lifecycle / Flags ----------------------------------------

  Future<void> init() async {
    try {
      await _store.init();
      _enabled = _store.isEnabled;

      final se = await _getOptBool(_kShareEnabled);
      _shareEnabled = se ?? _tryReadShareEnabledReflective() ?? false;

      await _initMemoryBridgeWindow();

      // Identity/Profile vorladen
      try {
        final n = await _getOptString(_kIdentityName);
        _identityNameCache = (n == null || n.trim().isEmpty) ? null : _cap(n.trim());
      } catch (_) {}
      try {
        final p = await _getOptString(_kProfileUserName);
        _profileUserNameCache = (p == null || p.trim().isEmpty) ? null : _cap(p.trim());
      } catch (_) {}
      try {
        final list = await _getOptStringList(_kProfileNicknames);
        _profileNicknamesCache = (list == null || list.isEmpty)
            ? null
            : list
                .map((e) => e.toString().trim())
                .where((e) => e.trim().isNotEmpty)
                .map(_cap)
                .toList(growable: false);
      } catch (_) {}
      try {
        final greet = await _getOptBool(_kIdentityGreetByName);
        _greetByNameCache = greet ?? false;
      } catch (_) {}

      // Letzter Ort
      try {
        _lastLocationLabelCache = await _getOptString(_kGeoLastLabel);
        final ts = await _getOptString(_kGeoLastTs);
        _lastLocationTsCache =
            (ts == null || ts.trim().isEmpty) ? null : DateTime.tryParse(ts)?.toUtc();
      } catch (_) {}
    } catch (_) {
      // defaults
    }
  }

  Future<void> warmup() async {
    try {
      await init();
      try {
        await topFacets(limit: 8);
        await latestTopics(limit: 6);
      } catch (_) {}
    } catch (_) {}
  }

  void preload() {
    // fire-and-forget
    // ignore: discarded_futures
    warmup();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      await _store.setEnabled(v);
    } catch (_) {}
  }

  Future<void> setShareEnabled(bool v) async {
    _shareEnabled = v;
    try {
      await _setOptBool(_kShareEnabled, v);
    } catch (_) {}
    if (v && ((_identityNameCache ?? '').trim().isEmpty || _greetByNameCache == null)) {
      try {
        await ensureGreetingNameLoaded();
      } catch (_) {}
    }
  }

  // -------- Memory-Bridge Window (Trial / Premium) ---------------------------

  Future<void> _initMemoryBridgeWindow() async {
    try {
      final active = await _getOptBool(_kMemoryActive);
      final expIso = await _getOptString(_kMemoryExpiry);

      if (active == null && (expIso == null || expIso.trim().isEmpty)) {
        // Erststart → 7-Tage-Trial
        _memoryActive = true;
        _memoryExpiryUtc = DateTime.now().toUtc().add(const Duration(days: 7));
        await _setOptBool(_kMemoryActive, true);
        await _setOptString(_kMemoryExpiry, _memoryExpiryUtc!.toIso8601String());
        return;
      }

      _memoryActive = active ?? true;
      _memoryExpiryUtc =
          (expIso == null || expIso.trim().isEmpty) ? null : DateTime.tryParse(expIso)?.toUtc();

      // Expiry prüfen – abgelaufen → deaktivieren
      if (_memoryActive && _isExpired()) {
        _memoryActive = false;
        try {
          await _setOptBool(_kMemoryActive, false);
        } catch (_) {}
      }
    } catch (_) {
      _memoryActive = true;
      _memoryExpiryUtc ??= DateTime.now().toUtc().add(const Duration(days: 7));
    }
  }

  bool _isExpired() {
    try {
      if (_memoryExpiryUtc == null) return false;
      return DateTime.now().toUtc().isAfter(_memoryExpiryUtc!);
    } catch (_) {
      return false;
    }
  }

  Future<void> setMemoryActive(bool active, {DateTime? expiryUtc, Duration? trial}) async {
    _memoryActive = active;
    if (expiryUtc != null) {
      _memoryExpiryUtc = expiryUtc.toUtc();
      try {
        await _setOptString(_kMemoryExpiry, _memoryExpiryUtc!.toIso8601String());
      } catch (_) {}
    } else if (trial != null) {
      _memoryExpiryUtc = DateTime.now().toUtc().add(trial);
      try {
        await _setOptString(_kMemoryExpiry, _memoryExpiryUtc!.toIso8601String());
      } catch (_) {}
    }
    try {
      await _setOptBool(_kMemoryActive, _memoryActive);
    } catch (_) {}
  }

  Future<void> setMemoryExpiry(DateTime? expiryUtc) async {
    _memoryExpiryUtc = expiryUtc?.toUtc();
    if (_memoryExpiryUtc == null) {
      try {
        final dyn = _store as dynamic;
        final r = dyn.removeOpt?.call(_kMemoryExpiry);
        if (r is Future) await r;
      } catch (_) {}
    } else {
      await _setOptString(_kMemoryExpiry, _memoryExpiryUtc!.toIso8601String());
    }
    if (_memoryActive && _isExpired()) {
      await setMemoryActive(false);
    }
  }

  Future<void> ensureTrialWindow({int days = 7}) async {
    if (_memoryExpiryUtc == null) {
      await setMemoryActive(true, trial: Duration(days: days));
    }
  }

  // ---------------- Identity/Profile -----------------------------------------

  Future<void> saveIdentityName(String name, {bool greetByName = true}) async {
    try {
      final n = _cap(name.trim());
      if (n.isEmpty) return;
      _identityNameCache = n;
      _greetByNameCache = greetByName;
      await _setOptString(_kIdentityName, n);
      await _setOptBool(_kIdentityGreetByName, greetByName);

      if ((_profileUserNameCache == null || _profileUserNameCache!.trim().isEmpty) &&
          greetByName == true) {
        await saveProfileUserName(n);
      }
    } catch (_) {}
  }

  Future<void> saveProfileUserName(String name) async {
    try {
      final n = _cap(name.trim());
      if (n.isEmpty) return;
      _profileUserNameCache = n;
      await _setOptString(_kProfileUserName, n);
    } catch (_) {}
  }

  Future<void> addNickname(String nickname) async {
    try {
      String n = _cap(nickname.trim());
      if (n.isEmpty || n.length < 2) return;
      final list = [...(_profileNicknamesCache ?? const <String>[])];
      final key = n.toLowerCase();
      if (!list.map((e) => e.toLowerCase()).contains(key)) {
        list.insert(0, n);
      }
      while (list.length > 5) {
        list.removeLast();
      }
      _profileNicknamesCache = list;
      await _setOptStringList(_kProfileNicknames, list);
    } catch (_) {}
  }

  Future<void> setGreetingConsent(bool greetByName) async {
    try {
      _greetByNameCache = greetByName;
      await _setOptBool(_kIdentityGreetByName, greetByName);
    } catch (_) {}
  }

  Future<void> forgetIdentityName() async {
    try {
      _identityNameCache = null;
      _greetByNameCache = false;
      final dyn = _store as dynamic;
      try {
        final r = dyn.removeOpt?.call(_kIdentityName);
        if (r is Future) await r;
      } catch (_) {}
      try {
        final r = dyn.setOptBool?.call(_kIdentityGreetByName, false);
        if (r is Future) await r;
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> forgetProfileNames() async {
    try {
      _profileUserNameCache = null;
      _profileNicknamesCache = null;

      final dyn = _store as dynamic;
      try {
        final r = dyn.removeOpt?.call(_kProfileUserName);
        if (r is Future) await r;
      } catch (_) {}
      try {
        final r = dyn.removeOpt?.call(_kProfileNicknames);
        if (r is Future) await r;
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> forgetAllPII() async {
    try {
      final dyn = _store as dynamic;
      try {
        final r = dyn.forgetAllPII?.call();
        if (r is Future) await r;
        _identityNameCache = null;
        _profileUserNameCache = null;
        _profileNicknamesCache = null;
        _greetByNameCache = false;
        return;
      } catch (_) {}
      await forgetIdentityName();
      await forgetProfileNames();
    } catch (_) {}
  }

  Future<({String? name, bool greetByName})> loadGreetingName() async {
    try {
      final name = await _getOptString(_kIdentityName);
      final greet = await _getOptBool(_kIdentityGreetByName) ?? false;
      final trimmed = (name?.trim().isEmpty ?? true) ? null : _cap(name!.trim());
      _identityNameCache = trimmed;
      _greetByNameCache = greet;
      return (name: trimmed, greetByName: greet);
    } catch (_) {
      return (name: _identityNameCache, greetByName: _greetByNameCache == true);
    }
  }

  Future<String?> loadIdentityName() async {
    try {
      final n = await _getOptString(_kIdentityName);
      _identityNameCache = (n == null || n.trim().isEmpty) ? null : _cap(n.trim());
      return _identityNameCache;
    } catch (_) {
      return _identityNameCache;
    }
  }

  Future<void> maybeRespectAnonFromText(String text) async {
    if (!_enabled) return;
    try {
      final t = text.toLowerCase();
      final anonPhrases = <RegExp>[
        RegExp(r'\bheute\s+lieber\s+anonym\b'),
        RegExp(r'\bheute\s+ohne\s+name(n)?\b'),
        RegExp(r'\bkein(en)?\s+namen\s+verwenden\b'),
        RegExp(r'\bnicht\s+mit\s+namen\s+ansprechen\b'),
      ];
      final wantsAnon = anonPhrases.any((re) => re.hasMatch(t));
      if (wantsAnon) {
        await setGreetingConsent(false);
      }
    } catch (_) {}
  }

  Future<void> learnNameFromText(String text, {bool greetByName = true}) async {
    if (!_enabled) return;
    try {
      final t = text.trim();
      if (t.isEmpty) return;

      final lower = t.toLowerCase();
      String? candidate;

      final patterns = <RegExp>[
        RegExp(r"\bich\s+hei(?:ß|ss|s|se)\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bmein\s+name\s+ist\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bmein\s+vorname\s+ist\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bich\s+bin\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bnenn\s+mich\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bman\s+nennt\s+mich\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bdu\s+kannst\s+mich\s+([a-zäöüß\-\' ]+)\s+nennen", caseSensitive: false),
        RegExp(r"\bja(?:,\s*)?\s*einfach\s+([a-zäöüß\-\' ]+)\b", caseSensitive: false),
      ];

      for (final re in patterns) {
        final m = re.firstMatch(lower);
        if (m != null && m.groupCount >= 1) {
          candidate = m.group(1);
          break;
        }
      }

      candidate ??= () {
        final m = RegExp(r"\b(hei(?:ß|ss|s|se)|name\s+ist)\b\s+([a-zäöüß\-\' ]+)")
            .firstMatch(lower);
        return (m != null && m.groupCount >= 2) ? m.group(2) : null;
      }();

      if (candidate == null) return;

      final firstToken = candidate.split(RegExp(r"\s+")).first;

      String clean = firstToken.replaceAll(RegExp(r"[^a-zA-ZäöüÄÖÜß\-' ]"), '');
      clean = clean.replaceAll(' ', '');
      if (clean.length < 2) return;
      clean = _cap(clean);

      const banned = {'einfach', 'ja', 'okay', 'ok', 'nein', 'anonym', 'und', 'uund'};
      if (banned.contains(clean.toLowerCase())) return;

      await saveIdentityName(clean, greetByName: greetByName);
      await saveProfileUserName(clean);
    } catch (_) {}
  }

  // ---------------- Konversation & Worker-Save --------------------------------

  Future<void> saveFromWorker(dynamic workerResponse, {String? source}) async {
    if (!_enabled) return;
    try {
      if (workerResponse is! Map) return;
      final map = Map<String, dynamic>.from(workerResponse);

      // 1) Standard-Mapper → Conversation/Facets (leicht)
      final entry = MemoryMapper.fromWorker(map); // nullable
      if (entry != null) {
        await _store.save(entry);
        if (entry.contextFacets.isNotEmpty) {
          final sorted = [...entry.contextFacets]
            ..sort((a, b) {
              final byHits = (b.hits).compareTo(a.hits);
              if (byHits != 0) return byHits;
              return (a.label).toLowerCase().compareTo((b.label).toLowerCase());
            });
          final facetKeys =
              sorted.map((f) => f.key).where((s) => s.trim().isNotEmpty).toList();
          final facetLabels =
              sorted.map((f) => f.label).where((s) => s.trim().isNotEmpty).toList();

          _lastHint = MemoryContextHint(
            facets: facetKeys.take(6).toList(growable: false),
            tags: null,
            topics: facetLabels.take(6).toList(growable: false),
          );
          _lastHintTs = DateTime.now();
        }
      }

      // 2) Facts & diverse Saves aus memories_to_save (K4+)
      await _ingestMemoriesToSave(map, allowIdentity: true);

      // 3) last.topic/mood/date Pins aus Root (understanding/flow/last)
      String? _topicFromUnderstanding(Map<String, dynamic> root) {
        try {
          final u = root['understanding'];
          if (u is Map) {
            final m = Map<String, dynamic>.from(u);
            final t = (m['topic_shift'] ?? m['topicShift'] ?? m['topic'])?.toString().trim();
            if (t != null && t.isNotEmpty) return t;
          }
          final flat =
              (root['understanding.topic_shift'] ?? root['understanding_topic_shift'])
                  ?.toString()
                  .trim();
          if (flat != null && flat.isNotEmpty) return flat;
        } catch (_) {}
        return null;
      }

      String? lastTopic = _topicFromUnderstanding(map);

      if ((lastTopic ?? '').isEmpty) {
        try {
          final list = (map['memories_to_save'] as List?) ??
              (map['memoriesToSave'] as List?) ??
              const [];
          for (final it in list) {
            if (it is Map) {
              final m = Map<String, dynamic>.from(it);
              final t =
                  (m['topic'] ?? m['last_topic'] ?? m['label'])?.toString().trim();
              if (t != null && t.isNotEmpty) {
                lastTopic = t;
                break;
              }
            }
          }
        } catch (_) {}
      }

      if ((lastTopic ?? '').isNotEmpty) {
        await _setOptString(_kLastTopic, lastTopic!.trim());
        // Sync-Pin
        final base = _lastHint;
        _lastHint = MemoryContextHint(
          facets: base?.facets,
          tags: base?.tags,
          topics: base?.topics,
          identityName: base?.identityName,
          profileUserName: base?.profileUserName,
          profileNicknames: base?.profileNicknames,
          activeFacet: base?.activeFacet,
          topicPin: lastTopic!.trim(),
        );
        _lastHintTs ??= DateTime.now();
        await _setOptString(_kLastDate, _ymd(DateTime.now().toUtc()));
      }

      String? _moodFromFlow(Map<String, dynamic> root) {
        try {
          final f = root['flow'];
          if (f is Map) {
            final m = Map<String, dynamic>.from(f);
            final v =
                (m['mood_prompt'] ?? m['moodPrompt'] ?? m['mood'])?.toString().trim();
            if (v != null && v.isNotEmpty) return v;
          }
          final flat = (root['mood'] ?? root['flow.mood_prompt'])?.toString().trim();
          if (flat != null && flat.isNotEmpty) return flat;
        } catch (_) {}
        return null;
      }

      final moodVal = _moodFromFlow(map);
      if ((moodVal ?? '').isNotEmpty) {
        await _setOptString(_kLastMood, moodVal!.trim());
        await _setOptString(_kLastDate, _ymd(DateTime.now().toUtc()));
      }

      // 4) Geo & Timeline tolerant übernehmen
      await _ingestGeoIfPresent(map);
      await _ingestTimelineIfPresent(map);

      _invalidateSoftCaches();
    } catch (_) {
      // still
    }
  }

  Future<void> saveUserTurn(String text, {Map<String, dynamic>? meta}) async {
    await _saveLine('user', text, meta: meta);
    try {
      await _maybeAutoTimelineFromText(role: 'user', text: text);
    } catch (_) {}
  }

  Future<void> savePandaTurn(String text, {Map<String, dynamic>? meta}) async {
    await _saveLine('panda', text, meta: meta);
    try {
      await _maybeAutoTimelineFromText(role: 'panda', text: text, pandaRelaxed: true);
    } catch (_) {}
  }

  Future<void> recordAcknowledge(Map<String, dynamic> ack) async {
    if (!_enabled) return;
    try {
      final safeAck = Map<String, dynamic>.from(ack);
      final dyn = _store as dynamic;

      try {
        final r = dyn.recordAcknowledge(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {}

      try {
        final r = dyn.saveAck?.call(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {}

      safeAck.putIfAbsent('kind', () => 'ack');
      safeAck.putIfAbsent('ts', () => DateTime.now().toUtc().toIso8601String());
      try {
        final r = dyn.saveMap?.call(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {}
      try {
        final r = dyn.save?.call(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _saveLine(String role, String text, {Map<String, dynamic>? meta}) async {
    if (!_enabled) return;
    try {
      final m = meta ?? const <String, dynamic>{};
      final dyn = _store as dynamic;

      try {
        if (role == 'user') {
          final r = dyn.saveUserLine(text, m);
          if (r is Future) await r;
          return;
        } else {
          final r = dyn.savePandaLine(text, m);
          if (r is Future) await r;
          return;
        }
      } catch (_) {}

      try {
        final r = dyn.appendLine(role, text, m);
        if (r is Future) await r;
        return;
      } catch (_) {}
      try {
        final r = dyn.saveLine(role: role, text: text, meta: m);
        if (r is Future) await r;
        return;
      } catch (_) {}

      final map = {
        'kind': 'line',
        'role': role,
        'text': text,
        'meta': m,
        'ts': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        final r = dyn.saveMap(map);
        if (r is Future) await r;
        return;
      } catch (_) {}
      try {
        final r = dyn.save(map);
        if (r is Future) await r;
        return;
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> clear() async {
    _lastHint = null;
    _lastHintTs = null;
    _latestTopicsCache = null;
    _latestTopicsTs = null;
    _topFacetsCache = null;
    _topFacetsTs = null;
    _identityNameCache = null;
    _profileUserNameCache = null;
    _profileNicknamesCache = null;
    _greetByNameCache = null;
    _lastLocationLabelCache = null;
    _lastLocationTsCache = null;
    try {
      await _store.clearAll();
    } catch (_) {}
  }

  // ---------------- Read (light) ---------------------------------------------

  Future<List<MemoryEntry>> latest(int n) async {
    try {
      return await _store.latest(limit: n);
    } catch (_) {
      return const <MemoryEntry>[];
    }
  }

  Future<List<Facet>> topFacets({int limit = 8}) async {
    try {
      if (_topFacetsCache != null &&
          _topFacetsTs != null &&
          DateTime.now().difference(_topFacetsTs!).inSeconds <= _facetsTtlSec) {
        return _topFacetsCache!.take(limit).toList(growable: false);
      }

      final all = await _store.all();
      if (all.isEmpty) return const <Facet>[];
      final counts = <String, int>{};
      final labels = <String, String>{};

      for (final e in all) {
        for (final f in e.contextFacets) {
          final k = f.key;
          counts[k] = (counts[k] ?? 0) + (f.hits <= 0 ? 1 : f.hits);
          labels.putIfAbsent(k, () => f.label);
        }
      }

      final keys = counts.keys.toList()
        ..sort((a, b) {
          final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
          if (byCount != 0) return byCount;
          final aIdx = all.indexWhere((e) => e.contextFacets.any((f) => f.key == a));
          final bIdx = all.indexWhere((e) => e.contextFacets.any((f) => f.key == b));
          return aIdx.compareTo(bIdx);
        });

      final result = keys
          .take(limit)
          .map((k) => Facet(key: k, label: labels[k] ?? k, hits: counts[k] ?? 1))
          .toList(growable: false);

      _topFacetsCache = result;
      _topFacetsTs = DateTime.now();
      return result;
    } catch (_) {
      return const <Facet>[];
    }
  }

  Future<List<String>> latestTopics({int limit = 6}) async {
    try {
      if (_latestTopicsCache != null &&
          _latestTopicsTs != null &&
          DateTime.now().difference(_latestTopicsTs!).inSeconds <= _topicsTtlSec) {
        return _latestTopicsCache!.take(limit).toList(growable: false);
      }

      final entries = await latest(12);
      final out = <String>[];
      final seen = <String>{};
      for (final e in entries) {
        for (final f in e.contextFacets) {
          final key = f.key.toLowerCase();
          if (seen.add(key)) {
            out.add(f.label);
            if (out.length >= limit) {
              _latestTopicsCache = out;
              _latestTopicsTs = DateTime.now();
              return out;
            }
          }
        }
      }
      _latestTopicsCache = out;
      _latestTopicsTs = DateTime.now();
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<String>> recentTopics({int limit = 6}) => latestTopics(limit: limit);

  Future<List<dynamic>> recall({int limit = 6, String? topicHint}) async {
    try {
      final int takeN = ((limit * 2).clamp(6, 24)).toInt();
      final rawTopics = await latestTopics(limit: takeN);
      final seen = <String>{};
      final ranked = <String>[];

      final hint = (topicHint ?? '').trim().toLowerCase();
      final tmp = [...rawTopics];

      if (hint.isNotEmpty) {
        int score(String s) {
          final t = s.toLowerCase();
          if (t.startsWith(hint)) return 2; // <-- Hotfix: startsWith (korrekt)
          if (t.contains(hint)) return 1;
          return 0;
        }

        tmp.sort((a, b) => score(b).compareTo(score(a)));
      }

      for (final t in tmp) {
        final label = t.trim();
        if (label.isEmpty) continue;
        final key = label.toLowerCase();
        if (seen.add(key)) {
          ranked.add(label);
          if (ranked.length >= limit) break;
        }
      }

      if (ranked.isNotEmpty) return List<dynamic>.from(ranked);

      final facets = await topFacets(limit: limit);
      final viaFacets =
          facets.map((f) => f.label.trim()).where((s) => s.trim().isNotEmpty).toList();
      return List<dynamic>.from(viaFacets);
    } catch (_) {
      return const <dynamic>[];
    }
  }

  // ---------------- Sync-Hints & Memories (ApiService) -----------------------

  MemoryContextHint? buildContextHint({
    int maxFacets = 3,
    int maxTags = 5,
    int maxAgeDays = _hintTtlDays,
    String? activeFacet,
    String? topicPin,
  }) {
    try {
      if (!_enabled) return null;

      final hint = _lastHint;
      List<String>? facets;
      List<String>? tags;
      List<String>? topics;

      if (hint != null) {
        if (_lastHintTs != null && maxAgeDays > 0) {
          final ageDays = DateTime.now().difference(_lastHintTs!).inDays;
          if (ageDays <= maxAgeDays) {
            facets = (hint.facets == null)
                ? null
                : hint.facets!.take(maxFacets).toList(growable: false);
            tags = (hint.tags == null)
                ? null
                : hint.tags!.take(maxTags).toList(growable: false);
            topics =
                (hint.topics == null) ? null : hint.topics!.take(5).toList(growable: false);
            activeFacet ??= hint.activeFacet;
            topicPin ??= hint.topicPin;
          }
        }
      }

      final idName = (_identityNameCache ?? '').trim();
      final profName = (_profileUserNameCache ?? '').trim();
      final nicks = (_profileNicknamesCache ?? const <String>[])
          .where((e) => e.trim().isNotEmpty)
          .map((e) => e.trim())
          .take(5)
          .toList(growable: false);

      if ((facets == null || facets.isEmpty) &&
          (tags == null || tags!.isEmpty) &&
          (topics == null || topics!.isEmpty) &&
          idName.isEmpty &&
          profName.isEmpty &&
          nicks.isEmpty &&
          (activeFacet == null || activeFacet.trim().isEmpty) &&
          (topicPin == null || topicPin.trim().isEmpty)) {
        return null;
      }

      return MemoryContextHint(
        facets: facets,
        tags: tags,
        topics: topics,
        identityName: idName.isEmpty ? null : idName,
        profileUserName: profName.isEmpty ? null : profName,
        profileNicknames: nicks.isEmpty ? null : nicks,
        activeFacet: (activeFacet ?? '').trim().isEmpty ? null : activeFacet!.trim(),
        topicPin: (topicPin ?? '').trim().isNotEmpty ? topicPin!.trim() : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Baut ein kompaktes Kontext-Paket ≤2 KB (nur bei Consent & aktiv).
  Future<Map<String, dynamic>> buildContextMemories({required bool consent}) async {
    try {
      if (!_enabled || !consent || !memoryActive) return const <String, dynamic>{};

      final out = <String, dynamic>{};

      // Identity (nur bei Consent + greet)
      String? nameToUse;
      bool greet = _greetByNameCache == true;
      if (greet && (_identityNameCache ?? '').trim().isNotEmpty) {
        nameToUse = _identityNameCache!.trim();
      } else {
        final id = await loadGreetingName();
        greet = id.greetByName;
        nameToUse = id.name;
      }
      if (greet && nameToUse != null && nameToUse.isNotEmpty) {
        out['identity'] = <String, dynamic>{'name': nameToUse};
      }

      // last.topic/mood/date
      String? lastTopic = await _getOptString(_kLastTopic);
      String? lastMoodStr = await _getOptString(_kLastMood);
      String? lastDateStr = await _getOptString(_kLastDate);

      if ((lastTopic ?? '').trim().isEmpty) {
        lastTopic = _lastHint?.topicPin?.trim().isNotEmpty == true
            ? _lastHint!.topicPin!.trim()
            : (_lastHint?.activeFacet?.trim().isNotEmpty == true
                ? _lastHint!.activeFacet!.trim()
                : null);
      }
      if ((lastTopic ?? '').trim().isEmpty) {
        final topics = await latestTopics(limit: 1);
        if (topics.isNotEmpty) lastTopic = topics.first.trim();
      }
      if ((lastTopic ?? '').isNotEmpty && lastTopic!.length > 36) {
        lastTopic = '${lastTopic!.substring(0, 36).trimRight()}…';
      }
      lastDateStr ??= _ymd(DateTime.now().toUtc());

      dynamic moodField;
      if ((lastMoodStr ?? '').trim().isNotEmpty) {
        final s = lastMoodStr!.trim();
        final n = int.tryParse(s);
        moodField = n ?? s;
      }

      // Mood-Objekt
      final moodLast = await _readLastMoodExpanded();
      final moodTrend = await _computeMoodTrend(days: 7, minDays: 3);

      if (moodLast != null || moodTrend != null) {
        out['mood'] = <String, dynamic>{
          if (moodLast != null)
            'last': {
              'date': moodLast['date'],
              'mental': moodLast['mental'],
              'physical': moodLast['physical'],
              'avg': moodLast['avg'],
            },
          if (moodTrend != null)
            'trend': {
              'days': moodTrend['days'],
              'mental_delta': moodTrend['mental_delta'],
              'physical_delta': moodTrend['physical_delta'],
              'dir': moodTrend['dir'],
            },
        };
        if (moodField == null && moodLast != null) {
          moodField = moodLast['avg'];
        }
      }

      // Timeline (kompakt)
      final timeline =
          await _exportTimeline(days: _timelineExportDays, perDay: _timelinePerDayExport);
      if (timeline.isNotEmpty) {
        out['timeline'] = timeline;
      }

      // K4: Kuratierte Insights (1–2 Zeilen; score/recency sortiert)
      final curated =
          await _insightsForBridge(days: _insightsExportDays, maxItems: _insightsExportMax);
      if (curated.isNotEmpty) out['insights'] = curated;

      // K5: Sehr kurze Recall-Zusammenfassung
      final rec = await computeRecall(days: 7);
      if (rec != null) out['recall'] = rec.toJson();

      if ((lastTopic ?? '').isNotEmpty || moodField != null || (lastDateStr ?? '').isNotEmpty) {
        out['last'] = <String, dynamic>{
          if ((lastTopic ?? '').isNotEmpty) 'topic': lastTopic,
          if (moodField != null) 'mood': moodField,
          if ((lastDateStr ?? '').isNotEmpty) 'date': lastDateStr,
        };
      }
      if (_shareEnabled) out['share'] = true;

      // Größenkappe ≤ 2 kB: stufenweise kürzen
      List<int> bytes() => utf8.encode(jsonEncode(out));
      if (bytes().length > 2048) out.remove('timeline');
      if (bytes().length > 2048) out.remove('insights');
      if (bytes().length > 2048) out.remove('recall');
      if (bytes().length > 2048) out.remove('share');
      if (bytes().length > 2048) out.remove('mood');
      if (bytes().length > 2048) (out['last'] as Map<String, dynamic>?)?.remove('mood');
      if (bytes().length > 2048) {
        final t = (out['last'] as Map<String, dynamic>?)?['topic']?.toString() ?? '';
        if (t.isNotEmpty) {
          (out['last'] as Map<String, dynamic>)['topic'] =
              (t.length <= 20) ? t : '${t.substring(0, 20).trimRight()}…';
        }
      }
      if (bytes().length > 2048) out.remove('last');
      if (bytes().length > 2048) out.remove('identity');

      return out;
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  // ---------------- Byte-Kontext (sync) --------------------------------------

  List<int>? tryGetByteContext([int maxBytes = 2048]) {
    try {
      if (_lastHint == null) return null;
      final map = <String, dynamic>{
        if (_lastHint!.facets != null && _lastHint!.facets!.isNotEmpty)
          'facets': _lastHint!.facets!.take(6).toList(),
        if (_lastHint!.topics != null && _lastHint!.topics!.isNotEmpty)
          'topics': _lastHint!.topics!.take(6).toList(),
        if ((_lastHint!.activeFacet ?? '').trim().isNotEmpty)
          'active_facet': _lastHint!.activeFacet!.trim(),
        if ((_lastHint!.topicPin ?? '').trim().isNotEmpty)
          'topic_pin': _lastHint!.topicPin!.trim(),
        if (_shareEnabled) 'share': true,
      };
      if (map.isEmpty) return null;
      final bytes = utf8.encode(jsonEncode(map));
      if (bytes.length <= maxBytes) return bytes;
      return bytes.sublist(0, maxBytes);
    } catch (_) {
      return null;
    }
  }

  List<int>? exportByteContext([int maxBytes = 2048]) => tryGetByteContext(maxBytes);
  List<int>? byteContext([int maxBytes = 2048]) => tryGetByteContext(maxBytes);

  // ---------------- Geo & Timeline & Timeline-Views --------------------------

  Future<void> recordLocation({
    String? label,
    double? lat,
    double? lon,
    double? accuracy,
    String? source,
    DateTime? tsUtc,
  }) async {
    if (!_enabled) return;
    try {
      final stamp = LocationBreadcrumb(
        label: (label ?? '').trim().isNotEmpty ? _cap(label!.trim()) : null,
        lat: lat,
        lon: lon,
        accuracy: accuracy,
        source: (source ?? '').trim().isNotEmpty ? source!.trim() : null,
        tsUtc: (tsUtc ?? DateTime.now().toUtc()),
      );

      final dyn = _store as dynamic;
      bool saved = false;
      try {
        final r = dyn.saveLocation?.call(stamp.toMap());
        if (r is Future) await r;
        saved = true;
      } catch (_) {}
      if (!saved) {
        try {
          final r = dyn.saveMap?.call(stamp.toMap());
          if (r is Future) await r;
          saved = true;
        } catch (_) {}
      }
      if (!saved) {
        try {
          final r = dyn.save?.call(stamp.toMap());
          if (r is Future) await r;
        } catch (_) {}
      }

      if ((stamp.label ?? '').trim().isNotEmpty) {
        _lastLocationLabelCache = stamp.label!.trim();
        await _setOptString(_kGeoLastLabel, _lastLocationLabelCache!);
      }
      _lastLocationTsCache = stamp.tsUtc;
      await _setOptString(_kGeoLastTs, stamp.tsUtc.toIso8601String());
      if (lat != null) await _setOptString(_kGeoLastLat, '$lat');
      if (lon != null) await _setOptString(_kGeoLastLon, '$lon');
      if (accuracy != null) await _setOptString(_kGeoLastAcc, '$accuracy');
    } catch (_) {}
  }

  Future<String?> lastPlaceLabel({int maxAgeHours = 96}) async {
    try {
      if (_lastLocationLabelCache != null && _lastLocationTsCache != null) {
        final ageH =
            DateTime.now().toUtc().difference(_lastLocationTsCache!).inHours;
        if (ageH <= maxAgeHours) return _lastLocationLabelCache;
      }
      final lbl = await _getOptString(_kGeoLastLabel);
      final ts = await _getOptString(_kGeoLastTs);
      if (lbl != null && ts != null) {
        final when = DateTime.tryParse(ts)?.toUtc();
        if (when != null) {
          final ageH = DateTime.now().toUtc().difference(when).inHours;
          if (ageH <= maxAgeHours) {
            _lastLocationLabelCache = lbl.trim();
            _lastLocationTsCache = when;
            return _lastLocationLabelCache;
          }
        }
      }

      try {
        final dyn = _store as dynamic;
        final r = await dyn.latestLocations?.call(limit: 1);
        if (r is List && r.isNotEmpty) {
          final crumb = LocationBreadcrumb.fromMap(r.first);
          if (crumb != null) {
            _lastLocationLabelCache =
                (crumb.label ?? '').trim().isEmpty ? null : crumb.label!.trim();
            _lastLocationTsCache = crumb.tsUtc;
            if (_lastLocationLabelCache != null) {
              await _setOptString(_kGeoLastLabel, _lastLocationLabelCache!);
              await _setOptString(_kGeoLastTs, _lastLocationTsCache!.toIso8601String());
            }
            return _lastLocationLabelCache;
          }
        }
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> recentTimeline({
    int limit = 50,
    DateTime? sinceUtc,
  }) async {
    if (!_enabled) return const <Map<String, dynamic>>[];
    try {
      try {
        final dyn = _store as dynamic;
        final r = await dyn.timeline?.call(limit: limit, sinceUtc: sinceUtc);
        if (r is List) {
          final list = r
              .where((e) => e != null)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(growable: false);
          list.sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
          return list.take(limit).toList(growable: false);
        }
      } catch (_) {}

      final out = <Map<String, dynamic>>[];

      try {
        final dyn = _store as dynamic;
        final lines = await dyn.latestLines?.call(limit: limit);
        if (lines is List) {
          for (final e in lines) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              m.putIfAbsent('kind', () => 'line');
              out.add(m);
            }
          }
        }
      } catch (_) {}

      try {
        final dyn = _store as dynamic;
        final facts = await dyn.latestFacts?.call(limit: (limit / 2).ceil());
        if (facts is List) {
          for (final e in facts) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              m.putIfAbsent('kind', () => 'fact');
              out.add(m);
            }
          }
        }
      } catch (_) {}

      try {
        final dyn = _store as dynamic;
        final markers = await dyn.latestTimelineMarkers?.call(limit: (limit / 2).ceil());
        if (markers is List) {
          for (final e in markers) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              m.putIfAbsent('kind', () => 'timeline');
              out.add(m);
            }
          }
        }
      } catch (_) {}

      try {
        final dyn = _store as dynamic;
        final locs = await dyn.latestLocations?.call(limit: 8);
        if (locs is List) {
          for (final e in locs) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              m.putIfAbsent('kind', () => 'location');
              out.add(m);
            }
          }
        }
      } catch (_) {}

      try {
        final dyn = _store as dynamic;
        final acks = await dyn.latestAcks?.call(limit: 12);
        if (acks is List) {
          for (final e in acks) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              m.putIfAbsent('kind', () => 'ack');
              out.add(m);
            }
          }
        }
      } catch (_) {}

      if (sinceUtc != null) {
        out.removeWhere((m) => _tsOf(m).isBefore(sinceUtc));
      }

      out.sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
      return out.take(limit).toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> timelineByDay({int days = 7}) async {
    try {
      final since = DateTime.now().toUtc().subtract(Duration(days: days));
      final events = await recentTimeline(limit: days * 64, sinceUtc: since);
      final map = <String, List<Map<String, dynamic>>>{};
      for (final e in events) {
        final ts = _tsOf(e);
        final key = _ymd(ts);
        (map[key] ??= <Map<String, dynamic>>[]).add(e);
      }
      for (final k in map.keys) {
        map[k]!.sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
        if (map[k]!.length > 64) {
          map[k] = map[k]!.take(64).toList(growable: false);
        }
      }
      return map;
    } catch (_) {
      return <String, List<Map<String, dynamic>>>{};
    }
  }

  Future<List<String>> recentDays({int days = 7}) async {
    try {
      final grouped = await timelineByDay(days: days);
      final keys = grouped.keys.toList(growable: false)..sort((a, b) => a.compareTo(b));
      return keys.takeLast(days).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<Map<String, dynamic>>> toHistoryTurns({int lastN = 20}) async {
    if (!_enabled) return const <Map<String, dynamic>>[];
    try {
      final dyn = _store as dynamic;

      // Primary path: echte Chat-Lines
      try {
        final res = await dyn.latestLines?.call(limit: lastN * 3);
        if (res is List) {
          final list = res
              .where((e) => e is Map)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .map((m) => <String, dynamic>{
                    'role': (m['role'] ?? '').toString(),
                    'text': (m['text'] ?? '').toString(),
                    'ts': (m['ts'] ??
                            m['created_at'] ??
                            m['createdAt'] ??
                            DateTime.now().toUtc().toIso8601String())
                        .toString(),
                  })
              .toList(growable: false);
          list.sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
          return list.takeLast(lastN);
        }
      } catch (_) {}

      // Fallback: Timeline-Feed
      final tl = await recentTimeline(limit: lastN * 3);
      final out = <Map<String, dynamic>>[];
      for (final e in tl) {
        final kind = (e['kind'] ?? '').toString();
        if (kind == 'line') {
          out.add(<String, dynamic>{
            'role': (e['role'] ?? '').toString(),
            'text': (e['text'] ?? '').toString(),
            'ts': (e['ts'] ??
                    e['created_at'] ??
                    e['createdAt'] ??
                    DateTime.now().toUtc().toIso8601String())
                .toString(),
          });
        }
      }
      out.sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
      return out.takeLast(lastN);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  // ---------------- KUTSCHE 2 — Mood: Write & Read ---------------------------

  Future<void> saveMoodEntry({
    DateTime? tsUtc,
    required int mental,
    required int physical,
    String? note,
  }) async {
    if (!_enabled) return;
    try {
      final now = (tsUtc ?? DateTime.now().toUtc());
      final m = _clampInt(mental, 1, 5);
      final p = _clampInt(physical, 1, 5);
      final entry = MoodEntry(
        id: 'm_${now.millisecondsSinceEpoch}',
        tsUtc: now,
        mental: m,
        physical: p,
        note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      );

      final dyn = _store as dynamic;
      bool saved = false;
      try {
        final r = await dyn.saveMoodEntry?.call(entry.toMap());
        if (r is bool && r == true) saved = true;
      } catch (_) {}
      if (!saved) {
        try {
          final r = await dyn.upsertMoodEntry?.call(entry.toMap());
          if (r is bool && r == true) saved = true;
        } catch (_) {}
      }
      if (!saved) {
        try {
          final map = {...entry.toMap(), 'type': 'mood'};
          final r = await dyn.upsertFact?.call(map);
          if (r is bool && r == true) {
            saved = true;
          } else {
            await dyn.saveFact?.call(map);
            saved = true;
          }
        } catch (_) {}
      }

      // Tages-De-Dup (≤2/Tag)
      try {
        final day = _ymd(now);
        final list = await _readMoodEntriesByDay(day);
        if (list.length > 2) {
          list.sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
          final toRemove = list.length - 2;
          for (int i = 0; i < toRemove; i++) {
            final rem = list[i];
            try {
              await dyn.removeMoodEntry?.call(rem.id);
            } catch (_) {
              try {
                await dyn.removeFactById?.call(rem.id);
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      // Opt-Pins (last.*)
      final dayKey = _ymd(now);
      await _setOptString(_kMoodLastMental, '$m');
      await _setOptString(_kMoodLastPhysical, '$p');
      await _setOptString(_kMoodLastDate, dayKey);

      final avg = ((m + p) / 2.0);
      await _setOptString(_kLastMood, avg.toStringAsFixed(avg % 1 == 0 ? 0 : 1));
      await _setOptString(_kLastDate, dayKey);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getLastMood() async => await _readLastMoodExpanded();

  Future<Map<String, dynamic>?> computeMoodTrend({int windowDays = 7}) async {
    final int d = windowDays < 3 ? 3 : (windowDays > 7 ? 7 : windowDays);
    return await _computeMoodTrend(days: d, minDays: 3);
  }

  Future<List<MoodPoint>> getMoodSeries({int days = 7}) async {
    final int d = days < 3 ? 3 : (days > 14 ? 14 : days);
    final win = await _readMoodWindow(days: d);
    return win.map(MoodPoint.fromEntry).toList(growable: false);
  }

  Future<List<int>> moodSparkline({int days = 7, String kind = 'avg'}) async {
    try {
      final int d = days < 3 ? 3 : (days > 14 ? 14 : days);
      final win = await _readMoodWindow(days: d);
      if (win.isEmpty) return const <int>[];
      final vals = <int>[];
      for (final e in win) {
        switch (kind) {
          case 'mental':
            vals.add(e.mental);
            break;
          case 'physical':
            vals.add(e.physical);
            break;
          default:
            vals.add(((e.mental + e.physical) / 2.0).round());
        }
      }
      return vals.takeLast(d).toList(growable: false);
    } catch (_) {
      return const <int>[];
    }
  }

  Future<Map<String, dynamic>?> _readLastMoodExpanded() async {
    try {
      final ment = await _getOptString(_kMoodLastMental);
      final phys = await _getOptString(_kMoodLastPhysical);
      final date = await _getOptString(_kMoodLastDate);
      if (ment != null && phys != null && date != null) {
        final mi = int.tryParse(ment) ?? 3;
        final pi = int.tryParse(phys) ?? 3;
        final avg = ((mi + pi) / 2.0);
        return {
          'date': date,
          'mental': mi,
          'physical': pi,
          'avg': double.parse(avg.toStringAsFixed(avg % 1 == 0 ? 0 : 1)),
        };
      }

      final last = await _readLastMood();
      if (last.value != null) {
        final avg = int.tryParse(last.value!) ?? 3;
        return {
          'date': _ymd(last.date ?? DateTime.now().toUtc()),
          'mental': avg,
          'physical': avg,
          'avg': avg.toDouble(),
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<MoodEntry>> _readMoodEntriesByDay(String ymd) async {
    final out = <MoodEntry>[];
    try {
      final dyn = _store as dynamic;
      try {
        final res = await dyn.moodEntriesByDay?.call(ymd);
        if (res is List) {
          for (final e in res) {
            final me = MoodEntry.fromMap(e);
            if (me != null && me.dayKey == ymd) out.add(me);
          }
          return out;
        }
      } catch (_) {}

      try {
        final res = await dyn.latestMoodEntries?.call(limit: 10);
        if (res is List) {
          for (final e in res) {
            final me = MoodEntry.fromMap(e);
            if (me != null && me.dayKey == ymd) out.add(me);
          }
          return out;
        }
      } catch (_) {}

      try {
        final res = await dyn.latestFacts?.call(limit: 20);
        if (res is List) {
          for (final e in res) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              final t = (m['type'] ?? '').toString().toLowerCase();
              if (t == 'mood') {
                final me = MoodEntry.fromMap(m);
                if (me != null && me.dayKey == ymd) out.add(me);
              }
            }
          }
        }
      } catch (_) {}
    } catch (_) {}
    return out;
  }

  Future<List<MoodEntry>> _readMoodWindow({int days = 7}) async {
    final out = <MoodEntry>[];
    try {
      final dyn = _store as dynamic;
      try {
        final res = await dyn.moodWindow?.call(days: days);
        if (res is List) {
          for (final e in res) {
            final me = MoodEntry.fromMap(e);
            if (me != null) out.add(me);
          }
          out.sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
          return out;
        }
      } catch (_) {}

      try {
        final res = await dyn.latestMoodEntries?.call(limit: days * 4);
        if (res is List) {
          final tmp = <String, List<MoodEntry>>{};
          for (final e in res) {
            final me = MoodEntry.fromMap(e);
            if (me == null) continue;
            (tmp[me.dayKey] ??= <MoodEntry>[]).add(me);
          }
          final keys = tmp.keys.toList()..sort();
          for (final k in keys.takeLast(days)) {
            final list = tmp[k]!..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
            final take = list.length <= 2 ? list : [list[list.length - 2], list.last];
            final avgM =
                (take.map((e) => e.mental).reduce((a, b) => a + b) / take.length).round();
            final avgP =
                (take.map((e) => e.physical).reduce((a, b) => a + b) / take.length).round();
            out.add(MoodEntry(
              id: 'd_$k',
              tsUtc: DateTime.parse('${k}T12:00:00Z'),
              mental: avgM,
              physical: avgP,
            ));
          }
          out.sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
          return out;
        }
      } catch (_) {}

      try {
        final res = await dyn.latestFacts?.call(limit: days * 6);
        if (res is List) {
          final tmp = <String, List<MoodEntry>>{};
          for (final e in res) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              final t = (m['type'] ?? '').toString().toLowerCase();
              if (t == 'mood') {
                final me = MoodEntry.fromMap(m);
                if (me == null) continue;
                (tmp[me.dayKey] ??= <MoodEntry>[]).add(me);
              }
            }
          }
          final keys = tmp.keys.toList()..sort();
          for (final k in keys.takeLast(days)) {
            final list = tmp[k]!..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
            final take = list.length <= 2 ? list : [list[list.length - 2], list.last];
            final avgM =
                (take.map((e) => e.mental).reduce((a, b) => a + b) / take.length).round();
            final avgP =
                (take.map((e) => e.physical).reduce((a, b) => a + b) / take.length).round();
            out.add(MoodEntry(
              id: 'd_$k',
              tsUtc: DateTime.parse('${k}T12:00:00Z'),
              mental: avgM,
              physical: avgP,
            ));
          }
          out.sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
          return out;
        }
      } catch (_) {}
    } catch (_) {}
    return out;
  }

  Future<Map<String, dynamic>?> _computeMoodTrend({int days = 7, int minDays = 3}) async {
    try {
      final int d = days < 3 ? 3 : (days > 7 ? 7 : days);
      final win = await _readMoodWindow(days: d);
      if (win.length < minDays) return null;
      final last = win.last;
      if (win.length == 1) {
        return {'days': 1, 'mental_delta': 0, 'physical_delta': 0, 'dir': 'flat'};
      }
      final prev = win.sublist(0, win.length - 1);
      double avgM =
          prev.map((e) => e.mental).fold<double>(0, (a, b) => a + b) / prev.length;
      double avgP =
          prev.map((e) => e.physical).fold<double>(0, (a, b) => a + b) / prev.length;

      final dM = (last.mental - avgM);
      final dP = (last.physical - avgP);

      String dir;
      final meanDelta = (dM + dP) / 2.0;
      if (meanDelta > 0.15) {
        dir = 'up';
      } else if (meanDelta < -0.15) {
        dir = 'down';
      } else {
        dir = 'flat';
      }

      return {
        'days': win.length,
        'mental_delta': _round1(dM),
        'physical_delta': _round1(dP),
        'dir': dir,
      };
    } catch (_) {
      return null;
    }
  }

  // ---------------- Timeline API (Write & Read) ------------------------------

  Future<void> saveTimelineMarker({
    required String topic,
    required int valence,
    DateTime? tsUtc,
    List<String>? tags,
    String? source,
  }) async {
    if (!_enabled) return;
    try {
      final now = (tsUtc ?? DateTime.now().toUtc());
      final t = _normTopic(topic);
      if (t.isEmpty) return;

      final tag = _pickPrimaryTag(tags ?? const <String>[], topic: t);
      final marker = TimelineMarker(
        id: 't_${now.millisecondsSinceEpoch}',
        tsUtc: now,
        topic: t,
        tag: tag,
        valence: _clampValence(valence),
        source: (source ?? '').trim().isEmpty ? null : source!.trim(),
      );

      final merged = await _mergeTimelineForDay(marker);
      await _capTimelineForDay(merged.tsUtc);

      // Globaler Hard-Cap prüfen / ggf. trimmen (K3)
      try {
        await _maybeTrimTimelineTotal();
      } catch (_) {}

      try {
        if ((await _getOptString(_kLastTopic)) == null ||
            (await _getOptString(_kLastTopic))!.trim().isEmpty) {
          await _setOptString(_kLastTopic, merged.topic);
          await _setOptString(_kLastDate, merged.dayKey);
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadTimelineRecent({
    int days = 7,
    int perDay = 2,
  }) async {
    return await _exportTimeline(days: days, perDay: perDay);
  }

  Future<void> _maybeAutoTimelineFromText({
    required String role, // "user" | "panda"
    required String text,
    DateTime? tsUtc,
    bool pandaRelaxed = false,
  }) async {
    final raw = text.trim();
    if (raw.isEmpty) return;

    final topic = _inferTopicFromText(raw);
    if (topic == null) return;

    if (role == 'panda' && pandaRelaxed == true) {
      final l = raw.toLowerCase();
      final isSelfWorth =
          RegExp(r'\b(stolz|wert|wertvoll|selbstwert)\b').hasMatch(l);
      if (!isSelfWorth) return;
    }

    int val = 0;
    try {
      final last = await _readLastMoodExpanded();
      if (last != null) {
        final avg = (last['avg'] as num?)?.toDouble() ?? 3.0;
        val = _valenceFromMoodAvg(avg);
      } else {
        val = _valenceFromText(raw);
      }
    } catch (_) {}

    final tags = _inferTagsFrom(topic: topic, text: raw);
    await saveTimelineMarker(
      topic: topic,
      valence: val,
      tsUtc: tsUtc,
      tags: tags,
      source: role,
    );
  }

  Future<List<Map<String, dynamic>>> _exportTimeline({
    int days = 3,
    int perDay = 1,
  }) async {
    try {
      final out = <Map<String, dynamic>>[];
      final dyn = _store as dynamic;

      List<dynamic>? raw;
      try {
        raw = await dyn.timelineMarkersWindow?.call(days: days);
      } catch (_) {}

      if (raw is List && raw.isNotEmpty) {
        final tmp = <String, List<TimelineMarker>>{};
        for (final e in raw) {
          final m = TimelineMarker.fromMap(e);
          if (m == null) continue;
          (tmp[m.dayKey] ??= <TimelineMarker>[]).add(m);
        }
        final keys = tmp.keys.toList()..sort();
        for (final k in keys.takeLast(days)) {
          final list = tmp[k]!..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
          list.sort((a, b) {
            final byTs = b.tsUtc.compareTo(a.tsUtc);
            if (byTs != 0) return byTs;
            final byAbs = b.valence.abs().compareTo(a.valence.abs());
            if (byAbs != 0) return byAbs;
            return (b.count).compareTo(a.count);
          });
          for (final m in list.take(perDay)) {
            out.add({
              'date': k,
              'topic': m.topic,
              if ((m.tag ?? '').isNotEmpty) 'tag': m.tag,
              'valence': m.valence,
            });
          }
        }
        return out;
      }

      List<dynamic>? latest;
      try {
        latest = await dyn.latestTimelineMarkers?.call(limit: days * 6);
      } catch (_) {}

      final tmp = <String, List<TimelineMarker>>{};
      if (latest is List && latest.isNotEmpty) {
        for (final e in latest) {
          final m = TimelineMarker.fromMap(e);
          if (m == null) continue;
          (tmp[m.dayKey] ??= <TimelineMarker>[]).add(m);
        }
      }

      if (tmp.isEmpty) {
        try {
          final facts = await dyn.latestFacts?.call(limit: days * 8);
          if (facts is List) {
            for (final e in facts) {
              if (e is Map) {
                final mm = Map<String, dynamic>.from(e);
                final t = (mm['type'] ?? mm['kind'] ?? '').toString().toLowerCase();
                if (t == 'timeline' || t == 'timeline_marker') {
                  final m = TimelineMarker.fromMap(mm);
                  if (m != null) (tmp[m.dayKey] ??= <TimelineMarker>[]).add(m);
                }
              }
            }
          }
        } catch (_) {}
      }

      if (tmp.isEmpty) return out;

      final keys = tmp.keys.toList()..sort();
      for (final k in keys.takeLast(days)) {
        final list = tmp[k]!..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
        list.sort((a, b) {
          final byTs = b.tsUtc.compareTo(a.tsUtc);
          if (byTs != 0) return byTs;
          final byAbs = b.valence.abs().compareTo(a.valence.abs());
          if (byAbs != 0) return byAbs;
          return (b.count).compareTo(a.count);
        });
        for (final m in list.take(perDay)) {
          out.add({
            'date': k,
            'topic': m.topic,
            if ((m.tag ?? '').isNotEmpty) 'tag': m.tag,
            'valence': m.valence,
          });
        }
      }
      return out;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<TimelineMarker> _mergeTimelineForDay(TimelineMarker m) async {
    final dyn = _store as dynamic;
    final day = m.dayKey;
    List<dynamic>? raw;
    try {
      raw = await dyn.timelineMarkersByDay?.call(day);
    } catch (_) {}

    TimelineMarker? existing;
    if (raw is List) {
      for (final e in raw) {
        final tm = TimelineMarker.fromMap(e);
        if (tm != null && _sameTopic(tm.topic, m.topic)) {
          existing = tm;
          break;
        }
      }
    } else {
      try {
        final latest = await dyn.latestTimelineMarkers?.call(limit: 12);
        if (latest is List) {
          for (final e in latest) {
            final tm = TimelineMarker.fromMap(e);
            if (tm != null && tm.dayKey == day && _sameTopic(tm.topic, m.topic)) {
              existing = tm;
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (existing == null) {
      final map = m.toMap();
      bool saved = false;
      try {
        final r = await dyn.saveTimelineMarker?.call(map);
        if (r is bool && r == true) saved = true;
      } catch (_) {}
      if (!saved) {
        try {
          final r = await dyn.upsertTimelineMarker?.call(map);
          if (r is bool && r == true) saved = true;
        } catch (_) {}
      }
      if (!saved) {
        try {
          final fm = {...map, 'type': 'timeline'};
          final r = await dyn.upsertFact?.call(fm);
          if (r is! bool) {
            await dyn.saveFact?.call(fm);
          }
        } catch (_) {}
      }
      return m;
    }

    final totalCount = (existing.count + 1);
    final mergedVal =
        ((existing.valence * existing.count + m.valence) / totalCount).round();
    final merged = TimelineMarker(
      id: existing.id,
      tsUtc: m.tsUtc.isAfter(existing.tsUtc) ? m.tsUtc : existing.tsUtc,
      topic: existing.topic,
      tag: existing.tag ?? m.tag,
      valence: _clampValence(mergedVal),
      source: m.source ?? existing.source,
      count: totalCount,
    );

    final map = merged.toMap();
    bool ok = false;
    try {
      final r = await dyn.upsertTimelineMarker?.call(map);
      if (r is bool && r == true) ok = true;
    } catch (_) {}
    if (!ok) {
      try {
        final fm = {...map, 'type': 'timeline'};
        final r = await dyn.upsertFact?.call(fm);
        if (r is! bool) {
          await dyn.saveFact?.call(fm);
        }
        ok = true;
      } catch (_) {}
    }
    return merged;
  }

  Future<void> _capTimelineForDay(DateTime dayTs) async {
    try {
      final dyn = _store as dynamic;
      final day = _ymd(dayTs);
      List<TimelineMarker> list = [];
      try {
        final raw = await dyn.timelineMarkersByDay?.call(day);
        if (raw is List) {
          list = raw
              .map((e) => TimelineMarker.fromMap(e))
              .whereType<TimelineMarker>()
              .toList();
        }
      } catch (_) {}
      if (list.isEmpty) {
        try {
          final raw = await dyn.latestTimelineMarkers?.call(limit: 10);
          if (raw is List) {
            list = raw
                .map((e) => TimelineMarker.fromMap(e))
                .whereType<TimelineMarker>()
                .where((m) => m.dayKey == day)
                .toList();
          }
        } catch (_) {}
      }
      if (list.isEmpty) return;

      list.sort((a, b) {
        final byTs = b.tsUtc.compareTo(a.tsUtc);
        if (byTs != 0) return byTs;
        final byAbs = b.valence.abs().compareTo(a.valence.abs());
        if (byAbs != 0) return byAbs;
        return (b.count).compareTo(a.count);
      });

      final kept = <TimelineMarker>[];
      final perTag = <String, int>{};
      for (final m in list) {
        final tg = (m.tag ?? 'untagged').toLowerCase();
        final used = (perTag[tg] ?? 0);
        if (used >= _timelineCapPerTagPerDay) continue;
        kept.add(m);
        perTag[tg] = used + 1;
        if (kept.length >= _timelineCapPerDay) break;
      }

      final toDrop = list.where((m) => !kept.any((k) => k.id == m.id)).toList();
      for (final m in toDrop) {
        try {
          final r = await dyn.removeTimelineMarkerById?.call(m.id);
          if (r is! bool) {
            await dyn.removeFactById?.call(m.id);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _maybeTrimTimelineTotal({int? maxTotal}) async {
    final max = maxTotal ?? _timelineHardCapTotal;
    try {
      final dyn = _store as dynamic;

      int? count;
      try {
        final v = await dyn.timelineCount?.call();
        if (v is int) count = v;
      } catch (_) {}

      if (count == null) {
        final all = await _readTimelineWindow(days: 365);
        count = all.length;
        if (count <= max) return;

        final toRemove = count - max;
        final victims = all..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
        for (final m in victims.take(toRemove)) {
          try {
            final r = await dyn.removeTimelineMarkerById?.call(m.id);
            if (r is! bool) {
              await dyn.removeFactById?.call(m.id);
            }
          } catch (_) {}
        }
        return;
      }

      if (count <= max) return;

      try {
        final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 365));
        final r = await dyn.removeTimelineOlderThan?.call(cutoff.toIso8601String());
        if (r is! bool) {
          final all = await _readTimelineWindow(days: 365);
          if (all.length > max) {
            final toRemove = all.length - max;
            final victims = all..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
            for (final m in victims.take(toRemove)) {
              try {
                final rr = await dyn.removeTimelineMarkerById?.call(m.id);
                if (rr is! bool) {
                  await dyn.removeFactById?.call(m.id);
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {
        final all = await _readTimelineWindow(days: 365);
        if (all.length > max) {
          final toRemove = all.length - max;
          final victims = all..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
          for (final m in victims.take(toRemove)) {
            try {
              final rr = await dyn.removeTimelineMarkerById?.call(m.id);
              if (rr is! bool) {
                await dyn.removeFactById?.call(m.id);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<int> trimTimelineHardCap({int maxTotal = _timelineHardCapTotal}) async {
    try {
      final all = await _readTimelineWindow(days: 365);
      if (all.length <= maxTotal) return 0;

      final toRemove = all.length - maxTotal;
      final victims = all..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
      int removed = 0;
      final dyn = _store as dynamic;
      for (final m in victims.take(toRemove)) {
        try {
          final r = await dyn.removeTimelineMarkerById?.call(m.id);
          if (r is! bool) {
            await dyn.removeFactById?.call(m.id);
          }
          removed++;
        } catch (_) {}
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  // ---------------- KUTSCHE 5 — Recall --------------------------------------

  Future<RecallSummary?> computeRecall({int days = 7}) async {
    if (!_enabled) return null;
    final d = (days <= 7) ? 7 : (days <= 30 ? 30 : 90);
    try {
      final full = await buildRecallSummary(days: d);
      final mood = (full['mood'] as Map?) ?? const {};
      final dir = (mood['dir'] ?? full['dir'] ?? 'flat').toString();
      final delta = (mood['delta'] as num?)?.toDouble() ?? 0.0;

      final topics = <String>[];
      final tlist = (full['topics'] as List? ?? const []);
      for (final it in tlist) {
        if (it is Map) {
          final label = (it['topic'] ?? '').toString().trim();
          if (label.isNotEmpty) topics.add(label);
          if (topics.length >= 3) break;
        }
      }

      return RecallSummary(days: d, trend: {'dir': dir, 'delta': delta}, topTopics: topics);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> buildRecallSummary({int days = 7}) async {
    final d = days < 7 ? 7 : (days > 30 ? 30 : days);
    try {
      final mood2x = await _readMoodWindow(days: d * 2);
      List<MoodEntry> cur = mood2x.takeLast(d);
      final startRaw = (mood2x.length - d * 2);
      final start = startRaw < 0 ? 0 : (startRaw > (mood2x.length - d) ? (mood2x.length - d) : startRaw);
      List<MoodEntry> prev = mood2x.length > d
          ? mood2x.sublist(start, mood2x.length - d)
          : const <MoodEntry>[];

      double _avg(List<int> xs) =>
          xs.isEmpty ? 0.0 : xs.reduce((a, b) => a + b) / xs.length;

      final curMental = _avg(cur.map((e) => e.mental).toList());
      final curPhysical = _avg(cur.map((e) => e.physical).toList());
      final curAvg = (curMental + curPhysical) / 2.0;

      final prevMental = _avg(prev.map((e) => e.mental).toList());
      final prevPhysical = _avg(prev.map((e) => e.physical).toList());
      final prevAvg = prev.isEmpty ? curAvg : (prevMental + prevPhysical) / 2.0;

      final delta = curAvg - prevAvg;
      String dir;
      if (delta > 0.15) {
        dir = 'up';
      } else if (delta < -0.15) {
        dir = 'down';
      } else {
        dir = 'flat';
      }

      final markers = await _readTimelineWindow(days: d);
      final byTopic = <String, List<int>>{};
      for (final m in markers) {
        (byTopic[m.topic] ??= <int>[]).add(m.valence);
      }
      final topicStats = <Map<String, dynamic>>[];
      byTopic.forEach((topic, vals) {
        final cnt = vals.length;
        final mean =
            vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
        topicStats.add({'topic': topic, 'count': cnt, 'valence_avg': _round1(mean.toDouble())});
      });
      topicStats.sort((a, b) {
        final byCount = (b['count'] as int).compareTo(a['count'] as int);
        if (byCount != 0) return byCount;
        final av = (a['valence_avg'] as num).abs().toDouble();
        final bv = (b['valence_avg'] as num).abs().toDouble();
        return bv.compareTo(av);
      });
      final topicsTop = topicStats.take(3).toList(growable: false);

      final insights = await _readInsightsWindow(days: d, limit: 8);
      final topInsights = insights
          .take(3)
          .map((f) => {
                'line': (f.line ?? '').trim(),
                if (f.score != null) 'score': _round1(f.score!),
              })
          .where((m) => (m['line'] as String).isNotEmpty)
          .toList(growable: false);

      final periodLabel = d == 7 ? 'diese Woche' : 'in den letzten $d Tagen';
      final moodSentence = () {
        final ca = _round1(curAvg);
        final pa = _round1(prevAvg);
        switch (dir) {
          case 'up':
            return 'Deine Stimmung war insgesamt etwas ruhiger als zuvor ($ca vs. $pa).';
          case 'down':
            return 'Deine Stimmung wirkte etwas angespannter als zuvor ($ca vs. $pa).';
          default:
            return 'Deine Stimmung war in etwa stabil ($ca vs. $pa).';
        }
      }();

      String _capWord(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

      final topicsSentence = () {
        if (topicsTop.isEmpty) return '';
        final labels = topicsTop.map((t) => _capWord(t['topic'].toString())).toList();
        if (labels.length == 1) return 'Dein Fokus lag häufig auf ${labels.first}.';
        if (labels.length == 2) return 'Oft ging es um ${labels[0]} und ${labels[1]}.';
        return 'Häufige Themen: ${labels[0]}, ${labels[1]} und ${labels[2]}.';
      }();

      final insightSentence = () {
        if (topInsights.isEmpty) return '';
        final first = topInsights.first['line'] as String;
        return 'Kleine Einsicht: $first';
      }();

      final text = [
        'Rückblick $periodLabel: $moodSentence',
        if (topicsSentence.isNotEmpty) topicsSentence,
        if (insightSentence.isNotEmpty) insightSentence,
      ].join(' ');

      return {
        'days': d,
        'text': text,
        'mood': {
          'avg': _round1(curAvg),
          'prev_avg': _round1(prevAvg),
          'delta': _round1(delta),
          'dir': dir,
          'mental_avg': _round1(curMental),
          'physical_avg': _round1(curPhysical),
          'sample_days': cur.length,
        },
        'topics': topicsTop,
        'insights': topInsights,
      };
    } catch (_) {
      return {
        'days': d,
        'text': d == 7
            ? 'Rückblick dieser Woche: Für eine kleine Zusammenfassung liegen noch zu wenige Daten vor.'
            : 'Rückblick der letzten $d Tage: Für eine kleine Zusammenfassung liegen noch zu wenige Daten vor.',
        'mood': const <String, dynamic>{},
        'topics': const <Map<String, dynamic>>[],
        'insights': const <Map<String, dynamic>>[],
      };
    }
  }

  // ---------------- KUTSCHE 6 — Story-Bundle --------------------------------

  Future<List<Map<String, dynamic>>> storyHistory({int lastN = 24, bool redact = true}) async {
    try {
      final bounded = lastN < 4 ? 4 : (lastN > 60 ? 60 : lastN);
      final lines = await toHistoryTurns(lastN: bounded);
      if (!redact) return lines;
      return lines
          .map((m) => <String, dynamic>{
                'role': (m['role'] ?? '').toString(),
                'text': _redactForExport((m['text'] ?? '').toString()),
                'ts': (m['ts'] ?? '').toString(),
              })
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>> buildStoryBundle({
    int days = 30,
    bool includeIdentity = false,
    int maxHistory = 24,
    bool redact = true,
  }) async {
    final d = days < 7 ? 7 : (days > 90 ? 90 : days);
    try {
      final bundle = <String, dynamic>{
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'days': d,
      };

      if (includeIdentity && _shareEnabled && (_greetByNameCache == true)) {
        final name = (_identityNameCache ?? '').trim().isEmpty
            ? (await loadGreetingName()).name
            : _identityNameCache;
        if ((name ?? '').toString().trim().isNotEmpty) {
          bundle['identity'] = {'name': _cap(name!.trim())};
        }
      }

      final place = await lastPlaceLabel(maxAgeHours: 96);
      if ((place ?? '').toString().trim().isNotEmpty) {
        bundle['last_place'] = place!.trim();
      }

      final recall =
          await buildRecallSummary(days: d < 7 ? 7 : (d <= 30 ? d : 30));
      bundle['recall'] = recall;

      final sparkAvg = await moodSparkline(days: (d <= 14 ? d : 14), kind: 'avg');
      final sparkMental =
          await moodSparkline(days: (d <= 14 ? d : 14), kind: 'mental');
      final sparkPhysical =
          await moodSparkline(days: (d <= 14 ? d : 14), kind: 'physical');
      bundle['sparkline'] = {'avg': sparkAvg, 'mental': sparkMental, 'physical': sparkPhysical};

      final markers = await _readTimelineWindow(days: d <= 30 ? d : 30);
      final tl = markers
          .map((m) => {
                'date': _ymd(m.tsUtc),
                'topic': m.topic,
                if ((m.tag ?? '').isNotEmpty) 'tag': m.tag,
                'valence': m.valence,
              })
          .toList(growable: false);
      if (tl.isNotEmpty) bundle['timeline'] = tl;

      bundle['topics'] = recall['topics'] ?? const <Map<String, dynamic>>[];
      bundle['insights'] = recall['insights'] ?? const <Map<String, dynamic>>[];
      bundle['history'] = await storyHistory(lastN: maxHistory, redact: redact);

      return bundle;
    } catch (_) {
      return {
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'days': d,
        'recall': await buildRecallSummary(days: d < 7 ? 7 : (d <= 30 ? d : 30)),
        'sparkline': const <String, dynamic>{},
        'timeline': const <Map<String, dynamic>>[],
        'topics': const <Map<String, dynamic>>[],
        'insights': const <Map<String, dynamic>>[],
        'history': const <Map<String, dynamic>>[],
      };
    }
  }

  // ---------------- FutureMap (Status der 6 Kutschen) ------------------------

  Future<Map<String, dynamic>> buildFutureMap() async {
    try {
      final mood = await _readMoodWindow(days: 14);
      final tl = await _readTimelineWindow(days: 14);
      final insights = await _readInsightsWindow(days: 30, limit: 30);

      final recall7 = await buildRecallSummary(days: 7);
      final storyOk = (await toHistoryTurns(lastN: 8)).isNotEmpty;

      return {
        'identity': {
          'has_name': (_identityNameCache ?? '').trim().isNotEmpty,
          'greet_enabled': _greetByNameCache == true,
          'share_enabled': _shareEnabled,
        },
        'mood': {
          'days_available': mood.map((e) => e.dayKey).toSet().length,
          'latest': (await _readLastMoodExpanded()) ?? const {},
          'trend': (await _computeMoodTrend(days: 7, minDays: 3)) ?? const {},
        },
        'timeline': {'markers_14d': tl.length},
        'insights': {'count_30d': insights.length},
        'recall': {'available': (recall7['mood'] as Map? ?? {}).isNotEmpty},
        'story': {'ready': storyOk},
      };
    } catch (_) {
      return {
        'identity': const <String, dynamic>{},
        'mood': const <String, dynamic>{},
        'timeline': const <String, dynamic>{},
        'insights': const <String, dynamic>{},
        'recall': const <String, dynamic>{},
        'story': const <String, dynamic>{},
      };
    }
  }

  // ---------------- interne Helfer (WRITE/UTILS) -----------------------------

  // KV-Utils
  Future<void> _setOptString(String key, String value) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOptString?.call(key, value);
      if (r is Future) await r;
    } catch (_) {}
  }

  Future<void> _setOptBool(String key, bool value) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOptBool?.call(key, value);
      if (r is Future) await r;
    } catch (_) {}
  }

  Future<void> _setOptStringList(String key, List<String> values) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOptStringList?.call(key, values);
      if (r is Future) await r;
    } catch (_) {
      try {
        await _setOptString(key, jsonEncode(values));
      } catch (_) {}
    }
  }

  Future<String?> _getOptString(String key) async {
    try {
      final dyn = _store as dynamic;
      final r = await dyn.getOptString?.call(key);
      if (r is String?) return r;
    } catch (_) {}
    return null;
  }

  Future<bool?> _getOptBool(String key) async {
    try {
      final dyn = _store as dynamic;
      final r = await dyn.getOptBool?.call(key);
      if (r is bool?) return r;
    } catch (_) {}
    return null;
  }

  Future<List<String>?> _getOptStringList(String key) async {
    try {
      final dyn = _store as dynamic;
      final r = await dyn.getOptStringList?.call(key);
      if (r is List) return r.map((e) => e.toString()).toList();
    } catch (_) {}
    try {
      final s = await _getOptString(key);
      if (s == null || s.trim().isEmpty) return null;
      final d = jsonDecode(s);
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
    return null;
  }

  // Times/Numbers
  static String _ymd(DateTime ts) {
    final u = ts.toUtc();
    final y = u.year.toString().padLeft(4, '0');
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
  static double _round1(num v) => double.parse(v.toStringAsFixed(1));

  static int _clampValence(int v) => v < -2 ? -2 : (v > 2 ? 2 : v);

  static DateTime _tsOf(Map m) {
    final raw = (m['ts'] ?? m['created_at'] ?? m['createdAt'] ?? m['date'])?.toString();
    return DateTime.tryParse((raw ?? '').isEmpty ? DateTime.now().toUtc().toIso8601String() : raw!)?.toUtc()
        ?? DateTime.now().toUtc();
  }

  int _valenceFromMoodAvg(double avg) {
    // 1..5 → -2..+2
    if (avg >= 4.2) return 2;
    if (avg >= 3.4) return 1;
    if (avg <= 1.8) return -2;
    if (avg <= 2.6) return -1;
    return 0;
  }

  int _valenceFromText(String text) {
    final l = text.toLowerCase();
    if (RegExp(r'\b(super|gut|ruhig|leichter|stolz|geschafft)\b').hasMatch(l)) return 1;
    if (RegExp(r'\b(schlecht|müde|ängstlich|überfordert|traurig|wertlos)\b').hasMatch(l)) return -1;
    if (RegExp(r'\b(panik|abgrund|katastrophe|hoffnungslos)\b').hasMatch(l)) return -2;
    if (RegExp(r'\b(glücklich|dankbar|kraftvoll)\b').hasMatch(l)) return 2;
    return 0;
  }

  // Topics/Tags
  String _normTopic(String s) {
    final t = s.toLowerCase().trim();
    return t.replaceAll(RegExp(r'[^a-z0-9äöüß\- ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _sameTopic(String a, String b) => _normTopic(a) == _normTopic(b);

  String? _inferTopicFromText(String text) {
    final l = text.toLowerCase();
    if (RegExp(r'\b(job|arbeit|chef|kolleg|projekt|meeting)\b').hasMatch(l)) return 'arbeit';
    if (RegExp(r'\b(schlaf|einschlaf|durchschlaf|müde)\b').hasMatch(l)) return 'schlaf';
    if (RegExp(r'\b(familie|partner|partnerin|mama|papa|kind|freund|freundin)\b').hasMatch(l)) return 'familie';
    if (RegExp(r'\b(selbstwert|wertlos|zweifel|versagen|stolz)\b').hasMatch(l)) return 'selbstwert';
    // Fallback: erstes sinnvolles Nomen/Token (grob)
    final tok = l.replaceAll(RegExp(r'[^a-zäöüß ]'), ' ').split(RegExp(r'\s+')).where((t) => t.length >= 4).toList();
    return tok.isEmpty ? null : tok.first;
  }

  List<String> _inferTagsFrom({required String topic, required String text}) {
    final out = <String>{};
    final l = text.toLowerCase();
    if (topic.contains('arbeit') || RegExp(r'\b(job|arbeit|chef|meeting|projekt)\b').hasMatch(l)) {
      out.add('arbeit');
    }
    if (topic.contains('schlaf') || RegExp(r'\b(schlaf|einschlaf|müde|durchschlaf)\b').hasMatch(l)) {
      out.add('schlaf');
    }
    if (topic.contains('familie') || RegExp(r'\b(familie|partner|mama|papa|kind|freund)\b').hasMatch(l)) {
      out.add('familie');
    }
    if (topic.contains('selbstwert') || RegExp(r'\b(selbstwert|wertlos|stolz|zweifel)\b').hasMatch(l)) {
      out.add('selbstwert');
    }
    return out.toList(growable: false);
  }

  String? _pickPrimaryTag(List<String> tags, {required String topic}) {
    final t = tags.map((e) => _normTopic(e)).toSet();
    for (final k in _knownTags) {
      if (t.contains(k)) return k;
    }
    if (topic.contains('arbeit')) return 'arbeit';
    if (topic.contains('schlaf')) return 'schlaf';
    if (topic.contains('familie')) return 'familie';
    if (topic.contains('selbstwert')) return 'selbstwert';
    return null;
  }

  // Insights (K4)
  Future<void> saveInsightFact({
    required String line,
    double? score,
    DateTime? tsUtc,
  }) async {
    if (!_enabled) return;
    final ts = (tsUtc ?? DateTime.now().toUtc());
    final clean = line.trim();
    if (clean.isEmpty) return;

    try {
      // Dedup: in den letzten 30..90 Tagen
      final existing = await _readInsightsWindow(days: _insightDedupDaysFallback, limit: 60);
      final norm = _normInsight(clean);
      final dup = existing.firstWhere(
        (f) => _normInsight(f.line ?? '') == norm,
        orElse: () => _InsightLite(id: null, line: null, score: null, tsUtc: ts),
      );
      final dyn = _store as dynamic;
      if ((dup.line ?? '').isNotEmpty && dup.id != null) {
        // Upsert/Boost
        try {
          final map = {
            'id': dup.id,
            'type': 'insight',
            'line': clean,
            if (score != null) 'score': score,
            'ts': ts.toIso8601String(),
          };
          final r = await dyn.upsertFact?.call(map);
          if (r is! bool) {
            await dyn.saveFact?.call(map);
          }
        } catch (_) {}
        return;
      }

      // Neu speichern
      final map = <String, dynamic>{
        'id': 'ins_${ts.millisecondsSinceEpoch}',
        'type': 'insight',
        'line': clean,
        if (score != null) 'score': score,
        'ts': ts.toIso8601String(),
      };
      try {
        final r = await dyn.saveInsight?.call(map);
        if (r is! bool) {
          final u = await dyn.upsertFact?.call(map);
          if (u is! bool) {
            await dyn.saveFact?.call(map);
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  String _normInsight(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüß ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<List<_InsightLite>> _readInsightsWindow({int days = 30, int limit = 30}) async {
    try {
      final dyn = _store as dynamic;
      final out = <_InsightLite>[];
      DateTime? cutoff;
      try {
        cutoff = DateTime.now().toUtc().subtract(Duration(days: days));
      } catch (_) {
        cutoff = null;
      }

      // Direct window
      try {
        final res = await dyn.insightsWindow?.call(days: days, limit: limit);
        if (res is List) {
          for (final e in res) {
            final f = _InsightLite.fromMap(e);
            if (f != null) out.add(f);
          }
        }
      } catch (_) {}

      // Latest explicit insights
      if (out.isEmpty) {
        try {
          final res = await dyn.latestInsights?.call(limit: limit * 2);
          if (res is List) {
            for (final e in res) {
              final f = _InsightLite.fromMap(e);
              if (f != null) out.add(f);
            }
          }
        } catch (_) {}
      }

      // Facts fallback
      if (out.isEmpty) {
        try {
          final res = await dyn.latestFacts?.call(limit: limit * 3);
          if (res is List) {
            for (final e in res) {
              if (e is Map) {
                final m = Map<String, dynamic>.from(e);
                final t = (m['type'] ?? m['kind'] ?? '').toString().toLowerCase();
                if (t == 'insight') {
                  final f = _InsightLite.fromMap(m);
                  if (f != null) out.add(f);
                }
              }
            }
          }
        } catch (_) {}
      }

      if (cutoff != null) {
        out.removeWhere((f) => f.tsUtc.isBefore(cutoff!));
      }

      // Sort: neu → alt, score desc
      out.sort((a, b) {
        final byTs = b.tsUtc.compareTo(a.tsUtc);
        if (byTs != 0) return byTs;
        final ascore = a.score ?? 0.0;
        final bscore = b.score ?? 0.0;
        return bscore.compareTo(ascore);
      });

      if (out.length > limit) return out.take(limit).toList(growable: false);
      return out;
    } catch (_) {
      return const <_InsightLite>[];
    }
  }

  Future<List<TimelineMarker>> _readTimelineWindow({int days = 30}) async {
    try {
      final dyn = _store as dynamic;
      final out = <TimelineMarker>[];
      final since = DateTime.now().toUtc().subtract(Duration(days: days));

      try {
        final res = await dyn.timelineMarkersWindow?.call(days: days);
        if (res is List) {
          for (final e in res) {
            final m = TimelineMarker.fromMap(e);
            if (m != null) out.add(m);
          }
        }
      } catch (_) {}

      if (out.isEmpty) {
        try {
          final res = await dyn.latestTimelineMarkers?.call(limit: days * 12);
          if (res is List) {
            for (final e in res) {
              final m = TimelineMarker.fromMap(e);
              if (m != null) out.add(m);
            }
          }
        } catch (_) {}
      }

      if (out.isEmpty) {
        try {
          final res = await dyn.latestFacts?.call(limit: days * 16);
          if (res is List) {
            for (final e in res) {
              if (e is Map) {
                final m = TimelineMarker.fromMap(e);
                if (m != null) out.add(m);
              }
            }
          }
        } catch (_) {}
      }

      out.removeWhere((m) => m.tsUtc.isBefore(since));
      out.sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
      return out;
    } catch (_) {
      return const <TimelineMarker>[];
    }
  }

  Future<List<Map<String, dynamic>>> _insightsForBridge({int days = 14, int maxItems = 2}) async {
    final facts = await _readInsightsWindow(days: days, limit: maxItems * 3);
    final list = facts.take(maxItems).map((f) => {
          'line': (f.line ?? '').trim(),
          if (f.score != null) 'score': _round1(f.score!),
        }).where((m) => (m['line'] as String).isNotEmpty).toList(growable: false);
    return list;
  }

  // ---------------- ingest helpers (K4+, tolerant) ---------------------------

  Future<void> _ingestMemoriesToSave(Map<String, dynamic> root, {bool allowIdentity = false}) async {
    try {
      final list = (root['memories_to_save'] as List?) ?? (root['memoriesToSave'] as List?) ?? const [];
      for (final it in list) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);

        final type = (m['type'] ?? m['kind'] ?? '').toString().toLowerCase().trim();

        if (type == 'insight') {
          final line = (m['line'] ?? m['text'] ?? m['value'] ?? '').toString().trim();
          if (line.isNotEmpty) {
            final score = (m['score'] is num) ? (m['score'] as num).toDouble() : (m['score'] is String ? double.tryParse(m['score']) : null);
            await saveInsightFact(line: line, score: score);
          }
          continue;
        }

        if (type == 'timeline' || type == 'timeline_marker') {
          final topic = (m['topic'] ?? m['label'] ?? '').toString().trim();
          if (topic.isNotEmpty) {
            int val = 0;
            final raw = m['valence'];
            if (raw is num) val = raw.toInt();
            if (raw is String) val = int.tryParse(raw) ?? 0;
            final tags = ((m['tags'] as List?) ?? const []).map((e) => e.toString()).toList();
            await saveTimelineMarker(topic: topic, valence: val, tags: tags, source: 'worker');
          }
          continue;
        }

        if (allowIdentity && (type == 'identity' || m.containsKey('identity.name'))) {
          final name = (m['name'] ?? m['identity.name'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            await saveIdentityName(name, greetByName: true);
          }
          continue;
        }
      }
    } catch (_) {}
  }

  Future<void> _ingestGeoIfPresent(Map<String, dynamic> root) async {
    try {
      final geo = root['geo'] ?? root['location'] ?? root['place'];
      if (geo is Map) {
        final m = Map<String, dynamic>.from(geo);
        await recordLocation(
          label: (m['label'] ?? m['name'] ?? '').toString(),
          lat: (m['lat'] is num) ? (m['lat'] as num).toDouble() : (m['latitude'] is num ? (m['latitude'] as num).toDouble() : null),
          lon: (m['lon'] is num) ? (m['lon'] as num).toDouble() : (m['longitude'] is num ? (m['longitude'] as num).toDouble() : null),
          accuracy: (m['accuracy'] is num) ? (m['accuracy'] as num).toDouble() : null,
          source: (m['source'] ?? '').toString(),
        );
      }
    } catch (_) {}
  }

  Future<void> _ingestTimelineIfPresent(Map<String, dynamic> root) async {
    try {
      final tl = root['timeline'] ?? root['timeline_markers'] ?? root['markers'];
      if (tl is List) {
        for (final e in tl) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            final topic = (m['topic'] ?? m['label'] ?? '').toString().trim();
            if (topic.isEmpty) continue;
            int val = 0;
            final raw = m['valence'];
            if (raw is num) val = raw.toInt();
            if (raw is String) val = int.tryParse(raw) ?? 0;
            final tags = ((m['tags'] as List?) ?? const []).map((x) => x.toString()).toList();
            await saveTimelineMarker(topic: topic, valence: val, tags: tags, source: 'worker');
          }
        }
      }
    } catch (_) {}
  }

  // ---------------- misc helpers --------------------------------------------

  String _cap(String s) {
    if (s.isEmpty) return s;
    final lower = s.toLowerCase();
    return lower.replaceAllMapped(RegExp(r"(^|[-\s'’])([a-zäöüß])"), (m) {
      final lead = m.group(1) ?? '';
      final ch = m.group(2) ?? '';
      return '$lead${ch.toUpperCase()}';
    });
  }

  void _invalidateSoftCaches() {
    _lastHintTs = null;
    _latestTopicsTs = null;
    _topFacetsTs = null;
  }

  bool? _tryReadShareEnabledReflective() {
    try {
      final dyn = _store as dynamic;
      final v = dyn.shareEnabled as bool?;
      return v;
    } catch (_) {
      return null;
    }
  }

  String _redactForExport(String s) {
    var t = s;
    // E-Mail
    t = t.replaceAll(RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '[E-Mail]');
    // Telefon
    t = t.replaceAll(RegExp(r'(\+?\d[\d\-\s]{6,}\d)'), '[Telefon]');
    // Adressen (sehr grob)
    t = t.replaceAll(RegExp(r'\b(strasse|straße|weg|platz)\b\s*\d+[a-zA-Z]?', caseSensitive: false), '[Adresse]');
    return t;
  }

  Future<_LastMood> _readLastMood() async {
    try {
      final v = await _getOptString(_kLastMood);
      final d = await _getOptString(_kLastDate);
      final dt = (d == null || d.trim().isEmpty) ? null : DateTime.tryParse(d)?.toUtc();
      return _LastMood(v, dt);
    } catch (_) {
      return const _LastMood(null, null);
    }
  }
}
