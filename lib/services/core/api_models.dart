// lib/api/models.dart
//
// MERGE SIGNAL: API Models v1.0.0 — Adds minimal result types used by ApiService
// - ReflectionAIResult (const-friendly, JSON helpers, tolerant aliases)
// - ZipCoreResult (binary + filename)
// - Typedefs for pluggable helpers (e.g., classifyMood)
// Zero Flutter deps (only dart:typed_data). Safe to import from anywhere.

import 'dart:typed_data';

/// Optional helper typedefs (can be referenced from ApiService or others).
typedef ClassifyMood = Future<int> Function(String text);

/// Lightweight result object for reflection endpoints / local fallbacks.
/// Keep fields final so we can use `const` where all arguments are compile-time
/// constants. Includes tolerant JSON helpers so callers can round-trip easily.
class ReflectionAIResult {
  /// Whether the operation was successful (non-fatal).
  final bool ok;

  /// Short empathetic reflection/mirror text.
  final String mirror;

  /// Exactly one guiding question for the user.
  final String question;

  /// Up to 3 helper chips (UI suggestions).
  final List<String> answerHelpers;

  /// Optional talk lines (short, warm lines before/after).
  final List<String> talk;

  /// Whether the UI should prompt for mood at this point.
  final bool moodPrompt;

  /// Whether the UI should recommend closing the round.
  final bool recommendEnd;

  /// Risk flag (true for mild/high). UI may show a safety hint.
  final bool risk;

  const ReflectionAIResult({
    this.ok = true,
    this.mirror = '',
    this.question = '',
    this.answerHelpers = const <String>[],
    this.talk = const <String>[],
    this.moodPrompt = false,
    this.recommendEnd = false,
    this.risk = false,
  });

  static const empty = ReflectionAIResult();

  ReflectionAIResult copyWith({
    bool? ok,
    String? mirror,
    String? question,
    List<String>? answerHelpers,
    List<String>? talk,
    bool? moodPrompt,
    bool? recommendEnd,
    bool? risk,
  }) {
    return ReflectionAIResult(
      ok: ok ?? this.ok,
      mirror: mirror ?? this.mirror,
      question: question ?? this.question,
      answerHelpers: answerHelpers ?? this.answerHelpers,
      talk: talk ?? this.talk,
      moodPrompt: moodPrompt ?? this.moodPrompt,
      recommendEnd: recommendEnd ?? this.recommendEnd,
      risk: risk ?? this.risk,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        'mirror': mirror,
        'question': question,
        'answer_helpers': answerHelpers,
        'talk': talk,
        'flow': {
          'mood_prompt': moodPrompt,
          'recommend_end': recommendEnd,
        },
        'risk': risk,
      };

  /// Tolerant parser supporting common aliases:
  /// - mirror: ['mirror','mirror_text']
  /// - answer helpers: ['answer_helpers','helpers','chips']
  /// - flow flags: flow.mood_prompt / flow.recommend_end
  /// - risk: bool risk OR string risk_level ('mild'|'high'→true)
  factory ReflectionAIResult.fromJson(Map<String, dynamic> json) {
    final mirror = _asString(json['mirror']) ?? _asString(json['mirror_text']) ?? '';
    final question = _asString(json['question']) ?? '';

    final helpers =
        _asStringList(json['answer_helpers']) ??
        _asStringList(json['helpers']) ??
        _asStringList(json['chips']) ??
        const <String>[];

    final talk = _asStringList(json['talk']) ?? const <String>[];

    bool moodPrompt = false;
    bool recommendEnd = false;
    final flow = json['flow'];
    if (flow is Map) {
      moodPrompt = _asBool(flow['mood_prompt']) ?? false;
      recommendEnd = _asBool(flow['recommend_end']) ?? false;
    } else {
      // tolerate top-level aliases as well
      moodPrompt = _asBool(json['mood_prompt']) ?? false;
      recommendEnd = _asBool(json['recommend_end']) ?? false;
    }

    bool risk = _asBool(json['risk']) ?? false;
    final riskLevel = _asString(json['risk_level']);
    if (riskLevel != null) {
      final rl = riskLevel.toLowerCase().trim();
      if (rl == 'mild' || rl == 'high') risk = true;
    }

    return ReflectionAIResult(
      ok: _asBool(json['ok']) ?? true,
      mirror: mirror,
      question: question,
      answerHelpers: helpers,
      talk: talk,
      moodPrompt: moodPrompt,
      recommendEnd: recommendEnd,
      risk: risk,
    );
  }
}

/// Simple binary container for zips/exports produced by ApiService.
class ZipCoreResult {
  final Uint8List bytes;
  final String filename;

  const ZipCoreResult({required this.bytes, required this.filename});

  /// Convenience: byte length of the archive.
  int get length => bytes.lengthInBytes;

  /// JSON shell without the raw bytes (for metadata logs if ever needed).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'filename': filename,
        'length': length,
      };
}

// -----------------------
// Minimal parsing helpers
// -----------------------

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

bool? _asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  final s = v.toString().toLowerCase().trim();
  if (s == 'true' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == '0' || s == 'no') return false;
  return null;
}

List<String>? _asStringList(dynamic v) {
  if (v == null) return null;
  if (v is List) {
    return v
        .map((e) => e == null ? null : (e is String ? e : e.toString()))
        .whereType<String>()
        .toList(growable: false);
  }
  // Single string → single-item list
  if (v is String) return <String>[v];
  return null;
}
