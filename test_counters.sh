HOST="https://nameless-breeze-87fb.edcvaultcom.workers.dev"
echo "GET  /help-total";            curl -s "$HOST/v1/community/help-total" | jq .
echo "POST /help-ack";              curl -s -X POST "$HOST/v1/community/help-ack" | jq .
echo "GET  /conversations-total";   curl -s "$HOST/v1/community/conversations-total" | jq .
echo "POST /talk-ack";              curl -s -X POST "$HOST/v1/community/talk-ack" | jq .
