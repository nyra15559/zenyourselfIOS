# tools/check_memory_bridge.sh
#!/usr/bin/env bash
set -euo pipefail

API="${1:-lib/services/core/api_service.dart}"
MEM="${2:-lib/core/memory/memory_service.dart}"
GUI="${3:-lib/services/guidance_service.dart}"

fail=0
ok(){ echo "✅ $1"; }
bad(){ echo "❌ $1"; fail=1; }

chk(){ local f="$1" p="$2" d="$3"; if grep -Eq "$p" "$f"; then ok "$d"; else bad "$d"; fi; }

echo "== ApiService checks ($API) =="
chk "$API" "memory_consent"                           "sets memory_consent"
chk "$API" "shareEnabled|MemoryService\.instance\.shareEnabled" "uses shareEnabled for consent"
chk "$API" "context.*memories|\\['context'\\].*\\['memories'\\]" "adds context.memories"
chk "$API" "\\['memories'\\]\\s*="                    "adds top-level memories"
chk "$API" "client_memory_merge"                      "sets meta.flags.client_memory_merge:true"
chk "$API" "reflect_full"                             "reflect_full patched"
chk "$API" "next_turn_full"                           "next_turn_full patched"
chk "$API" "closure_full"                             "closure_full patched"

echo "== MemoryService checks ($MEM) =="
chk "$MEM" "class\\s+MemoryContextHint"               "MemoryContextHint exists"
chk "$MEM" "identityName|identity\\.name"             "hint/toJson carries identity.name"
chk "$MEM" "profileUserName|profile\\.user_name"      "hint/toJson carries profile.user_name"
chk "$MEM" "profileNicknames|nicknames"               "optional nicknames present"
chk "$MEM" "buildContextMemories\\(|recent_topics|hint" "buildContextMemories provides hint & recent_topics"

echo "== GuidanceService checks ($GUI) =="
chk "$GUI" "answer_helpers"                           "passes answer_helpers"
chk "$GUI" "mood_prompt"                              "uses flow.mood_prompt for mood gate"
if grep -Eq "chipsFromQuestion|localChips|fallback.*chip|generate.*chip" "$GUI"; then
  bad "no local/fallback chips in UI normalization"
else
  ok "no local/fallback chips in UI normalization"
fi

echo
if (( fail == 0 )); then
  echo "✅ All checks passed."
else
  echo "⚠️ One or more checks failed. See ❌ lines above." && exit 1
fi
