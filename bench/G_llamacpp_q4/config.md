# G2: llama.cpp GGUF UD-Q4_K_XL vs Q8_0 vs vLLM NVFP4

- Date: 2026-08-21 13:48
- Model: unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_XL.gguf (17GB, Dynamic 3.0)
- Engine: llama.cpp build 0.21.0 ggml-cuda, --ctx-size 98304 --n-gpu-layers 99 --parallel 8
- benchy: pp8192 tg256 c1 c8 --runs 2 (same E protocol)

## Results

| test      | vLLM NVFP4 (E)       | llama.cpp Q8_0       | llama.cpp UD-Q4_K_XL | Q4 vs Q8 | Q4 vs NVFP4 |
|-----------|----------------------|----------------------|----------------------|----------|-------------|
| pp8192 c1 | 2529 t/s, 3341ms     | 1672 t/s, 5324ms     | 1550 t/s, 5674ms     | -7% prefill | -39% prefill, +70% TTFT |
| tg256 c1  | 66.9 t/s             | 27.6 t/s             | 40.8 t/s             | +48% gen | -39% gen |
| pp8192 c8 | 2463 t/s, 18311ms    | 1191 t/s, 40778ms    | 1145 t/s, 42658ms    | -4% | -54% |
| tg256 c8  | 72.6 t/s             | 43.0 t/s             | 41.9 t/s             | -2% | -42% |

Q4 gen is faster than Q8 (+48% c1) but prefill is slightly slower (-7%).
Both GGUFs are ~1.6x slower prefill and ~1.6-2.4x slower gen than vLLM Marlin NVFP4.

## Verdict
No TTFT win. Dynamic Q4 does not beat Q8 on prefill and both trail NVFP4
significantly. NVFP4 + Marlin remains the serving path. GGUFs are for
llama.cpp / single-GPU desktop, not for 2x3090 vLLM TTFT.

## Replay
```bash
./llama.cpp/build/bin/llama-server --model models-gguf/Qwen3.8-27B-UD-Q4_K_XL.gguf --ctx-size 98304 --n-gpu-layers 99 --host 127.0.0.1 --port 8000 --parallel 8
.venv/bin/llama-benchy --base-url http://127.0.0.1:8000/v1 --model unsloth/Qwen3.8-27B-NVFP4 --pp 8192 --tg 256 --concurrency 1 8 --runs 2 --latency-mode generation --extra-body '{"chat_template_kwargs":{"enable_thinking":false}}' --save-result bench/G_llamacpp_q4/bench.md --format md
```
