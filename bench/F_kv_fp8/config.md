# F: kv-cache-dtype fp8

- Date: 2026-08-19 ~21:35
- Config: baseline + --kv-cache-dtype fp8
- benchy: pp8192 tg256 c1 c8 --runs 2
- File: bench.md

## Results (vs A baseline)
- c1: pp 2499 vs 2487 t/s (=) | tg 66.67 vs 66.73 (=)
- c8: pp 2412 vs 2385 t/s (=) | tg 73.42 vs 72.73 (=)
- VRAM idle: 22256 MiB/GPU -- unchanged (attention KV is a small fraction; the
  dominant state is the Gated DeltaNet recurrent cache, dtype-independent)

## Verdict
No benefit on this hybrid model. Skip (avoid fp8 KV quality risk for zero gain).