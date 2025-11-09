// [UPDATED] lib/features/settings/profile_name_sheet.dart (v1.2.0, 2025-11-09)
// ZenYourself — Profilname Bottom-Sheet (Name setzen/ändern/vergessen)
// -----------------------------------------------------------------------------
// MERGE SIGNAL: ProfileNameSheet v1.2.0 — A11y & UX Polish (ohne Breaking Changes)
// • A11y: klarere Semantics, konsistente Labels, bessere Fokus-Flows.
// • Keyboard/Autofill: TextInputType.name, Capitalization.words, AutofillHints.name.
// • Input-Guards: LengthLimiting + Control-Char-Filter; sanfte Validierung bleibt.
// • Save/Forget: Fehler-Snackbars + Confirm-Dialog beim Vergessen.
// • Small UX: ENTER speichert (onFieldSubmitted), maybePop bleibt möglich.
// • Kompatibel zu MemoryService: loadGreetingName() (Record/String) & saveIdentityName(...).
//
// API unverändert:
//   await showProfileNameSheet(context) → Future<ProfileNameResult?> (null bei Abbruch).
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import '../../core/memory/memory_service.dart' as mem;

class ProfileNameResult {
  final String? name; // null, wenn vergessen
  final bool greetByName; // ob Panda den Namen aktiv verwenden darf
  const ProfileNameResult({required this.name, required this.greetByName});
}

Future<ProfileNameResult?> showProfileNameSheet(BuildContext context) {
  return showModalBottomSheet<ProfileNameResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    builder: (ctx) => const _ProfileNameSheet(),
  );
}

class _ProfileNameSheet extends StatefulWidget {
  const _ProfileNameSheet();

  @override
  State<_ProfileNameSheet> createState() => _ProfileNameSheetState();
}

class _ProfileNameSheetState extends State<_ProfileNameSheet> {
  final _svc = mem.MemoryService.instance;
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  String? _currentName;
  bool _greetByName = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _svc.loadGreetingName();
      if (res is ({String? name, bool greetByName})) {
        _currentName =
            (res.name ?? '').trim().isEmpty ? null : res.name!.trim();
        _greetByName = res.greetByName;
      } else if (res is String? /* legacy */) {
        _currentName = (res ?? '').trim().isEmpty ? null : res!.trim();
        _greetByName = _currentName != null; // Heuristik
      }
      _ctrl.text = _currentName ?? '';
    } catch (_) {
      // Ignorieren – Sheet bleibt nutzbar
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validate(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Bitte gib einen Namen ein.';
    if (s.runes.length > 40) return 'Maximal 40 Zeichen.';
    // Keine Steuerzeichen:
    final hasCtrl = s.runes.any((cp) => cp <= 0x1F || cp == 0x7F);
    if (hasCtrl) return 'Ungültige Zeichen entfernt bitte.';
    // Sanfte Whitelist (Buchstaben/Zahlen/Leerzeichen/.-’):
    final ok =
        RegExp(r"^[\p{L}\p{N} .'\-]+$", unicode: true).hasMatch(s);
    if (!ok) {
      return 'Bitte nur Buchstaben/Zahlen sowie . - \' und Leerzeichen.';
    }
    return null;
  }

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _ctrl.text.trim();
    try {
      await _svc.saveIdentityName(name, greetByName: _greetByName);
      if (!mounted) return;
      Navigator.of(context).pop(
        ProfileNameResult(name: name, greetByName: _greetByName),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte nicht speichern: $e')),
      );
    }
  }

  Future<void> _onForget() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name wirklich vergessen?'),
        content: const Text(
            'Der gespeicherte Name wird lokal entfernt und Panda spricht dich nicht mehr mit Namen an.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ja, löschen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _svc.saveIdentityName('', greetByName: false);
      if (!mounted) return;
      Navigator.of(context).pop(
        const ProfileNameResult(name: null, greetByName: false),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte nicht löschen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final tt = Theme.of(context).textTheme;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        _currentName == null
                            ? 'Name hinzufügen'
                            : 'Name bearbeiten',
                        style: tt.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ctrl,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        inputFormatters: const [
                          LengthLimitingTextInputFormatter(40),
                          // Erlaubt nur Buchstaben/Zahlen/Leerzeichen/.-’
                          FilteringTextInputFormatter.allow(
                            RegExp(r"[\p{L}\p{N} .'\-]", unicode: true),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Dein Name',
                          hintText: 'z. B. Matthias',
                          helperText: 'Der Name bleibt lokal gespeichert.',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validate,
                        onFieldSubmitted: (_) => _onSave(),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _greetByName,
                        onChanged: (v) => setState(() => _greetByName = v),
                        title: const Text('Mit Namen begrüßen'),
                        subtitle: const Text(
                            'Panda darf dich mit deinem Namen ansprechen'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (_currentName != null ||
                              _ctrl.text.trim().isNotEmpty)
                            TextButton.icon(
                              onPressed: _onForget,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Name vergessen'),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(null),
                            child: const Text('Abbrechen'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _onSave,
                            child: const Text('Speichern'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
