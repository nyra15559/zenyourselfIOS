// lib/models/journal_entry.dart
//
// JournalEntry — kanonisches Model (v5.2 • 2025-09-13)
// -----------------------------------------------------------------------------
// Ziele (Projektregeln v6zenyourself):
// • Einheitliches Datenmodell für alle Entry-Typen (reflection, journal, story)
// • Rückwärtskompatibel zu alten Saves (tolerantes fromMap, Legacy-Aliases)
// • Stabile Persistenz: storyBody wird NIE gekürzt/entfernt
// • Titel-Pipeline: withAutoTitleIfEmpty() überschreibt nie vorhandene Titel
// • Framework-frei (KEIN flutter/material.dart import)
// • UI-Kompat: computedTitle/metaLine/badge + Alias withAutoTitle()
//
// Wichtige Felder (Inhalt):
//  - thoughtText (Dein Gedanke), aiQuestion (Leitfrage), userAnswer (Antwort)
//  - storyTitle / storyTeaser / storyBody (Volltext)
//  - tags (inkl. mood:/moodScore:), hidden (Soft-Hide), sourceRef
//
// Lizenz: ZenYourself (v6zenyourself) — Oxford–Zen Style

import 'dart:convert';

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

/// Art des Eintrags in Journal/Gedankenbuch.
enum EntryKind { reflection, journal, story }

extension EntryKindX on EntryKind {
  /// Stabiler Key für Persistenz/Badges.
  String get key {
    switch (this) {
      case EntryKind.reflection:
        return 'reflection';
      case EntryKind.journal:
        return 'journal';
      case EntryKind.story:
        return 'story';
    }
  }

  /// Menschlicher Label-Text (DE).
  String get labelDe {
    switch (this) {
      case EntryKind.reflection:
        return 'Reflexion';
      case EntryKind.journal:
        return 'Gedanke';
      case EntryKind.story:
        return 'Kurzgeschichte';
    }
  }

  /// Icon/Badge-Key (UI wählt Icon/Farbe selbst).
  String get iconKey {
    switch (this) {
      case EntryKind.reflection:
        return 'icon.reflection';
      case EntryKind.journal:
        return 'icon.journal';
      case EntryKind.story:
        return 'icon.story';
    }
  }

  /// Badge-Key (für konsistente Badges).
  String get badgeKey {
    switch (this) {
      case EntryKind.reflection:
        return 'badge.reflection';
      case EntryKind.journal:
        return 'badge.journal';
      case EntryKind.story:
        return 'badge.story';
    }
  }

  /// Robust aus String/Dynamik herstellen (tolerant, DE/EN).
  static EntryKind fromAny(dynamic value) {
    final s = value?.toString().trim().toLowerCase() ?? '';
    switch (s) {
      case 'reflection':
      case 'reflexion':
      case 'reflektion':
      case 'reflection_entry':
        return EntryKind.reflection;
      case 'journal':
      case 'gedanke':
      case 'tagebuch':
      case 'note':
      case 'entry':
        return EntryKind.journal;
      case 'story':
      case 'kurzgeschichte':
      case 'short_story':
        return EntryKind.story;
      default:
        return EntryKind.journal;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

/// Kanonischer Journal-Eintrag.
/// Framework-frei, damit überall nutzbar (Provider/UI/Services).
class JournalEntry {
  // Basis
  final String id;
  final EntryKind kind;
  final DateTime createdAt; // UTC

  // Generischer Titel/Subtitel (für Card/Header)
  final String? title;
  final String? subtitle;

  // Reflection-Felder
  final String? thoughtText;   // „Dein Gedanke …“
  final String? aiQuestion;    // Panda-Leitfrage (kursiv in der View)
  final String? userAnswer;    // Deine Antwort (grün)

  // Story-Felder
  final String? storyTitle;    // Überschrift der Story
  final String? storyTeaser;   // kurzer Teaser (für Card-Preview)
  final String? storyBody;     // VOLLTEXT — wird nie beschnitten

  // Meta
  final List<String> tags;     // automatische/manuelle Tags
  final bool hidden;           // Soft-Hide-Flag
  final String? sourceRef;     // z. B. Session-ID, Worker, Import-Quelle

  const JournalEntry({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.title,
    this.subtitle,
    this.thoughtText,
    this.aiQuestion,
    this.userAnswer,
    this.storyTitle,
    this.storyTeaser,
    this.storyBody,
    this.tags = const [],
    this.hidden = false,
    this.sourceRef,
  });

  // ─────────────────────── Fabriken (Bequemlichkeit) ───────────────────────

  factory JournalEntry.journal({
    required String id,
    DateTime? createdAt,
    String? title,
    String? subtitle,
    String? thoughtText,
    List<String> tags = const [],
    bool hidden = false,
    String? sourceRef,
  }) {
    return JournalEntry(
      id: id,
      kind: EntryKind.journal,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      title: title,
      subtitle: subtitle,
      thoughtText: thoughtText,
      tags: tags,
      hidden: hidden,
      sourceRef: sourceRef,
    );
  }

  factory JournalEntry.reflection({
    required String id,
    DateTime? createdAt,
    String? title,
    String? subtitle,
    String? thoughtText,
    String? aiQuestion,
    String? userAnswer,
    List<String> tags = const [],
    bool hidden = false,
    String? sourceRef,
  }) {
    return JournalEntry(
      id: id,
      kind: EntryKind.reflection,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      title: title,
      subtitle: subtitle,
      thoughtText: thoughtText,
      aiQuestion: aiQuestion,
      userAnswer: userAnswer,
      tags: tags,
      hidden: hidden,
      sourceRef: sourceRef,
    );
  }

  factory JournalEntry.story({
    required String id,
    DateTime? createdAt,
    String? title,
    String? storyTitle,
    String? storyTeaser,
    String? storyBody,
    List<String> tags = const [],
    bool hidden = false,
    String? sourceRef,
  }) {
    return JournalEntry(
      id: id,
      kind: EntryKind.story,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      title: title,
      storyTitle: storyTitle,
      storyTeaser: storyTeaser,
      storyBody: storyBody,
      tags: tags,
      hidden: hidden,
      sourceRef: sourceRef,
    );
  }

  // ─────────────────────── UI-Hilfen (framework-frei) ───────────────────────

  /// Lokale Zeit für Anzeige.
  DateTime get createdAtLocal => createdAt.toLocal();

  /// Kurzer Preview-Text (3-Zeilen-geeignet).
  /// - Reflexion: bevorzugt userAnswer, sonst aiQuestion/thoughtText
  /// - Journal: thoughtText
  /// - Story: teaser → title → erste Wörter aus body
  String previewText() {
    switch (kind) {
      case EntryKind.reflection:
        final a = _safe(userAnswer);
        if (a.isNotEmpty) return a;
        final q = _safe(aiQuestion);
        if (q.isNotEmpty) return q;
        return _safe(thoughtText);
      case EntryKind.journal:
        return _safe(thoughtText);
      case EntryKind.story:
        final t = _safe(storyTeaser);
        if (t.isNotEmpty) return t;
        final st = _safe(storyTitle);
        if (st.isNotEmpty) return st;
        return _firstWords(_safe(storyBody), 10) ?? '';
    }
  }

  /// Nicht-destruktiv: setzt `title` nur, wenn aktuell leer.
  JournalEntry withAutoTitleIfEmpty() {
    if (_nonEmpty(title)) return this;

    String? candidate;
    switch (kind) {
      case EntryKind.reflection:
        candidate = _firstNonEmpty([userAnswer, aiQuestion, thoughtText]);
        break;
      case EntryKind.journal:
        candidate = _firstNonEmpty([thoughtText, subtitle]);
        break;
      case EntryKind.story:
        candidate = _firstNonEmpty([
          storyTitle,
          storyTeaser,
          _firstWords(storyBody, 6),
        ]);
        break;
    }
    candidate ??= kind.labelDe;

    final tidied = _tidyTitle(candidate);
    return copyWith(title: tidied);
  }

  // ─────────────────────── Copy / Equality ───────────────────────

  JournalEntry copyWith({
    String? id,
    EntryKind? kind,
    DateTime? createdAt,
    String? title,
    String? subtitle,
    String? thoughtText,
    String? aiQuestion,
    String? userAnswer,
    String? storyTitle,
    String? storyTeaser,
    String? storyBody,
    List<String>? tags,
    bool? hidden,
    String? sourceRef,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      createdAt: (createdAt ?? this.createdAt).toUtc(),
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      thoughtText: thoughtText ?? this.thoughtText,
      aiQuestion: aiQuestion ?? this.aiQuestion,
      userAnswer: userAnswer ?? this.userAnswer,
      storyTitle: storyTitle ?? this.storyTitle,
      storyTeaser: storyTeaser ?? this.storyTeaser,
      storyBody: storyBody ?? this.storyBody,
      tags: tags ?? List<String>.from(this.tags),
      hidden: hidden ?? this.hidden,
      sourceRef: sourceRef ?? this.sourceRef,
    );
  }

  @override
  String toString() =>
      'JournalEntry(${kind.key} • $id • ${createdAt.toIso8601String()} • "${title ?? '-'}")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalEntry && other.id == id);

  @override
  int get hashCode => id.hashCode;

  // ─────────────────────── (De)Serialisierung ───────────────────────

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.key,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'title': title,
      'subtitle': subtitle,
      'thoughtText': thoughtText,
      'aiQuestion': aiQuestion,
      'userAnswer': userAnswer,
      'storyTitle': storyTitle,
      'storyTeaser': storyTeaser,
      'storyBody': storyBody, // WICHTIG: niemals kürzen/entfernen
      'tags': tags,
      'hidden': hidden,
      'sourceRef': sourceRef,
    }..removeWhere((_, v) => v == null);
  }

  String toJson() => jsonEncode(toMap());

  /// Toleranter Parser: akzeptiert alte/abweichende Keys.
  /// Entfernt KEINE Inhalte (insb. storyBody bleibt).
  static JournalEntry fromMap(Map<String, dynamic> map) {
    // Helpers
    String? s0(dynamic v) => v?.toString();
    bool b(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final t = v.trim().toLowerCase();
        return t == 'true' || t == '1' || t == 'yes' || t == 'y';
      }
      return false;
    }

    // kind
    final rawKind = s0(map['kind']) ?? s0(map['type']);
    final kind = rawKind != null
        ? EntryKindX.fromAny(rawKind)
        : EntryKindX.fromAny(_inferKindKey(map));

    // createdAt
    DateTime created;
    final rawCreated = map['createdAt'] ??
        map['created_at'] ??
        map['ts'] ??
        map['timestamp'] ??
        map['created'] ??
        map['date'];
    created = _toDateUtc(rawCreated) ?? DateTime.now().toUtc();

    // tags
    final tags = <String>[];
    final rawTags = map['tags'] ?? map['tag'];
    if (rawTags is List) {
      for (final t in rawTags) {
        final s = s0(t)?.trim();
        if (s != null && s.isNotEmpty) tags.add(s);
      }
    } else if (rawTags is String && rawTags.trim().isNotEmpty) {
      tags.addAll(rawTags.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }

    // Legacy mood → in Tags spiegeln, falls noch nicht vorhanden
    final legacyMoodLabel = s0(map['mood']) ?? s0(map['moodLabel']);
    if (legacyMoodLabel != null &&
        !tags.any((t) => t.trim().toLowerCase().startsWith('mood:'))) {
      tags.add('mood:${legacyMoodLabel.trim()}');
    }
    final legacyMoodScore = _toInt(map['moodScore']);
    if (legacyMoodScore != null &&
        !tags.any((t) => t.trim().toLowerCase().startsWith('moodscore:'))) {
      final clamped = legacyMoodScore.clamp(0, 4);
      tags.add('moodScore:$clamped');
    }

    // Build
    final entry = JournalEntry(
      id: s0(map['id']) ?? _genIdFallback(created),
      kind: kind,
      createdAt: created,
      title: s0(map['title']) ?? s0(map['label']),
      subtitle: s0(map['subtitle']) ?? s0(map['subTitle']) ?? s0(map['sub']),
      thoughtText: s0(map['thoughtText']) ?? s0(map['text']) ?? s0(map['body']),
      aiQuestion: s0(map['aiQuestion']) ?? s0(map['question']) ?? s0(map['prompt']),
      userAnswer: s0(map['userAnswer']) ?? s0(map['answer']) ?? s0(map['response']),
      storyTitle: s0(map['storyTitle']) ?? s0(map['story_title']) ?? s0(map['storyName']),
      storyTeaser: s0(map['storyTeaser']) ?? s0(map['story_teaser']) ?? s0(map['teaser']),
      storyBody: s0(map['storyBody']) ?? s0(map['story_body']) ?? s0(map['content']),
      tags: tags,
      hidden: b(map['hidden']) ||
          b(map['isHidden']) ||
          b(map['softHidden']),
      sourceRef: s0(map['sourceRef']) ?? s0(map['source']) ?? s0(map['session']) ?? s0(map['remoteId']),
    );

    return entry.withAutoTitleIfEmpty();
  }

  static JournalEntry fromJson(dynamic source) {
    if (source is String) {
      final obj = jsonDecode(source);
      if (obj is Map<String, dynamic>) return fromMap(obj);
      if (obj is Map) return fromMap(obj.cast<String, dynamic>());
      throw const FormatException('JournalEntry.fromJson: JSON object expected');
    } else if (source is Map<String, dynamic>) {
      return fromMap(source);
    } else if (source is Map) {
      return fromMap(source.cast<String, dynamic>());
    }
    throw const FormatException('JournalEntry.fromJson expects String or Map');
  }

  // ─────────────────────── Utils ───────────────────────

  static String _inferKindKey(Map<String, dynamic> map) {
    // Heuristik zur Migration alter Datensätze
    final hasStory = (map.containsKey('storyBody') ||
        map.containsKey('story_title') ||
        map.containsKey('story_body') ||
        map.containsKey('storyTeaser'));
    if (hasStory) return 'story';

    final hasReflection =
        map.containsKey('aiQuestion') || map.containsKey('userAnswer') || map.containsKey('question');
    if (hasReflection) return 'reflection';

    return 'journal';
  }

  static DateTime? _toDateUtc(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toUtc();
    if (v is num) {
      final val = v.toInt();
      final isSec = val.abs() < 1000000000000;
      final ms = isSec ? val * 1000 : val;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      final n = num.tryParse(s);
      if (n != null) return _toDateUtc(n);
      return DateTime.tryParse(s)?.toUtc();
    }
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static String? _firstNonEmpty(List<String?> items) {
    for (final s in items) {
      if (s != null) {
        final t = s.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }

  static String? _firstWords(String? text, int n) {
    if (text == null) return null;
    final t = text.trim();
    if (t.isEmpty) return null;
    final words = t.split(RegExp(r'\s+'));
    final take = words.take(n).join(' ');
    return words.length > n ? '$take …' : take;
  }

  static String _tidyTitle(String raw) {
    var t = raw.trim();
    // Zero-Width/Steuerzeichen entfernen
    t = t
        .replaceAll(RegExp(r'[\u200B-\u200F\uFEFF]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.length > 140) t = '${t.substring(0, 137)}…';
    return t;
  }

  static String _genIdFallback(DateTime createdUtc) =>
      'je_${createdUtc.microsecondsSinceEpoch}';

  static bool _nonEmpty(String? s) => s != null && s.trim().isNotEmpty;

  static String _safe(String? s) => s?.trim() ?? '';
}

// ─────────────────────────────────────────────────────────────────────────────
// UI/Compat-Erweiterungen (framework-frei)
// ─────────────────────────────────────────────────────────────────────────────

extension JournalEntryUiCompatX on JournalEntry {
  /// Alias für ältere Aufrufer (Card erwartet withAutoTitle()).
  JournalEntry withAutoTitle() => withAutoTitleIfEmpty();

  /// Berechneter Titel ohne Mutation.
  /// Nutzt vorhandenen Titel, sonst heuristisch (Antwort → Frage → Gedanke …) und tidy.
  String get computedTitle {
    if (JournalEntry._nonEmpty(title)) return title!.trim();

    String? candidate;
    switch (kind) {
      case EntryKind.reflection:
        candidate = JournalEntry._firstNonEmpty([userAnswer, aiQuestion, thoughtText]);
        break;
      case EntryKind.journal:
        candidate = JournalEntry._firstNonEmpty([thoughtText, subtitle]);
        break;
      case EntryKind.story:
        candidate = JournalEntry._firstNonEmpty([
          storyTitle,
          storyTeaser,
          JournalEntry._firstWords(storyBody, 6),
        ]);
        break;
    }
    candidate ??= kind.labelDe;
    return JournalEntry._tidyTitle(candidate);
  }

  /// Meta-Zeile für Karten: „Do., 07.09., 19:05 — <Typ>“
  String metaLine() {
    final d = createdAtLocal;
    const wd = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];
    final weekday = wd[(d.weekday - 1).clamp(0, 6)];
    String two(int n) => n.toString().padLeft(2, '0');
    final dd = two(d.day);
    final mm = two(d.month);
    final hh = two(d.hour);
    final mi = two(d.minute);
    return '$weekday, $dd.$mm., $hh:$mi — ${kind.labelDe}';
  }

  /// Framework-freier Badge: Label + Icon-Key (UI mappt Key → IconData).
  ({String label, String iconKey}) get badge =>
      (label: kind.labelDe, iconKey: kind.iconKey);

  /// Menschenlesbares Mood-Label, falls in den Tags vorhanden (z. B. "mood:glücklich").
  /// Gibt `''` zurück, wenn nichts gesetzt ist.
  String get moodLabel {
    for (final raw in tags) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      final lower = s.toLowerCase();
      if (lower.startsWith('mood:')) {
        final idx = s.indexOf(':');
        if (idx >= 0 && idx + 1 < s.length) {
          final v = s.substring(idx + 1).trim();
          if (v.isNotEmpty) return v;
        }
      }
    }
    return '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collection helpers (Sorting/Filtering) — optional, aber praktisch
// ─────────────────────────────────────────────────────────────────────────────

extension JournalEntryListX on Iterable<JournalEntry> {
  /// Neueste zuerst (createdAt DESC).
  List<JournalEntry> sortedDesc() =>
      toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Nur sichtbare (nicht hidden).
  List<JournalEntry> visible() => where((e) => !e.hidden).toList();

  /// Filter nach Typ.
  List<JournalEntry> ofKind(EntryKind k) => where((e) => e.kind == k).toList();

  /// Titel automatisch füllen, wenn leer.
  List<JournalEntry> withAutoTitles() =>
      map((e) => e.withAutoTitleIfEmpty()).toList();
}
