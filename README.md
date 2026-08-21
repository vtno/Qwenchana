# Qwenchana

> *Qwenchana* plays on Korean *괜찮아* (*gwaenchanha*) — "it's okay": even if
> you have old GPUs.

Qwenchana is a turnkey Qwen3.8-27B serving setup specifically for inference server with 2x RTX 3090

Omakase style one command llm serving solution built for Claude Code & OpenCode:

- `unsloth/Qwen3.8-27B-NVFP4` (256k context) on **2x RTX 3090**
- vLLM
- LiteLLM gateway (auth, rate limits, budgets)
- Claude Code / OpenCode client configs.

```
client (claude / opencode / any OpenAI client)
        │  http://localhost:4000
        ▼
LiteLLM gateway ── Postgres (keys/budgets) + Redis (rate limits)
        │  http://vllm:8000
        ▼
vLLM serve (TP2, NVFP4/Marlin, 256k, prefix caching)
```

## Quick start

Requirements: 2x RTX 3090 (24GB), NVIDIA driver ≥ 580, Docker + nvidia-container-toolkit.

```bash
./qcn    # downloads weights (~22 GB) if missing, creates litellm/.env
                  # (prompts for master key / UI credentials), starts the stack,
                  # waits for vLLM to be healthy, prints connection details
```

Connect a client:

```bash
./qcn install opencode   # merge the provider into your existing opencode config
./qcn run claude         # or: launch a client now (env injected, nothing written)
./qcn run opencode
```

`install opencode` extends your existing config, never overrides it
(opencode's previous config is kept as `opencode.json.bak`). `run` just
execs the client in a configured shell.

Manual alternative (no config files touched at all):

```bash
export LITELLM_BASE_URL=http://localhost:4000
export LITELLM_API_KEY=<printed by ./qcn>
OPENCODE_CONFIG=assets/opencode.json opencode    # or:
source assets/claude-code-env.sh && claude
```

Any OpenAI-compatible client also works directly against `http://localhost:8000/v1`.
Disable thinking per request with `"chat_template_kwargs": {"enable_thinking": false}`.

<details>
<summary>Manual setup / dev path</summary>

```bash
hf download unsloth/Qwen3.8-27B-NVFP4 \
  --revision 7d6f8d4d72f56b92b3cdbf22f156b90e1bab0108 --local-dir models
cp litellm/.env.example litellm/.env
docker compose up -d --build
```

Dev path: vLLM on the host via venv ([`setup.sh`](https://github.com/vtno/Qwenchana/blob/main/setup.sh) &&
[`serve.sh`](https://github.com/vtno/Qwenchana/blob/main/serve.sh)), gateway only
(`docker compose up -d litellm db redis`), with
`VLLM_BASE_URL=http://host.docker.internal:8000/v1` in `litellm/.env`.

</details>

## Usage

Harness configs via [`assets/`](https://github.com/vtno/Qwenchana/tree/main/assets) (env-var driven, no secrets in the files) — see [`assets/README.md`](https://github.com/vtno/Qwenchana/blob/main/assets/README.md).

### OpenCode

```bash
./qcn install opencode   # merge the gateway provider into your existing config (extends, never overrides)
./qcn run opencode       # or launch now (env injected, nothing written)
# zero-config: OPENCODE_CONFIG=assets/opencode.json opencode
```

### Claude Code

```bash
./qcn run claude         # launch now (env injected, nothing written)
# zero-config: source assets/claude-code-env.sh && claude
```

Routed to the `-ant` gateway alias (Anthropic passthrough to vLLM's native `/v1/messages`).

### Manual wiring

```bash
# OpenAI route — OpenCode, any OpenAI client (via /v1/chat/completions)
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"hi"}]}'

# Anthropic route — Claude Code (via /v1/messages, native)
ANTHROPIC_BASE_URL=http://localhost:4000 ANTHROPIC_AUTH_TOKEN=$LITELLM_API_KEY \
  claude --model qwen3.8-27b-ant
```

`./qcn` does this for you; the snippets above are the underlying calls.

## Technical Specification

### vLLM

vLLM 0.27.1 (official image, digest-pinned, CUDA 13 build) with:

```
--tensor-parallel-size 2 --max-model-len 262144 --reasoning-parser qwen3
--enable-prefix-caching --max-num-batched-tokens 16384 --skip-mm-profiling
--enable-auto-tool-choice --tool-call-parser qwen3_coder
```

plus `VLLM_NVFP4_GEMM_BACKEND=marlin` — NVFP4 is officially a Hopper/Blackwell
format; on Ampere it works via the Marlin backend + the patch below. The tool
flags are required (clients sending `tool_choice: "auto"` 400 without them).
The MTP draft head is in the checkpoint but **disabled** — it benchmarks slower
on Ampere (see Performance).

#### Local patch (not upstream yet)

Fixes [vLLM #52434](https://github.com/vllm-project/vllm/issues/52434) for quantized-lm_head NVFP4 checkpoints (open [PR #52451](https://github.com/vllm-project/vllm/pull/52451)):
[`patches/vllm-0.27.1-humming-utils-52434.patch`](https://github.com/vtno/Qwenchana/blob/main/patches/vllm-0.27.1-humming-utils-52434.patch).
Baked into the image at build time; [`setup.sh`](https://github.com/vtno/Qwenchana/blob/main/setup.sh) applies it to the venv;
`git am` it into a vLLM checkout if you prefer. Drop once [#52451](https://github.com/vllm-project/vllm/pull/52451) merges.

### Gateway

- Config in `litellm/.env` (template: [`litellm/.env.example`](https://github.com/vtno/Qwenchana/blob/main/litellm/.env.example)),
  rendered at container start (LiteLLM doesn't interpolate env vars itself).
  Apply changes: `docker compose up -d litellm --force-recreate`
- Admin UI: http://localhost:4000/ui
- Model aliases: `qwen3.8-27b` (no thinking) + `-low/-mid/-high/-xhigh`
  reasoning-effort variants + `-ant` (Anthropic Messages API passthrough —
  Claude Code is routed to vLLM's native `/v1/messages`, which handles its
  mid-conversation system messages; the OpenAI entries translate via the
  Responses API, which the Qwen chat template rejects)
- Routes (how LiteLLM forwards to vLLM):
  | Client format | Gateway model | LiteLLM route | vLLM endpoint |
  | --- | --- | --- | --- |
  | OpenAI (`/v1/chat/completions`) | `qwen3.8-27b*` | `openai/*` | `/v1/chat/completions` |
  | Anthropic (`/v1/messages`) | `qwen3.8-27b-ant` | `anthropic/*` | `/v1/messages` (native) |
- `:8000` is bound to 127.0.0.1 (vLLM has no auth) — the gateway is the auth boundary

### Performance

Headline (2x 3090, TP2, pp8192/tg256): prefill ~2500 t/s, generation
66.7 t/s (c1) / ~73 t/s (c8). Verdicts baked into the flags:

| Serving choice        | Effect (2x 3090)                              |
| --------------------- | --------------------------------------------- |
| **MTP off**           | −48% single-stream on Ampere                  |
| **prefix caching on** | 8x faster TTFR on cached context, no gen penalty |
| **`--max-num-batched-tokens 16384`** | prefill +2–3%, gen flat          |
| humming == marlin, fp8 KV | no measurable change                     |

Full back-trace with raw `llama-benchy` tables: [`bench/`](https://github.com/vtno/Qwenchana/tree/main/bench).

## Caveats

- **Flaky boot:** vLLM engine core can die silently ~3–8s into startup
  (~1-in-6). In compose this self-heals (`restart: unless-stopped`); on the
  venv path, restart in a loop or fall back to `--enforce-eager`.
- Upgrading vLLM = rebuild the image + re-verify the patch.
- Weights (~22 GB) are downloaded once into `models/` (mounted, never in the image).
