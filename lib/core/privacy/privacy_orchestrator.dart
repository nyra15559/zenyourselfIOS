// [MERGE SIGNAL] lib/core/privacy/privacy_orchestrator.dart (v1.6 · 2025-11-10)
// ZenYourself — Privacy Orchestrator (Glue UI ↔ MemoryService)
// -----------------------------------------------------------------------------
// Was ist neu (v1.6):
// • 3-Stufen-Toggle: 🕊️ Aus · 🍃 On-Device (nur lokal) · 🌿 Voll (Bridge)
// • Trial/Expiry: 7 Tage ab erstem Einschalten von Consent (🌿). Danach memory_active=false,
//   bis Upgrade (nur Platzhalter-Hook). Statushinweis im UI.
// • SEND_CONTEXT-Regel: Nur wenn (memory_consent && memory_active) → ApiService sendet
//   meta.flags.client_memory:true und context.memories (≤2 kB) – sonst nie.
// • Session-Reset: Beim Wechsel von 🌿 → 🕊️/🍃 (also bei Deaktivierung des Kontext-Versands)
//   wird best-effort eine neue thread_id erzwungen (ApiService.resetThreadId/bumpThreadId, dynamisch).
// • Defensiv: dynamic-Calls für rückwärtskompatible MemoryService-/UI-Props; robuste Name-Flows.
// • Sanfte Snackbars für Nutzerfeedback.
//
// Pfade/Kompatibilität:
// • MemoryService im Core:  import '../memory/memory_service.dart' as mem;
// • PrivacyScreen-UI unter Features: '../../features/settings/privacy_screen.dart'
// • Diese Datei ist „Glue“ – keine hart verdrahteten Abhängigkeiten auf konkrete UI-Props.
//
// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/material.dart';

// UI-Komponente + Settings-Types (defensiv verwendet)
import '../../features/settings/privacy_screen.dart';

// Kanonischer MemoryService-Pfad (Core)
import '../memory/memory_service.dart' as mem;

/// Optionaler Modus, falls die UI ihn liefert (Strings werden tolerant gemappt).
enum PrivacyMode { off, onDevice, bridge }

class PrivacyOrchestrator extends StatefulWidget {
  const PrivacyOrchestrator({super.key});

  @override
  State<PrivacyOrchestrator> createState() => _PrivacyOrchestratorState();
}

class _PrivacyOrchestratorState extends State<PrivacyOrchestrator> {
  bool _loading = true;

  // Quellen (aus MemoryService):
  bool _memoryConsent = false; // memory_consent → shareEnabled (🌿 erfordert true)
  bool _memoryActive = true;   // Trial/Premium Gate (clientseitig); für 🍃 true, für 🕊️ false
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
    // 1) Consent lesen (Bridge-Erlaubnis)
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

    // 3) Trial/Active/Expiry laden (defensiv via dynamic)
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

      // memory_active (persistierter Schalter)
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

  // ---- Hilfsfunktionen ------------------------------------------------------

  PrivacyMode _parseModeDynamic(dynamic s) {
    // Tolerante Extraktion: s.mode / s.privacyMode / s.stage / s.toggle / s.value
    String? raw;
    try {
      raw = (s?.mode as String?) ??
            (s?.privacyMode as String?) ??
            (s?.stage as String?) ??
            (s?.toggle as String?) ??
            (s?.value as String?);
    } catch (_) {/* ignore */}

    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty) return _deriveModeFromState();

    if (v == 'off' || v == 'aus' || v == '🕊️' || v == 'dove' || v == '0') {
      return PrivacyMode.off;
    }
    if (v == 'on-device' || v == 'ondevice' || v == 'local' || v == '🍃' || v == '1') {
      return PrivacyMode.onDevice;
    }
    if (v == 'bridge' || v == 'voll' || v == 'full' || v == '🌿' || v == '2') {
      return PrivacyMode.bridge;
    }
    // Fallback
    return _deriveModeFromState();
  }

  PrivacyMode _deriveModeFromState() {
    if (!_memoryConsent && !_memoryActive) return PrivacyMode.off;
    if (!_memoryConsent && _memoryActive)  return PrivacyMode.onDevice;
    return PrivacyMode.bridge; // consent true → 🌿 (active kann via Trial false sein)
  }

  Future<void> _resetThreadIdIfSupported() async {
    // Best-effort: verschiedene mögliche Haken versuchen
    try {
      // Direkter Zugriff auf ApiService (falls offen gelegt)
      final dynSvc = _svc as dynamic;
      final api = dynSvc.apiService ?? dynSvc.getApiService?.call();
      if (api != null) {
        await api.resetThreadId?.call();
        return;
      }
    } catch (_) {/* noop */}
    try {
      // Alternativer Hook am MemoryService selbst
      final dynSvc = _svc as dynamic;
      await dynSvc.bumpThreadId?.call();
    } catch (_) {/* noop */}
  }

  // ---- Anwenden von UI-Änderungen (Save) ------------------------------------

  Future<void> _applySave(PrivacySettings s) async {
    // 0) Modus (falls UI ihn liefert)
    final desiredMode = _parseModeDynamic(s);

    // 1) Consent (shareEnabled) – vorläufig aus Settings; final durch Modus überschrieben
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

    // 3) Modus anwenden (überschreibt Consent/Active konsistent)
    final wasBridge = _memoryConsent; // bisheriger Sendestatus

    if (desiredMode == PrivacyMode.off) {
      _memoryConsent = false;                // kein Versand
      await _persistMemoryActive(false);     // lokale Memory AUS
    } else if (desiredMode == PrivacyMode.onDevice) {
      _memoryConsent = false;                // kein Versand
      await _persistMemoryActive(true);      // lokale Memory AN
    } else {
      // 🌿 Bridge
      _memoryConsent = true;
      final now = DateTime.now().toUtc();
      if (_trialStartedAtUtc == null) {
        _trialStartedAtUtc = now;
        _expiryAtUtc = now.add(const Duration(days: 7));
        await _persistTrial(_trialStartedAtUtc!, _expiryAtUtc!);
      }
      _checkAndApplyExpiry();
      // Wenn Trial nicht abgelaufen → active true, sonst false
      if (_expiryAtUtc != null && !_expiryAtUtc!.isBefore(now)) {
        await _persistMemoryActive(true);
      } else {
        await _persistMemoryActive(false);
      }
    }

    // 4) Consent final persistieren (nach Modus)
    try {
      await _svc.setShareEnabled(_memoryConsent);
    } catch (_) {/* ignore */}

    // 5) Session-Reset, falls Versand vorher AN (🌿) und jetzt AUS (🕊️/🍃)
    final sendNowAllowed = _memoryConsent && _memoryActive;
    if (wasBridge && !sendNowAllowed) {
      await _resetThreadIdIfSupported();
    }

    if (!mounted) return;
    setState(() {});

    // 6) Feedback
    final status = () {
      if (!_memoryConsent) {
        // 🕊️ oder 🍃
        return _memoryActive
            ? 'Gespeichert – On-Device aktiv (kein Kontext-Versand).'
            : 'Gespeichert – On-Device AUS (kein Kontext-Versand).';
      }
      // 🌿
      if (_memoryActive) {
        final left = _daysLeft;
        return left > 0
            ? 'Gespeichert – Bridge AKTIV (Trial, noch $left Tag${left == 1 ? "" : "e"}).'
            : 'Gespeichert – Bridge AKTIV (Trial).';
      }
      return 'Gespeichert – Consent an, aber Trial abgelaufen (kein Versand).';
    }();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
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
      if (!_memoryConsent) {
        // 🕊️ (off) oder 🍃 (on-device)
        return _memoryActive
            ? 'Kontext-Teilen: AUS · On-Device: AN'
            : 'Kontext-Teilen: AUS · On-Device: AUS';
      }
      // 🌿 (bridge)
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
        localOnly: !_memoryConsent, // Heuristik für UI: wenn kein Versand → lokal only

        // Handshake zu MemoryService
        memoryConsent: _memoryConsent, // steuert shareEnabled (🌿 erfordert true)
        greetByName: _greetByName,

        currentName: _currentName,
        policyVersion: 'v2.1',
        lastUpdated: DateTime(2025, 10, 10),

        // Zusatzinfos (optional, je nach Props verfügbar)
        memoryActive: _memoryActive,
        memoryExpiryAt: _expiryAtUtc,
        memoryStatusNote: statusNote,

        // (Falls die UI bereits einen Modus anbietet, kann sie ihn via onSave(...mode...)) setzen.

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

        onSave: (s) async => _applySave(s),

        // (Optional) Upgrade-Action, wenn Trial abgelaufen:
        onUpgrade: _handleUpgrade,
      ),
    );
  }
}
