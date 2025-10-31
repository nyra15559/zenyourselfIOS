#!/usr/bin/env bash
set -euo pipefail

# Zen CLI — Community-Only Fallback
# ---------------------------------
# ENV:
#   ZEN_COMMUNITY   = https://<dein-community-worker>.workers.dev  (Pflicht)
#   ZEN_GUIDANCE    = https://<dein-guidance-worker>.workers.dev   (optional; wenn leer => Community-Only)
#   ZEN_API_KEY     = <optional>   → schickt 'x-api-key: ...'
#   ZEN_APP_TOKEN   = <optional>   → schickt 'Authorization: Bearer ...'
#   ZEN_APP_SECRET  = <optional>   → schickt 'X-Signature: HMAC-SHA256(body)'
#   ZEN_USER_ID     = <optional>   → schickt 'x-user-id: ...'
#   ZEN_LOCALE      = de|en|...    → default: de
#   ZEN_TZ          = Europe/Zurich
#   ZEN_DEBUG       = 1|0

# --- Defaults ----------------------------------------------------------------
ZEN_COMMUNITY="${ZEN_COMMUNITY:-}"
ZEN_GUIDANCE="${ZEN_GUIDANCE:-}"
ZEN_LOCALE="${ZEN_LOCALE:-de}"
ZEN_TZ="${ZEN_TZ:-Europe/Zurich}"
ZEN_DEBUG="${ZEN_DEBUG:-0}"

err() { echo >&2 "ERR: $*"; }
log() { [ "$ZEN_DEBUG" = "1" ] && echo "[DBG] $*"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { err "Benötigt: $1"; exit 1; }
}
need curl
need jq
need openssl

if [ -z "${ZEN_COMMUNITY}" ]; then
  err "ZEN_COMMUNITY fehlt (z.B. https://nameless-breeze-87fb.edcvaultcom.workers.dev)."
  exit 1
fi

# --- Header Builder ----------------------------------------------------------
build_headers() {
  local body="${1:-}"
  local hdrs=(-H "content-type: application/json" -H "accept: application/json")
  [ -n "${ZEN_USER_ID:-}"   ] && hdrs+=(-H "x-user-id: ${ZEN_USER_ID}")
  [ -n "${ZEN_LOCALE:-}"    ] && hdrs+=(-H "x-locale: ${ZEN_LOCALE}")
  [ -n "${ZEN_TZ:-}"        ] && hdrs+=(-H "x-timezone: ${ZEN_TZ}")
  [ -n "${ZEN_API_KEY:-}"   ] && hdrs+=(-H "x-api-key: ${ZEN_API_KEY}")
  [ -n "${ZEN_APP_TOKEN:-}" ] && hdrs+=(-H "Authorization: Bearer ${ZEN_APP_TOKEN}")
  if [ -n "${ZEN_APP_SECRET:-}" ]; then
    # HMAC-SHA256(body) hex
    local sig
    sig="$(printf '%s' "${body}" | openssl dgst -sha256 -hmac "${ZEN_APP_SECRET}" -r | awk '{print $1}')"
    hdrs+=(-H "X-Signature: ${sig}")
  fi
  printf '%s\0' "${hdrs[@]}"
}

post_json() {
  # args: url body
  local url="$1"; shift
  local body="${1:-{}}"
  local tmp="$(mktemp)"
  local code
  IFS= read -r -d '' -a HDRS < <(build_headers "${body}")
  [ "$ZEN_DEBUG" = "1" ] && { echo; echo "→ POST $url"; echo "$body" | jq . || echo "$body"; }
  code=$(curl -sS -o "${tmp}" -w '%{http_code}' -X POST "${HDRS[@]}" --data "${body}" "$url" || true)
  [ "$ZEN_DEBUG" = "1" ] && echo "← HTTP $code"
  cat "${tmp}"
  rm -f "${tmp}"
  echo "___HTTP:$code"
}

get_json() {
  local url="$1"
  local tmp="$(mktemp)"
  local code
  IFS= read -r -d '' -a HDRS < <(build_headers "")
  [ "$ZEN_DEBUG" = "1" ] && { echo; echo "→ GET  $url"; }
  code=$(curl -sS -o "${tmp}" -w '%{http_code}' -X GET "${HDRS[@]}" "$url" || true)
  [ "$ZEN_DEBUG" = "1" ] && echo "← HTTP $code"
  cat "${tmp}"
  rm -f "${tmp}"
  echo "___HTTP:$code"
}

http_code_from_tail() {
  # reads stdin (body + ___HTTP:code) and outputs "code" to stdout while printing body to stderr if debug
  local body code
  body="$(cat -)"
  code="$(printf '%s' "$body" | awk -F'___HTTP:' 'NF>1{print $NF}' | tail -n1)"
  body="${body%___HTTP:*}"
  [ "$ZEN_DEBUG" = "1" ] && printf '%s\n' "$body" | sed 's/^/BODY: /' >&2
  printf '%s\n' "$code"
  return 0
}

# --- Capability Check --------------------------------------------------------
guidance_ok=0
if [ -n "${ZEN_GUIDANCE}" ]; then
  # schnell: existiert irgendeine reflect-Route?
  c=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data '{"text":"ping","locale":"de"}' \
      "${ZEN_GUIDANCE}/reflect_full" || true)
  if [ "$c" = "200" ] || [ "$c" = "201" ] || [ "$c" = "204" ]; then
    guidance_ok=1
  elif [ "$c" = "401" ] || [ "$c" = "403" ]; then
    # Auth nötig → mit Headern testen
    IFS= read -r -d '' -a HDRS < <(build_headers '{"text":"ping","locale":"de"}')
    c=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${HDRS[@]}" --data '{"text":"ping","locale":"de"}' \
        "${ZEN_GUIDANCE}/reflect_full" || true)
    [ "$c" = "200" ] || [ "$c" = "201" ] || [ "$c" = "204" ] && guidance_ok=1
  fi
fi

# --- Community Endpoints -----------------------------------------------------
COMM_HELP_TOTAL="$ZEN_COMMUNITY/v1/community/help-total"
COMM_HELP_ACK="$ZEN_COMMUNITY/v1/community/help-ack"
COMM_TALK_TOTAL="$ZEN_COMMUNITY/v1/community/conversations-total"
COMM_TALK_ACK="$ZEN_COMMUNITY/v1/community/talk-ack"

# --- Guidance Endpoints (versch. Pfade, wir probieren) -----------------------
declare -a R_REFLECT_FULL=(
  "${ZEN_GUIDANCE}/reflect_full"
  "${ZEN_GUIDANCE}/v1/reflect_full"
  "${ZEN_GUIDANCE}/api/reflect_full"
  "${ZEN_GUIDANCE}/reflect-full"
)
declare -a R_NEXT_FULL=(
  "${ZEN_GUIDANCE}/next_turn_full"
  "${ZEN_GUIDANCE}/v1/next_turn_full"
  "${ZEN_GUIDANCE}/api/next_turn_full"
)
declare -a R_CLOSE_FULL=(
  "${ZEN_GUIDANCE}/closure_full"
  "${ZEN_GUIDANCE}/v1/closure_full"
  "${ZEN_GUIDANCE}/api/closure_full"
)

pick_first_alive() {
  # args: list of urls
  for u in "$@"; do
    [ -z "${u}" ] && continue
    code=$(curl -sS -o /dev/null -w '%{http_code}' -X OPTIONS "$u" || true)
    if [ "$code" = "200" ] || [ "$code" = "204" ] || [ "$code" = "401" ] || [ "$code" = "405" ]; then
      echo "$u"; return 0
    fi
  done
  echo ""
}

REFLECT_ENDPOINT=""; NEXT_ENDPOINT=""; CLOSE_ENDPOINT=""
if [ "$guidance_ok" = "1" ]; then
  REFLECT_ENDPOINT=$(pick_first_alive "${R_REFLECT_FULL[@]}")
  NEXT_ENDPOINT=$(pick_first_alive "${R_NEXT_FULL[@]}")
  CLOSE_ENDPOINT=$(pick_first_alive "${R_CLOSE_FULL[@]}")
fi

# --- Commands ----------------------------------------------------------------
cmd="${1:-help}"
shift || true

usage() {
  cat <<EOF
Zen CLI
-------
ENV minimal:
  export ZEN_COMMUNITY="https://nameless-breeze-87fb.edcvaultcom.workers.dev"
  # Optional (wenn Guidance vorhanden):
  export ZEN_GUIDANCE="https://<dein-guidance>.workers.dev"

Befehle:
  health                 → zeigt Worker-Status (Community/Guidance)
  demo "<text>"          → volle Demo; fällt zurück auf community-demo wenn Guidance fehlt
  community-demo         → nur Help/Talk Acks + Zähler
  reflect "<text>"       → startet Session (nur mit Guidance)
  next "<antwort>"       → nächste Runde (nur mit Guidance)
  close                  → Closure/Mood-Intro (nur mit Guidance)
  mood <0..4>            → App-/Backend-Mood (nur wenn dein App-Backend + Token konfiguriert sind)
  help-ack               → +1 geholfen (Community)
  talk-ack               → +1 Gespräche (Community)
  counters               → beide Zähler anzeigen
EOF
}

do_health() {
  echo "Community:"
  get_json "${ZEN_COMMUNITY}/health" | sed '$d' | jq . || echo "{}"
  if [ "$guidance_ok" = "1" ]; then
    echo
    echo "Guidance:"
    get_json "${ZEN_GUIDANCE}/health" | sed '$d' | jq . || echo "{}"
  else
    echo
    echo "Guidance: nicht konfiguriert oder nicht erreichbar (Community-Only-Modus)."
  fi
}

do_community_demo() {
  echo "— Community Demo —"
  echo "+1 Help-Ack …"
  get_json "${COMM_HELP_ACK}" | sed '$d' | jq .
  echo "+1 Talk-Ack …"
  get_json "${COMM_TALK_ACK}" | sed '$d' | jq .
  echo "Totals:"
  get_json "${COMM_HELP_TOTAL}" | sed '$d' | jq .
  get_json "${COMM_TALK_TOTAL}" | sed '$d' | jq .
}

# Session Cache (einfach im /tmp)
STATE_DIR="${TMPDIR:-/tmp}/zen_cli_state"
mkdir -p "$STATE_DIR"
STATE_FILE="${STATE_DIR}/session.json"

cache_write() { printf '%s' "$1" > "$STATE_FILE"; }
cache_read()  { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo '{}'; }
cache_clear() { rm -f "$STATE_FILE"; }

reflect_start() {
  [ "$guidance_ok" != "1" ] && { err "Keine Guidance verfügbar. Nutze 'community-demo'."; exit 2; }
  local text="${1:-}"
  [ -z "$text" ] && { err "Bitte Text angeben: reflect \"<text>\""; exit 2; }
  local body
  body=$(jq -nc --arg t "$text" --arg l "$ZEN_LOCALE" --arg tz "$ZEN_TZ" \
        '{text:$t, locale:$l, tz:$tz}')
  local url="$REFLECT_ENDPOINT"
  [ -z "$url" ] && { err "Kein reflect_full-Endpoint auffindbar."; exit 2; }
  resp="$(post_json "$url" "$body")"
  code="$(printf '%s' "$resp" | http_code_from_tail)"
  out="${resp%___HTTP:*}"
  echo "— /reflect_full —"
  echo "$out" | jq .
  # session extrahieren (robust)
  sid="$(echo "$out" | jq -r '(.session.id // .session.thread_id // .thread_id // empty)' || true)"
  turn="$(echo "$out" | jq -r '(.session.turn // .session.turn_index // 0)' || echo 0)"
  if [ -n "$sid" ]; then
    jq -nc --arg id "$sid" --argjson turn "${turn:-0}" '{id:$id, turn:$turn}' | cache_write
  else
    cache_clear
  fi
}

reflect_next() {
  [ "$guidance_ok" != "1" ] && { err "Keine Guidance verfügbar."; exit 2; }
  local answer="${1:-}"
  [ -z "$answer" ] && { err "Bitte Antwort angeben: next \"<antwort>\""; exit 2; }
  local sess="$(cache_read)"
  sid="$(echo "$sess" | jq -r '.id // empty')"
  tnr="$(echo "$sess" | jq -r '.turn // 0')"
  [ -z "$sid" ] && { err "Keine Session gefunden. Erst 'reflect' ausführen."; exit 2; }

  local body
  body=$(jq -nc --arg id "$sid" --arg a "$answer" --arg l "$ZEN_LOCALE" --arg tz "$ZEN_TZ" \
         '{session:{id:$id, turn:0}, text:$a, locale:$l, tz:$tz}')
  local url="$NEXT_ENDPOINT"
  [ -z "$url" ] && { err "Kein next_turn_full-Endpoint auffindbar."; exit 2; }
  resp="$(post_json "$url" "$body")"
  code="$(printf '%s' "$resp" | http_code_from_tail)"
  out="${resp%___HTTP:*}"
  echo "— /next_turn_full —"
  echo "$out" | jq .
  sid2="$(echo "$out" | jq -r '(.session.id // .session.thread_id // .thread_id // empty)' || true)"
  turn2="$(echo "$out" | jq -r '(.session.turn // .session.turn_index // 0)' || echo 0)"
  [ -n "$sid2" ] && jq -nc --arg id "$sid2" --argjson turn "${turn2:-0}" '{id:$id, turn:$turn}' | cache_write
}

reflect_close() {
  [ "$guidance_ok" != "1" ] && { err "Keine Guidance verfügbar."; exit 2; }
  local sess="$(cache_read)"
  sid="$(echo "$sess" | jq -r '.id // empty')"
  [ -n "$sid" ] || { err "Keine Session gefunden. Erst 'reflect' ausführen."; exit 2; }
  local body
  body=$(jq -nc --arg id "$sid" --arg l "$ZEN_LOCALE" --arg tz "$ZEN_TZ" \
         '{session:{id:$id}, locale:$l, tz:$tz}')
  local url="$CLOSE_ENDPOINT"
  [ -z "$url" ] && { err "Kein closure_full-Endpoint auffindbar."; exit 2; }
  resp="$(post_json "$url" "$body")"
  code="$(printf '%s' "$resp" | http_code_from_tail)"
  out="${resp%___HTTP:*}"
  echo "— /closure_full —"
  echo "$out" | jq .
}

do_mood() {
  # Nur wenn du ein App-Backend hast (nicht Teil des Community-Workers)
  if [ -z "${ZEN_APP_API:-}" ] || [ -z "${ZEN_APP_TOKEN:-}" ]; then
    err "Mood-API nicht konfiguriert (ZEN_APP_API & ZEN_APP_TOKEN). Überspringe."
    exit 0
  fi
  local score="${1:-}"
  [[ "$score" =~ ^[0-4]$ ]] || { err "mood <0..4>"; exit 2; }
  local body
  body=$(jq -nc --argjson s "$score" '{icon:$s, note:null}')
  IFS= read -r -d '' -a HDRS < <(build_headers "$body")
  HDRS+=(-H "Authorization: Bearer ${ZEN_APP_TOKEN}")
  url="${ZEN_APP_API%/}/mood"
  [ "$ZEN_DEBUG" = "1" ] && { echo; echo "→ POST $url"; echo "$body" | jq .; }
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${HDRS[@]}" --data "$body" "$url" || true)
  echo "{ \"mood_sent\": $score, \"http\": $code }" | jq .
}

help_ack()  { get_json "${COMM_HELP_ACK}"       | sed '$d' | jq .; }
talk_ack()  { get_json "${COMM_TALK_ACK}"       | sed '$d' | jq .; }
counters()  {
  get_json "${COMM_HELP_TOTAL}" | sed '$d' | jq .
  get_json "${COMM_TALK_TOTAL}" | sed '$d' | jq .
}

do_demo() {
  local seed="${1:-Ich fühle mich heute angespannt, vielleicht wegen Arbeit}"
  if [ "$guidance_ok" = "1" ] && [ -n "$REFLECT_ENDPOINT" ]; then
    do_health >/dev/null || true
    reflect_start "$seed"
    reflect_next  "Kurz: Termine + Druck."
    reflect_close
    # Mood nur, wenn App-Backend vorhanden
    if [ -n "${ZEN_APP_API:-}" ] && [ -n "${ZEN_APP_TOKEN:-}" ]; then
      do_mood 3 || true
    else
      echo "— /mood —"
      echo "{ \"info\": \"kein App-Backend konfiguriert – übersprungen\" }" | jq .
    fi
    echo "+1 Help-Ack …"; help_ack
    echo "+1 Talk-Ack …"; talk_ack
    echo "Community counters:"; counters
  else
    echo "Guidance nicht verfügbar → wechsle zu Community-Demo."
    do_community_demo
  fi
}

case "$cmd" in
  help|-h|--help) usage ;;
  health)         do_health ;;
  community-demo) do_community_demo ;;
  demo)           do_demo "$@" ;;
  reflect)        reflect_start "$@" ;;
  next)           reflect_next "$@" ;;
  close)          reflect_close ;;
  mood)           do_mood "$@" ;;
  help-ack)       help_ack ;;
  talk-ack)       talk_ack ;;
  counters)       counters ;;
  *)
    err "Unbekanntes Kommando: $cmd"
    usage
    exit 2
    ;;
esac
