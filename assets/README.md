# Harness configs for our LiteLLM gateway (Qwen3.8-27B)

## Recommended: one-command setup

From the repo root:

```bash
./qwenmakase install opencode   # merge the provider into ~/.config/opencode/opencode.json
./qwenmakase run claude         # launch Claude Code now (env injected, nothing written)
./qwenmakase run opencode       # launch OpenCode now
```

- `install opencode`: your existing config is extended (other providers/settings
  kept) and backed up to `opencode.json.bak`. Restart opencode to pick it up.
- `run` launches the client in a configured shell and changes nothing
  (same effect as the manual methods below).
- All read the key from `LITELLM_API_KEY` if set, otherwise `litellm/.env`.

## Manual: env vars

Both configs drive Claude Code and OpenCode through the LiteLLM proxy at
`LITELLM_BASE_URL` using the LiteLLM master key. No secrets are stored in these
files — set the two env vars first:

```bash
export LITELLM_BASE_URL=http://localhost:4000
export LITELLM_API_KEY=<your LiteLLM master key>   # LITELLM_MASTER_KEY from litellm/.env
```

## OpenCode — `opencode.json`

Uses OpenCode's `{env:VAR}` interpolation, so it reads the two env vars at
runtime. Use it directly:

```bash
OPENCODE_CONFIG=assets/opencode.json opencode
```

(paths relative to the repo root; or use the absolute path to your clone)

or drop/copy it into your project root as `opencode.json` (project config is
picked up automatically). It sets the model to `litellm/qwen3.8-27b`.

- `baseURL` = `{env:LITELLM_BASE_URL}/v1`
- `apiKey`  = `{env:LITELLM_API_KEY}`

## Claude Code — `claude-code-env.sh`

Claude Code has no config-file env interpolation (its settings `env` block is
literal), and it speaks the **Anthropic Messages API** (`/v1/messages`), which
LiteLLM serves. So instead of a JSON file, this script maps our two env vars to
the Claude Code variables it reads:

```bash
source assets/claude-code-env.sh
claude
```

or add `source <repo>/assets/claude-code-env.sh` to your shell profile to apply
everywhere (`<repo>` = wherever you cloned this repo). It sets:

- `ANTHROPIC_BASE_URL`    → `LITELLM_BASE_URL`
- `ANTHROPIC_AUTH_TOKEN`  → `LITELLM_API_KEY` (sent as `Authorization: Bearer`)
- `ANTHROPIC_MODEL` / `ANTHROPIC_SMALL_FAST_MODEL` → `qwen3.8-27b-ant`
  (the gateway's Anthropic-passthrough entry, routed to vLLM's native
  `/v1/messages`; override by pre-setting `ANTHROPIC_MODEL`)
- `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`

Verify with `claude` → `/status`: the `Anthropic base URL` line should show
`LITELLM_BASE_URL`, and the credential line should name `ANTHROPIC_AUTH_TOKEN`.
