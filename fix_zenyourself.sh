#!/bin/bash
set -e

echo "=== Fix-Run für ZenYourself Projekt gestartet ==="

# 1. Entferne doppelten Import 'reflection.dart' aus reflection_entries_provider.dart
echo "1. Entferne doppelten Import 'reflection.dart' in reflection_entries_provider.dart..."
sed -i '/import .*reflection\.dart.*;/d' lib/models/reflection_entries_provider.dart

# 2. Entferne const bei Widgets, die Provider.of(...) nutzen (main.dart)
echo "2. Entferne 'const' bei Widgets mit Provider-Aufrufen in main.dart..."
sed -i 's/const \(JourneyMapScreen(moodEntries:\|ProScreen(moodEntries:\)/\1/g' lib/main.dart

# 3. Entferne veraltete/nicht existierende Parameter in main.dart und reflection_screen.dart
echo "3. Entferne veraltete Widget-Parameter..."
sed -i -E 's/(colorBlindMode|largeText|showBack|showInputOnly|onMoodSelected|text|asArtwork|icon|onResult|showBack): [^,}]+,?//g' lib/main.dart lib/features/reflection/reflection_screen.dart lib/features/pro/pro_screen.dart lib/features/impulse/impulse_screen.dart lib/shared/ui/zen_widgets.dart lib/features/calendar/mood_heatmap.dart

# 4. SoundscapeManager.of(context).toggle() ersetzen durch Provider-Zugriff ohne toggle (wenn Methode fehlt)
echo "4. Ersetze SoundscapeManager.of(context).toggle() durch Provider-Aufruf ohne toggle()..."
sed -i 's/SoundscapeManager.of(context).toggle()/Provider.of<SoundscapeManager>(context, listen: false).toggle()/g' lib/features/journey/journey_map.dart lib/features/reflection/reflection_screen.dart lib/features/impulse/impulse_screen.dart

# 5. Typcasting toJson in local_storage.dart fixen
echo "5. Typcasts in local_storage.dart bei toJson hinzufügen..."
sed -i 's/\(e\)\.toJson()/((e) as dynamic).toJson()/g' lib/services/local_storage.dart

# 6. Analytics: Sicherstellen, dass tags nicht null ist
echo "6. Füge Nullprüfung für entry.tags in analytics.dart hinzu..."
sed -i '/for (final tag in entry.tags)/i if (entry.tags == null) return;' lib/services/analytics.dart

echo "=== Fix-Run abgeschlossen! Bitte führe jetzt aus:"
echo "flutter clean"
echo "flutter pub get"
echo "flutter run -d linux"

