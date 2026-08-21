#!/usr/bin/env bash
# E2E test: Qwen through the LiteLLM gateway via
#   T1: raw OpenAI API (baseline)
#   T2: OpenCode harness   (OPENCODE_CONFIG, isolated HOME)
#   T3: Claude Code harness (claude -p via assets/claude-code-env.sh, isolated HOME)
#
# Usage: ./test/e2e.sh   (gateway must be running)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${LITELLM_BASE_URL:-http://localhost:4000}"
KEY="${LITELLM_API_KEY:-$(grep '^LITELLM_MASTER_KEY=' "$DIR/litellm/.env" 2>/dev/null | cut -d= -f2-)}"
MODEL="${QWENCHANA_E2E_MODEL:-qwen3.8-27b}"
EXPECT="QWENCHANA-E2E-OK"
TIMEOUT=240
PASS=0; FAIL=0

report() { # $1=name $2=rc $3=detail (optional)
  local name=$1 rc=$2 detail=${3:-}
  if [ "$rc" -eq 0 ]; then
    printf "\033[32mPASS\033[0m %-24s %b\n" "$name" "$detail"; PASS=$((PASS+1))
  else
    printf "\033[31mFAIL\033[0m %-24s %b\n" "$name" "$detail"; FAIL=$((FAIL+1))
  fi
}

[ -n "$KEY" ] || { echo "No API key: set LITELLM_API_KEY or create litellm/.env" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROMPT="Reply with exactly this token and nothing else: $EXPECT"

echo "E2E: $BASE_URL  model=$MODEL"
echo ""

# ---------- T1: raw OpenAI API through the gateway ----------
OUT=$(curl -sf -m 120 -X POST "$BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"max_tokens\":32,\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}" 2>&1)
RC=$?
if [ $RC -eq 0 ] && echo "$OUT" | grep -q "$EXPECT"; then
  report "T1 gateway api (raw)" 0
else
  report "T1 gateway api (raw)" 1 "marker missing; response: $(echo "$OUT" | head -c 200)"
fi

# ---------- T2: OpenCode harness ----------
if command -v opencode >/dev/null 2>&1; then
  HOME="$TMP/home-oc" OPENCODE_CONFIG="$DIR/assets/opencode.json" \
    LITELLM_BASE_URL="$BASE_URL" LITELLM_API_KEY="$KEY" \
    timeout "$TIMEOUT" opencode run "$PROMPT" > "$TMP/oc.out" 2>&1
  RC=$?
  if [ $RC -eq 0 ] && grep -q "$EXPECT" "$TMP/oc.out"; then
    report "T2 opencode harness" 0
  else
    report "T2 opencode harness" 1 "rc=$RC; output: $(tail -c 300 "$TMP/oc.out")"
  fi
else
  report "T2 opencode harness" 1 "(opencode CLI not installed)"
fi

# ---------- T3: Claude Code harness ----------
if command -v claude >/dev/null 2>&1; then
  HOME="$TMP/home-cc" LITELLM_BASE_URL="$BASE_URL" LITELLM_API_KEY="$KEY" \
    bash -c "source '$DIR/assets/claude-code-env.sh'; timeout $TIMEOUT claude -p '$PROMPT'" \
    > "$TMP/cc.out" 2>&1
  RC=$?
  if [ $RC -eq 0 ] && grep -q "$EXPECT" "$TMP/cc.out"; then
    report "T3 claude code harness" 0
  else
    report "T3 claude code harness" 1 "rc=$RC; output: $(tail -c 300 "$TMP/cc.out")"
  fi
else
  report "T3 claude code harness" 1 "(claude CLI not installed)"
fi

echo ""
echo "=============================="
echo " E2E result: $PASS passed, $FAIL failed"
echo "=============================="
[ "$FAIL" -eq 0 ]
