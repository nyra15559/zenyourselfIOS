// lib/models/journal_entry.dart
//
// JournalEntry Model — Oxford-Zen v3.9
// -----------------------------------------------------------------------------
// • Einheitliches Modell: EntryKind { reflection, journal, story }.
// • Robust: fromJson()/fromMap() akzeptieren String ODER Map, inkl. Legacy-Keys.
// • Legacy-Shims: JournalType, .type, .text, .moodLabel bleiben erhalten.
// • Titel-Pipeline: computedTitle + withAutoTitle() (nicht-destruktiv).
// • UI-Hilfen: badge (Label+Icon), previewText(), metaLine().
// • Zeit: createdAt wird intern als UTC gehalten; createdAtLocal liefert lokale Zeit.
// • Extras: Sortier-/Filter-Helfer & kleine Utils (ohne neue Abhängigkeiten).

import 'dart:convert';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

/// Moderne Arten von Journaleinträgen.
enum EntryKind { reflection, journal, story }

/// ⚠️ Legacy-Shim (für bestehenden Code).
@Deprecated('Use EntryKind instead')
enum JournalType { reflection, journal, story }

// ─────────────────────────────────────────────────────────────────────────────
// Kind helpers (robust / i18n)
// ─────────────────────────────────────────────────────────────────────────────

/// Robust: akzeptiert null / dynamische Eingaben.
EntryKind entryKindFromString(dynamic value) {
  final s = value?.toString().toLowerCase().trim() ?? '';
  switch (s) {
    // Reflection
    case 'reflection':
    case 'reflexion':
    case 'reflektion':
    case 'reflection_entry':
      return EntryKind.reflection;

    // Journal / Note
    case 'journal':
    case 'gedanke':
    case 'tagebuch':
    case 'note':
    case 'entry':
      return EntryKind.journal;

    // Story
    case 'story':
    case 'kurzgeschichte':
    case 'short_story':
      return EntryKind.story;

    default:
      return EntryKind.journal; // neutrale Grundform
  }
}

/// Lokalisierte Typ-Bezeichnung.
String entryKindToString(EntryKind kind, {String locale = 'de'}) {
  final de = locale.toLowerCase().startsWith('de');
  switch (kind) {
    case EntryKind.reflection:
      return de ? 'Reflexion' : 'reflection';
    case EntryKind.journal:
      return de ? 'Tagebuch' : 'journal';
    case EntryKind.story:
      return de ? 'Kurzgeschichte' : 'story';
  }
}

/// Leichtgewichtige Badge-Info (UI-Hilfe).
class EntryBadge {
  final String label;
  final IconData icon;
  const EntryBadge({required this.label, required this.icon});
}

EntryBadge badgeForEntryKind(EntryKind kind, {String locale = 'de'}) {
  switch (kind) {
    case EntryKind.reflection:
      return EntryBadge(
        label: entryKindToString(kind, locale: locale),
        icon: Icons.psychology_alt_outlined,
      );
    case EntryKind.journal:
      return EntryBadge(
        label: entryKindToString(kind, locale: locale),
        icon: Icons.menu_book_outlined,
      );
    case EntryKind.story:
      return EntryBadge(
        label: entryKindToString(kind, locale: locale),
        icon: Icons.auto_stories_outlined,
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

/// Zentrales Journal-Model (UI-nah, aber framework-frei).
class JournalEntry {
  // Basis
  final String id;
  final EntryKind kind;
  final DateTime createdAt; // UTC

  // Meta
  final String? title;
  final String? subtitle;

  // Journal / Reflexion
  final String? thoughtText; // „Dein Gedanke“
  final String? aiQuestion; // Leitfrage(n)
  final String? userAnswer; // Antwort

  // Story
  final String? storyTitle;
  final String? storyTeaser;

  // Flags & Zusatz
  final List<String> tags;
  final bool hidden; // Soft-Hide
  final String? sourceRef; // z. B. Session/Remote-ID

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
    this.tags = const <String>[],
    this.hidden = false,
    this.sourceRef,
  });

  // ───────── Factories

  /// Fabrik: Journal (Tagebuch).
  factory JournalEntry.journal({
    required String id,
    DateTime? createdAt,
    String? title,
    String? subtitle,
    String? thoughtText,
    List<String> tags = const <String>[],
    bool hidden = false,
    String? sourceRef,
  }) =>
      JournalEntry(
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

  /// Fabrik: Reflexion.
  factory JournalEntry.reflection({
    required String id,
    DateTime? createdAt,
    String? title,
    String? subtitle,
    String? thoughtText,
    String? aiQuestion,
    String? userAnswer,
    List<String> tags = const <String>[],
    bool hidden = false,
    String? sourceRef,
  }) =>
      JournalEntry(
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

  /// Fabrik: Story.
  factory JournalEntry.story({
    required String id,
    DateTime? createdAt,
    String? title,
    String? storyTitle,
    String? storyTeaser,
    List<String> tags = const <String>[],
    bool hidden = false,
    String? sourceRef,
  }) =>
      JournalEntry(
        id: id,
        kind: EntryKind.story,
        createdAt: (createdAt ?? DateTime.now()).toUtc(),
        title: title,
        storyTitle: storyTitle,
        storyTeaser: storyTeaser,
        tags: tags,
        hidden: hidden,
        sourceRef: sourceRef,
      );

  // ─────────────────────── UI-Hilfen ───────────────────────

  /// Lokale Zeit.
  DateTime get createdAtLocal => createdAt.toLocal();

  /// Badge (Label + Icon).
  EntryBadge get badge => badgeForEntryKind(kind);

  /// Legacy-Shim: alter Enum.
  @Deprecated('Use .kind instead')
  JournalType get type => JournalType.values[kind.index];

  /// Kurzer Inhaltstext:
  /// - Reflexion: bevorzugt userAnswer, sonst thoughtText
  /// - Journal: thoughtText
  /// - Story: storyTeaser (oder storyTitle)
  String get text {
    switch (kind) {
      case EntryKind.reflection:
        return _safe(userAnswer).isNotEmpty
            ? _safe(userAnswer)
            : _safe(thoughtText);
      case EntryKind.journal:
        return _safe(thoughtText);
      case EntryKind.story:
        final teaser = _safe(storyTeaser);
        return teaser.isNotEmpty ? teaser : _safe(storyTitle);
    }
  }

  /// Mood-Label aus Tags (`mood:<Label>`), z. B. „Neutral“.
  String? get moodLabel {
    for (final t in tags) {
      final s = t.trim();
      if (s.startsWith('mood:')) {
        final v = s.substring(5).trim();
        return v.isEmpty ? null : v;
      }
    }
    return null;
  }

  /// Optionaler numerischer Mood-Score aus Tags (`moodScore:<0..4>`).
  int? get moodScore {
    for (final t in tags) {
      final s = t.trim();
      if (s.startsWith('moodScore:')) {
        final v = int.tryParse(s.substring(10).trim());
        if (v != null) return v.clamp(0, 4);
      }
    }
    return null;
  }

  /// Titel, falls `title` leer ist – je nach Typ sinnvoll befüllt.
  /// (ohne Präfixe wie „Tagebuch:“ etc.)
  String get computedTitle {
    if (_isNotEmpty(title)) return title!.trim();
    switch (kind) {
      case EntryKind.journal:
        if (_isNotEmpty(thoughtText)) return _firstWords(thoughtText!, 6);
        return 'Tagebuch';
      case EntryKind.reflection:
        if (_isNotEmpty(userAnswer)) return _firstWords(userAnswer!, 8);
        if (_isNotEmpty(aiQuestion)) return _firstWords(aiQuestion!, 6);
        return 'Reflexion';
      case EntryKind.story:
        if (_isNotEmpty(storyTitle)) return storyTitle!.trim();
        return 'Kurzgeschichte';
    }
  }

  /// Nicht-destruktiv: setzt `title` auf `computedTitle`, wenn leer.
  JournalEntry withAutoTitle() =>
      _isNotEmpty(title) ? this : copyWith(title: computedTitle);

  /// Kompakter 3-Zeilen-Preview-Text (für Cards).
  String previewText({String locale = 'de'}) {
    switch (kind) {
      case EntryKind.reflection:
        final q = _isNotEmpty(aiQuestion) ? _italic(_safe(aiQuestion)) : '';
        final a = _safe(userAnswer);
        final t = _joinNonEmpty([q, a], sep: ' ');
        return t.isEmpty ? entryKindToString(kind, locale: locale) : t;
      case EntryKind.journal:
        return _safe(thoughtText).isNotEmpty
            ? _safe(thoughtText)
            : entryKindToString(kind, locale: locale);
      case EntryKind.story:
        final t = _safe(storyTitle).isNotEmpty
            ? _safe(storyTitle)
            : entryKindToString(kind, locale: locale);
        final z = _safe(storyTeaser);
        return _joinNonEmpty([t, z], sep: ' — ');
    }
  }

  /// Meta-Zeile wie „Mo., 08.09., 17:26 — Kurzgeschichte“ (ohne Intl-Dependency).
  String metaLine({String locale = 'de'}) {
    final dt = createdAtLocal;
    final de = locale.toLowerCase().startsWith('de');
    final wd = de ? _deWeekday(dt.weekday) : _enWeekday(dt.weekday);
    final dd = _two(dt.day);
    final mm = _two(dt.month);
    final hh = _two(dt.hour);
    final mi = _two(dt.minute);
    final date = de ? '$wd, $dd.$mm., $hh:$mi' : '$wd, $mm/$dd, $hh:$mi';
    return '$date — ${entryKindToString(kind, locale: locale)}';
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
      tags: tags ?? this.tags,
      hidden: hidden ?? this.hidden,
      sourceRef: sourceRef ?? this.sourceRef,
    );
  }

  @override
  String toString() =>
      'JournalEntry(id:$id, kind:$kind, createdAt:$createdAt, title:${title ?? ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is JournalEntry && other.id == id);

  @override
  int get hashCode => id.hashCode;

  // ─────────────────────── (De)Serialisierung ───────────────────────

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'kind': kind.toString().split('.').last,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'title': title,
        'subtitle': subtitle,
        'thoughtText': thoughtText,
        'aiQuestion': aiQuestion,
        'userAnswer': userAnswer,
        'storyTitle': storyTitle,
        'storyTeaser': storyTeaser,
        'tags': tags,
        'hidden': hidden,
        'sourceRef': sourceRef,
      }..removeWhere((_, v) => v == null);

  String toJson() => json.encode(toMap());

  /// ⚠️ Tolerant: akzeptiert String **oder** Map.
  static JournalEntry fromJson(dynamic source) {
    try {
      if (source is String) {
        final obj = json.decode(source);
        if (obj is Map<String, dynamic>) return fromMap(obj);
        if (obj is Map) return fromMap(obj.cast<String, dynamic>());
      } else if (source is Map<String, dynamic>) {
        return fromMap(source);
      } else if (source is Map) {
        return fromMap(source.cast<String, dynamic>());
      }
    } catch (_) {/* fallthrough */}
    throw const FormatException('JournalEntry.fromJson expects String or Map');
  }

  /// Tolerant gegenüber fehlenden/unbekannten Feldern (+ Legacy-Mapping).
  static JournalEntry fromMap(Map<String, dynamic> map) {
    // ---- ID
    final String id = _asString(map['id']) ?? _genId();

    // ---- Zeit
    final DateTime createdAt = _toDate(map['createdAt']) ??
        _toDate(map['ts']) ??
        _toDate(map['timestamp']) ??
        _toDate(map['created']) ??
        _toDate(map['created_at']) ??
        _toDate(map['date']) ??
        DateTime.now().toUtc();

    // ---- Kind
    EntryKind kind;
    final kRaw = _asString(map['kind']) ?? _asString(map['type']);
    if (_isNotEmpty(kRaw)) {
      kind = entryKindFromString(kRaw);
    } else if (_toBool(map['isReflection']) == true) {
      kind = EntryKind.reflection;
    } else if (_toBool(map['isStory']) == true) {
      kind = EntryKind.story;
    } else if (_toBool(map['isJournal']) == true || _toBool(map['isNote']) == true) {
      kind = EntryKind.journal;
    } else {
      // Heuristik
      kind = inferKind(
        aiQuestion: _asString(map['aiQuestion']) ?? _asString(map['question']),
        userAnswer: _asString(map['userAnswer']) ?? _asString(map['answer']),
        storyTitle: _asString(map['storyTitle']),
        storyTeaser: _asString(map['storyTeaser']),
        thoughtText: _asString(map['thoughtText']) ?? _asString(map['text']),
      );
    }

    // ---- Basis-/Inhaltsfelder (mit Legacy-Aliases)
    final title = _asString(map['title']) ?? _asString(map['label']);
    final subtitle = _asMaybeString(map, ['subtitle', 'subTitle']);
    final thoughtText =
        _asString(map['thoughtText']) ?? _asString(map['text']) ?? _asString(map['body']);
    final aiQuestion =
        _asString(map['aiQuestion']) ?? _asString(map['question']) ?? _asString(map['prompt']);
    final userAnswer =
        _asString(map['userAnswer']) ?? _asString(map['answer']) ?? _asString(map['response']);
    final storyTitle = _asString(map['storyTitle']); // bewusst NICHT title überschreiben
    final storyTeaser = _asString(map['storyTeaser']) ?? _asString(map['teaser']);

    // ---- Tags (inkl. Legacy-Einbettungen)
    final tags = <String>{
      ..._asStringList(map['tags']),
      ..._asStringList(map['tag']),
    };

    // Mood Label/Score in Tags nachziehen, falls nicht vorhanden
    final legacyMoodLabel = _asMaybeString(map, ['mood', 'moodLabel']);
    if (_isNotEmpty(legacyMoodLabel) && !tags.any((t) => t.trim().startsWith('mood:'))) {
      tags.add('mood:${legacyMoodLabel!.trim()}');
    }
    final legacyMoodScore = _asInt(map['moodScore']);
    if (legacyMoodScore != null && !tags.any((t) => t.trim().startsWith('moodScore:'))) {
      tags.add('moodScore:${legacyMoodScore.clamp(0, 4)}');
    }

    // ---- Hidden / Source
    final hidden = _toBool(map['hidden']) ??
        _toBool(map['isHidden']) ??
        _toBool(map['softHidden']) ??
        false;

    final sourceRef = _asMaybeString(map, ['sourceRef', 'source', 'sessionId', 'remoteId']);

    return JournalEntry(
      id: id,
      kind: kind,
      createdAt: createdAt,
      title: title,
      subtitle: subtitle,
      thoughtText: thoughtText,
      aiQuestion: aiQuestion,
      userAnswer: userAnswer,
      storyTitle: storyTitle,
      storyTeaser: storyTeaser,
      tags: tags.toList(growable: false),
      hidden: hidden,
      sourceRef: sourceRef,
    );
  }

  /// Heuristik für alte Saves ohne `kind`.
  static EntryKind inferKind({
    String? aiQuestion,
    String? userAnswer,
    String? storyTitle,
    String? storyTeaser,
    String? thoughtText,
  }) {
    if (_isNotEmpty(storyTitle) || _isNotEmpty(storyTeaser)) return EntryKind.story;
    if (_isNotEmpty(aiQuestion) || _isNotEmpty(userAnswer)) return EntryKind.reflection;
    if (_isNotEmpty(thoughtText)) return EntryKind.journal;
    return EntryKind.journal;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collection helpers (Sorting/Filtering) — optional, aber praktisch in Providern
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
  List<JournalEntry> withAutoTitles() => map((e) => e.withAutoTitle()).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (privat)
// ─────────────────────────────────────────────────────────────────────────────

bool _isNotEmpty(String? s) => (s != null) && s.trim().isNotEmpty;

String _safe(String? s) => s?.trim() ?? '';

String _joinNonEmpty(List<String> parts, {String sep = ' '}) =>
    parts.where((p) => p.trim().isNotEmpty).join(sep).trim();

String _firstWords(String s, int n, {String prefix = ''}) {
  final normalized = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return prefix.isNotEmpty ? prefix.trim() : '';
  final words = normalized.split(' ');
  final take = words.take(n).join(' ');
  return prefix + take + (words.length > n ? '…' : '');
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toUtc();
  if (v is num) {
    final val = v.toInt();
    // Heuristik: < 10^12 = Sekunden, sonst Millisekunden
    final isSec = val.abs() < 1000000000000;
    final ms = isSec ? val * 1000 : val;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    final numVal = num.tryParse(s);
    if (numVal != null) return _toDate(numVal);
    return DateTime.tryParse(s)?.toUtc();
  }
  return null;
}

bool? _toBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
  }
  return null;
}

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

String? _asMaybeString(Map<String, dynamic> map, List<String> keys) {
  for (final k in keys) {
    final v = map[k];
    final s = _asString(v);
    if (_isNotEmpty(s)) return s!.trim();
  }
  return null;
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

List<String> _asStringList(dynamic v) {
  if (v == null) return const <String>[];
  if (v is List) {
    return v
        .map((e) => _asString(e))
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .toList(growable: false);
  }
  if (v is String) {
    // Kommagetrennt (Legacy) akzeptieren
    return v
        .split(',')
        .map((e) => e.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

/// Markdown-ähnliche Kursiv-Andeutung (für Preview).
String _italic(String s) => '*$s*';

/// Einfache lokale ID (falls kein Backend-UUID vorhanden).
String _genId() => 'je_${DateTime.now().microsecondsSinceEpoch}';

String _two(int x) => x < 10 ? '0$x' : '$x';

String _deWeekday(int w) =>
    const ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'][_wdIndex(w)];
String _enWeekday(int w) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][_wdIndex(w)];

int _wdIndex(int w) => ((w % 7) + 6) % 7; // 1..7 → 0..6 (Mo..So)
// ─────────────────────────────────────────────────────────────────────────────
