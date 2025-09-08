// lib/models/_legacy/gedankenbuch_entry.dart
//
// GedankenbuchEntry — Kompatibilitäts-Shim über dem neuen JournalEntry
// -------------------------------------------------------------------
// Zweck:
// • Bewahrt dein bestehendes API (text, mood, isReflection, aiQuestion ...),
//   damit Provider/Screens nicht sofort refactort werden müssen.
// • Bridge zu/von dem kanonischen Model `JournalEntry`.
// • Mood/MoodScore/Emotion bleiben lokal; als Tags kodierbar.
//
// Empfehlung:
// • Neues Modell: lib/models/journal_entry.dart (EntryKind + konsistente Felder).
// • Schrittweise Migration: erst Provider+Screens auf JournalEntry heben,
//   dann diesen Shim entfernen.

import 'dart:collection';
import 'package:flutter/material.dart';
import 'journal_entry.dart';

// ⚠️ Legacy/Übergang.
@Deprecated('Bitte auf JournalEntry migrieren. Dieser Shim bleibt vorübergehend bestehen.')
class GedankenbuchEntry {
  final String id;
  final String text;          // Journal: text; Reflexion: userAnswer
  final String mood;          // freies Label
  final DateTime date;        // UTC empfohlen
  final bool isReflection;    // true = Reflexion
  final String aiQuestion;    // Leitfrage (optional)
  final int moodScore;        // 0..4, -1 = unbekannt
  final String detectedEmotion;
  final UnmodifiableListView<String> tags;

  GedankenbuchEntry({
    String? id,
    required String text,
    required String mood,
    required DateTime date,
    required this.isReflection,
    String? aiQuestion,
    int? moodScore,
    String? detectedEmotion,
    List<String>? tags,
  })  : id = id ?? _genId(),
        text = _normalize(text),
        mood = (mood).toString().trim(),
        date = date.toUtc(),
        aiQuestion = (aiQuestion ?? '').trim(),
        moodScore = moodScore ?? -1,
        detectedEmotion = (detectedEmotion ?? '').trim(),
        tags = _normalizeTags(tags);

  // ─────────────────────────── Factories ───────────────────────────

  factory GedankenbuchEntry.journal({
    String? id,
    required String text,
    String mood = '',
    DateTime? dateUtc,
    int? moodScore,
    String? detectedEmotion,
    List<String>? tags,
  }) {
    return GedankenbuchEntry(
      id: id,
      text: text,
      mood: mood,
      date: (dateUtc ?? DateTime.now().toUtc()),
      isReflection: false,
      aiQuestion: null,
      moodScore: moodScore,
      detectedEmotion: detectedEmotion,
      tags: tags,
    );
  }

  factory GedankenbuchEntry.reflection({
    String? id,
    required String text, // Nutzer-Antwort
    String mood = '',
    DateTime? dateUtc,
    String? aiQuestion,
    int? moodScore,
    String? detectedEmotion,
    List<String>? tags,
  }) {
    return GedankenbuchEntry(
      id: id,
      text: text,
      mood: mood,
      date: (dateUtc ?? DateTime.now().toUtc()),
      isReflection: true,
      aiQuestion: aiQuestion,
      moodScore: moodScore,
      detectedEmotion: detectedEmotion,
      tags: tags,
    );
  }

  // ───────────────────── JSON (Legacy-kompatibel) ───────────────────

  factory GedankenbuchEntry.fromJson(Map<String, dynamic> json) {
    return GedankenbuchEntry(
      id: _asString(json['id']),
      text: _asString(json['text']),
      mood: _asString(json['mood']),
      date: _parseDate(json['date']),
      isReflection: json['isReflection'] == true,
      aiQuestion: _asString(json['aiQuestion']),
      moodScore: _toInt(json['moodScore']) ?? -1, // <-- FIX: _toInt vorhanden
      detectedEmotion: _asString(json['detectedEmotion']),
      tags: _asStringList(json['tags']),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'text': text,
      'mood': mood,
      'date': date.toUtc().toIso8601String(),
      'isReflection': isReflection,
      'aiQuestion': aiQuestion.isEmpty ? null : aiQuestion,
      'moodScore': moodScore >= 0 ? moodScore : null,
      'detectedEmotion': detectedEmotion.isEmpty ? null : detectedEmotion,
      'tags': tags.isEmpty ? null : tags.toList(growable: false),
    };
    map.removeWhere((_, v) => v == null);
    return map;
  }

  // ─────────────────────── Bridges (Neu ↔ Alt) ──────────────────────

  JournalEntry toJournalEntry() {
    final kind = isReflection ? EntryKind.reflection : EntryKind.journal;

    // Mood/Emotion als Tags kodieren (verlustfrei).
    final moodTags = <String>[];
    if (mood.trim().isNotEmpty) moodTags.add('mood:${mood.trim()}');
    if (moodScore >= 0) moodTags.add('moodScore:$moodScore');
    if (detectedEmotion.trim().isNotEmpty) {
      moodTags.add('emotion:${detectedEmotion.trim()}');
    }

    final combinedTags = <String>{
      ...tags,
      ...moodTags,
    }.toList(growable: false);

    return JournalEntry(
      id: id,
      kind: kind,
      createdAt: date,
      title: '', // Autotitel greift (computedTitle)
      thoughtText: !isReflection ? text : null,
      aiQuestion: isReflection ? (aiQuestion.isNotEmpty ? aiQuestion : null) : null,
      userAnswer: isReflection ? text : null,
      storyTitle: null,
      storyTeaser: null,
      tags: combinedTags,
      hidden: false,
      sourceRef: null,
    );
  }

  static GedankenbuchEntry fromJournalEntry(JournalEntry e) {
    final isRefl = e.kind == EntryKind.reflection;
    final legacyText = isRefl
        ? (e.userAnswer?.trim().isNotEmpty == true ? e.userAnswer!.trim() : (e.thoughtText ?? ''))
        : (e.thoughtText ?? e.userAnswer ?? '');

    String mood = '';
    int moodScore = -1;
    String emotion = '';
    for (final t in e.tags) {
      final s = t.trim();
      if (s.startsWith('mood:')) mood = s.substring(5);
      if (s.startsWith('moodScore:')) {
        final n = int.tryParse(s.substring(10));
        if (n != null) moodScore = n;
      }
      if (s.startsWith('emotion:')) emotion = s.substring(8);
    }

    return GedankenbuchEntry(
      id: e.id,
      text: legacyText,
      mood: mood,
      date: e.createdAt.toUtc(),
      isReflection: isRefl,
      aiQuestion: isRefl ? (e.aiQuestion ?? '') : '',
      moodScore: moodScore,
      detectedEmotion: emotion,
      tags: e.tags,
    );
  }

  // ─────────────── Derived / UI Helper (legacy-kompatibel) ───────────────

  String get displayMoodLabel {
    final m = mood.trim();
    if (m.isNotEmpty) return m;
    switch (moodScore) {
      case 0:
        return 'Tief';
      case 1:
        return 'Niedrig';
      case 2:
        return 'Neutral';
      case 3:
        return 'Klar';
      case 4:
        return 'Erfüllt';
      default:
        return 'Unbekannt';
    }
  }

  String get moodEmoji {
    switch (moodScore) {
      case 0:
        return '🌧️';
      case 1:
        return '🌫️';
      case 2:
        return '⛅';
      case 3:
        return '🌤️';
      case 4:
        return '🌞';
      default:
        final l = displayMoodLabel.toLowerCase();
        if (l.contains('müde') || l.contains('traurig') || l.contains('tief')) return '🌧️';
        if (l.contains('klar') || l.contains('ruhig') || l.contains('gut')) return '🌤️';
        return '📝';
    }
  }

  Color get moodColor {
    switch (moodScore) {
      case 0:
        return const Color(0xFFB2B2B2); // Grau – Tief
      case 1:
        return const Color(0xFFEADFAF); // Sun Haze – Niedrig
      case 2:
        return const Color(0xFFE3D28A); // Golden Mist – Neutral
      case 3:
        return const Color(0xFFA5CBA1); // Soft Sage – Klar
      case 4:
        return const Color(0xFF2F5F49); // Deep Sage – Erfüllt
      default:
        return Colors.grey;
    }
  }

  String get dateShort =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  String get timeShort =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  String get prettyDate {
    final now = DateTime.now().toUtc();
    final d = date;
    final isToday = now.year == d.year && now.month == d.month && now.day == d.day;
    if (isToday) return 'Heute, $timeShort';
    final y = now.subtract(const Duration(days: 1));
    final isYesterday = y.year == d.year && y.month == d.month && y.day == d.day;
    if (isYesterday) return 'Gestern, $timeShort';
    return '$dateShort, $timeShort';
  }

  String preview([int max = 160]) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= max) return t;
    return t.substring(0, max).trimRight() + '…';
  }

  int compareTo(GedankenbuchEntry other) => other.date.compareTo(date);

  GedankenbuchEntry copyWith({
    String? id,
    String? text,
    String? mood,
    DateTime? date,
    bool? isReflection,
    String? aiQuestion,
    int? moodScore,
    String? detectedEmotion,
    List<String>? tags,
  }) {
    return GedankenbuchEntry(
      id: id ?? this.id,
      text: text ?? this.text,
      mood: mood ?? this.mood,
      date: (date ?? this.date),
      isReflection: isReflection ?? this.isReflection,
      aiQuestion: (aiQuestion ?? this.aiQuestion),
      moodScore: moodScore ?? this.moodScore,
      detectedEmotion: detectedEmotion ?? this.detectedEmotion,
      tags: tags ?? this.tags.toList(),
    );
  }

  @override
  String toString() =>
      'GedankenbuchEntry{id:$id, isReflection:$isReflection, mood:$mood/$moodScore, date:$date, text:${preview(40)}}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is GedankenbuchEntry && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

// ───────────────────────────── Helpers ─────────────────────────────

String _normalize(String v) => (v).toString().trim();

UnmodifiableListView<String> _normalizeTags(List<String>? raw) {
  if (raw == null) return UnmodifiableListView<String>(const []);
  final cleaned = <String>{};
  for (final e in raw) {
    final t = (e).toString().trim();
    if (t.isNotEmpty) cleaned.add(t);
    if (cleaned.length >= 8) break;
  }
  return UnmodifiableListView<String>(cleaned.toList(growable: false));
}

String _asString(dynamic v) {
  if (v == null) return '';
  return v.toString();
}

int? _toInt(dynamic v) { // <-- NEU
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  final s = v.toString().trim();
  return int.tryParse(s);
}

List<String> _asStringList(dynamic v) {
  if (v == null) return const <String>[];
  if (v is List) {
    return v
        .map((e) => e?.toString() ?? '')
        .where((e) => e.trim().isNotEmpty)
        .take(8)
        .toList(growable: false);
  }
  return const <String>[];
}

DateTime _parseDate(dynamic v) {
  if (v == null) return DateTime.now().toUtc();
  if (v is DateTime) return v.toUtc();
  if (v is num) {
    final n = v.toInt();
    final isSeconds = n.abs() < 1000000000000;
    final ms = isSeconds ? n * 1000 : n;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  final s = v.toString().trim();
  if (s.isEmpty) return DateTime.now().toUtc();
  final asNum = int.tryParse(s);
  if (asNum != null) return _parseDate(asNum);
  final parsed = DateTime.tryParse(s);
  return (parsed ?? DateTime.now()).toUtc();
}

String _genId() => 'gbe_${DateTime.now().microsecondsSinceEpoch}';
