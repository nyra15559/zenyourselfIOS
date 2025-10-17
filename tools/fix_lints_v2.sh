#!/usr/bin/env bash
set -euo pipefail

FILES=$(git ls-files 'lib/**/*.dart')

echo ">> 1) textScaleFactor → textScaler"
sed -E -i "s/textScaleFactor\s*:\s*([0-9]*\.?[0-9]+)/textScaler: TextScaler.linear(\1)/g" lib/features/accessibility/large_text_mode.dart lib/features/reflection/reflection_widgets.dart
sed -E -i "s/textScaleFactor\s*:\s*([^,)\}]+)\s*(?=[,)\}])/textScaler: TextScaler.linear(\1)/g" lib/features/accessibility/large_text_mode.dart lib/features/reflection/reflection_widgets.dart

echo ">> 2) withOpacity → withValues(alpha: ...)"
sed -E -i "s/\.withOpacity\(([^)]+)\)/.withValues(alpha: \1)/g" lib/shared/zen_style.dart

echo ">> 3) RawKeyboard API → KeyEvent API (reflections + editor)"
sed -E -i "s/\bRawKeyEvent\b/KeyEvent/g" lib/features/journal/journal_entry_editor.dart lib/features/reflection/reflection_screen.dart
sed -E -i "s/\bRawKeyDownEvent\b/KeyDownEvent/g" lib/features/reflection/reflection_screen.dart
sed -E -i "s/\bRawKeyboardListener\b/KeyboardListener/g" lib/features/journal/journal_entry_editor.dart lib/features/reflection/reflection_screen.dart
sed -E -i "s/\bisControlPressed\s*\(\)/HardwareKeyboard.instance.isControlPressed/g" lib/features/journal/journal_entry_editor.dart lib/features/reflection/reflection_screen.dart
sed -E -i "s/\bisMetaPressed\s*\(\)/HardwareKeyboard.instance.isMetaPressed/g" lib/features/journal/journal_entry_editor.dart lib/features/reflection/reflection_screen.dart
sed -E -i "s/\bisShiftPressed\s*\(\)/HardwareKeyboard.instance.isShiftPressed/g" lib/features/reflection/reflection_screen.dart

echo ">> 4) 'part of' muss Dateiname sein (keine lib-Names)"
sed -E -i "s/^part of\s+reflection_screen\s*;/part of 'reflection_screen.dart';/g" lib/features/reflection/reflection_models.dart
sed -E -i "s/^part of\s+reflection_screen\s*;/part of 'reflection_screen.dart';/g" lib/features/reflection/reflection_widgets.dart

echo ">> 5) Unused shown import: ZenBackdrop (Impulse/Start)"
sed -E -i "s/,\s*ZenBackdrop\s*//g" lib/features/impulse/impulse_screen.dart lib/features/start/start_screen.dart
sed -E -i "s/show\s+ZenBackdrop\s*//g" lib/features/impulse/impulse_screen.dart lib/features/start/start_screen.dart

echo ">> 6) Dead null-aware (x ?? y wenn x non-nullable) – gezielte Stellen"
sed -E -i "s/([A-Za-z0-9_\.]+)\s*\?\?\s*[^;]+;/\1;/g" \
  lib/features/calendar/mood_heatmap.dart \
  lib/features/journal/journal_day_screen.dart \
  lib/services/analytics.dart \
  lib/services/core/api_service.dart

echo ">> 7) Unused private Felder (_moods/_state/_savedEntryId) entfernen"
sed -E -i "/\b_(moods|state|savedEntryId)\b.*;/d" \
  lib/features/journal/journal_entry_editor.dart \
  lib/features/story/story_screen.dart

echo ">> 8) Temporär: library_private_types_in_public_api ignorieren (bis Cleanup)"
for f in \
  lib/features/impulse/impulse_screen.dart \
  lib/features/reflection/reflection_models.dart \
  lib/providers/journal_entries_provider.dart
do
  if [ -f "$f" ] && ! grep -q "ignore_for_file: library_private_types_in_public_api" "$f"; then
    sed -i "1s;^;// ignore_for_file: library_private_types_in_public_api\n&;" "$f"
  fi
done

echo ">> 9) Unused local 'tt' & unbenutzte _ChipsWrap/_TypingRowLegacy markieren"
for f in lib/features/reflection/reflection_widgets.dart; do
  sed -E -i "s/^(\s*)(final|var|const)\s+tt\s*=/\1\/\/ ignore: unused_local_variable\n\1\2 tt =/g" "$f"
  sed -E -i "s/^(\s*class\s+_ChipsWrap\b)/\/\/ ignore: unused_element\n\1/g" "$f"
  sed -E -i "s/^(\s*class\s+_TypingRowLegacy\b)/\/\/ ignore: unused_element\n\1/g" "$f"
done

echo ">> 10) Unused helper in pro_screen markieren"
sed -E -i "s/^(\s*(?:[a-zA-Z_<>,\s]+)\s+_isReflectionEntry\s*\()/\/\/ ignore: unused_element\n\1/" lib/features/pro/pro_screen.dart

echo ">> Fertig."
