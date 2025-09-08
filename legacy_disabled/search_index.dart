// lib/models/search_index.dart
//
// SearchIndex — Pro-Level Mini-Volltext für JournalEntries (offline, schnell)
// ---------------------------------------------------------------------------
// Ziele
// • Saubere, abhängige-freie Volltextsuche über JournalEntry (text, moodLabel, aiQuestion)
// • Ranking: TF-IDF-ähnlich + Recency-Boost (jüngere Einträge leicht bevorzugt)
// • Filter: Typ (note/reflection/story) + Datumsfenster (lokale Sicht)
// • Snippets: kurze Vorschaustellen mit Ellipsis; Treffer-Priorisierung
// • Inkrementelles Syncen: diff-basiert über (id, ts, text, moodLabel, aiQuestion, type)
// • Optionaler Binding-Helper zum JournalEntriesProvider (Re-Index bei Änderungen)
//
// Hinweise
// • Keine externen Pakete. Reiner Dart.
// • Diakritika-/Umlaute-Normalisierung (dezent): ä→ae, ö→oe, ü→ue, ß→ss, weitere Basics.
// • Tokenisierung: [A-Za-zÄÖÜäöüß0-9]+ (Bindestriche/Interpunktion sind Trenner).
// • Fuzzy light: Prefix-Match als Fallback, wenn kein exakter Token-Match existiert.
// • Designed für ~10–10.000 Einträge (mobile). Reindex i. d. R. < 10 ms / 1.000 Items auf modernen Geräten.
//
// Public API (Kernauszug)
// -----------------------
// final idx = SearchIndex();
// idx.syncFrom(entries);                           // kompletter Abgleich (diff)
// final results = idx.search('dankbar grenze');    // Treffer mit Ranking + Snippet
// idx.upsertEntry(entry);                          // Einzelne Mutation
// idx.removeById(id);
// idx.clear();
//
// Optionaler Provider-Binder:
// final binder = JournalEntriesSearchBinder(provider, idx);
// binder.attach(); // hört auf notifyListeners() und diffed intern
//
// Siehe: data/journal_entry.dart

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/journal_entry.dart';

/// Ergebnis eines Suchtreffers.
class SearchHit {
  final String id;
  final double score;
  final String snippet;
  final JournalType type;
  final DateTime ts; // UTC
  final List<String> matchedTerms;

  const SearchHit({
    required this.id,
    required this.score,
    required this.snippet,
    required this.type,
    required this.ts,
    required this.matchedTerms,
  });

  @override
  String toString() => 'SearchHit($id, ${score.toStringAsFixed(3)}, "${snippet.replaceAll('\n', ' ')}")';
}

/// Suchoptionen (optional).
class SearchOptions {
  final int limit;
  final Set<JournalType>? types; // Filter auf Typen, z. B. {JournalType.reflection}
  final DateTime? fromLocal; // inkl.
  final DateTime? toLocal;   // exkl.

  const SearchOptions({
    this.limit = 50,
    this.types,
    this.fromLocal,
    this.toLocal,
  });
}

/// Interner Dokument-Record (für Postings/Scoring).
class _Doc {
  final String id;
  final JournalType type;
  final DateTime tsUtc;
  final String text;        // Rohtext (für Snippets)
  final String moodLabel;   // Legacy-Label (kurz)
  final String aiQuestion;  // ggf. leer
  final String full;        // zusammengesetzt: text + moodLabel + aiQuestion
  final String norm;        // normalisierte Lowercase-/Diakritik-freie Variante von `full`
  final Map<String, int> tf; // Token → Häufigkeit

  _Doc({
    required this.id,
    required this.type,
    required this.tsUtc,
    required this.text,
    required this.moodLabel,
    required this.aiQuestion,
    required this.full,
    required this.norm,
    required this.tf,
  });
}

/// Mini-Volltextindex für JournalEntries.
class SearchIndex {
  // ------------------ Storage ------------------
  final Map<String, _Doc> _docs = {}; // id → doc
  final Map<String, Map<String, int>> _postings = {}; // token → (docId → tf)
  int get size => _docs.length;

  // Jitter/Boost-Parameter (manuell feinjustierbar)
  static const double _recencyBoostMax = 0.30;      // bis zu +30 % Bonus
  static const int _recencyWindowDays = 30;         // linearer Abfall über 30 Tage
  static const double _typeBoostReflection = 1.05;  // Reflexion leicht bevorzugen

  // ------------------ Public API ------------------

  /// Komplettes Diff-Syncen aus einer Entry-Liste.
  /// Aktualisiert, fügt hinzu, entfernt was fehlt – effizient.
  void syncFrom(Iterable<JournalEntry> entries) {
    // 1) Index bestehender IDs → schnelle Vergleiche
    final incomingById = <String, JournalEntry>{for (final e in entries) e.id: e};
    final currentIds = Set<String>.from(_docs.keys);

    // 2) Entfernte Dokumente raus
    for (final id in currentIds) {
      if (!incomingById.containsKey(id)) {
        _removeInternal(id);
      }
    }

    // 3) Hinzufügen/Updaten
    for (final e in entries) {
      _upsertFromEntry(e);
    }
  }

  /// Fügt/aktualisiert ein einzelnes Dokument.
  void upsertEntry(JournalEntry e) => _upsertFromEntry(e);

  /// Entfernt Dokument per ID.
  void removeById(String id) => _removeInternal(id);

  /// Leert den gesamten Index.
  void clear() {
    _docs.clear();
    _postings.clear();
  }

  /// Sucht nach Query (case-/diakritik-insensitive). Liefert Ranked-Hits mit Snippets.
  List<SearchHit> search(String query, {SearchOptions opts = const SearchOptions()}) {
    final q = _norm(query);
    if (q.isEmpty || _docs.isEmpty) return const [];

    // Vorab: Query-Token
    final qTokens = _tokenize(q);
    if (qTokens.isEmpty) return const [];

    // 1) Kandidaten sammeln (Union der Postings-Listen; inkl. Prefix-Fallback)
    final Map<String, double> scores = {}; // docId → score
    final Map<String, Set<String>> matchedTokens = {}; // docId → matched qTokens/prefixes

    for (final qt in qTokens) {
      // Exakt
      final exact = _postings[qt];
      if (exact != null) {
        for (final ent in exact.entries) {
          scores[ent.key] = (scores[ent.key] ?? 0) + _tfidf(qt, ent.value);
          (matchedTokens[ent.key] ??= <String>{}).add(qt);
        }
        continue;
      }
      // Prefix-Fallback (kleine Obergrenze, um Kosten zu begrenzen)
      const int prefixCap = 80;
      int seen = 0;
      for (final token in _postings.keys) {
        if (!token.startsWith(qt)) continue;
        final postings = _postings[token]!;
        for (final ent in postings.entries) {
          scores[ent.key] = (scores[ent.key] ?? 0) + 0.66 * _tfidf(token, ent.value); // leicht niedriger
          (matchedTokens[ent.key] ??= <String>{}).add(qt);
        }
        if (++seen >= prefixCap) break;
      }
    }

    if (scores.isEmpty) return const [];

    // 2) Filter + Recency/Type-Boost + Sort
    final nowLocal = DateTime.now();
    final hits = <SearchHit>[];

    for (final ent in scores.entries) {
      final id = ent.key;
      final rawScore = ent.value;
      final doc = _docs[id];
      if (doc == null) continue;

      // Filter: Typ
      if (opts.types != null && !opts.types!.contains(doc.type)) continue;

      // Filter: Datumsfenster (lokale Sicht)
      final local = doc.tsUtc.toLocal();
      if (opts.fromLocal != null && local.isBefore(opts.fromLocal!)) continue;
      if (opts.toLocal != null && !local.isBefore(opts.toLocal!)) continue;

      double score = rawScore;

      // Recency-Boost: linear abnehmend über 30 Tage
      final ageDays =
          nowLocal.difference(DateTime(local.year, local.month, local.day)).inDays.toDouble();
      final recency =
          (ageDays >= _recencyWindowDays) ? 0.0 : (1.0 - ageDays / _recencyWindowDays);
      score *= (1.0 + _recencyBoostMax * recency);

      // Type-Boost
      if (doc.type == JournalType.reflection) {
        score *= _typeBoostReflection;
      }

      final snippet = _makeSnippet(doc, qTokens);
      hits.add(SearchHit(
        id: id,
        score: score,
        snippet: snippet,
        type: doc.type,
        ts: doc.tsUtc,
        matchedTerms: (matchedTokens[id] ?? const <String>{}).toList(),
      ));
    }

    hits.sort((a, b) {
      final d = b.score.compareTo(a.score);
      if (d != 0) return d;
      // Tiebreaker: neuer zuerst
      return b.ts.compareTo(a.ts);
    });

    final limit = opts.limit <= 0 ? 50 : opts.limit;
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  // ------------------ Internals ------------------

  void _upsertFromEntry(JournalEntry e) {
    final id = e.id;
    final prev = _docs[id];

    // Prüfen, ob Indexeintrag noch gültig wäre (billiger Gleichheitscheck)
    if (prev != null) {
      final unchanged = prev.type == e.type &&
          prev.tsUtc == e.createdAt &&
          prev.text == e.text &&
          prev.moodLabel == (e.moodLabel ?? '') &&
          prev.aiQuestion == (e.aiQuestion ?? '');
      if (unchanged) return;
      // sonst: remove & neu indexieren
      _removeInternal(id);
    }

    final full = _concatFields(e.text, e.moodLabel, e.aiQuestion);
    final norm = _norm(full);
    final tf = _termFreq(norm);

    final doc = _Doc(
      id: id,
      type: e.type,
      tsUtc: e.createdAt, // bereits UTC im Model
      text: e.text,
      moodLabel: e.moodLabel ?? '',
      aiQuestion: e.aiQuestion ?? '',
      full: full,
      norm: norm,
      tf: tf,
    );

    _docs[id] = doc;

    // Postings füllen
    for (final kv in tf.entries) {
      final token = kv.key;
      final count = kv.value;
      final posting = (_postings[token] ??= <String, int>{});
      posting[id] = count;
    }
  }

  void _removeInternal(String id) {
    final doc = _docs.remove(id);
    if (doc == null) return;
    // Aus allen Postings entfernen
    for (final token in doc.tf.keys) {
      final p = _postings[token];
      if (p == null) continue;
      p.remove(id);
      if (p.isEmpty) _postings.remove(token);
    }
  }

  // ------------------ Scoring ------------------

  double _tfidf(String token, int tf) {
    final N = _docs.length;
    final df = _postings[token]?.length ?? 0;
    // log(1 + N/(1+df)) … begrenzt und stabil, df=0 tritt praktisch nicht auf
    final idf = math.log(1 + N / (1 + df));
    // sqrt-TF, damit Wiederholung in kurzen Texten nicht übermäßig dominiert
    return math.sqrt(tf.toDouble()) * idf;
  }

  // ------------------ Tokenisierung/Normalisierung ------------------

  // Normierung: trim, lowercase, einfache Diakritika-/Umlaute-Faltung, Mehrfach-Whitespace → 1 Space
  String _norm(String s) {
    if (s.isEmpty) return '';
    final lower = s.toLowerCase().trim();
    final folded = _foldDiacritics(lower);
    return folded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // Faltet diakritische Zeichen auf grobe ASCII-/deutsche Umschreibungen (keine 100%-Garantie).
  String _foldDiacritics(String s) {
    // Schneller Pass: wenn rein ASCII, direkt zurück
    if (RegExp(r'^[\x00-\x7F]+$').hasMatch(s)) return s;

    final buf = StringBuffer();
    for (final ch in s.characters) {
      buf.write(_foldMap[ch] ?? ch);
    }
    return buf.toString();
  }

  // Tokenizer auf Normalform (kein Diakritika mehr), erlaubt Ziffern.
  Iterable<String> _tokenize(String normed) sync* {
    final re = RegExp(r'[a-z0-9]+', caseSensitive: false);
    for (final m in re.allMatches(normed)) {
      final t = m.group(0);
      if (t != null && t.isNotEmpty) yield t;
    }
  }

  Map<String, int> _termFreq(String normed) {
    final tf = <String, int>{};
    for (final t in _tokenize(normed)) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    return tf;
  }

  String _concatFields(String text, String? mood, String? q) {
    final parts = <String>[
      text,
      if ((mood ?? '').trim().isNotEmpty) '[${mood!.trim()}]',
      if ((q ?? '').trim().isNotEmpty) q!.trim(),
    ];
    return parts.join(' ').trim();
  }

  // ------------------ Snippets ------------------

  String _makeSnippet(_Doc doc, List<String> qTokens, {int maxLen = 160}) {
    // 1) Versuche, im Originaltext eine der Query-Phrasen zu finden (case-insensitiv).
    final text = doc.text;
    if (text.trim().isEmpty) {
      final alt = (doc.aiQuestion.isNotEmpty ? doc.aiQuestion : doc.moodLabel).trim();
      return _ellipsis(alt, maxLen);
    }

    // Wir suchen nach der längsten Query-Komponente zuerst
    final sorted = List<String>.from(qTokens)..sort((a, b) => b.length.compareTo(a.length));
    int idx = -1;
    for (final t in sorted) {
      idx = _indexOfCaseFold(text, t);
      if (idx >= 0) break;
    }

    if (idx < 0) {
      // Kein direkter Treffer → fallback auf Anfang + Ellipsis
      return _ellipsis(text, maxLen);
    }

    // Kontextfenster um die Fundstelle
    const int pad = 50;
    final start = (idx - pad).clamp(0, text.length);
    final end = (idx + sorted.first.length + pad).clamp(0, text.length);
    final window = text.substring(start, end);

    return _ellipsis(window, maxLen);
  }

  int _indexOfCaseFold(String haystack, String needle) {
    final h = haystack.toLowerCase();
    final n = needle.toLowerCase();
    final i = h.indexOf(n);
    if (i >= 0) return i;

    // Diakritik-Fallback (langsamer) – nur wenn nötig
    final hf = _foldDiacritics(h);
    final nf = _foldDiacritics(n);
    return hf.indexOf(nf);
  }

  String _ellipsis(String s, int max) {
    final t = s.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= max) return t;
    final cut = t.substring(0, max);
    final lastSpace = cut.lastIndexOf(' ');
    final safe = lastSpace > 40 ? cut.substring(0, lastSpace) : cut;
    return '${safe.trim()}…';
  }
}

// ------------------ Deutsch-zentrierte Faltungstabelle ------------------
// Hinweis: sehr bewusst klein gehalten. Erweitere bei Bedarf.
const Map<String, String> _foldMap = {
  // Deutsch
  'ä': 'ae',
  'ö': 'oe',
  'ü': 'ue',
  'ß': 'ss',
  // Akzente (häufige)
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'ă': 'a',
  'ā': 'a',
  'ç': 'c',
  'č': 'c',
  'ć': 'c',
  'ď': 'd',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ě': 'e',
  'ė': 'e',
  'ē': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ō': 'o',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ș': 's',
  'ť': 't',
  'ț': 't',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'ue', // doppelt, falls Groß/Klein gemischt reinkommt
  'ū': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ž': 'z',
  // Großbuchstaben (Basis)
  'Ä': 'ae',
  'Ö': 'oe',
  'Ü': 'ue',
  'Á': 'a',
  'À': 'a',
  'Â': 'a',
  'Ã': 'a',
  'Å': 'a',
  'Ă': 'a',
  'Ā': 'a',
  'Ç': 'c',
  'Č': 'c',
  'Ć': 'c',
  'Ď': 'd',
  'É': 'e',
  'È': 'e',
  'Ê': 'e',
  'Ë': 'e',
  'Ě': 'e',
  'Ė': 'e',
  'Ē': 'e',
  'Í': 'i',
  'Ì': 'i',
  'Î': 'i',
  'Ï': 'i',
  'Ī': 'i',
  'Ł': 'l',
  'Ñ': 'n',
  'Ń': 'n',
  'Ō': 'o',
  'Ó': 'o',
  'Ò': 'o',
  'Ô': 'o',
  'Õ': 'o',
  'Ř': 'r',
  'Ś': 's',
  'Š': 's',
  'Ș': 's',
  'Ť': 't',
  'Ț': 't',
  'Ú': 'u',
  'Ù': 'u',
  'Û': 'u',
  'Ū': 'u',
  'Ý': 'y',
  'Ÿ': 'y',
  'Ž': 'z',
};

// ------------------ Optional: Provider-Binder ------------------
// Leichter Helfer, der den Index mit einem JournalEntriesProvider synchron hält.
// Nutzt notifyListeners() als Trigger und diffed lokal. Für kleine/mittlere
// Datenmengen ausreichend performant.

class JournalEntriesSearchBinder {
  final ChangeNotifier _provider;
  final Iterable<JournalEntry> Function() _entriesGetter;
  final SearchIndex index;
  VoidCallback? _listener;

  /// [provider] kann z. B. JournalEntriesProvider sein (ChangeNotifier).
  /// [entriesGetter] sollte die aktuelle, DESC-sortierte Liste liefern (z. B. () => provider.entries).
  JournalEntriesSearchBinder(this._provider, this._entriesGetter, this.index);

  void attach() {
    if (_listener != null) return;
    _listener = () {
      // Diff-basiertes Syncen bei jeder Mutation
      index.syncFrom(_entriesGetter());
    };
    // Initial sync
    index.syncFrom(_entriesGetter());
    _provider.addListener(_listener!);
  }

  void detach() {
    final l = _listener;
    if (l != null) {
      _provider.removeListener(l);
      _listener = null;
    }
  }
}
