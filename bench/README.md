# Benchmark back-trace log

## Baseline config (A: MTP OFF)
- Date: 2026-08-19 19:36-19:54
- Hardware: 2x RTX 3090 (24GB), driver 580.178.04, CUDA 12.9 toolchain
- vLLM 0.27.1 (pip, cu13), torch 2.13.0+cu13, llama-benchy 0.4.0
- Model: unsloth/Qwen3.8-27B-NVFP4 (NVFP4; MTP head weights present but NOT used)
- Serve args: --tensor-parallel-size 2 --max-model-len 262144 --reasoning-parser qwen3
- Env: VLLM_NVFP4_GEMM_BACKEND=marlin, VLLM_TEST_FORCE_FP8_MARLIN=1
- Patches: local humming_utils.py fixes (see ../README.md) - vLLM issue #52434
- KV: 22.25 GB/GPU used at idle (gpu-memory-utilization default 0.90)
- GPU util during load: 98-100% both GPUs
- IMPORTANT: engine log shows speculative_config=None => speculative decoding (MTP) was OFF in baseline
- Other engine defaults seen in log: enable_prefix_caching=False, enable_chunked_prefill=True,
  compilation_mode=VLLM_COMPILE (inductor + cudagraph FULL_AND_PIECEWISE, capture sizes 1..512)

## Results
- bench_pp.md: pp sweep (pp 2048/8192/32768, tg 128, depth 0/8192/32768)
  - prefill: 2757 / 2502 / 2198 t/s (depth 0); 1883 t/s @ d32768+pp32768
  - gen: 67.8 / 66.3 / 63.7 t/s @ depth 0/8k/32k
- bench_conc.md: concurrency sweep (pp8192 tg256, c 1/4/8/16)
  - prefill total: 2487 / 2422 / 2385 / 2365 t/s
  - gen total: 66.7 / 74.2 / 72.7 / 72.3 t/s  (ceiling ~74)
  - gen peak/req: 68 / 232 / 421 / 752 t/s
  - TTFR: 3.4 / 9.1 / 16.2 / 30.1 s
- gpu_sweep.log (local-only, gitignored): GPU0/GPU1 util + mem during conc sweep

## A/B experiments
- [x] A: MTP OFF (baseline, A_baseline/ (bench_pp.md + bench_conc.md + gpu_sweep.log, last one local-only))
      speculative_config=None in engine log; model_mtp.safetensors loaded only as checkpoint file
- [x] B: MTP ON --speculative-config '{"method":"qwen3_5_mtp","num_speculative_tokens":1}'
      (num_speculative_tokens REQUIRED: config lacks mtp_num_hidden_layers so n_predict=None;
       MTP module in model_mtp.safetensors has 1 layer (mtp.layers.0, 15 tensors))
      Result (B_mtp_on/ (bench_conc_mtp_on.md + bench_single_mtp_on.md)): MTP IS SLOWER - REJECTED
      - c8 tg256: 64.9 t/s total vs 72.7 (MTP OFF)  (-11%)
      - c1 tg128: 34.5 t/s vs 66.7 (MTP OFF)       (-48%)
      - c1 pp8192: 1949 t/s vs 2487 (MTP OFF)
      Cause: BF16 draft head on Ampere costs more than acceptance saves; NVFP4-Marlin
      main weights already fast. Server restored to MTP OFF (2026-08-19 ~21:05).
- [x] C: prefix caching --enable-prefix-caching -- RECOMMEND ENABLED (C_prefix_cache/)
      TTFR @ d32768: 2069ms vs 16501ms (cache hit); tg unchanged 64-66 t/s
- [x] D: VLLM_NVFP4_GEMM_BACKEND=humming -- identical to marlin (D_humming_kernel/) - SKIP
- [x] E: --max-num-batched-tokens 16384 -- prefill +2-3%, gen flat (E_scheduler/) - ADOPTED
      (32768 fails: KV cache too small for 262144 max len)
- [x] F: --kv-cache-dtype fp8 -- no change, no VRAM saving on hybrid (F_kv_fp8/) - SKIP

## Final config (baked into serve.sh, live since 2026-08-19 ~21:45)
  --tensor-parallel-size 2 --max-model-len 262144 --reasoning-parser qwen3
  --enable-prefix-caching --max-num-batched-tokens 16384
  Env: VLLM_NVFP4_GEMM_BACKEND=marlin (override with VLLM_NVFP4_GEMM_BACKEND=humming)

## vLLM 0.27.1 tunable flags (serve --help=<group>)
- SchedulerConfig: --enable-chunked-prefill (default on), --max-num-batched-tokens (8192),
  --max-num-seqs (256), --max-num-scheduled-tokens, --long-prefill-token-threshold,
  --prefill-schedule-interval, --scheduling-policy
- CacheConfig: --gpu-memory-utilization (0.90), --block-size, --enable-prefix-caching (off),
  --kv-cache-dtype {auto,bfloat16,float16,fp8,...,nvfp4}, --kv-cache-memory-bytes,
  --kv-offloading-backend {lmcache,native}
- Speculative: --speculative-config/-sc (JSON: method, num_speculative_tokens, model), legacy
  --spec-method/--spec-model/--spec-tokens
- ModelConfig: --runner {auto,draft,generate,pooling}

## Replay commands
- pp sweep:  .venv/bin/llama-benchy --base-url http://localhost:8000/v1 --model unsloth/Qwen3.8-27B-NVFP4 --pp 2048 8192 32768 --tg 128 --depth 0 8192 32768 --runs 2 --latency-mode generation --extra-body '{"chat_template_kwargs":{"enable_thinking":false}}' --save-result bench_pp.md --format md
- conc sweep: .venv/bin/llama-benchy --base-url http://localhost:8000/v1 --model unsloth/Qwen3.8-27B-NVFP4 --pp 8192 --tg 256 --concurrency 1 4 8 16 --runs 2 --latency-mode generation --extra-body '{"chat_template_kwargs":{"enable_thinking":false}}' --save-result bench_conc.md --format md