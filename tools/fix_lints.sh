#!/usr/bin/env bash
set -euo pipefail

# Alle Dart-Dateien auflisten
FILES=$(git ls-files '*.dart')

echo ">> Replace .withOpacity(x) -> .withValues(alpha: x)"
sed -E -i "s/\.withOpacity\(([^)]+)\)/.withValues(alpha: \1)/g" $FILES

echo ">> Replace textScaleFactor: X -> textScaler: TextScaler.linear(X)"
# einfache numerische Literale
sed -E -i "s/textScaleFactor\s*:\s*([0-9]*\.?[0-9]+)/textScaler: TextScaler.linear(\1)/g" $FILES
# allgemeiner Ausdruck (nicht zu gierig)
sed -E -i "s/textScaleFactor\s*:\s*([^,)\}]+)\s*(?=[,)\}])/textScaler: TextScaler.linear(\1)/g" $FILES

echo ">> Raw keyboard classes -> new KeyEvent API"
sed -E -i "s/\bRawKeyEvent\b/KeyEvent/g" $FILES
sed -E -i "s/\bRawKeyDownEvent\b/KeyDownEvent/g" $FILES
sed -E -i "s/\bRawKeyboardListener\b/KeyboardListener/g" $FILES

echo ">> Keyboard pressed helpers -> HardwareKeyboard.instance"
# Achtung: ersetzt nur freie Aufrufe, nicht bereits vollqualifizierte
sed -E -i "s/\b(isControlPressed|isMetaPressed|isShiftPressed)\s*\(\)/HardwareKeyboard.instance.\1()/g" $FILES

echo ">> Share -> SharePlus.instance.share(...)"
sed -E -i "s/\bShare\.share\(/SharePlus.instance.share(/g" $FILES

echo ">> Entferne überflüssige shown-Imports (Name wird nicht genutzt)"
# Beispiel: 'show ZenBackdrop' ungenutzt
sed -E -i "s/(import\s+'.*';\s*)/\\1/g" $FILES
# gezielt bekannte Stellen bereinigen
sed -E -i "s/,?\s*ZenBackdrop\s*//g" $FILES

echo ">> Add ignore_for_file for library_private_types_in_public_api (temp)"
# Für die konkret gemeldeten Dateien temporär Header setzen (du kannst diese Liste erweitern)
for f in \
  lib/features/impulse/impulse_screen.dart \
  lib/features/reflection/reflection_models.dart \
  lib/providers/journal_entries_provider.dart \
  lib/features/reflection/reflection_screen.dart
do
  if [ -f "$f" ] && ! grep -q "ignore_for_file: library_private_types_in_public_api" "$f"; then
    sed -i "1s;^;// ignore_for_file: library_private_types_in_public_api\n&;" "$f"
  fi
done

echo ">> Done."
