#!/usr/bin/env bash
set -euo pipefail

# === Einstellungen ===
FILES=(
  "lib/features/reflection/reflection_screen.dart"
  "lib/features/journal/journal_entry_editor.dart"
)

echo ">> Backup anlegen"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "Fehlt: $f"; exit 1; }
  cp "$f" "$f.bak"
done

echo ">> Ersetzungen durchführen"
for f in "${FILES[@]}"; do
  # 1) Listener-Klasse & Callback-Name
  perl -0777 -pi -e 's/\bRawKeyboardListener\b/KeyboardListener/g' "$f"
  perl -0777 -pi -e 's/\bonKey\s*:/onKeyEvent:/g' "$f"

  # 2) Parametertypen in Handlern/Funktionen
  perl -0777 -pi -e 's/\bRawKeyEvent\b/KeyEvent/g' "$f"
  perl -0777 -pi -e 's/\bRawKeyDownEvent\b/KeyDownEvent/g' "$f"

  # 3) Modifier dürfen NICHT mehr vom Event gelesen werden
  perl -0777 -pi -e 's/\be\.isControlPressed\b/HardwareKeyboard.instance.isControlPressed/g' "$f"
  perl -0777 -pi -e 's/\be\.isMetaPressed\b/HardwareKeyboard.instance.isMetaPressed/g' "$f"
  perl -0777 -pi -e 's/\be\.isShiftPressed\b/HardwareKeyboard.instance.isShiftPressed/g' "$f"

  # 4) Import für neue API sicherstellen
  if ! grep -q "package:flutter/services.dart" "$f"; then
    # nach der ersten import-Zeile einfügen
    perl -0777 -pi -e "s/(^import\\s+['\"][^'\"]+['\"];\\s*)/\\1import 'package:flutter\\/services.dart';\\n/s" "$f"
  fi
done

echo ">> Fertig. Starte Analyse:"
flutter analyze lib || true

echo
echo "Hinweis:"
echo "- Prüfe, ob deine Key-Handler jetzt die Signatur (KeyEvent e) nutzen."
echo "- Für Logik nur auf KeyDown reagieren: if (e is! KeyDownEvent) return;"
