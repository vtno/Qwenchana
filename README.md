# Qwen3.8-27B — turnkey LLM serving

A pre-packaged local LLM serving stack: `unsloth/Qwen3.8-27B-NVFP4` (256k context)
served by vLLM on **2x RTX 3090 (24GB)**, fronted by a LiteLLM gateway
(key auth, rate limits, budgets), with ready-to-use client configs for
Claude Code and OpenCode. Two scripts to serve, two env vars to connect.

```
client (claude / opencode / any OpenAI client)
        │  http://localhost:4000
        ▼
LiteLLM gateway ── Postgres (keys/budgets) + Redis (rate limits)
        │  http://host.docker.internal:8000
        ▼
vLLM serve (TP2, NVFP4/Marlin, 256k, prefix caching)
```

## Quick start

Requirements: 2x RTX 3090 (24GB), NVIDIA driver ≥ 580, Docker + nvidia-container-toolkit,
Python 3.12 (only for the one-time model download).

```bash
# 1. One-time: fetch model weights (~22 GB) into ./models (pinned revision)
pip install -U "huggingface_hub[cli]"
hf download unsloth/Qwen3.8-27B-NVFP4 \
  --revision 7d6f8d4d72f56b92b3cdbf22f156b90e1bab0108 --local-dir models

# 2. Configure and start the whole stack (vLLM + gateway + Postgres + Redis)
cd litellm && cp .env.example .env           # set LITELLM_MASTER_KEY, DB_PASSWORD
docker compose up -d --build
# gateway: http://localhost:4000   vLLM: http://localhost:8000/v1

# 3. Point a client at it
export LITELLM_BASE_URL=http://localhost:4000
export LITELLM_API_KEY=<LITELLM_MASTER_KEY>
OPENCODE_CONFIG=assets/opencode.json opencode        # or:
source assets/claude-code-env.sh && claude
```

Dev/alternative: run vLLM on the host via the venv (`./setup.sh && ./serve.sh`) and
start only the gateway with `docker compose up -d litellm db redis`, setting
`VLLM_BASE_URL=http://host.docker.internal:8000/v1` in `litellm/.env`.

Any OpenAI-compatible client works directly against `:8000` (or `:4000` through
the gateway). Disable thinking per request with
`"chat_template_kwargs": {"enable_thinking": false}`.

## What's included

```
Dockerfile.vllm       vLLM serving image (official base + humming patch baked in)
litellm/              all-in-one compose: vllm + litellm + postgres + redis
assets/               client harness configs (opencode.json, claude-code-env.sh)
patches/              git patch for vLLM (baked into the image at build time)
setup.sh / serve.sh   dev path: venv vLLM on the host (fallback, faster iteration)
bench/                tuning benchmarks backing the serving flags
```

## vLLM serving

The `vllm` compose service (built from `Dockerfile.vllm`: official
`vllm/vllm-openai:v0.27.1` + the humming patch + env vars) runs vLLM 0.27.1
with:

```
--tensor-parallel-size 2 --max-model-len 262144 --reasoning-parser qwen3
--enable-prefix-caching --max-num-batched-tokens 16384 --skip-mm-profiling
--enable-auto-tool-choice --tool-call-parser qwen3_coder
```

plus env: `VLLM_NVFP4_GEMM_BACKEND=marlin`, `VLLM_TEST_FORCE_FP8_MARLIN=1`
(set in the image), and `HF_HUB_OFFLINE=1` (weights come from the mounted
`./models`). The venv path additionally needs `LD_LIBRARY_PATH` entries for the
venv's cu13 libs (NVRTC for humming JIT) — handled by `serve.sh`.

- The stack is torch 2.13.0+cu13; driver 580.178.04 or newer.
- NVFP4 is officially supported by NVIDIA on Hopper/Blackwell; on Ampere it works
  via the Marlin backend plus the local patch below.
- MTP draft head is present in the checkpoint but **disabled** — it benchmarks
  slower on Ampere (see Performance).
- Tool calling needs `--enable-auto-tool-choice --tool-call-parser qwen3_coder`
  (clients sending `tool_choice: "auto"` get 400s without it).

### Local patch (not upstream yet)

Fixes vLLM issue #52434 (`'ParallelLMHead' object has no attribute
'output_partition_sizes'`, open PR #52451) for NVFP4/FP8 checkpoints with a
quantized lm_head. Shipped as a git patch:
[`patches/vllm-0.27.1-humming-utils-52434.patch`](patches/vllm-0.27.1-humming-utils-52434.patch)
— `shape_n_stacks` falls back to `output_size_per_partition` / `output_size`
via hasattr, `shape_n` falls back to `shape_n_stacks[0]`, and `has_bias` uses
`getattr(layer, "has_bias", False)`.

`Dockerfile.vllm` bakes it into the image at build time; `setup.sh` applies it
to the venv automatically. If you install/upgrade vLLM yourself, re-apply:

```bash
cd .venv/lib/python3.12/site-packages
git apply ../../patches/vllm-0.27.1-humming-utils-52434.patch
```

(Or, against a git checkout of vLLM: `git am patches/vllm-0.27.1-humming-utils-52434.patch`.)
Once PR #52451 merges upstream, the patch can be dropped.

## LiteLLM gateway

The `litellm/` compose stack runs everything at once: `vllm` (model, 2 GPUs) +
`litellm` (gateway on `:4000`) + Postgres (keys, spend, budgets) + Redis (rate
limits, cross-pod coordination). `docker compose up -d --build` brings the whole
stack up; the gateway reaches the model in-network at `http://vllm:8000/v1`.

- Config is rendered from `config.template.yaml` by `render_config.py` at container
  start (LiteLLM does not interpolate env vars in config.yaml itself)
- Apply `.env` changes: `docker compose up -d --force-recreate`
- Admin UI: http://localhost:4000/ui
- Model aliases: `qwen3.8-27b` (no thinking), plus `-low/-mid/-high/-xhigh`
  reasoning-effort variants

## Client configs

`assets/` points Claude Code and OpenCode at the gateway; both read the key/URL
from env vars (no secrets in the files). See `assets/README.md`.

- OpenCode: `OPENCODE_CONFIG=assets/opencode.json opencode`
  (uses `{env:VAR}` interpolation)
- Claude Code: `source assets/claude-code-env.sh && claude`
  (maps to `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`; LiteLLM serves the
  Anthropic Messages API)

## Performance

The serving flags (compose `vllm` service / `serve.sh`) come from a full tuning
pass in `bench/` — one directory
per experiment (MTP, prefix caching, kernel backend, scheduler, KV dtype) with raw
`llama-benchy` tables (means ± std, 2 runs) and replay commands; see
`bench/summary.md`.

Headline numbers (2x 3090, TP2, pp8192/tg256): prefill ~2500 t/s, generation
66.7 t/s (c1) / ~73 t/s (c8); long-context prefill 2757/2502/2198 t/s at
2k/8k/32k prompt. Key verdicts baked into the serving flags:

- **MTP off** — the BF16 draft head costs more than it saves on Ampere
  (−48% single-stream, −11% at c8)
- **prefix caching on** — 8x faster TTFR on cached context (16.5s → 2.1s @32k),
  zero generation penalty
- **`--max-num-batched-tokens 16384`** (2x default) — prefill +2–3%, gen flat
- humming == marlin and fp8 KV dtype: no measurable change, left at defaults

## Known caveats

- **Flaky boot:** the vLLM engine core process can die silently ~3–8s into startup
  (~1-in-6 boots succeed); no OOM/XID/core dump. Likely NVFP4-on-Ampere.
  In compose this self-heals via `restart: unless-stopped` + healthcheck;
  on the host venv: restart in a loop until UP, fallback `--enforce-eager`.
- Upgrading vLLM means rebuilding the image (`docker compose build vllm`) and
  re-checking the patch still applies (or re-running `setup.sh` for the venv).
- Model weights are ~22 GB and are downloaded once into `models/` (mounted
  read-only into the `vllm` container, never baked into the image).
