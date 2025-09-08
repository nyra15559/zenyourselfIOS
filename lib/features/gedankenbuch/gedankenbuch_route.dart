// lib/features/_legacy_gedankenbuch/gedankenbuch_route.dart
//
// GedankenbuchRoute — Oxford-Zen Wrapper (Provider-only)
// ------------------------------------------------------
// Schlanker Wrapper, der die Gedankenbuch-Timeline ohne lokale Fallback-Liste
// betreibt. Alle Aktionen (Add/Edit/Delete) werden sauber an den
// JournalEntriesProvider delegiert.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/journal_entries_provider.dart';
import 'gedankenbuch_timeline.dart';

class GedankenbuchRoute extends StatelessWidget {
  const GedankenbuchRoute({super.key});

  @override
  Widget build(BuildContext context) {
    // Die Timeline nutzt intern den Provider (KANON). Wir geben eine leere
    // Liste und No-Ops für Edit/Delete, damit keine lokalen Items mehr
    // verwaltet werden müssen.
    return GedankenbuchTimelineScreen(
      entries: const [], // ausschließlich Provider-Daten verwenden
      onAdd: (text, mood, {bool isReflection = false}) {
        final p = context.read<JournalEntriesProvider>();
        if (isReflection) {
          // Optional: direkt als Reflexion speichern
          p.addReflection(text: text, moodLabel: mood);
        } else {
          p.addDiary(text: text, moodLabel: mood);
        }
      },
      onEdit: (idx, text, mood, {bool isReflection = false}) {
        // Keine lokalen Items mehr -> kein Edit nötig.
      },
      onDelete: (idx) {
        // Keine lokalen Items mehr -> Delete über Card/Provider.
      },
    );
  }
}
