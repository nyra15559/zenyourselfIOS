// [PATCHED] lib/core/memory/memory_store.dart — v6.6.4 (10.11.2025)
// MERGE SIGNAL: Soft-Invalidation (TTL) + conversations/*.jsonl + robuste Ingest-Adapter
// -----------------------------------------------------------------------------
// Neu in v6.6.4 (Patch auf v6.6.3):
// • Soft-Invalidation: Caches für Timeline/Facts werden nach TTL automatisch neu
//   geladen; zusätzlich Public-API invalidateSoftCaches() zum sanften Zurücksetzen.
// • conversations/*.jsonl: Jede Zeile (Turn/Ereignis) wird zusätzlich in eine
//   pro Tag+Session rotierende Datei geschrieben: /profiles/<id>/conversations/YYYYMMDD_<session>.jsonl
// • saveMap()/appendLine()/recordAcknowledge() schreiben nun JSONL-Conversation-Files.
// • Kleine Robustheit: Budget-Check in getFactsForContext() bleibt, JSONL-Append safe.
//
// Bestand aus v6.6.3 (zur Einordnung):
// • ingestFacts(...) arbeitet mit InsightFact/MemoryFact/Map/String über
//   Kompatibilitäts-Adapter (_factTypeDyn/_factLineDyn/...).
// • Timeline/Facts Persistenz in /profiles/<id>/timeline.json(.jsonl) & facts.json.
// • Generische Save-/Dyn-APIs (saveDynamic/saveMap/appendLine) + Histogramm-Utils.
// -----------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/insight_models.dart' as im; // InsightFact/MemoryFact, Facet etc.
import 'memory_entry.dart' show MemoryEntry;

class MemoryStore {
  MemoryStore._();
  static final MemoryStore instance = MemoryStore._();

  // ---------------------------- Flags/Keys (Prefs) ----------------------------

  static const String _kEnabled = 'memory.enabled';
  static const String _kShareEnabled = 'memory.share_enabled'; // optional
  static const String _kEntries = 'memory.entries.json'; // v1/v2 Kompat-Key
  static const int _kMax = 200;

  // PII-Keys (von MemoryService genutzt)
  static const String _kIdentityName = 'identity.name';
  static const String _kIdentityGreetByName = 'identity.greet_by_name';
  static const String _kProfileUserName = 'profile.user_name';
  static const String _kProfileNicknames = 'profile.nicknames';

  SharedPreferences? _prefs;

  // ---------------------------- Timeline (Files) ------------------------------

  static const String _kAppFolder = 'zenyourself';
  static const String _kProfilesFolder = 'profiles';
  static const String _kTimelineJson = 'timeline.json';
  static const String _kTimelineJsonl = 'timeline.jsonl';

  // Conversations
  static const String _kConversationsFolder = 'conversations';

  String _activeProfileId = 'default';
  final Map<String, List<Map<String, dynamic>>> _timelineCache = {};
  final Map<String, bool> _timelineLoaded = {};
  final Map<String, DateTime> _timelineLoadedAt = {};
  final Map<String, Object> _profileLocks = {}; // simple per-profile lock token

  // ---------------------------- Facts (Files) --------------------------------
  static const String _kFactsJson = 'facts.json';
  static const int _kFactsCap = 500; // weiches Cap für gespeicherte Insights

  final Map<String, List<Map<String, dynamic>>> _insightsCache = {};
  final Map<String, bool> _insightsLoaded = {};
  final Map<String, DateTime> _insightsLoadedAt = {};

  // ---------------------------- Cache/TTL Config ------------------------------
  static const Duration _kCacheTtl = Duration(minutes: 5);

  // ============================ Init / State =================================

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (!_prefs!.containsKey(_kEnabled)) {
      await _prefs!.setBool(_kEnabled, true);
    }
    // share_enabled ist optional – nicht erzwingen
  }

  bool get isEnabled => _prefs?.getBool(_kEnabled) ?? true;

  Future<void> setEnabled(bool enabled) async {
    await init();
    await _prefs!.setBool(_kEnabled, enabled);
  }

  // ---- optionale Share-Flag-APIs (für MemoryService best-effort) ------------

  /// Best-effort Getter (nullable → nicht vorhanden).
  bool? get isShareEnabled {
    try {
      return _prefs?.getBool(_kShareEnabled);
    } catch (_) {
      return null;
    }
  }

  /// Expliziter Getter (non-null mit Default false).
  Future<bool> getShareEnabled() async {
    await init();
    return _prefs!.getBool(_kShareEnabled) ?? false;
  }

  /// Bevorzugte Methode für MemoryService.setShareEnabled().
  Future<void> setShareEnabled(bool enabled) async {
    await init();
    await _prefs!.setBool(_kShareEnabled, enabled);
  }

  /// Generischer Flag-Setter (Fallback für dynamische Aufrufe).
  Future<void> setFlag(String key, bool value) async {
    await init();
    await _prefs!.setBool(key, value);
  }

  /// Generischer Flag-Getter (Fallback für dynamische Aufrufe).
  Future<bool?> getFlag(String key) async {
    await init();
    return _prefs!.getBool(key);
  }

  // ---------- Generische Options/Key-APIs (dyn-kompatibel) -------------------

  Future<void> setOpt(String key, Object? value) async {
    await init();
    if (value is bool) {
      await _prefs!.setBool(key, value);
    } else if (value is int) {
      await _prefs!.setInt(key, value);
    } else if (value is double) {
      await _prefs!.setDouble(key, value);
    } else if (value is String) {
      await _prefs!.setString(key, value);
    } else if (value is List<String>) {
      await _prefs!.setStringList(key, value);
    } else {
      // Fallback: JSON-serialisieren
      try {
        await _prefs!.setString(key, jsonEncode(value));
      } catch (_) {
        // still – ignorieren
      }
    }
  }

  Future<void> setOptString(String key, String value) async {
    await init();
    await _prefs!.setString(key, value);
  }

  Future<void> setOptBool(String key, bool value) async {
    await init();
    await _prefs!.setBool(key, value);
  }

  Future<Object?> getOpt(String key) async {
    await init();
    if (!_prefs!.containsKey(key)) return null;
    return _prefs!.get(key);
  }

  Future<String?> getOptString(String key) async {
    await init();
    return _prefs!.getString(key);
  }

  Future<bool?> getOptBool(String key) async {
    await init();
    if (!_prefs!.containsKey(key)) return null;
    return _prefs!.getBool(key);
  }

  /// „Key“-Alias (einige dyn-Caller erwarten diese Namen).
  Future<void> setKey(String key, String value) => setOptString(key, value);
  Future<String?> getKey(String key) => getOptString(key);

  /// Entfernt eine gespeicherte Option (best-effort).
  Future<void> removeOpt(String key) async {
    await init();
    await _prefs!.remove(key);
  }

  // ================================ CRUD (Prefs) ==============================

  Future<void> clearAll() async {
    await init();
    await _prefs!.remove(_kEntries);
    // Flags bewusst NICHT löschen (enabled/share_enabled/PII bleiben)
  }

  /// Löscht die lokal gespeicherten PII-Felder (für Privacy-Screen).
  Future<void> forgetAllPII() async {
    await init();
    await _prefs!.remove(_kIdentityName);
    await _prefs!.setBool(_kIdentityGreetByName, false);
    await _prefs!.remove(_kProfileUserName);
    await _prefs!.remove(_kProfileNicknames);
  }

  Future<List<MemoryEntry>> all() async {
    await init();
    final raw = _prefs!.getString(_kEntries);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);

      // v1/v2: Liste direkt ODER {entries: [...]}
      List<dynamic> list = const [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['entries'] is List) {
        list = List<dynamic>.from(decoded['entries'] as List);
      }

      final out = <MemoryEntry>[];
      for (final e in list) {
        if (e is Map) {
          try {
            out.add(MemoryEntry.fromMap(Map<String, dynamic>.from(e)));
          } catch (_) {
            // Kaputtes Element ignorieren
          }
        }
      }

      // Neueste zuerst
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (_) {
      // Korruptes JSON niemals crashen lassen
      return const [];
    }
  }

  Future<List<MemoryEntry>> latest({int limit = 3}) async {
    final list = await all();
    final capped = _cap(limit, 0, _kMax);
    return list.take(capped).toList(growable: false);
  }

  Future<void> save(MemoryEntry entry) async {
    await init();
    if (!isEnabled) return;

    // Bestehende laden (neueste zuerst)
    final existing = await all();

    // Neu vorne einfügen
    final updated = <MemoryEntry>[entry, ...existing];

    // Sanftes Dedupe: Schlüssel = session_id | created_at (ISO-UTC)
    final seen = <String>{};
    final deduped = <MemoryEntry>[];
    for (final e in updated) {
      final key = '${e.sessionId}|${e.createdAt.toUtc().toIso8601String()}';
      if (seen.add(key)) {
        deduped.add(e);
      }
    }

    // FIFO-Pruning (neueste zuerst → Begrenzung mit take)
    final pruned = deduped.take(_kMax).toList(growable: false);

    // Persistieren als v2-Liste (snake_case-Maps)
    try {
      final jsonList = pruned.map((e) => e.toMap()).toList(growable: false);
      await _prefs!.setString(_kEntries, jsonEncode(jsonList));
    } catch (_) {
      // still – auf Persistenzfehler nicht hart reagieren
    }
  }

  // ---------- Generische Save-/Bridge-APIs (für dyn-Calls) -------------------

  /// Fügt eine generische „Zeile“ ein (role: 'user'|'panda'), meta optional.
  Future<void> appendLine(
    String role,
    String text,
    Map<String, dynamic>? meta,
  ) async {
    final m = <String, dynamic>{
      'kind': 'line',
      'role': role,
      'text': text,
      'meta': meta ?? const <String, dynamic>{},
      'session_id': (meta?['session_id'] as String?) ?? 'local',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'context_facets': const <dynamic>[],
    };

    // Persist in Prefs (aggregiertes Journal)
    await saveMap(m);

    // Zusätzlich: Conversation JSONL
    await _appendConversationIfApplicable(m);
  }

  Future<void> saveLine({
    required String role,
    required String text,
    Map<String, dynamic>? meta,
  }) =>
      appendLine(role, text, meta);

  Future<void> saveUserLine(String text, Map<String, dynamic>? meta) =>
      appendLine('user', text, meta);

  Future<void> savePandaLine(String text, Map<String, dynamic>? meta) =>
      appendLine('panda', text, meta);

  /// Acknowledge-Ereignis speichern (z. B. für Insight-Bestärkung).
  Future<void> recordAcknowledge(Map<String, dynamic> ack) async {
    final safe = Map<String, dynamic>.from(ack);
    safe['kind'] = safe['kind'] ?? 'ack';
    safe['created_at'] =
        (safe['created_at'] as String?) ?? DateTime.now().toUtc().toIso8601String();
    safe['session_id'] =
        (safe['session_id'] as String?) ?? (safe['round_id'] as String?) ?? 'local';

    await saveMap(safe); // auch im aggregierten Journal festhalten
    await _appendConversationIfApplicable(safe); // und zusätzlich in JSONL
  }

  /// Alias (für dyn.saveAck? in MemoryService).
  Future<void> saveAck(Map<String, dynamic> ack) => recordAcknowledge(ack);

  /// Universeller Map-Save: wandelt Map→MemoryEntry und speichert.
  Future<void> saveMap(Map<String, dynamic> map) async {
    try {
      final entry = MemoryEntry.fromMap(map);
      await save(entry);
    } catch (_) {
      // Falls Map nicht direkt parsebar ist, versuche defensive Normalisierung
      try {
        final safe = <String, dynamic>{
          ...map,
          'created_at':
              map['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
          'session_id': map['session_id'] ?? 'local',
        };
        final entry = MemoryEntry.fromMap(safe);
        await save(entry);
      } catch (_) {
        // still – ignorieren
      }
    }
  }

  /// Dynamischer Universal-Save (akzeptiert Map oder MemoryEntry).
  Future<void> saveDynamic(dynamic value) async {
    if (value is MemoryEntry) {
      await save(value);
      await _appendConversationIfApplicable(value.toMap());
    } else if (value is Map) {
      await saveMap(Map<String, dynamic>.from(value));
      await _appendConversationIfApplicable(Map<String, dynamic>.from(value));
    } else if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          await saveMap(Map<String, dynamic>.from(decoded));
          await _appendConversationIfApplicable(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {/* ignore */}
    }
  }

  // Alias für dyn-Caller
  Future<void> save_(dynamic value) => saveDynamic(value);
  Future<void> save$(dynamic value) => saveDynamic(value);
  Future<void> saveCall(dynamic value) => saveDynamic(value);
  Future<void> saveAny(dynamic value) => saveDynamic(value);
  Future<void> saveObject(dynamic value) => saveDynamic(value);

  // ---------- Auswertungen / kleine Helfer -----------------------------------

  /// Histogramm (Label → Häufigkeit) über die letzten [take] Einträge.
  /// Zählt Facet.hits mit (falls 0/fehlend → 1).
  Future<Map<String, int>> facetHistogram({int take = 60}) async {
    final list = await all();
    final slice = list.take(_cap(take, 0, _kMax));
    final Map<String, int> hist = {};
    for (final e in slice) {
      for (final f in e.contextFacets) {
        final k = f.label.trim();
        if (k.isEmpty) continue;
        final inc = (f.hits <= 0) ? 1 : f.hits;
        hist[k] = (hist[k] ?? 0) + inc;
      }
    }
    return hist;
  }

  /// Top-Facettenlabels (nur Text), nach Häufigkeit sortiert.
  Future<List<String>> topFacets({int take = 3}) async {
    final hist = await facetHistogram();
    final sorted = hist.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    final capped = _cap(take, 0, sorted.length);
    return sorted.take(capped).map((e) => e.key).toList(growable: false);
  }

  // ============================== Timeline API ================================

  /// Aktives Profil setzen & Timeline + Facts laden (mit TTL-Check). Ordner wird bei Bedarf erzeugt.
  Future<void> openProfile(String profileId) async {
    _activeProfileId = (profileId.isEmpty) ? 'default' : profileId.trim();
    _profileLocks[_activeProfileId] ??= Object();

    // Timeline lazy-load (mit TTL)
    if (_timelineLoaded[_activeProfileId] != true ||
        _isStale(_timelineLoadedAt[_activeProfileId])) {
      try {
        final list = await _loadTimeline(_activeProfileId);
        _timelineCache[_activeProfileId] = list;
        _timelineLoaded[_activeProfileId] = true;
        _timelineLoadedAt[_activeProfileId] = DateTime.now().toUtc();
      } catch (_) {
        _timelineCache[_activeProfileId] = <Map<String, dynamic>>[];
        _timelineLoaded[_activeProfileId] = true;
        _timelineLoadedAt[_activeProfileId] = DateTime.now().toUtc();
      }
    }

    // Insights/Facts lazy-load (mit TTL)
    if (_insightsLoaded[_activeProfileId] != true ||
        _isStale(_insightsLoadedAt[_activeProfileId])) {
      try {
        final facts = await _loadInsights(_activeProfileId);
        _insightsCache[_activeProfileId] = facts;
        _insightsLoaded[_activeProfileId] = true;
        _insightsLoadedAt[_activeProfileId] = DateTime.now().toUtc();
      } catch (_) {
        _insightsCache[_activeProfileId] = <Map<String, dynamic>>[];
        _insightsLoaded[_activeProfileId] = true;
        _insightsLoadedAt[_activeProfileId] = DateTime.now().toUtc();
      }
    }
  }

  /// Externe Sanft-Invalidierung (setzt nur Flags zurück; Nachladen beim nächsten Zugriff).
  Future<void> invalidateSoftCaches({bool timeline = true, bool insights = true}) async {
    if (timeline) {
      _timelineLoaded[_activeProfileId] = false;
      _timelineLoadedAt.remove(_activeProfileId);
    }
    if (insights) {
      _insightsLoaded[_activeProfileId] = false;
      _insightsLoadedAt.remove(_activeProfileId);
    }
  }

  /// Liefert Timeline-Einträge des aktiven Profils (neueste zuerst).
  Future<List<Map<String, dynamic>>> timeline({int? limit}) async {
    await openProfile(_activeProfileId);
    final list = List<Map<String, dynamic>>.from(
        _timelineCache[_activeProfileId] ?? const <Map<String, dynamic>>[]);
    if (limit != null && limit > 0 && limit < list.length) {
      return list.take(limit).toList(growable: false);
    }
    return list;
  }

  /// Alias für timeline(limit: ...).
  Future<List<Map<String, dynamic>>> latestTimeline({int limit = 20}) {
    return timeline(limit: limit);
  }

  /// Fügt einen Timeline-Eintrag hinzu (sanitizing + persist).
  ///
  /// Unterstützte Felder (frei erweiterbar):
  /// - date (String, ISO-8601 'YYYY-MM-DD') ODER ts/created_at (ISO-Datetime)
  /// - topic (String) → wird getrimmt
  /// - mood (int 0–4) optional
  /// - mental / physical (int 0–4) optional (Dual-Skala)
  /// - note (String) optional
  /// - meta (Map) optional
  Future<void> addTimelineEntry({
    DateTime? date,
    String? topic,
    int? mood,
    int? mental,
    int? physical,
    String? note,
    Map<String, dynamic>? meta,
  }) async {
    await openProfile(_activeProfileId);

    final entry = <String, dynamic>{
      if (date != null) 'date': _toIsoDate(date),
      if (topic != null) 'topic': topic,
      if (mood != null) 'mood': mood,
      if (mental != null) 'mental': mental,
      if (physical != null) 'physical': physical,
      if (note != null) 'note': note,
      if (meta != null) 'meta': meta,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    final safe = _sanitizeTimelineEntry(entry);
    final list = _timelineCache[_activeProfileId] ?? <Map<String, dynamic>>[];
    list.insert(0, safe); // neueste zuerst im Cache
    _sortTimelineList(list);

    // Persistieren (atomar JSON + Append JSONL)
    await _storeTimeline(_activeProfileId, list);
    await _appendTimelineJsonl(_activeProfileId, safe);

    _timelineCache[_activeProfileId] = list;
  }

  /// Ersetzt die komplette Timeline mit einer neuen, bereits sanitizten Liste.
  Future<void> replaceTimeline(List<Map<String, dynamic>> items) async {
    await openProfile(_activeProfileId);
    final sanitized = items.map(_sanitizeTimelineEntry).toList(growable: false);
    _sortTimelineList(sanitized);
    await _storeTimeline(_activeProfileId, sanitized);
    _timelineCache[_activeProfileId] = List<Map<String, dynamic>>.from(sanitized);
  }

  /// Löscht die Timeline-Dateien und leert den Cache.
  Future<void> clearTimeline() async {
    await openProfile(_activeProfileId);
    final dir = await _profileDir(_activeProfileId);
    try {
      final fJson = File(p.join(dir.path, _kTimelineJson));
      if (await fJson.exists()) await fJson.delete();
    } catch (_) {}
    try {
      final fJsonl = File(p.join(dir.path, _kTimelineJsonl));
      if (await fJsonl.exists()) await fJsonl.delete();
    } catch (_) {}
    _timelineCache[_activeProfileId] = <Map<String, dynamic>>[];
  }

  // ============================ Timeline Internals ============================

  Future<Directory> _profileDir(String profileId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
        p.join(base.path, _kAppFolder, _kProfilesFolder, profileId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Conversations-Unterordner sicherstellen
    final conv = Directory(p.join(dir.path, _kConversationsFolder));
    if (!await conv.exists()) {
      try { await conv.create(recursive: true); } catch (_) {}
    }
    return dir;
  }

  Future<List<Map<String, dynamic>>> _loadTimeline(String profileId) async {
    // simple critical section (not re-entrant), best-effort:
    return await Future.sync(() async {
      final dir = await _profileDir(profileId);
      final fJson = File(p.join(dir.path, _kTimelineJson));
      final fJsonl = File(p.join(dir.path, _kTimelineJsonl));

      // 1) Versuche JSON-Array
      if (await fJson.exists()) {
        try {
          final raw = await fJson.readAsString();
          final decoded = jsonDecode(raw);
          final list = <Map<String, dynamic>>[];
          if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) list.add(_sanitizeTimelineEntry(e.cast<String, dynamic>()));
            }
          } else if (decoded is Map && decoded['items'] is List) {
            // toleranter Reader: {items:[...]}
            for (final e in decoded['items'] as List) {
              if (e is Map) list.add(_sanitizeTimelineEntry(e.cast<String, dynamic>()));
            }
          }
          _sortTimelineList(list);
          return list;
        } catch (_) {
          // ignore and try JSONL
        }
      }

      // 2) Fallback: JSONL
      if (await fJsonl.exists()) {
        try {
          final lines = await fJsonl.readAsLines();
          final list = <Map<String, dynamic>>[];
          for (final line in lines) {
            final s = line.trim();
            if (s.isEmpty) continue;
            try {
              final obj = jsonDecode(s);
              if (obj is Map) {
                list.add(_sanitizeTimelineEntry(obj.cast<String, dynamic>()));
              }
            } catch (_) {/* ignore bad line */}
          }
          _sortTimelineList(list);
          return list;
        } catch (_) {
          // ignore
        }
      }

      // 3) Nichts vorhanden → leere Liste
      return <Map<String, dynamic>>[];
    });
  }

  Future<void> _storeTimeline(
      String profileId, List<Map<String, dynamic>> items) async {
    final dir = await _profileDir(profileId);
    final path = p.join(dir.path, _kTimelineJson);
    final tmp = '$path.tmp';

    // JSON-Snapshot (atomar via rename)
    try {
      final safeList = items.map(_sanitizeTimelineEntry).toList(growable: false);
      final data = jsonEncode(safeList);
      await File(tmp).writeAsString(data, flush: true);
      final fJson = File(path);
      if (await fJson.exists()) {
        await fJson.delete();
      }
      await File(tmp).rename(path);
    } catch (_) {
      // tmp evtl. aufräumen — still
      try { await File(tmp).delete(); } catch (_) {}
    }
  }

  Future<void> _appendTimelineJsonl(
      String profileId, Map<String, dynamic> entry) async {
    final dir = await _profileDir(profileId);
    final fJsonl = File(p.join(dir.path, _kTimelineJsonl));
    try {
      final enc = jsonEncode(_sanitizeTimelineEntry(entry));
      await fJsonl.writeAsString('$enc\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // still
    }
  }

  Map<String, dynamic> _sanitizeTimelineEntry(Map<String, dynamic> inMap) {
    final m = Map<String, dynamic>.from(inMap);

    // date ableiten/normalisieren
    String? date = _asString(m['date']);
    final ts = _asString(m['ts'] ?? m['created_at']);
    if ((date == null || date.isEmpty) && ts != null) {
      final parsed = _tryParseDateTime(ts);
      if (parsed != null) {
        date = _toIsoDate(parsed);
      }
    }
    if (date == null || !_isIsoDate(date)) {
      date = _toIsoDate(DateTime.now());
    }
    m['date'] = date;

    // topic trimmen
    final topic = _asString(m['topic'])?.trim() ?? '';
    m['topic'] = topic;

    // mood clamp 0–4
    if (m.containsKey('mood')) m['mood'] = _clampInt(m['mood'], 0, 4);
    if (m.containsKey('mental')) m['mental'] = _clampInt(m['mental'], 0, 4);
    if (m.containsKey('physical')) m['physical'] = _clampInt(m['physical'], 0, 4);

    // note optional string
    if (m.containsKey('note')) {
      m['note'] = _asString(m['note']) ?? '';
    }

    // meta optional map
    if (m.containsKey('meta')) {
      final meta = m['meta'];
      if (meta is! Map) {
        m['meta'] = <String, dynamic>{'raw': meta?.toString() ?? ''};
      }
    }

    return m;
  }

  void _sortTimelineList(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final da = _parseIsoDate(_asString(a['date'])) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = _parseIsoDate(_asString(b['date'])) ?? DateTime.fromMillisecondsSinceEpoch(0);
      // neueste (größere) zuerst
      return db.compareTo(da);
    });
  }

  // ============================== Insights (facts.json) =======================

  /// Liefert die neuesten Atomic-Facts (Aha-Fakten), bereits sanitizt & sortiert.
  Future<List<Map<String, dynamic>>> latestFacts({int limit = 80}) async {
    await openProfile(_activeProfileId);
    final list = List<Map<String, dynamic>>.from(
      _insightsCache[_activeProfileId] ?? const <Map<String, dynamic>>[],
    );
    if (limit > 0 && limit < list.length) {
      return list.take(limit).toList(growable: false);
    }
    return list;
  }

  /// Liefert jüngste Insights innerhalb [days] Tagen, max. [max] Items.
  Future<List<Map<String, dynamic>>> loadInsightsRecent({
    int days = 14,
    int max = 6,
  }) async {
    final list = await latestFacts(limit: 9999);
    if (list.isEmpty) return const <Map<String, dynamic>>[];

    final since = DateTime.now().toUtc().subtract(Duration(days: days));
    final out = <Map<String, dynamic>>[];
    for (final m in list) {
      final tsRaw = _asString(m['updated_at']) ?? _asString(m['created_at']);
      final ts = (tsRaw == null || tsRaw.trim().isEmpty)
          ? null
          : _tryParseDateTime(tsRaw);
      if (ts == null || ts.isBefore(since)) continue;

      // Nur gültige Zeilen weiterreichen
      final line = (_asString(m['line']) ?? _asString(m['value']) ?? '').trim();
      if (line.isEmpty) continue;

      final safe = <String, dynamic>{'line': line};
      final score = m['score'];
      if (score is num) safe['score'] = (score as num).toDouble();
      out.add(safe);
      if (out.length >= max) break;
    }
    return out;
  }

  /// Fügt/merged einen Insight (Upsert); ersetzt addInsight aus v6.6.0.
  Future<void> addInsight({
    required String line,
    double? score,               // optional 0..1
    String? topic,               // ≤ 64
    String? activeFacet,         // ≤ 64
    String? topicPin,            // ≤ 64
    List<String>? tags,          // ≤ 5
    String? canon,               // optional kanonische Form
  }) async {
    await openProfile(_activeProfileId);

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final raw = <String, dynamic>{
      'type': 'insight',
      'line': line,
      if (score != null) 'score': score,
      if (topic != null) 'topic': topic,
      if (activeFacet != null) 'activeFacet': activeFacet,
      if (topicPin != null) 'topicPin': topicPin,
      if (tags != null) 'tags': tags,
      if (canon != null) 'canon': canon,
      'created_at': nowIso,
      'updated_at': nowIso,
    };

    await _upsertInsight(raw);
  }

  /// Ersetzt alle Insights (Liste muss NICHT vor-sanitizt sein).
  Future<void> replaceInsights(List<Map<String, dynamic>> items) async {
    await openProfile(_activeProfileId);
    final sanitized = items.map(_sanitizeInsight).toList(growable: false);
    final merged = _dedupeInsights(sanitized);
    _sortInsightsList(merged);
    await _storeInsights(_activeProfileId, merged);
    _insightsCache[_activeProfileId] = List<Map<String, dynamic>>.from(merged);
  }

  /// Löscht facts.json und leert den Cache.
  Future<void> clearInsights() async {
    await openProfile(_activeProfileId);
    final dir = await _profileDir(_activeProfileId);
    try {
      final fFacts = File(p.join(dir.path, _kFactsJson));
      if (await fFacts.exists()) await fFacts.delete();
    } catch (_) {}
    _insightsCache[_activeProfileId] = <Map<String, dynamic>>[];
  }

  // ---- Insight/MemoryFact Kompatibilitäts-Adapter ----------------------------

  String _factTypeDyn(dynamic f, {String or = 'insight'}) {
    try {
      final v = f.type;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = f.kind; // alternative Feldbezeichnung
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = f.factType; // weitere mögliche Bezeichnung
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return or;
  }

  String _factTopicDyn(dynamic f, {String or = ''}) {
    try {
      final v = f.topic;
      if (v is String) return v.trim();
    } catch (_) {}
    try {
      final v = f.subject; // alternative
      if (v is String) return v.trim();
    } catch (_) {}
    return or;
  }

  String _factLineDyn(dynamic f, {String or = ''}) {
    try {
      final v = f.line;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = f.text;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = f.value;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return or;
  }

  String? _factActiveFacetDyn(dynamic f) {
    try {
      final v = f.activeFacet;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = f.active_facet;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return null;
  }

  String? _factTopicPinDyn(dynamic f) {
    try {
      final v = f.topicPin;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = f.topic_pin;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return null;
  }

  String? _factCanonDyn(dynamic f) {
    try {
      final v = f.canon;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = f.canonical;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return null;
  }

  double? _factScoreDyn(dynamic f) {
    try {
      final v = f.score;
      if (v is num) return (v as num).toDouble();
    } catch (_) {}
    return null;
  }

  List<String>? _factTagsDyn(dynamic f) {
    try {
      final v = f.tags;
      if (v is List) {
        final out = <String>[];
        for (final it in v) {
          if (it == null) continue;
          final s = it.toString().trim();
          if (s.isEmpty) continue;
          out.add(_capLen(s, 32));
          if (out.length >= 5) break;
        }
        return out.isEmpty ? null : out;
      }
    } catch (_) {}
    return null;
  }

  /// Ingest aus MemoryMapper.factsFromWorker(...) – akzeptiert MemoryFact/InsightFact, Map oder String.
  /// Rückgabe: Anzahl erfolgreich upserteter Elemente.
  Future<int> ingestFacts(List<dynamic> facts) async {
    await openProfile(_activeProfileId);
    var count = 0;
    for (final f in facts) {
      try {
        if (f is im.MemoryFact || f is im.InsightFact) {
          final m = <String, dynamic>{};

          final type = _factTypeDyn(f);
          if (type.isNotEmpty) m['type'] = type;

          final line = _factLineDyn(f);
          if (line.isNotEmpty) m['line'] = line;

          final topic = _factTopicDyn(f);
          if (topic.isNotEmpty) m['topic'] = topic;

          final af = _factActiveFacetDyn(f);
          if (af != null && af.isNotEmpty) m['activeFacet'] = af;

          final tp = _factTopicPinDyn(f);
          if (tp != null && tp.isNotEmpty) m['topicPin'] = tp;

          final canon = _factCanonDyn(f);
          if (canon != null && canon.isNotEmpty) m['canon'] = canon;

          final score = _factScoreDyn(f);
          if (score != null) m['score'] = score;

          final tags = _factTagsDyn(f);
          if (tags != null && tags.isNotEmpty) m['tags'] = tags;

          await _upsertInsight(m);
          count++;
        } else if (f is Map) {
          await _upsertInsight(Map<String, dynamic>.from(f));
          count++;
        } else if (f is String) {
          // Kurzer Aha-Satz als Insight
          final s = f.trim();
          if (s.isNotEmpty) {
            await addInsight(line: s);
            count++;
          }
        }
      } catch (_) {
        // tolerantes Ignorieren einzelner defekter Items
      }
    }
    return count;
  }

  /// Liefert kompakte Facts für den Bridge-Kontext. Budget begrenzt die JSON-Größe.
  Future<List<Map<String, dynamic>>> getFactsForContext({
    int maxItems = 8,
    int days = 60,
    int budgetBytes = 1024, // grobes Limit zur Schonung der Bridge
    bool includeMeta = false, // nur 'line' & 'score' standardmäßig
  }) async {
    final list = await latestFacts(limit: 9999);
    if (list.isEmpty) return const <Map<String, dynamic>>[];

    final since = DateTime.now().toUtc().subtract(Duration(days: days));
    final filtered = <Map<String, dynamic>>[];

    for (final m in list) {
      if (filtered.length >= maxItems) break;
      final tsRaw = _asString(m['updated_at']) ?? _asString(m['created_at']);
      final ts = (tsRaw == null || tsRaw.trim().isEmpty)
          ? null
          : _tryParseDateTime(tsRaw);
      if (ts == null || ts.isBefore(since)) continue;

      final line = (_asString(m['line']) ?? '').trim();
      if (line.isEmpty) continue;

      final out = <String, dynamic>{'line': line};
      final score = m['score'];
      if (score is num) out['score'] = (score as num).toDouble();

      if (includeMeta) {
        for (final k in const ['topic', 'activeFacet', 'topicPin', 'canon', 'tags']) {
          final v = m[k];
          if (v != null) out[k] = v;
        }
      }

      filtered.add(out);

      // Budget grob prüfen
      final approx = utf8.encode(jsonEncode(filtered)).length;
      if (approx >= budgetBytes) {
        filtered.removeLast();
        break;
      }
    }
    return filtered;
  }

  // --------------------------- Insights Internals ----------------------------

  Future<List<Map<String, dynamic>>> _loadInsights(String profileId) async {
    final dir = await _profileDir(profileId);
    final fFacts = File(p.join(dir.path, _kFactsJson));

    if (!await fFacts.exists()) {
      return <Map<String, dynamic>>[];
    }

    try {
      final raw = await fFacts.readAsString();
      final decoded = jsonDecode(raw);

      final list = <Map<String, dynamic>>[];
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map) {
            list.add(_sanitizeInsight(e.cast<String, dynamic>()));
          }
        }
      } else if (decoded is Map && decoded['items'] is List) {
        // toleranter Reader: {items:[...]}
        for (final e in decoded['items'] as List) {
          if (e is Map) {
            list.add(_sanitizeInsight(e.cast<String, dynamic>()));
          }
        }
      }

      final merged = _dedupeInsights(list);
      _sortInsightsList(merged);
      return merged;
    } catch (_) {
      // korrupt → leere Liste
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _storeInsights(
      String profileId, List<Map<String, dynamic>> items) async {
    final dir = await _profileDir(profileId);
    final path = p.join(dir.path, _kFactsJson);
    final tmp = '$path.tmp';

    try {
      // Sanitize + Merge + Prune
      final safeList = _dedupeInsights(
        items.map(_sanitizeInsight).toList(growable: false),
      );
      _sortInsightsList(safeList);
      final pruned = safeList.take(_kFactsCap).toList(growable: false);

      final data = jsonEncode(pruned);
      await File(tmp).writeAsString(data, flush: true);
      final fFacts = File(path);
      if (await fFacts.exists()) {
        await fFacts.delete();
      }
      await File(tmp).rename(path);
    } catch (_) {
      try { await File(tmp).delete(); } catch (_) {}
    }
  }

  Future<void> _upsertInsight(Map<String, dynamic> inMap) async {
    await openProfile(_activeProfileId);
    final safe = _sanitizeInsight(inMap);

    final list = _insightsCache[_activeProfileId] ?? <Map<String, dynamic>>[];

    // Key: type::topic::(canon|line)
    String keyOf(Map<String, dynamic> m) {
      final type = (_asString(m['type']) ?? 'insight').toLowerCase().trim();
      final topic = (_asString(m['topic']) ?? '').toLowerCase().trim();
      final canon = (_asString(m['canon']) ?? '').toLowerCase().trim();
      final line = (_asString(m['line']) ?? '').toLowerCase().trim();
      final pivot = canon.isNotEmpty ? canon : line;
      return '$type::$topic::$pivot';
    }

    final kNew = keyOf(safe);
    bool merged = false;

    for (var i = 0; i < list.length; i++) {
      final cur = list[i];
      if (keyOf(cur) == kNew) {
        // Merge-Strategie: höchste score, Tag-Union, meta-Felder „besserer“ Wert
        final mergedMap = Map<String, dynamic>.from(cur);

        // score: max()
        final sOld = cur['score'];
        final sNew = safe['score'];
        if (sOld is num || sNew is num) {
          final dOld = (sOld is num) ? (sOld as num).toDouble() : 0.0;
          final dNew = (sNew is num) ? (sNew as num).toDouble() : 0.0;
          mergedMap['score'] = double.parse(
              (dOld > dNew ? dOld : dNew).toStringAsFixed(3));
        }

        // tags: Union, max 5, je ≤32
        final tags = <String>{};
        void addTags(dynamic v) {
          if (v is List) {
            for (final it in v) {
              final s = _asString(it)?.trim();
              if (s == null || s.isEmpty) continue;
              tags.add(_capLen(s, 32));
              if (tags.length >= 5) break;
            }
          }
        }
        addTags(cur['tags']);
        addTags(safe['tags']);
        if (tags.isEmpty) {
          mergedMap.remove('tags');
        } else {
          mergedMap['tags'] = tags.toList(growable: false);
        }

        // Bevorzugung „informativer“ Felder (längerer String gewinnt)
        String _better(String a, String b) => (a.trim().length >= b.trim().length) ? a : b;
        for (final k in const ['topic', 'activeFacet', 'topicPin', 'canon']) {
          final a = _asString(cur[k]) ?? '';
          final b = _asString(safe[k]) ?? '';
          final best = _better(a, b).trim();
          if (best.isEmpty) {
            mergedMap.remove(k);
          } else {
            mergedMap[k] = best;
          }
        }

        // line bleibt (bereits ≤240 getrimmt) – falls canon gesetzt, line nur aktualisieren, wenn länger
        final lOld = _asString(cur['line']) ?? '';
        final lNew = _asString(safe['line']) ?? '';
        mergedMap['line'] = _better(lOld, lNew);

        // Timestamps
        final created = _asString(cur['created_at']) ?? _asString(safe['created_at']);
        mergedMap['created_at'] = created ?? DateTime.now().toUtc().toIso8601String();
        mergedMap['updated_at'] = DateTime.now().toUtc().toIso8601String();

        list[i] = _sanitizeInsight(mergedMap);
        merged = true;
        break;
      }
    }

    if (!merged) {
      // Neu einfügen (vorne), Updated/Created bereits gesetzt
      list.insert(0, safe);
    }

    // Sortieren + Prunen + Persist
    _sortInsightsList(list);
    final pruned = list.take(_kFactsCap).toList(growable: false);
    await _storeInsights(_activeProfileId, pruned);
    _insightsCache[_activeProfileId] = pruned;
  }

  Map<String, dynamic> _sanitizeInsight(Map<String, dynamic> inMap) {
    final m = Map<String, dynamic>.from(inMap);

    // Pflicht: type=insight, line (trim, max 240)
    m['type'] = 'insight';
    final rawLine = (_asString(m['line']) ?? _asString(m['value']) ?? '').trim();
    m['line'] = _capLen(rawLine, 240);

    // optionale Felder: topic/activeFacet/topicPin (max 64)
    if (m.containsKey('topic')) {
      m['topic'] = _capLen((_asString(m['topic']) ?? '').trim(), 64);
    }
    if (m.containsKey('activeFacet')) {
      m['activeFacet'] = _capLen((_asString(m['activeFacet']) ?? '').trim(), 64);
    } else if (m.containsKey('active_facet')) {
      m['activeFacet'] = _capLen((_asString(m['active_facet']) ?? '').trim(), 64);
      m.remove('active_facet');
    }
    if (m.containsKey('topicPin')) {
      m['topicPin'] = _capLen((_asString(m['topicPin']) ?? '').trim(), 64);
    } else if (m.containsKey('topic_pin')) {
      m['topicPin'] = _capLen((_asString(m['topic_pin']) ?? '').trim(), 64);
      m.remove('topic_pin');
    }

    // score (0..1) soft-clamp
    if (m['score'] is num) {
      double s = (m['score'] as num).toDouble();
      if (s.isNaN) {
        m.remove('score');
      } else {
        if (s < 0) s = 0;
        if (s > 1) s = 1;
        m['score'] = double.parse(s.toStringAsFixed(3));
      }
    } else {
      m.remove('score');
    }

    // tags: Liste von Strings, ≤5, getrimmt & dedupliziert
    if (m.containsKey('tags')) {
      final tags = _sanitizeTags(m['tags']);
      if (tags.isEmpty) {
        m.remove('tags');
      } else {
        m['tags'] = tags;
      }
    }

    // canon optional → trim
    if (m.containsKey('canon')) {
      final c = (_asString(m['canon']) ?? '').trim();
      if (c.isEmpty) m.remove('canon'); else m['canon'] = c;
    }

    // Timestamps: created_at / updated_at
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final created = _asString(m['created_at']) ?? _asString(m['createdAt']);
    final updated = _asString(m['updated_at']) ?? _asString(m['updatedAt']);
    m['created_at'] = (created != null && created.trim().isNotEmpty)
        ? (_tryParseDateTime(created) ?? DateTime.now().toUtc()).toIso8601String()
        : nowIso;
    m['updated_at'] = (updated != null && updated.trim().isNotEmpty)
        ? (_tryParseDateTime(updated) ?? DateTime.now().toUtc()).toIso8601String()
        : m['created_at'];

    return m;
  }

  List<Map<String, dynamic>> _dedupeInsights(List<Map<String, dynamic>> list) {
    final byKey = <String, Map<String, dynamic>>{};

    String keyOf(Map<String, dynamic> m) {
      final type = (_asString(m['type']) ?? 'insight').toLowerCase().trim();
      final topic = (_asString(m['topic']) ?? '').toLowerCase().trim();
      final canon = (_asString(m['canon']) ?? '').toLowerCase().trim();
      final line = (_asString(m['line']) ?? '').toLowerCase().trim();
      final pivot = canon.isNotEmpty ? canon : line;
      return '$type::$topic::$pivot';
    }

    for (final e in list) {
      final safe = _sanitizeInsight(e);
      final k = keyOf(safe);
      final prev = byKey[k];
      if (prev == null) {
        byKey[k] = safe;
      } else {
        // Merge analog zu _upsertInsight
        final merged = Map<String, dynamic>.from(prev);

        // score: max
        final sOld = prev['score'];
        final sNew = safe['score'];
        if (sOld is num || sNew is num) {
          final dOld = (sOld is num) ? (sOld as num).toDouble() : 0.0;
          final dNew = (sNew is num) ? (sNew as num).toDouble() : 0.0;
          merged['score'] =
              double.parse((dOld > dNew ? dOld : dNew).toStringAsFixed(3));
        }

        // tags: Union
        final tags = <String>{};
        void addTags(dynamic v) {
          if (v is List) {
            for (final it in v) {
              final s = _asString(it)?.trim();
              if (s == null || s.isEmpty) continue;
              tags.add(_capLen(s, 32));
              if (tags.length >= 5) break;
            }
          }
        }
        addTags(prev['tags']);
        addTags(safe['tags']);
        if (tags.isEmpty) merged.remove('tags'); else merged['tags'] = tags.toList(growable: false);

        String _better(String a, String b) => (a.trim().length >= b.trim().length) ? a : b;
        for (final k2 in const ['topic', 'activeFacet', 'topicPin', 'canon']) {
          final a = _asString(prev[k2]) ?? '';
          final b = _asString(safe[k2]) ?? '';
          final best = _better(a, b).trim();
          if (best.isEmpty) merged.remove(k2); else merged[k2] = best;
        }

        // line
        final lOld = _asString(prev['line']) ?? '';
        final lNew = _asString(safe['line']) ?? '';
        merged['line'] = _better(lOld, lNew);

        // timestamps
        final created = _asString(prev['created_at']) ?? _asString(safe['created_at']);
        merged['created_at'] = created ?? DateTime.now().toUtc().toIso8601String();
        merged['updated_at'] = DateTime.now().toUtc().toIso8601String();

        byKey[k] = _sanitizeInsight(merged);
      }
    }

    return byKey.values.toList(growable: false);
  }

  void _sortInsightsList(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final ta = _tryParseDateTime(_asString(a['updated_at'])) ??
          _tryParseDateTime(_asString(a['created_at'])) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final tb = _tryParseDateTime(_asString(b['updated_at'])) ??
          _tryParseDateTime(_asString(b['created_at'])) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      // neueste zuerst
      return tb.compareTo(ta);
    });
  }

  // --------------------------- Conversations (JSONL) --------------------------

  Future<void> _appendConversationIfApplicable(Map<String, dynamic> map) async {
    try {
      final sessionId = _asString(map['session_id']) ??
          _asString((map['meta'] is Map) ? map['meta']['session_id'] : null) ??
          'local';
      final dir = await _profileDir(_activeProfileId);
      final convDir = Directory(p.join(dir.path, _kConversationsFolder));
      if (!await convDir.exists()) {
        try { await convDir.create(recursive: true); } catch (_) {}
      }
      final tsIso = _asString(map['created_at']) ??
          DateTime.now().toUtc().toIso8601String();
      final ts = _tryParseDateTime(tsIso) ?? DateTime.now().toUtc();
      final fileName = '${_yyyymmdd(ts)}_${_sanitizeFileSegment(sessionId)}.jsonl';
      final f = File(p.join(convDir.path, fileName));
      final enc = jsonEncode(map);
      await f.writeAsString('$enc\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // still
    }
  }

  String _sanitizeFileSegment(String s) {
    // rudimentär: nur Buchstaben/Ziffern/_-
    final cleaned = s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
    if (cleaned.isEmpty) return 'local';
    return cleaned;
  }

  String _yyyymmdd(DateTime utc) {
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  // --------------------------- Insights: Sanitizer-Utils ----------------------

  List<String> _sanitizeTags(dynamic v) {
    final out = <String>[];
    if (v is List) {
      for (final it in v) {
        final s = _asString(it)?.trim();
        if (s == null || s.isEmpty) continue;
        final clipped = _capLen(s, 32);
        if (!out.contains(clipped)) out.add(clipped);
        if (out.length >= 5) break; // max 5 Tags
      }
    } else if (v is String) {
      final s = v.trim();
      if (s.isNotEmpty) out.add(_capLen(s, 32));
    }
    return out;
  }

  // ================================ Utils ====================================

  bool _isStale(DateTime? loadedAt) {
    if (loadedAt == null) return true;
    final now = DateTime.now().toUtc();
    return now.difference(loadedAt) > _kCacheTtl;
  }

  int _cap(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  String _capLen(String s, int max) {
    if (s.length <= max) return s;
    return s.substring(0, max);
  }

  String _toIsoDate(DateTime dt) {
    final d = dt.toUtc();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  bool _isIsoDate(String s) {
    // sehr einfache Prüfung: YYYY-MM-DD
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    return re.hasMatch(s);
  }

  DateTime? _parseIsoDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final parts = s.split('-');
      if (parts.length == 3) {
        final y = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final d = int.parse(parts[2]);
        return DateTime.utc(y, m, d);
      }
    } catch (_) {}
    return null;
  }

  DateTime? _tryParseDateTime(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s).toUtc();
    } catch (_) {
      return null;
    }
  }

  String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  int _clampInt(dynamic v, int lo, int hi) {
    int n;
    if (v is int) {
      n = v;
    } else if (v is double) {
      n = v.round();
    } else {
      try {
        n = int.parse(v.toString());
      } catch (_) {
        n = lo;
      }
    }
    if (n < lo) n = lo;
    if (n > hi) n = hi;
    return n;
  }

  // ============================ Export/Forget Stubs ===========================

  /// (Stub) Exportiert das Profil als ZIP. Future-Feature – derzeit null.
  Future<File?> exportProfileZip({String? profileId}) async {
    // Platzhalter – wird in Phase 4 implementiert.
    return null;
  }
}
