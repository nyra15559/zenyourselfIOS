// [MERGE SIGNAL] lib/core/privacy/privacy_orchestrator.dart (v1.5 · 2025-11-09)
// ZenYourself — Privacy Orchestrator (Glue UI ↔ MemoryService)
// -----------------------------------------------------------------------------
// Aufgaben:
// • 3-Stufen-Toggle 🕊️/🍃/🌿 & Consent (shareEnabled) steuern.
// • Gating-Regel: SEND_CONTEXT := memory_consent && memory_active
//   → Nur dann setzt ApiService meta.flags.client_memory:true & context.memories.
// • Trial-Expiry: 7 Tage ab erstem Einschalten von Consent; danach memory_active=false
//   bis Premium/Upgrade (hier nur Platzhalter-Hook).
// • UI-Glue: liest/stellt Consent (shareEnabled), Greet-by-Name & Name.
//
// Pfade/Kompatibilität:
// • MemoryService liegt im Core:  import '../memory/memory_service.dart' as mem;
// • PrivacyScreen-UI liegt unter Features: '../../features/settings/privacy_screen.dart'
// • Defensiv via dynamic-Calls (Backward-Compat zu v6.4+).
//
// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';

// UI-Komponente + Settings-Types
import '../../features/settings/privacy_screen.dart';

// Kanonischer MemoryService-Pfad (Core)
import '../memory/memory_service.dart' as mem;

class PrivacyOrchestrator extends StatefulWidget {
  const PrivacyOrchestrator({super.key});

  @override
  State<PrivacyOrchestrator> createState() => _PrivacyOrchestratorState();
}

class _PrivacyOrchestratorState extends State<PrivacyOrchestrator> {
  bool _loading = true;

  // Quellen (aus MemoryService):
  bool _memoryConsent = false; // memory_consent → shareEnabled
  bool _memoryActive = true;   // Trial/Premium Gate (clientseitig)
  bool _greetByName = false;   // Begrüßung mit Name erlaubt?
  String? _currentName;        // nur wenn greetByName == true sinnvoll

  // Trial/Expiry
  DateTime? _trialStartedAtUtc;
  DateTime? _expiryAtUtc; // trialStart + 7 Tage
  int _daysLeft = 0;

  mem.MemoryService get _svc => mem.MemoryService.instance;

  // KV-Schlüssel
  static const String _kMemActive     = 'privacy.memory_active';
  static const String _kTrialStarted  = 'privacy.memory_trial_started_at';
  static const String _kExpiryAt      = 'privacy.memory_expiry_at';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 1) Consent lesen
    _memoryConsent = _svc.shareEnabled;

    // 2) Name/Gruß laden – robust zu v6.5 (Record) und Legacy (String?)
    try {
      final res = await _svc.loadGreetingName();
      if (res is ({String? name, bool greetByName})) {
        _greetByName = res.greetByName;
        _currentName = (res.name ?? '').trim().isEmpty ? null : res.name!.trim();
      } else if (res is String? /* legacy */) {
        _currentName = (res ?? '').trim().isEmpty ? null : res!.trim();
        _greetByName = _currentName != null;
      } else {
        _greetByName = false;
        _currentName = null;
      }
    } catch (_) {
      _greetByName = false;
      _currentName = null;
    }

    // 3) Trial/Active/Expiry laden (defensive dynamic-Calls)
    await _loadActiveAndExpiry();

    // 4) Expires jetzt prüfen
    _checkAndApplyExpiry();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  // ---- Memory Active + Trial/Expiry Laden/Speichern -------------------------

  Future<void> _loadActiveAndExpiry() async {
    _memoryActive = true;
    _trialStartedAtUtc = null;
    _expiryAtUtc = null;

    try {
      final dyn = _svc as dynamic;

      // memory_active
      try {
        final v = await dyn.getMemoryActive?.call();
        if (v is bool) _memoryActive = v;
      } catch (_) {/* noop */}

      // trial started
      try {
        final s = await dyn.getOptString?.call(_kTrialStarted) ??
                  await dyn.getOpt?.call(_kTrialStarted) ??
                  await dyn.getKey?.call(_kTrialStarted);
        if (s is String && s.trim().isNotEmpty) {
          _trialStartedAtUtc = DateTime.tryParse(s.trim())?.toUtc();
        }
      } catch (_) {/* noop */}

      // expiry
      try {
        final s = await dyn.getOptString?.call(_kExpiryAt) ??
                  await dyn.getOpt?.call(_kExpiryAt) ??
                  await dyn.getKey?.call(_kExpiryAt);
        if (s is String && s.trim().isNotEmpty) {
          _expiryAtUtc = DateTime.tryParse(s.trim())?.toUtc();
        }
      } catch (_) {/* noop */}
    } catch (_) {
      // Kein KV? → Defaults bleiben aktiv.
    }

    // Falls Consent aktiv, aber kein Trial-Start existiert → jetzt initialisieren
    if (_memoryConsent && _trialStartedAtUtc == null) {
      final now = DateTime.now().toUtc();
      _trialStartedAtUtc = now;
      _expiryAtUtc = now.add(const Duration(days: 7));
      await _persistTrial(_trialStartedAtUtc!, _expiryAtUtc!);
    }
  }

  Future<void> _persistTrial(DateTime startedUtc, DateTime expiryUtc) async {
    try {
      final dyn = _svc as dynamic;
      final startStr = startedUtc.toIso8601String();
      final expStr   = expiryUtc.toIso8601String();

      await dyn.setOptString?.call(_kTrialStarted, startStr);
      await dyn.setOpt?.call(_kTrialStarted, startStr);
      await dyn.setKey?.call(_kTrialStarted, startStr);

      await dyn.setOptString?.call(_kExpiryAt, expStr);
      await dyn.setOpt?.call(_kExpiryAt, expStr);
      await dyn.setKey?.call(_kExpiryAt, expStr);
    } catch (_) {/* ignore */}
  }

  Future<void> _persistMemoryActive(bool active) async {
    _memoryActive = active;
    try {
      final dyn = _svc as dynamic;
      await dyn.setMemoryActive?.call(active); // bevorzugter Weg
    } catch (_) {/* noop */}
    try {
      final dyn = _svc as dynamic;
      await dyn.setOptBool?.call(_kMemActive, active);
      await dyn.setOpt?.call(_kMemActive, active);
      await dyn.setFlag?.call(_kMemActive, active);
    } catch (_) {/* ignore */}
  }

  // ---- Expiry-Logik ---------------------------------------------------------

  void _checkAndApplyExpiry() {
    final now = DateTime.now().toUtc();

    if (_trialStartedAtUtc == null && _memoryConsent) {
      _trialStartedAtUtc = now;
      _expiryAtUtc = now.add(const Duration(days: 7));
    }

    if (_expiryAtUtc != null) {
      final remaining = _expiryAtUtc!.difference(now);
      if (remaining.isNegative) {
        _daysLeft = 0;
        _memoryActive = false; // Trial abgelaufen
      } else {
        _daysLeft = (remaining.inDays.clamp(0, 9999)).toInt();
      }
    } else {
      _daysLeft = 0;
    }
  }

  // ---- Anwenden von UI-Änderungen (Save) ------------------------------------

  Future<void> _applySave(PrivacySettings s) async {
    // 1) Consent
    try {
      await _svc.setShareEnabled(s.memoryConsent);
    } catch (_) {/* ignore */}
    _memoryConsent = s.memoryConsent;

    // 2) Greet/Name
    if (s.greetByName) {
      if ((_currentName ?? '').trim().isEmpty) {
        final newName = await _askForName(context);
        if (newName != null && newName.trim().isNotEmpty) {
          await _svc.saveIdentityName(newName.trim(), greetByName: true);
          _currentName = newName.trim();
          _greetByName = true;
        } else {
          await _svc.saveIdentityName('', greetByName: false);
          _currentName = null;
          _greetByName = false;
        }
      } else {
        await _svc.saveIdentityName(_currentName!, greetByName: true);
        _greetByName = true;
      }
    } else {
      await _svc.saveIdentityName(_currentName ?? '', greetByName: false);
      _greetByName = false;
    }

    // 3) Trial-/Active-Logik
    final now = DateTime.now().toUtc();

    if (_memoryConsent) {
      if (_trialStartedAtUtc == null) {
        _trialStartedAtUtc = now;
        _expiryAtUtc = now.add(const Duration(days: 7));
        await _persistTrial(_trialStartedAtUtc!, _expiryAtUtc!);
      }

      _checkAndApplyExpiry();

      if (_expiryAtUtc != null && !_expiryAtUtc!.isBefore(now)) {
        await _persistMemoryActive(true);
      } else {
        await _persistMemoryActive(false);
      }
    } else {
      await _persistMemoryActive(false);
    }

    if (!mounted) return;
    setState(() {});
  }

  // ---- Name-Dialog & kleine Actions ----------------------------------------

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

  // ---- Optional: Upgrade/Premium (Platzhalter) ------------------------------

  Future<void> _handleUpgrade() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upgrade ist noch nicht verfügbar.')),
    );
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final statusNote = () {
      if (!_memoryConsent) return 'Kontext-Teilen: AUS';
      if (_memoryActive) {
        final left = _daysLeft;
        return left > 0
            ? 'Kontext-Teilen: AN (Trial, noch $left Tag${left == 1 ? "" : "e"})'
            : 'Kontext-Teilen: AN (Trial aktiv)';
      }
      return 'Kontext-Teilen: AUS (Trial abgelaufen)';
    }();

    return PrivacyScreen(
      props: PrivacyScreenProps(
        // Basiskonfig (falls vom PrivacyScreen genutzt)
        shareDiagnostics: false,
        shareUsage: false,
        enableCloudBackup: false,
        localOnly: true,

        // Wichtig: Handshake zu MemoryService
        memoryConsent: _memoryConsent, // steuert shareEnabled
        greetByName: _greetByName,

        currentName: _currentName,
        policyVersion: 'v2.1',
        lastUpdated: DateTime(2025, 10, 10),

        // Zusatzinfos (optional, je nach Props verfügbar)
        memoryActive: _memoryActive,
        memoryExpiryAt: _expiryAtUtc,
        memoryStatusNote: statusNote,

        // Aktionen
        onOpenPolicy: () {/* TODO: Policy anzeigen */},
        onExport: () {/* optional: Export triggern */},
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

          final sendAllowed = _memoryConsent && _memoryActive;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sendAllowed
                    ? 'Einstellungen gespeichert – Kontext wird (Trial) mitgesendet.'
                    : _memoryConsent
                        ? 'Gespeichert – Trial abgelaufen, kein Kontext-Versand.'
                        : 'Gespeichert – Kontext-Versand deaktiviert.',
              ),
            ),
          );
        },

        // (Optional) Upgrade-Action, wenn Trial abgelaufen:
        onUpgrade: _handleUpgrade,
      ),
    );
  }
}
