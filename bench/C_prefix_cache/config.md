# C: prefix caching (--enable-prefix-caching)

- Date: 2026-08-19 ~21:10
- Config: baseline + `--enable-prefix-caching`
- benchy: pp2048 tg128 depth 8192 32768 --enable-prefix-caching (2-stage ctx load + inference)
- File: bench.md

## Results
- ctx_pp (cache fill): 2459 t/s @8k, 2131 t/s @32k (one-time cost per unique context)
- pp2048 @ d8192: TTFR 1115ms vs A 4335ms  (cache hit: only 2048 fresh tokens processed)
- pp2048 @ d32768: TTFR 2069ms vs A 16501ms (cache hit)
- tg: 64-66.8 t/s -- NO throughput penalty vs baseline

## Verdict
RECOMMEND ENABLING. Recurring context (system prompts, RAG) gets 2-8x faster TTFR
with zero generation penalty. Cost: slight extra VRAM for cached blocks.