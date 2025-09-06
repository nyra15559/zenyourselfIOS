// lib/models/community_question.dart

import 'package:flutter/foundation.dart';

/// CommunityQuestion
/// ------------------
/// Separates Modell für Community-Fragen (unabhängig von Leitfragen).
/// - Stabil & nullsafe
/// - Robustes JSON (tolerant bei Typen)
/// - copyWith / Equality / Hash
/// - Hilfsfunktionen für Sortierung (Votes, Recency, Hotness)
@immutable
class CommunityQuestion {
  /// Lokale/Server-ID (String, kann UUID o.ä. sein)
  final String id;

  /// Sichtbarer Fragetext
  final String text;

  /// Upvotes (>= 0)
  final int votes;

  /// Erstellzeitpunkt (UTC empfohlen)
  final DateTime createdAt;

  /// Optional: Pseudonym/Autor-Label (anonym möglich)
  final String? authorAlias;

  /// Moderations-Flags (optional)
  final bool isArchived;
  final bool isFlagged;

  const CommunityQuestion({
    required this.id,
    required this.text,
    required this.votes,
    required this.createdAt,
    this.authorAlias,
    this.isArchived = false,
    this.isFlagged = false,
  }) : assert(votes >= 0, 'votes must be >= 0');

  /// Bequeme Factory für lokale Erstellung (ID wird generiert)
  factory CommunityQuestion.create({
    required String text,
    String? authorAlias,
    DateTime? createdAt,
  }) {
    final now = DateTime.now().toUtc();
    return CommunityQuestion(
      id: _genLocalId(now),
      text: text.trim(),
      votes: 0,
      createdAt: createdAt?.toUtc() ?? now,
      authorAlias: authorAlias?.trim().isEmpty == true ? null : authorAlias?.trim(),
    );
  }

  /// Nullsichere Deserialisierung
  factory CommunityQuestion.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString();
    final text = (j['text'] ?? '').toString().trim();
    final votes = _toInt(j['votes']) ?? 0;
    final createdAt = _parseDate(j['createdAt']) ?? DateTime.now().toUtc();

    return CommunityQuestion(
      id: id.isEmpty ? _genLocalId(createdAt) : id,
      text: text,
      votes: votes < 0 ? 0 : votes,
      createdAt: createdAt,
      authorAlias: (j['authorAlias'] as String?)?.trim().isEmpty == true
          ? null
          : (j['authorAlias'] as String?),
      isArchived: _toBool(j['isArchived']),
      isFlagged: _toBool(j['isFlagged']),
    );
  }

  /// Serialisierung
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'votes': votes,
        'createdAt': createdAt.toIso8601String(),
        if (authorAlias != null) 'authorAlias': authorAlias,
        if (isArchived) 'isArchived': true,
        if (isFlagged) 'isFlagged': true,
      };

  /// Immutables Update
  CommunityQuestion copyWith({
    String? id,
    String? text,
    int? votes,
    DateTime? createdAt,
    String? authorAlias,
    bool? isArchived,
    bool? isFlagged,
  }) {
    return CommunityQuestion(
      id: id ?? this.id,
      text: (text ?? this.text).trim(),
      votes: (votes ?? this.votes).clamp(0, 1 << 31),
      createdAt: (createdAt ?? this.createdAt).toUtc(),
      authorAlias: authorAlias == null ? this.authorAlias : (authorAlias.trim().isEmpty ? null : authorAlias.trim()),
      isArchived: isArchived ?? this.isArchived,
      isFlagged: isFlagged ?? this.isFlagged,
    );
  }

  /// Sortierung: Neueste zuerst
  int compareByRecency(CommunityQuestion other) => other.createdAt.compareTo(createdAt);

  /// Sortierung: Meiste Votes zuerst
  int compareByVotes(CommunityQuestion other) => other.votes.compareTo(votes);

  /// „Hotness“: Votes abzüglich leichter Zeitabfall (Stunden)
  /// Größerer Wert = „heißer“. Nutze für Trending-Listen.
  double hotScore({DateTime? now}) {
    final n = (now ?? DateTime.now().toUtc());
    final ageHours = n.difference(createdAt).inSeconds / 3600.0;
    // Abfallfaktor: 0.08 pro Stunde – fein abstimmbar
    return votes - 0.08 * ageHours;
  }

  bool get isValid => text.isNotEmpty;

  @override
  String toString() => 'CommunityQuestion(id: $id, votes: $votes, text: $text)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommunityQuestion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          votes == other.votes &&
          createdAt == other.createdAt &&
          authorAlias == other.authorAlias &&
          isArchived == other.isArchived &&
          isFlagged == other.isFlagged;

  @override
  int get hashCode => Object.hash(id, text, votes, createdAt, authorAlias, isArchived, isFlagged);

  // ---- Helpers ----

  static String _genLocalId(DateTime t) =>
      'cq_${t.microsecondsSinceEpoch}';

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
    }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  /// Akzeptiert ISO-String, Sekunden/Millis seit Epoch, DateTime
  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toUtc();
    if (v is int) {
      // Heuristik: große Werte = ms, kleine = s
      final isMillis = v > 2000000000; // ~2033 in Sekunden
      final epoch = isMillis
          ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true);
      return epoch;
    }
    if (v is String && v.trim().isNotEmpty) {
      try {
        return DateTime.parse(v).toUtc();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Leeres Objekt (nur für Platzhalter)
  static CommunityQuestion empty() => CommunityQuestion(
        id: _genLocalId(DateTime.now().toUtc()),
        text: '',
        votes: 0,
        createdAt: DateTime.now().toUtc(),
      );
}
