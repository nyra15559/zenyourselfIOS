// [BASELINE] lib/core/memory/memory_service.dart — v6.7.3 (S12.4 • Story-Bundle v1.0 · 07.11.2025)
// ZenYourself — MemoryService (Lokales Kontext-Gedächtnis, Ghost-Mode by default)
// -----------------------------------------------------------------------------
// NEU in v6.7.3 (Kutsche 6 — Story/Story-Builder):
// • Public-API: buildStoryBundle({days:30, includeIdentity:false, maxHistory:24, redact:true})
//   → gebündelte Daten für PDF/Story-Builder: recall, mood-Sparkline, Topics, Insights,
//     Timeline (Fenster), History (letzte Turns, optional redacted), letzter Ort.
// • Public-API: storyHistory({lastN:24, redact:true}) → kompakte Turn-Liste (role/text/ts)
// • Sanfte Redaktions-Helfer (_redactForExport) für E-Mails/URLs/Telefonnummern.
//
// NEU in v6.7.2 (Kutsche 5 — Recall/Rückblick):
// • Public-API: buildRecallSummary({int days = 7}) → liefert sanften Wochen/Monats-Text
//   + kleine Trendwerte aus Mood/Timeline/Insights. Unterstützt days ∈ [7, 30].
// • Interne Helfer: _readTimelineWindow(...), _readInsightsWindow(...), _round1(...).
//
// NEU in v6.7.1 (Mood/Public API + Bugfix):
// • Public-APIs: getLastMood() und computeMoodTrend(windowDays:7) hinzugefügt.
// • Bugfix: Falscher Rückgabetyp im catch-Zweig von toHistoryTurns() behoben.
//
// NEU in v6.7.0 (Kutsche 3 — Timeline/Themenverlauf):
// • saveTimelineMarker(topic, valence[, tsUtc, tags, source]) — legt/merged Tages-Marker.
// • Auto-Ableitung: aus saveUserTurn/savePandaTurn (sanfte Heuristik) → Themen-Marker.
// • Duplikate mergen: gleicher Tag + Topic → Valence gemittelt (clamp -2..+2), count++.
// • Tags-Heuristik (arbeit/schlaf/familie/selbstwert) + manuelle Übergabe.
// • Caps: max 3 Marker pro Tag insgesamt, max 2 pro Tag/Tag-Kategorie.
// • Export: buildContextMemories() fügt context.memories.timeline hinzu (bis 3 Tage,
//   1 Marker/Tag, {date, topic, tag, valence}); Timeline wird als erstes entfernt,
//   wenn das 2-KB-Budget überschritten wird (danach share → mood → last.mood …).
//
// NEU in v6.6.5 (Mood Window, Trend & Context-Memories):
// • saveMoodEntry(ts, mental, physical[, note]) — speichert Tagesstimmung (2-Parameter).
// • Tages-De-Dup: max. 2 Mood-Entries pro Kalendertag (älteste überschreibt).
// • Mood-Trend (3–7 Tage): leichte Delta-Berechnung gegenüber gleitendem Mittel.
// • buildContextMemories(): liefert zusätzlich context.memories.mood
//   { last:{date,mental,physical,avg}, trend:{days,mental_delta,physical_delta,dir} }.
// • Kompatibilität: "last.mood" bleibt erhalten (avg-Wert als Zahl), Größe ≤2 KB
//   mit aggressiver Kürzung.
//
// MERGE-SIGNAL / Bridge-Guard (unverändert):
// • Api/Guidance senden context.memories **nur**, wenn enabled && consent && memoryActive.
// • meta.flags.client_memory:true wird extern (ApiService/ReflectionLogic) gesetzt.
//
// Vorversionen siehe Kopf der Datei (v6.6.1–v6.6.5).
// -----------------------------------------------------------------------------

import 'dart:convert' show jsonEncode, jsonDecode, utf8;

import '../models/insight_models.dart';
import 'memory_entry.dart';
import 'memory_mapper.dart';
import 'memory_store.dart';

/// Leichte, synchrone Hint-Struktur für den Worker (keine PII).
/// **Neu**: activeFacet/topicPin (optional).
class MemoryContextHint {
  final List<String>? facets; // stabile Facet-Keys
  final List<String>? tags; // optional
  final List<String>? topics; // human labels der Facetten

  // Identity/Profile (rein lokal, sync, klein)
  final String? identityName; // -> context.memories.identity.name
  final String? profileUserName; // -> context.memories.profile.user_name
  final List<String>? profileNicknames; // -> context.memories.profile.nicknames[]

  // Kontext-Pins (neu)
  final String? activeFacet; // bevorzugte aktive Facette
  final String? topicPin; // kurzer Themen-Pin/Schlüsselwort

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
          'identity': {
            'name': identityName!.trim(),
          },
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

/// Kleiner Geo-Stempel (lokal; PII-schonend, keine automatische Weitergabe).
class LocationBreadcrumb {
  final String? label;       // z. B. "Zürich HB" | "Home"
  final double? lat;         // optional
  final double? lon;         // optional
  final double? accuracy;    // Meter (optional)
  final String? source;      // "device" | "user" | "worker"
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

// ---------------- Mood Models (leicht) ---------------------------------------

class MoodEntry {
  final String id;
  final DateTime tsUtc; // genauer Zeitstempel
  final int mental;     // 1..5
  final int physical;   // 1..5
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
      final tsRaw = (m['ts'] ?? m['date'] ?? m['created_at'] ?? m['createdAt'])?.toString();
      final ts = (tsRaw == null || tsRaw.trim().isEmpty)
          ? DateTime.now().toUtc()
          : DateTime.tryParse(tsRaw)?.toUtc() ?? DateTime.now().toUtc();
      int? _int(dynamic x) {
        if (x is int) return x;
        if (x is num) return x.toInt();
        if (x is String) return int.tryParse(x.trim());
        return null;
      }
      final mental = _int(m['mental'] ?? m['mind'] ?? m['m']) ?? _int(m['value']) ?? 3;
      final physical = _int(m['physical'] ?? m['body'] ?? m['p']) ?? 3;
      final id = (m['id'] ?? 'm_${ts.millisecondsSinceEpoch}').toString();
      final note = (m['note'] ?? m['line'])?.toString();
      return MoodEntry(
        id: id,
        tsUtc: ts,
        mental: mental.clamp(1, 5),
        physical: physical.clamp(1, 5),
        note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// ---------------- Timeline Models (Kutsche 3) -------------------------------

class TimelineMarker {
  final String id;
  final DateTime tsUtc;
  final String topic;   // kompakter Topic (z. B. "arbeit")
  final String? tag;    // einer der bekannten Tags oder null
  final int valence;    // -2..+2 (negativ..positiv)
  final String? source; // "user" | "panda" | "worker" | "journal"
  final int count;      // Merge-Zähler (wie oft zusammengefasst)

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
      final tsRaw = (m['ts'] ?? m['date'] ?? m['created_at'] ?? m['createdAt'])?.toString();
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
      final source = (m['source'] ?? '').toString().trim().isEmpty ? null : m['source'].toString().trim();
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

class MemoryService {
  MemoryService._internal();
  static final MemoryService instance = MemoryService._internal();

  final MemoryStore _store = MemoryStore.instance;

  // Flags
  bool _enabled = true;          // Ghost-Mode (lokales Gedächtnis)
  bool _shareEnabled = false;    // Therapist-Mode (Opt-in → Name teilen erlaubt, etc.)

  // Memory-Bridge Aktivierung + Trial-Fenster
  bool _memoryActive = true;     // Bridge aktiv (Trial/Premium)
  DateTime? _memoryExpiryUtc;    // Ende des Trial-Fensters

  bool get enabled => _enabled;
  bool get shareEnabled => _shareEnabled;

  /// true, wenn Memory-Bridge aktiv ist (Trial/Premium) und nicht abgelaufen
  bool get memoryActive => _memoryActive && !_isExpired();
  /// Alias für Kompatibilität mit älteren Call-Sites
  bool get isActive => memoryActive;
  DateTime? get memoryExpiryUtc => _memoryExpiryUtc;

  // Kleiner, rein lokaler Cache für buildContextHint() (sync!)
  MemoryContextHint? _lastHint;
  DateTime? _lastHintTs;

  // Weiche Caches (kurzer TTL)
  List<String>? _latestTopicsCache;
  DateTime? _latestTopicsTs;
  List<Facet>? _topFacetsCache;
  DateTime? _topFacetsTs;

  // Identity/Profile Sync-Caches
  String? _identityNameCache;
  String? get identityNameSync => _identityNameCache;

  String? _profileUserNameCache;
  List<String>? _profileNicknamesCache;

  // NEU: Greet-Consent Sync-Cache
  bool? _greetByNameCache;

  // NEU (S12.2): Letzter Orts-Recall (lokal)
  String? _lastLocationLabelCache;
  DateTime? _lastLocationTsCache;

  // NEU (v6.6.1): „last.*“-Opt-Keys
  static const String _kLastTopic = 'last.topic';
  static const String _kLastMood = 'last.mood';
  static const String _kLastDate = 'last.date';

  // NEU (v6.6.5): Mood-Opt-Keys (explizit)
  static const String _kMoodLastMental = 'mood.last.mental';
  static const String _kMoodLastPhysical = 'mood.last.physical';
  static const String _kMoodLastDate = 'mood.last.date';

  // NEU (v6.7.0): Timeline (Opt-/Store-Keys + Heuristiken)
  static const Set<String> _knownTags = {'arbeit', 'schlaf', 'familie', 'selbstwert'};
  static const int _timelineExportDays = 3;     // Export-Fenster
  static const int _timelinePerDayExport = 1;   // 1 Marker/Tag exportieren
  static const int _timelineCapPerDay = 3;      // max 3 Marker pro Tag
  static const int _timelineCapPerTagPerDay = 2; // max 2 Marker je Tag-Kategorie/Tag

  bool get profileHasNicknamesSync =>
      (_profileNicknamesCache?.isNotEmpty ?? false);

  String? get profileUserNameSync => _profileUserNameCache;
  List<String> get profileNicknamesSync =>
      List.unmodifiable(_profileNicknamesCache ?? const <String>[]);

  // Bequeme Alias-Getter
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

  /// NEU: true, wenn Name sofort (sync) geteilt werden darf.
  bool get canShareNameSync =>
      _shareEnabled &&
      (_greetByNameCache == true) &&
      ((_identityNameCache ?? '').trim().isNotEmpty);

  /// NEU: Sync-Lesehilfe für UI (z. B. Intro-Bubble).
  ({String? name, bool greetByName}) greetingNameSync(
      {bool requireConsent = false}) {
    final name = (_identityNameCache ?? '').trim().isEmpty
        ? null
        : _identityNameCache!.trim();
    final greet = _greetByNameCache == true;
    final ok = requireConsent ? (greet && _shareEnabled) : greet;
    return (name: ok ? name : null, greetByName: ok);
  }

  /// NEU: Lädt Name/Greet in den Sync-Cache, wenn noch nicht vorhanden.
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

  // Storage-Keys (nur lokal)
  static const String _kIdentityName = 'identity.name';
  static const String _kIdentityGreetByName = 'identity.greet_by_name';
  static const String _kShareEnabled = 'share_enabled';

  // Memory-Bridge Keys
  static const String _kMemoryActive = 'memory.active';
  static const String _kMemoryExpiry = 'memory.expiry_utc';

  // Profile-Keys
  static const String _kProfileUserName = 'profile.user_name';
  static const String _kProfileNicknames = 'profile.nicknames'; // JSON-Array

  // Geo-Keys (S12.2)
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

      // shareEnabled (Consent)
      final se = await _getOptBool(_kShareEnabled);
      _shareEnabled = se ?? _tryReadShareEnabledReflective() ?? false;

      // Memory-Bridge: active + expiry (mit Default-7-Tage-Trial)
      await _initMemoryBridgeWindow();

      // Identity & Profile vorladen (für sync use)
      try {
        final n = await _getOptString(_kIdentityName);
        _identityNameCache =
            (n == null || n.trim().isEmpty) ? null : _cap(n.trim());
      } catch (_) {/* ignore */}

      try {
        final p = await _getOptString(_kProfileUserName);
        _profileUserNameCache =
            (p == null || p.trim().isEmpty) ? null : _cap(p.trim());
      } catch (_) {/* ignore */}

      try {
        final list = await _getOptStringList(_kProfileNicknames);
        _profileNicknamesCache = (list == null || list.isEmpty)
            ? null
            : list
                .map((e) => e.toString().trim())
                .where((e) => e.trim().isNotEmpty)
                .map(_cap)
                .toList(growable: false);
      } catch (_) {/* ignore */}

      // Greet-Consent vorladen
      try {
        final greet = await _getOptBool(_kIdentityGreetByName);
        _greetByNameCache = greet ?? false;
      } catch (_) {/* ignore */}

      // Letzten Ort vorladen
      try {
        _lastLocationLabelCache = await _getOptString(_kGeoLastLabel);
        final ts = await _getOptString(_kGeoLastTs);
        _lastLocationTsCache =
            (ts == null || ts.trim().isEmpty) ? null : DateTime.tryParse(ts)?.toUtc();
      } catch (_) {/* ignore */}
    } catch (_) {
      // Defaults beibehalten
    }
  }

  Future<void> warmup() async {
    try {
      await init();
      try {
        await topFacets(limit: 8);
        await latestTopics(limit: 6);
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
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
    } catch (_) {/* ignore */}
  }

  Future<void> setShareEnabled(bool v) async {
    _shareEnabled = v;
    try {
      await _setOptBool(_kShareEnabled, v);
    } catch (_) {/* ignore */}
    // Bei aktivierter Freigabe Name/Greet sicherstellen
    if (v && ((_identityNameCache ?? '').trim().isEmpty || _greetByNameCache == null)) {
      try {
        await ensureGreetingNameLoaded();
      } catch (_) {/* ignore */}
    }
  }

  // -------- Memory-Bridge Window (Trial / Premium) ---------------------------

  Future<void> _initMemoryBridgeWindow() async {
    try {
      final active = await _getOptBool(_kMemoryActive);
      final expIso = await _getOptString(_kMemoryExpiry);

      if (active == null && (expIso == null || expIso.trim().isEmpty)) {
        // Erststart → 7-Tage-Trial ab jetzt
        _memoryActive = true;
        _memoryExpiryUtc = DateTime.now().toUtc().add(const Duration(days: 7));
        await _setOptBool(_kMemoryActive, true);
        await _setOptString(_kMemoryExpiry, _memoryExpiryUtc!.toIso8601String());
        return;
      }

      _memoryActive = active ?? true;
      _memoryExpiryUtc = (expIso == null || expIso.trim().isEmpty)
          ? null
          : DateTime.tryParse(expIso)?.toUtc();

      // Expiry prüfen – abgelaufen → ausgeschaltet persistieren
      if (_memoryActive && _isExpired()) {
        _memoryActive = false;
        try {
          await _setOptBool(_kMemoryActive, false);
        } catch (_) {/* ignore */}
      }
    } catch (_) {
      // Fallback: aktiv ohne Expiry (konservativ)
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

  /// Aktiviert/Deaktiviert die Memory-Bridge. Optional Expiry setzen.
  Future<void> setMemoryActive(bool active, {DateTime? expiryUtc, Duration? trial}) async {
    _memoryActive = active;
    if (expiryUtc != null) {
      _memoryExpiryUtc = expiryUtc.toUtc();
      try {
        await _setOptString(_kMemoryExpiry, _memoryExpiryUtc!.toIso8601String());
      } catch (_) {/* ignore */}
    } else if (trial != null) {
      _memoryExpiryUtc = DateTime.now().toUtc().add(trial);
      try {
        await _setOptString(_kMemoryExpiry, _memoryExpiryUtc!.toIso8601String());
      } catch (_) {/* ignore */}
    }
    try {
      await _setOptBool(_kMemoryActive, _memoryActive);
    } catch (_) {/* ignore */}
  }

  /// Setzt nur die Expiry (z. B. nach Upgrade).
  Future<void> setMemoryExpiry(DateTime? expiryUtc) async {
    _memoryExpiryUtc = expiryUtc?.toUtc();
    if (_memoryExpiryUtc == null) {
      // Entfernen → kein Ablauf
      try {
        final dyn = _store as dynamic;
        final r = dyn.removeOpt?.call(_kMemoryExpiry);
        if (r is Future) await r;
      } catch (_) {/* ignore */}
    } else {
      await _setOptString(_kMemoryExpiry, _memoryExpiryUtc!.toIso8601String());
    }
    // Wenn abgelaufen → deaktivieren
    if (_memoryActive && _isExpired()) {
      await setMemoryActive(false);
    }
  }

  /// Stellt sicher, dass eine Trial-Laufzeit existiert (idempotent).
  Future<void> ensureTrialWindow({int days = 7}) async {
    if (_memoryExpiryUtc == null) {
      await setMemoryActive(true, trial: Duration(days: days));
    }
  }

  // ---------------- Identity/Profile (lokal) ---------------------------------

  Future<void> saveIdentityName(String name, {bool greetByName = true}) async {
    try {
      final n = _cap(name.trim());
      if (n.isEmpty) return;
      _identityNameCache = n; // Sync-Cache
      _greetByNameCache = greetByName; // Cache aktualisieren
      await _setOptString(_kIdentityName, n);
      await _setOptBool(_kIdentityGreetByName, greetByName);

      if ((_profileUserNameCache == null ||
              _profileUserNameCache!.trim().isEmpty) &&
          greetByName == true) {
        await saveProfileUserName(n);
      }
    } catch (_) {/* ignore */}
  }

  Future<void> saveProfileUserName(String name) async {
    try {
      final n = _cap(name.trim());
      if (n.isEmpty) return;
      _profileUserNameCache = n;
      await _setOptString(_kProfileUserName, n);
    } catch (_) {/* ignore */}
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
    } catch (_) {/* ignore */}
  }

  Future<void> setGreetingConsent(bool greetByName) async {
    try {
      _greetByNameCache = greetByName;
      await _setOptBool(_kIdentityGreetByName, greetByName);
    } catch (_) {/* ignore */}
  }

  Future<void> forgetIdentityName() async {
    try {
      _identityNameCache = null;
      _greetByNameCache = false;
      final dyn = _store as dynamic;
      try {
        final r = dyn.removeOpt?.call(_kIdentityName);
        if (r is Future) await r;
      } catch (_) {/* try next */}
      try {
        final r = dyn.setOptBool?.call(_kIdentityGreetByName, false);
        if (r is Future) await r;
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  Future<void> forgetProfileNames() async {
    try {
      _profileUserNameCache = null;
      _profileNicknamesCache = null;

      final dyn = _store as dynamic;
      try {
        final r = dyn.removeOpt?.call(_kProfileUserName);
        if (r is Future) await r;
      } catch (_) {/* try next */}
      try {
        final r = dyn.removeOpt?.call(_kProfileNicknames);
        if (r is Future) await r;
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
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
      } catch (_) {/* try next */}
      await forgetIdentityName();
      await forgetProfileNames();
    } catch (_) {/* ignore */}
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
      _identityNameCache =
          (n == null || n.trim().isEmpty) ? null : _cap(n.trim());
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
    } catch (_) {/* ignore */}
  }

  Future<void> learnNameFromText(String text, {bool greetByName = true}) async {
    if (!_enabled) return;
    try {
      final t = text.trim();
      if (t.isEmpty) return;

      final lower = t.toLowerCase();

      String? candidate;

      final patterns = <RegExp>[
        RegExp(r"\bich\s+hei(?:ß|ss|s|se)\s+([a-zäöüß\-\' ]+)",
            caseSensitive: false),
        RegExp(r"\bmein\s+name\s+ist\s+([a-zäöüß\-\' ]+)",
            caseSensitive: false),
        RegExp(r"\bmein\s+vorname\s+ist\s+([a-zäöüß\-\' ]+)",
            caseSensitive: false),
        RegExp(r"\bich\s+bin\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bnenn\s+mich\s+([a-zäöüß\-\' ]+)", caseSensitive: false),
        RegExp(r"\bman\s+nennt\s+mich\s+([a-zäöüß\-\' ]+)",
            caseSensitive: false),
        RegExp(r"\bdu\s+kannst\s+mich\s+([a-zäöüß\-\' ]+)\s+nennen",
            caseSensitive: false),
        RegExp(r"\bja(?:,\s*)?\s*einfach\s+([a-zäöüß\-\' ]+)\b",
            caseSensitive: false),
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

      // Nur das erste "Wort"
      final firstToken = candidate.split(RegExp(r"\s+")).first;

      String clean =
          firstToken.replaceAll(RegExp(r"[^a-zA-ZäöüÄÖÜß\-' ]"), '');
      clean = clean.replaceAll(' ', '');
      if (clean.length < 2) return;
      clean = _cap(clean);

      const banned = {'einfach', 'ja', 'okay', 'ok', 'nein', 'anonym', 'und', 'uund'};
      if (banned.contains(clean.toLowerCase())) return;

      await saveIdentityName(clean, greetByName: greetByName);
      await saveProfileUserName(clean);
    } catch (_) {/* ignore */}
  }

  // ---------------- Write: Konversation & Worker-Save ------------------------

  /// Public-API (D1): Einzelnen Insight-Fakt upserten (für Acknowledge-Layer/Badge).
  Future<void> saveInsightFact({
    String? sessionId,
    String? topic,
    required String line,
    double? score,
    String? activeFacet,
    String? topicPin,
    DateTime? createdAt,
  }) async {
    if (!_enabled) return;
    try {
      final ts = (createdAt ?? DateTime.now().toUtc());
      final fact = MemoryFact(
        id: 'f_${ts.millisecondsSinceEpoch}',
        type: FactType.insight,
        sessionId: (sessionId ?? '').trim().isEmpty ? null : sessionId!.trim(),
        topic: (topic ?? '').trim().isEmpty ? null : topic!.trim(),
        line: line.trim(),
        score: score,
        activeFacet:
            (activeFacet ?? '').trim().isEmpty ? null : activeFacet!.trim(),
        topicPin:
            (topicPin ?? '').trim().isEmpty ? null : topicPin!.trim(),
        createdAt: ts,
      );

      final s = _store as dynamic;
      try {
        final r = s.upsertFacts?.call([fact.toMap()]);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = s.upsertFact?.call(fact.toMap());
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = s.saveFact?.call(fact.toMap());
        if (r is Future) await r;
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  /// Public-API: Generischer Fakt (alle Typen), sicher upserten.
  Future<void> saveFact(MemoryFact fact) async {
    if (!_enabled) return;
    try {
      final map = fact.toMap();
      final s = _store as dynamic;
      try {
        final r = s.upsertFact?.call(map);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = s.saveFact?.call(map);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = s.upsertFacts?.call([map]);
        if (r is Future) await r;
        return;
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  /// Public-API: Batch-Speichern mehrerer Fakten (upsert bevorzugt).
  Future<void> saveFacts(List<MemoryFact> facts) async {
    if (!_enabled || facts.isEmpty) return;
    try {
      final maps = facts.map((f) => f.toMap()).toList(growable: false);
      final s = _store as dynamic;
      bool ok = false;
      try {
        final r = s.upsertFacts?.call(maps);
        if (r is Future) await r;
        ok = true;
      } catch (_) {/* try next */}
      if (!ok) {
        try {
          final r = s.saveFacts?.call(maps);
          if (r is Future) await r;
          ok = true;
        } catch (_) {/* try next */}
      }
      if (!ok) {
        for (final m in maps) {
          try {
            final r = s.upsertFact?.call(m);
            if (r is Future) await r;
          } catch (_) {
            try {
              final r2 = s.saveFact?.call(m);
              if (r2 is Future) await r2;
            } catch (_) {/* swallow */}
          }
        }
      }
    } catch (_) {/* ignore */}
  }

  /// Speichert tolerant aus einer Worker-Response (no-op, wenn disabled).
  /// Verarbeitet zusätzlich memories_to_save[] (Insights).
  /// **Neu (v6.6.1):** Upsert von last.topic/last.mood/last.date (kein Identity-Overwrite).
  Future<void> saveFromWorker(dynamic workerResponse, {String? source}) async {
    if (!_enabled) return;
    try {
      if (workerResponse is! Map) return;
      final map = Map<String, dynamic>.from(workerResponse);

      // 1) Standard-Mapper → Conversation/Facets (leicht)
      final entry = MemoryMapper.fromWorker(map); // nullable
      if (entry != null) {
        await _store.save(entry);
        // leichten Sync-Hint aktualisieren
        if (entry.contextFacets.isNotEmpty) {
          final sorted = [...entry.contextFacets]..sort((a, b) {
              final byHits = (b.hits).compareTo(a.hits);
              if (byHits != 0) return byHits;
              return (a.label).toLowerCase().compareTo((b.label).toLowerCase());
            });

          final facetKeys =
              sorted.map((f) => f.key).where((s) => s.trim().isNotEmpty).toList();
          final facetLabels = sorted
              .map((f) => f.label)
              .where((s) => s.trim().isNotEmpty)
              .toList();

          _lastHint = MemoryContextHint(
            facets: facetKeys.take(6).toList(growable: false),
            tags: null,
            topics: facetLabels.take(6).toList(growable: false),
          );
          _lastHintTs = DateTime.now();
        }
      }

      // 2) D1/E1 — Facts aus memories_to_save extrahieren und upserten
      final facts = MemoryMapper.factsFromWorker(map);
      if (facts.isNotEmpty) {
        final maps = facts.map((f) => f.toMap()).toList(growable: false);
        final s = _store as dynamic;

        bool savedBatch = false;
        try {
          final r = s.upsertFacts?.call(maps);
          if (r is Future) await r;
          savedBatch = true;
        } catch (_) {/* try next */}
        if (!savedBatch) {
          try {
            final r = s.saveFacts?.call(maps);
            if (r is Future) await r;
            savedBatch = true;
          } catch (_) {/* try next */}
        }
        if (!savedBatch) {
          for (final m in maps) {
            try {
              final r = s.upsertFact?.call(m);
              if (r is Future) await r;
            } catch (_) {
              try {
                final r2 = s.saveFact?.call(m);
                if (r2 is Future) await r2;
              } catch (_) {/* swallow */}
            }
          }
        }

        // Hint um activeFacet/topicPin aus dem ersten Fact ergänzen (sync)
        final first = facts.first;
        final af = (first.activeFacet ?? '').trim();
        final pin = (first.topicPin ?? '').trim();
        if (af.isNotEmpty || pin.isNotEmpty) {
          final base = _lastHint;
          _lastHint = MemoryContextHint(
            facets: base?.facets,
            tags: base?.tags,
            topics: base?.topics,
            identityName: base?.identityName,
            profileUserName: base?.profileUserName,
            profileNicknames: base?.profileNicknames,
            activeFacet: af.isNotEmpty ? af : base?.activeFacet,
            topicPin: pin.isNotEmpty ? pin : base?.topicPin,
          );
          _lastHintTs ??= DateTime.now();
        }
      }

      // 3) „last.*“ direkt aus Worker-Response extrahieren
      bool touchedLast = false;

      // 3a) last.topic – bevorzugt understanding.topic_shift
      String? _topicFromUnderstanding(Map<String, dynamic> root) {
        try {
          final u = root['understanding'];
          if (u is Map) {
            final m = Map<String, dynamic>.from(u);
            final t = (m['topic_shift'] ?? m['topicShift'] ?? m['topic'])
                ?.toString()
                .trim();
            if (t != null && t.isNotEmpty) return t;
          }
          final flat = (root['understanding.topic_shift'] ??
                  root['understanding_topic_shift'])
              ?.toString()
              .trim();
          if (flat != null && flat.isNotEmpty) return flat;
        } catch (_) {/* ignore */}
        return null;
      }

      String? lastTopic = _topicFromUnderstanding(map);

      // Fallback: memories_to_save[].topic
      if ((lastTopic ?? '').isEmpty) {
        try {
          final list = (map['memories_to_save'] as List?) ??
              (map['memoriesToSave'] as List?) ??
              const [];
          for (final it in list) {
            if (it is Map) {
              final m = Map<String, dynamic>.from(it);
              final t = (m['topic'] ?? m['last_topic'] ?? m['label'])
                  ?.toString()
                  .trim();
              if (t != null && t.isNotEmpty) {
                lastTopic = t;
                break;
              }
            }
          }
        } catch (_) {/* ignore */}
      }

      if ((lastTopic ?? '').isNotEmpty) {
        await _setOptString(_kLastTopic, lastTopic!.trim());
        // kleinen Pin setzen (sync)
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
        touchedLast = true;
      }

      // 3b) last.mood – flow.mood_prompt oder flow.mood
      String? _moodFromFlow(Map<String, dynamic> root) {
        try {
          final f = root['flow'];
          if (f is Map) {
            final m = Map<String, dynamic>.from(f);
            final v = (m['mood_prompt'] ?? m['moodPrompt'] ?? m['mood'])
                ?.toString()
                .trim();
            if (v != null && v.isNotEmpty) return v;
          }
          final flat = (root['mood'] ?? root['flow.mood_prompt'])
              ?.toString()
              .trim();
          if (flat != null && flat.isNotEmpty) return flat;
        } catch (_) {/* ignore */}
        return null;
      }

      final moodVal = _moodFromFlow(map);
      if ((moodVal ?? '').isNotEmpty) {
        await _setOptString(_kLastMood, moodVal!.trim());
        touchedLast = true;
      }

      // 3c) last.date – heute, wenn etwas an last.* geändert wurde
      if (touchedLast) {
        await _setOptString(_kLastDate, _ymd(DateTime.now().toUtc()));
      }

      // 4) Identity/Profile NICHT vom Worker übernehmen (Explizit v6.6.1-Regel).
      await _ingestMemoriesToSave(map, allowIdentity: false);

      // 5) Geo-Felder tolerant übernehmen (falls vorhanden)
      await _ingestGeoIfPresent(map);

      // 6) Timeline aus Worker-Plan/Feldern tolerant übernehmen (optional)
      await _ingestTimelineIfPresent(map);

      _invalidateSoftCaches();
    } catch (_) {
      // still
    }
  }

  /// Konversationszeile des Nutzers lokal protokollieren (best-effort).
  Future<void> saveUserTurn(String text, {Map<String, dynamic>? meta}) async {
    await _saveLine('user', text, meta: meta);
    // Sanfte Auto-Ableitung eines Timeline-Markers aus der User-Zeile
    try {
      await _maybeAutoTimelineFromText(role: 'user', text: text);
    } catch (_) {/* ignore */}
  }

  /// Konversationszeile des Panda lokal protokollieren (best-effort).
  Future<void> savePandaTurn(String text, {Map<String, dynamic>? meta}) async {
    await _saveLine('panda', text, meta: meta);
    // Panda-Zeilen erzeugen i. d. R. keinen Marker (nur bei klaren Selbstwert/Erkenntnis-Refs)
    try {
      await _maybeAutoTimelineFromText(role: 'panda', text: text, pandaRelaxed: true);
    } catch (_) {/* ignore */}
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
      } catch (_) {/* try next */}

      try {
        final r = dyn.saveAck?.call(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}

      safeAck.putIfAbsent('kind', () => 'ack');
      safeAck.putIfAbsent('ts', () => DateTime.now().toUtc().toIso8601String());
      try {
        final r = dyn.saveMap?.call(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = dyn.save?.call(safeAck);
        if (r is Future) await r;
        return;
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  Future<void> _saveLine(String role, String text,
      {Map<String, dynamic>? meta}) async {
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
      } catch (_) {/* try next */}

      try {
        final r = dyn.appendLine(role, text, m);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}
      try {
        final r = dyn.saveLine(role: role, text: text, meta: m);
        if (r is Future) await r;
        return;
      } catch (_) {/* try next */}

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
      } catch (_) {/* try next */}
      try {
        final r = dyn.save(map);
        if (r is Future) await r;
        return;
      } catch (_) {/* swallow */}
    } catch (_) {/* ignore */}
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
    } catch (_) {/* ignore */}
  }

  // ---------------- Read ------------------------------------------------------

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
          final aIdx =
              all.indexWhere((e) => e.contextFacets.any((f) => f.key == a));
          final bIdx =
              all.indexWhere((e) => e.contextFacets.any((f) => f.key == b));
          return aIdx.compareTo(bIdx);
        });

      final result = keys
          .take(limit)
          .map(
              (k) => Facet(key: k, label: labels[k] ?? k, hits: counts[k] ?? 1))
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
          DateTime.now().difference(_latestTopicsTs!).inSeconds <=
              _topicsTtlSec) {
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

  Future<List<String>> recentTopics({int limit = 6}) =>
      latestTopics(limit: limit);

  /// Liefert kompakte Recall-Liste (Labels) für UI-Brücken (intern).
  Future<List<dynamic>> recall({int limit = 6, String? topicHint}) async {
    try {
      final int takeN = (limit * 2).clamp(6, 24).toInt();
      final rawTopics = await latestTopics(limit: takeN);
      final seen = <String>{};
      final ranked = <String>[];

      final hint = (topicHint ?? '').trim().toLowerCase();
      final tmp = [...rawTopics];

      if (hint.isNotEmpty) {
        int score(String s) {
          final t = s.toLowerCase();
          if (t.startsWith(hint)) return 2;
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

      if (ranked.isNotEmpty) {
        return List<dynamic>.from(ranked);
      }

      final facets = await topFacets(limit: limit);
      final viaFacets = facets
          .map((f) => f.label.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);

      return List<dynamic>.from(viaFacets);
    } catch (_) {
      return const <dynamic>[];
    }
  }

  // ---------------- Sync-Hints & Memories für ApiService ---------------------

  /// **Synchroner** Hint für den Worker (klein, aus Cache).
  /// **Neu**: optionale Pins `activeFacet` / `topicPin`.
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
            topics = (hint.topics == null)
                ? null
                : hint.topics!.take(5).toList(growable: false);
            // Vorhandene Pins aus letztem Hint übernehmen, falls keine neuen kommen
            activeFacet ??= hint.activeFacet;
            topicPin ??= hint.topicPin;
          }
        }
      }

      // Namen rein aus Sync-Cache (niemals await!)
      final idName = (_identityNameCache ?? '').trim();
      final profName = (_profileUserNameCache ?? '').trim();
      final nicks = (_profileNicknamesCache ?? const <String>[])
          .where((e) => e.trim().isNotEmpty)
          .map((e) => e.trim())
          .take(5)
          .toList(growable: false);

      if ((facets == null || facets.isEmpty) &&
          (tags == null || tags.isEmpty) &&
          (topics == null || topics.isEmpty) &&
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

  /// Baut ein **kompaktes, kuratiertes** Kontext-Paket ≤2 KB für den Worker.
  /// Enthält **nur**: identity.name (bei Consent & Greet), last.topic, last.mood(+date),
  /// **NEU:** mood {last, trend} sowie **NEU:** timeline (bis 3 Tage, 1 Marker/Tag).
  Future<Map<String, dynamic>> buildContextMemories({required bool consent}) async {
    try {
      // Gate streng nach Projektstand: nur wenn enabled && consent && memoryActive
      if (!_enabled || !consent || !memoryActive) return const <String, dynamic>{};

      final out = <String, dynamic>{};

      // 1) Identity.name nur bei Consent + greetByName
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

      // 2) last.topic/mood/date – primär aus Opt-Keys, dann sanfte Fallbacks
      String? lastTopic = await _getOptString(_kLastTopic);
      String? lastMoodStr = await _getOptString(_kLastMood);
      String? lastDateStr = await _getOptString(_kLastDate);

      // Fallback topic: Pins/Topics/Facets
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

      // Fallback date: heute
      lastDateStr ??= _ymd(DateTime.now().toUtc());

      // mood numerisch, falls möglich (Kompatibilität: single value)
      dynamic moodField;
      if ((lastMoodStr ?? '').trim().isNotEmpty) {
        final s = lastMoodStr!.trim();
        final n = int.tryParse(s);
        moodField = n ?? s; // Zahl, falls parsebar; sonst String
      }

      // 3) Mood-Objekt (letzte Messung + Trend 3–7 Tage)
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
              'dir': moodTrend['dir'], // "up" | "down" | "flat"
            },
        };
        // Kompatibilität: "last.mood" (Einzahl) → avg-Wert, sofern nicht schon gesetzt
        if (moodField == null && moodLast != null) {
          moodField = moodLast['avg'];
        }
      }

      // 4) Timeline-Export (kompakt): bis 3 Tage, 1 Marker/Tag
      final timeline = await _exportTimeline(days: _timelineExportDays, perDay: _timelinePerDayExport);
      if (timeline.isNotEmpty) {
        out['timeline'] = timeline; // [{date, topic, tag?, valence}]
      }

      // 5) Zusammenstellen von "last" (Thema/Einzelwert + Datum)
      if ((lastTopic ?? '').isNotEmpty || moodField != null || (lastDateStr ?? '').isNotEmpty) {
        out['last'] = <String, dynamic>{
          if ((lastTopic ?? '').isNotEmpty) 'topic': lastTopic,
          if (moodField != null) 'mood': moodField,
          if ((lastDateStr ?? '').isNotEmpty) 'date': lastDateStr,
        };
      }

      // 6) share-Flag (klein, optional)
      if (_shareEnabled) {
        out['share'] = true;
      }

      // 7) Größenkappe ≤ 2048 Bytes (2 KB). Falls zu groß → aggressiv kürzen.
      List<int> bytes() => utf8.encode(jsonEncode(out));
      if (bytes().length > 2048) {
        // zuerst timeline komplett entfernen (niedrigste Priorität)
        out.remove('timeline');
      }
      if (bytes().length > 2048) {
        // dann share weglassen
        out.remove('share');
      }
      if (bytes().length > 2048) {
        // dann mood-Objekt komplett entfernen (da relativ größer)
        out.remove('mood');
      }
      if (bytes().length > 2048) {
        // dann "last.mood" entfernen
        (out['last'] as Map<String, dynamic>?)?.remove('mood');
      }
      if (bytes().length > 2048) {
        // topic härter kürzen
        final t = (out['last'] as Map<String, dynamic>?)?['topic']?.toString() ?? '';
        if (t.isNotEmpty) {
          (out['last'] as Map<String, dynamic>)['topic'] =
              (t.length <= 20) ? t : '${t.substring(0, 20).trimRight()}…';
        }
      }
      if (bytes().length > 2048) {
        // last komplett entfernen
        out.remove('last');
      }
      if (bytes().length > 2048) {
        // identity entfernen (als letzte Eskalation)
        out.remove('identity');
      }

      return out;
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  // ---------------- Byte-Kontext (sync, klein) ------------------------------

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

  List<int>? exportByteContext([int maxBytes = 2048]) =>
      tryGetByteContext(maxBytes);
  List<int>? byteContext([int maxBytes = 2048]) => tryGetByteContext(maxBytes);

  // ---------------- Recency/Timeline & Geo (S12.2 + v6.7.0) ------------------

  /// Legt einen lokalen Location-Breadcrumb an (PII-schonend; kein Autoshare).
  Future<void> recordLocation({
    String? label,
    double? lat,
    double? lon,
    double? accuracy,
    String? source, // "device" | "user" | "worker"
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

      // Store tolerant beschreiben
      final dyn = _store as dynamic;
      bool saved = false;

      try {
        final r = dyn.saveLocation?.call(stamp.toMap());
        if (r is Future) await r;
        saved = true;
      } catch (_) {/* try next */}
      if (!saved) {
        try {
          final r = dyn.saveMap?.call(stamp.toMap());
          if (r is Future) await r;
          saved = true;
        } catch (_) {/* try next */}
      }
      if (!saved) {
        try {
          final r = dyn.save?.call(stamp.toMap());
          if (r is Future) await r;
        } catch (_) {/* ignore */}
      }

      // Sync-Cache + Opt-Keys aktualisieren
      if ((stamp.label ?? '').trim().isNotEmpty) {
        _lastLocationLabelCache = stamp.label!.trim();
        await _setOptString(_kGeoLastLabel, _lastLocationLabelCache!);
      }
      _lastLocationTsCache = stamp.tsUtc;
      await _setOptString(_kGeoLastTs, stamp.tsUtc.toIso8601String());
      if (lat != null) await _setOptString(_kGeoLastLat, '$lat');
      if (lon != null) await _setOptString(_kGeoLastLon, '$lon');
      if (accuracy != null) await _setOptString(_kGeoLastAcc, '$accuracy');
    } catch (_) {/* ignore */}
  }

  /// Liefert das letzte, lokal bekannte Ortslabel (falls nicht zu alt).
  Future<String?> lastPlaceLabel({int maxAgeHours = 96}) async {
    try {
      // 1) Schnellpfad: Cache/Opt-Keys
      if (_lastLocationLabelCache != null && _lastLocationTsCache != null) {
        final ageH = DateTime.now().toUtc().difference(_lastLocationTsCache!).inHours;
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

      // 2) Optional: Store befragen
      try {
        final dyn = _store as dynamic;
        final r = await dyn.latestLocations?.call(limit: 1);
        if (r is List && r.isNotEmpty) {
          final crumb = LocationBreadcrumb.fromMap(r.first);
          if (crumb != null) {
            _lastLocationLabelCache = (crumb.label ?? '').trim().isEmpty ? null : crumb.label!.trim();
            _lastLocationTsCache = crumb.tsUtc;
            if (_lastLocationLabelCache != null) {
              await _setOptString(_kGeoLastLabel, _lastLocationLabelCache!);
              await _setOptString(_kGeoLastTs, _lastLocationTsCache!.toIso8601String());
            }
            return _lastLocationLabelCache;
          }
        }
      } catch (_) {/* ignore */}

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Baut eine leichte, zeitlich sortierte Timeline zuletzt gespeicherter Items.
  /// Enthält, sofern verfügbar: lines, facts, ack, location, timeline.
  Future<List<Map<String, dynamic>>> recentTimeline({
    int limit = 50,
    DateTime? sinceUtc,
  }) async {
    if (!_enabled) return const <Map<String, dynamic>>[];
    try {
      // 1) Falls Store eine native Timeline anbietet, diese nutzen
      try {
        final dyn = _store as dynamic;
        final r = await dyn.timeline?.call(limit: limit, sinceUtc: sinceUtc);
        if (r is List) {
          // defensive Kopie und Sortierung (älteste→neueste)
          final list = r
              .where((e) => e != null)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(growable: false);
          list.sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
          return list.take(limit).toList(growable: false);
        }
      } catch (_) {/* try fallback */}

      // 2) Fallback: aus verschiedenen Quellen zusammenbauen
      final out = <Map<String, dynamic>>[];

      // 2a) Konversations-Lines
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
      } catch (_) {/* ignore */}

      // 2b) Facts
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
      } catch (_) {/* ignore */}

      // 2c) Timeline Marker
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
      } catch (_) {/* ignore */}

      // 2d) Location Breadcrumbs
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
      } catch (_) {/* ignore */}

      // 2e) Acks (optional)
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
      } catch (_) {/* ignore */}

      // Filter by sinceUtc
      if (sinceUtc != null) {
        out.removeWhere((m) => _tsOf(m).isBefore(sinceUtc));
      }

      // Sortieren und limitieren (älteste→neueste)
      out.sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
      return out.take(limit).toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// Gruppiert die Timeline nach Tagen (YYYY-MM-DD → Events).
  Future<Map<String, List<Map<String, dynamic>>>> timelineByDay({
    int days = 7,
  }) async {
    try {
      final since = DateTime.now().toUtc().subtract(Duration(days: days));
      final events = await recentTimeline(limit: days * 64, sinceUtc: since);
      final map = <String, List<Map<String, dynamic>>>{};
      for (final e in events) {
        final ts = _tsOf(e);
        final key = _ymd(ts);
        // FIX: List-Initialisierung mit [] statt ().
        (map[key] ??= <Map<String, dynamic>>[]).add(e);
      }
      // täglich auf 64 begrenzen, stabil sortiert
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

  /// Liefert die letzten n Tages-Keys, an denen etwas passiert ist.
  Future<List<String>> recentDays({int days = 7}) async {
    try {
      final grouped = await timelineByDay(days: days);
      final keys = grouped.keys.toList(growable: false)
        ..sort((a, b) => a.compareTo(b));
      return keys.take(days).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  /// OPTIONAL: Liefert die letzten N Turns (role/text/ts) kompakt.
  /// Hinweis: Diese Funktion ist **nur für lokale/QA-Zwecke** gedacht und
  /// wird von buildContextMemories **nicht** verwendet.
  Future<List<Map<String, dynamic>>> toHistoryTurns({int lastN = 20}) async {
    if (!_enabled) return const <Map<String, dynamic>>[];
    try {
      final dyn = _store as dynamic;

      // 1) Direkt „latestLines“ bevorzugen
      try {
        final res = await dyn.latestLines?.call(limit: lastN);
        if (res is List) {
          final list = res
              .where((e) => e is Map)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .map((m) => <String, dynamic>{
                    'role': (m['role'] ?? '').toString(),
                    'text': (m['text'] ?? '').toString(),
                    'ts': (m['ts'] ?? m['created_at'] ?? m['createdAt'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
                  })
              .toList(growable: false);
          list.sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
          return list.take(lastN).toList(growable: false);
        }
      } catch (_) {/* try fallback */}

      // 2) Fallback: aus Timeline extrahieren
      final tl = await recentTimeline(limit: lastN * 3);
      final out = <Map<String, dynamic>>[];
      for (final e in tl) {
        final kind = (e['kind'] ?? '').toString();
        if (kind == 'line') {
          out.add(<String, dynamic>{
            'role': (e['role'] ?? '').toString(),
            'text': (e['text'] ?? '').toString(),
            'ts': (e['ts'] ?? e['created_at'] ?? e['createdAt'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
          });
        }
        if (out.length >= lastN) break;
      }
      return out.take(lastN).toList(growable: false);
    } catch (_) {
      // BUGFIX v6.7.1: korrekter Rückgabetyp im Fehlerfall
      return const <Map<String, dynamic>>[];
    }
  }

  // ---------------- Mood: Write & Read ---------------------------------------

  /// Speichert eine 2-Parameter-Stimmung. Tages-De-Dup: max 2 Einträge/Tag.
  Future<void> saveMoodEntry({
    DateTime? tsUtc,
    required int mental,
    required int physical,
    String? note,
  }) async {
    if (!_enabled) return;
    try {
      final now = (tsUtc ?? DateTime.now().toUtc());
      final m = mental.clamp(1, 5);
      final p = physical.clamp(1, 5);
      final entry = MoodEntry(
        id: 'm_${now.millisecondsSinceEpoch}',
        tsUtc: now,
        mental: m,
        physical: p,
        note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      );

      // 1) Persist tolerant (Store-Funktionen verschieden benannt)
      final dyn = _store as dynamic;
      bool saved = false;
      try {
        final r = await dyn.saveMoodEntry?.call(entry.toMap());
        if (r is bool && r == true) saved = true;
      } catch (_) {/* try next */}
      if (!saved) {
        try {
          final r = await dyn.upsertMoodEntry?.call(entry.toMap());
          if (r is bool && r == true) saved = true;
        } catch (_) {/* try next */}
      }
      if (!saved) {
        // Fallback über Facts (type: mood)
        try {
          final map = {
            ...entry.toMap(),
            'type': 'mood',
          };
          final r = await dyn.upsertFact?.call(map);
          if (r is bool && r == true) saved = true;
          if (!saved) {
            await dyn.saveFact?.call(map);
            saved = true;
          }
        } catch (_) {/* swallow */}
      }

      // 2) Tages-De-Dup: max 2/Tag → falls mehr, älteste löschen
      try {
        final day = _ymd(now);
        final list = await _readMoodEntriesByDay(day);
        if (list.length > 2) {
          // sort by ts asc, remove extras from start
          list.sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
          final toRemove = list.length - 2;
          for (int i = 0; i < toRemove; i++) {
            final rem = list[i];
            try {
              await dyn.removeMoodEntry?.call(rem.id);
            } catch (_) {
              // fallback: remove by map
              try {
                await dyn.removeFactById?.call(rem.id);
              } catch (_) {/* ignore */}
            }
          }
        }
      } catch (_) {/* ignore */}

      // 3) Opt-Keys für "mood.last.*" + Kompatibilität "last.mood"
      final dayKey = _ymd(now);
      await _setOptString(_kMoodLastMental, '$m');
      await _setOptString(_kMoodLastPhysical, '$p');
      await _setOptString(_kMoodLastDate, dayKey);

      final avg = ((m + p) / 2.0);
      await _setOptString(_kLastMood, avg.toStringAsFixed(avg % 1 == 0 ? 0 : 1));
      await _setOptString(_kLastDate, dayKey);
    } catch (_) {/* ignore */}
  }

  /// Public-API: letzte Stimmung lesen (kompakt).
  Future<Map<String, dynamic>?> getLastMood() async {
    return await _readLastMoodExpanded();
  }

  /// Public-API: Trend über Fenster (3..7 Tage). Default 7.
  Future<Map<String, dynamic>?> computeMoodTrend({int windowDays = 7}) async {
    final int d = windowDays < 3 ? 3 : (windowDays > 7 ? 7 : windowDays);
    return await _computeMoodTrend(days: d, minDays: 3);
  }

  /// Liest die letzte Stimmung (mental/physical) kompakt als Map.
  Future<Map<String, dynamic>?> _readLastMoodExpanded() async {
    try {
      // Bevorzugt aus Opt-Keys (schnell, robust)
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

      // Fallback: aus Store lesen
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

  /// Liefert Mood-Entries eines Tages (YYYY-MM-DD) tolerant.
  Future<List<MoodEntry>> _readMoodEntriesByDay(String ymd) async {
    final out = <MoodEntry>[];
    try {
      final dyn = _store as dynamic;
      // 1) native Day-Query
      try {
        final res = await dyn.moodEntriesByDay?.call(ymd);
        if (res is List) {
          for (final e in res) {
            final me = MoodEntry.fromMap(e);
            if (me != null && me.dayKey == ymd) out.add(me);
          }
          return out;
        }
      } catch (_) {/* try next */}

      // 2) latestMoodEntries + Filter
      try {
        final res = await dyn.latestMoodEntries?.call(limit: 10);
        if (res is List) {
          for (final e in res) {
            final me = MoodEntry.fromMap(e);
            if (me != null && me.dayKey == ymd) out.add(me);
          }
          return out;
        }
      } catch (_) {/* try next */}

      // 3) Fallback über latestFacts(type==mood)
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
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
    return out;
  }

  /// Liest die letzten N Tage (bis zu `days`) als ein Tagesmittel (mental/physical).
  Future<List<MoodEntry>> _readMoodWindow({int days = 7}) async {
    final out = <MoodEntry>[];
    try {
      final dyn = _store as dynamic;
      // 1) native API
      try {
        final res = await dyn.moodWindow?.call(days: days);
        if (res is List) {
          for (final e in res) {
            final me = MoodEntry.fromMap(e);
            if (me != null) out.add(me);
          }
          // sort asc by ts
          out.sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
          return out;
        }
      } catch (_) {/* try next */}

      // 2) latestMoodEntries; wir deduplizieren per Tag (max 2 -> Mittel)
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
            final avgM = (take.map((e) => e.mental).reduce((a, b) => a + b) / take.length).round();
            final avgP = (take.map((e) => e.physical).reduce((a, b) => a + b) / take.length).round();
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
      } catch (_) {/* try next */}

      // 3) Fallback latestFacts(type==mood)
      try {
        final res = await dyn.latestFacts?.call(limit: days * 6);
        if (res is List) {
          final tmp = <String, List<MoodEntry>>{};
          for (final e in res) {
            if (e is Map) {
              final t = (e['type'] ?? '').toString().toLowerCase();
              if (t == 'mood') {
                final me = MoodEntry.fromMap(e);
                if (me == null) continue;
                (tmp[me.dayKey] ??= <MoodEntry>[]).add(me);
              }
            }
          }
          final keys = tmp.keys.toList()..sort();
          for (final k in keys.takeLast(days)) {
            final list = tmp[k]!..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
            final take = list.length <= 2 ? list : [list[list.length - 2], list.last];
            final avgM = (take.map((e) => e.mental).reduce((a, b) => a + b) / take.length).round();
            final avgP = (take.map((e) => e.physical).reduce((a, b) => a + b) / take.length).round();
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
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
    return out;
  }

  /// Berechnet einen einfachen Trend über 3–7 Tage.
  /// Delta = letzter Tag – gleitendes Mittel der vorigen N-1 Tage.
  Future<Map<String, dynamic>?> _computeMoodTrend({int days = 7, int minDays = 3}) async {
    try {
      final win = await _readMoodWindow(days: days.clamp(3, 7));
      if (win.length < minDays) return null;
      // letztes Element = "heute/zuletzt"
      final last = win.last;
      if (win.length == 1) {
        return {
          'days': 1,
          'mental_delta': 0,
          'physical_delta': 0,
          'dir': 'flat',
        };
      }
      final prev = win.sublist(0, win.length - 1);
      double avgM = prev.map((e) => e.mental).fold<double>(0, (a, b) => a + b) / prev.length;
      double avgP = prev.map((e) => e.physical).fold<double>(0, (a, b) => a + b) / prev.length;

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

      double _round1(double v) => double.parse(v.toStringAsFixed(1));

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

  /// Sparkline-Werte für Pro-Screen (klein). Gibt z. B. [3,3,4,5,4] zurück.
  Future<List<int>> moodSparkline({int days = 7, String kind = 'avg'}) async {
    try {
      final win = await _readMoodWindow(days: days.clamp(3, 14));
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
      return vals.takeLast(days).toList(growable: false);
    } catch (_) {
      return const <int>[];
    }
  }

  // ---------------- Timeline API (Write & Read) ------------------------------

  /// Öffentliche API: expliziten Timeline-Marker speichern/mergen.
  /// topic → kurzer Themenstring; valence → -2..+2; tags optional (werden auf bekannte reduziert).
  Future<void> saveTimelineMarker({
    required String topic,
    required int valence,
    DateTime? tsUtc,
    List<String>? tags,
    String? source, // "user" | "panda" | "worker" | "journal"
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

      // 1) Merge: gleicher Tag + Topic → mitteln & count++
      final merged = await _mergeTimelineForDay(marker);

      // 2) Caps pro Tag anwenden
      await _capTimelineForDay(merged.tsUtc);

      // 3) Optional: "last.topic" aktualisieren (sanft)
      try {
        if ((await _getOptString(_kLastTopic)) == null || (await _getOptString(_kLastTopic))!.trim().isEmpty) {
          await _setOptString(_kLastTopic, merged.topic);
          await _setOptString(_kLastDate, merged.dayKey);
        }
      } catch (_) {/* ignore */}
    } catch (_) {/* ignore */}
  }

  /// Heuristische Auto-Ableitung eines Markers aus einem Turn (User/Panda/Journal).
  Future<void> _maybeAutoTimelineFromText({
    required String role, // "user" | "panda"
    required String text,
    DateTime? tsUtc,
    bool pandaRelaxed = false,
  }) async {
    final raw = text.trim();
    if (raw.isEmpty) return;

    // 1) Topic-Ableitung (einfach): bevorzugt bekannte Tags/Wörter
    final topic = _inferTopicFromText(raw);
    if (topic == null) return;

    // Panda-Zeilen sehr restriktiv interpretieren
    if (role == 'panda' && pandaRelaxed == true) {
      // Nur für klare Selbstwert-Spiegelungen
      final l = raw.toLowerCase();
      final isSelfWorth = RegExp(r'\b(stolz|wert|wertvoll|selbstwert)\b').hasMatch(l);
      if (!isSelfWorth) return;
    }

    // 2) Valence aus Mood (letzter avg) bzw. Sentiment-Wörtern
    int val = 0;
    try {
      final last = await _readLastMoodExpanded();
      if (last != null) {
        final avg = (last['avg'] as num?)?.toDouble() ?? 3.0;
        val = _valenceFromMoodAvg(avg);
      } else {
        val = _valenceFromText(raw);
      }
    } catch (_) {/* ignore */}

    // 3) Tags ableiten + speichern
    final tags = _inferTagsFrom(topic: topic, text: raw);
    await saveTimelineMarker(
      topic: topic,
      valence: val,
      tsUtc: tsUtc,
      tags: tags,
      source: role,
    );
  }

  /// Timeline-Export für context.memories.timeline (kompakt).
  Future<List<Map<String, dynamic>>> _exportTimeline({
    int days = 3,
    int perDay = 1,
  }) async {
    try {
      final out = <Map<String, dynamic>>[];
      final dyn = _store as dynamic;

      // Bevorzugt native API: timelineMarkersWindow
      List<dynamic>? raw;
      try {
        raw = await dyn.timelineMarkersWindow?.call(days: days);
      } catch (_) {/* ignore */}

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
          // jüngste priorisieren, bei mehreren → höchste |valence| bevorzugen
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

      // Fallback: latestTimelineMarkers + Gruppierung
      List<dynamic>? latest;
      try {
        latest = await dyn.latestTimelineMarkers?.call(limit: days * 6);
      } catch (_) {/* ignore */}

      final tmp = <String, List<TimelineMarker>>{};
      if (latest is List && latest.isNotEmpty) {
        for (final e in latest) {
          final m = TimelineMarker.fromMap(e);
          if (m == null) continue;
          (tmp[m.dayKey] ??= <TimelineMarker>[]).add(m);
        }
      }

      // Eventueller Fallback über latestFacts(type==timeline)
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
        } catch (_) {/* ignore */}
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

  /// Merged einen Marker auf Tagesebene (gleicher Tag + Topic → zusammenfassen).
  Future<TimelineMarker> _mergeTimelineForDay(TimelineMarker m) async {
    final dyn = _store as dynamic;
    final day = m.dayKey;
    List<dynamic>? raw;
    try {
      raw = await dyn.timelineMarkersByDay?.call(day);
    } catch (_) {/* ignore */}

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
      // Fallback: latestTimelineMarkers + Filter
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
      } catch (_) {/* ignore */}
    }

    if (existing == null) {
      // direkt speichern
      final map = m.toMap();
      bool saved = false;
      try {
        final r = await dyn.saveTimelineMarker?.call(map);
        if (r is bool && r == true) saved = true;
      } catch (_) {/* try next */}
      if (!saved) {
        try {
          final r = await dyn.upsertTimelineMarker?.call(map);
          if (r is bool && r == true) saved = true;
        } catch (_) {/* try next */}
      }
      if (!saved) {
        // Fallback über Fact
        try {
          final fm = {
            ...map,
            'type': 'timeline',
          };
          final r = await dyn.upsertFact?.call(fm);
          if (r is! bool) {
            await dyn.saveFact?.call(fm);
          }
        } catch (_) {/* ignore */}
      }
      return m;
    }

    // Merge: valence mitteln (gewichtetes Mittel über count), count++
    final totalCount = (existing.count + 1);
    final mergedVal = ((existing.valence * existing.count + m.valence) / totalCount).round();
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
    } catch (_) {/* try next */}
    if (!ok) {
      try {
        final fm = {
          ...map,
          'type': 'timeline',
        };
        final r = await dyn.upsertFact?.call(fm);
        if (r is! bool) {
          await dyn.saveFact?.call(fm);
        }
        ok = true;
      } catch (_) {/* ignore */}
    }
    return merged;
  }

  /// Erzwingt Tages-Caps: max 3 Marker/Tag, max 2 je Tag-Kategorie/Tag (neueste behalten).
  Future<void> _capTimelineForDay(DateTime dayTs) async {
    try {
      final dyn = _store as dynamic;
      final day = _ymd(dayTs);
      List<TimelineMarker> list = [];
      try {
        final raw = await dyn.timelineMarkersByDay?.call(day);
        if (raw is List) {
          list = raw.map((e) => TimelineMarker.fromMap(e)).whereType<TimelineMarker>().toList();
        }
      } catch (_) {/* ignore */}
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
        } catch (_) {/* ignore */}
      }
      if (list.isEmpty) return;

      // Sort: neueste zuerst, dann |valence|, dann count
      list.sort((a, b) {
        final byTs = b.tsUtc.compareTo(a.tsUtc);
        if (byTs != 0) return byTs;
        final byAbs = b.valence.abs().compareTo(a.valence.abs());
        if (byAbs != 0) return byAbs;
        return (b.count).compareTo(a.count);
      });

      // pro Tag-Kategorie Deckel 2
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

      // Entferne Rest
      final toDrop = list.where((m) => !kept.any((k) => k.id == m.id)).toList();
      for (final m in toDrop) {
        try {
          final r = await dyn.removeTimelineMarkerById?.call(m.id);
          if (r is! bool) {
            await dyn.removeFactById?.call(m.id);
          }
        } catch (_) {/* ignore */}
      }
    } catch (_) {/* ignore */}
  }

  // ---------------- KUTSCHE 5: Recall (Rückblick & Entwicklung) --------------

  /// Public-API: Baut eine sanfte Wochen-/Monatszusammenfassung mit kleinen Kennwerten.
  /// Gibt immer ein Map zurück:
  /// {
  ///   "days": 7|30,
  ///   "text": "<DE-Zusammenfassung>",
  ///   "mood": { "avg": 3.7, "prev_avg": 3.4, "delta": 0.3, "dir": "up|down|flat",
  ///             "mental_avg": 4.0, "physical_avg": 3.4, "sample_days": 6 },
  ///   "topics": [ { "topic":"arbeit","count":3,"valence_avg":0.3 }, ... ],
  ///   "insights": [ {"line":"…","score":0.82}, ... ] // max 3
  /// }
  Future<Map<String, dynamic>> buildRecallSummary({int days = 7}) async {
    final d = days < 7 ? 7 : (days > 30 ? 30 : days);
    try {
      // --- Mood: aktuelles Fenster vs. vorheriges gleich langes Fenster ---
      final mood2x = await _readMoodWindow(days: d * 2);
      List<MoodEntry> cur = mood2x.takeLast(d);
      List<MoodEntry> prev = mood2x.length > d
          ? mood2x.sublist((mood2x.length - d * 2).clamp(0, mood2x.length - d), mood2x.length - d)
          : const <MoodEntry>[];

      double _avg(List<int> xs) => xs.isEmpty ? 0.0 : xs.reduce((a, b) => a + b) / xs.length;

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

      // --- Timeline: häufige Themen + Valence ---
      final markers = await _readTimelineWindow(days: d);
      final byTopic = <String, List<int>>{}; // topic -> list of valences
      for (final m in markers) {
        (byTopic[m.topic] ??= <int>[]).add(m.valence);
      }
      final topicStats = <Map<String, dynamic>>[];
      byTopic.forEach((topic, vals) {
        final cnt = vals.length;
        final mean = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
        topicStats.add({
          'topic': topic,
          'count': cnt,
          'valence_avg': _round1(mean.toDouble()),
        });
      });
      topicStats.sort((a, b) {
        final byCount = (b['count'] as int).compareTo(a['count'] as int);
        if (byCount != 0) return byCount;
        // bei Gleichstand → stärkere |valence|-Tendenz
        final av = (a['valence_avg'] as num).abs().toDouble();
        final bv = (b['valence_avg'] as num).abs().toDouble();
        return bv.compareTo(av);
      });
      final topicsTop = topicStats.take(3).toList(growable: false);

      // --- Insights: letzte kleine Einsichten im Fenster ---
      final insights = await _readInsightsWindow(days: d, limit: 8);
      final topInsights = insights.take(3).map((f) {
        return {
          'line': (f.line ?? '').trim(),
          if (f.score != null) 'score': _round2(f.score!),
        };
      }).where((m) => (m['line'] as String).isNotEmpty).toList(growable: false);

      // --- Text: sanfte DE-Zusammenfassung ---
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
        if (labels.length == 1) {
          return 'Dein Fokus lag häufig auf ${labels.first}.';
        }
        if (labels.length == 2) {
          return 'Oft ging es um ${labels[0]} und ${labels[1]}.';
        }
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

  // ---------------- KUTSCHE 6: Story-Bundle (gebündelte Daten) ---------------

  /// Public-API: Liefert ein gebündeltes Paket für Story-/PDF-Builder.
  /// Standard ist PII-schonend (includeIdentity=false, redact=true).
  ///
  /// Rückgabe (Beispiel-Shape):
  /// {
  ///   "generated_at": "2025-11-07T21:12:00Z",
  ///   "days": 30,
  ///   "identity": {"name":"Matthias"}? // nur wenn includeIdentity && shareEnabled && greetByName
  ///   "last_place": "Home"?,
  ///   "recall": {...},               // aus buildRecallSummary(days)
  ///   "sparkline": {"avg":[...], "mental":[...], "physical":[...]},
  ///   "timeline": [{"date":"2025-11-06","topic":"arbeit","tag":"arbeit","valence":1}, ...],
  ///   "topics": [...],               // aus recall.topics
  ///   "insights": [...],             // aus recall.insights
  ///   "history": [{"role":"user","text":"…","ts":"…"}, ...] // redacted falls aktiviert
  /// }
  Future<Map<String, dynamic>> buildStoryBundle({
    int days = 30,
    bool includeIdentity = false,
    int maxHistory = 24,
    bool redact = true,
  }) async {
    final d = days < 7 ? 7 : (days > 90 ? 90 : days); // Story darf bis 90d gehen
    try {
      final bundle = <String, dynamic>{
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'days': d,
      };

      // Identity optional und nur bei expliziter Freigabe sinnvoll
      if (includeIdentity && _shareEnabled && (_greetByNameCache == true)) {
        final name = (_identityNameCache ?? '').trim().isEmpty
            ? (await loadGreetingName()).name
            : _identityNameCache;
        if ((name ?? '').toString().trim().isNotEmpty) {
          bundle['identity'] = {'name': _cap(name!.trim())};
        }
      }

      // Letzter Ort (PII-schonend; nur Label)
      final place = await lastPlaceLabel(maxAgeHours: 96);
      if ((place ?? '').toString().trim().isNotEmpty) {
        bundle['last_place'] = place!.trim();
      }

      // Recall (Mood/Topics/Insights)
      final recall = await buildRecallSummary(days: d < 7 ? 7 : (d <= 30 ? d : 30));
      bundle['recall'] = recall;

      // Sparkline: avg/mental/physical
      final sparkAvg = await moodSparkline(days: (d <= 14 ? d : 14), kind: 'avg');
      final sparkMental = await moodSparkline(days: (d <= 14 ? d : 14), kind: 'mental');
      final sparkPhysical = await moodSparkline(days: (d <= 14 ? d : 14), kind: 'physical');
      bundle['sparkline'] = {
        'avg': sparkAvg,
        'mental': sparkMental,
        'physical': sparkPhysical,
      };

      // Timeline-Fenster komplett (bis d Tage, kompakt)
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

      // Topics/Insights 1:1 aus Recall (praktisch für Builder)
      bundle['topics'] = recall['topics'] ?? const <Map<String, dynamic>>[];
      bundle['insights'] = recall['insights'] ?? const <Map<String, dynamic>>[];

      // History (letzte Turns) — für Story-Zitatblasen (redacted by default)
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

  /// Public-API: Liefert die letzten N Zeilen (user/panda) für Story-Zitate.
  /// `redact` ersetzt E-Mails/URLs/Telefonnummern durch Platzhalter.
  Future<List<Map<String, dynamic>>> storyHistory({
    int lastN = 24,
    bool redact = true,
  }) async {
    try {
      final lines = await toHistoryTurns(lastN: lastN.clamp(4, 60));
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

  // ---------------- interne Helfer ------------------------------------------

  /// Timeline-Marker der letzten `days` Tage (sanft; nutzt native API oder Fallback).
  Future<List<TimelineMarker>> _readTimelineWindow({required int days}) async {
    final out = <TimelineMarker>[];
    try {
      final dyn = _store as dynamic;

      // 1) Bevorzugt: timelineMarkersWindow(days)
      try {
        final raw = await dyn.timelineMarkersWindow?.call(days: days);
        if (raw is List) {
          for (final e in raw) {
            final tm = TimelineMarker.fromMap(e);
            if (tm != null) out.add(tm);
          }
        }
      } catch (_) {/* ignore */}

      // 2) Fallback: latestTimelineMarkers & Filter auf Tage-Keys
      if (out.isEmpty) {
        final dayKeys = <String>{};
        for (int i = 0; i < days; i++) {
          dayKeys.add(_ymd(DateTime.now().toUtc().subtract(Duration(days: i))));
        }
        try {
          final raw = await dyn.latestTimelineMarkers?.call(limit: days * 6);
          if (raw is List) {
            for (final e in raw) {
              final tm = TimelineMarker.fromMap(e);
              if (tm != null && dayKeys.contains(tm.dayKey)) out.add(tm);
            }
          }
        } catch (_) {/* ignore */}

        // 3) weiterer Fallback über latestFacts(type == timeline)
        if (out.isEmpty) {
          try {
            final facts = await dyn.latestFacts?.call(limit: days * 8);
            if (facts is List) {
              for (final e in facts) {
                if (e is Map) {
                  final mm = Map<String, dynamic>.from(e);
                  final t = (mm['type'] ?? mm['kind'] ?? '').toString().toLowerCase();
                  if (t == 'timeline' || t == 'timeline_marker') {
                    final tm = TimelineMarker.fromMap(mm);
                    if (tm != null && dayKeys.contains(tm.dayKey)) out.add(tm);
                  }
                }
              }
            }
          } catch (_) {/* ignore */}
        }
      }

      // sort: älteste→neueste
      out.sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
      return out;
    } catch (_) {
      return const <TimelineMarker>[];
    }
  }

  /// Liest Insight-Fakten innerhalb des Fensters (letzte `days` Tage), neueste zuerst.
  Future<List<MemoryFact>> _readInsightsWindow({required int days, int limit = 8}) async {
    final out = <MemoryFact>[];
    try {
      final since = DateTime.now().toUtc().subtract(Duration(days: days));
      final dyn = _store as dynamic;
      try {
        final raw = await dyn.latestFacts?.call(limit: limit * 3);
        if (raw is List) {
          for (final e in raw) {
            if (e is Map) {
              final mm = Map<String, dynamic>.from(e);
              final type = (mm['type'] ?? '').toString().toLowerCase();
              if (type == 'insight') {
                final f = MemoryFact.fromMap(mm);
                if (f.createdAt != null && f.createdAt!.toUtc().isBefore(since)) continue;
                out.add(f);
                if (out.length >= limit) break;
              }
            }
          }
        }
      } catch (_) {/* ignore */}
      // Neueste zuerst
      out.sort((a, b) {
        final ta = (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)).toUtc();
        final tb = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)).toUtc();
        return tb.compareTo(ta);
      });
      return out;
    } catch (_) {
      return const <MemoryFact>[];
    }
  }

  void _invalidateSoftCaches() {
    _latestTopicsCache = null;
    _latestTopicsTs = null;
    _topFacetsCache = null;
    _topFacetsTs = null;
  }

  bool? _tryReadShareEnabledReflective() {
    try {
      final dyn = _store as dynamic;
      final v = dyn.isShareEnabled;
      if (v is bool) return v;
    } catch (_) {/* ignore */}
    try {
      final dyn = _store as dynamic;
      final res = dyn.getShareEnabled();
      if (res is bool) return res;
    } catch (_) {/* ignore */}
    return null;
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // -- kleine Key/Value-Utils -------------------------------------------------

  Future<void> _setOptString(String key, String value) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOptString(key, value);
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOpt(key, value);
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setKey(key, value);
      if (r is Future) await r;
    } catch (_) {/* ignore */}
  }

  Future<String?> _getOptString(String key) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.getOptString(key);
      if (r is String) return r;
      if (r is Future) {
        final v = await r;
        if (v is String) return v;
      }
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.getOpt(key);
      if (r is String) return r;
      if (r is Future) {
        final v = await r;
        if (v is String) return v;
      }
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.getKey(key);
      if (r is String) return r;
      if (r is Future) {
        final v = await r;
        if (v is String) return v;
      }
    } catch (_) {/* ignore */}
    return null;
  }

  Future<void> _setOptStringList(String key, List<String> values) async {
    try {
      final json = jsonEncode(values);
      await _setOptString(key, json);
    } catch (_) {/* ignore */}
  }

  Future<List<String>?> _getOptStringList(String key) async {
    try {
      final raw = await _getOptString(key);
      if (raw == null || raw.trim().isEmpty) return null;
      final v = jsonDecode(raw);
      if (v is List) {
        return v
            .where((e) => e != null)
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {/* ignore */}
    return null;
  }

  Future<void> _setOptBool(String key, bool value) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOptBool(key, value);
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setOpt(key, value);
      if (r is Future) await r;
      return;
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.setFlag(key, value);
      if (r is Future) await r;
    } catch (_) {/* ignore */}
  }

  Future<bool?> _getOptBool(String key) async {
    try {
      final dyn = _store as dynamic;
      final r = dyn.getOptBool(key);
      if (r is bool) return r;
      if (r is Future) {
        final v = await r;
        if (v is bool) return v;
      }
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.getOpt(key);
      if (r is bool) return r;
      if (r is Future) {
        final v = await r;
        if (v is bool) return v;
      }
    } catch (_) {/* try next */}
    try {
      final dyn = _store as dynamic;
      final r = dyn.getFlag(key);
      if (r is bool) return r;
      if (r is Future) {
        final v = await r;
        if (v is bool) return v;
      }
    } catch (_) {/* ignore */}
    return null;
  }

  static List<String> _parseStringList(dynamic v) {
    if (v == null) return const <String>[];
    if (v is List) {
      return v
          .where((e) => e != null)
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return const <String>[];
      return s
          .split(RegExp(r'[,\n;]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  // -- Export-Redaktion (sanft, lokal) ----------------------------------------

  /// Ersetzt E-Mails, URLs und Telefonnummern (≥6 Ziffern, inkl. Trennzeichen) durch Platzhalter.
  String _redactForExport(String s) {
    try {
      var out = s;

      // E-Mail
      out = out.replaceAll(RegExp(r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}', caseSensitive: false), '[email]');

      // URLs (http/https/www)
      out = out.replaceAll(RegExp(r'\b((https?:\/\/|www\.)\S+)', caseSensitive: false), '[link]');

      // Telefonnummern/Nummernfolgen ≥6 Ziffern (erlaubt Leerzeichen, +, -, /, (), .)
      out = out.replaceAll(RegExp(r'(?:(?<!\d)[+()]?[\d\s\-/().]{0,3})?(?:\d[\d\s\-/().]){5,}\d'), '[number]');

      // Mehrfache Platzhalter zusammenziehen
      out = out.replaceAll(RegExp(r'(\[(email|link|number)\])\s+(\[(email|link|number)\])'), r'$1 $3');

      return out;
    } catch (_) {
      return s;
    }
  }

  // -- Misc Helpers -----------------------------------------------------------

  /// Liest die letzte Stimmung (mood) aus dem Store, falls verfügbar.
  /// Unterstützt mehrere mögliche Store-Signaturen.
  Future<({String? value, DateTime? date})> _readLastMood() async {
    try {
      final dyn = _store as dynamic;

      // 1) Bevorzugt: dedicated API latestMood / lastMoodEntry
      try {
        final m = await dyn.latestMood?.call();
        if (m is Map) {
          final mm = Map<String, dynamic>.from(m);
          final val = (mm['value'] ?? mm['mood'] ?? mm['name'])?.toString().trim();
          final tsRaw = (mm['date'] ?? mm['ts'] ?? mm['created_at'] ?? mm['createdAt'])?.toString();
          final ts = (tsRaw == null || tsRaw.trim().isEmpty) ? null : DateTime.tryParse(tsRaw)?.toUtc();
          if ((val ?? '').toString().trim().isNotEmpty) return (value: val, date: ts);
        }
      } catch (_) {/* try next */}
      try {
        final m = await dyn.lastMoodEntry?.call();
        if (m is Map) {
          final mm = Map<String, dynamic>.from(m);
          final val = (mm['value'] ?? mm['mood'] ?? mm['name'])?.toString().trim();
          final tsRaw = (mm['date'] ?? mm['ts'] ?? mm['created_at'] ?? mm['createdAt'])?.toString();
          final ts = (tsRaw == null || tsRaw.trim().isEmpty) ? null : DateTime.tryParse(tsRaw)?.toUtc();
          if ((val ?? '').toString().trim().isNotEmpty) return (value: val, date: ts);
        }
      } catch (_) {/* try next */}

      // 2) Fallback: über latestFacts (type == 'mood')
      try {
        final facts = await dyn.latestFacts?.call(limit: 10);
        if (facts is List) {
          for (final e in facts) {
            if (e is Map) {
              final mm = Map<String, dynamic>.from(e);
              final type = (mm['type'] ?? '').toString().toLowerCase();
              if (type == 'mood') {
                final val = (mm['value'] ?? mm['line'] ?? mm['mood'])?.toString().trim();
                final tsRaw = (mm['ts'] ?? mm['created_at'] ?? mm['createdAt'] ?? mm['date'])?.toString();
                final ts = (tsRaw == null || tsRaw.trim().isEmpty) ? null : DateTime.tryParse(tsRaw)?.toUtc();
                if ((val ?? '').isNotEmpty) return (value: val, date: ts);
              }
            }
          }
        }
      } catch (_) {/* ignore */}

      // nichts gefunden
      return (value: null, date: null);
    } catch (_) {
      return (value: null, date: null);
    }
  }

  static DateTime _tsOf(Map<String, dynamic> m) {
    try {
      final raw = (m['ts'] ?? m['created_at'] ?? m['createdAt'])?.toString();
      if (raw != null && raw.trim().isNotEmpty) {
        return DateTime.parse(raw).toUtc();
      }
    } catch (_) {/* ignore */}
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static String _ymd(DateTime dtUtc) {
    final y = dtUtc.year.toString().padLeft(4, '0');
    final m = dtUtc.month.toString().padLeft(2, '0');
    final d = dtUtc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _clampValence(int v) => v < -2 ? -2 : (v > 2 ? 2 : v);

  int _valenceFromMoodAvg(double avg) {
    // Map 1..5 → -2..+2 (3 = 0)
    if (avg <= 1.5) return -2;
    if (avg <= 2.5) return -1;
    if (avg < 3.5) return 0;
    if (avg < 4.5) return 1;
    return 2;
  }

  int _valenceFromText(String t) {
    final s = t.toLowerCase();
    final neg2 = RegExp(r'\b(furchtbar|schrecklich|katastrophal|panik|verzweifelt)\b');
    final neg1 = RegExp(r'\b(schwer|müde|erschöpft|traurig|nervös|gestresst)\b');
    final pos2 = RegExp(r'\b(großartig|grossartig|wundervoll|fantastisch|super|top)\b');
    final pos1 = RegExp(r'\b(okay|ok|besser|ruhig|gut|stabil)\b');

    if (neg2.hasMatch(s)) return -2;
    if (pos2.hasMatch(s)) return 2;
    if (neg1.hasMatch(s)) return -1;
    if (pos1.hasMatch(s)) return 1;
    return 0;
  }

  String _normTopic(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return '';
    // einfache Normalisierung
    final base = t
        .replaceAll(RegExp(r'[^a-zäöüß\- ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Alias-Mapping
    if (RegExp(r'\barbeit|job|büro|projekt|kunden?\b').hasMatch(base)) return 'arbeit';
    if (RegExp(r'\bschlaf|müde|insomnia|wach\b').hasMatch(base)) return 'schlaf';
    if (RegExp(r'\bfamilie|mutter|vater|partner(in)?|kind(er)?\b').hasMatch(base)) return 'familie';
    if (RegExp(r'\bwert|selbstwert|zweifel|stolz|scham\b').hasMatch(base)) return 'selbstwert';
    return base.split(' ').first; // kurzer Kern
  }

  bool _sameTopic(String a, String b) => _normTopic(a) == _normTopic(b);

  String? _inferTopicFromText(String text) {
    final s = text.toLowerCase();
    if (RegExp(r'\barbeit|job|kunden?|chef|kolleg', caseSensitive: false).hasMatch(s)) {
      return 'arbeit';
    }
    if (RegExp(r'\bschlaf|einschlafen|aufwachen|müde|traum', caseSensitive: false).hasMatch(s)) {
      return 'schlaf';
    }
    if (RegExp(r'\bfamilie|partner(in)?|freund(in)?|kind|mutter|vater', caseSensitive: false).hasMatch(s)) {
      return 'familie';
    }
    if (RegExp(r'\b(wert|selbstwert|zweifel|stolz|scham|unsicher)', caseSensitive: false).hasMatch(s)) {
      return 'selbstwert';
    }
    // fallback: erstes sinnvolles Nomen/Token
    final m = RegExp(r'\b([a-zäöüß]{4,})\b', caseSensitive: false).firstMatch(s);
    return m != null ? _normTopic(m.group(1) ?? '') : null;
  }

  List<String> _inferTagsFrom({required String topic, required String text}) {
    final tags = <String>{};
    final t = topic.toLowerCase();
    final s = text.toLowerCase();
    if (t == 'arbeit' || RegExp(r'\barbeit|job|projekt|meeting\b').hasMatch(s)) tags.add('arbeit');
    if (t == 'schlaf' || RegExp(r'\bschlaf|müde|aufwachen\b').hasMatch(s)) tags.add('schlaf');
    if (t == 'familie' || RegExp(r'\bfamilie|partner|kind|eltern\b').hasMatch(s)) tags.add('familie');
    if (t == 'selbstwert' || RegExp(r'\bwert|stolz|zweifel|scham\b').hasMatch(s)) tags.add('selbstwert');
    return tags.toList(growable: false);
  }

  String? _pickPrimaryTag(List<String> tags, {required String topic}) {
    final set = tags.map((e) => e.toLowerCase().trim()).toSet();
    for (final k in _knownTags) {
      if (set.contains(k)) return k;
    }
    // aus Topic ableiten
    final t = _normTopic(topic);
    for (final k in _knownTags) {
      if (t == k) return k;
    }
    return null;
  }

  Future<void> _ingestMemoriesToSave(Map<String, dynamic> root, {required bool allowIdentity}) async {
    try {
      final list = (root['memories_to_save'] as List?) ??
          (root['memoriesToSave'] as List?) ??
          const [];
      if (list.isEmpty) return;

      final facts = <MemoryFact>[];
      for (final it in list) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        final type = (m['type'] ?? m['kind'] ?? '').toString().toLowerCase();

        if (!allowIdentity && (type == 'identity' || type == 'profile')) {
          // Identity-Felder überspringen (Client-only)
          continue;
        }

        if (type == 'insight') {
          final line = (m['line'] ?? m['text'] ?? '').toString();
          if (line.trim().isEmpty) continue;
          final score = (m['score'] is num) ? (m['score'] as num).toDouble() : null;
          final topic = (m['topic'] ?? '').toString().trim().isEmpty ? null : _normTopic(m['topic'].toString());
          facts.add(MemoryFact(
            id: 'f_${DateTime.now().millisecondsSinceEpoch}',
            type: FactType.insight,
            line: line.trim(),
            score: score,
            topic: topic,
            createdAt: DateTime.now().toUtc(),
          ));
        }

        if (type == 'timeline' || type == 'timeline_marker') {
          final topic = (m['topic'] ?? m['label'] ?? '').toString();
          final val = (m['valence'] is num) ? (m['valence'] as num).toInt() : 0;
          final tags = _parseStringList(m['tags']);
          await saveTimelineMarker(topic: topic, valence: val, tags: tags, source: 'worker');
        }

        if (type == 'mood') {
          // optionaler Mood-Fact → auf Opt-Keys legen
          final v = (m['value'] ?? m['avg'] ?? m['mood'])?.toString();
          if ((v ?? '').toString().trim().isNotEmpty) {
            await _setOptString(_kLastMood, v!.trim());
            await _setOptString(_kLastDate, _ymd(DateTime.now().toUtc()));
          }
        }
      }

      if (facts.isNotEmpty) {
        await saveFacts(facts);
      }
    } catch (_) {/* ignore */}
  }

  Future<void> _ingestGeoIfPresent(Map<String, dynamic> root) async {
    try {
      final g = root['geo'] ?? root['location'] ?? root['place'];
      if (g is Map) {
        final m = Map<String, dynamic>.from(g);
        await recordLocation(
          label: (m['label'] ?? m['name'])?.toString(),
          lat: (m['lat'] as num?)?.toDouble(),
          lon: (m['lon'] as num?)?.toDouble(),
          accuracy: (m['accuracy'] as num?)?.toDouble(),
          source: (m['source'] ?? 'worker').toString(),
          tsUtc: DateTime.now().toUtc(),
        );
      }
    } catch (_) {/* ignore */}
  }

  Future<void> _ingestTimelineIfPresent(Map<String, dynamic> root) async {
    try {
      // direct array
      final tl = root['timeline'];
      if (tl is List) {
        for (final it in tl) {
          if (it is! Map) continue;
          final m = Map<String, dynamic>.from(it);
          final topic = (m['topic'] ?? '').toString();
          if (topic.trim().isEmpty) continue;
          final val = (m['valence'] is num) ? (m['valence'] as num).toInt() : 0;
          final tag = (m['tag'] ?? '').toString().trim();
          final tags = tag.isEmpty ? const <String>[] : <String>[tag];
          await saveTimelineMarker(topic: topic, valence: val, tags: tags, source: 'worker');
        }
      }

      // soft hint via understanding.topic_shift
      final u = root['understanding'];
      if (u is Map) {
        final topic = (u['topic_shift'] ?? u['topic'] ?? '').toString().trim();
        if (topic.isNotEmpty) {
          await saveTimelineMarker(topic: topic, valence: 0, source: 'worker');
        }
      }
    } catch (_) {/* ignore */}
  }

  static double _round1(double v) => double.parse(v.toStringAsFixed(1));
  static double _round2(double v) => double.parse(v.toStringAsFixed(2));
}

// ---------------- Extensions --------------------------------------------------

extension _TakeLastListExt<T> on List<T> {
  List<T> takeLast(int n) {
    if (n <= 0) return <T>[];
    if (isEmpty) return <T>[];
    final start = length - n;
    return (start <= 0) ? List<T>.from(this) : sublist(start);
  }
}
