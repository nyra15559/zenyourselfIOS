// lib/core/models/insight_models.dart
import 'package:flutter/foundation.dart';

@immutable
class Facet {
  final String key;   // technischer Schlüssel
  final String label; // Anzeige
  final int hits;     // optional: Häufigkeit/Gewicht

  const Facet({required this.key, required this.label, this.hits = 1});

  factory Facet.fromWorker(dynamic raw) {
    if (raw is String) return Facet(key: raw, label: raw, hits: 1);
    if (raw is Map) {
      final k = (raw['key'] ?? raw['id'] ?? raw['label'] ?? '').toString();
      final l = (raw['label'] ?? k).toString();
      final h = (raw['hits'] is num) ? (raw['hits'] as num).toInt() : 1;
      return Facet(key: k.isNotEmpty ? k : l, label: l, hits: h);
    }
    final s = raw?.toString() ?? '';
    return Facet(key: s, label: s, hits: 1);
  }

  factory Facet.fromMap(Map<String, dynamic> m) => Facet(
        key: (m['key'] ?? '').toString(),
        label: (m['label'] ?? m['key'] ?? '').toString(),
        hits: (m['hits'] is num) ? (m['hits'] as num).toInt() : 1,
      );

  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        'hits': hits,
      };

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is Facet && o.key == key && o.label == label && o.hits == hits);

  @override
  int get hashCode => Object.hash(key, label, hits);
}

@immutable
class MoodPair {
  final int mental;   // 0..4
  final int physical; // 0..4
  const MoodPair({required this.mental, required this.physical});

  factory MoodPair.fromWorker(Map<String, dynamic> m) {
    int coerce(dynamic x) => (x is num) ? x.clamp(0, 4).toInt() : 2;
    return MoodPair(
      mental: coerce(m['mental'] ?? m['icon']),
      physical: coerce(m['physical'] ?? m['body'] ?? m['somatic']),
    );
  }

  factory MoodPair.fromMap(Map<String, dynamic> m) => MoodPair(
        mental: (m['mental'] is num) ? (m['mental'] as num).clamp(0, 4).toInt() : 2,
        physical: (m['physical'] is num) ? (m['physical'] as num).clamp(0, 4).toInt() : 2,
      );

  Map<String, dynamic> toMap() => {
        'mental': mental,
        'physical': physical,
      };

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is MoodPair && o.mental == mental && o.physical == physical);

  @override
  int get hashCode => Object.hash(mental, physical);
}

@immutable
class InsightScore {
  final double value;    // 0..1 oder 0..100 — wir normieren nicht hart
  final double? baseline;
  const InsightScore(this.value, {this.baseline});

  int as0to4() {
    final v = value;
    if (v <= 0) return 0;
    if (v < .25) return 1;
    if (v < .5)  return 2;
    if (v < .75) return 3;
    return 4;
  }

  double delta() => (baseline == null) ? 0 : (value - baseline!);

  factory InsightScore.fromMap(Map<String, dynamic> m) => InsightScore(
        (m['value'] is num) ? (m['value'] as num).toDouble() : 0.0,
        baseline: (m['baseline'] is num) ? (m['baseline'] as num).toDouble() : null,
      );

  Map<String, dynamic> toMap() => {
        'value': value,
        'baseline': baseline,
      };

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is InsightScore && o.value == value && o.baseline == baseline);

  @override
  int get hashCode => Object.hash(value, baseline);
}
