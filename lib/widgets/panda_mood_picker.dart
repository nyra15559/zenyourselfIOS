// lib/widgets/panda_mood_picker.dart
//
// PandaMoodPicker — Bottom-Sheet (kompakt)
// - 4 Spalten (bei sehr schmalen Screens 3)
// - Kleine Icons (~36–44dp), ruhige Labels 12–13sp
// - Tap wählt und schließt; "Überspringen" gibt null zurück
// - KEINE Snackbars/Autosave hier

import 'package:flutter/material.dart';
import '../models/panda_mood.dart';

class PandaMoodPicker extends StatefulWidget {
  final void Function(PandaMood mood) onSelected;
  final EdgeInsetsGeometry padding;

  const PandaMoodPicker({
    super.key,
    required this.onSelected,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  State<PandaMoodPicker> createState() => _PandaMoodPickerState();
}

class _PandaMoodPickerState extends State<PandaMoodPicker> {
  late final Future<List<PandaMood>> _moods = PandaMood.loadAll();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<PandaMood>>(
      future: _moods,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Stimmungen konnten nicht geladen werden.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          );
        }

        final moods = snap.data ?? const <PandaMood>[];

        // Sehr schmale Screens → 3 Spalten, sonst 4.
        final w = MediaQuery.of(context).size.width;
        final cols = w < 380 ? 3 : 4;

        return GridView.builder(
          padding: widget.padding,
          itemCount: moods.length,
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            // Etwas höher als breit (Platz für Label)
            childAspectRatio: 0.95,
          ),
          itemBuilder: (context, i) {
            final m = moods[i];
            return _MoodTile(
              mood: m,
              onTap: () => widget.onSelected(m),
            );
          },
        );
      },
    );
  }
}

class _MoodTile extends StatelessWidget {
  final PandaMood mood;
  final VoidCallback onTap;

  const _MoodTile({required this.mood, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Klein und konsistent – kein Expanded, damit die Icons NICHT wachsen.
    // Leicht adaptiv: sehr schmal → 36dp, sonst bis 44dp.
    final screenW = MediaQuery.of(context).size.width;
    final double icon = screenW < 380 ? 36 : 44;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Semantics(
        button: true,
        label: 'Panda Stimmung: ${mood.labelDe}',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: icon,
              width: icon,
              child: Image.asset(
                mood.asset,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mood.labelDe,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium, // ruhiger als labelLarge
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience: zeigt den Picker als Bottom-Sheet.
/// Tap auf ein Item gibt die gewählte Stimmung zurück.
/// „Überspringen“ gibt `null` zurück.
Future<PandaMood?> showPandaMoodPicker(
  BuildContext context, {
  String title = 'Wähle deine Stimmung',
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<PandaMood>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      PandaMood? chosen;

      // Maximal 60% der Höhe, damit nichts erschlägt.
      final maxHeight = MediaQuery.of(context).size.height * 0.60;

      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(chosen),
                    child: const Text('Überspringen'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PandaMoodPicker(
                onSelected: (m) {
                  chosen = m;
                  Navigator.of(context).pop(m);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
