// [BASELINE] lib/core/memory/memory_service.dart — v6.4.2 (31.10.2025)
// ZenYourself — MemoryService (Lokales Kontext-Gedächtnis, Ghost-Mode by default)
// -----------------------------------------------------------------------------
// D1: FactType.insight + Serialisierung (MemoryFact) integriert.
//     buildContextHint(..., activeFacet, topicPin) erweitert.
//     Public-API: saveInsightFact(...).
// E1: saveFromWorker(...) upsertet zusätzlich memories_to_save[*] als Facts.
//
// Rückwärtskompatibel zu v6.3.8. Bestehende Signaturen bleiben erhalten;
// neue optionale Named-Parameter sind additive Erweiterungen.

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

class MemoryService {
  MemoryService._internal();
  static final MemoryService instance = MemoryService._internal();

  final MemoryStore _store = MemoryStore.instance;

  // Flags
  bool _enabled = true; // Ghost-Mode (lokales Gedächtnis)
  bool _shareEnabled = false; // Therapist-Mode (Opt-in)

  bool get enabled => _enabled;
  bool get shareEnabled => _shareEnabled;

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

  // TTLs
  static const _hintTtlDays = 14;
  static const _topicsTtlSec = 30;
  static const _facetsTtlSec = 30;

  // Storage-Keys (nur lokal)
  static const String _kIdentityName = 'identity.name';
  static const String _kIdentityGreetByName = 'identity.greet_by_name';
  static const String _kShareEnabled = 'share_enabled';

  // Profile-Keys
  static const String _kProfileUserName = 'profile.user_name';
  static const String _kProfileNicknames = 'profile.nicknames'; // JSON-Array

  // ---------------- Lifecycle / Flags ----------------------------------------

  Future<void> init() async {
    try {
      await _store.init();
      _enabled = _store.isEnabled;

      final se = await _getOptBool(_kShareEnabled);
      _shareEnabled = se ?? _tryReadShareEnabledReflective() ?? false;

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
  }

  // ---------------- Identity/Profile (lokal) ---------------------------------

  Future<void> saveIdentityName(String name, {bool greetByName = true}) async {
    try {
      final n = _cap(name.trim());
      if (n.isEmpty) return;
      _identityNameCache = n; // Sync-Cache
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
      await _setOptBool(_kIdentityGreetByName, greetByName);
    } catch (_) {/* ignore */}
  }

  Future<void> forgetIdentityName() async {
    try {
      _identityNameCache = null; // Sync-Cache löschen
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
      _identityNameCache = trimmed; // Cache aktualisieren
      return (name: trimmed, greetByName: greet);
    } catch (_) {
      return (name: null, greetByName: false);
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

      final firstToken = candidate.split(RegExp(r"\s+")).first;

      String clean =
          firstToken.replaceAll(RegExp(r"[^a-zA-ZäöüÄÖÜß\-' ]"), '');
      clean = clean.replaceAll(' ', '');
      if (clean.length < 2) return;
      clean = _cap(clean);

      const banned = {'einfach', 'ja', 'okay', 'ok', 'nein', 'anonym'};
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

  /// Speichert tolerant aus einer Worker-Response (no-op, wenn disabled).
  /// Verarbeitet zusätzlich memories_to_save[] (Identity/Profile + Insights).
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
            // Name/activeFacet/topicPin werden unten ggf. ergänzt
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

      // 3) Bestehende Identity/Profile-Upserts aus memories_to_save (PII)
      await _ingestMemoriesToSave(map);

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
        topicPin: (topicPin ?? '').trim().isEmpty ? null : topicPin!.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> buildContextMemories(
      {required bool consent}) async {
    try {
      if (!_enabled || !consent) return const <String, dynamic>{};

      final out = <String, dynamic>{};

      final id = await loadGreetingName();
      if (id.greetByName && id.name != null && id.name!.isNotEmpty) {
        out['identity'] = <String, dynamic>{'name': id.name};
      }

      if ((_profileUserNameCache ?? '').toString().trim().isNotEmpty ||
          (_profileNicknamesCache?.isNotEmpty ?? false)) {
        out['profile'] = <String, dynamic>{
          if ((_profileUserNameCache ?? '').toString().trim().isNotEmpty)
            'user_name': _profileUserNameCache!.trim(),
          if (_profileNicknamesCache != null && _profileNicknamesCache!.isNotEmpty)
            'nicknames': _profileNicknamesCache,
        };
      }

      final hint = buildContextHint();
      if (hint != null) {
        out['hint'] = hint.toJson()
          ..remove('identity')
          ..remove('profile'); // identity/profile sind oben explizit gesetzt
      }

      try {
        final topics = await latestTopics(limit: 8);
        if (topics.isNotEmpty) {
          out['recent_topics'] = topics;
        }
      } catch (_) {/* ignore */}

      if (_shareEnabled) {
        out['share'] = true;
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

  // ---------------- interne Helfer ------------------------------------------

  Future<void> _ingestMemoriesToSave(Map<String, dynamic> root) async {
    try {
      final list = (root['memories_to_save'] as List?) ??
          (root['memoriesToSave'] as List?) ??
          const [];
      if (list.isEmpty) return;

      // 1) Identity/Profile + 2) generische Saves + 3) Insight-Facts
      final factMaps = <Map<String, dynamic>>[];

      for (final item in list) {
        if (item == null) continue;
        if (item is Map) {
          final mem = Map<String, dynamic>.from(item);

          // (1) identity.name
          final idMap = (mem['identity'] is Map)
              ? Map<String, dynamic>.from(mem['identity'])
              : null;
          final idName =
              (idMap?['name'] ?? mem['identity_name'] ?? mem['name'])
                  ?.toString()
                  .trim();
          if ((idName ?? '').isNotEmpty) {
            await saveIdentityName(idName!);
          }

          // (1) profile.user_name & profile.nicknames[]
          final profMap = (mem['profile'] is Map)
              ? Map<String, dynamic>.from(mem['profile'])
              : null;
          final profName =
              (profMap?['user_name'] ?? mem['profile_user_name'])
                  ?.toString()
                  .trim();
          if ((profName ?? '').isNotEmpty) {
            await saveProfileUserName(profName!);
          }

          final nicksDyn = (profMap?['nicknames'] ?? mem['nicknames']);
          final nicks = _parseStringList(nicksDyn);
          for (final nick in nicks) {
            await addNickname(nick);
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
        } else if (item is String) {
          // einfacher String → kann ein Insight-Satz sein ODER Nickname
          final s = item.trim();
          if (s.split(' ').length == 1 && s.length >= 2 && s.length <= 24) {
            await addNickname(s); // kurzer Alias
          } else if (s.isNotEmpty) {
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

      // Hint um Namen/Pins ergänzen (sync), ohne await
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
}

// ---------------- kleine Extension-Helfer ------------------------------------

extension _ListX<T> on List<T>? {
  bool get isNotEmpty => (this != null && this!.isNotEmpty);
}
