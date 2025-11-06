#!/usr/bin/env bash
# zenpanda_smoke.sh — v1.7 (2025-11-03)
# Test: Turn0 pusht Name NUR via context.memories (kein Name im Chat-Verlauf).
# Erwartung: Turn1/2 zeigen source=SERVER_RECALL (Tag: name_recall), NICHT local_only.

set -euo pipefail
# export BASE="https://nameless-breeze-87fb.edcvaultcom.workers.dev"
# export APP_TOKEN="daded2f03bd67dd25d8434272c7095c234c80f9d15daefb253418b7a779244aa"
: "${BASE:?Bitte BASE setzen (https://...workers.dev)}"
: "${APP_TOKEN:?Bitte APP_TOKEN setzen}"
SEND_MOOD="${SEND_MOOD:-1}"

for cmd in curl jq uuidgen; do command -v "$cmd" >/dev/null || { echo "Fehlt: $cmd"; exit 1; }; done

SID="$(uuidgen)"; echo "🧪 Starte Smoke-Test · Session: $SID"
HDR=(-H "Authorization: Bearer $APP_TOKEN" -H "Content-Type: application/json")

src_flag_jq='
  .tags as $t |
  ( if ($t|index("local_only")) then "LOCAL_ONLY"
    elif ($t|index("name_recall")) then "SERVER_RECALL"
    else "UNKNOWN" end ) as $src |
  {
    turn: (.session.turn // .session.turn_index // 0),
    source: $src,
    tags: ($t // []),
    says_name: (..|strings|select(test("Matthias";"i"))? // empty),
    question: (.question // .output_text // ""),
    helpers: (.answer_helpers // []),
    risk: (.risk_level // "none"),
    mood_prompt: (.flow.mood_prompt // false),
    recommend_end: (.flow.recommend_end // false)
  }
'

say(){ printf "\n——— %s ———\n" "$*"; }

# === /health ================================================================
say "HEALTH"
curl -fsS "$BASE/health" "${HDR[@]}" | jq '{ok,version,model,retrieval,anon_mode,time}'

# === TURN 0 — Name pushen (füttert Session-Profile) ========================
say "TURN 0 · Name push (Matthias)"
P0=$(jq -nc --arg sid "$SID" '{
  text:"Ich heiße Matthias.", locale:"de", tz:"Europe/Zurich",
  session:{id:$sid, turn:0, max_turns:6},
  memory_consent:true,
  meta:{flags:{client_memory:true, client_memory_merge:true}},
  context:{memories:{identity:{name:"Matthias"}}},
  memories:{identity:{name:"Matthias"}},
  messages:[{role:"user", content:"Ich heiße Matthias."}]
}')
curl -fsS "$BASE/reflect_full" "${HDR[@]}" --data "$P0" \
  | tee /tmp/zen_p0.json | jq "$src_flag_jq"

# === TURN 1 — Recall ohne locals ===========================================
say "TURN 1 · Recall ohne locals (Erwartung: evtl. LOCAL_ONLY wegen Full-Session)"
P1=$(jq -nc --arg sid "$SID" '{
  text:"Wie heiße ich?", locale:"de", tz:"Europe/Zurich",
  session:{id:$sid, turn:1, max_turns:6},
  memory_consent:true,
  meta:{flags:{client_memory:true, client_memory_merge:true}},
  messages:[{role:"user", content:"Wie heiße ich?"}]
}')
curl -fsS "$BASE/reflect_full" "${HDR[@]}" --data "$P1" \
  | tee /tmp/zen_p1.json | jq "$src_flag_jq"

# === TURN 2 — noch ein Recall ohne locals ==================================
say "TURN 2 · Nochmals Recall ohne locals"
P2=$(jq -nc --arg sid "$SID" '{
  text:"Sag es nochmal: Wie heiße ich?", locale:"de", tz:"Europe/Zurich",
  session:{id:$sid, turn:2, max_turns:6},
  memory_consent:true,
  meta:{flags:{client_memory:true, client_memory_merge:true}},
  messages:[{role:"user", content:"Sag es nochmal: Wie heiße ich?"}]
}')
curl -fsS "$BASE/reflect_full" "${HDR[@]}" --data "$P2" \
  | tee /tmp/zen_p2.json | jq "$src_flag_jq"

# === CLOSURE ================================================================
say "CLOSURE · /closure_full"
PC=$(jq -nc --arg sid "$SID" '{
  text:"Danke, das war hilfreich.", locale:"de", tz:"Europe/Zurich",
  session:{id:$sid, turn:3, max_turns:6},
  memory_consent:true,
  meta:{flags:{client_memory:true}},
  messages:[{role:"user", content:"Danke, das war hilfreich."}]
}')
curl -fsS "$BASE/closure_full" "${HDR[@]}" --data "$PC" \
  | tee /tmp/zen_close.json | jq '{
    turn:(.session.turn // .session.turn_index // 0),
    mood_prompt:(.flow.mood_prompt // false),
    recommend_end:(.flow.recommend_end // false),
    mood_intro:(.closure.mood_intro.text // .closure.mood_intro // "")
  }'

# === MOOD (optional) ========================================================
if [ "$SEND_MOOD" = "1" ]; then
  say "MOOD · /mood (4/5, helpfulness 2/5)"
  PM=$(jq -nc --arg sid "$SID" '{
    session:{id:$sid},
    mood:{value:4, label:"good", text:"gut"},
    helpfulness:{value:2, label:"bad", text:"niedrig"},
    locale:"de", tz:"Europe/Zurich"
  }')
  curl -fsS "$BASE/mood" "${HDR[@]}" --data "$PM" | jq '{ok,version,mood,helpfulness,interpretation}'
else
  say "MOOD · übersprungen (SEND_MOOD=0)"
fi

echo -e "\n✅ Smoke-Test beendet: Session $SID"