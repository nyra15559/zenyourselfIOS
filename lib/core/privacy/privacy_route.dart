// [MERGE SIGNAL] lib/core/privacy/privacy_route.dart (v1.4 · 2025-11-09)
// ZenYourself — Privacy Route
// -----------------------------------------------------------------------------
// Zweck:
// • Schlanke Route, die die komplette Logik an den PrivacyOrchestrator delegiert.
// • Vermeidet doppelte Zustands-/MemoryService-Handhabung in Route & Screen.
// • Einheitliche Einstiegstelle für Navigator.pushNamed(...) o. ä.
//
// Annahmen:
// • lib/core/privacy/privacy_orchestrator.dart existiert und enthält alle
//   Gating-/Trial-/Consent- und Name-Flows.
// • PrivacyOrchestrator rendert selbst ein vollständiges Scaffold.
//
// Öffentliche API:
// • PrivacyRoute.routeName → "/privacy"
// • PrivacyRoute.material() → MaterialPageRoute<void>
//
// Keine direkten Imports/Abhängigkeiten zu MemoryService hier notwendig.

import 'package:flutter/material.dart';
import 'privacy_orchestrator.dart';

class PrivacyRoute extends StatelessWidget {
  const PrivacyRoute({super.key});

  /// Einheitlicher Routenname (optional für Named Routes).
  static const String routeName = '/privacy';

  /// Bequemer Helfer für imperative Navigation:
  /// Navigator.of(context).push(PrivacyRoute.material());
  static MaterialPageRoute<void> material({Key? key}) {
    return MaterialPageRoute<void>(
      builder: (_) => PrivacyRoute(key: key),
      settings: const RouteSettings(name: routeName),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Orchestrator kümmert sich um Laden/Speichern/Trial/Consent/Name.
    return const PrivacyOrchestrator();
  }
}
