import 'package:flutter/material.dart';

enum RiskLevel { none, mild, high }

class SafetyBanner extends StatelessWidget {
  final RiskLevel level;
  final EdgeInsetsGeometry padding;

  const SafetyBanner({
    super.key,
    required this.level,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    if (level == RiskLevel.none) return const SizedBox.shrink();

    final text = level == RiskLevel.high
        ? 'Wenn es dir akut nicht gut geht: Du musst da nicht alleine durch. Hilfe & Notfälle anzeigen.'
        : 'Danke fürs Teilen. Wenn du magst: Hilfe & Notfälle anzeigen.';

    return Semantics(
      container: true,
      label: 'Sicherheits-Hinweis',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.volunteer_activism, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
            TextButton(
              onPressed: () => _showResources(context),
              child: const Text('Öffnen'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResources(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Text('Hilfe & Notfälle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            Text('DE: 0800 111 0 111 / 0800 111 0 222 – TelefonSeelsorge'),
            Text('CH: 143 – Die Dargebotene Hand'),
            Text('AT: 142 – TelefonSeelsorge'),
            SizedBox(height: 12),
            Text('International: Befrienders Worldwide / IASP (Websuche)'),
            SizedBox(height: 8),
            Text(
              'Hinweis: ZenYourself ersetzt keine Therapie. '
              'Bei akuter Gefahr wende dich bitte an den Notruf deiner Region.',
            ),
          ],
        );
      },
    );
  }
}
