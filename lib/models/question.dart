import 'package:flutter/foundation.dart';

/// Guiding Question (nur für Leitfragen – nicht für Community-Fragen!)
/// - Stabil & nullsafe
/// - Optionales [createdAt] für Sortierung/Analytics (kein Pflichtfeld)
@immutable
class Question {
  final String id;
  final String text;
  final bool isFollowUp;

  /// Optional: Erstellzeitpunkt (kann vom Backend kommen oder lokal gesetzt werden)
  final DateTime? createdAt;

  const Question({
    required this.id,
    required this.text,
    this.isFollowUp = false,
    this.createdAt,
  });

  /// Nullsichere Deserialisierung aus JSON/Map (mit Aliassen)
  factory Question.fromJson(Map<String, dynamic> j) {
    final dt = _parseDate(
      j['createdAt'] ??
          j['created_at'] ??
          j['timestamp'] ??
          j['ts'] ??
          j['date'] ??
          j['time'],
    );

    final String rawId = (j['id'] ?? '').toString().trim();
    final String text = (j['text'] ?? '').toString();

    // isFollowUp: akzeptiere diverse Schreibweisen
    final bool isFollowUp = _readBool(
          j['isFollowUp'] ??
              j['is_follow_up'] ??
              j['followUp'] ??
              j['follow_up'],
        ) ??
        false;

    // Fallback-ID, falls leer (deterministisch & stabil)
    final String id = rawId.isEmpty ? _fallbackId(dt, text) : rawId;

    return Question(
      id: id,
      text: text,
      isFollowUp: isFollowUp,
      createdAt: dt,
    );
  }

  /// Alias
  factory Question.fromMap(Map<String, dynamic> j) => Question.fromJson(j);

  /// Serialisierung in Map (für JSON, Persistenz)
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'isFollowUp': isFollowUp,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      };

  /// Alias
  Map<String, dynamic> toMap() => toJson();

  /// Kopie mit Änderungen (immutables Pattern)
  Question copyWith({
    String? id,
    String? text,
    bool? isFollowUp,
    DateTime? createdAt,
  }) {
    return Question(
      id: id ?? this.id,
      text: text ?? this.text,
      isFollowUp: isFollowUp ?? this.isFollowUp,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Hilfreich für Sortierung: neue zuerst (fallback auf id, wenn kein Datum)
  int compareByRecency(Question other) {
    final a = createdAt;
    final b = other.createdAt;
    if (a != null && b != null) {
      final cmp = b.compareTo(a);
      if (cmp != 0) return cmp;
      // Tie-breaker: ID absteigend, damit stabil
      return other.id.compareTo(id);
    }
    if (a == null && b == null) return other.id.compareTo(id);
    return a == null ? 1 : -1; // Fragen ohne Datum ans Ende
  }

  /// Bequemer Validitätscheck
  bool get isValid => id.isNotEmpty && text.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Question &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          isFollowUp == other.isFollowUp &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(id, text, isFollowUp, createdAt);

  @override
  String toString() =>
      'Question(id: $id, followUp: $isFollowUp, createdAt: $createdAt, text: $text)';

  // ---- Helpers ----

  /// Intuitive Bool-Deserialisierung (true/false, 1/0, yes/no, ja/nein, y/n)
  static bool? _readBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return null;
    if (const ['true', '1', 'yes', 'y', 'ja', 'wahr'].contains(s)) return true;
    if (const ['false', '0', 'no', 'n', 'nein', 'falsch'].contains(s)) return false;
    return null;
  }

  /// Akzeptiert ISO-String, Sekunden/Millis/Mikrosekunden seit Epoch, DateTime und numerische Strings
  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toUtc();
    if (v is num) {
      final n = v.toInt().abs();
      if (n < 1000000000000) {
        // Sekunden
        return DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000, isUtc: true);
      } else if (n < 10000000000000000) {
        // Millisekunden
        return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
      } else {
        // Mikrosekunden
        return DateTime.fromMicrosecondsSinceEpoch(v.toInt(), isUtc: true);
      }
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      final digitsOnly = RegExp(r'^\d+$');
      if (digitsOnly.hasMatch(s)) {
        // numerischer String → wiederverwende num-Pfad
        return _parseDate(int.parse(s));
      }
      try {
        return DateTime.parse(s).toUtc();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Fallback-ID (deterministisch), falls keine ID geliefert wird
  static String _fallbackId(DateTime? created, String text) {
    final ts = (created ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    return 'q_${ts}_${text.hashCode}';
  }

  /// Leeres Objekt (z. B. für Placeholders)
  static const empty = Question(id: '', text: '', isFollowUp: false);
}
