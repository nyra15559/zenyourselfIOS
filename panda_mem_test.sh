#!/usr/bin/env bash
set -euo pipefail

# ================== FEST EINGESETZT (deine Angaben) =========================
WORKER="https://nameless-breeze-87fb.edcvaultcom.workers.dev"  # ggf. prüfen
APP_TOKEN="daded2f03bd67dd25d8434272c7095c234c80f9d15daefb253418b7a779244aa"
APP_SECRET=""   # kein HMAC

# Sanitize (Trailing Slash weg)
WORKER="${WORKER%/}"

# ================== TESTIDENTITÄT ==========================================
USER_ID="matthias-zenyourself"
SESSION_ID="sess-$(date +%s)"
NAME="Matthias"
LOCALE="de-CH"
TZ="Europe/Zurich"

# ================== HILFSFUNKTIONEN ========================================
post_json() {
  local path="$1"; local body="$2"; local url="${WORKER}${path}"
  local headers=(-sS -X POST "$url" -H "content-type: application/json")
  [[ -n "${APP_TOKEN}"  ]] && headers+=(-H "authorization: Bearer ${APP_TOKEN}")
  curl "${headers[@]}" --data "$body"
}
get_json() {
  local path="$1"; local url="${WORKER}${path}"; local headers=(-sS -X GET "$url")
  [[ -n "${APP_TOKEN}"  ]] && headers+=(-H "authorization: Bearer ${APP_TOKEN}")
  curl "${headers[@]}"
}
hr(){ printf '\n%s\n' "---------------------------------------------"; }

echo "User: ${USER_ID}"
echo "Session: ${SESSION_ID}"
hr

# 0) Healthcheck
echo ">> [0] /health"
get_json "/health" || true
hr

# 1) Consent + Name (Name bleibt NUR clientseitig; KV speichert KEINEN Namen)
TS="$(date +%s)"
BODY_CONSENT_AND_IDENTITY=$(cat <<JSON
{
  "ts": ${TS},
  "user_id": "${USER_ID}",
  "locale": "${LOCALE}",
  "tz": "${TZ}",
  "mem_consent": true,
  "text": "Kleiner Check-in.",
  "session": { "id": "${SESSION_ID}", "turn": 0 },
  "context": {
    "memories": {
      "identity": { "name": "${NAME}" }
    }
  }
}
JSON
)
echo ">> [1] Consent + Name pushen → /reflect"
post_json "/reflect" "$BODY_CONSENT_AND_IDENTITY" | sed 's/\\n/\n/g'
hr

# 2A) Name-Recall OHNE identity: sollte sagen „kein Name hinterlegt“
TS="$(date +%s)"
BODY_WHATS_MY_NAME_NO_ID=$(cat <<JSON
{
  "ts": ${TS},
  "user_id": "${USER_ID}",
  "locale": "${LOCALE}",
  "tz": "${TZ}",
  "text": "Wie heiße ich?",
  "session": { "id": "${SESSION_ID}", "turn": 1 }
}
JSON
)
echo ">> [2A] 'Wie heiße ich?' OHNE identity → /reflect"
post_json "/reflect" "$BODY_WHATS_MY_NAME_NO_ID" | sed 's/\\n/\n/g'
hr

# 2B) Name-Recall MIT identity: sollte „Matthias“ bestätigen
TS="$(date +%s)"
BODY_WHATS_MY_NAME_WITH_ID=$(cat <<JSON
{
  "ts": ${TS},
  "user_id": "${USER_ID}",
  "locale": "${LOCALE}",
  "tz": "${TZ}",
  "text": "Wie heiße ich?",
  "session": { "id": "${SESSION_ID}", "turn": 2 },
  "context": {
    "memories": {
      "identity": { "name": "${NAME}" }
    }
  }
}
JSON
)
echo ">> [2B] 'Wie heiße ich?' MIT identity → /reflect"
post_json "/reflect" "$BODY_WHATS_MY_NAME_WITH_ID" | sed 's/\\n/\n/g'
hr

# 3) Themen-Memory (KV) testen – Model kann memory_update setzen (Consent aktiv)
TS="$(date +%s)"
BODY_MEMORY_THEME=$(cat <<JSON
{
  "ts": ${TS},
  "user_id": "${USER_ID}",
  "locale": "${LOCALE}",
  "tz": "${TZ}",
  "mem_consent": true,
  "text": "Heute war Arbeit stressig, Grenzen setzen ist mir schwer gefallen.",
  "session": { "id": "${SESSION_ID}", "turn": 3 }
}
JSON
)
echo ">> [3] Themenreflexion → /reflect"
post_json "/reflect" "$BODY_MEMORY_THEME" | sed 's/\\n/\n/g'
hr

echo ">> [3b] /recent_topics (Server-Memory lesen) → user_id=${USER_ID}"
get_json "/recent_topics?user_id=${USER_ID}&limit=8"
hr

echo "Fertig. Falls recent_topics noch leer: Schritt [3] 1–2× mit kleiner Textvariation wiederholen."
