// lib/models/panda_mood.dart
//
// PandaMood model — Oxford-Zen v1.2
// - Stabiles JSON-Loading mit In-Memory-Cache
// - Sortierung nach id (falls im JSON unsortiert)
// - Klare Felder und Semantik

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class PandaMood {
  final int id;
  final String key;
  final String labelDe;
  final double valence; // -1..+1
  final double energy;  // 0..1
  final String asset;   // assets/panda_moods/...

  const PandaMood({
    required this.id,
    required this.key,
    required this.labelDe,
    required this.valence,
    required this.energy,
    required this.asset,
  });

  factory PandaMood.fromJson(Map<String, dynamic> j) => PandaMood(
        id: j['id'] as int,
        key: j['key'] as String,
        labelDe: j['label_de'] as String,
        valence: (j['valence'] as num).toDouble(),
        energy: (j['energy'] as num).toDouble(),
        asset: j['asset'] as String,
      );

  static List<PandaMood>? _cache;

  /// Lädt alle Moods aus assets/panda_moods/moods.json (mit Cache).
  static Future<List<PandaMood>> loadAll() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/panda_moods/moods.json');
    final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
    final moods = list.map(PandaMood.fromJson).toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    _cache = moods;
    return moods;
  }

  static Future<PandaMood?> byKey(String key) async {
    final all = await loadAll();
    try {
      return all.firstWhere((m) => m.key == key);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'PandaMood($id,$key,$labelDe)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PandaMood && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
