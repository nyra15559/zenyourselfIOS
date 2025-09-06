#!/bin/bash
echo "== ZenYourself Fix Script =="
echo "Alle alten MoodEntry/ReflectionEntry/Question Konstrukte werden repariert…"

# 1. moodLabel Parameter entfernen
echo "- Entferne 'moodLabel:'-Parameter aus allen Dart-Files…"
find . -name "*.dart" -exec sed -i '/moodLabel:/d' {} +

# 2. id: bei ReflectionEntry entfernen
echo "- Entferne 'id:'-Parameter bei ReflectionEntry…"
find . -name "*.dart" -exec sed -i '/ReflectionEntry.*id:/d' {} +

# 3. demoFromKey oder demoFromLabel ersetzen (Tipp: Wenn du die Factory nutzt!)
echo "- Ersetze MoodEntry.demoFromKey durch MoodEntry.demoFromLabel (Factory nötig, s.u.)"
find . -name "*.dart" -exec sed -i 's/MoodEntry\.demoFromKey/MoodEntry.demoFromLabel/g' {} +

# 4. Überflüssige named Parameter: onSoundscapeTap, title (optional)
echo "- Entferne onSoundscapeTap und title Parameter (bei ZenAppBar, ZenDialog etc.)…"
find . -name "*.dart" -exec sed -i 's/onSoundscapeTap: [^,]*,//g' {} +
find . -name "*.dart" -exec sed -i 's/title: [^,]*,//g' {} +

# 5. Remove all trailing commas left behind (nice to have)
echo "- Entferne überflüssige Kommas nach dem Entfernen…"
find . -name "*.dart" -exec sed -i 's/,,/,/g' {} +

# 6. Hinweis: Falls du MoodEntry.demoFromLabel noch NICHT hast, schreibe dies in mood_entry.dart:
echo
echo "---------------------------------------------------"
cat <<EOT

// mood_entry.dart, ergänzen:
factory MoodEntry.demoFromLabel(String label) {
  final moodMap = {
    "Sonnig": 4,
    "Wolkig": 2,
    "Regnerisch": 0,
    "Grün": 3,
    "Unklar": 1,
    "Neutral": 2,
  };
  return MoodEntry(
    timestamp: DateTime.now(),
    moodScore: moodMap[label] ?? 2,
  );
}

EOT
echo "---------------------------------------------------"
echo "Alle alten Konstruktor-Aufrufe wurden entfernt/ersetzt!"
echo "Jetzt kannst du 'flutter clean' && 'flutter pub get' und 'flutter run -d linux' probieren!"
echo "FERTIG."
