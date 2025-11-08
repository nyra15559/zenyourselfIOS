// [BASELINE] lib/core/memory/insight_models.dart — v6.3.2 (Stand: 07.11.2025)
//
// Insight-Modelle (Facet, MoodPair, InsightScore, InsightFact)
// ------------------------------------------------------------
// • Kleine, immutable Value-Types ohne externe Abhängigkeiten (außer foundation)
// • Tolerante Factory-Methoden (fromWorker/fromMap), defensive Defaults
// • V2-Map (snake_case) Ausgabe; Backwards-kompatibel zu bestehenden Call-Sites
// • Neu: InsightFact {topic, fact, since, confidence, tags}
//
// Kompat-Hinweise:
// - Facet.fromWorker akzeptiert String ODER Map {key|id|label|name|title, hits?}
// - MoodPair.fromWorker akzeptiert {mental|icon, physical|body|somatic}
// - InsightScore.as0to4() normiert heuristisch (0..1 oder 0..100 → Quartile)
// - InsightFact.fromWorker akzeptiert flexible Schemata:
//     topic: 'topic'|'theme'|'subject'|'label'
//     fact:  'fact'|'text'|'value'|'content'|'note'
//     since: 'since'|'date'|'ts'   (ISO-8601, millis/sek UNIX möglich)
//     conf:  'confidence'|'conf'|'score'|'prob'|'weight' (0..1 oder 0..100)
//     tags:  'tags'|'labels'|'keywords'|'facets' (Strings oder Maps mit label/name/title)

import 'package:flutter/foundation.dart';

@immutable
class Facet {
  /// Technischer Schlüssel (dedupe/merge).
  final String key;

  /// Menschliches Label (Anzeige).
  final String label;

  /// Optionales Gewicht / Häufigkeit (>=1).
  final int hits;

  const Facet({
    required this.key,
    required this.label,
    this.hits = 1,
  });

  /// Tolerant gegen verschiedene Worker-Schemata.
  /// Akzeptiert:
  /// - String → {key: s, label: s}
  /// - Map → {key|id|label|name|title, hits?}
  factory Facet.fromWorker(dynamic raw) {
    if (raw is String) {
      final s = raw.trim();
      return Facet(key: s, label: s, hits: 1);
    }
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      String pickKey() {
        final k =
            (m['key'] ?? m['id'] ?? m['label'] ?? m['name'] ?? m['title'] ?? '')
                .toString()
                .trim();
        if (k.isNotEmpty) return k;
        final l = (m['label'] ?? m['title'] ?? '').toString().trim();
        return l.isNotEmpty ? l : '';
      }

      final k = pickKey();
      final l = ((m['label'] ?? m['title'] ?? k)).toString().trim();
      final h = (m['hits'] is num) ? (m['hits'] as num).toInt() : 1;
      return Facet(
        key: k.isNotEmpty ? k : l,
        label: l.isNotEmpty ? l : (k.isNotEmpty ? k : ''),
        hits: h <= 0 ? 1 : h,
      );
    }
    final s = raw?.toString().trim() ?? '';
    return Facet(key: s, label: s, hits: 1);
  }

  /// V2-Map (snake_case) bevorzugt; toleriert minimale Abweichungen.
  factory Facet.fromMap(Map<String, dynamic> m) => Facet(
        key: (m['key'] ?? '').toString(),
        label: (m['label'] ?? m['key'] ?? '').toString(),
        hits: (m['hits'] is num)
            ? (m['hits'] as num).toInt().clamp(1, 1 << 31)
            : 1,
      );

  /// V2-Map (snake_case) Ausgabe.
  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        'hits': hits,
      };

  Facet copyWith({String? key, String? label, int? hits}) => Facet(
        key: key ?? this.key,
        label: label ?? this.label,
        hits: (hits ?? this.hits),
      );

  @override
  String toString() => 'Facet(key:$key, label:$label, hits:$hits)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Facet &&
        other.key == key &&
        other.label == label &&
        other.hits == hits;
  }

  @override
  int get hashCode => Object.hash(key, label, hits);
}

@immutable
class MoodPair {
  /// 0..4 (Sehr schlecht .. Sehr gut)
  final int mental;

  /// 0..4 (Sehr schlecht .. Sehr gut)
  final int physical;

  const MoodPair({required this.mental, required this.physical});

  /// Tolerant: liest mentale/physische Stimmung aus verschiedenen Aliasen.
  /// - mental: 'mental' | 'icon'
  /// - physical: 'physical' | 'body' | 'somatic'
  factory MoodPair.fromWorker(Map<String, dynamic> m) {
    int coerce(dynamic x) {
      if (x is num) return x.toInt().clamp(0, 4);
      final s = x?.toString().toLowerCase().trim() ?? '';
      // Versuche Zahl aus String zu lesen
      final n = int.tryParse(s);
      if (n != null) return n.clamp(0, 4);
      // Grobe Text-Mapping-Heuristik (de/en)
      switch (s) {
        case 'sehr schlecht':
        case 'very bad':
        case 'awful':
          return 0;
        case 'schlecht':
        case 'bad':
          return 1;
        case 'neutral':
        case 'okay':
          return 2;
        case 'gut':
        case 'good':
          return 3;
        case 'sehr gut':
        case 'great':
        case 'excellent':
          return 4;
        default:
          return 2; // neutral
      }
    }

    return MoodPair(
      mental: coerce(m['mental'] ?? m['icon']),
      physical: coerce(m['physical'] ?? m['body'] ?? m['somatic']),
    );
  }

  factory MoodPair.fromMap(Map<String, dynamic> m) => MoodPair(
        mental: (m['mental'] is num)
            ? (m['mental'] as num).toInt().clamp(0, 4)
            : MoodPair.fromWorker(m).mental,
        physical: (m['physical'] is num)
            ? (m['physical'] as num).toInt().clamp(0, 4)
            : MoodPair.fromWorker(m).physical,
      );

  Map<String, dynamic> toMap() => {
        'mental': mental,
        'physical': physical,
      };

  MoodPair copyWith({int? mental, int? physical}) => MoodPair(
      mental: mental ?? this.mental, physical: physical ?? this.physical);

  @override
  String toString() => 'MoodPair(mental:$mental, physical:$physical)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MoodPair &&
        other.mental == mental &&
        other.physical == physical;
  }

  @override
  int get hashCode => Object.hash(mental, physical);
}

@immutable
class InsightScore {
  /// Wert typischerweise 0..1 (oder 0..100 – wird weich normiert).
  final double value;

  /// Optionaler Vergleichswert (gleiches Intervall wie value).
  final double? baseline;

  const InsightScore(this.value, {this.baseline});

  /// Heuristische Normierung auf 0..1 für die 0..4-Einteilung.
  /// - 0..1 → direkt
  /// - 0..100 → /100
  /// - >100 → als 1.0 behandeln
  double _norm() {
    final v = value;
    if (v <= 1.0) return v.clamp(0.0, 1.0);
    if (v <= 100.0) return (v / 100.0).clamp(0.0, 1.0);
    return 1.0;
  }

  /// Grobe Quartil-Skala 0..4 aus dem normalisierten Wert.
  int as0to4() {
    final v = _norm();
    if (v <= 0) return 0;
    if (v < .25) return 1;
    if (v < .5) return 2;
    if (v < .75) return 3;
    return 4;
  }

  /// Delta zum Baseline-Wert (Rohwert-Differenz; kann negativ sein).
  double delta() => (baseline == null) ? 0 : (value - baseline!);

  /// Tolerantes Einlesen:
  /// - Map {'value'|'score'|'v', 'baseline'?}
  /// - num → direkt als value
  /// - String-Zahl → parse
  factory InsightScore.fromWorker(dynamic raw) {
    if (raw is num) return InsightScore(raw.toDouble());
    if (raw is String) {
      final v = double.tryParse(raw.trim());
      return InsightScore(v ?? 0.0);
    }
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final val = (m['value'] ?? m['score'] ?? m['v']);
      final base = m['baseline'];
      final v = (val is num)
          ? val.toDouble()
          : double.tryParse(val?.toString() ?? '') ?? 0.0;
      final b = (base is num)
          ? base.toDouble()
          : double.tryParse(base?.toString() ?? '');
      return InsightScore(v, baseline: b);
    }
    return const InsightScore(0.0);
  }

  factory InsightScore.fromMap(Map<String, dynamic> m) => InsightScore(
        (m['value'] is num)
            ? (m['value'] as num).toDouble()
            : double.tryParse((m['value'] ?? '').toString()) ?? 0.0,
        baseline: (m['baseline'] is num)
            ? (m['baseline'] as num).toDouble()
            : double.tryParse((m['baseline'] ?? '').toString()),
      );

  Map<String, dynamic> toMap() => {
        'value': value,
        'baseline': baseline,
      };

  InsightScore copyWith({double? value, double? baseline}) =>
      InsightScore(value ?? this.value, baseline: baseline ?? this.baseline);

  @override
  String toString() =>
      'InsightScore(value:$value, baseline:${baseline ?? '∅'})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InsightScore &&
        other.value == value &&
        other.baseline == baseline;
  }

  @override
  int get hashCode => Object.hash(value, baseline);
}

@immutable
class InsightFact {
  /// Themen-Schlüssel (z. B. 'arbeit', 'familie') – kurz & dedupe-fähig.
  final String topic;

  /// Der eigentliche Erkenntnis-Satz.
  final String fact;

  /// Zeitpunkt der Erst-Erkenntnis (UTC empfohlen; ISO-kompatibel serialisiert).
  final DateTime since;

  /// Vertrauens-/Relevanzwert 0..1 (weich; >1 wird auf 0..1 normiert).
  final double confidence;

  /// Freie Schlagworte (bereinigt, einzigartig, klein geschrieben).
  final List<String> tags;

  const InsightFact({
    required this.topic,
    required this.fact,
    required this.since,
    this.confidence = 0.0,
    this.tags = const <String>[],
  });

  /// Toleranter Parser für Worker/Backend-Varianten.
  factory InsightFact.fromWorker(dynamic raw) {
    if (raw is String) {
      final f = raw.trim();
      return InsightFact(
        topic: '',
        fact: f,
        since: DateTime.now().toUtc(),
        confidence: 0.0,
        tags: const <String>[],
      );
    }
    final m = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    String pickTopic() {
      final t = (m['topic'] ?? m['theme'] ?? m['subject'] ?? m['label'] ?? '')
          .toString()
          .trim();
      return t;
    }

    String pickFact() {
      final f = (m['fact'] ??
              m['text'] ??
              m['value'] ??
              m['content'] ??
              m['note'] ??
              '')
          .toString()
          .trim();
      return f;
    }

    DateTime pickSince() {
      final rawSince = (m['since'] ?? m['date'] ?? m['ts']);
      final dt = _parseSince(rawSince);
      return dt ?? DateTime.now().toUtc();
    }

    double pickConfidence() {
      final c = (m['confidence'] ?? m['conf'] ?? m['score'] ?? m['prob'] ?? m['weight']);
      double v;
      if (c is num) {
        v = c.toDouble();
      } else {
        v = double.tryParse(c?.toString() ?? '') ?? 0.0;
      }
      // 0..100 → /100, >100 → 1.0
      if (v > 1.0 && v <= 100.0) v = v / 100.0;
      if (v > 1.0) v = 1.0;
      if (v < 0.0) v = 0.0;
      return v;
    }

    List<String> pickTags() => _coerceTags(m['tags'] ?? m['labels'] ?? m['keywords'] ?? m['facets']);

    return InsightFact(
      topic: pickTopic(),
      fact: pickFact(),
      since: pickSince(),
      confidence: pickConfidence(),
      tags: pickTags(),
    );
  }

  /// V2-Map (snake_case). Fehlende Felder werden defensiv ersetzt.
  factory InsightFact.fromMap(Map<String, dynamic> m) {
    return InsightFact(
      topic: (m['topic'] ?? '').toString(),
      fact: (m['fact'] ?? '').toString(),
      since: _parseSince(m['since']) ?? DateTime.now().toUtc(),
      confidence: _normConfidence(m['confidence']),
      tags: _coerceTags(m['tags']),
    );
  }

  Map<String, dynamic> toMap() => {
        'topic': topic,
        'fact': fact,
        'since': since.toUtc().toIso8601String(),
        'confidence': confidence,
        'tags': tags,
      };

  InsightFact copyWith({
    String? topic,
    String? fact,
    DateTime? since,
    double? confidence,
    List<String>? tags,
  }) =>
      InsightFact(
        topic: topic ?? this.topic,
        fact: fact ?? this.fact,
        since: since ?? this.since,
        confidence: (confidence ?? this.confidence),
        tags: tags ?? this.tags,
      );

  /// Normalisierte, einzigartige Kleinbuchstaben-Tags.
  List<String> normalizedTags() {
    final set = <String>{};
    for (final t in tags) {
      final s = (t).toString().trim().toLowerCase();
      if (s.isNotEmpty) set.add(s);
    }
    return List.unmodifiable(set);
  }

  @override
  String toString() =>
      'InsightFact(topic:$topic, fact:$fact, since:${since.toIso8601String()}, confidence:$confidence, tags:${normalizedTags()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InsightFact &&
        other.topic == topic &&
        other.fact == fact &&
        other.since.toUtc() == since.toUtc() &&
        other.confidence == confidence &&
        listEquals(other.normalizedTags(), normalizedTags());
  }

  @override
  int get hashCode =>
      Object.hash(topic, fact, since.toUtc(), confidence, Object.hashAll(normalizedTags()));

  // ---- Helpers ----------------------------------------------------------------

  static DateTime? _parseSince(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    if (raw is num) {
      // Heuristik: >= 10^12 → Millisekunden; sonst Sekunden.
      final n = raw.toInt();
      if (n > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      }
      return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
    }
    final s = raw.toString().trim();
    // Versuche ISO-8601
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toUtc();
    // Fallback: leer → null
    return null;
  }

  static double _normConfidence(dynamic raw) {
    if (raw == null) return 0.0;
    double v;
    if (raw is num) {
      v = raw.toDouble();
    } else {
      v = double.tryParse(raw.toString()) ?? 0.0;
    }
    if (v > 1.0 && v <= 100.0) v = v / 100.0;
    if (v > 1.0) v = 1.0;
    if (v < 0.0) v = 0.0;
    return v;
  }

  static List<String> _coerceTags(dynamic raw) {
    if (raw == null) return const <String>[];
    final out = <String>[];
    void addOne(dynamic x) {
      if (x == null) return;
      if (x is String) {
        // Split an Kommas/Strichpunkten tolerant erlauben.
        final parts = x.split(RegExp(r'[,\;]')).map((e) => e.trim()).where((e) => e.isNotEmpty);
        out.addAll(parts);
        return;
      }
      if (x is Map) {
        final m = Map<String, dynamic>.from(x);
        final label = (m['label'] ?? m['name'] ?? m['title'] ?? m['key'] ?? '').toString().trim();
        if (label.isNotEmpty) {
          out.add(label);
          return;
        }
      }
      // Fallback: toString
      final s = x.toString().trim();
      if (s.isNotEmpty) out.add(s);
    }

    if (raw is List) {
      for (final x in raw) addOne(x);
    } else {
      addOne(raw);
    }

    // Normalisieren & deduplizieren
    final set = <String>{};
    for (final t in out) {
      final n = t.toLowerCase().trim();
      if (n.isNotEmpty) set.add(n);
    }
    return List.unmodifiable(set);
  }
}
