#!/usr/bin/env bash
set -euo pipefail

# Usage: tools/check_name_pipeline.sh "Matthias"
NAME="${1:-Matthias}"
BASE_URL="${WORKER_BASE:-https://nameless-breeze-87fb.edcvaultcom.workers.dev}"
TOKEN="${APP_TOKEN:-}"   # optional
SID="sess-$(date +%s)-$RANDOM"

# --- FLAGS (Single Source of Truth) ---
FLAGS_JSON='{"client_memory":true,"client_memory_merge":true}'

hdr=(-H 'Content-Type: application/json')
[[ -n "$TOKEN" ]] && hdr+=(-H "Authorization: Bearer $TOKEN")

say(){ printf "\n%s\n" "==> $*"; }
post(){ curl -sS "${hdr[@]}" -X POST "$1" -d "$2"; }
contains_name(){ jq -r "$1" <<<"$2" | grep -qi -- "$NAME"; }

# ---------- Turn 0: reflect_full WITH memories ----------
say "Turn 0 (reflect_full) mit Memories & Merge-Flag"
payload0=$(cat <<JSON
{
  "session": {"id":"$SID","turn":0},
  "text": "hallo panda",
  "locale":"de",
  "tz":"Europe/Zurich",
  "memory_consent": true,
  "meta": { "flags": $FLAGS_JSON },
  "context": { "memories": { "identity": { "name": "$NAME" }, "profile": { "user_name": "$NAME" } } },
  "memories": { "identity": { "name": "$NAME" }, "profile": { "user_name": "$NAME" } }
}
JSON
)
res0=$(post "$BASE_URL/reflect_full" "$payload0" | jq '.')
echo "$res0"
if contains_name '.mirror // ""' "$res0"; then
  echo "✔ Name in Turn 0 erkannt"
else
  echo "✖ KEIN Name in Turn 0"
fi

# ---------- Turn 1: next_turn_full WITHOUT memories ----------
say "Turn 1 (next_turn_full) OHNE Memories"
payload1=$(cat <<JSON
{
  "session": {"id":"$SID","turn":1},
  "text": "weiter",
  "locale":"de",
  "tz":"Europe/Zurich"
}
JSON
)
res1=$(post "$BASE_URL/next_turn_full" "$payload1" | jq '.')
echo "$res1"
if contains_name '.mirror // ""' "$res1"; then
  echo "✔ Name in Turn 1 (ohne Memories)"
else
  echo "… (oft OK) kein Name in Turn 1 ohne Memories"
fi

# ---------- Turn 2: next_turn_full WITH memories ----------
say "Turn 2 (next_turn_full) MIT Memories"
payload2=$(cat <<JSON
{
  "session": {"id":"$SID","turn":2},
  "text": "nochmal",
  "locale":"de",
  "tz":"Europe/Zurich",
  "memory_consent": true,
  "meta": { "flags": $FLAGS_JSON },
  "context": { "memories": { "identity": { "name": "$NAME" }, "profile": { "user_name": "$NAME" } } },
  "memories": { "identity": { "name": "$NAME" }, "profile": { "user_name": "$NAME" } }
}
JSON
)
res2=$(post "$BASE_URL/next_turn_full" "$payload2" | jq '.')
echo "$res2"
if contains_name '.mirror // ""' "$res2"; then
  echo "✔ Name in Turn 2 erkannt (mit Memories)"
else
  echo "✖ KEIN Name in Turn 2 (mit Memories) —> Problem"
fi

# ---------- Turn 3: explicit question „wie heiße ich?“ WITH memories ----------
say "Turn 3 (next_turn_full) Frage: 'wie heiße ich?' MIT Memories"
payload3=$(cat <<JSON
{
  "session": {"id":"$SID","turn":3},
  "text": "weißt du wie ich heiße?",
  "locale":"de",
  "tz":"Europe/Zurich",
  "memory_consent": true,
  "meta": { "flags": $FLAGS_JSON },
  "context": { "memories": { "identity": { "name": "$NAME" }, "profile": { "user_name": "$NAME" } } },
  "memories": { "identity": { "name": "$NAME" }, "profile": { "user_name": "$NAME" } }
}
JSON
)
res3=$(post "$BASE_URL/next_turn_full" "$payload3" | jq '.')
echo "$res3"
if contains_name '.mirror // ""' "$res3"; then
  echo "✔ Name wird bei Nachfrage gespiegelt/benutzt"
else
  echo "✖ Bei Nachfrage kein Name —> Problem"
fi
