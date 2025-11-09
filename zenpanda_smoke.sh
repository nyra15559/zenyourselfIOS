#!/usr/bin/env bash
set -euo pipefail

# Dein Worker & Token
WORKER="https://nameless-breeze-87fb.edcvaultcom.workers.dev"
TOKEN="daded2f03bd67dd25d8434272c7095c234c80f9d15daefb253418b7a779244aa"

# JSON-Pretty-Printer (jq, sonst plain)
pp() { if command -v jq >/dev/null; then jq; else cat; fi; }

get()  { curl -fsS "$WORKER$1" -H "Authorization: Bearer $TOKEN"; }
post() { curl -fsS "$WORKER$1" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$2"; }

echo "1) /health — Statuscheck"
get /health | pp

echo
echo "2) /reflect_full — Ghost-Mode (kein Sharing, keine Bridge)"
post /reflect_full '{
  "intent": "reflect",
  "text": "Ich heiße Matthias. Heute war viel los. Nur ein kurzer Check.",
  "memory_consent": false,
  "meta": { "flags": { "client_memory": false } }
}' | pp

echo
echo "3) /next_turn_full — Bridge AN (🍃/🌿: kuratierter Kontext)"
post /next_turn_full '{
  "intent": "reflect",
  "text": "Weiter gehts mit dem heutigen Check-in.",
  "memory_consent": true,
  "context": {
    "memories": {
      "identity": { "name": "Matthias" },
      "last": { "topic": "Alltag", "mood": 3 }
    }
  },
  "meta": { "flags": { "client_memory": true } }
}' | pp
