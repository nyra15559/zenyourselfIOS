#!/usr/bin/env bash
# V2: Warnt nur bei *Zuweisungen* an 'memories' OHNE 'context.' davor.
set -euo pipefail

ROOT="${1:-.}"
has_rg() { command -v rg >/dev/null 2>&1; }

EXCLUDES=(
  --glob '!**/.git/**' --glob '!**/.dart_tool/**' --glob '!**/build/**'
  --glob '!**/ios/Pods/**' --glob '!**/android/.gradle/**' --glob '!**/node_modules/**'
  --glob '!**/assets/**' --glob '!**/test/**' --glob '!**/tests/**'
  --glob '!**/tools/**' --glob '!**/scripts/**' --glob '!**/bin/**'
)

# Nur produktiver Dart-Code
GLOB='**/*.dart'

# Muster: 'memories' gefolgt von ':' oder '=' und NICHT 'context.' davor (8 Zeichen fix → Lookbehind ok)
PATTERN='(?<!context\.)\bmemories\b\s*[:=]'

# Whitelist: Legacy-Spiegel im ApiService ist beabsichtigt
WHITELIST_RX='^(\./)?lib/services/core/api_service\.dart$|^(\./)?lib/core/memory/'

HITS=()
if has_rg; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    FILE="${line%%:*}"
    [[ "$FILE" =~ $WHITELIST_RX ]] && continue
    HITS+=("$line")
  done < <(rg -n --no-ignore -S -P "${EXCLUDES[@]}" -g "$GLOB" -e "$PATTERN" "$ROOT" || true)
else
  echo "Bitte ripgrep (rg) installieren." >&2; exit 1
fi

echo "🔎 Scanne $ROOT nach Top-Level 'memories' Zuweisungen …"
if ((${#HITS[@]}==0)); then
  echo "✅ Keine verdächtigen Top-Level-'memories'-Zuweisungen außerhalb der Whitelist."
else
  echo "⚠️  Prüfen (Top-Level 'memories' ohne 'context.' davor):"
  printf '  - %s\n' "${HITS[@]}"
  exit 2
fi
