# H: W4A16 INT4 (RedHatAI/Qwen3.8-27B-INT4) vs A: NVFP4 baseline

- Date: 2026-08-22 15:46-16:05 (pp sweep 15:46, conc sweep 15:54)
- Hardware: 2x RTX 3090 (24GB), driver 580.178.04 — same box as A
- vLLM 0.27.1 (same image as A), llama-benchy 0.4.0
- Model: RedHatAI/Qwen3.8-27B-INT4 — compressed-tensors W4A16 (INT4 G128,
  GPTQ + AWQ smoothing; visual, lm_head, embed_tokens kept BF16). 19.5GB total
  (~9.7 GB/GPU weights vs ~11.7 GB/GPU for NVFP4). MTP head present (0.85GB), unused.
- Kernel: `MarlinLinearKernel for CompressedTensorsWNA16` on both TP workers
  (single-level INT4 dequant; the NVFP4 env var/patch path is not involved)
- Serve args: identical to A's final config (compose): TP2, 262144 ctx,
  reasoning-parser qwen3, prefix caching, max-num-batched-tokens 16384,
  skip-mm-profiling, tool-call-parser qwen3_coder
- served-model-name still `unsloth/Qwen3.8-27B-NVFP4` (label only, unchanged)
- Memory: idle 23.4GB/GPU; available KV cache 9.83 GiB/GPU (A: 22.25 GB/GPU idle)

## Results vs A (NVFP4)

pp sweep (tg128):

| pp | prefill A | prefill H | gen A | gen H | delta gen |
|---:|---:|---:|---:|---:|---:|
| 2048 (d0) | 2757 | 2562 | 67.8 | 78.1 | +15% |
| 8192 (d0) | 2502 | 2440 | 66.3 | 76.0 | +15% |
| 32768 (d0) | 2198 | 2185 | 63.7 | 69.3 | +9% |
| 8192 (d8k) | - | 2320 | ~66 | 73.2 | +13% |
| 32768 (d32k) | - | 1925 | ~64 | 63.4 | ~flat |

conc sweep (pp8192/tg256):

| metric | A c1 | H c1 | A c8 | H c8 | A c16 | H c16 |
|---|---:|---:|---:|---:|---:|---:|
| prefill t/s | 2487 | 2416 | 2385 | 2385 | 2365 | 2387 |
| gen total t/s | 66.7 | 75.5 | 72.7 | 71.2 | 72.3 | 71.6 |
| gen peak/req t/s | 68 | 77 | 421 | 446 | 752 | 751 |
| TTFR s | 3.4 | 3.5 | 16.2 | 21.1 | 30.1 | 37.2 |

## Verdict

- **c1 (interactive) generation: +13%** (66.7 -> 75.5 t/s) — the smaller weight
  footprint pays off in decode, exactly as expected (1/4-byte weights, Marlin).
- Prefill: -0.5..-7% (compute-bound; INT4 dequant overhead on long sequences).
- c4+ total throughput: -1..-4% (flat within variance); per-request peaks slightly up.
- **TTFR degrades with concurrency: c4 +21% (9.1->11.0s), c8 +30% (16.2->21.1s),
  c16 +24% (30.1->37.2s)** while prefill throughput is identical — CONFIRMED
  reproducible (rerun: bench_conc_rerun.md, 21.10s vs 21.13s @ c8), mechanism
  unexplained (candidate: more KV headroom -> scheduler packs more co-existing
  prefill/decode work per step). Does not affect c1 (TTFR 3.4 vs 3.5s).
- Accuracy pass (gsm8k/mt-bench) still pending before making W4A16 the default.
- Rollback to NVFP4: `mv models models-w4a16 && mv models-nvfp4 models && docker compose up -d vllm --force-recreate`

## Quality A/B (2026-08-22, lm-eval 0.4.12, openai-chat-completions, greedy, limit 64/task)

| task | metric | W4A16 | NVFP4 | delta |
|---|---|---:|---:|---|
| gsm8k (5-shot) | exact_match flexible-extract | 0.5625 ±0.0625 | 0.5781 ±0.0622 | -1.6pt (noise) |
| gsm8k (5-shot) | exact_match strict-match | 0.4844 ±0.0630 | 0.5000 ±0.0630 | -1.6pt (noise) |
| humaneval | pass@1 (custom fence-fixed task) | 0.7344 ±0.0556 | 0.6875 ±0.0584 | +4.7pt (noise, favors W4A16) |

Two harness fixes were required for humaneval (both models measured identically):
1. lm_eval's default stop list contains "\ndef" which collides with chat-mode
   signature restating -> null/empty responses (bogus 0.0)
2. upstream build_predictions appends raw responses to prompt; Qwen3.8 wraps
   code in ```python fences -> SyntaxError on every sample.
   Custom task in `humaneval_fixed/` strips fences + disables stops.

Absolute numbers are not comparable to Intel's published lmeval-hf table
(different prompt path); checkpoint-vs-checkpoint A/B is valid.
**Verdict: no degradation -> W4A16 adopted as default (2026-08-22).**

Files: bench_pp.md, bench_conc.md, bench_conc_rerun.md, quality_w4a16*/,
quality_nvfp4_gsm8k/, quality_nvfp4_humaneval_fixed/ (llama-benchy 0.4.0 +
lm-eval 0.4.12, same replay commands as A)
