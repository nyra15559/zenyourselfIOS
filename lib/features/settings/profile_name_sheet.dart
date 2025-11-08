// [BASELINE] lib/features/settings/profile_name_sheet.dart (v1.0, 2025-11-07)
// ZenYourself — Profilname Bottom-Sheet (Name setzen/ändern/vergessen)
// -----------------------------------------------------------------------------
// Zweck:
// • Kleines, eigenständiges Bottom-Sheet zum Setzen/Ändern/Vergessen des Namens.
// • Ruft MemoryService: loadGreetingName(), saveIdentityName(..., greetByName: ...).
// • Robust gegenüber älteren MemoryService-Versionen (Record- oder String-Return).
//
// API:
// • await showProfileNameSheet(context);
//   → Future<ProfileNameResult?> (null bei Abbruch).
//
// UI-Hinweise:
// • Deutsch, ruhiger Ton. Validierung: 1–40 Zeichen, keine Steuerzeichen.
// • Optionaler Toggle „Mit Namen begrüßen“ (Name bleibt lokal gespeichert).
//
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import '../../core/memory/memory_service.dart' as mem;

class ProfileNameResult {
  final String? name;       // null, wenn vergessen
  final bool greetByName;   // ob Panda den Namen aktiv verwenden darf
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
        _currentName = (res.name ?? '').trim().isEmpty ? null : res.name!.trim();
        _greetByName = res.greetByName;
      } else if (res is String? /* legacy */) {
        _currentName = (res ?? '').trim().isEmpty ? null : res!.trim();
        _greetByName = _currentName != null; // heuristisch: wenn Name da, dann nutzen
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
    final ok = RegExp(r"^[\p{L}\p{N} .'\-]+$", unicode: true).hasMatch(s);
    if (!ok) return 'Bitte nur Buchstaben/Zahlen sowie . - \' und Leerzeichen.';
    return null;
  }

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _ctrl.text.trim();
    try {
      await _svc.saveIdentityName(name, greetByName: _greetByName);
    } catch (_) {
      // optional: SnackBar bei Fehler
    }
    if (!mounted) return;
    Navigator.of(context).pop(ProfileNameResult(name: name, greetByName: _greetByName));
  }

  Future<void> _onForget() async {
    try {
      await _svc.saveIdentityName('', greetByName: false);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(const ProfileNameResult(name: null, greetByName: false));
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      _currentName == null ? 'Name hinzufügen' : 'Name bearbeiten',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ctrl,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
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
                      subtitle: const Text('Panda darf dich mit deinem Namen ansprechen'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (_currentName != null || _ctrl.text.trim().isNotEmpty)
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
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
