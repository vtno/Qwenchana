# D: NVFP4 humming kernel backend (VLLM_NVFP4_GEMM_BACKEND=humming)

- Date: 2026-08-19 ~21:15
- Config: baseline except VLLM_NVFP4_GEMM_BACKEND=humming (marlin is default in serve.sh)
- benchy: pp8192 tg256 c1 c8 --runs 2
- File: bench.md

## Results (vs A baseline marlin)
- c1: pp 2503 vs 2487 t/s | tg 66.68 vs 66.73 t/s
- c8: pp 2407 vs 2385 t/s | tg 73.30 vs 72.73 t/s | peak 422 vs 421 t/s

## Verdict
Statistically identical to marlin on Ampere (+0.5%, within noise). No change;
keep marlin default (already validated).