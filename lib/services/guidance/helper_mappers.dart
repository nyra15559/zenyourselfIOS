// [MERGE] lib/services/guidance/helper_mappers.dart (Stand: 2025-11-08, v1.6.3)
// MERGE SIGNAL — Kutsche 3: Topic-Normalisierung & Timeline-Support (alias-safe)
// -----------------------------------------------------------------------------
// Zweck: Schlanke Mapper/Funktionen für UI-nahe Daten aus Worker/DTOs.
//  • Answer-Helpers limitieren (max. 3) → Display/Insert-Varianten, sanft bereinigt.
//  • Topics/Facetten mappen → normalisieren (≤3 Wörter, lowercase, trim, de-dup).
//  • Timeline-Support → Primär-Topic heuristisch wählen (Confidence + Source).
//  • Hope/Closure mappen → mood_intro/hope_reply/closure_prompt normalisieren.
//  • Emotions mappen → MoodScore (−2..+2) + Labels (primär/sekundär).
//  • Risiko mappen → 'none' | 'mild' | 'high' (+ bool risk).
//
// Änderungen v1.6.3 (alias-safe):
//  • Alias-Support snake_case ⇄ camelCase in _get() & mapClosure() (answer_helpers, follow_ups,
//    risk_flag, helper_suggestion, moodIntro, hopeReply, closurePrompt).
//  • topicChips(): filtert zusätzlich 'mood_score:'.
//  • mapEmotions(): akzeptiert tags:'mood_score:' und ctx['moodScore'].
//  • Utilities: _aliasValue(), _toSnake(), _toCamel().
//
// Baselines (fix): memory_store.dart v6.6.0 · memory_entry.dart v6.4.3 ·
// memory_mapper.dart v6.4.2 · reflection_logic.dart v6.7.1 · api_service.dart v6.4.7
// -----------------------------------------------------------------------------

library guidance_helper_mappers;

typedef Json = Map<String, dynamic>;

class HelperMappers {
  HelperMappers._();

  static const String _kFallbackChipSeed = 'Wichtig ist mir außerdem';
  static const String _kFallbackChipSeedAlt = 'Ich mag klein anfangen';

  // ─────────────────────────────────────────────────────────────────────
  // Answer-Helpers (Display / Insert) — max. 3, sanft bereinigt
  // ─────────────────────────────────────────────────────────────────────

  /// Extrahiert bis zu 3 Answer-Helpers (Display-Variante, mit „…“).
  static List<String> answerHelpersDisplay(dynamic turn, {int max = 3}) {
    final primary = _listOfString(_get(turn, 'answerHelpers'));
    final legacy  = _listOfString(_get(turn, 'followups'));
    final src = primary.isNotEmpty ? primary : legacy;

    final out = <String>[];
    final seen = <String>{};
    for (final s in src) {
      final cleaned = _cleanChipForDisplay(s);
      if (cleaned.isEmpty) continue;
      final k = cleaned.toLowerCase();
      if (!seen.add(k)) continue;
      out.add(cleaned);
      if (out.length >= max) break;
    }

    // Mindestanzahl: 0 → 2 Fallbacks, 1 → +1 Fallback
    if (out.isEmpty) {
      final a = _cleanChipForDisplay(_kFallbackChipSeed);
      final b = _cleanChipForDisplay(_kFallbackChipSeedAlt);
      if (a.isNotEmpty) out.add(a);
      if (b.isNotEmpty && !out.any((e) => e.toLowerCase() == b.toLowerCase())) {
        out.add(b);
      }
    } else if (out.length == 1) {
      final b = _cleanChipForDisplay(_kFallbackChipSeed);
      if (!out.any((e) => e.toLowerCase() == b.toLowerCase())) out.add(b);
    }

    return out.length > max ? out.take(max).toList() : out;
  }

  /// Insert-Variante (ohne Ellipsis/Punktuation), gleiche Limitierung.
  static List<String> answerHelpersInsert(dynamic turn, {int max = 3}) {
    final display = answerHelpersDisplay(turn, max: max);
    final seen = <String>{};
    final out = <String>[];
    for (final d in display) {
      final cleaned = _cleanChipForInsert(d);
      if (cleaned.isEmpty) continue;
      final k = cleaned.toLowerCase();
      if (!seen.add(k)) continue;
      out.add(cleaned);
      if (out.length >= max) break;
    }

    if (out.isEmpty) {
      final a = _cleanChipForInsert(_kFallbackChipSeed);
      final b = _cleanChipForInsert(_kFallbackChipSeedAlt);
      if (a.isNotEmpty) out.add(a);
      if (b.isNotEmpty && !out.any((e) => e.toLowerCase() == b.toLowerCase())) {
        out.add(b);
      }
    } else if (out.length == 1) {
      final b = _cleanChipForInsert(_kFallbackChipSeed);
      if (!out.any((e) => e.toLowerCase() == b.toLowerCase())) out.add(b);
    }

    return out.length > max ? out.take(max).toList() : out;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Topic-Chips (UI) — aus Tags/Facetten dedupliziert (case-insensitive)
  // ─────────────────────────────────────────────────────────────────────

  /// UI-nahe Themenchips (roh, ohne starke Normalisierung). Für Anzeige geeignet.
  static List<String> topicChips(dynamic turn, {int limit = 6}) {
    final tags = _listOfString(_get(turn, 'tags'));

    // Kontext kann je nach Quelle List<String> (DTO) oder Map sein
    final ctxMap = _map(_get(turn, 'context'));
    final facetsCtx = _listOfString(ctxMap['facets']);
    final topicsCtx = _listOfString(ctxMap['topics']);

    // Normalized-API: understanding.{facets,topics}
    final understanding = _map(_get(turn, 'understanding'));
    final facetsUnder = _listOfString(understanding['facets']);
    final topicsUnder = _listOfString(understanding['topics']);

    final src = <String>[
      ...tags,
      ...facetsCtx,
      ...topicsCtx,
      ...facetsUnder,
      ...topicsUnder,
    ];

    final out = <String>[];
    final seen = <String>{};
    for (final raw in src) {
      final t = raw.trim();
      if (t.isEmpty) continue;

      // Offensichtliche Nicht-Topics ausfiltern
      final lower = t.toLowerCase();
      if (lower.startsWith('mood:') ||
          lower.startsWith('emotion:') ||
          lower.startsWith('moodscore:') ||
          lower.startsWith('mood_score:') ||
          lower.startsWith('risk') ||
          lower == 'mild' ||
          lower == 'high' ||
          lower == 'none') {
        continue;
      }

      final key = t.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(_trimEllipsis(t));
      if (out.length >= limit) break;
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Topic-Normalisierung (K3) — ≤3 Wörter, lowercase, trim, de-dup
  // ─────────────────────────────────────────────────────────────────────

  /// Liefert normalisierte Topic-Kandidaten für Kontext/Timeline (hart bereinigt).
  static List<String> topicsNormalized(
    dynamic turn, {
    int limit = 6,
    int maxWords = 3,
  }) {
    final rawChips = topicChips(turn, limit: limit * 2); // reichlich Rohmaterial
    final out = <String>[];
    final seen = <String>{};

    for (final raw in rawChips) {
      final norm = _normalizeTopic(raw, maxWords: maxWords);
      if (norm.isEmpty) continue;
      if (!seen.add(norm)) continue;
      out.add(norm);
      if (out.length >= limit) break;
    }

    // Zusätzliche Quellen: tags wie "topic: ..." / "theme: ..."
    if (out.length < limit) {
      final tags = _listOfString(_get(turn, 'tags'));
      for (final t in tags) {
        final l = t.toLowerCase().trim();
        if (l.startsWith('topic:') || l.startsWith('theme:')) {
          final norm = _normalizeTopic(
              t.split(':').skip(1).join(':').trim(),
              maxWords: maxWords);
          if (norm.isEmpty) continue;
          if (!seen.add(norm)) continue;
          out.add(norm);
          if (out.length >= limit) break;
        }
      }
    }

    return out;
  }

  /// Heuristisch ein Primär-Topic bestimmen (für Timeline-Marker).
  /// Gibt TopicInfo mit Quelle & Confidence (0.0–1.0) zurück.
  static TopicInfo pickPrimaryTopic(
    dynamic turn, {
    String? hint,
  }) {
    final candidates = <_ScoredTopic>[];
    final hintNorm = _normalizeTopic(hint ?? '');

    // 1) understanding.topics (höchste Priorität)
    for (final t in _listOfString(_map(_get(turn, 'understanding'))['topics'])) {
      final norm = _normalizeTopic(t);
      if (norm.isEmpty) continue;
      candidates.add(_ScoredTopic(norm, source: 'understanding.topics', base: 1.00));
    }

    // 2) context.topics / context.facets
    final ctx = _map(_get(turn, 'context'));
    for (final t in _listOfString(ctx['topics'])) {
      final norm = _normalizeTopic(t);
      if (norm.isEmpty) continue;
      candidates.add(_ScoredTopic(norm, source: 'context.topics', base: 0.92));
    }
    for (final t in _listOfString(ctx['facets'])) {
      final norm = _normalizeTopic(t);
      if (norm.isEmpty) continue;
      candidates.add(_ScoredTopic(norm, source: 'context.facets', base: 0.88));
    }

    // 3) tags: "topic:..." / "theme:..." / sonstige (gefiltert)
    final tags = _listOfString(_get(turn, 'tags'));
    for (final t in tags) {
      final l = t.toLowerCase().trim();
      if (l.startsWith('mood:') ||
          l.startsWith('emotion:') ||
          l.startsWith('moodscore:') ||
          l.startsWith('mood_score:') ||
          l.startsWith('risk') ||
          l == 'mild' ||
          l == 'high' ||
          l == 'none') {
        continue;
      }
      String candidate = t;
      if (l.startsWith('topic:') || l.startsWith('theme:')) {
        candidate = t.split(':').skip(1).join(':');
      }
      final norm = _normalizeTopic(candidate);
      if (norm.isEmpty) continue;
      candidates.add(_ScoredTopic(norm, source: 'tags', base: 0.84));
    }

    // 4) Fallback: topicsNormalized()
    if (candidates.isEmpty) {
      for (final norm in topicsNormalized(turn, limit: 3)) {
        candidates.add(_ScoredTopic(norm, source: 'normalized', base: 0.80));
      }
    }

    if (candidates.isEmpty) {
      return const TopicInfo(topic: '', source: 'none', confidence: 0.0);
    }

    // Aggregation: gleicher Topic-String → Boost durch Wiederholung
    final agg = <String, _Agg>{};
    for (final c in candidates) {
      final key = c.topic;
      final entry = agg.putIfAbsent(key, () => _Agg());
      entry.count += 1;
      entry.bestBase = entry.bestBase < c.base ? c.base : entry.bestBase;
      entry.sources.add(c.source);
    }

    // Endscore berechnen
    String bestTopic = '';
    double bestScore = -1.0;
    String bestSource = 'mixed';

    agg.forEach((topic, a) {
      // Base aus bester Quelle
      double score = a.bestBase;

      // Wiederholungs-Boost: +0.03 je zusätzlichem Vorkommen (bis +0.12)
      final repBoost = (a.count - 1).clamp(0, 4) * 0.03;
      score += repBoost;

      // Hint-Boost, falls übergeben
      if (hintNorm.isNotEmpty && hintNorm == topic) {
        score += 0.10;
      } else if (hintNorm.isNotEmpty && topic.contains(hintNorm)) {
        score += 0.05;
      }

      if (score > bestScore) {
        bestScore = score;
        bestTopic = topic;
        bestSource = a.sources.contains('understanding.topics')
            ? 'understanding.topics'
            : a.sources.contains('context.topics')
                ? 'context.topics'
                : a.sources.contains('context.facets')
                    ? 'context.facets'
                    : a.sources.contains('tags')
                        ? 'tags'
                        : 'normalized';
      }
    });

    final conf = double.parse(bestScore.clamp(0.0, 1.0).toStringAsFixed(2));
    return TopicInfo(topic: bestTopic, source: bestSource, confidence: conf);
  }

  /// Liefert nur den Topic-String für Timeline-Markierung (oder '').
  static String timelineTopic(dynamic turn, {String? hint}) {
    final info = pickPrimaryTopic(turn, hint: hint);
    return info.topic;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Hope/Closure — mood_intro / hope_reply / closure_prompt (alias-safe)
  // ─────────────────────────────────────────────────────────────────────

  /// Nimmt eine Closure-Response (Map oder Worker-Objekt) und normalisiert Felder.
  static Map<String, String> mapClosure(dynamic closureResponse) {
    // Zulässige Eingaben:
    //  - { closure: { mood_intro: {text}, hope_reply, closure_prompt }, flow: {...} }
    //  - direkt { mood_intro, hope_reply, closure_prompt }
    //  - alias: moodIntro/hopeReply/closurePrompt werden akzeptiert
    final src = _map(closureResponse);
    final closure = _map(_aliasValue(src, 'closure') ?? src);

    final moodIntroObj = _map(_aliasValue(closure, 'mood_intro'));
    final moodText = (_aliasValue(moodIntroObj, 'text') ?? '').toString().trim();

    final hope   = (_aliasValue(closure, 'hope_reply') ?? '').toString().trim();
    final prompt = (_aliasValue(closure, 'closure_prompt') ?? '').toString().trim();

    return {
      'mood_intro': moodText,
      'hope_reply': hope,
      'closure_prompt': prompt,
    };
  }

  // ─────────────────────────────────────────────────────────────────────
  // Emotionen — aus Tags/Kontext heuristisch; inkl. MoodScore (−2..+2)
  // ─────────────────────────────────────────────────────────────────────

  static EmotionInfo mapEmotions(dynamic turn) {
    // 1) Aus Tags lesen:
    final tags = _listOfString(_get(turn, 'tags'));

    // moodScore:<0..4> oder mood_score:<0..4> → −2..+2
    double? score;
    for (final t in tags) {
      final s = t.trim();
      final low = s.toLowerCase();
      if (low.startsWith('moodscore:') || low.startsWith('mood_score:')) {
        final n = int.tryParse(s.split(':').last.trim());
        if (n != null) {
          score = n.clamp(0, 4).toDouble() - 2.0;
          break;
        }
      }
    }

    // mood:<Label> oder emotion:<Label>
    String? primary;
    String? secondary;
    for (final t in tags) {
      final s = t.trim();
      final lower = s.toLowerCase();
      if (lower.startsWith('mood:')) {
        primary ??= _labelCap(s.substring(5).trim());
      } else if (lower.startsWith('emotion:')) {
        secondary ??= _labelCap(s.substring(8).trim());
      }
    }

    // 2) Optional aus Kontext lesen (falls vorhanden)
    final ctx = _map(_get(turn, 'context'));
    if ((primary == null || primary.isEmpty) && ctx.isNotEmpty) {
      primary = _labelCap(
          (_aliasValue(ctx, 'mood') ?? _aliasValue(ctx, 'primary_emotion') ?? '')
              .toString());
    }
    if ((secondary == null || secondary.isEmpty) && ctx.isNotEmpty) {
      secondary = _labelCap(
          (_aliasValue(ctx, 'secondary_emotion') ?? '').toString());
    }
    if (score == null) {
      final s = (_aliasValue(ctx, 'mood_score') ?? _aliasValue(ctx, 'sentiment') ?? '')
          .toString();
      final n = double.tryParse(s.trim());
      if (n != null) score = n.clamp(-2.0, 2.0);
    }

    // 3) Ableitung aus Labels (fallback), minimale Heuristik
    score ??= _scoreFromLabel(primary) ?? _scoreFromLabel(secondary) ?? 0.0;

    return EmotionInfo(
      moodLabel: (primary ?? '').trim(),
      secondaryLabel: (secondary ?? '').trim(),
      moodScore: double.parse(score.toStringAsFixed(2)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Risiko-Level — 'none' | 'mild' | 'high' (+ bool risk)
  // ─────────────────────────────────────────────────────────────────────

  static RiskInfo mapRisk(dynamic turn) {
    // Map-Ansicht besorgen (tolerant für DTOs/Maps)
    final m = _map(turn);
    String _asStr(dynamic v) => (v ?? '').toString().trim().toLowerCase();

    // Quellen: risk_level | level | risk_flag/riskFlag | risk (bool)
    final rl = _asStr(_aliasValue(m, 'risk_level'));
    final lvl = _asStr(_aliasValue(m, 'level'));
    final flag = _asStr(_aliasValue(m, 'risk_flag') ?? _get(turn, 'riskFlag'));
    final boolFlg = (m['risk'] == true);

    String mapLevel(String x) {
      if (x == 'high' || x == 'crisis') return 'high';
      if (x == 'mild' || x == 'support' || x == 'true') return 'mild';
      return 'none';
    }

    String level = 'none';
    if (rl.isNotEmpty) {
      level = mapLevel(rl);
    } else if (lvl.isNotEmpty) {
      level = mapLevel(lvl);
    } else if (flag.isNotEmpty) {
      level = mapLevel(flag);
    }
    if (level == 'none' && boolFlg) level = 'mild'; // konservativer Fallback

    final risk = (level == 'mild' || level == 'high') || boolFlg;
    return RiskInfo(level: level, risk: risk);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Utilities (sanft, robust)
  // ─────────────────────────────────────────────────────────────────────

  static String _cleanChipForDisplay(String s) {
    var x = s.trim();
    x = x.replaceAll(RegExp(r'^[0-9]+[.)]\s+'), '');
    x = x.replaceAll(RegExp(r'^[\u2013\-\u2022\s]+'), '');
    x = x.replaceAll(RegExp('^[„“"\'»«]+'), '');
    x = x.replaceAll(RegExp(r'\s*[:：]\s*$'), ''); // trailing ':' entfernen
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    x = x.replaceAll(RegExp(r'\s*[?!]+$'), '');
    if (x.length > 72) x = '${x.substring(0, 72).trimRight()}…';
    if (!x.endsWith('…')) x = '$x…';
    return x.trim();
  }

  static String _cleanChipForInsert(String s) {
    var x = s.trim();
    x = x.replaceAll(RegExp(r'^[0-9]+[.)]\s+'), '');
    x = x.replaceAll(RegExp(r'^[\u2013\-\u2022\s]+'), '');
    x = x.replaceAll(RegExp('^[„“"\'»«]+'), '');
    x = x.replaceAll(RegExp(r'\s*[:：]\s*$'), ''); // trailing ':' entfernen
    x = x.replaceAll(RegExp(r'[…]+$'), '');
    x = x.replaceAll(RegExp(r'\s*[?!.\u2026]+$'), '');
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  static String _trimEllipsis(String s) =>
      s.replaceAll(RegExp(r'[ \u2026…]+$'), '').trim();

  static String _labelCap(String v) {
    final t = v.trim();
    if (t.isEmpty) return '';
    return t[0].toUpperCase() + t.substring(1);
  }

  static double? _scoreFromLabel(String? label) {
    if (label == null) return null;
    final k = label.toLowerCase().trim();
    const map = <String, double>{
      'glücklich': 2.0,
      'freudig': 2.0,
      'ruhig': 1.0,
      'neutral': 0.0,
      'traurig': -1.0,
      'gestresst': -1.0,
      'wütend': -2.0,
      'ängstlich': -1.0,
      'verzweifelt': -2.0,
      'hoffnungsvoll': 1.0,
      'dankbar': 1.0,
    };
    return map[k];
  }

  // generic defensive getters (alias-safe)
  static dynamic _get(dynamic obj, String key) {
    if (obj == null) return null;

    // 1) Direktzugriff auf bekannte DTO-Felder per switch (inkl. snake_case-Aliase)
    try {
      final d = obj as dynamic;
      switch (key) {
        case 'answerHelpers':
          return d.answerHelpers ?? d.answer_helpers;
        case 'followups':
          return d.followups ?? d.follow_ups;
        case 'tags':
          return d.tags;
        case 'context':
          return d.context;
        case 'understanding':
          return d.understanding;
        case 'riskFlag':
          return d.riskFlag ?? d.risk_flag;
        case 'helperSuggestion':
          return d.helperSuggestion ?? d.helper_suggestion;
        case 'flow':
          return d.flow;
        case 'session':
          return d.session;
        case 'questions':
          return d.questions;
        case 'talk':
          return d.talk;
      }
    } catch (_) {
      // weiter zu den Map-Fällen
    }

    // 2) toJson()-Map (falls vorhanden) — danach Alias-Keys versuchen
    try {
      final m = (obj as dynamic).toJson?.call();
      if (m is Map) {
        final mv = Map<String, dynamic>.from(m);
        final direct = mv[key];
        if (direct != null) return direct;
        final alias = _aliasValue(mv, key);
        if (alias != null) return alias;
      }
    } catch (_) {}

    // 3) direkte Map + Aliase
    if (obj is Map) {
      final mv = Map<String, dynamic>.from(obj);
      if (mv.containsKey(key)) return mv[key];
      final alias = _aliasValue(mv, key);
      if (alias != null) return alias;
    }

    return null;
  }

  static List<String> _listOfString(dynamic v) {
    if (v == null) return const <String>[];
    if (v is List) {
      return v
          .where((e) => e != null)
          .map((e) => e.toString())
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  static Map<String, dynamic> _map(dynamic v) {
    if (v is Map) {
      return Map<String, dynamic>.from(v);
    }
    try {
      final m = (v as dynamic).toJson?.call();
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return <String, dynamic>{};
  }

  // ─────────────────────────────────────────────────────────────────────
  // Alias-Utilities
  // ─────────────────────────────────────────────────────────────────────

  static dynamic _aliasValue(dynamic src, String key) {
    final m = _map(src);
    if (m.isEmpty) return null;

    // Kandidaten: original, snake, camel + handverlesene Synonyme
    final candidates = <String>{
      key,
      _toSnake(key),
      _toCamel(key),
      if (key == 'followups') 'follow_ups',
      if (key == 'answerHelpers') 'answer_helpers',
      if (key == 'riskFlag') 'risk_flag',
      if (key == 'helperSuggestion') 'helper_suggestion',
      if (key == 'mood_intro') 'moodIntro',
      if (key == 'hope_reply') 'hopeReply',
      if (key == 'closure_prompt') 'closurePrompt',
    };

    for (final c in candidates) {
      if (m.containsKey(c)) return m[c];
    }
    // Case-insensitive Fallback
    final lowerMap = <String, dynamic>{
      for (final e in m.entries) e.key.toLowerCase(): e.value
    };
    for (final c in candidates) {
      final v = lowerMap[c.toLowerCase()];
      if (v != null) return v;
    }
    return null;
  }

  static String _toSnake(String k) {
    if (k.contains('_')) return k;
    return k.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
  }

  static String _toCamel(String k) {
    if (!k.contains('_')) return k;
    final parts = k.split('_');
    return parts.first + parts.skip(1).map((p) => p.isEmpty ? '' : (p[0].toUpperCase() + p.substring(1))).join();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Topic-Normalisierung — Utilities
  // ─────────────────────────────────────────────────────────────────────

  static String _normalizeTopic(String raw, {int maxWords = 3}) {
    if (raw.isEmpty) return '';
    var s = _stripPunctEmoji(raw.toLowerCase());
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return '';

    // Tokenize & Stopwords filtern
    final tokens = _tokenize(s)
        .where((w) => w.isNotEmpty && !_isStopwordDe(w))
        .toList();

    if (tokens.isEmpty) return '';
    final limited = tokens.take(maxWords).toList();

    // Kurze/triviale Einträge verwerfen
    final joined = limited.join(' ').trim();
    if (joined.length < 2) return '';
    return joined;
  }

  static String _stripPunctEmoji(String s) {
    // Erlaubt: Buchstaben (inkl. Umlauten), Ziffern, Leerzeichen, Bindestrich
    // Entfernt: sonstige Satzzeichen, Emojis, Quotes
    final re = RegExp(r'[^A-Za-zÀ-ÖØ-öø-ÿ0-9\s\-]');
    return s.replaceAll(re, '');
  }

  static Iterable<String> _tokenize(String s) =>
      s.split(RegExp(r'\s+')).map((w) => w.trim());

  static bool _isStopwordDe(String w) {
    // Kleine, robuste Menge an Stopwörtern + triviale Wörter
    const set = <String>{
      'und', 'oder', 'aber', 'denn', 'doch', 'nur', 'auch',
      'der', 'die', 'das', 'ein', 'eine', 'einer', 'einem', 'einen', 'eines',
      'im', 'in', 'am', 'an', 'auf', 'aus', 'mit', 'ohne', 'für', 'von', 'vor',
      'nach', 'bei', 'zum', 'zur', 'zu', 'über', 'unter', 'zwischen',
      'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr', 'man', 'mein', 'dein',
      'heute', 'gestern', 'morgen', 'jetzt', 'bisschen', 'mal',
      'sehr', 'mehr', 'weniger', 'viel', 'wenig', 'noch', 'schon',
      'thema', 'topics', 'topic', 'facet', 'facets',
    };
    return set.contains(w);
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Kleinere Value-Objekte für UI/Service-Schichten
// ────────────────────────────────────────────────────────────────────────────

class EmotionInfo {
  final String moodLabel; // primäres Label (z. B. „Ruhig“)
  final String secondaryLabel; // optional (z. B. „Hoffnungsvoll“)
  final double moodScore; // −2..+2

  const EmotionInfo({
    required this.moodLabel,
    required this.secondaryLabel,
    required this.moodScore,
  });

  Map<String, dynamic> toJson() => {
        'mood_label': moodLabel,
        'secondary_label': secondaryLabel,
        'mood_score': moodScore,
      };

  EmotionInfo copyWith({
    String? moodLabel,
    String? secondaryLabel,
    double? moodScore,
  }) =>
      EmotionInfo(
        moodLabel: moodLabel ?? this.moodLabel,
        secondaryLabel: secondaryLabel ?? this.secondaryLabel,
        moodScore: moodScore ?? this.moodScore,
      );
}

class RiskInfo {
  final String level; // 'none' | 'mild' | 'high'
  final bool risk;

  const RiskInfo({required this.level, required this.risk});

  Map<String, dynamic> toJson() => {
        'risk_level': level,
        'risk': risk,
      };
}

class TopicInfo {
  final String topic;      // normalisiert (≤3 Wörter, lowercase)
  final String source;     // understanding.topics | context.topics | context.facets | tags | normalized | none
  final double confidence; // 0.00–1.00

  const TopicInfo({
    required this.topic,
    required this.source,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
    'topic': topic,
    'source': source,
    'confidence': confidence,
  };

  @override
  String toString() =>
      'TopicInfo(topic: $topic, source: $source, confidence: $confidence)';
}

// Kleine String-Extension (lokal, für eventuelle Helfer)
extension IfEmptyX on String {
  String ifEmpty(String Function() alt) => isEmpty ? alt() : this;
}

// interne Hilfsklassen für Scoring
class _ScoredTopic {
  final String topic;
  final String source;
  final double base; // Grundscore je Quelle

  _ScoredTopic(this.topic, {required this.source, required this.base});
}

class _Agg {
  int count = 0;
  double bestBase = 0.0;
  final Set<String> sources = <String>{};
}
