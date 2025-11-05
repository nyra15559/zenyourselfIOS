// [BASELINE] lib/main.dart (Stand: 04.11.2025 · v1.7.0)
// ZenYourself — App Bootstrap (Oxford-Zen, Pro-Level, Material 3)
// -----------------------------------------------------------------------------
// • EINZIGE MaterialApp im Projekt (verhindert Routing-Konflikte).
// • Alle benannten Routen (/, /reflection, /journey, …) hier registriert.
// • Robustes Bootstrapping (runZonedGuarded, PlatformDispatcher.onError).
// • Provider-Setup inkl. Journal-Persistenz (kanonisch).
// • A11y, i18n, Themes (Material 3), sanftes Scroll-Verhalten.
// • MemoryService.init()/warmup()/ensureGreetingNameLoaded() beim Start,
//   damit Consent/Active/Name vor dem ersten Turn verfügbar sind.
// • NEU v1.7.0: ReflectionSession-Provider mit frischer Session-ID
//   beim Öffnen von /reflection (ohne externe uuid-Abhängigkeit).
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';

// Routing-Konstanten
import 'app/app.dart' show AppRoutes;

// --- State Management Provider ---
import 'models/mood_entries_provider.dart';
import 'models/reflection_entries_provider.dart';
import 'models/user_profile_provider.dart';
import 'models/app_settings.dart'; // ← persistente AppSettings (KANON)
import 'providers/journal_entries_provider.dart'; // ← kanonischer Journal-Store

// --- Kanonisches Journal-Modell (für Provider + Persistenz) ---
import 'models/journal_entry.dart' as jm;

// --- Accessibility ---
import 'features/accessibility/color_blind_mode.dart';
import 'features/accessibility/large_text_mode.dart';
import 'features/accessibility/a11y_utils.dart';

// --- Audio/Sound ---
import 'audio/soundscape_manager.dart';

// --- Local Storage Service ---
import 'services/local_storage.dart';

// --- Services (Pro): Guidance + ApiClient ---
import 'services/guidance_service.dart';
import 'services/api_client.dart';

// --- Core Screens ---
import 'features/start/start_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/reflection/reflection_screen.dart';
import 'features/impulse/impulse_screen.dart';
import 'features/story/story_screen.dart';
import 'features/pro/pro_screen.dart';
import 'features/journey/journey_map.dart';

// --- Env Defaults / Fallback ---
import 'env_config.dart';

// --- Memory Layer Bootstrap ---
import 'core/memory/memory_service.dart';

// --- Community Services ---
import 'services/community/api_community.dart' as comm;
import 'services/community/community_stats_api.dart' as cstats;

/// Compile-Time Konfiguration (per --dart-define)
const String _kApiUrl = String.fromEnvironment('ZEN_API_URL', defaultValue: '');
const bool _kApiEnabled =
    bool.fromEnvironment('ZEN_API_ENABLED', defaultValue: true);
const String _kApiToken =
    String.fromEnvironment('ZEN_APP_TOKEN', defaultValue: '');

// Community: bewusst standardmäßig AUS, bis ihr eine URL hinterlegt.
const bool _kCommEnabled =
    bool.fromEnvironment('ZEN_COMMUNITY_ENABLED', defaultValue: false);
const String _kCommUrl =
    String.fromEnvironment('ZEN_COMMUNITY_URL', defaultValue: '');
const String _kCommApiKey =
    String.fromEnvironment('ZEN_COMMUNITY_API_KEY', defaultValue: '');
const String _kCommHmacSecret =
    String.fromEnvironment('ZEN_COMMUNITY_HMAC', defaultValue: '');
const String _kCommRespHmac =
    String.fromEnvironment('ZEN_COMMUNITY_RESP_HMAC', defaultValue: '');

// -----------------------------------------------------------------------------
// ReflectionSession — stellt eine frische Session-ID pro Reflexionsstart bereit
// -----------------------------------------------------------------------------
class ReflectionSession {
  final String id;
  final DateTime startedAtUtc;

  ReflectionSession._(this.id, this.startedAtUtc);

  /// Robuste v4-ähnliche ID (ohne externe Abhängigkeit).
  static String newId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant
    String _hx(int b) => b.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(_hx).toList(growable: false);
    return '${b[0]}${b[1]}${b[2]}${b[3]}-'
           '${b[4]}${b[5]}-'
           '${b[6]}${b[7]}-'
           '${b[8]}${b[9]}-'
           '${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
  }

  static ReflectionSession fresh() =>
      ReflectionSession._(newId(), DateTime.now().toUtc());
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Lokaler Storage
    try {
      await LocalStorageService().init();
    } catch (e, st) {
      debugPrint('[Init] LocalStorage error: $e\n$st');
    }

    // MemoryService (Kontext-Gedächtnis) initialisieren – vor App-Start.
    try {
      await MemoryService.instance.init();
      // Warmup (Topics/Facets laden), Name/Greet Sync-Cache füllen
      // ignore: discarded_futures
      MemoryService.instance.warmup();
      await MemoryService.instance.ensureGreetingNameLoaded();
      debugPrint('✅ MemoryService ready (consent/active/name preloaded).');

      // --- Dev-Opt-in (nur Debug): Consent + Greet aktivieren ----------------
      if (kDebugMode) {
        try {
          final dyn = MemoryService.instance as dynamic;
          await (dyn.setShareEnabled?.call(true));
          await (dyn.setGreetingConsent?.call(true));
          debugPrint('✅ Memory (debug): consent+greet enabled for local testing.');
        } catch (_) {/* ignore */}
      }
      // ----------------------------------------------------------------------
    } catch (e, st) {
      debugPrint('⚠️  MemoryService init failed (continuing without memory): $e\n$st');
    }

    // Fehlerabfang (Flutter/UI)
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details);
    };
    // Fehlerabfang (Dart/Plattform)
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      debugPrint('[Platform] Uncaught: $error\n$stack');
      return true;
    };

    // HTTP-Backend initialisieren (mit Fallback)
    _setupZenApi();

    // Community (GET-Stats + signed POST) initialisieren — sanft & optional
    _setupCommunityApis();

    if (kDebugMode) {
      _printRuntimeSummaryAndCliHints();
    }

    runApp(const ZenYourselfApp());
  }, (e, st) {
    debugPrint('[Zoned] Uncaught: $e\n$st');
  });
}

/// Liest zuerst --dart-define, sonst lib/env_config.dart.
void _setupZenApi() {
  final bool definesUsed =
      _kApiUrl.isNotEmpty || _kApiToken.isNotEmpty || !_kApiEnabled;

  final bool enabled = definesUsed ? _kApiEnabled : ZenEnv.apiEnabled;
  final String url =
      definesUsed && _kApiUrl.isNotEmpty ? _kApiUrl : ZenEnv.apiUrl;
  final String token =
      definesUsed && _kApiToken.isNotEmpty ? _kApiToken : ZenEnv.appToken;

  if (enabled && url.isNotEmpty) {
    try {
      final client = ApiClient(
        baseUrl: Uri.parse(url),
        tokenProvider: () async => token.isNotEmpty ? token : null,
        onLog: (msg) => debugPrint('[Api] $msg'),
      );

      GuidanceService.instance.configureHttp(
        invoker: client.call,
        baseUrl: client.baseUrlStr,
      );

      debugPrint('✅ GuidanceService HTTP enabled → $url');
      if (token.isEmpty) {
        debugPrint('⚠️  Guidance: Kein APP_TOKEN gesetzt – dein Worker könnte 401/403 liefern.');
      } else {
        debugPrint('ℹ️ Guidance: Auth=Bearer (Token vorhanden).');
      }
    } catch (e, st) {
      debugPrint('❌ ApiClient setup failed: $e\n$st');
    }
  } else {
    debugPrint(
      'ℹ️ GuidanceService HTTP disabled (lokaler Fallback aktiv). '
      'Grund: enabled=$enabled, url="${url.isEmpty ? '<leer>' : url}"',
    );
  }
}

/// Community-Bootstrap: GET-Stats (ohne Signatur) + POST (signiert, optional).
void _setupCommunityApis() {
  if (!_kCommEnabled) {
    debugPrint('ℹ️ Community APIs disabled (ZEN_COMMUNITY_ENABLED=false).');
    return;
  }
  if (_kCommUrl.isEmpty) {
    debugPrint('ℹ️ Community APIs: baseUrl ist leer – deaktiviert.');
    return;
  }

  try {
    // 1) GET-Stats (kein Secret nötig)
    cstats.CommunityStatsApi.instance.configure(
      baseUrl: _kCommUrl,
    );

    // 2) Signierter POST (nur wenn Key+Secret vorhanden)
    comm.CommunityApi.instance.configure(
      baseUrl: _kCommUrl,
      apiKey: _kCommApiKey,
      hmacSecret: _kCommHmacSecret,
      responseHmacSecret: _kCommRespHmac.isNotEmpty ? _kCommRespHmac : null,
    );

    if (_kCommApiKey.isEmpty || _kCommHmacSecret.isEmpty) {
      debugPrint('⚠️ CommunityApi: API_KEY/HMAC fehlen – POST-Acks werden scheitern (UI fängt es ab).');
    }

    debugPrint('✅ Community APIs enabled → ${_kCommUrl}');
  } catch (e, st) {
    debugPrint('❌ Community setup failed: $e\n$st');
  }
}

/// Debug-Übersicht + sichere CLI-Hinweise (maskiert).
void _printRuntimeSummaryAndCliHints() {
  // Guidance
  final String gUrl = (_kApiUrl.isNotEmpty ? _kApiUrl : ZenEnv.apiUrl);
  final bool gEnabled =
      (_kApiUrl.isNotEmpty || _kApiToken.isNotEmpty || !_kApiEnabled)
          ? _kApiEnabled
          : ZenEnv.apiEnabled;
  final bool gHasToken = (_kApiToken.isNotEmpty || ZenEnv.appToken.isNotEmpty);

  debugPrint('— — — RUNTIME SUMMARY — — —');
  debugPrint(
      'Guidance: enabled=$gEnabled, url=${gUrl.isEmpty ? "<leer>" : gUrl}, auth=${gHasToken ? "Bearer" : "none"}');

  // Community
  final bool cEnabled = _kCommEnabled && _kCommUrl.isNotEmpty;
  debugPrint(
      'Community: enabled=$cEnabled, url=${_kCommUrl.isEmpty ? "<leer>" : _kCommUrl}, '
      'postAuth=${(_kCommApiKey.isNotEmpty && _kCommHmacSecret.isNotEmpty) ? "API_KEY+HMAC" : "none"}');

  // CLI-Hints (maskiert)
  if (gUrl.isNotEmpty) {
    final maskedToken =
        _mask(_kApiToken.isNotEmpty ? _kApiToken : ZenEnv.appToken);
    final maskedApiKey = _mask(_kCommApiKey);
    final maskedHmac = _mask(_kCommHmacSecret);

    debugPrint('— — — CLI HINTS (copy/paste) — — —');
    debugPrint('export ZEN_GUIDANCE="$gUrl"');
    if ((_kApiToken.isNotEmpty || ZenEnv.appToken.isNotEmpty)) {
      debugPrint('# Bearer (App-Token, maskiert): ${maskedToken.isEmpty ? "<none>" : maskedToken}');
      debugPrint('export ZEN_APP_TOKEN="<DEIN_BEARER_TOKEN_HIER>"');
    } else {
      debugPrint('# Kein Bearer-Token in der App-Konfiguration gefunden.');
    }

    if (_kCommUrl.isNotEmpty) {
      debugPrint('export ZEN_COMMUNITY="${_kCommUrl}"');
    }
    if (_kCommApiKey.isNotEmpty) {
      debugPrint('# Community API-Key (maskiert): ${maskedApiKey}');
      debugPrint('export ZEN_API_KEY="<DEIN_COMMUNITY_API_KEY_HIER>"');
    }
    if (_kCommHmacSecret.isNotEmpty) {
      debugPrint('# Community HMAC (maskiert): ${maskedHmac}');
      debugPrint('export ZEN_APP_SECRET="<DEIN_COMMUNITY_HMAC_SECRET_HIER>"');
    }
    debugPrint('# Debug einschalten (zeigt im CLI die probierten Pfade):');
    debugPrint('export ZEN_DEBUG=1');
    debugPrint('— — — — — — — — — — — — — —');
  }
}

String _mask(String s, {int keepHead = 4, int keepTail = 3}) {
  final t = s.trim();
  if (t.isEmpty) return '';
  if (t.length <= keepHead + keepTail) return '${t[0]}***${t[t.length - 1]}';
  final head = t.substring(0, keepHead);
  final tail = t.substring(t.length - keepTail);
  return '$head***$tail';
}

class ZenYourselfApp extends StatelessWidget {
  const ZenYourselfApp({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = LocalStorageService();

    return MultiProvider(
      providers: [
        // --- A11y / System ---
        ChangeNotifierProvider(create: (_) => ColorBlindModeProvider(false)),
        ChangeNotifierProvider(create: (_) => LargeTextModeProvider()),
        Provider(create: (_) => SoundscapeManager()), // kein ChangeNotifier
        ChangeNotifierProvider(create: (_) => UserProfileProvider()),
        ChangeNotifierProvider(create: (_) => AppSettings()),

        // --- Domain ---
        ChangeNotifierProvider(create: (_) => MoodEntriesProvider()),
        ChangeNotifierProvider(create: (_) => ReflectionEntriesProvider()),

        // JournalEntriesProvider mit Persistenz-Hooks (KANON)
        ChangeNotifierProvider(
          create: (_) {
            final p = JournalEntriesProvider();
            // Restore & Persist (asynchron starten)
            p.attachPersistence(
              load: () async => storage.loadJournalEntries<jm.JournalEntry>(
                jm.JournalEntry.fromMap,
              ),
              save: (entries) async => storage.saveJournalEntries(entries),
              loadNow: true,
            );
            return p;
          },
        ),
      ],
      child: const _ZenYourselfMaterialApp(),
    );
  }
}

class _ZenYourselfMaterialApp extends StatelessWidget {
  const _ZenYourselfMaterialApp();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final isDark = settings.darkMode;

    return A11yProvider(
      colorBlind: context.watch<ColorBlindModeProvider>().enabled,
      darkMode: isDark,
      child: LargeTextProvider(
        child: MaterialApp(
          restorationScopeId: 'zenyourself-app',
          debugShowCheckedModeBanner: false,
          // Material 3 explizit aktivieren
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: AppTheme.light.copyWith(useMaterial3: true),
          darkTheme: AppTheme.dark.copyWith(useMaterial3: true),
          themeAnimationDuration: const Duration(milliseconds: 240),
          themeAnimationCurve: Curves.easeInOutCubicEmphasized,
          useInheritedMediaQuery: true,

          // Locale / i18n
          locale: settings.locale,
          supportedLocales: const [
            Locale('de', 'DE'),
            Locale('en', 'US'),
            Locale('fr', 'FR'),
            Locale('it', 'IT'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeListResolutionCallback:
              (List<Locale>? locales, Iterable<Locale> supported) {
            if (locales == null || locales.isEmpty) return supported.first;
            for (final dev in locales) {
              for (final s in supported) {
                final lang = s.languageCode == dev.languageCode;
                final regionOk =
                    s.countryCode == null || s.countryCode == dev.countryCode;
                if (lang && regionOk) return s;
              }
              for (final s in supported) {
                if (s.languageCode == dev.languageCode) return s;
              }
            }
            return supported.first;
          },

          // UX-Verhalten
          scrollBehavior: const _ZenScrollBehavior(),

          // === EINZIGE Routing-Quelle ===
          initialRoute: AppRoutes.start,

          // Statische Routen (ohne /reflection – dafür onGenerateRoute)
          routes: {
            AppRoutes.start: (_) => const StartScreen(),
            AppRoutes.journal: (_) => const JournalScreen(),
            AppRoutes.impulse: (_) => const ImpulseScreen(),
            AppRoutes.story: (_) => const StoryScreen(),
            AppRoutes.pro: (_) => const ProScreen(
                  moodEntries: [],
                  reflectionEntries: [],
                ),
            AppRoutes.journey: (_) => const JourneyMapScreen(
                  moodEntries: [],
                  reflections: [],
                ),
            AppRoutes.menu: (_) => const JourneyMapScreen(
                  moodEntries: [],
                  reflections: [],
                ),
            '/gedankenbuch': (_) => const StoryScreen(), // historischer Alias
          },

          // Dynamische Route für /reflection → frische Session-ID + Provider
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.reflection) {
              final session = ReflectionSession.fresh();
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => Provider<ReflectionSession>.value(
                  value: session,
                  // ReflectionScreen bleibt unverändert.
                  // reflection_logic kann die Session-ID bei Bedarf
                  // via Provider (dynamic) lesen; kein Import auf main.dart nötig:
                  //   final s = Provider.of<dynamic>(context, listen:false);
                  //   final sessionId = (s?.id as String?) ?? '<fallback>';
                  child: const ReflectionScreen(),
                ),
              );
            }
            return null; // Unknown → fallback unten
          },

          onUnknownRoute: (_) =>
              MaterialPageRoute(builder: (_) => const StartScreen()),
        ),
      ),
    );
  }
}

class _ZenScrollBehavior extends MaterialScrollBehavior {
  const _ZenScrollBehavior();
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // kein Glow
  }
}
