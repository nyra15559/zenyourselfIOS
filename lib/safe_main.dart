// lib/save_main.dart
//
// Safe Entry Wrapper („Feuerwerk Main“) — Material 3 Mini-Bootstrap
// v1.2 · 2025-10-22
// -----------------------------------------------------------------------------
// Zweck:
//  • Startet sofort eine kleine, ruhige Splash-UI (Material 3).
//  • Leitet dann in euren echten main() aus lib/main.dart über.
//  • Fängt frühe Fehler sichtbar ab statt „Black Screen“.
//
// Verwendung:
//  • In platform-spezifischen Runnern als Entry verwenden
//    (z. B. Windows/Linux/macOS/web): lib/save_main.dart
//  • Der eigentliche App-Start bleibt in lib/main.dart (app.main()).
//
// Hinweise:
//  • Splash ist bewusst minimalistisch (A11y-freundlich, ruhige Farben).
// -----------------------------------------------------------------------------

import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart' as app; // -> ruft euren echten Einstieg auf

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Alle Flutter-Errors in die Zone weiterreichen
  FlutterError.onError = (FlutterErrorDetails details) {
    Zone.current.handleUncaughtError(
      details.exception,
      details.stack ?? StackTrace.empty,
    );
  };

  runZonedGuarded(() async {
    // Sofort etwas zeigen, damit nicht "schwarz" steht
    runApp(const _BootSplash());

    // Nach dem ersten Frame den echten App-Start ausführen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.microtask(() {
        try {
          app.main(); // ruft euren echten main() (der macht runApp eurer App)
        } catch (e, st) {
          Zone.current.handleUncaughtError(e, st);
        }
      });
    });
  }, (error, stack) {
    // Sichtbarer Fehler-Screen statt Black Screen
    runApp(_ErrorApp(error: error, stack: stack));
  });
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F5F49), // Deep Sage (ruhig)
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        textTheme: Typography.blackCupertino.apply(fontSizeFactor: 1.0),
      ),
      home: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Icon(Icons.spa_rounded, size: 40, color: colorScheme.primary),
                  const SizedBox(height: 14),
                  Text(
                    'ZenYourself startet…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stack;
  const _ErrorApp({required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB3261E), // Material 3 error seed
      brightness: Brightness.light,
    );
    final msg = error.toString();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: scheme),
      home: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.error.withOpacity(.25)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      'Startfehler:\n\n$msg\n\n$stack',
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
