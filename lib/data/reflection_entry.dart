// lib/data/reflection_entry.dart
//
// ReflectionEntry — v5-kompatibles Datenmodell (rückwärtskompatibel)
// ------------------------------------------------------------------
// • Bestehende Felder bleiben erhalten (timestamp, content, moodScore, …)
// • NEU (optional): analysis, answer, challenge, links, inputMeta,
//   helperSuggestion (sanfter 0–1-Satz unter Leitfrage).
// • toJsonV5() exportiert den v5-Union-Shape für JournalEntry:
//   { type:"reflection", input, analysis, answer, challenge, mood, links, …, reflection }
//
// Robustheit & Kompat:
// • Null-safe, Normalisierung von Text/Tags, Mood clamped (0–4)
// • Tolerante JSON-Parser (Alias-Felder, gemischte Formate)
// • Zeit-Parsing: diverse Formate (ISO, Sek./Millis/Mikros) → **lokale** Zeit
//
// Zusätze in dieser Überarbeitung:
// • fromJson: liest auch { mood:{icon,note} } und reflection.helper_suggestion
// • InputMeta.fromMaybe: akzeptiert duration_sec | durationSec | duration
// • Answer.fromMaybe: akzeptiert content | text
// • MiniChallenge.fromMaybe: akzeptiert duration_sec | durationSec
// • Analysis.fromMaybe: mappt risk=true → risk_level:"high"
// • ReflectionLinks.fromMaybe: akzeptiert story_id | storyId

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../shared/zen_style.dart'; // ZenColors

class ReflectionEntry {
  // ===== Kern (bestehend) =====================================================
  final String id;
  final DateTime timestamp;
  final String content;
  final String? moodDayTag;
  final int? moodScore; // 0..4
  final String? category;
  final List<String> tags;
  final String? audioPath;
  final String? aiSummary;
  final String? source;

  // ===== NEU: v5-Felder (optional) ============================================
  final InputMeta? input; // mode/text/duration
  final Analysis? analysis; // Spiegelung + 1 Frage + Risk + SORC + Levers
  final Answer? answer; // Antwort des Nutzers (voice/text)
  final MiniChallenge? challenge; // Micro-Challenge ≤ 2 Min
  final ReflectionLinks? links; // z. B. storyId
  final String? moodNote; // Freitext zum Mood (separat von score)
  /// Sanfter 0–1-Satz direkt unter der Leitfrage (aus Worker/Turn)
  final String? helperSuggestion;

  ReflectionEntry({
    String? id,
    required this.timestamp,
    required String content,
    this.moodDayTag,
    int? moodScore,
    this.category,
    List<String>? tags,
    this.audioPath,
    this.aiSummary,
    this.source,
    this.input,
    this.analysis,
    this.answer,
    this.challenge,
    this.links,
    this.moodNote,
    this.helperSuggestion,
  })  : id = id ?? _makeId(timestamp, content),
        content = _sanitizeContent(content),
        moodScore = _clampMood(moodScore),
        tags = _normalizeTags(tags);

  // ===== Fabriken =============================================================

  /// JSON → Model (tolerant bei Typen & Alias-Feldern)
  factory ReflectionEntry.fromJson(Map<String, dynamic> json) {
    final ts = _parseDate(
      json['timestamp'] ??
          json['createdAt'] ??
          json['created_at'] ??
          json['ts'] ??
          json['time'] ??
          json['date'],
    );

    final content =
        _sanitizeContent((json['content'] ?? json['text'] ?? '').toString());

    final rawId = (json['id'] ?? '').toString().trim();
    final id = rawId.isEmpty ? _makeId(ts, content) : rawId;

    // v5-kompatible Blöcke (optional)
    final input = InputMeta.fromMaybe(
      json['input'],
      fallbackContent: content,
      audioPath: json['audioPath'] ?? json['audio_path'],
    );
    final analysis = Analysis.fromMaybe(json['analysis']);
    final answer = Answer.fromMaybe(json['answer']);
    final challenge = MiniChallenge.fromMaybe(json['challenge']);
    final links = ReflectionLinks.fromMaybe(json['links']);

    // helperSuggestion tolerant einlesen (camelCase & snake_case + reflection-block)
    String? helperSuggestion = _asTrimmedOrNull(
      json['helperSuggestion'] ?? json['helper_suggestion'],
    );
    if (helperSuggestion == null && json['reflection'] is Map) {
      final ref = Map<String, dynamic>.from(json['reflection'] as Map);
      helperSuggestion = _asTrimmedOrNull(
        ref['helper_suggestion'] ?? ref['helperSuggestion'],
      );
    }

    // Mood-Block lesen (optional): { mood: { icon, note } }
    int? moodScore =
        _clampMood(_toInt(json['moodScore'] ?? json['mood_score']));
    String? moodNote = _asTrimmedOrNull(
        json['moodNote'] ?? json['mood_note'] ?? json['moodComment']);
    final moodObj = json['mood'];
    if (moodObj is Map) {
      final mm = Map<String, dynamic>.from(moodObj);
      moodScore ??= _clampMood(_toInt(mm['icon'] ?? mm['score'] ?? mm['mood']));
      moodNote ??= _asTrimmedOrNull(mm['note'] ?? mm['text'] ?? mm['comment']);
    }

    return ReflectionEntry(
      id: id,
      timestamp: ts,
      content: content,
      moodDayTag: (json['moodDayTag'] ?? json['mood_day_tag']) as String?,
      moodScore: moodScore,
      category: _asTrimmedOrNull(json['category']),
      tags: _coerceTags(json['tags']),
      audioPath: _asTrimmedOrNull(json['audioPath'] ?? json['audio_path']),
      aiSummary: _asTrimmedOrNull(json['aiSummary'] ?? json['ai_summary']),
      source: _asTrimmedOrNull(json['source']),
      input: input,
      analysis: analysis,
      answer: answer,
      challenge: challenge,
      links: links,
      moodNote: moodNote,
      helperSuggestion: helperSuggestion,
    );
  }

  /// Alias
  factory ReflectionEntry.fromMap(Map<String, dynamic> map) =>
      ReflectionEntry.fromJson(map);

  // ===== Serialisierung =======================================================

  /// Model → JSON (klassisch + neue optionale v5-Blöcke)
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'content': content,
      'moodDayTag': moodDayTag,
      'moodScore': moodScore,
      'category': category,
      'tags': tags,
      'audioPath': audioPath,
      'aiSummary': aiSummary,
      'source': source,
      if (input != null) 'input': input!.toJson(),
      if (analysis != null) 'analysis': analysis!.toJson(),
      if (answer != null) 'answer': answer!.toJson(),
      if (challenge != null) 'challenge': challenge!.toJson(),
      if (links != null) 'links': links!.toJson(),
      if (moodNote != null) 'moodNote': moodNote,
      if ((helperSuggestion ?? '').trim().isNotEmpty)
        'helperSuggestion': helperSuggestion!.trim(),
    };
    map.removeWhere((_, v) => v == null);
    return map;
  }

  /// Export im neuen v5-Union-Shape eines JournalEntry (type:"reflection")
  Map<String, dynamic> toJsonV5() {
    final mode = (input?.mode ??
            (audioPath != null && audioPath!.trim().isNotEmpty
                ? 'voice'
                : 'text'))
        .toString();

    final moodObj =
        (moodScore == null && (moodNote == null || moodNote!.isEmpty))
            ? null
            : {
                if (moodScore != null) 'icon': moodScore,
                if (moodNote != null && moodNote!.isNotEmpty) 'note': moodNote,
              };

    final map = <String, dynamic>{
      'id': id,
      'ts': timestamp.toIso8601String(),
      'type': 'reflection',
      'input': {
        'mode': mode,
        'content': content, // = erster Gedanke
        if (input?.durationSec != null) 'duration_sec': input!.durationSec,
      },
      if (analysis != null) 'analysis': analysis!.toJson(),
      if (answer != null) 'answer': answer!.toJson(),
      if (challenge != null) 'challenge': challenge!.toJson(),
      if (moodObj != null) 'mood': moodObj,
      if (links != null) 'links': links!.toJson(),
    };

    // NEU: Reflection-Block (thought + Step aus analysis/answer + risk + helper_suggestion)
    final refl = _toReflectionBlock();
    if (refl.isNotEmpty) {
      map['reflection'] = refl;
    }

    return map;
  }

  /// Reflection-Block erzeugen (thought + Step aus analysis/answer + risk + helper_suggestion)
  Map<String, dynamic> _toReflectionBlock() {
    final thought = content.trim().isEmpty ? null : content.trim();

    final hasAny = (analysis?.mirror?.trim().isNotEmpty == true) ||
        (analysis?.question?.trim().isNotEmpty == true) ||
        (answer?.content?.trim().isNotEmpty == true);

    final steps = <Map<String, dynamic>>[];
    if (hasAny) {
      final m = (analysis?.mirror ?? '').trim();
      final q = (analysis?.question ?? '').trim();
      final a = (answer?.content ?? '').trim();
      final step = <String, dynamic>{
        if (m.isNotEmpty) 'mirror': m,
        if (q.isNotEmpty) 'question': q,
        if (a.isNotEmpty) 'answer': a,
      };
      if (step.isNotEmpty) steps.add(step);
    }

    final String rl = (analysis?.riskLevel ?? '').toLowerCase().trim();
    final bool? risk = rl.isEmpty ? null : (rl == 'high');

    final out = <String, dynamic>{
      if (thought != null) 'thought': thought,
      if (steps.isNotEmpty) 'steps': steps,
      if (risk != null) 'risk': risk,
      if ((helperSuggestion ?? '').trim().isNotEmpty)
        'helper_suggestion': helperSuggestion!.trim(),
    };
    return out;
  }

  // ===== UX-Helper ============================================================

  /// Kurzes Label (erste Zeile des Inhalts; Fallback: Kategorie/„Reflexion“)
  String get label {
    final trimmed = content.trim();
    if (trimmed.isNotEmpty) {
      final singleLine = trimmed.replaceAll(RegExp(r'\s+'), ' ');
      return singleLine.length > 44
          ? '${singleLine.substring(0, 41)}…'
          : singleLine;
    }
    return category ?? 'Reflexion';
  }

  /// YYYY-MM-DD – nützlich für Gruppierungen/Joins
  String get dayTag {
    final ts = timestamp.toLocal();
    return '${ts.year.toString().padLeft(4, '0')}-'
        '${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')}';
  }

  /// dd.MM.yyyy
  String get dateFormatted {
    final ts = timestamp.toLocal();
    return '${ts.day.toString().padLeft(2, '0')}.'
        '${ts.month.toString().padLeft(2, '0')}.'
        '${ts.year}';
  }

  /// HH:mm
  String get timeFormatted {
    final ts = timestamp.toLocal();
    return '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}';
  }

  /// „Heute, HH:mm“ / „Gestern, HH:mm“ / „dd.MM.yyyy, HH:mm“
  String get timestampFormatted {
    final now = DateTime.now();
    final ts = timestamp.toLocal();
    final isSameDay =
        now.year == ts.year && now.month == ts.month && now.day == ts.day;
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == ts.year &&
        yesterday.month == ts.month &&
        yesterday.day == ts.day;
    if (isSameDay) return 'Heute, $timeFormatted';
    if (isYesterday) return 'Gestern, $timeFormatted';
    return '$dateFormatted, $timeFormatted';
  }

  /// Zen MoodColor für Timeline/Heatmaps (nutzt Compat-Colors)
  Color get moodColor {
    if (moodScore == null) return ZenColors.cloud;
    switch (moodScore!) {
      case 0:
        return ZenColors.cherry;
      case 1:
        return ZenColors.gold;
      case 2:
        return ZenColors.bamboo;
      case 3:
        return ZenColors.jadeMid;
      case 4:
        return ZenColors.jade;
      default:
        return ZenColors.cloud;
    }
  }

  /// Emoji passend zur Stimmung
  String get moodEmoji {
    if (moodScore == null) return '❓';
    switch (moodScore!) {
      case 0:
        return '🌧️';
      case 1:
        return '🌥️';
      case 2:
        return '⛅';
      case 3:
        return '🌤️';
      case 4:
        return '☀️';
      default:
        return '❓';
    }
  }

  /// „Vollständige Runde“ (Analyse+Frage vorhanden, Antwort vorhanden)
  bool get isCompleteRound =>
      (analysis?.question != null && analysis!.question!.trim().isNotEmpty) &&
      (answer?.content != null && answer!.content!.trim().isNotEmpty);

  /// Kleiner Vorschau-Snippet (z. B. für Listen/Chips)
  String preview([int maxChars = 120]) {
    final t = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars - 1)}…';
  }

  /// Tag-Helper
  bool hasTag(String tag) => tags.contains(tag);

  // ===== Mutationen / Equality ===============================================

  ReflectionEntry copyWith({
    String? id,
    DateTime? timestamp,
    String? content,
    String? moodDayTag,
    int? moodScore,
    String? category,
    List<String>? tags,
    String? audioPath,
    String? aiSummary,
    String? source,
    InputMeta? input,
    Analysis? analysis,
    Answer? answer,
    MiniChallenge? challenge,
    ReflectionLinks? links,
    String? moodNote,
    String? helperSuggestion,
  }) {
    return ReflectionEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      content: content != null ? _sanitizeContent(content) : this.content,
      moodDayTag: moodDayTag ?? this.moodDayTag,
      moodScore: _clampMood(moodScore ?? this.moodScore),
      category: category ?? this.category,
      tags: _normalizeTags(tags ?? this.tags),
      audioPath: audioPath ?? this.audioPath,
      aiSummary: aiSummary ?? this.aiSummary,
      source: source ?? this.source,
      input: input ?? this.input,
      analysis: analysis ?? this.analysis,
      answer: answer ?? this.answer,
      challenge: challenge ?? this.challenge,
      links: links ?? this.links,
      moodNote: moodNote ?? this.moodNote,
      helperSuggestion: helperSuggestion ?? this.helperSuggestion,
    );
  }

  int compareTo(ReflectionEntry other) => other.timestamp.compareTo(timestamp);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReflectionEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          timestamp == other.timestamp &&
          content == other.content &&
          moodDayTag == other.moodDayTag &&
          moodScore == other.moodScore &&
          category == other.category &&
          _listEquals(tags, other.tags) &&
          audioPath == other.audioPath &&
          aiSummary == other.aiSummary &&
          source == other.source &&
          input == other.input &&
          analysis == other.analysis &&
          answer == other.answer &&
          challenge == other.challenge &&
          links == other.links &&
          moodNote == other.moodNote &&
          helperSuggestion == other.helperSuggestion;

  @override
  int get hashCode => Object.hash(
        id,
        timestamp,
        content,
        moodDayTag,
        moodScore,
        category,
        Object.hashAll(tags),
        audioPath,
        aiSummary,
        source,
        input,
        analysis,
        answer,
        challenge,
        links,
        moodNote,
        helperSuggestion,
      );

  // ===== Intern: Normalisierung ==============================================

  static String _makeId(DateTime ts, String content) =>
      '${ts.millisecondsSinceEpoch}_${content.hashCode}';

  static String _sanitizeContent(String v) {
    final t = v.trim().replaceAll(RegExp(r'[ \t]+'), ' ');
    return t.isEmpty ? '—' : t;
  }

  static int? _clampMood(int? m) {
    if (m == null) return null;
    if (m < 0) return 0;
    if (m > 4) return 4;
    return m;
  }

  static List<String> _normalizeTags(List<String>? raw) {
    if (raw == null) return const [];
    final out = <String>[];
    for (final r in raw) {
      final t = r.toString().trim();
      if (t.isEmpty) continue;
      final clipped = t.length > 24 ? '${t.substring(0, 23)}…' : t;
      if (!out.contains(clipped)) out.add(clipped);
      if (out.length >= 8) break;
    }
    return List.unmodifiable(out);
  }

  /// Wandelt verschiedene Zeitrepräsentationen in **lokale** Zeit um.
  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v.toLocal();

    // numerisch (Sekunden / Millisekunden / Mikrosekunden)
    if (v is num) {
      final n = v.toInt().abs();
      if (n < 1000000000000) {
        // Sekunden
        return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true)
            .toLocal();
      } else if (n < 10000000000000000) {
        // Millisekunden
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
      } else {
        // Mikrosekunden
        return DateTime.fromMicrosecondsSinceEpoch(n, isUtc: true).toLocal();
      }
    }

    // numerischer String?
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return DateTime.now();
      if (RegExp(r'^\d+$').hasMatch(s)) {
        return _parseDate(int.parse(s));
      }
      // ISO → DateTime.parse (kann UTC oder lokal sein), dann nach lokal
      final parsed = DateTime.tryParse(s);
      return (parsed ?? DateTime.now()).toLocal();
    }

    return DateTime.now();
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  static String? _asTrimmedOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static List<String> _coerceTags(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v.map((e) => e?.toString() ?? '').toList();
    if (v is String && v.trim().isNotEmpty) {
      // CSV oder ein einzelner Tag
      final parts =
          v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      return parts;
    }
    return const [];
  }

  static bool _listEquals(List? a, List? b) {
    if (a == null || b == null) return identical(a, b);
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ============================================================================
// v5-Untermodelle (leichtgewichtig, ohne externe Abhängigkeiten)
// ============================================================================

class InputMeta {
  /// 'voice' | 'text' | 'import' | …
  final String? mode;
  final int? durationSec;

  const InputMeta({this.mode, this.durationSec});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      if (mode != null) 'mode': mode,
      if (durationSec != null) 'duration_sec': durationSec,
    };
    return map;
  }

  static InputMeta? fromMaybe(dynamic v,
      {String? fallbackContent, dynamic audioPath}) {
    if (v == null && (fallbackContent == null && audioPath == null))
      return null;
    if (v is Map<String, dynamic>) {
      return InputMeta(
        mode: ReflectionEntry._asTrimmedOrNull(v['mode']),
        durationSec: ReflectionEntry._toInt(
          v['duration_sec'] ?? v['durationSec'] ?? v['duration'],
        ),
      );
    }
    // Fallback-Heuristik: audioPath → voice, sonst text
    final hasAudio = (audioPath?.toString().trim().isNotEmpty ?? false);
    return InputMeta(mode: hasAudio ? 'voice' : 'text', durationSec: null);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InputMeta &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          durationSec == other.durationSec;

  @override
  int get hashCode => Object.hash(mode, durationSec);
}

class Analysis {
  final Sorc? sorc;
  final List<String> levers; // z. B. ["Gedanken","Gefühle"]
  final String? mirror;
  final String? question; // ≤ 30 Wörter
  final String? riskLevel; // none | mild | high

  const Analysis({
    this.sorc,
    this.levers = const [],
    this.mirror,
    this.question,
    this.riskLevel,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      if (sorc != null) 'sorc': sorc!.toJson(),
      if (levers.isNotEmpty) 'levers': levers,
      if (mirror != null) 'mirror': mirror,
      if (question != null) 'question': question,
      if (riskLevel != null) 'risk_level': riskLevel,
    };
    return map;
  }

  static Analysis? fromMaybe(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) {
      // risk (bool) → risk_level
      final riskLevel = ReflectionEntry._asTrimmedOrNull(
        v['risk_level'] ?? (v['risk'] == true ? 'high' : null),
      );
      return Analysis(
        sorc: Sorc.fromMaybe(v['sorc']),
        levers: (v['levers'] is List)
            ? (v['levers'] as List).map((e) => e?.toString() ?? '').toList()
            : const [],
        mirror: ReflectionEntry._asTrimmedOrNull(v['mirror']),
        question: ReflectionEntry._asTrimmedOrNull(v['question']),
        riskLevel: riskLevel,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Analysis &&
          runtimeType == other.runtimeType &&
          sorc == other.sorc &&
          ReflectionEntry._listEquals(levers, other.levers) &&
          mirror == other.mirror &&
          question == other.question &&
          riskLevel == other.riskLevel;

  @override
  int get hashCode =>
      Object.hash(sorc, Object.hashAll(levers), mirror, question, riskLevel);
}

class Sorc {
  final String? stimulus;
  final String? organism;
  final String? response;
  final String? consequence;

  const Sorc({this.stimulus, this.organism, this.response, this.consequence});

  Map<String, dynamic> toJson() => {
        if (stimulus != null) 'stimulus': stimulus,
        if (organism != null) 'organism': organism,
        if (response != null) 'response': response,
        if (consequence != null) 'consequence': consequence,
      };

  static Sorc? fromMaybe(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) {
      return Sorc(
        stimulus: ReflectionEntry._asTrimmedOrNull(v['stimulus']),
        organism: ReflectionEntry._asTrimmedOrNull(v['organism']),
        response: ReflectionEntry._asTrimmedOrNull(v['response']),
        consequence: ReflectionEntry._asTrimmedOrNull(v['consequence']),
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Sorc &&
          runtimeType == other.runtimeType &&
          stimulus == other.stimulus &&
          organism == other.organism &&
          response == other.response &&
          consequence == other.consequence;

  @override
  int get hashCode => Object.hash(stimulus, organism, response, consequence);
}

class Answer {
  final String? content;
  final String? mode; // 'voice' | 'text'

  const Answer({this.content, this.mode});

  Map<String, dynamic> toJson() => {
        if (content != null) 'content': content,
        if (mode != null) 'mode': mode,
      };

  static Answer? fromMaybe(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) {
      return Answer(
        content: ReflectionEntry._asTrimmedOrNull(v['content'] ?? v['text']),
        mode: ReflectionEntry._asTrimmedOrNull(v['mode']),
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Answer &&
          runtimeType == other.runtimeType &&
          content == other.content &&
          mode == other.mode;

  @override
  int get hashCode => Object.hash(content, mode);
}

class MiniChallenge {
  final String? id;
  final String? title; // z. B. "90 Sek Pause"
  final String? kind; // "micro"
  final int? durationSec; // ≤ 120
  final String? status; // offered | accepted | done

  const MiniChallenge({
    this.id,
    this.title,
    this.kind,
    this.durationSec,
    this.status,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (title != null) 'title': title,
        if (kind != null) 'kind': kind,
        if (durationSec != null) 'duration_sec': durationSec,
        if (status != null) 'status': status,
      };

  static MiniChallenge? fromMaybe(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) {
      return MiniChallenge(
        id: ReflectionEntry._asTrimmedOrNull(v['id']),
        title: ReflectionEntry._asTrimmedOrNull(v['title']),
        kind: ReflectionEntry._asTrimmedOrNull(v['kind']),
        durationSec:
            ReflectionEntry._toInt(v['duration_sec'] ?? v['durationSec']),
        status: ReflectionEntry._asTrimmedOrNull(v['status']),
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MiniChallenge &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          kind == other.kind &&
          durationSec == other.durationSec &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, title, kind, durationSec, status);
}

class ReflectionLinks {
  final String? storyId;

  const ReflectionLinks({this.storyId});

  Map<String, dynamic> toJson() => {
        if (storyId != null) 'story_id': storyId,
      };

  static ReflectionLinks? fromMaybe(dynamic v) {
    if (v == null) return null;
    if (v is String && v.trim().isNotEmpty) {
      return ReflectionLinks(storyId: v.trim());
    }
    if (v is Map<String, dynamic>) {
      return ReflectionLinks(
        storyId:
            ReflectionEntry._asTrimmedOrNull(v['story_id'] ?? v['storyId']),
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReflectionLinks &&
          runtimeType == other.runtimeType &&
          storyId == other.storyId;

  @override
  int get hashCode => storyId.hashCode;
}

// ============================================================================
// Guiding Question (nur für Leitfragen – nicht für Community-Fragen!)
// - Stabil & nullsafe
// - Optionales [createdAt] für Sortierung/Analytics (kein Pflichtfeld)
// ============================================================================

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
        if (createdAt != null)
          'createdAt': createdAt!.toUtc().toIso8601String(),
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
    if (const ['false', '0', 'no', 'n', 'nein', 'falsch'].contains(s))
      return false;
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
        return DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000,
            isUtc: true);
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
