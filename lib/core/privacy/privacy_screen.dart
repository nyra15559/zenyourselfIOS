// lib/core/privacy/privacy_screen.dart
//
// ZenYourself — Privacy Screen (calm, props-only UI, 2025)
// -----------------------------------------------------------------------------
// • Reine UI-Schicht: rendert Transparenz/Einwilligungen ohne Business-Logik.
// • Nutzt Zen-Design-Tokens (Radii, Spacing, ruhige Farben, Glass).
// • Ruhige Typografie (ZenTypography/ZEN Reflection Text).
// • "withValues(alpha: …)" überall für Konsistenz.
// • Backdrop mit sanftem Glow/Haze (ruhig, AA-konform).
//
// Einbindung:
//   final screen = PrivacyScreen(
//     props: PrivacyScreenProps(
//       shareDiagnostics: false,
//       shareUsage: false,
//       enableCloudBackup: false,
//       localOnly: true,
//       policyVersion: 'v2.1',
//       lastUpdated: DateTime(2025, 10, 10),
//       onOpenPolicy: () { /* open policy URL/route */ },
//       onSave: (settings) { /* persist settings */ },
//       onExport: () { /* export flow */ },
//       onDeleteAll: () { /* delete flow */ },
//     ),
//   );
//
// Hinweise:
// • Dieser Screen trifft KEINE Entscheidungen. Orchestrator persistiert.
// • Schaltet ihr "localOnly" an, werden die restlichen Schalter visuell gedimmt.

import 'package:flutter/material.dart';
import '../../shared/zen_style.dart';

class PrivacyScreenProps {
  final bool shareDiagnostics; // Absturz-/Diagnose-Infos teilen
  final bool shareUsage;       // anonyme Nutzungsanalyse
  final bool enableCloudBackup;// Cloud-Backup von Metadaten
  final bool localOnly;        // Inhalte nur lokal (keine Cloud-Inhalte)

  final String policyVersion;
  final DateTime? lastUpdated;

  // Actions/Callbacks
  final VoidCallback? onOpenPolicy;
  final ValueChanged<PrivacySettings>? onSave;
  final VoidCallback? onExport;
  final VoidCallback? onDeleteAll;

  // Optional: Titel/Untertitel überschreiben
  final String? title;
  final String? subtitle;

  const PrivacyScreenProps({
    this.shareDiagnostics = false,
    this.shareUsage = false,
    this.enableCloudBackup = false,
    this.localOnly = true,
    this.policyVersion = 'v1.0',
    this.lastUpdated,
    this.onOpenPolicy,
    this.onSave,
    this.onExport,
    this.onDeleteAll,
    this.title,
    this.subtitle,
  });
}

class PrivacySettings {
  final bool shareDiagnostics;
  final bool shareUsage;
  final bool enableCloudBackup;
  final bool localOnly;

  const PrivacySettings({
    required this.shareDiagnostics,
    required this.shareUsage,
    required this.enableCloudBackup,
    required this.localOnly,
  });

  Map<String, dynamic> toJson() => {
        'share_diagnostics': shareDiagnostics,
        'share_usage': shareUsage,
        'enable_cloud_backup': enableCloudBackup,
        'local_only': localOnly,
      };
}

class PrivacyScreen extends StatefulWidget {
  final PrivacyScreenProps props;
  const PrivacyScreen({super.key, required this.props});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late bool _shareDiagnostics = widget.props.shareDiagnostics;
  late bool _shareUsage = widget.props.shareUsage;
  late bool _enableCloudBackup = widget.props.enableCloudBackup;
  late bool _localOnly = widget.props.localOnly;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pad = context.screenPad;

    final lastUpdate = widget.props.lastUpdated;
    final lastStr = lastUpdate == null
        ? null
        : '${ZenFormat.two(lastUpdate.day)}.${ZenFormat.two(lastUpdate.month)}.${lastUpdate.year}';

    // Ruhiger Hintergrund
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ZenAppBar(
        title: Text(widget.props.title ?? 'Datenschutz'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Sanfter Backdrop (ruhige Sättigung/Glow/Haze)
          ZenBackdropPresets.menu(),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, 0),
              child: LayoutBuilder(
                builder: (context, c) {
                  final maxW = c.maxWidth.clamp(0, 760.0).toDouble();
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
                                _PrinciplesRow(
                                  items: const [
                                    ('Keine versteckten Datenflüsse', Icons.verified_user_rounded),
                                    ('Inhalte bleiben privat', Icons.lock_rounded),
                                    ('Transparente Einwilligungen', Icons.fact_check_rounded),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Einwilligungen
                          _SectionHeader(title: 'Deine Einwilligungen'),
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
                                    ? null // visuell dimmen: deaktiviert wenn lokal-only
                                    : (v) => setState(() => _shareDiagnostics = v),
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
                                    'Optionales Backup von Metadaten (z. B. Stimmung/Datum) '
                                    'ohne Reflexionsinhalte.',
                                icon: Icons.cloud_sync_rounded,
                                value: _enableCloudBackup,
                                onChanged: _localOnly
                                    ? null
                                    : (v) => setState(() => _enableCloudBackup = v),
                                dimWhenDisabled: _localOnly,
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Rechtliches
                          _SectionHeader(title: 'Rechtliches'),
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
                                          color: ZenColors.ink.withValues(alpha: .75),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          TextButton.icon(
                                            onPressed: widget.props.onOpenPolicy,
                                            icon: const Icon(Icons.open_in_new_rounded),
                                            label: const Text('Erklärung lesen'),
                                          ),
                                          if (widget.props.onExport != null)
                                            OutlinedButton.icon(
                                              onPressed: widget.props.onExport,
                                              icon: const Icon(Icons.file_download_rounded),
                                              label: const Text('Daten exportieren'),
                                            ),
                                          if (widget.props.onDeleteAll != null)
                                            OutlinedButton.icon(
                                              onPressed: widget.props.onDeleteAll,
                                              icon: const Icon(Icons.delete_outline_rounded),
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: ZenColors.ink.withValues(alpha: .87),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              final out = PrivacySettings(
                                shareDiagnostics: _shareDiagnostics && !_localOnly,
                                shareUsage: _shareUsage && !_localOnly,
                                enableCloudBackup: _enableCloudBackup && !_localOnly,
                                localOnly: _localOnly,
                              );
                              widget.props.onSave?.call(out);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Einstellungen gespeichert')),
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
              color: ZenColors.surface.withValues(alpha: .72),
              borderRadius: const BorderRadius.all(ZenRadii.m),
              border: Border.all(color: ZenColors.jade.withValues(alpha: .18)),
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
      child: Column(
        children: children,
      ),
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
                      color: ZenColors.ink.withValues(alpha: .78),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: item.value,
            onChanged: item.onChanged,
          ),
        ],
      ),
    );
  }
}
