#!/usr/bin/env bash
set -euo pipefail

# ================== CONFIG ==================
WORKER_BASE="https://nameless-breeze-87fb.edcvaultcom.workers.dev"
APP_TOKEN="daded2f03bd67dd25d8434272c7095c234c80f9d15daefb253418b7a779244aa"

# Optional (nur setzen, wenn dein Worker HMAC prüft)
: "${APP_SECRET:=${APP_SECRET:-}}"

# Test-Identitäten
USER_ID="demo-user-$(date +%s)"
SESSION_A="sessA-$(openssl rand -hex 6 2>/dev/null || echo $RANDOM$RANDOM)"
SESSION_B="sessB-$(openssl rand -hex 6 2>/dev/null || echo $RANDOM$RANDOM)"

TZ_STR="Europe/Zurich"
LOCALE="de-CH"

# ================== HILFSFUNKTIONEN ==================
hmac_sign() {
  # Signiert Body mit APP_SECRET (hex), wenn APP_SECRET gesetzt ist
  # Benötigt: openssl + xxd (xxd ist i.d.R. auf macOS/Linux vorhanden)
  if [[ -z "${APP_SECRET}" ]]; then
    return 0
  fi
  printf '%s' "$1" \
    | openssl dgst -sha256 -mac HMAC -macopt "key:${APP_SECRET}" -binary \
    | xxd -p -c 256
}

post_json() {
  local path="$1"
  local body="$2"
  local sig=""
  if [[ -n "${APP_SECRET}" ]]; then
    sig="$(hmac_sign "${body}")"
  fi

  curl -sS -X POST "${WORKER_BASE}${path}" \
    -H "Authorization: Bearer ${APP_TOKEN}" \
    -H "Content-Type: application/json" \
    ${sig:+ -H "X-Signature: ${sig}"} \
    --data "${body}"
  echo
}

# ================== CALLS ==================

echo "— GET /health"
curl -sS "${WORKER_BASE}/health" -H "Authorization: Bearer ${APP_TOKEN}" ; echo
echo

# ----- Case A: reflect_full (OHNE Client-Memory-Merge-Flag) -----
# Erwartung: KEIN Namens-Gruß, obwohl context.memories.identity.name gesetzt wäre,
# denn merge ist nur aktiv bei meta.flags.client_memory === true.
BODY_A="$(cat <<EOF
{
  "user_id": "${USER_ID}",
  "locale": "${LOCALE}",
  "tz": "${TZ_STR}",
  "text": "Ich starte ruhig in den Tag.",
  "session": { "id": "${SESSION_A}", "turn": 0 },
  "memory_consent": true,
  "context": {
    "memories": {
      "identity": { "name": "Matthias" },
      "recent_topics": ["Start in den Tag", "Ruhe"]
    }
  },
  "meta": {
    "ts": $(date +%s),
    "flags": {
      "client_memory": false
    }
  }
}
EOF
)"
echo "— POST /reflect_full (Case A: client_memory=false)"
post_json "/reflect_full" "${BODY_A}"
echo

# ----- Case B: reflect_full (MIT Client-Memory-Merge-Flag) -----
# Erwartung: Namens-Gruß möglich (Name aus context.memories), Mood/Flow normal.
BODY_B="$(cat <<EOF
{
  "user_id": "${USER_ID}",
  "locale": "${LOCALE}",
  "tz": "${TZ_STR}",
  "text": "Lass uns anfangen.",
  "session": { "id": "${SESSION_B}", "turn": 0 },
  "memory_consent": true,
  "context": {
    "memories": {
      "identity": { "name": "Matthias" },
      "recent_topics": ["Start", "Motivation"],
      "facets": ["Morgenroutine"]
    }
  },
  "meta": {
    "ts": $(date +%s),
    "flags": {
      "client_memory": true
    }
  }
}
EOF
)"
echo "— POST /reflect_full (Case B: client_memory=true)"
post_json "/reflect_full" "${BODY_B}"
echo

# Optional: direkte Namensfrage testen (gleiches Session B, nächster Turn)
BODY_B2="$(cat <<EOF
{
  "user_id": "${USER_ID}",
  "locale": "${LOCALE}",
  "tz": "${TZ_STR}",
  "text": "Wie heiße ich?",
  "session": { "id": "${SESSION_B}", "turn": 1 },
  "memory_consent": true,
  "meta": {
    "ts": $(date +%s),
    "flags": { "client_memory": true }
  }
}
EOF
)"
echo "— POST /reflect_full (Namensfrage im Turn 2, client_memory=true)"
post_json "/reflect_full" "${BODY_B2}"
echo
