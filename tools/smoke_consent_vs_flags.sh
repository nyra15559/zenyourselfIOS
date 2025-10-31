#!/usr/bin/env bash
# V2: Flag-Check nur in relevanten Code-Dateien, ignoriert Kommentarzeilen.
set -euo pipefail

ROOT="${1:-.}"
has_rg() { command -v rg >/dev/null 2>&1; }

EXCLUDES=(
  --glob '!**/.git/**' --glob '!**/.dart_tool/**' --glob '!**/build/**'
  --glob '!**/ios/Pods/**' --glob '!**/android/.gradle/**' --glob '!**/node_modules/**'
  --glob '!**/assets/**' --glob '!**/test/**' --glob '!**/tests/**'
  --glob '!**/tools/**' --glob '!**/scripts/**' --glob '!**/bin/**'
)

# Nur .dart / .kt / .swift falls du magst; hier .dart fokus
PATTERN='^\s*(?!\/\/|#).*meta\.(flags|flag)s?\.[A-Za-z0-9_\-]+'

FILES=()
if has_rg; then
  while IFS= read -r f; do FILES+=("$f"); done < <(
    rg -l --no-ignore -n -S -P "${EXCLUDES[@]}" -g '**/*.dart' -e "$PATTERN" "$ROOT" || true
  )
else
  echo "Bitte ripgrep (rg) installieren." >&2; exit 1
fi

# Zusätzliche Whitelist: DTOs parsen Flags, brauchen kein memory_consent-Gating
WHITELIST_RX='^(\./)?lib/services/guidance/dtos\.dart$|^(\./)?lib/features/reflection/reflection_screen\.dart$'

BAD=()
for f in "${FILES[@]}"; do
  # Whitelist?
  if [[ "$f" =~ $WHITELIST_RX ]]; then continue; fi
  # Im selben File auch (nicht kommentiert) 'memory_consent'?
  if ! rg -n --no-ignore -S -P "${EXCLUDES[@]}" -e '^\s*(?!\/\/|#).*memory_consent' "$f" >/dev/null 2>&1; then
    BAD+=("$f")
  fi
done

if ((${#BAD[@]}==0)); then
  echo "✅ Alle produktiven Flag-Verwendungen erscheinen in Files, die auch 'memory_consent' referenzieren."
else
  echo "⚠️  Prüfen (Flags ohne sichtbare 'memory_consent'-Referenz in Code-Zeilen):"
  printf '  - %s\n' "${BAD[@]}"
  echo "Tipp: Falls nur Kommentare → ok. Sonst Consent-Gating nachziehen."
  exit 2
fi
