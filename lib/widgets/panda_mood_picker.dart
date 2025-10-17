// lib/widgets/panda_mood_picker.dart
//
// PandaMoodPicker — Bottom-Sheet (kompakt, a11y-freundlich)
// - 4 Spalten (bei sehr schmalen Screens 3)
// - Kleine Icons (~36–44dp), ruhige Labels 12–13sp
// - Tap wählt und schließt; "Überspringen" gibt null zurück
// - KEINE Snackbars/Autosave hier
//
// WICHTIG:
// • Kein rootNavigator-Pop & Reentrancy-Guard → verhindert Doppel-Pop/Zurückspringen
// • A11y: klare Semantics-Labels, Buttons korrekt ausgezeichnet

import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late Future<List<PandaMood>> _moods;

  @override
  void initState() {
    super.initState();
    _moods = _loadMoods();
  }

  Future<List<PandaMood>> _loadMoods() async {
    if (kDebugMode) debugPrint('[PandaMoodPicker] Lade Stimmungen …');
    try {
      final list = await PandaMood.loadAll().timeout(const Duration(seconds: 5));
      if (kDebugMode) debugPrint('[PandaMoodPicker] ${list.length} Stimmungen geladen');
      return list;
    } on TimeoutException {
      if (kDebugMode) debugPrint('[PandaMoodPicker] Timeout beim Laden');
      return const <PandaMood>[];
    } catch (e) {
      if (kDebugMode) debugPrint('[PandaMoodPicker] Fehler: $e');
      return const <PandaMood>[];
    }
  }

  @override
  Widget build(BuildContext context) {
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
          return _ErrorView(
            message: 'Stimmungen konnten nicht geladen werden.',
            onRetry: () => setState(() => _moods = _loadMoods()),
          );
        }

        final moods = snap.data ?? const <PandaMood>[];
        if (moods.isEmpty) {
          return _ErrorView(
            message: 'Keine Stimmungen gefunden.',
            onRetry: () => setState(() => _moods = _loadMoods()),
          );
        }

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
            childAspectRatio: 0.95, // etwas höher als breit – Platz fürs Label
          ),
          itemBuilder: (context, i) {
            final m = moods[i];
            return _MoodTile(
              mood: m,
              onTap: () {
                HapticFeedback.selectionClick();
                // WICHTIG: Hier KEIN Pop! (Schließen steuert der Sheet-Builder)
                widget.onSelected(m);
              },
            );
          },
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ],
      ),
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
        label: 'Stimmung wählen: ${mood.labelDe}',
        hint: 'Doppeltippen zum Auswählen',
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
/// „Überspringen“ oder dismiss gibt `null` zurück.
///
/// [onDismissed] wird aufgerufen, wenn das Sheet ohne Auswahl geschlossen wurde.
Future<PandaMood?> showPandaMoodPicker(
  BuildContext context, {
  String title = 'Wähle deine Stimmung',
  VoidCallback? onDismissed,
}) {
  final theme = Theme.of(context);

  final fut = showModalBottomSheet<PandaMood>(
    context: context,
    useRootNavigator: false, // WICHTIG: im lokalen Navigator bleiben
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true, // falls verfügbar
    barrierColor: theme.colorScheme.scrim.withValues(alpha: .35),
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      PandaMood? chosen;
      final closing = ValueNotifier<bool>(false); // Reentrancy-Guard

      // Maximal 60% der Höhe, damit nichts erschlägt.
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.60;

      if (kDebugMode) {
        debugPrint('[PandaMoodPicker] Sheet geöffnet (maxHeight=${maxHeight.toStringAsFixed(0)}).');
      }

      void safePop([PandaMood? value]) {
        if (closing.value) return;
        closing.value = true;
        Navigator.of(sheetContext).pop(value);
      }

      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // (Drag-Handle wird von showDragHandle gezeichnet; hier dezenter Balken als Fallback)
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
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Überspringen, keine Stimmung wählen',
                    child: TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        // Nur Sheet schließen (kein Root-Pop)
                        safePop(chosen); // gibt null zurück
                      },
                      child: const Text('Überspringen'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PandaMoodPicker(
                onSelected: (m) {
                  if (closing.value) return;
                  chosen = m;
                  HapticFeedback.selectionClick();
                  // Einziger Pop: Bottom-Sheet schließen und Ergebnis zurückgeben.
                  safePop(m);
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  // onDismissed auslösen, wenn ohne Auswahl geschlossen wurde
  return fut.then((value) {
    if (value == null) {
      onDismissed?.call();
      if (kDebugMode) debugPrint('[PandaMoodPicker] Sheet ohne Auswahl geschlossen.');
    } else {
      if (kDebugMode) debugPrint('[PandaMoodPicker] Gewählt: ${value.labelDe}');
    }
    return value;
  });
}
