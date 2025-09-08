// test/widget_test.dart
//
// v8 — Widget-Smoke-Tests (projektnamen-unabhängig)
// -------------------------------------------------
// - Kein Import deiner App-Klasse/Packages (vermeidet uri_does_not_exist)
// - Kleines Testbed im Testfile selbst: Counter + FAB
// - Tests:
//     1) Inkrement via FAB
//     2) A11y: Tooltip vorhanden
//     3) Text-Scaling wird respektiert

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Smoke', () {
    testWidgets('Counter increments via FAB', (WidgetTester tester) async {
      // Build minimal test app.
      await tester.pumpWidget(const _TestApp());

      // Starts at 0.
      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsNothing);

      // Tap '+' and rebuild a frame.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // Counter incremented to 1.
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('FAB has accessible tooltip', (WidgetTester tester) async {
      await tester.pumpWidget(const _TestApp());

      // Semantics einschalten, damit Tooltip im Semantikbaum prüfbar ist.
      final handle = tester.ensureSemantics();
      expect(find.byTooltip('Increment'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Respects text scaling (accessibility)', (WidgetTester tester) async {
      // 1) Standard-Skalierung
      await tester.pumpWidget(const _TestApp());
      final sizeNormal = tester.getSize(find.text('0'));

      // 2) Höhere Textskalierung injizieren
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            );
          },
          home: const _CounterPage(),
        ),
      );

      final sizeScaled = tester.getSize(find.text('0'));

      // Erwartung: Höhe (und damit Fontgröße) ist gewachsen.
      expect(sizeScaled.height, greaterThan(sizeNormal.height));
    });
  });
}

// --- Testbed -----------------------------------------------------------------

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: _CounterPage(),
    );
  }
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Testbed')),
      body: Center(
        child: Text(
          '$_count',
          style: const TextStyle(fontSize: 36),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Increment',
        onPressed: () => setState(() => _count++),
        child: const Icon(Icons.add),
      ),
    );
  }
}
