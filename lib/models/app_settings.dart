// lib/models/app_settings.dart
//
// AppSettings — Persistente App- & A11y-Einstellungen (Oxford-Zen v3.2)
// ----------------------------------------------------------------------
// ✓ ChangeNotifier mit Auto-Hydration aus LocalStorage
// ✓ Persistente Flags: DarkMode, LargeText, ColorBlindMode
// ✓ Lokalisierung: Locale speichern/laden ("de_DE", "en_US", …)
// ✓ Therapeuten-Modus: therapistModeEnabled, therapistCode (secure), shareUntil (ISO)
// ✓ Saubere Set-/Toggle-APIs (nur bei Änderungen notify + persist)
// ✓ Backup/Restore: toJson/applyFromJson (inkl. Therapeuten-Felder)

import 'package:flutter/material.dart';
import '../services/local_storage.dart';

class AppSettings extends ChangeNotifier {
  // ---------------- Keys (namespace handled by LocalStorageService) -----------
  static const _kDarkMode       = 'settings:dark_mode';
  static const _kLargeText      = 'settings:large_text';
  static const _kColorBlind     = 'settings:color_blind';
  static const _kLocale         = 'settings:locale';         // "de_DE"

  // Therapeuten-Modus
  static const _kTherapistOn    = 'settings:therapist_mode';
  static const _kTherapistCode  = 'settings:therapist_code'; // secure storage
  static const _kShareUntil     = 'settings:share_until';    // ISO-8601 UTC

  // ---------------- State -----------------------------------------------------
  bool darkMode = false;
  bool largeText = false;
  bool colorBlindMode = false;
  Locale locale = const Locale('de', 'DE');

  // Therapeuten-Modus
  bool therapistModeEnabled = false;
  String? therapistCode;        // optionaler Code (secure)
  DateTime? shareUntil;         // optionale Freigabe-Frist (UTC)

  bool _hydrated = false;
  bool get isHydrated => _hydrated;

  final LocalStorageService _storage;

  AppSettings({LocalStorageService? storage})
      : _storage = storage ?? LocalStorageService() {
    // Fire-and-forget Hydration (sicher & idempotent)
    _hydrate();
  }

  // ---------------- Public API (Setters/Toggles) -----------------------------

  ThemeMode get themeMode => darkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> toggleDarkMode(bool value, {bool persist = true}) async {
    if (darkMode == value) return;
    darkMode = value;
    notifyListeners();
    if (persist) await _storage.saveSetting<bool>(_kDarkMode, darkMode);
  }

  Future<void> toggleLargeText(bool value, {bool persist = true}) async {
    if (largeText == value) return;
    largeText = value;
    notifyListeners();
    if (persist) await _storage.saveSetting<bool>(_kLargeText, largeText);
  }

  Future<void> toggleColorBlind(bool value, {bool persist = true}) async {
    if (colorBlindMode == value) return;
    colorBlindMode = value;
    notifyListeners();
    if (persist) await _storage.saveSetting<bool>(_kColorBlind, colorBlindMode);
  }

  Future<void> setLocale(Locale l, {bool persist = true}) async {
    final same =
        locale.languageCode == l.languageCode &&
        (locale.countryCode ?? '') == (l.countryCode ?? '');
    if (same) return;

    locale = l;
    notifyListeners();
    if (persist) await _storage.saveSetting<String>(_kLocale, _encodeLocale(l));
  }

  // --- Therapeuten-Modus -----------------------------------------------------

  Future<void> setTherapistModeEnabled(bool value, {bool persist = true}) async {
    if (therapistModeEnabled == value) return;
    therapistModeEnabled = value;
    notifyListeners();
    if (persist) await _storage.saveSetting<bool>(_kTherapistOn, therapistModeEnabled);
  }

  /// Code setzen/entfernen. Leerer/Null-Code entfernt den gespeicherten Wert.
  Future<void> setTherapistCode(String? code, {bool persist = true}) async {
    final sanitized = _sanitizeCode(code);
    if (therapistCode == sanitized) return;
    therapistCode = sanitized;
    notifyListeners();
    if (persist) {
      if (sanitized == null) {
        await _storage.removeSecure(_kTherapistCode);
      } else {
        await _storage.saveSecure(_kTherapistCode, sanitized);
      }
    }
  }

  /// Optionales Enddatum für Freigaben setzen (UTC gespeichert). `null` entfernt.
  Future<void> setShareUntil(DateTime? dt, {bool persist = true}) async {
    final next = dt?.toUtc();
    final prev = shareUntil;
    final equal = (prev == null && next == null) ||
        (prev != null && next != null && prev.isAtSameMomentAs(next));
    if (equal) return;

    shareUntil = next;
    notifyListeners();

    if (persist) {
      if (next == null) {
        await _storage.remove(_kShareUntil);
      } else {
        await _storage.saveSetting<String>(_kShareUntil, next.toIso8601String());
      }
    }
  }

  /// Praktisch für UI: Ist ein Freigabefenster aktiv?
  bool get isShareWindowOpen {
    if (!therapistModeEnabled) return false;
    if (shareUntil == null) return false;
    return DateTime.now().toUtc().isBefore(shareUntil!);
  }

  // Schneller Reset (z. B. Debug/Support)
  Future<void> resetToDefaults({bool persist = true}) async {
    darkMode = false;
    largeText = false;
    colorBlindMode = false;
    locale = const Locale('de', 'DE');
    therapistModeEnabled = false;
    therapistCode = null;
    shareUntil = null;
    notifyListeners();

    if (persist) {
      await Future.wait([
        _storage.saveSetting<bool>(_kDarkMode, darkMode),
        _storage.saveSetting<bool>(_kLargeText, largeText),
        _storage.saveSetting<bool>(_kColorBlind, colorBlindMode),
        _storage.saveSetting<String>(_kLocale, _encodeLocale(locale)),
        _storage.saveSetting<bool>(_kTherapistOn, therapistModeEnabled),
        _storage.removeSecure(_kTherapistCode),
        _storage.remove(_kShareUntil),
      ]);
    }
  }

  // ---------------- Backup/Restore (optional) --------------------------------

  Map<String, dynamic> toJson() => {
        'darkMode': darkMode,
        'largeText': largeText,
        'colorBlindMode': colorBlindMode,
        'locale': _encodeLocale(locale),
        'therapistModeEnabled': therapistModeEnabled,
        'therapistCode': therapistCode, // bewusst mit exportiert
        'shareUntil': shareUntil?.toIso8601String(),
      };

  Future<void> applyFromJson(Map<String, dynamic> json, {bool persist = true}) async {
    final dm = json['darkMode'] == true;
    final lt = json['largeText'] == true;
    final cb = json['colorBlindMode'] == true;
    final locStr = (json['locale'] ?? '').toString();
    final loc = _decodeLocale(locStr) ?? const Locale('de', 'DE');

    final tOn = json['therapistModeEnabled'] == true;
    final tCode = _sanitizeCode(json['therapistCode']?.toString());
    final suIso = json['shareUntil']?.toString();
    final su = _parseDate(suIso);

    bool changed = false;
    void apply<T>(T prev, T next, void Function(T) setField) {
      if (prev != next) {
        setField(next);
        changed = true;
      }
    }

    apply<bool>(darkMode, dm, (v) => darkMode = v);
    apply<bool>(largeText, lt, (v) => largeText = v);
    apply<bool>(colorBlindMode, cb, (v) => colorBlindMode = v);

    if (locale.languageCode != loc.languageCode ||
        (locale.countryCode ?? '') != (loc.countryCode ?? '')) {
      locale = loc;
      changed = true;
    }

    apply<bool>(therapistModeEnabled, tOn, (v) => therapistModeEnabled = v);
    if (therapistCode != tCode) {
      therapistCode = tCode;
      changed = true;
    }

    final equalShare = (shareUntil == null && su == null) ||
        (shareUntil != null && su != null && shareUntil!.isAtSameMomentAs(su));
    if (!equalShare) {
      shareUntil = su;
      changed = true;
    }

    if (changed) {
      notifyListeners();
      if (persist) {
        await Future.wait([
          _storage.saveSetting<bool>(_kDarkMode, darkMode),
          _storage.saveSetting<bool>(_kLargeText, largeText),
          _storage.saveSetting<bool>(_kColorBlind, colorBlindMode),
          _storage.saveSetting<String>(_kLocale, _encodeLocale(locale)),
          _storage.saveSetting<bool>(_kTherapistOn, therapistModeEnabled),
          if (therapistCode == null)
            _storage.removeSecure(_kTherapistCode)
          else
            _storage.saveSecure(_kTherapistCode, therapistCode!),
          if (shareUntil == null)
            _storage.remove(_kShareUntil)
          else
            _storage.saveSetting<String>(_kShareUntil, shareUntil!.toIso8601String()),
        ]);
      }
    }
  }

  // ---------------- Hydration -------------------------------------------------

  Future<void> _hydrate() async {
    try {
      await _storage.init();

      final dm = await _storage.loadSetting<bool>(_kDarkMode);
      final lt = await _storage.loadSetting<bool>(_kLargeText);
      final cb = await _storage.loadSetting<bool>(_kColorBlind);
      final locStr = await _storage.loadSetting<String>(_kLocale);

      final tOn = await _storage.loadSetting<bool>(_kTherapistOn);
      final tCode = await _storage.loadSecure(_kTherapistCode);
      final suIso = await _storage.loadSetting<String>(_kShareUntil);

      bool changed = false;

      bool _apply<T>(T? incoming, T current, void Function(T) setField) {
        if (incoming != null && incoming != current) {
          setField(incoming);
          return true;
        }
        return false;
      }

      if (_apply<bool>(dm, darkMode, (v) => darkMode = v)) changed = true;
      if (_apply<bool>(lt, largeText, (v) => largeText = v)) changed = true;
      if (_apply<bool>(cb, colorBlindMode, (v) => colorBlindMode = v)) changed = true;

      final decoded = _decodeLocale(locStr);
      if (decoded != null &&
          (decoded.languageCode != locale.languageCode ||
              (decoded.countryCode ?? '') != (locale.countryCode ?? ''))) {
        locale = decoded;
        changed = true;
      }

      if (_apply<bool>(tOn, therapistModeEnabled, (v) => therapistModeEnabled = v)) {
        changed = true;
      }

      if (tCode != null && tCode != therapistCode) {
        therapistCode = _sanitizeCode(tCode);
        changed = true;
      }

      final su = _parseDate(suIso);
      final equalShare = (shareUntil == null && su == null) ||
          (shareUntil != null && su != null && shareUntil!.isAtSameMomentAs(su));
      if (!equalShare) {
        shareUntil = su;
        changed = true;
      }

      _hydrated = true;
      if (changed) notifyListeners();
      if (!changed) notifyListeners(); // signalisiert: geladen
    } catch (_) {
      _hydrated = true;
      notifyListeners();
    }
  }

  // ---------------- Helpers ---------------------------------------------------

  static String _encodeLocale(Locale l) {
    final cc = l.countryCode;
    return (cc == null || cc.isEmpty) ? l.languageCode : '${l.languageCode}_${cc}';
  }

  static Locale? _decodeLocale(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final parts = s.split(RegExp(r'[-_]'));
    if (parts.length == 1) return Locale(parts[0]);
    return Locale(parts[0], parts[1]);
  }

  static DateTime? _parseDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    return dt?.toUtc();
  }

  static String? _sanitizeCode(String? code) {
    if (code == null) return null;
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    // Erlaube alnum, -, _ ; Länge 6..32
    final ok = RegExp(r'^[A-Za-z0-9\-_]{6,32}$').hasMatch(trimmed);
    return ok ? trimmed : null;
  }
}
