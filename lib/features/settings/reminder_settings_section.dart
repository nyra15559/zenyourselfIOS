// lib/features/settings/reminder_settings_section.dart
//
// ReminderSettingsSection — tägliche & wöchentliche Erinnerungen (Pro)
// -------------------------------------------------------------------
// • Keine neuen Deps: nutzt NotificationService (MethodChannel) + LocalStorageService
// • UI: Schalter, Zeitwahl (TimeOfDay), Wochentags-Chips, Test-Benachrichtigung
// • Robust: Permission-Flow (anfragen/öffnen), sofortiges (De-)Scheduling
// • Persistenz: SharedPreferences (über LocalStorageService)
// • A11y: Semantics, klare Labels, große Hit-Zonen
//
// Einbindung in SettingsScreen:
//   const ReminderSettingsSection(),
//
// Erforderlich:
//   - services/notification_service.dart
//   - services/local_storage.dart
//   - shared/zen_style.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/notification_service.dart';
import '../../services/local_storage.dart';
import '../../shared/zen_style.dart';

class ReminderSettingsSection extends StatefulWidget {
  const ReminderSettingsSection({super.key});

  @override
  State<ReminderSettingsSection> createState() => _ReminderSettingsSectionState();
}

class _ReminderSettingsSectionState extends State<ReminderSettingsSection> {
  // ---- Storage Keys ---------------------------------------------------------
  static const _kDailyEnabled = 'reminder.daily.enabled';
  static const _kDailyHour = 'reminder.daily.hour';
  static const _kDailyMinute = 'reminder.daily.minute';

  static const _kWeeklyEnabled = 'reminder.weekly.enabled';
  static const _kWeeklyWeekday = 'reminder.weekly.weekday'; // 1=Mo..7=So
  static const _kWeeklyHour = 'reminder.weekly.hour';
  static const _kWeeklyMinute = 'reminder.weekly.minute';

  static const _kDailyTitle = 'reminder.daily.title';
  static const _kDailyBody = 'reminder.daily.body';
  static const _kWeeklyTitle = 'reminder.weekly.title';
  static const _kWeeklyBody = 'reminder.weekly.body';

  final _storage = LocalStorageService();
  final _ns = NotificationService.instance;

  bool _loading = true;

  bool _dailyEnabled = false;
  TimeOfDay _dailyTime = const TimeOfDay(hour: 8, minute: 0);
  String _dailyTitle = 'Kurze Reflexion';
  String _dailyBody = '2 Minuten für dich – bereit?';

  bool _weeklyEnabled = false;
  int _weeklyWeekday = 1; // Montag
  TimeOfDay _weeklyTime = const TimeOfDay(hour: 18, minute: 0);
  String _weeklyTitle = 'Wochen-Reflexion';
  String _weeklyBody = 'Sanfter Rückblick & ein kleiner Fokus für nächste Woche.';

  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _initFlow();
  }

  Future<void> _initFlow() async {
    await _ns.init(); // sichert Web/No-Op ab
    _hasPermission = await _ns.hasPermission();

    // Laden
    _dailyEnabled = (await _storage.loadSetting<bool>(_kDailyEnabled)) ?? false;
    final dh = (await _storage.loadSetting<int>(_kDailyHour)) ?? _dailyTime.hour;
    final dm = (await _storage.loadSetting<int>(_kDailyMinute)) ?? _dailyTime.minute;
    _dailyTime = TimeOfDay(hour: dh.clamp(0, 23), minute: dm.clamp(0, 59));

    _weeklyEnabled = (await _storage.loadSetting<bool>(_kWeeklyEnabled)) ?? false;
    _weeklyWeekday = (await _storage.loadSetting<int>(_kWeeklyWeekday)) ?? _weeklyWeekday;
    _weeklyWeekday = _weeklyWeekday.clamp(1, 7);
    final wh = (await _storage.loadSetting<int>(_kWeeklyHour)) ?? _weeklyTime.hour;
    final wm = (await _storage.loadSetting<int>(_kWeeklyMinute)) ?? _weeklyTime.minute;
    _weeklyTime = TimeOfDay(hour: wh.clamp(0, 23), minute: wm.clamp(0, 59));

    _dailyTitle = (await _storage.loadSetting<String>(_kDailyTitle)) ?? _dailyTitle;
    _dailyBody = (await _storage.loadSetting<String>(_kDailyBody)) ?? _dailyBody;
    _weeklyTitle = (await _storage.loadSetting<String>(_kWeeklyTitle)) ?? _weeklyTitle;
    _weeklyBody = (await _storage.loadSetting<String>(_kWeeklyBody)) ?? _weeklyBody;

    if (mounted) setState(() => _loading = false);

    // Nach Laden aktuelle Planung widerspiegeln (best-effort).
    await _applyScheduling();
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _SectionCard(
        title: 'Erinnerungen',
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Erinnerungen',
          subtitle:
              'Freundliche Stupser für kurze Reflexionen – lokal, dezent, jederzeit anpassbar.',
          child: Column(
            children: [
              if (!_hasPermission)
                _PermissionBanner(
                  onRequest: _handlePermissionRequest,
                  onOpenSettings: _ns.openSystemSettings,
                ),
              // --- Täglich ---
              SwitchListTile.adaptive(
                value: _dailyEnabled,
                title: const Text('Tägliche Erinnerung'),
                subtitle: const Text('Zur gewählten Uhrzeit jeden Tag'),
                activeColor: ZenColors.cta,
                onChanged: (v) async {
                  await _toggleDaily(v);
                },
              ),
              _RowTile(
                enabled: _dailyEnabled,
                icon: Icons.schedule_rounded,
                label: 'Uhrzeit',
                value: _formatTime(_dailyTime),
                onTap: _dailyEnabled ? _pickDailyTime : null,
              ),
              const SizedBox(height: 6),
              _EditableTextRow(
                enabled: _dailyEnabled,
                label: 'Titel',
                value: _dailyTitle,
                onChanged: (s) async {
                  _dailyTitle = s.trim().isEmpty ? _dailyTitle : s.trim();
                  await _storage.saveSetting(_kDailyTitle, _dailyTitle);
                  if (_dailyEnabled) await _scheduleDaily();
                  setState(() {});
                },
              ),
              _EditableTextRow(
                enabled: _dailyEnabled,
                label: 'Nachricht',
                value: _dailyBody,
                onChanged: (s) async {
                  _dailyBody = s.trim().isEmpty ? _dailyBody : s.trim();
                  await _storage.saveSetting(_kDailyBody, _dailyBody);
                  if (_dailyEnabled) await _scheduleDaily();
                  setState(() {});
                },
              ),
              const Divider(height: 24),

              // --- Wöchentlich ---
              SwitchListTile.adaptive(
                value: _weeklyEnabled,
                title: const Text('Wöchentliche Zusammenfassung'),
                subtitle: const Text('Einmal pro Woche zum gewählten Zeitpunkt'),
                activeColor: ZenColors.cta,
                onChanged: (v) async {
                  await _toggleWeekly(v);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: _WeekdayPicker(
                  enabled: _weeklyEnabled,
                  value: _weeklyWeekday,
                  onChanged: (d) async {
                    _weeklyWeekday = d;
                    await _storage.saveSetting(_kWeeklyWeekday, _weeklyWeekday);
                    if (_weeklyEnabled) await _scheduleWeekly();
                    setState(() {});
                  },
                ),
              ),
              _RowTile(
                enabled: _weeklyEnabled,
                icon: Icons.schedule_rounded,
                label: 'Uhrzeit',
                value: _formatTime(_weeklyTime),
                onTap: _weeklyEnabled ? _pickWeeklyTime : null,
              ),
              const SizedBox(height: 6),
              _EditableTextRow(
                enabled: _weeklyEnabled,
                label: 'Titel',
                value: _weeklyTitle,
                onChanged: (s) async {
                  _weeklyTitle = s.trim().isEmpty ? _weeklyTitle : s.trim();
                  await _storage.saveSetting(_kWeeklyTitle, _weeklyTitle);
                  if (_weeklyEnabled) await _scheduleWeekly();
                  setState(() {});
                },
              ),
              _EditableTextRow(
                enabled: _weeklyEnabled,
                label: 'Nachricht',
                value: _weeklyBody,
                onChanged: (s) async {
                  _weeklyBody = s.trim().isEmpty ? _weeklyBody : s.trim();
                  await _storage.saveSetting(_kWeeklyBody, _weeklyBody);
                  if (_weeklyEnabled) await _scheduleWeekly();
                  setState(() {});
                },
              ),

              const SizedBox(height: 16),
              // Test & Übersicht
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.notifications_active_rounded),
                      label: const Text('Test-Benachrichtigung'),
                      onPressed: _sendTest,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.list_alt_rounded),
                      label: const Text('Geplante anzeigen'),
                      onPressed: _showPending,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Actions / Scheduling --------------------------------------------------

  Future<void> _handlePermissionRequest() async {
    HapticFeedback.selectionClick();
    final ok = await _ns.requestPermission();
    if (!mounted) return;
    setState(() => _hasPermission = ok);
    if (!ok) {
      _snack('Benachrichtigungen nicht erlaubt. Bitte in den Systemeinstellungen aktivieren.');
      await _ns.openSystemSettings();
    } else {
      await _applyScheduling();
      _snack('Benachrichtigungen aktiviert.');
    }
  }

  Future<void> _toggleDaily(bool v) async {
    if (v && !_hasPermission) {
      final ok = await _ns.requestPermission();
      _hasPermission = ok;
      if (!ok) {
        if (mounted) setState(() {});
        _snack('Benachrichtigungen nicht erlaubt.');
        return;
      }
    }
    _dailyEnabled = v;
    await _storage.saveSetting(_kDailyEnabled, _dailyEnabled);
    if (_dailyEnabled) {
      await _scheduleDaily();
    } else {
      await _cancelDaily();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleWeekly(bool v) async {
    if (v && !_hasPermission) {
      final ok = await _ns.requestPermission();
      _hasPermission = ok;
      if (!ok) {
        if (mounted) setState(() {});
        _snack('Benachrichtigungen nicht erlaubt.');
        return;
      }
    }
    _weeklyEnabled = v;
    await _storage.saveSetting(_kWeeklyEnabled, _weeklyEnabled);
    if (_weeklyEnabled) {
      await _scheduleWeekly();
    } else {
      await _cancelWeekly();
    }
    if (mounted) setState(() {});
  }

  Future<void> _applyScheduling() async {
    if (_dailyEnabled) {
      await _scheduleDaily();
    } else {
      await _cancelDaily();
    }
    if (_weeklyEnabled) {
      await _scheduleWeekly();
    } else {
      await _cancelWeekly();
    }
  }

  Future<void> _scheduleDaily() async {
    final id = NotificationService.idFrom('reminder.daily');
    await _ns.scheduleDaily(
      id: id,
      time: _dailyTime,
      title: _dailyTitle,
      body: _dailyBody,
      payload: 'action:open_reflection',
    );
  }

  Future<void> _cancelDaily() async {
    final id = NotificationService.idFrom('reminder.daily');
    await _ns.cancel(id);
  }

  Future<void> _scheduleWeekly() async {
    final id = NotificationService.idFrom('reminder.weekly.$_weeklyWeekday');
    await _ns.scheduleWeekly(
      id: id,
      weekday: _weeklyWeekday,
      time: _weeklyTime,
      title: _weeklyTitle,
      body: _weeklyBody,
      payload: 'action:open_weekly_summary',
    );
  }

  Future<void> _cancelWeekly() async {
    final id = NotificationService.idFrom('reminder.weekly.$_weeklyWeekday');
    await _ns.cancel(id);
  }

  Future<void> _pickDailyTime() async {
    final res = await showTimePicker(
      context: context,
      initialTime: _dailyTime,
      helpText: 'Tägliche Uhrzeit',
    );
    if (res == null) return;
    _dailyTime = res;
    await _storage.saveSetting(_kDailyHour, _dailyTime.hour);
    await _storage.saveSetting(_kDailyMinute, _dailyTime.minute);
    if (_dailyEnabled) await _scheduleDaily();
    if (mounted) setState(() {});
  }

  Future<void> _pickWeeklyTime() async {
    final res = await showTimePicker(
      context: context,
      initialTime: _weeklyTime,
      helpText: 'Wöchentliche Uhrzeit',
    );
    if (res == null) return;
    _weeklyTime = res;
    await _storage.saveSetting(_kWeeklyHour, _weeklyTime.hour);
    await _storage.saveSetting(_kWeeklyMinute, _weeklyTime.minute);
    if (_weeklyEnabled) await _scheduleWeekly();
    if (mounted) setState(() {});
  }

  Future<void> _sendTest() async {
    HapticFeedback.lightImpact();
    final id = NotificationService.idFrom('reminder.test');
    await _ns.show(
      id: id,
      title: 'Test von ZenYourself',
      body: 'Das ist eine Beispiel-Benachrichtigung.',
      payload: 'action:open_app',
    );
    _snack('Test-Benachrichtigung gesendet.');
  }

  Future<void> _showPending() async {
    final list = await _ns.pending();
    if (!mounted) return;
    if (list.isEmpty) {
      _snack('Keine geplanten Benachrichtigungen.');
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: ZenRadii.xl),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Geplante Benachrichtigungen', style: ZenTextStyles.title),
              const SizedBox(height: 12),
              ...list.map((e) {
                final title = (e['title'] ?? '').toString();
                final body = (e['body'] ?? '').toString();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_rounded),
                  title: Text(title.isEmpty ? '(ohne Titel)' : title,
                      style: ZenTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    body.isEmpty ? '(ohne Nachricht)' : body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ZenTextStyles.caption,
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // ---- Helpers --------------------------------------------------------------

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _snack(String msg) {
    final snack = SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    ScaffoldMessenger.of(context).showSnackBar(snack);
  }
}

// ====== Subwidgets ===========================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: ZenColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZenColors.border),
        boxShadow: ZenShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: ZenTextStyles.title.copyWith(fontSize: 20)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: ZenTextStyles.caption.copyWith(color: ZenColors.ink)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final VoidCallback onRequest;
  final Future<void> Function() onOpenSettings;

  const _PermissionBanner({
    required this.onRequest,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: .12),
          border: Border.all(color: Colors.orange.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_off_rounded, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Benachrichtigungen sind derzeit deaktiviert.',
                style: ZenTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(onPressed: onRequest, child: const Text('Erlauben')),
            const SizedBox(width: 4),
            TextButton(onPressed: onOpenSettings, child: const Text('Einstellungen')),
          ],
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final bool enabled;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _RowTile({
    required this.enabled,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: enabled ? ZenColors.jade : ZenColors.jadeMid),
      title: Text(label, style: ZenTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
      trailing: Text(
        value,
        style: ZenTextStyles.caption.copyWith(
          color: enabled ? ZenColors.inkStrong : ZenColors.ink.withValues(alpha: .6),
        ),
      ),
    );

    if (!enabled || onTap == null) {
      return Opacity(opacity: enabled ? 1 : .5, child: content);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: content,
    );
  }
}

class _EditableTextRow extends StatelessWidget {
  final bool enabled;
  final String label;
  final String value;
  final Future<void> Function(String) onChanged;

  const _EditableTextRow({
    required this.enabled,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: value);
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        onSubmitted: (s) => onChanged(s),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  final bool enabled;
  final int value; // 1=Mo..7=So
  final ValueChanged<int> onChanged;

  const _WeekdayPicker({
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  static const _labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (i) {
        final idx = i + 1;
        final selected = value == idx;
        return ChoiceChip(
          label: Text(_labels[i]),
          selected: selected,
          onSelected: enabled ? (_) => onChanged(idx) : null,
          selectedColor: ZenColors.sage.withValues(alpha: .25),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? ZenColors.jade : ZenColors.ink,
          ),
        );
      }),
    );
  }
}
