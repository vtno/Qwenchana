#!/usr/bin/env bash
# Point Claude Code at our LiteLLM gateway. Claude Code speaks the Anthropic
# Messages API (/v1/messages); the "-ant" model entry on the gateway is an
# anthropic passthrough straight to vLLM's native /v1/messages implementation,
# which handles Claude Code's mid-conversation system messages natively (the
# OpenAI-compatible entries translate via the Responses API, which the Qwen
# chat template rejects them for).
#
# Requires: LITELLM_BASE_URL and LITELLM_API_KEY in the environment
# (e.g. export LITELLM_BASE_URL=http://localhost:4000  LITELLM_API_KEY=<master key>).
# Add this line to your shell profile to apply everywhere
# (<repo> = wherever you cloned this repo):
#   source <repo>/assets/claude-code-env.sh
set -euo pipefail

: "${LITELLM_BASE_URL:?set LITELLM_BASE_URL, e.g. http://localhost:4000}"
: "${LITELLM_API_KEY:?set LITELLM_API_KEY to the LiteLLM master key}"

export ANTHROPIC_BASE_URL="${LITELLM_BASE_URL}"
export ANTHROPIC_AUTH_TOKEN="${LITELLM_API_KEY}"
export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-qwen3.8-27b-ant}"
export ANTHROPIC_SMALL_FAST_MODEL="${ANTHROPIC_SMALL_FAST_MODEL:-qwen3.8-27b-ant}"
# Suppress pre-release capability fields Claude Code would otherwise send.
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS="${CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS:-1}"
