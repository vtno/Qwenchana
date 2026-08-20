# E: scheduler knob (--max-num-batched-tokens 16384, default 8192)

- Date: 2026-08-19 ~21:25
- Config: baseline + --max-num-batched-tokens 16384
- benchy: pp8192 tg256 c1 c8 --runs 2
- File: bench.md

## Results (vs A baseline)
- c1: pp 2529 vs 2487 t/s (+1.7%) | tg 66.88 vs 66.73 (=)
- c8: pp 2463 vs 2385 t/s (+3.3%) | tg 72.56 vs 72.73 (=-0.2%)

## Notes
- 32768 FAILED to start: KV cache dropped to 3.16 GiB < 4.09 GiB required for
  max_model_len 262144 (estimated max len 202272). Bigger batched-token budget
  consumes KV memory. 16384 is the sweet spot for this model+VRAM.
- gen throughput unaffected; prefill +2-3% at concurrency.

## Verdict
Minor prefill win at 16384; adopt if prefill-heavy (many concurrent long prompts),
harmless otherwise.