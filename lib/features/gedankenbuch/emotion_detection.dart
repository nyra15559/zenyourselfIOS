// lib/features/voice/emotion_detection.dart
//
// Emotion Detection — Oxford Zen Edition
// -------------------------------------
// • Robust, transparent keyword–scoring (multi-language DE/EN) + Umlaut-Normalisierung
// • Crisis signal (self-harm/suicidality) flag without diagnosis
// • Clear UI visuals (emoji + color) aligned with our palette
// • Safe defaults: neutral if uncertain, bounded confidence
// • Fully serializable (toJson / fromJson)
// • Helpers: toMoodLabel()  → Journal-Label  |  toMoodScore() → 0..4 Scale
//
// NOTE: This is a lightweight, on-device heuristic.
//       Swap out the scoring with a model later via the same API.

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Modellierte Emotionen
enum EmotionType {
  joy,
  sadness,
  anger,
  fear,
  calm,
  surprise,
  neutral,
  compassion,
}

/// Ergebnis-Objekt für die Emotionsanalyse
class DetectedEmotionResult {
  final EmotionType emotion;
  /// 0.0–1.0 (wir clampen auf [0.55, 0.98] für UI-Stabilität)
  final double confidence;
  final String emoji;
  final Color color;

  /// Optional: kurze Begründung (z. B. erkannte Schlüsselwörter)
  final String? reason;

  /// Sicherheits-Flag, falls Text mögliche Krisen-Signale enthält
  final bool isCrisis;

  /// (Optional) Welche Keywords wurden gefunden – für Debug/Telemetrie (lokal)
  final List<String> matchedKeywords;

  const DetectedEmotionResult({
    required this.emotion,
    required this.confidence,
    required this.emoji,
    required this.color,
    this.reason,
    this.isCrisis = false,
    this.matchedKeywords = const [],
  });

  /// UX-Label (DE/EN)
  String label({String locale = 'de'}) {
    final map = locale.toLowerCase().startsWith('en')
        ? _emotionLabelsEn
        : _emotionLabelsDe;
    return map[emotion]!;
  }

  /// Mapped auf unsere Journal-Labels (Glücklich, Ruhig, Neutral, Traurig, Gestresst, Wütend)
  String toMoodLabel() => _emotionToMoodLabel(emotion);

  /// Grober 0..4-Moodscore (kompatibel zu GuidanceService.classifyMood)
  int toMoodScore() => _emotionToMoodScore(emotion);

  Map<String, dynamic> toJson() => {
        'emotion': emotion.name,
        'confidence': confidence,
        'emoji': emoji,
        'color': color.value,
        'reason': reason,
        'isCrisis': isCrisis,
        'matchedKeywords': matchedKeywords,
      };

  factory DetectedEmotionResult.fromJson(Map<String, dynamic> j) {
    final e = EmotionType.values.firstWhere(
      (x) => x.name == (j['emotion'] as String? ?? 'neutral'),
      orElse: () => EmotionType.neutral,
    );
    return DetectedEmotionResult(
      emotion: e,
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.66,
      emoji: j['emoji'] as String? ?? _emotionVisuals[e]!['emoji'] as String,
      color: Color((j['color'] as num?)?.toInt() ?? (_emotionVisuals[e]!['color'] as Color).value),
      reason: j['reason'] as String?,
      isCrisis: j['isCrisis'] as bool? ?? false,
      matchedKeywords:
          (j['matchedKeywords'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

/// Oxford/Zen Farben & Emojis für jede Emotion (zentral für UI)
const Map<EmotionType, Map<String, dynamic>> _emotionVisuals = {
  EmotionType.joy:        {'emoji': '😊', 'color': Color(0xFFA5CBA1)}, // Soft Sage
  EmotionType.sadness:    {'emoji': '😢', 'color': Color(0xFF95A3B3)}, // Blue Gray
  EmotionType.anger:      {'emoji': '😡', 'color': Color(0xFFD67873)}, // Warm Rust
  EmotionType.fear:       {'emoji': '😨', 'color': Color(0xFFB2B8CB)}, // Mist Blue
  EmotionType.calm:       {'emoji': '🌿', 'color': Color(0xFFBEE6CB)}, // Calm Green
  EmotionType.surprise:   {'emoji': '😲', 'color': Color(0xFFF7CE84)}, // Golden Mist
  EmotionType.neutral:    {'emoji': '😐', 'color': Color(0xFFB5B5B5)}, // Neutral Gray
  EmotionType.compassion: {'emoji': '🤗', 'color': Color(0xFFE9C8A7)}, // Warm Sand
};

const Map<EmotionType, String> _emotionLabelsDe = {
  EmotionType.joy: 'Freude',
  EmotionType.sadness: 'Traurigkeit',
  EmotionType.anger: 'Wut',
  EmotionType.fear: 'Angst',
  EmotionType.calm: 'Ruhe',
  EmotionType.surprise: 'Überraschung',
  EmotionType.neutral: 'Neutral',
  EmotionType.compassion: 'Mitgefühl',
};

const Map<EmotionType, String> _emotionLabelsEn = {
  EmotionType.joy: 'Joy',
  EmotionType.sadness: 'Sadness',
  EmotionType.anger: 'Anger',
  EmotionType.fear: 'Fear',
  EmotionType.calm: 'Calm',
  EmotionType.surprise: 'Surprise',
  EmotionType.neutral: 'Neutral',
  EmotionType.compassion: 'Compassion',
};

/// Keyword-Bank (DE+EN). Später durch ML/Backend ersetzbar.
/// Wichtig: sanfte, nicht-diagnostische Hinweise.
final Map<EmotionType, List<String>> _keywords = {
  EmotionType.joy: [
    'glücklich','freude','dankbar','lachen','zufrieden','leicht',
    'happy','joy','grateful','smile','content','uplifted'
  ],
  EmotionType.sadness: [
    'traurig','erschöpft','verloren','leer','weinen','niedergeschlagen',
    'sad','tired','exhausted','lost','down'
  ],
  EmotionType.anger: [
    'wütend','ärgerlich','genervt','frustriert','gereizt',
    'angry','mad','furious','annoyed','irritated','frustrated'
  ],
  EmotionType.fear: [
    'ängstlich','angst','sorge','unsicher','panik','bedrohlich',
    'afraid','anxious','fear','worry','panic','unsafe'
  ],
  EmotionType.calm: [
    'ruhig','gelassen','ausgeglichen','zentriert','klar',
    'calm','peaceful','grounded','centered','clear'
  ],
  EmotionType.surprise: [
    'überrascht','wow','unerwartet','krass','what?!',
    'surprised','shocked','unexpected','astonished','wow'
  ],
  EmotionType.compassion: [
    'mitgefühl','herzlich','verstehen','freundlich','warmherzig',
    'compassion','tender','kind','caring','warm'
  ],
  // neutral: kein eigenes Set – default wenn nichts passt
};

/// Potenzielle Krisen-Signale (Stichworte; keine Diagnosen).
const List<String> _crisisKeywords = [
  // DE
  'suizid','selbstmord','ich will nicht mehr','mich umbringen','mich verletzen',
  'ritzen','abschied nehmen','keinen sinn',
  // EN
  'suicide','kill myself','end it all','self harm','hurt myself','goodbye world',
];

/// Hauptfunktion zur Emotions-Detektion (Text-basiert)
Future<DetectedEmotionResult> detectEmotionFromVoice({
  required String transcript,
  String locale = 'de',
}) async {
  // Mini async, um API kompatibel zu halten (später: echte Modell-Calls)
  await Future<void>.delayed(const Duration(milliseconds: 1));

  final raw = transcript.trim();
  if (raw.isEmpty) {
    return _neutralResult(reason: 'Kein Inhalt erkannt.');
  }

  final lower = raw.toLowerCase();
  final norm = _normalize(lower);

  // 1) Krisen-Signal prüfen (ohne harte Entscheidungen zu treffen)
  final matchedCrisis = _matchAny(lower, _crisisKeywords, normedText: norm);

  // 2) Scoring per Emotion
  final scores = <EmotionType, int>{ for (final e in EmotionType.values) e: 0 };
  final matched = <String>[];

  for (final entry in _keywords.entries) {
    for (final kw in entry.value) {
      if (_containsKw(lower, kw, normedText: norm)) {
        scores[entry.key] = (scores[entry.key] ?? 0) + 1;
        matched.add(kw);
      }
    }
  }

  // 3) Best Emotion bestimmen
  final best = _bestEmotion(scores);

  // 4) Confidence ableiten (sanft normalisiert)
  final totalHits = math.max(0, matched.length);
  final bestHits = scores[best] ?? 0;
  final conf = _confidenceFromHits(bestHits: bestHits, totalHits: totalHits);

  // 5) Visuals laden
  final visuals = _emotionVisuals[best]!;
  final emoji = visuals['emoji'] as String;
  final color = visuals['color'] as Color;

  // 6) Freundliche Begründung
  final because = matched.isEmpty
      ? 'Sanfte Schätzung basierend auf deinem Text.'
      : 'Erkannt wegen: ${matched.take(5).join(', ')}'
        '${matched.length > 5 ? ' (+${matched.length - 5})' : ''}.';

  return DetectedEmotionResult(
    emotion: best,
    confidence: conf,
    emoji: emoji,
    color: color,
    reason: because,
    isCrisis: matchedCrisis,
    matchedKeywords: matched,
  );
}

/// -------------------- Hilfsfunktionen --------------------

DetectedEmotionResult _neutralResult({String? reason}) {
  final v = _emotionVisuals[EmotionType.neutral]!;
  return DetectedEmotionResult(
    emotion: EmotionType.neutral,
    confidence: 0.66,
    emoji: v['emoji'] as String,
    color: v['color'] as Color,
    reason: reason ?? 'Neutral (unsicher).',
  );
}

/// Umlaut-/Sonderzeichen-Normalisierung für DE/EN (einfach & lokal).
String _normalize(String s) {
  return s
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ì', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ò', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u');
}

bool _containsKw(String lowerText, String kw, {required String normedText}) {
  final kLower = kw.toLowerCase();
  final kNorm = _normalize(kLower);
  // einfacher „contains“-Check plus Normalisierungs-Variante
  if (lowerText.contains(kLower) || normedText.contains(kNorm)) return true;

  // sanfte Wortgrenzenprüfung (Unicode)
  final re = RegExp(r'\b' + RegExp.escape(kLower) + r'\b', unicode: true);
  if (re.hasMatch(lowerText)) return true;

  return false;
}

bool _matchAny(String text, List<String> keywords, {required String normedText}) {
  for (final k in keywords) {
    if (_containsKw(text, k, normedText: normedText)) return true;
  }
  return false;
}

EmotionType _bestEmotion(Map<EmotionType, int> scores) {
  // Entferne neutral aus Selektion – wird nur Default
  final filtered = Map.of(scores)..remove(EmotionType.neutral);

  // Fallback, wenn keine Treffer
  if (filtered.values.every((v) => v == 0)) {
    return EmotionType.neutral;
  }

  // Max wählen – bei Gleichstand leichte Präferenz für calm/joy
  final prefs = [
    EmotionType.calm,
    EmotionType.joy,
    EmotionType.compassion,
    EmotionType.surprise,
    EmotionType.sadness,
    EmotionType.fear,
    EmotionType.anger,
  ];

  final maxVal = filtered.values.fold<int>(0, (m, v) => v > m ? v : m);
  final tied = filtered.entries
      .where((e) => e.value == maxVal)
      .map((e) => e.key)
      .toSet();

  for (final p in prefs) {
    if (tied.contains(p)) return p;
  }
  return tied.first;
}

double _confidenceFromHits({required int bestHits, required int totalHits}) {
  if (totalHits <= 0 || bestHits <= 0) return 0.62;
  // Anteil des besten Clusters – sanft skaliert
  final ratio = bestHits / totalHits; // 0..1
  // mappe in [0.55, 0.98], leicht gebremst für UI
  final conf = 0.55 + 0.43 * ratio;
  return conf.clamp(0.55, 0.98);
}

/// Mapping: Emotion → Journal-Mood-Label
String _emotionToMoodLabel(EmotionType e) {
  switch (e) {
    case EmotionType.joy:
      return 'Glücklich';
    case EmotionType.calm:
    case EmotionType.compassion:
      return 'Ruhig';
    case EmotionType.neutral:
    case EmotionType.surprise:
      return 'Neutral';
    case EmotionType.sadness:
      return 'Traurig';
    case EmotionType.fear:
      return 'Gestresst';
    case EmotionType.anger:
      return 'Wütend';
  }
}

/// Mapping: Emotion → 0..4 Score (für Heuristik/Charts)
int _emotionToMoodScore(EmotionType e) {
  switch (e) {
    case EmotionType.joy:
      return 4;
    case EmotionType.calm:
    case EmotionType.compassion:
      return 3;
    case EmotionType.neutral:
    case EmotionType.surprise:
      return 2;
    case EmotionType.sadness:
    case EmotionType.fear:
      return 1;
    case EmotionType.anger:
      return 0;
  }
}
