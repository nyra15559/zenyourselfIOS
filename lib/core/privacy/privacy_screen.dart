// [MERGE SIGNAL] lib/core/privacy/privacy_screen.dart (v2.0 · 2025-11-18 · memoryToggle-3stage)
// ZenYourself — Privacy Screen (calm, props-only UI)
// -----------------------------------------------------------------------------
// • Reine UI-Schicht: rendert Transparenz/Einwilligungen ohne Business-Logik.
// • 3-Stufen-Memory-Toggle (🕊️ AUS · 🍃 On-Device · 🌿 Voll/Bridge) als zentrale Steuerung.
// • Props: memoryMode (0/1/2) + memoryConsent/greetByName → Orchestrator verdrahtet auf MemoryService.
// • Gear tappbar (AppBar.actions), Backdrop per IgnorePointer → keine Tap-Blocker.
// • Optional-Props für Trial/Status/Upgrade ergänzt (kompatibel zum Orchestrator).
// • Ruhige Oxford-Zen-Typografie & Glass Cards.
//
// Hinweise:
// – Save-Button triggert props.onSave(PrivacySettings).
// – memoryMode: 0 = Aus (🕊️), 1 = On-Device (🍃), 2 = Voll/Bridge (🌿).
// – "Mit Namen ansprechen" ist nur aktiv, wenn currentName gesetzt ist.
// – Wenn memoryMode==2 und memoryActive==false → Upgrade-CTA (falls onUpgrade gesetzt).

import 'package:flutter/material.dart';
import '../../shared/zen_style.dart';

class PrivacyScreenProps {
  // Datenschutz-Basics
  final bool shareDiagnostics; // Absturz-/Diagnose-Infos teilen
  final bool shareUsage; // anonyme Nutzungsanalyse
  final bool enableCloudBackup; // optionales Cloud-Backup von Metadaten
  final bool localOnly; // Inhalte nur lokal (keine Cloud-Inhalte)

  // Erinnerung & Name
  final bool memoryConsent; // Panda darf sich erinnern (on-device)
  final bool greetByName; // Panda darf dich mit Namen ansprechen
  final String? currentName; // gespeicherter Name (optional)

  /// Memory-Mode: 0 = AUS (🕊️), 1 = On-Device (🍃), 2 = Voll/Bridge (🌿).
  /// Orchestrator übersetzt auf MemoryService + ApiService (buildContextMemories).
  final int memoryMode;

  // Policy-Meta
  final String policyVersion;
  final DateTime? lastUpdated;

  // Optional: Trial/Status/Upgrade (für Anzeige)
  final bool? memoryActive; // ob Kontext-Bridge aktuell aktiv ist (Trial/Premium)
  final DateTime? memoryExpiryAt; // optionales Trial-Ende
  final String? memoryStatusNote; // vorformulierte Status-Zeile
  final VoidCallback? onUpgrade; // Upgrade-Action (wenn Trial abgelaufen)

  // Actions/Callbacks
  final VoidCallback? onOpenPolicy;
  final ValueChanged<PrivacySettings>? onSave;
  final VoidCallback? onExport;
  final VoidCallback? onDeleteAll;

  // Name/Memory-spezifische Aktionen (optional)
  final VoidCallback? onForgetName;
  final VoidCallback? onEditName;
  final VoidCallback? onForgetMemories;

  // Optional: Titel/Untertitel überschreiben
  final String? title;
  final String? subtitle;

  const PrivacyScreenProps({
    // Basics
    this.shareDiagnostics = false,
    this.shareUsage = false,
    this.enableCloudBackup = false,
    this.localOnly = true,

    // Memory & Name
    this.memoryConsent = false,
    this.greetByName = false,
    this.currentName,
    this.memoryMode = 0,

    // Policy
    this.policyVersion = 'v1.0',
    this.lastUpdated,

    // Trial/Status/Upgrade (optional)
    this.memoryActive,
    this.memoryExpiryAt,
    this.memoryStatusNote,
    this.onUpgrade,

    // Actions
    this.onOpenPolicy,
    this.onSave,
    this.onExport,
    this.onDeleteAll,
    this.onForgetName,
    this.onEditName,
    this.onForgetMemories,

    // Optional Titles
    this.title,
    this.subtitle,
  });
}

class PrivacySettings {
  final bool shareDiagnostics;
  final bool shareUsage;
  final bool enableCloudBackup;
  final bool localOnly;

  // Memory & Name
  final bool memoryConsent;
  final bool greetByName;

  /// Memory-Mode: 0 = AUS (🕊️), 1 = On-Device (🍃), 2 = Voll/Bridge (🌿).
  final int memoryMode;

  const PrivacySettings({
    required this.shareDiagnostics,
    required this.shareUsage,
    required this.enableCloudBackup,
    required this.localOnly,
    required this.memoryConsent,
    required this.greetByName,
    this.memoryMode = 0,
  });

  Map<String, dynamic> toJson() => {
        'share_diagnostics': shareDiagnostics,
        'share_usage': shareUsage,
        'enable_cloud_backup': enableCloudBackup,
        'local_only': localOnly,
        'memory_consent': memoryConsent,
        'greet_by_name': greetByName,
        'memory_mode': memoryMode,
      };
}

class PrivacyScreen extends StatefulWidget {
  final PrivacyScreenProps props;
  const PrivacyScreen({super.key, required this.props});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  // Basics
  late bool _shareDiagnostics;
  late bool _shareUsage;
  late bool _enableCloudBackup;
  late bool _localOnly;

  // Memory & Name
  late int _memoryMode; // 0/1/2
  late bool _memoryConsent;
  late bool _greetByName;

  @override
  void initState() {
    super.initState();
    final p = widget.props;

    _shareDiagnostics = p.shareDiagnostics;
    _shareUsage = p.shareUsage;
    _enableCloudBackup = p.enableCloudBackup;
    _localOnly = p.localOnly;

    // Memory-Mode: Backcompat – wenn nur memoryConsent gesetzt war, default auf On-Device (1)
    var mode = p.memoryMode;
    if (mode < 0 || mode > 2) {
      mode = 0;
    }
    if (mode == 0 && p.memoryConsent) {
      mode = 1;
    }
    _memoryMode = mode;
    _memoryConsent = _memoryMode > 0;

    _greetByName = p.greetByName;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pad = const EdgeInsets.symmetric(horizontal: 16);

    // Meta
    final lastUpdate = widget.props.lastUpdated;
    final lastStr = lastUpdate == null
        ? null
        : '${ZenFormat.two(lastUpdate.day)}.${ZenFormat.two(lastUpdate.month)}.${lastUpdate.year}';

    final hasName = (widget.props.currentName != null &&
        widget.props.currentName!.trim().isNotEmpty);

    // Trial/Status-Text
    final statusNote = widget.props.memoryStatusNote ??
        (() {
          final active = widget.props.memoryActive;
          if (!_memoryConsent || _memoryMode <= 0) {
            return 'Erinnerungen: AUS (🕊️ Ghost-Mode)';
          }
          if (_memoryMode == 1) {
            return 'Erinnerungen: On-Device (🍃, nur auf diesem Gerät)';
          }
          // _memoryMode == 2
          if (active == false) {
            return 'Kontext-Bridge: AUS (🌿 gewählt, aber nicht aktiv)';
          }
          if (active == true) {
            return 'Kontext-Bridge: AN (🌿, kuratierter Kontext wird mitgeschickt)';
          }
          return 'Kontext-Bridge: –';
        })();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ZenAppBar(
        title: Text(widget.props.title ?? 'Datenschutz'),
        centerTitle: true,
        actions: [
          _GearButton(
            onOpenPolicy: widget.props.onOpenPolicy,
            onExport: widget.props.onExport,
            onDeleteAll: widget.props.onDeleteAll,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Sanfter Backdrop — IGNORE POINTER (wichtig für Tap-Durchlass!)
          const IgnorePointer(ignoring: true, child: ZenBackdropPresets.menu()),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, 0),
              child: LayoutBuilder(
                builder: (context, c) {
                  final maxW = c.maxWidth.clamp(0.0, 760.0).toDouble();
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxW),
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 120),
                        children: [
                          const SizedBox(height: 6),

                          // Header-Card (ruhige Panda-Typo)
                          ZenGlassCard(
                            borderRadius: const BorderRadius.all(ZenRadii.xl),
                            topOpacity: .22,
                            bottomOpacity: .10,
                            borderOpacity: .16,
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.props.subtitle ??
                                      'Wir schützen deine Privatsphäre. '
                                      'Du entscheidest, was geteilt wird.',
                                  style: ZenReflectionText.mirrorStyle,
                                ),
                                const SizedBox(height: 10),
                                const _PrinciplesRow(
                                  items: [
                                    (
                                      'Keine versteckten Datenflüsse',
                                      Icons.verified_user_rounded
                                    ),
                                    (
                                      'Inhalte bleiben privat',
                                      Icons.lock_rounded
                                    ),
                                    (
                                      'Transparente Einwilligungen',
                                      Icons.fact_check_rounded
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Einwilligungen (Basics)
                          const _SectionHeader(title: 'Deine Einwilligungen'),
                          const SizedBox(height: 8),
                          _ToggleCard(
                            items: [
                              _ToggleItem(
                                title: 'Nur lokal speichern',
                                subtitle:
                                    'Reflexionen bleiben auf deinem Gerät. '
                                    'Keine automatische Cloud-Speicherung.',
                                icon: Icons.shield_rounded,
                                value: _localOnly,
                                onChanged: (v) => setState(() => _localOnly = v),
                              ),
                              _ToggleItem(
                                title: 'Diagnose senden',
                                subtitle:
                                    'Fehler- & Crash-Infos helfen uns, Stabilität zu verbessern. '
                                    'Nie Inhalte von Reflexionen.',
                                icon: Icons.health_and_safety_rounded,
                                value: _shareDiagnostics,
                                onChanged: _localOnly
                                    ? null // deaktiviert bei strikt lokal
                                    : (v) =>
                                        setState(() => _shareDiagnostics = v),
                                dimWhenDisabled: _localOnly,
                              ),
                              _ToggleItem(
                                title: 'Anonyme Nutzung teilen',
                                subtitle:
                                    'Aggregierte Nutzungswerte (z. B. App-Starts). '
                                    'Keine personenbezogenen Inhalte.',
                                icon: Icons.insights_rounded,
                                value: _shareUsage,
                                onChanged: _localOnly
                                    ? null
                                    : (v) => setState(() => _shareUsage = v),
                                dimWhenDisabled: _localOnly,
                              ),
                              _ToggleItem(
                                title: 'Cloud-Backup (nur Metadaten)',
                                subtitle:
                                    'Optionales Backup von Metadaten (z. B. Stimmung/Datum) — '
                                    'ohne Reflexionsinhalte.',
                                icon: Icons.cloud_sync_rounded,
                                value: _enableCloudBackup,
                                onChanged: _localOnly
                                    ? null
                                    : (v) =>
                                        setState(() => _enableCloudBackup = v),
                                dimWhenDisabled: _localOnly,
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Erinnerung & Name
                          const _SectionHeader(title: 'Erinnerungen & Name'),
                          const SizedBox(height: 8),
                          ZenGlassCard(
                            borderRadius: const BorderRadius.all(ZenRadii.l),
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            topOpacity: .20,
                            bottomOpacity: .10,
                            child: Column(
                              children: [
                                // Statuszeile (Trial/Active) – dezent
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Opacity(
                                    opacity: .82,
                                    child: Text(
                                      statusNote,
                                      style: tt.bodySmall?.copyWith(
                                        color: ZenColors.jadeMid,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Neuer 3-Stufen-Memory-Toggle
                                _MemoryModeRow(
                                  mode: _memoryMode,
                                  onChanged: (mode) {
                                    setState(() {
                                      _memoryMode = mode;
                                      _memoryConsent = _memoryMode > 0;
                                    });
                                  },
                                ),

                                const SizedBox(height: 8),
                                _ToggleRow(
                                  item: _ToggleItem(
                                    title: 'Mit Namen ansprechen',
                                    subtitle: hasName
                                        ? 'Panda darf dich beim Namen nennen.'
                                        : 'Kein Name gespeichert. Füge einen Namen hinzu, um diese Option zu aktivieren.',
                                    icon: Icons.badge_rounded,
                                    value: _greetByName && hasName,
                                    onChanged: hasName
                                        ? (v) => setState(() => _greetByName = v)
                                        : null,
                                    dimWhenDisabled: !hasName,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _NameRow(
                                  name: widget.props.currentName,
                                  onEdit: widget.props.onEditName,
                                  onForget: widget.props.onForgetName,
                                ),
                                if (widget.props.onForgetMemories != null) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: widget.props.onForgetMemories,
                                      icon: const Icon(
                                          Icons.cleaning_services_rounded),
                                      label: const Text('Erinnerungen löschen'),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Opacity(
                                  opacity: .82,
                                  child: Text(
                                    'Hinweis: Im Modus 🍃 bleiben Erinnerungen auf deinem Gerät. '
                                    'Im Modus 🌿 sendet Panda einen kleinen, kuratierten Kontext '
                                    '(z. B. Thema, Stimmung) mit – niemals ganze Texte. '
                                    'Panda spricht gespeicherte Inhalte nie von sich aus an, '
                                    'sie fließen nur ein, wenn du ähnliche Themen wieder ansprichst.',
                                    style: tt.bodySmall?.copyWith(
                                      color: ZenColors.ink.withValue(alpha: .80),
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                ),

                                // Optionaler Upgrade-Hinweis, wenn Trial abgelaufen und Voll-Modus gewählt
                                if (_memoryMode == 2 &&
                                    (widget.props.memoryActive == false) &&
                                    widget.props.onUpgrade != null) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: widget.props.onUpgrade,
                                      icon: const Icon(Icons.star_rounded),
                                      label: const Text('Upgrade aktivieren'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Rechtliches
                          const _SectionHeader(title: 'Rechtliches'),
                          const SizedBox(height: 8),
                          ZenGlassCard(
                            borderRadius: const BorderRadius.all(ZenRadii.l),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            topOpacity: .20,
                            bottomOpacity: .10,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const ExcludeSemantics(
                                  child: Icon(Icons.policy_rounded,
                                      size: 20, color: ZenColors.ink),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Datenschutzerklärung',
                                        style: tt.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: ZenColors.inkStrong,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          if (lastStr != null) 'Stand $lastStr',
                                          'Version ${widget.props.policyVersion}',
                                        ].join(' • '),
                                        style: tt.bodyMedium?.copyWith(
                                          color: ZenColors.ink
                                              .withValue(alpha: .75),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          TextButton.icon(
                                            onPressed: widget.props.onOpenPolicy,
                                            icon: const Icon(
                                                Icons.open_in_new_rounded),
                                            label: const Text('Erklärung lesen'),
                                          ),
                                          if (widget.props.onExport != null)
                                            OutlinedButton.icon(
                                              onPressed: widget.props.onExport,
                                              icon: const Icon(
                                                  Icons.file_download_rounded),
                                              label: const Text('Daten exportieren'),
                                            ),
                                          if (widget.props.onDeleteAll != null)
                                            OutlinedButton.icon(
                                              onPressed: widget.props.onDeleteAll,
                                              icon: const Icon(
                                                  Icons.delete_outline_rounded),
                                              label: const Text('Alle Daten löschen'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Footer-Disclaimer (ruhig)
                          Center(
                            child: Opacity(
                              opacity: .72,
                              child: Text(
                                'Dies ist keine Therapie, sondern eine mentale Begleitungs-App.',
                                textAlign: TextAlign.center,
                                style: tt.bodyMedium?.copyWith(height: 1.25),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Save-Bar (fix unten)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ZenGlassCard(
                      borderRadius: const BorderRadius.all(ZenRadii.l),
                      topOpacity: .20,
                      bottomOpacity: .14,
                      borderOpacity: .16,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          const ExcludeSemantics(
                            child: Icon(Icons.privacy_tip_rounded,
                                size: 20, color: ZenColors.jade),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Deine Auswahl gilt ab dem Speichern.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: ZenColors.ink.withValue(alpha: .87),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              final hasName = (widget.props.currentName != null &&
                                  widget.props.currentName!
                                      .trim()
                                      .isNotEmpty);

                              final out = PrivacySettings(
                                shareDiagnostics:
                                    _shareDiagnostics && !_localOnly,
                                shareUsage: _shareUsage && !_localOnly,
                                enableCloudBackup:
                                    _enableCloudBackup && !_localOnly,
                                localOnly: _localOnly,
                                memoryConsent: _memoryConsent,
                                greetByName: _greetByName && hasName,
                                memoryMode: _memoryMode,
                              );
                              widget.props.onSave?.call(out);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Einstellungen gespeichert')),
                              );
                            },
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Speichern'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// UI-Bausteine
// -----------------------------------------------------------------------------

/// AppBar-Settings-Button (immer tappbar, 44px Tap-Min)
class _GearButton extends StatelessWidget {
  final VoidCallback? onOpenPolicy;
  final VoidCallback? onExport;
  final VoidCallback? onDeleteAll;

  const _GearButton({
    required this.onOpenPolicy,
    required this.onExport,
    required this.onDeleteAll,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Einstellungen',
      icon: const Icon(Icons.settings_rounded),
      onPressed: () {
        // Wenn gar keine Aktion hinterlegt ist: kurzer Tap-Feedback
        if (onOpenPolicy == null && onExport == null && onDeleteAll == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Einstellungen')),
          );
          return;
        }
        _openSheet(context);
      },
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ZenGlassCard(
            borderRadius: const BorderRadius.all(ZenRadii.l),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.policy_rounded, color: ZenColors.jade),
                  title: const Text('Datenschutzerklärung öffnen'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onOpenPolicy?.call();
                  },
                ),
                if (onExport != null)
                  ListTile(
                    leading: const Icon(Icons.file_download_rounded,
                        color: ZenColors.jade),
                    title: const Text('Daten exportieren'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onExport?.call();
                    },
                  ),
                if (onDeleteAll != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded,
                        color: ZenColors.cherry),
                    title: const Text('Alle Daten löschen'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onDeleteAll?.call();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: ZenTextStyles.h2.copyWith(
        color: ZenColors.inkStrong,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PrinciplesRow extends StatelessWidget {
  final List<(String, IconData)> items;
  const _PrinciplesRow({required this.items});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final it in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: ZenColors.surface.withValue(alpha: .72),
              borderRadius: const BorderRadius.all(ZenRadii.m),
              border: Border.all(color: ZenColors.jade.withValue(alpha: .18)),
              boxShadow: const [ZenShadows.glow],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(it.$2, size: 16, color: ZenColors.jade),
                const SizedBox(width: 8),
                Text(
                  it.$1,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ZenColors.inkStrong,
                    height: 1.22,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ToggleCard extends StatelessWidget {
  final List<_ToggleItem> items;
  const _ToggleCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      children.add(_ToggleRow(item: it));
      if (i != items.length - 1) {
        children.add(const SizedBox(height: 8));
      }
    }

    return ZenGlassCard(
      borderRadius: const BorderRadius.all(ZenRadii.l),
      topOpacity: .20,
      bottomOpacity: .10,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(children: children),
    );
  }
}

class _ToggleItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool dimWhenDisabled;

  const _ToggleItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.dimWhenDisabled = false,
  });
}

class _ToggleRow extends StatelessWidget {
  final _ToggleItem item;
  const _ToggleRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDisabled = item.onChanged == null;
    final opacity = isDisabled && item.dimWhenDisabled ? .45 : 1.0;

    final tt = Theme.of(context).textTheme;
    return Opacity(
      opacity: opacity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Icon(Icons.info_outline, size: 0), // Alignment-Placeholder
          ),
          ExcludeSemantics(
            child: Icon(item.icon, size: 18, color: ZenColors.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ZenColors.inkStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: tt.bodyMedium?.copyWith(
                      color: ZenColors.ink.withValue(alpha: .78),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Switch(value: item.value, onChanged: item.onChanged),
        ],
      ),
    );
  }
}

class _NameRow extends StatelessWidget {
  final String? name;
  final VoidCallback? onEdit;
  final VoidCallback? onForget;

  const _NameRow({
    required this.name,
    required this.onEdit,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasName = name != null && name!.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const ExcludeSemantics(
          child: Icon(Icons.person_rounded, size: 18, color: ZenColors.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: hasName
              ? Text(
                  'Gespeicherter Name: $name',
                  style: tt.bodyMedium?.copyWith(
                    color: ZenColors.inkStrong,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Text(
                  'Kein Name gespeichert.',
                  style: tt.bodyMedium?.copyWith(
                    color: ZenColors.ink.withValue(alpha: .80),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        if (onEdit != null)
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Namen ändern'),
          ),
        const SizedBox(width: 8),
        if (onForget != null)
          TextButton.icon(
            onPressed: onForget,
            icon: const Icon(Icons.backspace_rounded, size: 18),
            label: const Text('Name löschen'),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Memory-Mode UI (3-Stufen-Toggle 🕊️ · 🍃 · 🌿)
// -----------------------------------------------------------------------------

class _MemoryModeRow extends StatelessWidget {
  final int mode; // 0/1/2
  final ValueChanged<int> onChanged;

  const _MemoryModeRow({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(
          child: Icon(Icons.memory_rounded, size: 18, color: ZenColors.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Panda-Gedächtnis',
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ZenColors.inkStrong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _descriptionForMode(mode),
                style: tt.bodyMedium?.copyWith(
                  color: ZenColors.ink.withValue(alpha: .80),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MemoryModeChip(
                    label: '🕊️ AUS',
                    subtitle: 'kein Gedächtnis',
                    isActive: mode == 0,
                    onTap: () => onChanged(0),
                  ),
                  _MemoryModeChip(
                    label: '🍃 On-Device',
                    subtitle: 'nur lokal',
                    isActive: mode == 1,
                    onTap: () => onChanged(1),
                  ),
                  _MemoryModeChip(
                    label: '🌿 Voll',
                    subtitle: 'mit Kontext-Bridge',
                    isActive: mode == 2,
                    onTap: () => onChanged(2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _descriptionForMode(int mode) {
    switch (mode) {
      case 0:
        return 'Panda vergisst nach jeder Sitzung (Ghost-Mode).';
      case 1:
        return 'Panda erinnert sich nur lokal an Name, Stimmung und Erkenntnisse.';
      case 2:
        return 'Panda nutzt zusätzlich eine kleine Kontext-Bridge, damit Antworten besser zu dir passen.';
      default:
        return 'Steuere, wie stark Panda sich erinnern darf.';
    }
  }
}

class _MemoryModeChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;

  const _MemoryModeChip({
    required this.label,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bg = isActive
        ? ZenColors.jade.withValue(alpha: .20)
        : ZenColors.surface.withValue(alpha: .70);
    final border = isActive
        ? ZenColors.jade.withValue(alpha: .70)
        : ZenColors.ink.withValue(alpha: .16);
    final textColor =
        isActive ? ZenColors.inkStrong : ZenColors.ink.withValue(alpha: .90);

    return InkWell(
      borderRadius: const BorderRadius.all(ZenRadii.m),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(ZenRadii.m),
          border: Border.all(color: border),
          boxShadow: isActive ? const [ZenShadows.glow] : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: tt.bodySmall?.copyWith(
                color: ZenColors.ink.withValue(alpha: .80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
