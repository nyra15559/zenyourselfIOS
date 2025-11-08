// [BASELINE] lib/features/story/story_builder.dart (Stand: 2025-11-07, v6.7.0)
// Kutsche 6 — StoryBuilder
// MERGE SIGNAL v6.7.0:
// • Aggregiert die 5 Kutschen (Identity, Mood, Timeline, Insights, Recall)
//   zu einem kurzen, warmen Narrativ (Titel + Body).
// • Robust gegen fehlende Felder (defensive Parsing).
// • Rein lokal, keine Netz-Abhängigkeit. Optional kann das Ergebnis direkt
//   als Fallback für GuidanceService.story(...) dienen.
// • Ton: Oxford-Zen (ruhig, wertfrei, kurzatmig), keine Therapieaussagen.
//
// Erwartete Memory-Form (tolerant):
// context.memories: {
//   identity: { name: "…" },
//   mood: {
//     last: { ts: "...ISO...", mental: <num or string>, physical: <num or string> },
//     trend: { dir: "up|down|steady", delta: <num?> }
//   },
//   timeline: { items: [ { date:"ISO", topic:"…", mood_delta:<num?> }, ... ] },
//   insights: [ { topic:"…", fact:"…" }, ... ],
//   recall: { weekly:"…", summary:"…" }
// }
//
// Ausgabe: StoryResult (services/guidance/dtos.dart) — { title, body }

import 'dart:math';

import '../../services/guidance/dtos.dart';

/// Öffentliche Fassade: baue aus einem (toleranten) Memory-Map eine Story.
/// `locale` aktuell nur "de" vorgesehen (Default).
class StoryBuilder {
  static StoryResult buildFromMemories(
    Map<String, dynamic>? memories, {
    String locale = 'de',
    int maxSentences = 7,
  }) {
    final ing = StoryIngredients.fromMemories(memories ?? const {});
    return _composeStory(ing, locale: locale, maxSentences: maxSentences);
  }

  static StoryResult build(
    StoryIngredients ingredients, {
    String locale = 'de',
    int maxSentences = 7,
  }) {
    return _composeStory(ingredients, locale: locale, maxSentences: maxSentences);
  }

  // -------- Intern -----------------------------------------------------------

  static StoryResult _composeStory(
    StoryIngredients ing, {
    required String locale,
    required int maxSentences,
  }) {
    // Titelwahl
    final title = _pickTitle(ing);

    // Sätze sammeln (max. ~7, kurze Sätze).
    final lines = <String>[];

    // 1) Auftakt
    lines.add(_opening(ing));

    // 2) Stimmung (last + trend)
    final moodLine = _moodLine(ing);
    if (moodLine != null) lines.add(moodLine);

    // 3) Timeline-Themen
    final topicsLine = _topicsLine(ing);
    if (topicsLine != null) lines.add(topicsLine);

    // 4) Einsichten (max. 2)
    final insightLines = _insightLines(ing, max: 2);
    lines.addAll(insightLines);

    // 5) Recall / Wochenblick
    final recallLine = _recallLine(ing);
    if (recallLine != null) lines.add(recallLine);

    // 6) Abschluss
    lines.add(_closure(locale));

    // Trim auf maxSentences
    final body = lines.take(maxSentences).join(' ');

    return StoryResult(
      title: title,
      body: body.trim(),
    );
  }

  static String _opening(StoryIngredients ing) {
    final name = ing.name?.trim();
    final intro = (name == null || name.isEmpty)
        ? 'Aus deinen letzten Tagen zeichnet sich ein leiser Faden.'
        : 'Aus deinen letzten Tagen, $name, zeichnet sich ein leiser Faden.';
    return intro;
  }

  static String? _moodLine(StoryIngredients ing) {
    final last = ing.lastMood;
    final trend = ing.trend;
    if (last == null && trend == null) return null;

    final head = last != null ? _describeMental(last.mental) : null;
    final body = last != null ? _describePhysical(last.physical) : null;
    final parts = <String>[];

    if (head != null && body != null) {
      parts.add('Im Kopf $head, im Körper $body.');
    } else if (head != null) {
      parts.add('Im Kopf $head.');
    } else if (body != null) {
      parts.add('Im Körper $body.');
    }

    if (trend != null && trend.dir != MoodDirection.unknown) {
      parts.add('Insgesamt ${_trendWord(trend)}.');
    }

    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  static String? _topicsLine(StoryIngredients ing) {
    if (ing.topics.isEmpty) return null;
    final t = ing.topics.take(2).toList();
    if (t.length == 1) {
      return 'Ein wiederkehrendes Thema war ${_quote(t[0])}.';
    } else {
      return 'Wiederkehrende Themen waren ${_quote(t[0])} und ${_quote(t[1])}.';
    }
  }

  static List<String> _insightLines(StoryIngredients ing, {int max = 2}) {
    final out = <String>[];
    if (ing.insights.isEmpty) return out;

    for (final i in ing.insights.take(max)) {
      final topic = (i.topic?.trim().isEmpty ?? true) ? null : i.topic!.trim();
      final fact = (i.fact?.trim().isEmpty ?? true) ? null : i.fact!.trim();

      if (fact != null && topic != null) {
        out.add('Du hast erkannt: ${_quote(fact)} – im Feld ${_quote(topic)}.');
      } else if (fact != null) {
        out.add('Du hast erkannt: ${_quote(fact)}.');
      } else if (topic != null) {
        out.add('Dein Blick blieb öfter bei ${_quote(topic)} stehen.');
      }
    }
    return out;
  }

  static String? _recallLine(StoryIngredients ing) {
    final txt = (ing.recall?.trim().isEmpty ?? true) ? null : ing.recall!.trim();
    if (txt == null) return null;

    // Sanfte Einbettung ohne Bewertung
    return 'Im Rückblick: $txt';
  }

  static String _closure(String locale) {
    // Einheitlicher, kurzer Schluss ohne Frage.
    return 'Du darfst es heute leicht nehmen. Zeit hat keine Eile.';
  }

  static String _pickTitle(StoryIngredients ing) {
    // a) Trend-basiert
    if (ing.trend != null) {
      switch (ing.trend!.dir) {
        case MoodDirection.up:
          return 'Ein Hauch von Leichterwerden';
        case MoodDirection.down:
          return 'Stark geblieben';
        case MoodDirection.steady:
          return 'Ein stiller Faden';
        case MoodDirection.unknown:
          break;
      }
    }
    // b) Themen-basiert
    if (ing.topics.isNotEmpty) {
      final t = ing.topics.first;
      return 'Zwischen ${_titleCase(t)} und dir';
    }
    // c) Fallback
    return 'Deine kleine Geschichte';
    }

  // --- Text-Hilfen -----------------------------------------------------------

  static String _quote(String s) => '„${s.trim()}“';

  static String _titleCase(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    return parts.map((w) {
      if (w.isEmpty) return w;
      final head = w[0].toUpperCase();
      final tail = w.length > 1 ? w.substring(1) : '';
      return '$head$tail';
    }).join(' ');
  }

  static String _trendWord(MoodTrend t) {
    switch (t.dir) {
      case MoodDirection.up:
        return 'ein wenig leichter';
      case MoodDirection.down:
        return 'etwas schwerer';
      case MoodDirection.steady:
        return 'in ruhiger Bahn';
      case MoodDirection.unknown:
        return 'ausgeglichen';
    }
  }

  static String? _describeMental(double? v) {
    if (v == null) return null;
    if (v >= 0.35) return 'klarer geworden';
    if (v <= -0.35) return 'schwer und voll';
    return 'eher neutral';
  }

  static String? _describePhysical(double? v) {
    if (v == null) return null;
    if (v >= 0.35) return 'ruhiger und freier';
    if (v <= -0.35) return 'angespannt und müde';
    return 'im Gleichmaß';
  }
}

/// Datenträger für die 5 Kutschen (ohne Story/Narrativ selbst).
class StoryIngredients {
  final String? name;
  final MoodPoint? lastMood;
  final MoodTrend? trend;
  final List<String> topics; // aus Timeline verdichtet (2–3 Wörter)
  final List<Insight> insights;
  final String? recall; // freier Wochen- / Rückblick-Text

  const StoryIngredients({
    required this.name,
    required this.lastMood,
    required this.trend,
    required this.topics,
    required this.insights,
    required this.recall,
  });

  /// Robuste Extraktion aus einer toleranten Memory-Map.
  factory StoryIngredients.fromMemories(Map<String, dynamic> m) {
    // Identity
    final name = _readStr(m, ['identity', 'name']);

    // Mood last
    final lastMental = _readNumFlex(m, ['mood', 'last', 'mental']);
    final lastPhysical = _readNumFlex(m, ['mood', 'last', 'physical']);
    final last = (lastMental != null || lastPhysical != null)
        ? MoodPoint(mental: _normalizeMood(lastMental), physical: _normalizeMood(lastPhysical))
        : null;

    // Mood trend
    final dirStr = _readStr(m, ['mood', 'trend', 'dir']);
    final delta = _readNumFlex(m, ['mood', 'trend', 'delta']);
    final dir = _toDir(dirStr);
    final trend = (dir != MoodDirection.unknown || delta != null)
        ? MoodTrend(dir: dir, delta: delta)
        : null;

    // Timeline -> Themen
    final rawItems = _readList(m, ['timeline', 'items']);
    final topics = _collectTopicsFromTimeline(rawItems);

    // Insights
    final rawInsights = _readList(m, ['insights']);
    final insights = _collectInsights(rawInsights);

    // Recall
    final recall = _readStr(m, ['recall', 'weekly']) ?? _readStr(m, ['recall', 'summary']);

    return StoryIngredients(
      name: name,
      lastMood: last,
      trend: trend,
      topics: topics,
      insights: insights,
      recall: recall,
    );
  }

  // --- Helpers ---------------------------------------------------------------

  static List<String> _collectTopicsFromTimeline(List<dynamic>? items) {
    if (items == null || items.isEmpty) return <String>[];
    final counts = <String, int>{};

    for (final it in items) {
      if (it is Map<String, dynamic>) {
        final t = _readStr(it, ['topic']) ??
            _readStr(it, ['theme']) ??
            (_readList(it, ['topics'])?.whereType<String>().join(' ') ?? '');
        final compact = _compactTopic(t);
        if (compact.isEmpty) continue;
        counts[compact] = (counts[compact] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return <String>[];
    final sorted = counts.keys.toList()
      ..sort((a, b) => (counts[b]!).compareTo(counts[a]!));
    return sorted.take(4).toList();
  }

  static List<Insight> _collectInsights(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return <Insight>[];
    final out = <Insight>[];
    for (final it in raw) {
      if (it is Map<String, dynamic>) {
        final topic = _readStr(it, ['topic']) ?? _readStr(it, ['tag']);
        final fact = _readStr(it, ['fact']) ?? _readStr(it, ['text']) ?? _readStr(it, ['note']);
        if ((topic != null && topic.trim().isNotEmpty) || (fact != null && fact.trim().isNotEmpty)) {
          out.add(Insight(topic: topic?.trim(), fact: fact?.trim()));
        }
      } else if (it is String) {
        out.add(Insight(topic: null, fact: it.trim()));
      }
    }
    return out;
  }

  static String _compactTopic(String? s) {
    if (s == null) return '';
    final x = s
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\.!?]'), '')
        .trim();
    // Kürzen auf 3 Wörter
    final parts = x.split(' ');
    final cut = parts.take(3).join(' ');
    return cut;
  }

  static double? _normalizeMood(num? v) {
    if (v == null) return null;
    // Akzeptiere Skalen: [-1..1], [0..1], [0..100]
    double d = v.toDouble();
    if (d >= -1.0 && d <= 1.0) return d;
    if (d >= 0.0 && d <= 1.0) return (d * 2) - 1; // 0..1 -> -1..1
    if (d >= 0.0 && d <= 100.0) return (d / 50.0) - 1; // 0..100 -> -1..1
    // Clampen als Sicherheit
    return d.clamp(-1.0, 1.0);
  }

  static MoodDirection _toDir(String? s) {
    switch ((s ?? '').toLowerCase().trim()) {
      case 'up':
      case 'improving':
      case 'better':
        return MoodDirection.up;
      case 'down':
      case 'worse':
      case 'decline':
        return MoodDirection.down;
      case 'steady':
      case 'flat':
      case 'even':
        return MoodDirection.steady;
      default:
        return MoodDirection.unknown;
    }
  }

  static String? _readStr(Map<String, dynamic> m, List<String> path) {
    final v = _read(m, path);
    if (v is String) return v;
    if (v == null) return null;
    return v.toString();
  }

  static num? _readNumFlex(Map<String, dynamic> m, List<String> path) {
    final v = _read(m, path);
    if (v is num) return v;
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      final parsed = num.tryParse(s.replaceAll(',', '.'));
      return parsed;
    }
    return null;
  }

  static List<dynamic>? _readList(Map<String, dynamic> m, List<String> path) {
    final v = _read(m, path);
    if (v is List) return v;
    return null;
  }

  static dynamic _read(Map<String, dynamic> m, List<String> path) {
    dynamic cur = m;
    for (final key in path) {
      if (cur is Map<String, dynamic> && cur.containsKey(key)) {
        cur = cur[key];
      } else {
        return null;
      }
    }
    return cur;
  }
}

/// Letzter Stimmungs-Punkt.
class MoodPoint {
  final double? mental;   // normiert auf [-1..1]
  final double? physical; // normiert auf [-1..1]
  const MoodPoint({this.mental, this.physical});
}

/// Verlauf / Tendenz.
class MoodTrend {
  final MoodDirection dir;
  final num? delta; // optional, metrisch
  const MoodTrend({required this.dir, this.delta});
}

enum MoodDirection { up, down, steady, unknown }

/// Kleine Einsicht (Atomic Fact)
class Insight {
  final String? topic;
  final String? fact;
  const Insight({this.topic, this.fact});
}
