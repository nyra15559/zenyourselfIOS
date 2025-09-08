// lib/features/chat/chat_screen.dart
//
// Zen Chat — Oxford Edition (Provider + ReflectionEntry Storage)
// --------------------------------------------------------------
// • Sanfter Panda-Chat für niederschwellige Selbstreflexion
// • Speichert User-Text/Voice + Panda-Impuls als ReflectionEntry (content-basiert)
// • Lokale Heuristik für Tags/Mood (später leicht gegen GuidanceService austauschbar)
// • Robuste, barrierearme UI mit Zen-Design-Tokens
// • Stabilitäts-Fixes: keine Aktionen nach dispose, Timer statt Future.delayed, mounted-Guards,
//   context-sichere Provider-Zugriffe, defensives Scrollen

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../shared/zen_style.dart';
import '../voice/voice_input.dart';

// Domain-Model + Provider
import '../../data/reflection_entry.dart';
import '../../models/reflection_entries_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// Schlanker Chat-Datensatz (nur für die UI)
class _ChatMessage {
  final String id;
  final String text;
  final bool fromUser; // true = Nutzer:in, false = Panda/Coach
  final DateTime timestamp;

  const _ChatMessage({
    required this.id,
    required this.text,
    required this.fromUser,
    required this.timestamp,
  });
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final ScrollController _scrollCtrl = ScrollController();

  late final AnimationController _pandaBreathCtrl;
  bool _showComposer = false;
  final _rand = Random();

  // Sichere, cancelbare Verzögerungen (kein Future.delayed nach dispose)
  Timer? _coachTimer;

  @override
  void initState() {
    super.initState();
    _pandaBreathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _coachTimer?.cancel();
    _pandaBreathCtrl.dispose();
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    const accent = ZenColors.jadeMid;

    return Stack(
      children: [
        // 1) Ruhige Lottie-Wolken (ohne Screenreader-Lärm)
        Positioned.fill(
          child: ExcludeSemantics(
            child: Lottie.asset(
              'assets/lottie/zen_bg_clouds.json',
              fit: BoxFit.cover,
              repeat: true,
              animate: true,
            ),
          ),
        ),
        // 2) Sanfter Schleier (für Lesbarkeit)
        Positioned.fill(
          child: IgnorePointer(
            child: Container(color: ZenColors.white.withValues(alpha: 0.42)),
          ),
        ),

        // 3) Scaffold
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: ZenColors.white.withValues(alpha: 0.95),
            foregroundColor: ZenColors.jade,
            elevation: 0,
            centerTitle: true,
            title: Text(
              "Zen Chat",
              style: ZenTextStyles.h2.copyWith(fontSize: 21, color: ZenColors.jade),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.tips_and_updates_outlined, color: ZenColors.jadeMid),
                tooltip: "Impuls erhalten",
                onPressed: _pushCoachImpulse,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Panda mit „Atmung“
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: AnimatedBuilder(
                    animation: _pandaBreathCtrl,
                    builder: (_, __) {
                      final scale = 1.0 + 0.03 * _pandaBreathCtrl.value;
                      return Transform.scale(
                        scale: scale,
                        child: Image.asset(
                          "assets/panda.png",
                          width: 64,
                          height: 64,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),
                ),

                // Chatverlauf
                Expanded(
                  child: _messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          key: const PageStorageKey('zen_chat_list'),
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
                          reverse: true, // neueste unten
                          itemCount: _messages.length,
                          itemBuilder: (_, i) {
                            final msg = _messages[_messages.length - 1 - i];
                            final isUser = msg.fromUser;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Align(
                                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                child: Semantics(
                                  label: isUser ? 'Deine Nachricht' : 'Zen Panda',
                                  child: ZenBubble(
                                    color: isUser
                                        ? ZenColors.white.withValues(alpha: 0.96)
                                        : ZenColors.sand.withValues(alpha: 0.38),
                                    borderRadius: isUser
                                        ? const BorderRadius.only(
                                            topLeft: Radius.circular(21),
                                            topRight: Radius.circular(21),
                                            bottomLeft: Radius.circular(21),
                                            bottomRight: Radius.circular(8),
                                          )
                                        : const BorderRadius.only(
                                            topLeft: Radius.circular(21),
                                            topRight: Radius.circular(21),
                                            bottomLeft: Radius.circular(8),
                                            bottomRight: Radius.circular(21),
                                          ),
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          msg.text,
                                          style: ZenTextStyles.body.copyWith(
                                            fontSize: isUser ? 16.8 : 15.6,
                                            fontWeight: isUser ? FontWeight.w600 : FontWeight.w400,
                                            color: ZenColors.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _fmtTime(msg.timestamp),
                                          style: ZenTextStyles.caption.copyWith(
                                            fontSize: 12.4,
                                            color: ZenColors.jadeMid.withValues(alpha: 0.62),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Composer (Text + Voice)
                AnimatedSwitcher(
                  duration: animShort,
                  child: _showComposer ? _buildComposer(accent) : _buildCTA(accent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ZenBubble(
        color: ZenColors.white,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.spa_rounded, color: ZenColors.jadeMid, size: 44),
            const SizedBox(height: 11),
            Text("Was beschäftigt dich gerade?", style: ZenTextStyles.h3.copyWith(fontSize: 19.2)),
            const SizedBox(height: 9),
            Text(
              "Sprich oder tippe deine Gedanken.\nDeine Reflexion bleibt privat.",
              style: ZenTextStyles.caption.copyWith(color: ZenColors.jadeMid.withValues(alpha: 0.83)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
            ZenButton(
              label: "Reflexion starten",
              icon: Icons.edit_rounded,
              onPressed: () => _safeSetState(() => _showComposer = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCTA(Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: FloatingActionButton.extended(
        heroTag: "chat_reflect_fab",
        backgroundColor: accent,
        icon: const Icon(Icons.spa),
        label: const Text("Reflektieren", style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _safeSetState(() => _showComposer = true),
      ),
    );
  }

  Widget _buildComposer(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
      child: ZenBubble(
        color: ZenColors.white,
        borderRadius: BorderRadius.circular(17),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Voice-Input (optional)
            VoiceInputWidget(
              hint: "Sprich deine Gedanken …",
              onResult: (transcript, emotion) {
                final t = transcript.trim();
                if (t.isEmpty) return;
                _addUserAndCoach(t, source: "voice");
                _safeSetState(() => _showComposer = false);
                _controller.clear();
              },
            ),
            const SizedBox(height: 10),
            // Text-Eingabe
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: "Oder tippe hier deine Gedanken …",
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: ZenColors.outline.withValues(alpha: 0.8)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: ZenColors.focus, width: 2),
                      ),
                    ),
                    onSubmitted: _onSubmitText,
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: "Reflexion absenden",
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: ZenColors.jadeMid, size: 26),
                    onPressed: () => _onSubmitText(_controller.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- Interaktionen ----
  void _onSubmitText(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _addUserAndCoach(t, source: "manual");
    _safeSetState(() => _showComposer = false);
    _controller.clear();
  }

  void _pushCoachImpulse() {
    final impulse = _generateZenImpulse("");
    _addCoachOnly(impulse, persist: true); // nur Impuls anzeigen & speichern
  }

  void _addUserAndCoach(String userText, {required String source}) {
    _addUser(userText, persist: true, source: source);

    // leichte Verzögerung für „natürliches“ Gefühl – cancelbar
    _coachTimer?.cancel();
    _coachTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _addCoachOnly(_generateZenImpulse(userText), persist: true);
    });
  }

  void _addUser(String text, {bool persist = false, required String source}) {
    final now = DateTime.now();
    _messages.add(_ChatMessage(
      id: _id(),
      text: text,
      fromUser: true,
      timestamp: now,
    ));
    if (persist && mounted) {
      _persistReflection(
        content: text,
        source: source, // "manual" | "voice"
        // Lokale Heuristiken (mood/tags) — später gegen GuidanceService austauschbar
        moodScore: _classifyMoodLocal(text),
        tags: _suggestTagsLocal(text),
      );
    }
    _jumpToBottom();
    _safeSetState(() {});
  }

  void _addCoachOnly(String text, {bool persist = false}) {
    final now = DateTime.now();
    _messages.add(_ChatMessage(
      id: _id(),
      text: text,
      fromUser: false,
      timestamp: now,
    ));
    if (persist && mounted) {
      _persistReflection(
        content: text,
        source: "coach",
        category: "Impulse",
      );
    }
    _jumpToBottom();
    _safeSetState(() {});
  }

  void _jumpToBottom() {
    if (!mounted) return;
    if (!_scrollCtrl.hasClients) {
      // Nach dem nächsten Frame erneut versuchen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo(0);
      });
      return;
    }
    // Da die Liste reversed ist, springen wir an den Anfang
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  // ---- Persistenz mit ReflectionEntriesProvider ----
  void _persistReflection({
    required String content,
    required String source,
    String? category,
    int? moodScore,
    List<String>? tags,
  }) {
    if (!mounted) return;
    final entry = ReflectionEntry(
      timestamp: DateTime.now(),
      content: content,
      moodDayTag: _dayTag(DateTime.now()),
      moodScore: moodScore,
      category: category,
      tags: tags,
      aiSummary: null,
      audioPath: null,
      source: source,
    );
    // Kontext-sicherer Provider-Zugriff (nur wenn noch gemountet)
    context.read<ReflectionEntriesProvider>().add(entry);
  }

  // ---- Hilfen ----
  String _fmtTime(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();

  String _dayTag(DateTime dt) =>
      "${dt.year.toString().padLeft(4, '0')}-"
      "${dt.month.toString().padLeft(2, '0')}-"
      "${dt.day.toString().padLeft(2, '0')}";

  String _generateZenImpulse(String input) {
    // kleine, freundliche, nicht-direktive Impulse
    const pool = [
      "Was wäre heute ein 1%-Schritt in Richtung Ruhe?",
      "Wenn du kurz innehältst: Was tut dir jetzt gut?",
      "Was darf heute unperfekt sein — und trotzdem okay?",
      "Welcher kleine Gedanke schenkt dir gerade Entlastung?",
      "Wenn du sanft auf das Thema blickst: Was ist ein nächster, machbarer Schritt?",
      "Was würdest du einem guten Freund in dieser Lage raten?",
    ];
    // deterministische, aber leicht variierende Auswahl
    final idx = (_rand.nextInt(1000) + DateTime.now().second) % pool.length;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return pool[idx];
    final hint = trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed;
    return "${pool[idx]}\n\n(Bezug: $hint)";
  }

  // Sehr einfache, lokale Heuristiken (können 1:1 gegen GuidanceService getauscht werden)
  int? _classifyMoodLocal(String text) {
    final t = text.toLowerCase();
    if (_any(t, ['panik', 'schlecht', 'hoffnungslos', 'nutzlos'])) return 0;
    if (_any(t, ['müde', 'niedrig', 'erschöpft', 'überfordert'])) return 1;
    if (_any(t, ['okay', 'neutral', 'so lala'])) return 2;
    if (_any(t, ['gut', 'klar', 'ruhig', 'stabil'])) return 3;
    if (_any(t, ['stark', 'erfüllt', 'dankbar', 'zuversichtlich'])) return 4;
    return null;
  }

  List<String> _suggestTagsLocal(String text) {
    final out = <String>{};
    final t = text.toLowerCase();
    if (_any(t, ['arbeit', 'job', 'projekt'])) out.add('Arbeit');
    if (_any(t, ['famil', 'partner', 'freund'])) out.add('Beziehungen');
    if (_any(t, ['schlaf', 'müde', 'wach'])) out.add('Schlaf');
    if (_any(t, ['angst', 'sorge', 'unsicher'])) out.add('Ängste');
    if (_any(t, ['dankbar', 'freu', 'stolz'])) out.add('Dankbarkeit');
    return out.take(3).toList();
  }

  bool _any(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    // Vorsicht, falls ein Build gerade läuft
    // (defer, um setState-during-build zu vermeiden)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(fn);
    });
  }
}
