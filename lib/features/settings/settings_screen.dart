// lib/features/settings/settings_screen.dart
//
// SettingsScreen — Oxford-Zen Pro (Batch 3 / Drop F)
// --------------------------------------------------
// • A11y: Dark Mode, Große Schrift, Farbsehmodus
// • Sprache: de/en/fr/it (über AppSettings Provider)
// • Therapeuten-Modus: Toggle + Code-Eingabe, Share-Until Picker
// • API-Endpoint: sicher speichern (SecureStorage) + GuidanceService binden
// • Backup/Restore: Clipboard + optional GZip über BackupExportService
// • Datenpflege: Clear Namespace (mit Bestätigung)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/zen_style.dart';
import '../../shared/ui/zen_widgets.dart';

import '../../services/local_storage.dart';
import '../../services/guidance_service.dart';
import '../../services/api_client.dart' show ApiClient;
import '../../services/backup_export_service.dart' show BackupExportService;

import '../../models/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  static const routeName = '/settings';

  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // API
  final _apiController = TextEditingController();
  final _apiFocus = FocusNode();
  String? _loadedApiBase; // aus SecureStorage

  // Therapist
  final _therapistCodeCtrl = TextEditingController();
  final _therapistCodeFocus = FocusNode();

  bool _busy = false;
  final _storage = LocalStorageService();

  @override
  void initState() {
    super.initState();
    _loadSecureApiBase();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.read<AppSettings>();
    final code = s.therapistCode ?? '';
    if (_therapistCodeCtrl.text != code) {
      _therapistCodeCtrl.text = code;
    }
  }

  Future<void> _loadSecureApiBase() async {
    final s = await _storage.loadSecure('api_base_url');
    if (!mounted) return;
    setState(() {
      _loadedApiBase = s ?? '';
      _apiController.text = _loadedApiBase!;
    });
  }

  @override
  void dispose() {
    _apiController.dispose();
    _apiFocus.dispose();
    _therapistCodeCtrl.dispose();
    _therapistCodeFocus.dispose();
    super.dispose();
  }

  // ---------------------------
  // Helpers
  // ---------------------------

  bool _looksLikeUrl(String v) {
    final s = v.trim();
    if (s.isEmpty) return true; // leer = Remote trennen erlaubt
    final ok = s.startsWith('http://') || s.startsWith('https://');
    return ok && s.length > 10;
  }

  bool _validTherapistCode(String? v) {
    if (v == null || v.trim().isEmpty) return true; // leer = entfernen erlaubt
    return RegExp(r'^[A-Za-z0-9\-_]{6,32}$').hasMatch(v.trim());
  }

  String _fmtDateTimeShort(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year}, ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _applyApiBase() async {
    final base = _apiController.text.trim();

    if (!_looksLikeUrl(base)) {
      _toast('Bitte eine gültige URL angeben (https://…)');
      _apiFocus.requestFocus();
      return;
    }

    setState(() => _busy = true);
    try {
      // 1) Sicher speichern (auch leer möglich → trennt Remote)
      await _storage.saveSecure('api_base_url', base);

      // 2) Sofort GuidanceService konfigurieren (leer → lokaler Fallback)
      if (base.isEmpty) {
        GuidanceService.instance.configureHttp(invoker: null, baseUrl: null);
      } else {
        final client = ApiClient(
          baseUrl: Uri.parse(base),
          tokenProvider: () async => null,
          onLog: (msg) => debugPrint('[Api] $msg'),
        );
        GuidanceService.instance.configureHttp(
          invoker: client.call,
          baseUrl: client.baseUrlStr,
        );
      }

      _toast('API-Endpoint gespeichert und angewendet.');
      setState(() => _loadedApiBase = base);
    } catch (e) {
      _toast('Konnte API-Endpoint nicht speichern.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _exportToClipboard() async {
    setState(() => _busy = true);
    try {
      final dump = await _storage.exportNamespace();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(dump);
      await Clipboard.setData(ClipboardData(text: jsonStr));
      _toast('Backup in Zwischenablage kopiert.');
    } catch (_) {
      _toast('Export fehlgeschlagen.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _exportGzipIfAvailable() async {
    setState(() => _busy = true);
    try {
      await BackupExportService().exportNamespaceGzip();
      _toast('Backup (GZip) erstellt.');
    } catch (_) {
      _toast('GZip-Export nicht verfügbar.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _importFromClipboard() async {
    final confirm = await _confirm(
      title: 'Aus Zwischenablage importieren?',
      message:
          'Bestehende Daten in diesem Namespace werden überschrieben. Fortfahren?',
      confirmLabel: 'Ja, importieren',
      danger: true,
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final data = await Clipboard.getData('text/plain');
      final raw = data?.text ?? '';
      if (raw.trim().isEmpty) {
        _toast('Zwischenablage ist leer.');
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      await _storage.importNamespace(decoded);
      _toast('Import erfolgreich. Starte die App ggf. neu.');
    } catch (_) {
      _toast('Import fehlgeschlagen. Ist es gültiges JSON?');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _clearNamespace() async {
    final ok = await _confirm(
      title: 'Alle App-Daten löschen?',
      message:
          'Dies entfernt alle gespeicherten Werte im Zen-Namespace (SharedPreferences). '
          'Sichere Daten vorher als Backup. Dieser Vorgang kann nicht rückgängig gemacht werden.',
      confirmLabel: 'Ja, alles löschen',
      danger: true,
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _storage.clearNamespace();
      _toast('Daten gelöscht. Starte die App ggf. neu.');
    } catch (_) {
      _toast('Löschen fehlgeschlagen.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    String confirmLabel = 'OK',
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: danger
                ? ElevatedButton.styleFrom(backgroundColor: Colors.redAccent)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ---------------------------
  // UI
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // --- Allgemein
                _sectionHeader('Allgemein'),
                _card(
                  children: [
                    _localeRow(settings),
                    const Divider(height: 1),
                    _switchRow(
                      icon: Icons.dark_mode,
                      title: 'Dunkles Design',
                      value: settings.darkMode,
                      onChanged: (v) => settings.toggleDarkMode(v),
                    ),
                    const Divider(height: 1),
                    _switchRow(
                      icon: Icons.text_increase_rounded,
                      title: 'Große Schrift',
                      value: settings.largeText,
                      onChanged: (v) => settings.toggleLargeText(v),
                    ),
                    const Divider(height: 1),
                    _switchRow(
                      icon: Icons.visibility_rounded,
                      title: 'Farbsehmodus (Kontrast)',
                      value: settings.colorBlindMode,
                      onChanged: (v) => settings.toggleColorBlind(v),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // --- Therapeuten-Modus
                _sectionHeader('Therapeuten-Modus'),
                _card(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        settings.therapistModeEnabled
                            ? 'Therapeuten-Modus ist AKTIV'
                            : 'Therapeuten-Modus ist AUS',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: settings.therapistModeEnabled
                              ? ZenColors.deepSage
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Wenn aktiviert, kannst du Inhalte leichter für deine Therapie vorbereiten '
                        'und bei Bedarf ausgewählte Einträge teilen. Nichts wird automatisch gesendet.',
                        style: ZenTextStyles.caption,
                      ),
                      value: settings.therapistModeEnabled,
                      onChanged: (v) async {
                        await settings.setTherapistModeEnabled(v);
                        _toast(v ? 'Therapeuten-Modus aktiviert.' : 'Therapeuten-Modus beendet.');
                      },
                    ),

                    if (settings.therapistModeEnabled) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _therapistCodeCtrl,
                        focusNode: _therapistCodeFocus,
                        decoration: const InputDecoration(
                          labelText: 'Code (optional, 6–32 Zeichen)',
                          hintText: 'ABC123 / praxis-id',
                          prefixIcon: Icon(Icons.verified_user_rounded),
                          helperText:
                              'Nur Buchstaben/Zahlen, „-“ und „_“ erlaubt. Leer lassen, um Code zu entfernen.',
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _saveTherapistCode(settings),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Code speichern'),
                              onPressed: () => _saveTherapistCode(settings),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Share-Until
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.schedule_rounded, color: ZenColors.jadeMid),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Freigaben bis',
                                  style: ZenTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  settings.shareUntil == null
                                      ? 'Kein Enddatum gesetzt.'
                                      : _fmtDateTimeShort(settings.shareUntil!.toLocal()),
                                  style: ZenTextStyles.caption,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.edit_calendar_rounded),
                                      label: const Text('Festlegen'),
                                      onPressed: () => _pickShareUntil(settings),
                                    ),
                                    if (settings.shareUntil != null)
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.clear_rounded),
                                        label: const Text('Löschen'),
                                        onPressed: () => settings.setShareUntil(null),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 18),

                // --- API / Entwickler
                _sectionHeader('API / Entwicklereinstellungen'),
                _card(
                  children: [
                    _apiField(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.link_rounded),
                            label: const Text('Endpoint speichern & anwenden'),
                            onPressed: _applyApiBase,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if ((_loadedApiBase ?? '').isNotEmpty)
                      Text(
                        'Aktuell: ${_loadedApiBase!}',
                        style: ZenTextStyles.caption.copyWith(
                          color: ZenColors.jadeMid,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 18),

                // --- Daten & Backup
                _sectionHeader('Daten & Backup'),
                _card(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy_all_rounded),
                            label: const Text('Backup → Zwischenablage'),
                            onPressed: _exportToClipboard,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.file_download_rounded),
                            label: const Text('Backup (GZip) erstellen'),
                            onPressed: _exportGzipIfAvailable,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.paste_rounded),
                            label: const Text('Import aus Zwischenablage'),
                            onPressed: _importFromClipboard,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.delete_forever_rounded),
                            label: const Text('Alle Daten löschen (Namespace)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _clearNamespace,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // --- Info
                _sectionHeader('Info'),
                _card(
                  children: [
                    _infoRow('Version', 'v5 (Oxford-Zen)'),
                    const Divider(height: 1),
                    _infoRow('Speicherort', 'SharedPreferences + SecureStorage'),
                    const Divider(height: 1),
                    _infoRow('Remote-Analyse', 'Optional, mit lokalem Fallback'),
                  ],
                ),
              ],
            ),

            if (_busy)
              const Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: _BusyOverlay(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- UI: Bausteine --------------------------------------------------------

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Text(
        title,
        style: ZenTextStyles.title.copyWith(
          fontWeight: FontWeight.w800,
          color: ZenColors.inkStrong,
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: ZenColors.surface,
        borderRadius: const BorderRadius.all(ZenRadii.lg),
        border: Border.all(color: ZenColors.border, width: 1),
        boxShadow: ZenShadows.card,
      ),
      padding: const EdgeInsets.all(ZenSpacing.padBubble),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _localeRow(AppSettings settings) {
    const locales = [
      Locale('de', 'DE'),
      Locale('en', 'US'),
      Locale('fr', 'FR'),
      Locale('it', 'IT'),
    ];

    String labelFor(Locale l) {
      switch (l.languageCode) {
        case 'de':
          return 'Deutsch';
        case 'en':
          return 'English';
        case 'fr':
          return 'Français';
        case 'it':
          return 'Italiano';
        default:
          return l.toLanguageTag();
      }
    }

    return Row(
      children: [
        const Icon(Icons.language_rounded, color: ZenColors.jadeMid),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<Locale>(
            value: locales.firstWhere(
              (l) =>
                  l.languageCode == settings.locale.languageCode &&
                  (l.countryCode == null ||
                      l.countryCode == settings.locale.countryCode),
              orElse: () => settings.locale,
            ),
            decoration: const InputDecoration(
              labelText: 'Sprache',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final l in locales)
                DropdownMenuItem(
                  value: l,
                  child: Text(labelFor(l)),
                )
            ],
            onChanged: (l) {
              if (l != null) settings.setLocale(l);
            },
          ),
        ),
      ],
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: ZenColors.jadeMid),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: ZenTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _apiField() {
    return TextFormField(
      controller: _apiController,
      focusNode: _apiFocus,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        labelText: 'API-Endpoint (leer = lokal, z. B. https://api.zen.example)',
        hintText: 'https://…',
        prefixIcon: Icon(Icons.cloud_rounded),
      ),
    );
  }

  Widget _infoRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: ZenTextStyles.body.copyWith(
                color: ZenColors.jadeMid,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(v, style: ZenTextStyles.body),
        ],
      ),
    );
  }

  // ---- Therapist helpers ----------------------------------------------------

  Future<void> _saveTherapistCode(AppSettings settings) async {
    final val = _therapistCodeCtrl.text.trim();
    if (!_validTherapistCode(val)) {
      _toast('Ungültiger Code: 6–32 Zeichen, nur A–Z, a–z, 0–9, - und _.');
      _therapistCodeFocus.requestFocus();
      return;
    }
    await settings.setTherapistCode(val.isEmpty ? null : val);
    _toast(val.isEmpty ? 'Code entfernt.' : 'Code gespeichert.');
  }

  Future<void> _pickShareUntil(AppSettings settings) async {
    final now = DateTime.now();
    final initialDate = settings.shareUntil?.toLocal() ?? now.add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return;

    final local = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await settings.setShareUntil(local);
    _toast('Freigaben bis: ${_fmtDateTimeShort(local)}');
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(.06),
      child: const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}
