// [BASELINE] lib/core/privacy/privacy_route.dart (v1.3, 2025-11-01)
// Datenschutz / Privacy – Opt-in für Erinnerungen & Name
//
// Fixes in dieser Version:
// • Kein statischer Zugriff mehr auf Instance-Member von MemoryService
// • share/enabled als Felder (keine ()-Aufrufe) → vermeidet invocation_of_non_function_expression
// • Korrektes Handling des Rückgabetyps von loadGreetingName():
//   unterstützt sowohl ({bool greetByName, String? name}) als auch legacy String?
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
  bool _memEnabled = false;   // on-device Erinnerungen
  bool _shareEnabled = false; // Kontext an Panda senden (ApiService → memory_consent)
  bool _greetByName = false;
  String? _name;

  MemoryService get _svc => MemoryService.instance;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _svc.warmup();

      // enabled/shareEnabled als Felder (keine Funktionsaufrufe!)
      try {
        _memEnabled = _svc.enabled;
      } catch (_) {
        _memEnabled = false;
      }
      try {
        _shareEnabled = _svc.shareEnabled;
      } catch (_) {
        _shareEnabled = false;
      }

      // Name/Gruß laden – unterstützt Record ({greetByName, name}) und legacy String?
      try {
        final res = await _svc.loadGreetingName();

        if (res is ({bool greetByName, String? name})) {
          final nm = (res.name ?? '').trim();
          _name = nm.isEmpty ? null : nm;
          _greetByName = res.greetByName && (_name?.isNotEmpty ?? false);
        } else if (res is String? /* legacy */) {
          final nm = (res ?? '').trim();
          _name = nm.isEmpty ? null : nm;
          _greetByName = _name != null;
        } else {
          _name = null;
          _greetByName = false;
        }
      } catch (_) {
        // defensiv: nichts setzen
        _name = null;
        _greetByName = false;
      }
    } catch (_) {
      // ruhig bleiben – UI nicht blockieren
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _applySave(PrivacySettings s) async {
    // Ein Schalter („Erinnerungen erlauben“) steuert aktuell BEIDES:
    //  on-device speichern  +  memory_consent fürs Senden an den Worker.
    try {
      await _svc.setEnabled(s.memoryConsent);
    } catch (_) {}
    try {
      await _svc.setShareEnabled(s.memoryConsent);
    } catch (_) {}

    // Name/Gruß
    if (s.greetByName) {
      final nm = (_name ?? '').trim();
      if (nm.isNotEmpty) {
        try {
          await _svc.saveIdentityName(nm, greetByName: true);
        } catch (_) {}
        _greetByName = true;
      } else {
        // kein Name gesetzt → bleibt aus, bis Nutzer explizit Namen vergibt
        _greetByName = false;
      }
    } else {
      final nm = (_name ?? '').trim();
      try {
        await _svc.saveIdentityName(nm, greetByName: false);
      } catch (_) {}
      _greetByName = false;
    }

    // Dummy-Persistenzen für Basics (ersetzen, wenn du echte AppSettings hast)
    _localOnly = s.localOnly;
    _shareDiagnostics = s.shareDiagnostics;
    _shareUsage = s.shareUsage;
    _enableCloudBackup = s.enableCloudBackup;

    if (!mounted) return;
    setState(() {});
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
      await _svc.saveIdentityName(_name ?? '', greetByName: (_name ?? '').isNotEmpty);
    } catch (_) {}

    _greetByName = (_name ?? '').isNotEmpty;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _forgetName() async {
    _name = null;
    try {
      await _svc.saveIdentityName('', greetByName: false);
    } catch (_) {}
    _greetByName = false;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _forgetMemories() async {
    try {
      await _svc.forgetAllPII();
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
        memoryConsent: _memEnabled && _shareEnabled, // bis zur Trennung als ein Schalter
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
