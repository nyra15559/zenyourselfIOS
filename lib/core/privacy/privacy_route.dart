// [BASELINE] lib/core/privacy/privacy_route.dart (Stand: 29.10.)
// Datenschutz / Privacy – Opt-in für Erinnerungen & Name
//
// Fixes in dieser Version:
// • Kein statischer Zugriff mehr auf Instance-Member von MemoryService
// • Korrektes Handling des Rückgabetyps von loadGreetingName() = ({bool greetByName, String? name})
// • Konsistente Consent-Kette: UI-Toggle → MemoryService.setEnabled + setShareEnabled
// • Ruhiges Fehlerverhalten (keine Crashes bei fehlender Implementierung)

import 'package:flutter/material.dart';
import '../memory/memory_service.dart';
import 'privacy_screen.dart';

class PrivacyRoute extends StatefulWidget {
  const PrivacyRoute({super.key});
  @override
  State<PrivacyRoute> createState() => _PrivacyRouteState();
}

class _PrivacyRouteState extends State<PrivacyRoute> {
  bool _loading = true;

  // Basics (Dummy-Persistenz – falls du eigene AppSettings hast, dort verdrahten)
  bool _localOnly = true;
  bool _shareDiagnostics = false;
  bool _shareUsage = false;
  bool _enableCloudBackup = false;

  // Memory & Name
  bool _memEnabled = false; // on-device Erinnerungen
  bool _shareEnabled =
      false; // Kontext an Panda senden (ApiService → memory_consent)
  bool _greetByName = false;
  String? _name;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Instance-Aufrufe (kein statischer Zugriff)
      await MemoryService.instance.warmup();

      // enabled/shareEnabled können je nach Implementierung Future<bool> liefern
      try {
        final bool e = await (MemoryService.instance.enabled());
        _memEnabled = e;
      } catch (_) {
        // Fallback: falls als Feld/Getter implementiert wurde
        try {
          final dyn = MemoryService.instance as dynamic;
          final e = await (dyn.enabled as Future<bool>);
          _memEnabled = e;
        } catch (_) {}
      }

      try {
        final bool s = await (MemoryService.instance.shareEnabled());
        _shareEnabled = s;
      } catch (_) {
        try {
          final dyn = MemoryService.instance as dynamic;
          final s = await (dyn.shareEnabled as Future<bool>);
          _shareEnabled = s;
        } catch (_) {}
      }

      // loadGreetingName liefert ein Record ({greetByName, name})
      try {
        final res = await MemoryService.instance.loadGreetingName();
        // res erwartet: ({bool greetByName, String? name})
        final bool greetFlag = res.greetByName;
        final String? nm = res.name;
        _name = (nm?.trim().isNotEmpty ?? false) ? nm!.trim() : null;
        _greetByName = greetFlag && (_name?.isNotEmpty ?? false);
      } catch (_) {
        // defensiv: nichts gesetzt
      }
    } catch (_) {
      // ruhig bleiben – UI nicht blockieren
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _applySave(PrivacySettings s) async {
    // Mapping:
    // Ein Schalter („Erinnerungen erlauben“) steuert aktuell BEIDES:
    //  on-device speichern  +  memory_consent fürs Senden an den Worker.
    // (Wenn du trennen willst, zweiten Toggle ergänzen.)
    try {
      await MemoryService.instance.setEnabled(s.memoryConsent);
    } catch (_) {}
    try {
      await MemoryService.instance.setShareEnabled(s.memoryConsent);
    } catch (_) {}

    // Name/Gruß
    if (s.greetByName) {
      // Falls kein Name gesetzt ist, belassen – „Name ändern“ kümmert sich darum
      final String nm = (_name ?? '').trim();
      if (nm.isNotEmpty) {
        try {
          await MemoryService.instance.saveIdentityName(nm, greetByName: true);
        } catch (_) {}
      }
    } else {
      // Gruß deaktivieren (Name bleibt lokal vorhanden, aber ohne Nutzung)
      final String nm = (_name ?? '').trim();
      try {
        await MemoryService.instance.saveIdentityName(nm, greetByName: false);
      } catch (_) {}
    }

    // Dummy-Persistenzen für Basics (ersetzen, wenn du echte AppSettings hast)
    _localOnly = s.localOnly;
    _shareDiagnostics = s.shareDiagnostics;
    _shareUsage = s.shareUsage;
    _enableCloudBackup = s.enableCloudBackup;

    if (mounted) setState(() {});
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _name ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Name festlegen'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Dein Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (v == null) return;

    _name = v.isEmpty ? null : v;
    try {
      await MemoryService.instance
          .saveIdentityName(_name ?? '', greetByName: (_name ?? '').isNotEmpty);
    } catch (_) {}

    _greetByName = (_name ?? '').isNotEmpty;
    if (mounted) setState(() {});
  }

  Future<void> _forgetName() async {
    _name = null;
    try {
      await MemoryService.instance.saveIdentityName('', greetByName: false);
    } catch (_) {}
    _greetByName = false;
    if (mounted) setState(() {});
  }

  Future<void> _forgetMemories() async {
    // Sanfter Wipe (PII raus); passe an, falls separater Clear-Call existiert
    try {
      await MemoryService.instance.forgetAllPII();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erinnerungen gelöscht')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konnte Erinnerungen nicht löschen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PrivacyScreen(
      props: PrivacyScreenProps(
        // Basics
        shareDiagnostics: _shareDiagnostics,
        shareUsage: _shareUsage,
        enableCloudBackup: _enableCloudBackup,
        localOnly: _localOnly,

        // Memory & Name
        memoryConsent:
            _memEnabled && _shareEnabled, // bis zur Trennung als ein Schalter
        greetByName: _greetByName,
        currentName: _name,

        // Meta
        policyVersion: 'v2.1',
        lastUpdated: DateTime(2025, 10, 10),

        // Aktionen
        onOpenPolicy: () {
          // TODO: Policy öffnen (Route/URL)
        },
        onSave: _applySave,
        onExport: () {
          // optional: Export-Flow
        },
        onDeleteAll: () {
          // optional: Delete-Flow (mit Confirm)
        },
        onForgetName: _forgetName,
        onEditName: _editName,
        onForgetMemories: _forgetMemories,

        // Titel/Untertitel
        title: 'Datenschutz',
        subtitle: null,
      ),
    );
  }
}
