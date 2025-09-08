import 'package:flutter/material.dart';
import 'package:zenyourself/models/user.dart';

/// UserProfileProvider
/// -------------------
/// Globale User-State-Verwaltung für ZenYourself:
/// - Beibehalt deiner API (displayName, userId, isLoggedIn, setUser, updateUser, clearUser)
/// - Ergänzt: optionale Persistenz-Callbacks (load/save/clear), async init(),
///   Loading-Flag, sichere Updates, Upsert-Pattern, nützliche UI-Helper.
class UserProfileProvider with ChangeNotifier {
  ZenUser? _user;
  bool _loading = false;
  DateTime? _lastUpdate;

  /// Optionale Persistenz-Callbacks (frei injizierbar)
  final Future<ZenUser?> Function()? _loadUserFn;
  final Future<void> Function(ZenUser user)? _saveUserFn;
  final Future<void> Function()? _clearUserFn;

  /// Konstruktor:
  /// - [initialUser] für sofortigen Start (z. B. nach Splash/Restore)
  /// - [loadUserFn]/[saveUserFn]/[clearUserFn] für Persistenz (optional)
  UserProfileProvider({
    ZenUser? initialUser,
    Future<ZenUser?> Function()? loadUserFn,
    Future<void> Function(ZenUser user)? saveUserFn,
    Future<void> Function()? clearUserFn,
  })  : _user = initialUser,
        _loadUserFn = loadUserFn,
        _saveUserFn = saveUserFn,
        _clearUserFn = clearUserFn;

  // -------- State / Status --------

  /// Aktuelles Profil (null, wenn nicht eingeloggt)
  ZenUser? get user => _user;

  /// Ist ein User vorhanden?
  bool get isLoggedIn => _user != null;

  /// Lädt aktuell?
  bool get isLoading => _loading;

  /// Letztes Änderungsdatum (lokal)
  DateTime? get lastUpdate => _lastUpdate;

  /// Anzeigename (Fallback: "Gast")
  String get displayName {
    final name = _user?.displayName.trim();
    return (name != null && name.isNotEmpty) ? name : 'Gast';
  }

  /// User-ID (Fallback: "unknown")
  String get userId => _user?.id ?? 'unknown';

  /// Optionales Profilbild-Asset (solange nicht im Model)
  String get profileImage => 'assets/user_default.png';

  /// Kürzel/Initialen für Avatare („GA“, „ME“…)
  String get initials {
    final n = displayName.trim();
    if (n.isEmpty || n == 'Gast') return 'G';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return n.characters.first.toUpperCase();
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  /// Einfaches freundliches Greeting
  String get greeting => 'Hallo, $displayName';

  // -------- Lifecycle / Persistenz --------

  /// Optionaler Initial-Load aus Persistenz.
  Future<void> init() async {
    if (_loadUserFn == null) return;
    _setLoading(true);
    try {
      final loaded = await _loadUserFn.call();
      if (loaded != null) {
        _user = loaded;
        _lastUpdate = DateTime.now();
      }
    } finally {
      _setLoading(false);
    }
  }

  // -------- Mutationen --------

  /// Setzt das User-Profil (synchron). Nutze [setUserAsync] für Persistenz.
  void setUser(ZenUser user, {bool notify = true}) {
    _user = user;
    _lastUpdate = DateTime.now();
    if (notify) notifyListeners();
  }

  /// Setzt & speichert das User-Profil (falls save-Callback gesetzt).
  Future<void> setUserAsync(ZenUser user, {bool notify = true}) async {
    setUser(user, notify: false);
    if (_saveUserFn != null) {
      await _saveUserFn(user);
    }
    if (notify) notifyListeners();
  }

  /// Selektives Update (z. B. displayName). Ruft `copyWith` auf dem Model.
  void updateUser({String? displayName, bool notify = true}) {
    if (_user == null) return;
    _user = _user!.copyWith(displayName: displayName ?? _user!.displayName);
    _lastUpdate = DateTime.now();
    if (notify) notifyListeners();
  }

  /// Funktionales Update (beliebige Mutation über copyWith).
  /// Beispiel:
  ///   provider.mutateUser((u) => u.copyWith(locale: 'de-DE'));
  void mutateUser(ZenUser Function(ZenUser u) mutate, {bool notify = true}) {
    if (_user == null) return;
    _user = mutate(_user!);
    _lastUpdate = DateTime.now();
    if (notify) notifyListeners();
  }

  /// Logout/Clear (synchron). Nutze [clearUserAsync], wenn Persistenz bereinigt werden soll.
  void clearUser({bool notify = true}) {
    _user = null;
    _lastUpdate = DateTime.now();
    if (notify) notifyListeners();
  }

  /// Logout/Clear inkl. Persistenz.
  Future<void> clearUserAsync({bool notify = true}) async {
    clearUser(notify: false);
    if (_clearUserFn != null) {
      await _clearUserFn.call();
    }
    if (notify) notifyListeners();
  }

  // -------- intern --------
  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }
}
