#!/usr/bin/env bash
# reflect_smoke.sh – Zen Panda CLI Smoketest
# - Liest Text von STDIN (Here-Doc) ODER aus $1
# - Ruft /health und /reflect_full auf
# - Nutzt eingebauten Bearer-Token (override via ZEN_APP_TOKEN)
# - Optional: HMAC x-signature falls $APP_SECRET gesetzt ist

set -euo pipefail

# === Konfiguration (per ENV übersteuerbar) ==================================
ZEN_GUIDANCE="${ZEN_GUIDANCE:-https://nameless-breeze-87fb.edcvaultcom.workers.dev}"

# Dein App-Token (fest eingebaut, wie gewünscht). Per ENV überschreibbar: ZEN_APP_TOKEN
APP_TOKEN="${ZEN_APP_TOKEN:-daded2f03bd67dd25d8434272c7095c234c80f9d15daefb253418b7a779244aa}"

# Optional: HMAC-Secret, falls der Worker APP_SECRET erwartet.
# Per ENV setzen: export APP_SECRET="dein_app_secret"
APP_SECRET="${APP_SECRET:-}"

# Abhängigkeiten prüfen
command -v jq >/dev/null 2>&1 || { echo "❌ jq fehlt (sudo apt-get install -y jq)"; exit 1; }
if [[ -n "$APP_SECRET" ]]; then
  command -v openssl >/dev/null 2>&1 || { echo "❌ openssl fehlt für HMAC (sudo apt-get install -y openssl)"; exit 1; }
fi

# === Input aufnehmen =========================================================
if [ -t 0 ]; then
  # keine STDIN-Pipe; nimm erstes Argument oder Default
  INPUT="${1:-Hey Panda, wie geht's dir?}"
else
  # STDIN komplett einlesen
  INPUT="$(cat)"
  INPUT="${INPUT:-Hey Panda, wie geht's dir?}"
fi

BODY=$(jq -c --arg txt "$INPUT" --arg id "smoke_cli" '{text:$txt, session:{id:$id, turn:0}}')

# === Signatur-Header optional hinzufügen ====================================
SIG_HDR=()
if [[ -n "$APP_SECRET" ]]; then
  SIG=$(printf %s "$BODY" | openssl dgst -sha256 -hmac "$APP_SECRET" | awk '{print $2}')
  SIG_HDR=(-H "x-signature: $SIG")
fi

mask() {
  local t="$1"
  if (( ${#t} > 8 )); then
    echo "${t:0:4}***${t: -3}"
  else
    echo "***"
  fi
}

echo "Guidance: $ZEN_GUIDANCE"
echo "Bearer:   $(mask "$APP_TOKEN")"
[[ -n "$APP_SECRET" ]] && echo "HMAC:     aktiv" || echo "HMAC:     aus"
echo

# === /health =================================================================
echo "=== GET /health ==="
curl -sS -H "Authorization: Bearer $APP_TOKEN" "$ZEN_GUIDANCE/health" | jq .
echo

# === /reflect_full ===========================================================
echo "=== POST /reflect_full ==="
curl -sS -H "Authorization: Bearer $APP_TOKEN" -H "Content-Type: application/json" \
  "${SIG_HDR[@]}" -d "$BODY" "$ZEN_GUIDANCE/reflect_full" | jq .
echo
