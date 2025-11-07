// [BASELINE] lib/core/memory/memory_service.dart — v6.6.4 (S12.3+CB v1.4 • 07.11.2025)
// ZenYourself — MemoryService (Lokales Kontext-Gedächtnis, Ghost-Mode by default)
// -----------------------------------------------------------------------------
// MERGE-SIGNAL / Bridge-Guard:
// • Api/Guidance senden context.memories **nur**, wenn enabled && consent && memoryActive.
// • meta.flags.client_memory:true wird extern (ApiService/ReflectionLogic) gesetzt.
// -----------------------------------------------------------------------------
// NEU in v6.6.3 (S12.3+Context-Bridge v1.3):
// • saveFact(MemoryFact) & saveFacts(List<MemoryFact>) als generische Public-APIs.
// • Kleinere Robustheits-Verbesserungen (Null-Safety, defensive Trims, try/catch).
//
// NEU in v6.6.2 (S12.3+Context-Bridge v1.2):
// • memoryActive-Fenster inkl. 7-Tage-Trial ab Erststart (lokal, ohne Cloud).
// • Getter: memoryActive / isActive, Expiry-Handling, Setters: setMemoryActive(...),
//   setMemoryExpiry(...), ensureTrialWindow(...).
// • buildContextMemories(consent) respektiert jetzt memoryActive: sendet nur bei
//   enabled && consent && memoryActive (wie per Projektstand gefordert).
//
// NEU in v6.6.1 (S12.3+Context-Bridge v1.1):
// • buildContextMemories(): kuratiertes Kontext-Paket ≤2 KB
//   – identity.name (nur mit Consent & greetByName; niemals vom Worker überschrieben)
//   – last.topic  (aus saveFromWorker: understanding.topic_shift oder memories_to_save[].topic)
//   – last.mood   (aus saveFromWorker: flow.mood_prompt/mood; numerisch, falls möglich)
//   – last.date   (YYYY-MM-DD; beim erfolgreichen Panda-Turn gesetzt)
// • saveFromWorker(...):
//   – extrahiert last.topic & last.mood aus Worker-Response
//   – setzt last.date auf heutiges Datum (UTC, YYYY-MM-DD)
//   – **kein** Upsert von identity.name aus Worker (Name bleibt lokal/quellwahr)
// • 2 KB Budget-Guard: aggressive Kürzung (share → mood → topic → last → identity)
//
// Beibehalten:
// – Keine Roh-Transkripte im Kontextpaket
// – Recency/Timeline & Geo-Breadcrumbs (rein lokal)
// – Sync-Caches (Name/Greet/Profile) + Byte-Kontext
//
// Rückwärtskompatibel zu v6.5.x.

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
                .where((e) => e.isNotEmpty)
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
        topicPin: (topicPin ?? '').trim().isEmpty ? null : topicPin!.trim(),
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

      _invalidateSoftCaches();
    } catch (_) {
      // still
    }
  }

  /// Konversationszeile des Nutzers lokal protokollieren (best-effort).
  Future<void> saveUserTurn(String text, {Map<String, dynamic>? meta}) async {
    await _saveLine('user', text, meta: meta);
  }

  /// Konversationszeile des Panda lokal protokollieren (best-effort).
  Future<void> savePandaTurn(String text, {Map<String, dynamic>? meta}) async {
    await _saveLine('panda', text, meta: meta);
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
  /// Enthält **nur**: identity.name (bei Consent & Greet), last.topic, last.mood, last.date, share-Flag.
  /// Keine Roh-Transkripte, keine History.
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

      // mood numerisch, falls möglich
      dynamic moodField;
      if ((lastMoodStr ?? '').trim().isNotEmpty) {
        final s = lastMoodStr!.trim();
        final n = int.tryParse(s);
        moodField = n ?? s; // Zahl, falls parsebar; sonst String
      }

      // Zusammenstellen von "last"
      if ((lastTopic ?? '').isNotEmpty || moodField != null || (lastDateStr ?? '').isNotEmpty) {
        out['last'] = <String, dynamic>{
          if ((lastTopic ?? '').isNotEmpty) 'topic': lastTopic,
          if (moodField != null) 'mood': moodField,
          if ((lastDateStr ?? '').isNotEmpty) 'date': lastDateStr,
        };
      }

      // 3) share-Flag (klein, optional)
      if (_shareEnabled) {
        out['share'] = true;
      }

      // 4) Größenkappe ≤ 2048 Bytes (2 KB). Falls zu groß → aggressiv kürzen.
      List<int> bytes() => utf8.encode(jsonEncode(out));
      if (bytes().length > 2048) {
        // zuerst share weglassen
        out.remove('share');
      }
      if (bytes().length > 2048) {
        // mood entfernen (größer als topic)
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

  // ---------------- Recency/Timeline & Geo (S12.2) --------------------------

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
  /// Enthält, sofern verfügbar: lines, facts, ack, location. Rein lokal.
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

      // 2a) Konversations-Lines (sofern verfügbar)
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

      // 2b) Facts (leichtgewichtig)
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

      // 2c) Location Breadcrumbs
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

      // 2d) Acks (optional)
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
      return const <Map<String, dynamic>>[];
    }
  }

  // ---------------- interne Helfer ------------------------------------------

  /// Ingest von memories_to_save. **allowIdentity=false** verhindert PII-Overwrite (Name etc.).
  Future<void> _ingestMemoriesToSave(Map<String, dynamic> root, {bool allowIdentity = false}) async {
    try {
      final list = (root['memories_to_save'] as List?) ??
          (root['memoriesToSave'] as List?) ??
          const [];
      if (list.isEmpty) return;

      // 1) generische Saves + 2) Insight-Facts + 3) optional: last.topic (Fallback)
      final factMaps = <Map<String, dynamic>>[];
      String? topicFallback;

      for (final item in list) {
        if (item == null) continue;
        if (item is Map) {
          final mem = Map<String, dynamic>.from(item);

          // (PII) Identity/Profile: NICHT speichern, außer explizit erlaubt
          if (allowIdentity) {
            try {
              final idMap = (mem['identity'] is Map)
                  ? Map<String, dynamic>.from(mem['identity'])
                  : null;
              final idName =
                  (idMap?['name'] ?? mem['identity_name'] ?? mem['name'])
                      ?.toString()
                      .trim();
              if ((idName ?? '').isNotEmpty && (_identityNameCache ?? '').trim().isEmpty) {
                await saveIdentityName(idName!);
              }
              final profMap = (mem['profile'] is Map)
                  ? Map<String, dynamic>.from(mem['profile'])
                  : null;
              final profName =
                  (profMap?['user_name'] ?? mem['profile_user_name'])
                      ?.toString()
                      .trim();
              if ((profName ?? '').isNotEmpty && (_profileUserNameCache ?? '').trim().isEmpty) {
                await saveProfileUserName(profName!);
              }
              final nicksDyn = (profMap?['nicknames'] ?? mem['nicknames']);
              final nicks = _parseStringList(nicksDyn);
              for (final nick in nicks) {
                await addNickname(nick);
              }
            } catch (_) {/* ignore */}
          }

          // (2) best-effort generisch sichern (falls Store es unterstützt)
          try {
            final dyn = _store as dynamic;
            final safe = <String, dynamic>{
              ...mem,
              'kind': mem['kind'] ?? 'memory',
              'ts': DateTime.now().toUtc().toIso8601String()
            };
            try {
              final r1 = dyn.saveMap?.call(safe);
              if (r1 is Future) await r1;
            } catch (_) {/* try next */}
            try {
              final r2 = dyn.save?.call(safe);
              if (r2 is Future) await r2;
            } catch (_) {/* ignore */}
          } catch (_) {/* ignore */}

          // (3) Insight-Fact herausziehen (falls vorhanden)
          final m = {
            ...mem,
            'type': mem['type'] ?? 'insight',
          };
          try {
            final fact = MemoryFact.fromMap(m);
            factMaps.add(fact.toMap());
          } catch (_) {/* ignore */}

          // Fallback: topic sammeln
          final t = (mem['topic'] ?? mem['last_topic'] ?? mem['label'])
              ?.toString()
              .trim();
          if ((t ?? '').isNotEmpty && (topicFallback ?? '').isEmpty) {
            topicFallback = t;
          }
        } else if (item is String) {
          // einfacher String → Insight-Satz
          final s = item.trim();
          if (s.isNotEmpty) {
            try {
              final fact = MemoryFact.fromMap({
                'type': 'insight',
                'line': s,
              });
              factMaps.add(fact.toMap());
            } catch (_) {/* ignore */}
          }
        }
      }

      // batch persist
      if (factMaps.isNotEmpty) {
        final s = _store as dynamic;
        bool ok = false;
        try {
          final r = s.upsertFacts?.call(factMaps);
          if (r is Future) await r;
          ok = true;
        } catch (_) {/* try next */}
        if (!ok) {
          try {
            final r = s.saveFacts?.call(factMaps);
            if (r is Future) await r;
            ok = true;
          } catch (_) {/* try next */}
        }
        if (!ok) {
          for (final m in factMaps) {
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
      }

      // Fallback: last.topic aus memories_to_save setzen (falls noch nicht gesetzt)
      if ((topicFallback ?? '').isNotEmpty) {
        final existing = await _getOptString(_kLastTopic);
        if ((existing ?? '').trim().isEmpty) {
          await _setOptString(_kLastTopic, topicFallback!.trim());
          await _setOptString(_kLastDate, _ymd(DateTime.now().toUtc()));
          // Pin auch sync aktualisieren
          final base = _lastHint;
          _lastHint = MemoryContextHint(
            facets: base?.facets,
            tags: base?.tags,
            topics: base?.topics,
            identityName: base?.identityName,
            profileUserName: base?.profileUserName,
            profileNicknames: base?.profileNicknames,
            activeFacet: base?.activeFacet,
            topicPin: topicFallback!.trim(),
          );
          _lastHintTs ??= DateTime.now();
        }
      }

      // Hint um Namen/Pins ergänzen (sync), **ohne** Worker-PII-Overwrite
      final idNameNow = (_identityNameCache ?? '').trim();
      final profNameNow = (_profileUserNameCache ?? '').trim();
      final nicksNow = (_profileNicknamesCache ?? const <String>[])
          .where((e) => e.trim().isNotEmpty)
          .map((e) => e.trim())
          .toList(growable: false);

      _lastHint = MemoryContextHint(
        facets: _lastHint?.facets,
        tags: _lastHint?.tags,
        topics: _lastHint?.topics,
        identityName: idNameNow.isEmpty ? _lastHint?.identityName : idNameNow,
        profileUserName:
            profNameNow.isEmpty ? _lastHint?.profileUserName : profNameNow,
        profileNicknames:
            (nicksNow.isEmpty ? _lastHint?.profileNicknames : nicksNow),
        activeFacet: _lastHint?.activeFacet,
        topicPin: _lastHint?.topicPin,
      );
      _lastHintTs ??= DateTime.now();
    } catch (_) {/* ignore */}
  }

  /// Liest optionale Geo-Felder aus einer Worker-Antwort und legt Stempel an.
  Future<void> _ingestGeoIfPresent(Map<String, dynamic> root) async {
    try {
      Map<String, dynamic>? _asMap(dynamic v) =>
          (v is Map<String, dynamic>) ? v : (v is Map) ? Map<String, dynamic>.from(v) : null;

      double? _num(dynamic x) {
        if (x is num) return x.toDouble();
        if (x is String) return double.tryParse(x.trim());
        return null;
      }

      // Tolerante Quellen: top-level 'location'|'geo', sowie plan.location
      final loc = _asMap(root['location']) ??
          _asMap(root['geo']) ??
          _asMap(_asMap(root['plan'])?['location']);

      if (loc == null) return;

      final label = (loc['label'] ?? loc['place'] ?? loc['city'] ?? loc['name'])
          ?.toString();
      final lat = _num(loc['lat'] ?? loc['latitude']);
      final lon = _num(loc['lon'] ?? loc['lng'] ?? loc['longitude']);
      final acc = _num(loc['accuracy'] ?? loc['acc']);
      final src = (loc['source'] ?? 'worker').toString();

      if ((label == null || label.trim().isEmpty) &&
          lat == null &&
          lon == null) {
        return;
      }

      await recordLocation(
        label: label,
        lat: lat,
        lon: lon,
        accuracy: acc,
        source: src,
      );
    } catch (_) {/* ignore */}
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
}

// ---------------- kleine Extension-Helfer ------------------------------------

extension _ListX<T> on List<T>? {
  bool get isNotEmpty => (this != null && this!.isNotEmpty);
}
