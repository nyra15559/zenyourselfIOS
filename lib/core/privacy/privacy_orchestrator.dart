// [BASELINE] lib/core/privacy/privacy_orchestrator.dart (v1.2, 2025-11-01)
// ZenYourself — Privacy Orchestrator (Glue UI ↔ MemoryService)
// -----------------------------------------------------------------------------
// Aufgabe:
// - Lädt aktuellen Consent + (optional) Grußname aus MemoryService.
// - Reicht Änderungen aus PrivacyScreen.onSave zurück an MemoryService.
// - Öffnet bei aktivem "Mit Namen ansprechen" ggf. einen Dialog zum Setzen des Namens.
// - Triggert damit indirekt den Merge-Handshake (ApiService liest shareEnabled).
//
// Einbindung (Routing):
//   Navigator.of(context).push(MaterialPageRoute(
//     builder: (_) => const PrivacyOrchestrator(),
//   ));
//
// Hinweise:
// - Dieser Orchestrator fasst KEINE HTTP-Logik an. ApiService hängt Flags/Memories
//   pro Turn automatisch an, wenn MemoryService.shareEnabled == true.

import 'package:flutter/material.dart';
import 'privacy_screen.dart';
import '../memory/memory_service.dart' as mem;

class PrivacyOrchestrator extends StatefulWidget {
  const PrivacyOrchestrator({super.key});

  @override
  State<PrivacyOrchestrator> createState() => _PrivacyOrchestratorState();
}

class _PrivacyOrchestratorState extends State<PrivacyOrchestrator> {
  bool _loading = true;

  // Quellen der Wahrheit (aus MemoryService):
  bool _memoryConsent = false;
  bool _greetByName = false; // true == Name darf aktiv verwendet werden
  String? _currentName; // nur gesetzt, wenn greetByName == true

  mem.MemoryService get _svc => mem.MemoryService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 1) Consent lesen (Instanz, kein statischer Zugriff)
    _memoryConsent = _svc.shareEnabled;

    // 2) Name/Gruß laden – robust für beide Varianten:
    //    a) neuer Rückgabetyp: ({bool greetByName, String? name})
    //    b) legacy: String? (nur Name; greetByName implizit via null/non-null)
    try {
      final result = await _svc.loadGreetingName();

      if (result is ({bool greetByName, String? name})) {
        _greetByName = result.greetByName;
        _currentName = (result.name ?? '').trim().isEmpty ? null : result.name!.trim();
      } else if (result is String? /* legacy */) {
        _currentName = (result ?? '').trim().isEmpty ? null : result!.trim();
        _greetByName = _currentName != null;
      } else {
        // Falls künftig anders: defensiv auf "aus"
        _greetByName = false;
        _currentName = null;
      }
    } catch (_) {
      _greetByName = false;
      _currentName = null;
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _applySave(PrivacySettings s) async {
    // 1) Consent setzen — ApiService setzt daraus Merge-Flags & context.memories.
    await _svc.setShareEnabled(s.memoryConsent);

    // 2) Gruß/Name
    if (s.greetByName) {
      // Nutzer möchte Begrüßung mit Namen
      if (_currentName == null || _currentName!.trim().isEmpty) {
        final newName = await _askForName(context);
        if (newName != null && newName.trim().isNotEmpty) {
          await _svc.saveIdentityName(newName.trim(), greetByName: true);
          _currentName = newName.trim();
          _greetByName = true;
        } else {
          // kein Name -> Gruß wieder deaktivieren
          await _svc.saveIdentityName('', greetByName: false);
          _currentName = null;
          _greetByName = false;
        }
      } else {
        // Name existiert bereits -> nur Greet-Flag sicherstellen
        await _svc.saveIdentityName(_currentName!, greetByName: true);
        _greetByName = true;
      }
    } else {
      // Begrüßung deaktivieren (Name bleibt lokal gespeichert; kein proaktiver Recall)
      await _svc.saveIdentityName(_currentName ?? '', greetByName: false);
      _greetByName = false;
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _forgetName() async {
    await _svc.saveIdentityName('', greetByName: false);
    if (!mounted) return;
    setState(() {
      _currentName = null;
      _greetByName = false;
    });
  }

  Future<String?> _askForName(BuildContext ctx) async {
    final ctrl = TextEditingController(text: _currentName ?? '');
    return showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Wie möchtest du angesprochen werden?'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'z. B. Matthias'),
          onSubmitted: (_) => Navigator.of(c).pop(ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(null),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(ctrl.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PrivacyScreen(
      props: PrivacyScreenProps(
        // Basics (falls du App-weite Prefs hast, hier injizieren)
        shareDiagnostics: false,
        shareUsage: false,
        enableCloudBackup: false,
        localOnly: true,

        // WICHTIG für Merge-Handshake:
        memoryConsent: _memoryConsent,
        greetByName: _greetByName,

        currentName: _currentName,
        policyVersion: 'v2.1',
        lastUpdated: DateTime(2025, 10, 10),

        // Aktionen
        onOpenPolicy: () {/* policy öffnen */},
        onExport: () {/* optional: Export */},
        onDeleteAll: () {/* optional: Full Wipe */},

        onEditName: () async {
          final n = await _askForName(context);
          if (n != null && n.trim().isNotEmpty) {
            await _svc.saveIdentityName(n.trim(), greetByName: true);
            if (!mounted) return;
            setState(() {
              _currentName = n.trim();
              _greetByName = true;
            });
          }
        },
        onForgetName: _forgetName,

        onSave: (s) async {
          await _applySave(s);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Einstellungen gespeichert')),
          );
        },
      ),
    );
  }
}
