#!/usr/bin/env bash
set -euo pipefail

# === Zen Panda Debug: Merge-Flag Pipeline (SSoT) ==============================
# - Einheitliche Flags via FLAGS_JSON (client_memory + client_memory_merge)
# - Case A: nur context.memories (ohne Flags)  → kein Namens-Gruß (erwartet)
# - Case B*: Flags + Top-Level+Context memories → Name ab Turn 0/2
# - Case C: "ich heiße <Name>" → Name im selben Turn
# ==============================================================================

# --- Worker + Token (Tipp: per ENV überschreiben & Token NICHT committen) ----
BASE_URL="${WORKER_BASE:-https://nameless-breeze-87fb.edcvaultcom.workers.dev}"
APP_TOKEN="${APP_TOKEN:-daded2f03bd67dd25d8434272c7095c234c80f9d15daefb253418b7a779244aa}"  # TODO: rotieren

# Optionaler Name als Argument, sonst "Matthias"
NAME="${1:-Matthias}"

# SSoT: beide Flags in EINEM JSON-Block
FLAGS_JSON='{"client_memory":true,"client_memory_merge":true}'

# Abhängigkeiten prüfen
for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Fehlt: $bin"; exit 1; }
done

# Header & kleine Helfer
hdr=(-H "Authorization: Bearer $APP_TOKEN" -H "Content-Type: application/json")
jq_filter='. | {mirror: .mirror, question: (.question // .primary // .output_text), reply: .reply}'

check_name_in () {
  local json="$1"
  echo "$json" | tee /dev/tty | jq -r '.mirror, .question, .reply' | grep -iq -- "$NAME" \
    && echo "✔ Name gefunden" || echo "… (kein Name, aber ok)"
}

echo "Resolved BASE_URL: $BASE_URL"
echo "Token length: ${#APP_TOKEN}"
echo

# ---------- Case A: nur context.memories (ohne Top-Level, ohne Merge-Flag) ----------
echo "Case A: nur context.memories (ohne Top-Level, ohne Merge-Flag)"
payload_a="$(jq -nc --arg name "$NAME" '{
  text:"start",
  locale:"de", tz:"Europe/Zurich",
  session:{id:("dbg-a-"+(now|tostring)), turn:0, max_turns:3},
  memory_consent:true,
  context:{memories:{identity:{name:$name}, profile:{user_name:$name}}}
}')"
out_a="$(echo "$payload_a" \
  | curl -sS -X POST "$BASE_URL/reflect_full" "${hdr[@]}" -d @- \
  | jq "$jq_filter" 2>/dev/null || true)"
echo "$out_a"
check_name_in "$out_a"
echo "✅ Erwartung: KEIN Namens-Gruß (Legacy-Pfad will Top-Level/Flag)."
echo

# ---------- Case B: Merge-Variante (Top-Level + Flags) ----------
SID="dbg-b-$(date +%s%N)"

echo "Case B1: context.memories + Top-Level memories + Flags (Turn 0)"
payload_b1="$(jq -nc \
  --arg name "$NAME" \
  --arg sid "$SID" \
  --argjson flags "$FLAGS_JSON" \
  '{
    text:"start",
    locale:"de", tz:"Europe/Zurich",
    session:{id:$sid, turn:0, max_turns:3},
    memory_consent:true,
    meta:{flags:$flags},
    context:{memories:{identity:{name:$name}, profile:{user_name:$name}}},
    memories:{identity:{name:$name}, profile:{user_name:$name}}
  }')"
out_b1="$(echo "$payload_b1" \
  | curl -sS -X POST "$BASE_URL/reflect_full" "${hdr[@]}" -d @- \
  | jq "$jq_filter" 2>/dev/null || true)"
echo "$out_b1"
check_name_in "$out_b1"
echo

echo "Case B2: gleicher Session-ID → next_turn_full (Turn 1, ohne erneute Memories)"
payload_b2="$(jq -nc \
  --arg sid "$SID" \
  --argjson flags "$FLAGS_JSON" \
  '{
    text:"weiter",
    locale:"de", tz:"Europe/Zurich",
    session:{id:$sid, turn:1, max_turns:3},
    memory_consent:true,
    meta:{flags:$flags}
  }')"
out_b2="$(echo "$payload_b2" \
  | curl -sS -X POST "$BASE_URL/next_turn_full" "${hdr[@]}" -d @- \
  | jq "$jq_filter" 2>/dev/null || true)"
echo "$out_b2"
check_name_in "$out_b2"
echo

echo "Case B2R: Turn 1 MIT Memories erneut mitsenden (wie die App)"
payload_b2r="$(jq -nc \
  --arg sid "$SID" \
  --arg name "$NAME" \
  --argjson flags "$FLAGS_JSON" \
  '{
    text:"weiter (resend memories)",
    locale:"de", tz:"Europe/Zurich",
    session:{id:$sid, turn:1, max_turns:3},
    memory_consent:true,
    meta:{flags:$flags},
    context:{memories:{identity:{name:$name}, profile:{user_name:$name}}},
    memories:{identity:{name:$name}, profile:{user_name:$name}}
  }')"
out_b2r="$(echo "$payload_b2r" \
  | curl -sS -X POST "$BASE_URL/next_turn_full" "${hdr[@]}" -d @- \
  | jq "$jq_filter" 2>/dev/null || true)"
echo "$out_b2r"
check_name_in "$out_b2r"
echo

echo "— Payload-Check (Case B1, gekürzt) —"
echo "$payload_b1" | jq '{memory_consent, meta, context:{memories}, memories}'
echo

# ---------- Case B3: Identitäts-Probe (gleiche Session-ID) ----------
echo "Case B3: Identitäts-Probe (gleiche Session-ID, explizite Nachfrage)"
payload_b3="$(jq -nc \
  --arg sid "$SID" \
  --argjson flags "$FLAGS_JSON" \
  '{
    text:"Wie ist mein Name?",
    locale:"de", tz:"Europe/Zurich",
    session:{id:$sid, turn:2, max_turns:3},
    memory_consent:true,
    meta:{flags:$flags}
  }')"
out_b3="$(echo "$payload_b3" \
  | curl -sS -X POST "$BASE_URL/next_turn_full" "${hdr[@]}" -d @- \
  | jq "$jq_filter" 2>/dev/null || true)"
echo "$out_b3"
check_name_in "$out_b3"
echo

# ---------- Case C: Sofort-Injection im selben Turn ----------
echo 'Case C: Sofort-Injection (Text enthält "ich heiße ...") → Name im selben Turn'
payload_c="$(jq -nc \
  --arg name "$NAME" \
  --argjson flags "$FLAGS_JSON" \
  '{
    text:("ich heiße "+$name),
    locale:"de", tz:"Europe/Zurich",
    session:{id:("dbg-c-"+(now|tostring)), turn:0, max_turns:3},
    memory_consent:true,
    meta:{flags:$flags},
    context:{memories:{identity:{name:$name}, profile:{user_name:$name}}},
    memories:{identity:{name:$name}, profile:{user_name:$name}}
  }')"
out_c="$(echo "$payload_c" \
  | curl -sS -X POST "$BASE_URL/reflect_full" "${hdr[@]}" -d @- \
  | jq "$jq_filter" 2>/dev/null || true)"
echo "$out_c"
check_name_in "$out_c"
echo

echo "Fertig. Erwartung:"
echo "  • Case A: kein Name"
echo "  • Case B2: evtl. kein Name (ohne erneute Memories) — Demonstration"
echo "  • Case B2R/B3: Name da (wie App-Verhalten)"
echo "  • Case C: Name sofort im selben Turn"
