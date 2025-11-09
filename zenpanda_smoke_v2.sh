#!/usr/bin/env bash
set -euo pipefail

# ── Worker & Token (von dir) ─────────────────────────────────────────────────
WORKER="https://nameless-breeze-87fb.edcvaultcom.workers.dev"
TOKEN="daded2f03bd67dd25d8434272c7095c234c80f9d15daefb253418b7a779244aa"

# Pretty printer
pp(){ if command -v jq >/dev/null; then jq; else cat; fi; }

# Thin wrappers
get(){  curl -fsS "$WORKER$1" -H "Authorization: Bearer $TOKEN"; }
post(){ curl -fsS "$WORKER$1" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$2"; }

echo "1) /health"
get /health | pp

echo; echo "2) /reflect_full — Ghost-Mode (keine Bridge, Name nur aus der Nachricht)"
post /reflect_full '{
  "intent":"reflect",
  "text":"Ich heiße Matthias. Heute nur ein kurzer Check.",
  "memory_consent": false,
  "meta": { "flags": { "client_memory": false } }
}' | pp

echo; echo "3) /next_turn_full — Bridge AN (kontext mit name/mood/topic) + THREAD capture"
RESP=$(post /next_turn_full '{
  "intent":"reflect",
  "text":"Weiter gehts mit dem heutigen Check-in.",
  "memory_consent": true,
  "context": {
    "memories": {
      "identity": { "name": "Matthias" },
      "last": { "topic": "Alltag", "mood": 3 }
    }
  },
  "meta": { "flags": { "client_memory": true } }
}')
echo "$RESP" | pp
THREAD=$(echo "$RESP" | jq -r '.session.thread_id // empty')
echo "THREAD=$THREAD"

if [ -z "$THREAD" ] || [ "$THREAD" = "null" ]; then
  echo "WARN: Kein thread_id zurückgegeben – Folge-Tests werden ohne Session fortgesetzt."
fi

echo; echo "4) /next_turn_full — gleicher Thread (Kontinuität prüfen)"
post /next_turn_full "$(cat <<JSON
{
  "intent":"reflect",
  "text":"Kleines Update im gleichen Thread. Ich bleibe bei einem ruhigen Check-in.",
  "memory_consent": true,
  "session": { "thread_id": "$THREAD" },
  "meta": { "flags": { "client_memory": true } }
}
JSON
)" | pp

echo; echo "5) /closure_full — sanft schließen (soll oft mood_prompt oder closure prompt liefern)"
post /closure_full "$(cat <<JSON
{
  "intent":"reflect",
  "text":"Lass uns sanft schließen.",
  "memory_consent": true,
  "session": { "thread_id": "$THREAD" },
  "flow": { "request_end": true }
}
JSON
)" | pp

echo; echo "6) /mood — Mood-Log nachreichen (3=mittel, helpfulness=4)"
post /mood "$(cat <<JSON
{
  "mood": 3,
  "helpfulness": 4,
  "note": "kurzer Tagescheck",
  "session": { "thread_id": "$THREAD" }
}
JSON
)" | pp

echo; echo "7) Consent-OFF-Test — Bridge AUS (Worker sollte Namen *nicht* aus context verwenden)"
post /next_turn_full '{
  "intent":"reflect",
  "text":"Teste: Consent AUS.",
  "memory_consent": false,
  "context": { "memories": { "identity": { "name": "Matthias" } } },
  "meta": { "flags": { "client_memory": false } }
}' | pp

echo; echo "8) Risk mild / Überforderung — Safety-Ton prüfen (soll sanft reagieren, kein Alarm)"
post /reflect_full '{
  "intent":"reflect",
  "text":"Ich bin seit Tagen übermüdet und fühle mich am Limit. Ich brauche einen sanften Umgang damit.",
  "memory_consent": false
}' | pp

echo; echo "9) Memory-Proposal — Bitte um Aha-Fakt (kann available_actions oder memories_to_save senden)"
post /next_turn_full "$(cat <<JSON
{
  "intent":"reflect",
  "text":"Merke dir: Wasser trinken hilft mir bei Unruhe.",
  "memory_consent": true,
  "session": { "thread_id": "$THREAD" },
  "meta": { "flags": { "client_memory": true } }
}
JSON
)" | pp

echo; echo "Fertig."
