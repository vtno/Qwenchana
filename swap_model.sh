#!/usr/bin/env bash
# Swap live model either direction: ./swap_model.sh <w4a16|nvfp4>
# Auto-rolls back if the target fails to become healthy.
set -u
cd "$(dirname "$0")"
TARGET=$1
if [ "$TARGET" = "w4a16" ]; then NEW=models-w4a16; OLD=models-nvfp4
else NEW=models-nvfp4; OLD=models-w4a16; fi

VLLM_HEALTH=http://127.0.0.1:8000/health
GW_URL=http://127.0.0.1:4000
UP_TIMEOUT=900
log() { echo "[$(date -u '+%H:%M:%S')] $*"; }
wait_up() {
  local end=$(( $(date +%s) + UP_TIMEOUT ))
  while :; do
    curl -sf -o /dev/null "$VLLM_HEALTH" && { log "UP"; return 0; }
    [ "$(date +%s)" -ge "$end" ] && { log "TIMEOUT"; return 1; }
    sleep 5
  done
}
smoke() {
  local key
  key=$(grep -E '^LITELLM_MASTER_KEY=' litellm/.env | head -1 | cut -d= -f2-)
  curl -sf --max-time 300 "$GW_URL/v1/chat/completions" \
    -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
    -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"ping"}],"max_tokens":5}' >/dev/null
}
start() { docker compose up -d vllm --force-recreate >/dev/null && wait_up; }

[ -d "$NEW" ] || { echo "ERROR: $NEW missing"; exit 1; }
if { [ "$TARGET" = "nvfp4" ] && grep -q nvfp4 models/config.json 2>/dev/null; } \
   || { [ "$TARGET" = "w4a16" ] && ! grep -q nvfp4 models/config.json 2>/dev/null; }; then
  log "already on $TARGET; ensuring vLLM up"
  start && smoke && echo "SWAP-$TARGET-READY" && exit 0
  echo "BOTH-FAILED"; exit 2
fi

log "swapping to $TARGET"
mv models "$OLD"
mv "$NEW" models
if start && smoke; then
  echo "SWAP-$TARGET-READY"; exit 0
fi
log "target FAILED -> rolling back"
mv models "$NEW"
mv "$OLD" models
if start && smoke; then
  echo "ROLLBACK-READY"; exit 1
fi
echo "BOTH-FAILED"; exit 2
