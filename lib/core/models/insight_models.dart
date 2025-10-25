// lib/core/models/insight_models.dart
//
// Insight-Modelle (Facet, MoodPair, InsightScore)
// ------------------------------------------------
// • Kleine, immutable Value-Types ohne externe Abhängigkeiten (außer foundation)
// • Tolerante Factory-Methoden (fromWorker/fromMap), defensive Defaults
// • Bewahren strikte Backwards-Kompatibilität zu bestehenden Call-Sites
// • Utilitys (copyWith, toString) für bequemere Nutzung
//
// Kompat-Hinweise:
// - Facet.fromWorker akzeptiert String ODER Map {key|id|label|name, hits?}
// - MoodPair.fromWorker akzeptiert {mental|icon, physical|body|somatic}
// - InsightScore.as0to4() normiert heuristisch (0..1 oder 0..100 → Quartile)

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
  /// - Map → {key|id|label|name, hits?}
  factory Facet.fromWorker(dynamic raw) {
    if (raw is String) {
      final s = raw.trim();
      return Facet(key: s, label: s, hits: 1);
    }
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      String pickKey() {
        final k = (m['key'] ?? m['id'] ?? m['label'] ?? m['name'] ?? '').toString().trim();
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
        hits: (m['hits'] is num) ? (m['hits'] as num).toInt().clamp(1, 1 << 31) : 1,
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
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is Facet && o.key == key && o.label == label && o.hits == hits);

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

  MoodPair copyWith({int? mental, int? physical}) =>
      MoodPair(mental: mental ?? this.mental, physical: physical ?? this.physical);

  @override
  String toString() => 'MoodPair(mental:$mental, physical:$physical)';

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is MoodPair && o.mental == mental && o.physical == physical);

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
      final v = (val is num) ? val.toDouble() : double.tryParse(val?.toString() ?? '') ?? 0.0;
      final b = (base is num) ? base.toDouble() : double.tryParse(base?.toString() ?? '');
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
  String toString() => 'InsightScore(value:$value, baseline:${baseline ?? '∅'})';

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is InsightScore && o.value == value && o.baseline == baseline);

  @override
  int get hashCode => Object.hash(value, baseline);
}
