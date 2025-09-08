import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/journal_entries_provider.dart';
import 'gedankenbuch_timeline.dart';

/// Schlanker Wrapper, damit die Timeline ohne lokale Fallback-Liste läuft.
/// Er reicht Provider-Aktionen sauber durch (Add/Edit/Delete greifen auf den Provider).
class GedankenbuchRoute extends StatelessWidget {
  const GedankenbuchRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return GedankenbuchTimelineScreen(
      entries: const [], // Wir nutzen ausschließlich den Provider.
      onAdd: (text, mood, {bool isReflection = false}) {
        final p = context.read<JournalEntriesProvider>();
        // Aktuell: Tagebuch-Eintrag; wenn du Reflexion direkt anlegen willst,
        // kannst du hier p.addReflection(...) verwenden.
        p.addDiary(text: text, moodLabel: mood);
      },
      onEdit: (idx, text, mood, {bool isReflection = false}) {
        // Keine lokalen Items mehr -> nichts zu tun (Provider hat eigene Edit-Flows).
      },
      onDelete: (idx) {
        // Keine lokalen Items mehr -> nichts zu tun (Provider-Delete via Card-Menü).
      },
    );
  }
}
