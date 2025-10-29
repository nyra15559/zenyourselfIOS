// lib/services/guidance/helper_mappers.dart
//
// Guidance — Helper-Mappers (v1.3 · 2025-10-24)
// -----------------------------------------------------------------------------
// Zweck: Schlanke Mapper/Funktionen für UI-nahe Daten aus Worker/DTOs.
//  • helpers limitieren (max. 3) → Display/Insert-Varianten, sanft bereinigt.
//  • topic chips mappen          → aus Tags/Facetten dedupliziert.
//  • hope closure mappen         → mood_intro/hope_reply/closure_prompt normalisiert.
//  • emotion felder mappen       → Mood/Emotions aus Tags/Kontext (robust).
//  • risikolevel übernehmen      → 'none' | 'mild' | 'high' (+ bool risk).
//
// Änderungen v1.3:
//  • Mindestanzahl Chips jetzt robust: 0 → 2 Fallbacks, 1 → +1 Fallback.
//  • Trailing-Doppelpunkt wird bei Display/Insert entfernt.
//  • Risk-Mapping liest zusätzlich top-level `risk_level`/`level`/`risk_flag`
//    und bool `risk` (Konservativ: true ⇒ mild, falls sonst none).
//  • take(max) nach Fallbacks für harte Obergrenze.
// -----------------------------------------------------------------------------
//
// Abhängigkeit: optionale DTOs (ReflectionTurn etc.). Diese Datei toleriert auch
// plain Maps (dyn). Keine Flutter-UI-Imports nötig.
//

library guidance_helper_mappers;

/// Optional, falls die DTOs verfügbar sind (gleicher Ordner).
/// Nicht zwingend – die Mapper funktionieren auch mit dynamic/Map.
///
/// import './dtos.dart';

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
    final legacy = _listOfString(_get(turn, 'followups'));
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
  // Topic-Chips — aus Tags/Facetten dedupliziert (case-insensitive)
  // ─────────────────────────────────────────────────────────────────────

  static List<String> topicChips(dynamic turn, {int limit = 6}) {
    final tags = _listOfString(_get(turn, 'tags'));

    // Kontext kann je nach Quelle List<String> (DTO) oder Map mit Facetten sein
    final ctxMap = _map(_get(turn, 'context'));
    final facetsCtx = _listOfString(ctxMap['facets']);
    final topicsCtx = _listOfString(ctxMap['topics']);

    // Normalized-API legt Facetten/Topics unter understanding.{facets,topics} ab
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
      final key = t.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(_trimEllipsis(t));
      if (out.length >= limit) break;
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Hope/Closure — mood_intro / hope_reply / closure_prompt
  // ─────────────────────────────────────────────────────────────────────

  /// Nimmt eine Closure-Response (Map oder Worker-Objekt) und normalisiert Felder.
  static Map<String, String> mapClosure(dynamic closureResponse) {
    // Zulässige Eingaben:
    //  - { closure: { mood_intro: {text}, hope_reply, closure_prompt }, flow: {...} }
    //  - direkt { mood_intro, hope_reply, closure_prompt }
    final src = _map(closureResponse);
    final closure =
        _map(src['closure']).isNotEmpty ? _map(src['closure']) : src;

    final moodIntro = _map(closure['mood_intro']);
    final moodText = (moodIntro['text'] ?? '').toString().trim();

    final hope = (closure['hope_reply'] ?? '').toString().trim();
    final prompt = (closure['closure_prompt'] ?? '').toString().trim();

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

    // moodScore:<0..4> → −2..+2
    double? score;
    for (final t in tags) {
      final s = t.trim();
      if (s.toLowerCase().startsWith('moodscore:')) {
        final n = int.tryParse(s.substring(10).trim());
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
      primary =
          _labelCap((ctx['mood'] ?? ctx['primary_emotion'] ?? '').toString());
    }
    if ((secondary == null || secondary.isEmpty) && ctx.isNotEmpty) {
      secondary = _labelCap((ctx['secondary_emotion'] ?? '').toString());
    }
    if (score == null) {
      final s = (ctx['mood_score'] ?? ctx['sentiment'] ?? '').toString();
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
    final rl = _asStr(m['risk_level']);
    final lvl = _asStr(m['level']);
    final flag =
        _asStr(m['risk_flag'] ?? m['riskFlag'] ?? _get(turn, 'riskFlag'));
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

  // generic defensive getters
  static dynamic _get(dynamic obj, String key) {
    if (obj == null) return null;

    // 1) Direktzugriff auf bekannte DTO-Felder per switch (kein Spiegel/mirrors).
    try {
      final d = obj as dynamic;
      switch (key) {
        case 'answerHelpers':
          return d.answerHelpers;
        case 'followups':
          return d.followups;
        case 'tags':
          return d.tags;
        case 'context':
          return d.context;
        case 'understanding':
          return d
              .understanding; // existiert nur bei normalisiertem JSON-Objekt
        case 'riskFlag':
          return d.riskFlag;
        case 'helperSuggestion':
          return d.helperSuggestion;
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

    // 2) toJson()-Map (falls vorhanden)
    try {
      final m = (obj as dynamic).toJson?.call();
      if (m is Map) return m[key];
    } catch (_) {}

    // 3) direkte Map
    if (obj is Map) return obj[key];

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
}

// ────────────────────────────────────────────────────────────────────────────
/* Kleinere Value-Objekte für UI/Service-Schichten */
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
