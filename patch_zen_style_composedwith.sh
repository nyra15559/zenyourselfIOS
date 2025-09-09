#!/usr/bin/env bash
set -euo pipefail

FILE="lib/shared/zen_style.dart"
BACKUP="$FILE.bak-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$FILE" ]]; then
  echo "❌ Datei nicht gefunden: $FILE"
  exit 1
fi

echo "🧾 Erstelle Backup: $BACKUP"
cp "$FILE" "$BACKUP"

echo "🔎 Prüfe auf .composedWith(...) Vorkommen…"
if ! grep -q "\.composedWith(" "$FILE"; then
  echo "ℹ️  Keine '.composedWith(' Stelle gefunden. Nichts zu tun."
  exit 0
fi

echo "🩹 Patche ColorFilter: entferne .composedWith(...) und setze weißen Film (.05)…"
# 1) const ColorFilter.mode(Colors.transparent, BlendMode.srcATop)
#    → ColorFilter.mode(Colors.white.withOpacity(0.05), BlendMode.srcATop)
# 2) jegliches .composedWith(const ColorFilter.matrix(<double>[…])) entfernen
perl -0777 -pe "
  s/const\s+ColorFilter\.mode\(\s*Colors\.transparent\s*,\s*BlendMode\.srcATop\s*\)/
    ColorFilter.mode(Colors.white.withOpacity(0.05), BlendMode.srcATop)
  /gx;
  s/\.composedWith\(\s*const\s*ColorFilter\.matrix\(\s*<double>\[[^\]]*\]\s*\)\s*\)//gs;
" -i "$FILE"

echo "✅ Patch fertig. Baue Projekt an:"
flutter clean >/dev/null 2>&1 || true
flutter pub get
flutter run -d linux
