// lib/features/community/custom_questions.dart
//
// CustomQuestionsScreen — Oxford Zen Edition
// ------------------------------------------
// • User-generierte Fragen: erstellen, upvoten, favorisieren
// • Persistenz lokal (keine Cloud): Fragen + abgegebene Votes
// • Sanftes, glasiges UI mit Zen-Bubbles (aus zen_widgets.dart)
// • A11y: Semantics, klare Labels, große Tap-Ziele
// • Sanity-Checks: Länge, Duplikat-Check (normalisiert), leichte Entschärfung
// • Timestamps in UTC für stabile Sortierung/Export

import 'package:flutter/material.dart';
import 'package:zenyourself/shared/zen_style.dart';
import 'package:zenyourself/shared/ui/zen_widgets.dart';
import 'package:zenyourself/services/local_storage.dart';

class CustomQuestionsScreen extends StatefulWidget {
  const CustomQuestionsScreen({super.key});

  @override
  State<CustomQuestionsScreen> createState() => _CustomQuestionsScreenState();
}

class _CustomQuestionsScreenState extends State<CustomQuestionsScreen> {
  final _storage = LocalStorageService();

  // State
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();

  final List<_CustomQuestion> _questions = <_CustomQuestion>[];
  final Set<String> _votedIds = <String>{}; // je Frage-ID max. 1 Vote
  bool _showForm = false;
  bool _loading = true;

  static const _storeQuestionsKey = 'custom_questions_v1';
  static const _storeVotesKey = 'custom_questions_voted_ids_v1';

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    await _storage.init();

    // Votes laden
    final voted = await _storage.loadJson<List<dynamic>>(_storeVotesKey, null);
    if (voted != null) {
      _votedIds.addAll(voted.map((e) => e.toString()));
    }

    // Fragen laden
    final list = await _storage.loadJson<List<dynamic>>(_storeQuestionsKey, null);
    if (list != null) {
      _questions
        ..clear()
        ..addAll(
          list.map((e) => _CustomQuestion.fromJson(Map<String, dynamic>.from(e))),
        );
    } else {
      // Seed-Daten (lokal)
      final now = DateTime.now().toUtc();
      _questions.addAll([
        _CustomQuestion(text: "Was hat dich heute wirklich berührt?", votes: 13, createdAt: now),
        _CustomQuestion(text: "Wofür bist du dir selbst gerade dankbar?", votes: 21, createdAt: now),
        _CustomQuestion(text: "Wann warst du zuletzt ehrlich zu dir selbst?", votes: 7, createdAt: now),
      ]);
      await _persistQuestions();
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persistQuestions() async {
    try {
      await _storage.saveJson(
        _storeQuestionsKey,
        _questions.map((q) => q.toJson()).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ZenToast.show(context, "Konnte Fragen nicht speichern.");
    }
  }

  Future<void> _persistVotes() async {
    try {
      await _storage.saveJson(_storeVotesKey, _votedIds.toList());
    } catch (e) {
      if (!mounted) return;
      ZenToast.show(context, "Konnte Stimme nicht speichern.");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  // --- Actions ---------------------------------------------------------------

  void _toggleForm() {
    setState(() => _showForm = !_showForm);
    if (_showForm) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _fieldFocus.requestFocus();
      });
    }
  }

  void _submitQuestion() async {
    final raw = _controller.text;
    final text = _sanitize(raw).trim();
    if (text.isEmpty) return;

    // Sanity: Länge
    if (text.length < 10) {
      ZenToast.show(context, "Bitte formuliere deine Frage etwas ausführlicher.");
      return;
    }
    if (text.length > 160) {
      ZenToast.show(context, "Max. 160 Zeichen, bitte leicht kürzen.");
      return;
    }

    // Duplikat-Check (normalisiert: trim + Mehrfach-Whitespace -> 1)
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final dup = _questions.any((q) => norm(q.text) == norm(text));
    if (dup) {
      ZenToast.show(context, "Diese Frage gibt es bereits.");
      return;
    }

    setState(() {
      _questions.insert(
        0,
        _CustomQuestion(
          text: text,
          votes: 1,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      _showForm = false;
      _controller.clear();
    });

    await _persistQuestions();
    ZenToast.show(context, "Danke für deine Inspiration 🌱");
  }

  void _voteQuestion(_CustomQuestion q) async {
    if (_votedIds.contains(q.id)) return;
    final idx = _questions.indexWhere((e) => e.id == q.id);
    if (idx == -1) return;

    setState(() {
      _questions[idx] = _questions[idx].copyWith(votes: _questions[idx].votes + 1);
      _votedIds.add(q.id);
    });
    await _persistQuestions();
    await _persistVotes();
  }

  void _toggleFavorite(_CustomQuestion q) async {
    final idx = _questions.indexWhere((e) => e.id == q.id);
    if (idx == -1) return;

    setState(() {
      _questions[idx] = _questions[idx].copyWith(favorite: !_questions[idx].favorite);
    });
    await _persistQuestions();
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    const accent = ZenColors.jade;

    return ZenScaffold(
      appBar: ZenAppBar(
        title: "Deine Fragen an die Community",
        actions: [
          IconButton(
            tooltip: _showForm ? "Formular schließen" : "Neue Frage einreichen",
            icon: Icon(_showForm ? Icons.close : Icons.add_circle, color: accent),
            onPressed: _toggleForm,
          ),
        ],
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZenBubble(
                  color: accent.withOpacity(0.10),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.forum_rounded, color: ZenColors.jadeMid),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Welche Frage würdest du gerne in die Community geben? "
                          "Teile deine Inspiration – anonym, freundlich, respektvoll.",
                          style: ZenTextStyles.body.copyWith(fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: Icon(_showForm ? Icons.expand_less : Icons.expand_more, color: accent),
                        onPressed: _toggleForm,
                        tooltip: _showForm ? "Formular schließen" : "Formular öffnen",
                      ),
                    ],
                  ),
                ),

                // Formular
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _showForm
                      ? ZenBubble(
                          key: const ValueKey('form'),
                          color: ZenColors.white,
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                textField: true,
                                label: "Eigene Frage eingeben",
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _fieldFocus,
                                  maxLength: 160,
                                  minLines: 2,
                                  maxLines: 4,
                                  style: ZenTextStyles.body.copyWith(fontSize: 16.2),
                                  decoration: const InputDecoration(
                                    hintText: "Deine Frage …",
                                    border: InputBorder.none,
                                    counterText: "",
                                  ),
                                  onSubmitted: (_) => _submitQuestion(),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.send),
                                    label: const Text("Einreichen"),
                                    onPressed: _submitQuestion,
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 6),

                // Liste
                Expanded(
                  child: _questions.isEmpty
                      ? Center(
                          child: ZenBubble(
                            color: ZenColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
                            child: Text(
                              "Noch keine Fragen – sei die*der Erste 🌿",
                              style: ZenTextStyles.body.copyWith(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: ZenColors.jadeMid,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _questions.length,
                          itemBuilder: (ctx, i) {
                            final q = _questions[i];
                            final hasVoted = _votedIds.contains(q.id);

                            return ZenBubble(
                              color: ZenColors.white,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Upvote
                                  Semantics(
                                    button: true,
                                    label: hasVoted
                                        ? "Bereits abgestimmt. ${q.votes} Stimmen."
                                        : "Abstimmen. Aktuell ${q.votes} Stimmen.",
                                    child: IconButton(
                                      iconSize: 26,
                                      icon: Icon(
                                        Icons.arrow_upward_rounded,
                                        color: hasVoted ? ZenColors.sage : accent,
                                      ),
                                      onPressed: hasVoted ? null : () => _voteQuestion(q),
                                      tooltip: hasVoted ? "Du hast bereits abgestimmt" : "Upvoten",
                                    ),
                                  ),

                                  // Count
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Text(
                                      "${q.votes}",
                                      style: ZenTextStyles.h3.copyWith(
                                        fontSize: 16.5,
                                        color: accent,
                                      ),
                                    ),
                                  ),

                                  // Text
                                  Expanded(
                                    child: Text(
                                      q.text,
                                      style: ZenTextStyles.body.copyWith(
                                        fontSize: 15.8,
                                        fontWeight: FontWeight.w600,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),

                                  // Favorit
                                  IconButton(
                                    icon: Icon(
                                      q.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                                      color: q.favorite ? ZenColors.gold : ZenColors.jadeMid,
                                    ),
                                    tooltip: q.favorite ? "Aus Favoriten entfernen" : "Zu Favoriten",
                                    onPressed: () => _toggleFavorite(q),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  // sehr vorsichtige, lokal/offline „Entschärfung“
  String _sanitize(String s) {
    // leichte Heuristik – vermeidet das Speichern roher Beleidigungen
    const blocked = ['scheiße', 'blödmann'];
    var out = s;
    for (final b in blocked) {
      out = out.replaceAll(RegExp(b, caseSensitive: false), '…');
    }
    return out;
  }
}

// ============================================================================
// Lokales Model (bewusst nicht global, um Konflikte mit models/question.dart
// zu vermeiden). Minimal + robust serialisierbar. UTC-Zeitstempel.
// ============================================================================
class _CustomQuestion {
  final String id;
  final String text;
  final int votes;
  final DateTime createdAt; // UTC
  final bool favorite;

  _CustomQuestion({
    String? id,
    required this.text,
    this.votes = 1,
    DateTime? createdAt,
    this.favorite = false,
  })  : id = id ?? DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
        createdAt = (createdAt ?? DateTime.now().toUtc());

  _CustomQuestion copyWith({
    String? id,
    String? text,
    int? votes,
    DateTime? createdAt,
    bool? favorite,
  }) {
    return _CustomQuestion(
      id: id ?? this.id,
      text: text ?? this.text,
      votes: votes ?? this.votes,
      createdAt: createdAt ?? this.createdAt,
      favorite: favorite ?? this.favorite,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'votes': votes,
        'createdAt': createdAt.toIso8601String(),
        'favorite': favorite,
      };

  factory _CustomQuestion.fromJson(Map<String, dynamic> j) => _CustomQuestion(
        id: j['id'] as String?,
        text: (j['text'] as String?)?.trim() ?? '',
        votes: (j['votes'] as num?)?.toInt() ?? 1,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        favorite: j['favorite'] as bool? ?? false,
      );
}
