# Final verdict: Qwen3.8-27B-NVFP4 on 2x RTX 3090 (vLLM 0.27.1)

Date: 2026-08-19 | Stack: vLLM 0.27.1 (cu13), torch 2.13.0, driver 580.178.04,
NVFP4 via Marlin, TP=2, 256k context, MTP weights present but disabled.

## Verdict
- **Keep MTP OFF.** The BF16 draft head on Ampere costs more than it saves:
  66.7 -> 34.5 t/s single-stream (-48%), 72.7 -> 64.9 t/s at c8 (-11%).
- **Enable prefix caching.** 8x faster TTFR on cached context (16.5s -> 2.1s @32k
  depth), zero generation penalty.
- **max-num-batched-tokens 16384** (2x default): prefill +2-3% at concurrency, gen
  flat. 32768 does not fit (KV cache drops below 262144-token requirement).
- **Kernel backend and KV dtype: no change.** humming == marlin on Ampere; fp8 KV
  changes nothing on this hybrid model (state is Gated DeltaNet, not attention KV).
- **Scheduler watermark 0.03: no win.** c1 flat, c8 TTFR +11% within variance; keep default 0.

## Final serving numbers (pp8192/tg256)
| metric | c1 | c8 |
|---|---:|---:|
| prefill | ~2500 t/s | ~2400 t/s |
| generation | 66.7 t/s | 72.7-73.4 t/s |
| gen peak (per req) | 68 t/s | ~53 t/s |

Long-context (pp sweep, tg128): prefill 2757 (2k) / 2502 (8k) / 2198 (32k) t/s;
generation 67.8 / 66.3 / 63.7 t/s @ depth 0 / 8k / 32k. TTFR 0.86s @2k, 15.0s @32k.

## Final config (live in serve.sh)
```
--tensor-parallel-size 2 --max-model-len 262144 --reasoning-parser qwen3
--enable-prefix-caching --max-num-batched-tokens 16384 --skip-mm-profiling
--enable-auto-tool-choice --tool-call-parser qwen3_coder
Env: VLLM_NVFP4_GEMM_BACKEND=marlin, VLLM_TEST_FORCE_FP8_MARLIN=1
```
Load ~22.25 GB/GPU (of 24), GPUs ~98% utilized under load. Hardware is the ceiling.

## Known caveats
- Local humming_utils.py patches ([vLLM #52434](https://github.com/vllm-project/vllm/issues/52434)) lost on vllm upgrade; re-apply.
- MTP enable requires `num_speculative_tokens:1` (config lacks mtp_num_hidden_layers).
- Thinking enabled by default; disable per request via
  `chat_template_kwargs: {"enable_thinking": false}`.

## Tool calling
- opencode sends `tool_choice: "auto"` -> vLLM 400s unless started with
  `--enable-auto-tool-choice --tool-call-parser qwen3_coder`.
- `qwen3_coder` (Qwen3EngineToolParser) parses Qwen3.5's `<tool_call>` XML
  format via `vllm/parser/qwen3.py`; xlam/granite parsers do NOT match.

## Flaky boot (open issue)
- EngineCore parent dies SILENTLY 3-8s into the startup profile/dummy forward
  (~40s after weight load, after `--skip-mm-profiling` skip line). No traceback,
  no OOM/XID/ECC, no core dump; workers log "Parent process exited".
- Intermittent ~1-in-6 boots succeed; NOT tied to tool flags (baseline crashes
  too) nor to caches (cleared compile/flashinfer/torch caches, still crashes).
- Likely NVFP4-on-Ampere: NVIDIA officially supports NVFP4 on Hopper/Blackwell
  only; 3090s need Marlin backend + patched humming_kernels. No matching public
  issue found (closest: vLLM #39915 TP=2 silent parent exit at NCCL init,
  closed "not planned").
- Recovery: `../boot_retry.sh` (local-only script, gitignored) restarts serve.sh up to 10x until UP
  (background, setsid detached). Fallback if it never boots: `--enforce-eager`.

## opencode variants integration
- Configured in `~/.config/opencode/opencode.json`: single model
  `litellm/qwen3.8-27b` (reasoning true, `interleaved: "reasoning_content"`,
  limit 262144/65536) with variants passing `chat_template_kwargs`:
  - `fast`: `{"enable_thinking": false}`
  - `low` / `mid` / `high` / `xhigh`: `{"reasoning_effort": ...}`
- Chat template supports `xhigh`, `medium`, `low` only; `high` is auto-aliased
  to `xhigh` (so `high` and `xhigh` are behaviorally identical).
- Gateway aliases: `qwen3.8-27b` (fast), `-low`, `-mid`, `-high`, `-xhigh`.
- Gateway now auth-enabled (Postgres + LITELLM_MASTER_KEY in .env); opencode
  provider sends `apiKey`. UI login: http://localhost:4000/ui.
- opencode handles variants NATIVELY for openai-compatible providers — no
  plugin needed. `LLMRequestPrep.prepare` merges active variant options into
  AI SDK `providerOptions`; the openai-compatible transformer copies the whole
  options object into the request body and maps `reasoningEffort` ->
  `reasoning_effort`. Arbitrary keys (e.g. `chat_template_kwargs`) pass through.
- SDK type `variants?: { [key: string]: { disabled?; [key: string]: unknown } }`
  allows arbitrary option keys (opencode.ai/config.json schema only showing
  `disabled` is stale).
- Verified 2026-08-20 end to end: `opencode run -m litellm/qwen3.8-27b
  --variant fast` -> no reasoning; `--variant thinking` -> `reasoning_content`
  present; no 400s.

## Gateway
LiteLLM proxy in `../litellm/` (docker compose, port 4000, restart=unless-stopped):
- Config via `litellm/.env`: LITELLM_MODEL_NAME (alias), VLLM_MODEL_ID (backend id),
  VLLM_BASE_URL, VLLM_API_KEY, LITELLM_PORT, LITELLM_IMAGE
- config.template.yaml rendered at container start by render_config.py (LiteLLM does
  NOT interpolate env vars in config.yaml itself)
- Apply .env changes: `docker compose up -d --force-recreate` (in ../litellm/)
- Verified 2026-08-19: chat completion through :4000 works end to end
- Aliases (fast / thinking / thinking-medium / thinking-low) used by opencode;
  aliases must differ from backend model ID. Apply .env changes:
  `docker compose up -d --force-recreate`.

## Evidence
See per-experiment dirs: A_baseline/ B_mtp_on/ C_prefix_cache/ D_humming_kernel/
E_scheduler/ F_kv_fp8/ + this README for the full back-trace.