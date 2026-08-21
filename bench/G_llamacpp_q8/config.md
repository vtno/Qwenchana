# G: llama.cpp GGUF Q8_0 vs vLLM NVFP4

- Date: 2026-08-21 13:13-13:27
- Model: unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-Q8_0.gguf (26.7GB, Dynamic 3.0)
- Engine: llama.cpp build 0.21.0 ggml-cuda, --ctx-size 98304 --n-gpu-layers 99 --parallel 8
- benchy: pp8192 tg256 c1 c8 --runs 2 (same E protocol)

## Results (vs vLLM NVFP4 E baseline: watermark 0, pp8192)

| test      | vLLM NVFP4 (E)       | llama.cpp Q8_0       | delta |
|-----------|----------------------|----------------------|-------|
| pp8192 c1 | 2529 t/s, ttfr 3341ms| 1672 t/s, ttfr 5324ms| -34% prefill, +59% TTFT |
| tg256 c1  | 66.9 t/s             | 27.6 t/s             | -59% gen |
| pp8192 c8 | 2463 t/s, ttfr 18311ms| 1191 t/s, ttfr 40778ms| -52% prefill, 2.2x TTFT |
| tg256 c8  | 72.6 t/s             | 43.0 t/s             | -41% gen |

## Verdict
No win. vLLM + Marlin NVFP4 is 1.5x faster prefill and 2.4x faster gen than
llama.cpp Q8 on 2x 3090. Q8 is heavier (8-bit) than NVFP4 (4-bit) and llama.cpp
CUDA kernels are less tuned for this hybrid (Gated DeltaNet) model. Smaller
GGUFs (Q4) would be faster than Q8 but still behind Marlin.

## Replay
```bash
./llama.cpp/build/bin/llama-server --model models-gguf/Qwen3.8-27B-Q8_0.gguf --ctx-size 98304 --n-gpu-layers 99 --host 127.0.0.1 --port 8000 --parallel 8
.venv/bin/llama-benchy --base-url http://127.0.0.1:8000/v1 --model unsloth/Qwen3.8-27B-NVFP4 --pp 8192 --tg 256 --concurrency 1 8 --runs 2 --latency-mode generation --extra-body '{"chat_template_kwargs":{"enable_thinking":false}}' --save-result bench/G_llamacpp_q8/bench.md --format md
```
