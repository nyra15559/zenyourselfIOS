#!/usr/bin/env bash
# tools/smoke_flags.sh
# Prüft, ob unerwartete meta.flags.* im Code übrig sind.
set -euo pipefail

ROOT="${1:-.}"

# Erlaubte Flags (Whitelist) – hier bei Bedarf ergänzen:
ALLOWED_META_FLAGS=("client_memory" "client_memory_merge")

# Suchmuster (PCRE): findet z.B. meta.flags.client_memory
PATTERN='meta\.(flags|flag)s?\.[A-Za-z0-9_\-]+'

has_rg() { command -v rg >/dev/null 2>&1; }

# Ordner ausschließen (Build/Deps)
EXCLUDES=(
  --glob '!**/.git/**'
  --glob '!**/.dart_tool/**'
  --glob '!**/build/**'
  --glob '!**/ios/Pods/**'
  --glob '!**/android/.gradle/**'
  --glob '!**/node_modules/**'
)

echo "🔎 Scanne ${ROOT} nach meta.flags.* …"

if has_rg; then
  # Vollständige Trefferliste (Datei:Zeile:Match)
  MATCHES="$(rg -n --no-ignore -S "${EXCLUDES[@]}" -e "${PATTERN}" "${ROOT}" || true)"
  # Nur die Flag-Namen extrahieren
  KEYS="$(rg -n --no-ignore -S "${EXCLUDES[@]}" -o -e "${PATTERN}" "${ROOT}" \
        | sed -E 's@.*meta\.(flags|flag)s?\.@@' \
        | sort -f | uniq -i || true)"
else
  # Fallback mit grep -P
  MATCHES="$(grep -RNoP --exclude-dir='.git|.dart_tool|build|node_modules|ios/Pods|android/.gradle' "${PATTERN}" "${ROOT}" || true)"
  KEYS="$(grep -RNoP --exclude-dir='.git|.dart_tool|build|node_modules|ios/Pods|android/.gradle' -o "${PATTERN}" "${ROOT}" \
        | sed -E 's@.*meta\.(flags|flag)s?\.@@' \
        | sort -f | uniq -i || true)"
fi

if [[ -z "${MATCHES}" ]]; then
  echo "✅ Keine meta.flags.*-Verwendungen gefunden."
  exit 0
fi

echo "— Treffer:"
echo "${MATCHES}"

echo
echo "— Gefundene Flag-Namen:"
echo "${KEYS}"

# Prüfen gegen Whitelist
UNKNOWN=()
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  ok=false
  for allow in "${ALLOWED_META_FLAGS[@]}"; do
    if [[ "${key,,}" == "${allow,,}" ]]; then ok=true; break; fi
  done
  if ! $ok; then UNKNOWN+=("$key"); fi
done < <(printf '%s\n' "${KEYS}")

if (( ${#UNKNOWN[@]} == 0 )); then
  echo
  echo "✅ Alle meta.flags.* sind whitelisted (${ALLOWED_META_FLAGS[*]})."
  exit 0
else
  echo
  echo "⚠️  Unbekannte Flags gefunden (nicht in Whitelist):"
  printf '  - %s\n' "${UNKNOWN[@]}"
  echo
  echo "Tipp: Wenn gewollt, ergänze sie in ALLOWED_META_FLAGS oben."
  exit 2
fi
