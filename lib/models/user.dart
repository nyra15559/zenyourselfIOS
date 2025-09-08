import 'package:flutter/material.dart';

/// ZenYourself User Model — Oxford Safety Edition
/// ------------------------------------------------
/// Fokus: maximale Privatsphäre & psychische Sicherheit.
/// - Privacy-by-default (lokal, keine Telemetrie, sensible Filter an)
/// - Robuste (de-)Serialisierung, defensive Fallbacks
/// - Redaction-/Export-Hilfen (PII entfernen)
/// - Sanfte UI-Preferences (Trigger-Filter, weniger Druck)
@immutable
class ZenUser {
  /// Eindeutige Nutzer-ID (lokal generiert, niemals öffentlich).
  final String id;

  /// Anzeigename (Pseudonym empfohlen; keine E-Mail-Adresse).
  final String displayName;

  /// Optional: Avatar-Pfad (Asset/Datei/Netz).
  final String? avatarPath;

  /// Account-Typ: 'anonym' | 'local' | 'oauth' | 'therapist'
  final String accountType;

  /// Pro-/Lizenz-Status.
  final bool isPro;

  /// Strikter Datenschutzmodus: alles lokal, kein Sync.
  final bool localOnly;

  /// Bevorzugte Sprache (z. B. 'de', 'en').
  final String? preferredLanguage;

  /// A11y.
  final bool colorBlindMode;
  final bool largeTextMode;

  /// Nutzungsstatistik (aggregiert, unsensibel).
  final int totalReflections;
  final int totalMoodEntries;

  /// Darf der User Export durchführen?
  final bool allowExport;

  /// Letzter App-Start/-Login.
  final DateTime lastActive;

  // ======================
  //  Safety & Privacy Flags
  // ======================

  /// Zeige Hinweise auf Krisen-Hotlines/Notfallressourcen.
  final bool showCrisisResources;

  /// Inhaltliche Trigger filtern/entschärfen (sanfte Wortwahl).
  final bool sensitiveContentFilter;

  /// Gamification (Streaks/Badges) ausblenden → weniger Druck.
  final bool hideGamification;

  /// Stille Benachrichtigungen/Reminder erlauben?
  final bool allowPushReminders;

  /// Einwilligung zur anonymisierten Diagnostik/Telemetry (opt-in).
  final bool consentAnalytics;

  /// Einwilligung für AI-gestützte Vorschläge (lokal/Backend).
  final bool consentAiSuggestions;

  /// Aufbewahrungstage für Inhalte (0 = keine Begrenzung).
  final int retentionDays;

  /// Ob alte Inhalte nach [retentionDays] automatisch entfernt werden.
  final bool autoDeleteOldEntries;

  /// Region/ISO-Code für lokale Hilfsangebote (z. B. 'DE', 'AT', 'CH').
  final String? regionCode;

  /// Version der geltenden Datenschutz-/Sicherheitsrichtlinie.
  final String privacyVersion;

  const ZenUser({
    required this.id,
    required this.displayName,
    this.avatarPath,
    this.accountType = 'anonym',
    this.isPro = false,
    this.localOnly = true,
    this.preferredLanguage,
    this.colorBlindMode = false,
    this.largeTextMode = false,
    this.totalReflections = 0,
    this.totalMoodEntries = 0,
    this.allowExport = true,
    required this.lastActive,

    // Safety & Privacy (Defaults bewusst konservativ)
    this.showCrisisResources = true,
    this.sensitiveContentFilter = true,
    this.hideGamification = true,
    this.allowPushReminders = false,
    this.consentAnalytics = false,
    this.consentAiSuggestions = true,
    this.retentionDays = 0, // 0 = unbegrenzt (keine Überraschungs-Löschungen)
    this.autoDeleteOldEntries = false,
    this.regionCode,
    this.privacyVersion = '1.0',
  });

  // ===========
  //  JSON I/O
  // ===========
  factory ZenUser.fromJson(Map<String, dynamic> json) => ZenUser(
        id: (json['id'] ?? '').toString(),
        displayName: _sanitizeName((json['displayName'] ?? 'Gast').toString()),
        avatarPath: _toNullableString(json['avatarPath']),
        accountType: (json['accountType'] ?? 'anonym').toString(),
        isPro: _toBool(json['isPro'], fallback: false),
        localOnly: _toBool(json['localOnly'], fallback: true),
        preferredLanguage: _toNullableString(json['preferredLanguage']),
        colorBlindMode: _toBool(json['colorBlindMode'], fallback: false),
        largeTextMode: _toBool(json['largeTextMode'], fallback: false),
        totalReflections: _toInt(json['totalReflections'], fallback: 0),
        totalMoodEntries: _toInt(json['totalMoodEntries'], fallback: 0),
        allowExport: _toBool(json['allowExport'], fallback: true),
        lastActive: _parseDate(json['lastActive']) ?? DateTime.now(),

        showCrisisResources: _toBool(json['showCrisisResources'], fallback: true),
        sensitiveContentFilter: _toBool(json['sensitiveContentFilter'], fallback: true),
        hideGamification: _toBool(json['hideGamification'], fallback: true),
        allowPushReminders: _toBool(json['allowPushReminders'], fallback: false),
        consentAnalytics: _toBool(json['consentAnalytics'], fallback: false),
        consentAiSuggestions: _toBool(json['consentAiSuggestions'], fallback: true),
        retentionDays: _toInt(json['retentionDays'], fallback: 0),
        autoDeleteOldEntries: _toBool(json['autoDeleteOldEntries'], fallback: false),
        regionCode: _toNullableString(json['regionCode']),
        privacyVersion: (json['privacyVersion'] ?? '1.0').toString(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'avatarPath': avatarPath,
        'accountType': accountType,
        'isPro': isPro,
        'localOnly': localOnly,
        'preferredLanguage': preferredLanguage,
        'colorBlindMode': colorBlindMode,
        'largeTextMode': largeTextMode,
        'totalReflections': totalReflections,
        'totalMoodEntries': totalMoodEntries,
        'allowExport': allowExport,
        'lastActive': lastActive.toUtc().toIso8601String(),
        'showCrisisResources': showCrisisResources,
        'sensitiveContentFilter': sensitiveContentFilter,
        'hideGamification': hideGamification,
        'allowPushReminders': allowPushReminders,
        'consentAnalytics': consentAnalytics,
        'consentAiSuggestions': consentAiSuggestions,
        'retentionDays': retentionDays,
        'autoDeleteOldEntries': autoDeleteOldEntries,
        'regionCode': regionCode,
        'privacyVersion': privacyVersion,
      }..removeWhere((_, v) => v == null);

  /// Reduzierte, PII-arme Repräsentation (für Support/Telemetry).
  Map<String, dynamic> toRedactedJson() => <String, dynamic>{
        'id': _hashId(id),
        'accountType': accountType,
        'isPro': isPro,
        'localOnly': localOnly,
        'colorBlindMode': colorBlindMode,
        'largeTextMode': largeTextMode,
        'totalReflections': totalReflections,
        'totalMoodEntries': totalMoodEntries,
        'showCrisisResources': showCrisisResources,
        'sensitiveContentFilter': sensitiveContentFilter,
        'hideGamification': hideGamification,
        'allowPushReminders': allowPushReminders,
        'consentAnalytics': consentAnalytics,
        'consentAiSuggestions': consentAiSuggestions,
        'retentionDays': retentionDays,
        'autoDeleteOldEntries': autoDeleteOldEntries,
        'regionCode': regionCode,
        'privacyVersion': privacyVersion,
      }..removeWhere((_, v) => v == null);

  // ===========
  //  UI Helpers
  // ===========
  IconData get icon {
    switch (accountType) {
      case 'therapist':
        return Icons.health_and_safety;
      case 'oauth':
        return Icons.verified_user;
      case 'local':
        return Icons.person;
      default:
        return Icons.emoji_nature;
    }
  }

  String get emoji {
    if (accountType == 'therapist') return '🧑‍⚕️';
    if (isPro) return '🌟';
    if (localOnly) return '🔒';
    return '🙂';
  }

  String get lastActiveFormatted {
    final diff = DateTime.now().difference(lastActive);
    if (diff.inDays >= 1) return '${diff.inDays} Tage aktiv';
    if (diff.inHours >= 1) return '${diff.inHours} Std. aktiv';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} Min. aktiv';
    return 'Gerade aktiv';
  }

  /// Initialen (für Avatar mit Buchstaben).
  String get initials {
    final n = displayName.trim();
    if (n.isEmpty || n.toLowerCase() == 'gast') return 'G';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  /// Ist das Profil effektiv anonym?
  bool get isAnonymous => accountType == 'anonym' || localOnly == true;

  /// Sollten Einträge nach Aufbewahrungszeit entfernt werden?
  bool shouldAutoDelete() => autoDeleteOldEntries && retentionDays > 0;

  /// Zeitpunkt, ab dem Inhalte verfallen (oder null, wenn unbegrenzt).
  DateTime? deleteBefore(DateTime now) {
    if (!shouldAutoDelete()) return null;
    return now.subtract(Duration(days: retentionDays));
  }

  /// lastActive „antippen“ (ohne andere Felder zu verändern).
  ZenUser touchActive() => copyWith(lastActive: DateTime.now());

  // ===========
  //  Copy & Eq
  // ===========
  ZenUser copyWith({
    String? id,
    String? displayName,
    String? avatarPath,
    String? accountType,
    bool? isPro,
    bool? localOnly,
    String? preferredLanguage,
    bool? colorBlindMode,
    bool? largeTextMode,
    int? totalReflections,
    int? totalMoodEntries,
    bool? allowExport,
    DateTime? lastActive,
    bool? showCrisisResources,
    bool? sensitiveContentFilter,
    bool? hideGamification,
    bool? allowPushReminders,
    bool? consentAnalytics,
    bool? consentAiSuggestions,
    int? retentionDays,
    bool? autoDeleteOldEntries,
    String? regionCode,
    String? privacyVersion,
  }) {
    return ZenUser(
      id: id ?? this.id,
      displayName: displayName != null ? _sanitizeName(displayName) : this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      accountType: accountType ?? this.accountType,
      isPro: isPro ?? this.isPro,
      localOnly: localOnly ?? this.localOnly,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      colorBlindMode: colorBlindMode ?? this.colorBlindMode,
      largeTextMode: largeTextMode ?? this.largeTextMode,
      totalReflections: totalReflections ?? this.totalReflections,
      totalMoodEntries: totalMoodEntries ?? this.totalMoodEntries,
      allowExport: allowExport ?? this.allowExport,
      lastActive: lastActive ?? this.lastActive,
      showCrisisResources: showCrisisResources ?? this.showCrisisResources,
      sensitiveContentFilter: sensitiveContentFilter ?? this.sensitiveContentFilter,
      hideGamification: hideGamification ?? this.hideGamification,
      allowPushReminders: allowPushReminders ?? this.allowPushReminders,
      consentAnalytics: consentAnalytics ?? this.consentAnalytics,
      consentAiSuggestions: consentAiSuggestions ?? this.consentAiSuggestions,
      retentionDays: retentionDays ?? this.retentionDays,
      autoDeleteOldEntries: autoDeleteOldEntries ?? this.autoDeleteOldEntries,
      regionCode: regionCode ?? this.regionCode,
      privacyVersion: privacyVersion ?? this.privacyVersion,
    );
  }

  @override
  String toString() => 'ZenUser($id, $displayName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZenUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          displayName == other.displayName &&
          avatarPath == other.avatarPath &&
          accountType == other.accountType &&
          isPro == other.isPro &&
          localOnly == other.localOnly &&
          preferredLanguage == other.preferredLanguage &&
          colorBlindMode == other.colorBlindMode &&
          largeTextMode == other.largeTextMode &&
          totalReflections == other.totalReflections &&
          totalMoodEntries == other.totalMoodEntries &&
          allowExport == other.allowExport &&
          lastActive == other.lastActive &&
          showCrisisResources == other.showCrisisResources &&
          sensitiveContentFilter == other.sensitiveContentFilter &&
          hideGamification == other.hideGamification &&
          allowPushReminders == other.allowPushReminders &&
          consentAnalytics == other.consentAnalytics &&
          consentAiSuggestions == other.consentAiSuggestions &&
          retentionDays == other.retentionDays &&
          autoDeleteOldEntries == other.autoDeleteOldEntries &&
          regionCode == other.regionCode &&
          privacyVersion == other.privacyVersion;

  @override
  int get hashCode => Object.hashAll([
        id,
        displayName,
        avatarPath,
        accountType,
        isPro,
        localOnly,
        preferredLanguage,
        colorBlindMode,
        largeTextMode,
        totalReflections,
        totalMoodEntries,
        allowExport,
        lastActive.millisecondsSinceEpoch,
        showCrisisResources,
        sensitiveContentFilter,
        hideGamification,
        allowPushReminders,
        consentAnalytics,
        consentAiSuggestions,
        retentionDays,
        autoDeleteOldEntries,
        regionCode,
        privacyVersion,
      ]);

  // ===============
  //  Static Helpers
  // ===============
  static String _sanitizeName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Gast';
    // Falls E-Mail/Telefon hereinschneit → anonymisieren
    if (RegExp(r'@').hasMatch(n) || RegExp(r'^\+?\d').hasMatch(n)) {
      return 'Gast';
    }
    return n;
  }

  static String? _toNullableString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool _toBool(dynamic v, {required bool fallback}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return fallback;
  }

  static int _toInt(dynamic v, {required int fallback}) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) {
      final p = int.tryParse(v);
      if (p != null) return p;
    }
    return fallback;
  }

  /// Unterstützt ISO-8601 String / Epoch (ms) / DateTime.
  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) {
      // Epoch (ms oder s → Heuristik)
      if (v > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true);
      }
    }
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Hash der ID (billig & ausreichend für Redaction-Zwecke).
  static String _hashId(String id) {
    // einfache FNV-1a Variante
    int hash = 0x811C9DC5;
    for (final codeUnit in id.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Bequemer Erzeuger eines anonymen Default-Nutzers.
  static ZenUser anonymous({required String id, String? regionCode}) => ZenUser(
        id: id,
        displayName: 'Gast',
        accountType: 'anonym',
        localOnly: true,
        isPro: false,
        allowExport: true,
        lastActive: DateTime.now(),
        showCrisisResources: true,
        sensitiveContentFilter: true,
        hideGamification: true,
        allowPushReminders: false,
        consentAnalytics: false,
        consentAiSuggestions: true,
        retentionDays: 0,
        autoDeleteOldEntries: false,
        regionCode: regionCode,
        privacyVersion: '1.0',
      );
}
