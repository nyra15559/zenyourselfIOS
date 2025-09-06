// lib/features/community/question_voting.dart
//
// CommunityQuestionVoting — Oxford Zen Edition
// --------------------------------------------
// • Sanftes, glasiges Layout mit Zen-DNA (Farben/Typo aus zen_style.dart)
// • Lokales Upvote-Tracking (persistiert), 1 Vote pro Frage/Device
// • A11y: Semantics, große Tap-Ziele, klare Statusmeldungen
// • Saubere State- und Animations-Logik, deterministische Sortierung

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:zenyourself/models/community_question.dart';
import 'package:zenyourself/shared/ui/zen_widgets.dart';
import 'package:zenyourself/shared/zen_style.dart';
import 'package:zenyourself/services/local_storage.dart';

enum _SortMode { top, neu }

class CommunityQuestionVoting extends StatefulWidget {
  const CommunityQuestionVoting({Key? key}) : super(key: key);

  @override
  State<CommunityQuestionVoting> createState() => _CommunityQuestionVotingState();
}

class _CommunityQuestionVotingState extends State<CommunityQuestionVoting>
    with SingleTickerProviderStateMixin {
  final _storage = LocalStorageService();

  late List<CommunityQuestion> _questions;
  final Set<String> _votedIds = {};
  _SortMode _sort = _SortMode.top;

  String? _toastMessage;
  late AnimationController _toastController;

  static const _votedKey = 'community_voted_ids_v1';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _questions = [
      CommunityQuestion(id: '1', text: "Hast du heute etwas über dich gelernt?", votes: 8, createdAt: now),
      CommunityQuestion(id: '2', text: "Hat dir ZenYourSelf heute geholfen?", votes: 6, createdAt: now.subtract(const Duration(minutes: 3))),
      CommunityQuestion(id: '3', text: "Wünschst du dir mehr Features in ZenYourSelf?", votes: 10, createdAt: now.subtract(const Duration(minutes: 5))),
    ];
    _toastController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _loadVoted();
  }

  Future<void> _loadVoted() async {
    await _storage.init();
    final raw = await _storage.loadJson<List<dynamic>>(_votedKey, null);
    if (raw != null) {
      setState(() => _votedIds.addAll(raw.map((e) => e.toString())));
    }
  }

  Future<void> _persistVoted() async {
    await _storage.saveJson(_votedKey, _votedIds.toList());
  }

  @override
  void dispose() {
    _toastController.dispose();
    super.dispose();
  }

  void _vote(String id) async {
    final idx = _questions.indexWhere((q) => q.id == id);
    if (idx == -1 || _votedIds.contains(id)) return;

    setState(() {
      _questions[idx] = _questions[idx].copyWith(votes: _questions[idx].votes + 1);
      _votedIds.add(id);
      _toastMessage = "Danke für deine Wertschätzung 🌱";
    });
    _persistVoted();

    _toastController.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _toastMessage = null);
  }

  List<CommunityQuestion> get _sorted {
    final list = [..._questions];
    switch (_sort) {
      case _SortMode.top:
        list.sort((a, b) {
          final byVotes = b.votes.compareTo(a.votes);
          return byVotes != 0 ? byVotes : a.createdAt.compareTo(b.createdAt);
        });
        break;
      case _SortMode.neu:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1) Softes Community-Backdrop
          Positioned.fill(
            child: Image.asset(
              'assets/startbild5.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          // 2) Nebelschleier oben
          Positioned(
            top: 0, left: 0, right: 0, height: 160,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.20), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          // 3) Glas-Karte mit Inhalt
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 11, sigmaY: 11),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    decoration: BoxDecoration(
                      color: ZenColors.white.withOpacity(0.82),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [ZenShadows.card],
                      border: Border.all(color: ZenColors.jadeMid.withOpacity(0.08), width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Text(
                            "Raum für echte Inspiration",
                            textAlign: TextAlign.center,
                            style: ZenTextStyles.h2.copyWith(
                              fontSize: 23,
                              color: ZenColors.jade,
                              shadows: const [Shadow(blurRadius: 8, color: Colors.white24, offset: Offset(0, 2))],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Teile, was dich bewegt. Lass dich berühren.",
                            textAlign: TextAlign.center,
                            style: ZenTextStyles.body.copyWith(
                              color: ZenColors.jadeMid,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Sort / Filter
                          _SortChips(
                            mode: _sort,
                            onChanged: (m) => setState(() => _sort = m),
                          ),

                          const SizedBox(height: 8),

                          // Fragenliste
                          ..._sorted.map((q) => _QuestionBubble(
                                q: q,
                                hasVoted: _votedIds.contains(q.id),
                                onVote: () => _vote(q.id),
                              )),

                          const SizedBox(height: 14),
                          // CTA: Frage stellen (Stub)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add_comment_rounded, color: ZenColors.jade),
                            label: const Text("Frage stellen"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ZenColors.jade,
                              side: const BorderSide(color: ZenColors.jade, width: 1.2),
                              backgroundColor: Colors.white.withOpacity(0.75),
                              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            ),
                            onPressed: () => ZenToast.show(context, "Fragen posten – kommt bald!"),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Dein Beitrag bleibt anonym. Jeder Gedanke zählt.",
                            textAlign: TextAlign.center,
                            style: ZenTextStyles.caption.copyWith(color: ZenColors.inkSubtle),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 4) Dankes-Toast
          if (_toastMessage != null)
            Positioned(
              bottom: 44, left: 0, right: 0,
              child: FadeTransition(
                opacity: CurvedAnimation(parent: _toastController, curve: Curves.easeInOut),
                child: Center(
                  child: Semantics(
                    label: _toastMessage!,
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 22),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(23),
                        boxShadow: [ZenShadows.card],
                        border: Border.all(color: ZenColors.jadeMid.withOpacity(0.10)),
                      ),
                      child: Text(
                        _toastMessage!,
                        style: ZenTextStyles.body.copyWith(
                          color: ZenColors.jade,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------- Widgets --------------------

class _SortChips extends StatelessWidget {
  final _SortMode mode;
  final ValueChanged<_SortMode> onChanged;
  const _SortChips({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(_SortMode m, String label) {
      final selected = mode == m;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onChanged(m),
          labelStyle: ZenTextStyles.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : ZenColors.jade,
          ),
          backgroundColor: ZenColors.white,
          selectedColor: ZenColors.jade,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: ZenColors.jade.withOpacity(0.20)),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        chip(_SortMode.top, "Top"),
        chip(_SortMode.neu, "Neu"),
      ],
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  final CommunityQuestion q;
  final bool hasVoted;
  final VoidCallback onVote;

  const _QuestionBubble({
    required this.q,
    required this.hasVoted,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = hasVoted ? ZenColors.sage : ZenColors.jadeMid;
    final bg = hasVoted ? ZenColors.sage.withOpacity(0.12) : Colors.white.withOpacity(0.98);

    return Semantics(
      container: true,
      label:
          "Frage: ${q.text}. Aktuelle Stimmen: ${q.votes}. ${hasVoted ? "Bereits abgestimmt." : "Zum Abstimmen tippen."}",
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(19),
          boxShadow: hasVoted ? [] : [ZenShadows.soft],
          border: Border.all(color: baseColor.withOpacity(hasVoted ? 0.40 : 0.12), width: 1.1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.bubble_chart_rounded, color: ZenColors.jadeMid, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                q.text,
                style: ZenTextStyles.body.copyWith(
                  fontSize: 16.5,
                  height: 1.28,
                  color: ZenColors.inkStrong,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _VoteButton(
              votes: q.votes,
              hasVoted: hasVoted,
              onTap: onVote,
            ),
          ],
        ),
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final int votes;
  final bool hasVoted;
  final VoidCallback onTap;

  const _VoteButton({
    required this.votes,
    required this.hasVoted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = hasVoted ? ZenColors.sage : ZenColors.jade;
    return Semantics(
      button: true,
      label: hasVoted ? "Bereits abgestimmt. $votes Stimmen." : "Abstimmen. Aktuell $votes Stimmen.",
      child: GestureDetector(
        onTap: hasVoted ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(15),
            boxShadow: hasVoted ? [] : [ZenShadows.soft],
          ),
          child: Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 5),
              Text(
                "$votes",
                style: ZenTextStyles.button.copyWith(fontSize: 15.5, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
