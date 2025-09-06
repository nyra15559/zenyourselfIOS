// lib/data/journal_entry.dart
//
// JournalEntry – Compatibility Shim v1.0 (Oxford-Zen)
//
// Zweck
// -----
// Dieses File re-exportiert das *kanonische* Modell aus `lib/models/journal_entry.dart`
// und stellt eine dünne Legacy-Kompatibilitätsschicht bereit, damit ältere Stellen
// im Code weiter mit `package:.../data/journal_entry.dart` arbeiten können.
//
// Was ist enthalten?
// - Re-Export:  JournalEntry, EntryKind  (kanonisch)
// - Legacy-Enum: JournalType { journal, reflection, story }
// - Extension auf EntryKind: Mapping zu JournalType
// - Extension auf JournalEntry: 
//     • `type` (Legacy, aus `kind` abgeleitet)
//     • `moodLabel` (aus Tags: `mood:` oder `moodScore:` → Label)
//     • `moodScore` (optional; aus `moodScore:`-Tag)
//     • `dayKey`, `timeLabel`, `ts` (Aliasse/Helfer für ältere Aufrufer)
//     • `preview([max=160])` (kompakte Vorschau; robust für Reflection/Story/Journal)
//
// Wichtig
// -------
// *Keine* UI-Imports in diesem Shim. Farben/Icons etc. gehören in UI-Schichten.
// Dieser Shim beseitigt die Typ-Divergenz (/*1*/ vs /*2*/) ohne Groß-Refactor,
// indem überall derselbe JournalEntry-Typ verwendet wird.
//

// Re-export des kanonischen Modells
import '../models/journal_entry.dart' as jm show JournalEntry, EntryKind;
export '../models/journal_entry.dart' show JournalEntry, EntryKind;

/// Legacy-Typ für alten Code (entspricht EntryKind im kanonischen Modell).
enum JournalType { journal, reflection, story }

/// Mapping vom kanonischen EntryKind zum Legacy-JournalType.
extension EntryKindLegacyMapping on jm.EntryKind {
  JournalType get asLegacy {
    switch (this) {
      case jm.EntryKind.journal:
        return JournalType.journal;
      case jm.EntryKind.reflection:
        return JournalType.reflection;
      case jm.EntryKind.story:
        return JournalType.story;
    }
  }
}

/// Kompatibilitäts- und Convenience-APIs auf dem kanonischen JournalEntry.
extension JournalEntryCompat on jm.JournalEntry {
  /// Legacy-Getter `type` (aus `kind` abgeleitet).
  JournalType get type => kind.asLegacy;

  /// Optionaler Mood-Score (0..4), aus Tags `moodScore:<n>` extrahiert.
  int? get moodScore {
    for (final t in tags) {
      final s = t.trim();
      if (s.startsWith('moodScore:')) {
        final raw = s.substring(10).trim();
        final n = int.tryParse(raw);
        if (n != null) return n;
      }
    }
    return null;
  }

  /// Legacy `moodLabel` – aus `mood:<Label>` oder via Mapping von `moodScore`.
  String get moodLabel {
    // 1) Direktes Label vorrangig
    for (final t in tags) {
      final s = t.trim();
      if (s.startsWith('mood:')) {
        final lbl = s.substring(5).trim();
        if (lbl.isNotEmpty) return lbl;
      }
    }
    // 2) Fallback aus Score
    final score = moodScore;
    switch (score) {
      case 0:
        return 'Sehr schlecht';
      case 1:
        return 'Eher schlecht';
      case 2:
        return 'Neutral';
      case 3:
        return 'Eher gut';
      case 4:
        return 'Sehr gut';
      default:
        return '';
    }
  }

  /// Alias für Alt-Code (einige Alt-Modelle nutzten `ts`).
  DateTime get ts => createdAt;

  /// YYYYMMDD als int – nützlich zum Gruppieren in Listen (lokale Zeit).
  int get dayKey {
    final d = createdAt.toLocal();
    return d.year * 10000 + d.month * 100 + d.day;
    // Beispiel: 2025-09-04 → 20250904
  }

  /// HH:MM (lokal) – kurzer Zeitstempel für UI.
  String get timeLabel {
    final d = createdAt.toLocal();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Kompakte Vorschau:
  /// - Reflection: letzte Nutzerantwort → sonst Thought → sonst Frage
  /// - Story: Teaser → sonst (Story-)Title
  /// - Journal: Thought/Text → sonst Title
  /// Whitespace normalisiert, bei Bedarf auf [max] gekürzt.
  String preview([int max = 160]) {
    String pick() {
      if (kind == jm.EntryKind.story) {
        final teaser = (storyTeaser ?? '').trim();
        if (teaser.isNotEmpty) return teaser;
        final ttl = ((storyTitle ?? title) ?? '').trim();
        return ttl.isNotEmpty ? ttl : 'Kurzgeschichte';
      }
      if (kind == jm.EntryKind.reflection) {
        final ans = (userAnswer ?? '').trim();
        if (ans.isNotEmpty) return ans;
        final thought = (thoughtText ?? '').trim();
        if (thought.isNotEmpty) return thought;
        final q = (aiQuestion ?? '').trim();
        return q.isNotEmpty ? q : 'Reflexion';
      }
      // Journal
      final t = (thoughtText ?? '').trim();
      if (t.isNotEmpty) return t;
      final ttl = (title ?? '').trim();
      return ttl.isNotEmpty ? ttl : 'Gedanke';
    }

    final base = pick().replaceAll(RegExp(r'\s+'), ' ');
    if (base.length <= max) return base;
    return '${base.substring(0, max).trimRight()}…';
  }
}
