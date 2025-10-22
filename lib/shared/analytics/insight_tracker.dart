// lib/shared/analytics/insight_tracker.dart
//
// InsightTracker — ruhiger Trend-Text aus MemoryStore-Metriken
// ------------------------------------------------------------
// • Analysiert MemoryEntries und liefert Trendtexte/Stats
// • Robuste Behandlung verschiedener Skalen (0..1, 0..100) via Spannweite
// • Store-Variante (async) und List-Variante (sync)
// • Defensive Null- und Leerezustände

import 'dart:math';
import '../../core/memory/memory_store.dart';
import '../../core/memory/memory_entry.dart';

class InsightStats {
  final double? avg;     // Durchschnitt (0..1 oder 0..100, je nach Quelle)
  final double? delta;   // Veränderung ggü. Vorfenster
  final int count;       // Anzahl berücksichtigter Werte (aktuelles Fenster)

  const InsightStats({this.avg, this.delta, required this.count});

  String asText() {
    if (avg == null || count < 3) return 'Einsicht: noch zu wenig Daten';
    final d = (delta ?? 0).toDouble();
    if (d.abs() < 0.03) return 'Einsicht: stabil';
    if (d > 0) {
      if (d >= 0.10) return 'Einsicht: deutlich steigend';
      if (d >= 0.05) return 'Einsicht: leicht steigend';
      return 'Einsicht: sanft steigend';
    } else {
      if (d <= -0.10) return 'Einsicht: deutlich fallend';
      if (d <= -0.05) return 'Einsicht: leicht fallend';
      return 'Einsicht: sanft fallend';
    }
  }
}

class InsightTracker {
  final MemoryStore _store = MemoryStore.instance;

  /// Async-Statistik über die letzten [curWindow] Einträge + Vorfenster [prevWindow].
  Future<InsightStats> compute({int curWindow = 12, int prevWindow = 12}) async {
    final all = await _store.all();
    if (all.isEmpty) {
      return const InsightStats(avg: null, delta: null, count: 0);
    }

    double? avg(List<MemoryEntry> xs) {
      final vals = xs
          .map((e) => e.insightScore?.value)
          .whereType<double>()
          .toList(growable: false);
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    }

    // MemoryStore.all() liefert bereits neueste→älteste sortiert.
    final cur = all.take(curWindow).toList(growable: false);
    final prev = all.skip(cur.length).take(prevWindow).toList(growable: false);

    final aCur = avg(cur);
    final aPrev = avg(prev);
    final delta = (aCur != null && aPrev != null) ? (aCur - aPrev) : null;

    final used = cur.where((e) => e.insightScore?.value != null).length;
    return InsightStats(avg: aCur, delta: delta, count: used);
  }

  /// Kompakter Trend-Text direkt aus dem Store (bequem für UI).
  Future<String> trendTextFromStore({int window = 10}) async {
    final entries = await _store.all();
    return trendTextFromList(entries, window: window);
  }

  /// Trend-Text aus einer beliebigen Entry-Liste (z. B. vorgefiltert).
  /// Erwartet Liste neueste→älteste (wie MemoryStore.all()).
  static String trendTextFromList(List<MemoryEntry> all, {int window = 10}) {
    // Extrahiere numerische Insight-Werte
    final vals = all
        .map((e) => e.insightScore?.value)
        .whereType<double>()
        .toList(growable: false);

    if (vals.isEmpty) return 'Noch keine Einsichten erfasst.';
    if (vals.length == 1) return 'Erste Einsicht erfasst.';

    // Fenster bilden
    final recent = vals.take(window).toList(growable: false);
    final older  = vals.skip(window).take(window).toList(growable: false);

    double? avg(List<double> xs) =>
        xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;

    final a = avg(recent);
    final b = avg(older);

    // Keine aktuelle Basis? -> neutral
    if (a == null) return 'Noch keine Einsichten erfasst.';

    // Wenn kein Baseline-Fenster vorhanden ist, mild pos./neutral formulieren
    if (b == null) return 'Erste Tendenz sichtbar – bleib freundlich dran.';

    final d = a - b;
    final ad = d.abs();

    // Skalen-heuristik: nutze Spannweite der Gesamtdaten als Maßstab
    final scale = _scaleHint(vals);
    final threshSmall = max(0.01, 0.05 * scale);
    final threshBig   = max(0.02, 0.15 * scale);

    if (ad < threshSmall) return 'Stabile Einsichten – ruhig weitermachen.';
    if (d > 0) {
      return ad > threshBig
          ? 'Deine Einsichten werden deutlich klarer.'
          : 'Leichter Aufwärtstrend bei den Einsichten.';
    } else {
      return ad > threshBig
          ? 'Deine Einsichten sind zuletzt deutlich abgeflacht.'
          : 'Leichter Rückgang – völlig normal.';
    }
  }

  static double _scaleHint(List<double> vals) {
    final minV = vals.reduce(min);
    final maxV = vals.reduce(max);
    final span = (maxV - minV).abs();
    return span <= 0 ? 1.0 : span;
    // Bei 0..1 ergibt sich ~1.0; bei 0..100 ≈100 → Schwellen skalieren sinnvoll.
  }
}
