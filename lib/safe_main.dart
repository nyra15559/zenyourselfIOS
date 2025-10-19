import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart' as app; // <- dein bestehender Einstieg bleibt unberührt

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Alle Flutter-Errors in die Zone weiterreichen
  FlutterError.onError = (FlutterErrorDetails details) {
    Zone.current.handleUncaughtError(details.exception, details.stack ?? StackTrace.empty);
  };

  runZonedGuarded(() async {
    // Sofort etwas zeigen, damit nicht "schwarz" steht
    runApp(const _BootSplash());
    // Nach dem ersten Frame den echten App-Start ausführen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.microtask(() {
        try {
          app.main(); // ruft euren echten main() auf (der macht runApp eurer App)
        } catch (e, st) {
          Zone.current.handleUncaughtError(e, st);
        }
      });
    });
  }, (error, stack) {
    // Wenn beim Start was schiefgeht: sichtbarer Fehler-Screen statt Black Screen
    runApp(_ErrorApp(error: error, stack: stack));
  });
}

class _BootSplash extends StatelessWidget {
  const _BootSplash({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text('ZenYourself startet…', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _ErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stack;
  const _ErrorApp({super.key, required this.error, required this.stack});
  @override
  Widget build(BuildContext context) {
    final msg = error.toString();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text(
                'Startfehler:\n\n$msg\n\n$stack',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
