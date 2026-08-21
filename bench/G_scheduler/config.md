# G: scheduler knob (--watermark 0.03, default 0.0)

- Date: 2026-08-21 12:46-12:51
- Config: baseline + `--watermark 0.03` (3% KV headroom to avoid eviction thrashing)
- benchy: `pp8192 tg256 c1 c8 --runs 2` (same E protocol)
- File: bench_watermark03.md
- Note: `async_scheduling` already ON by default in 0.27.1 (no knob to test);
  `long_prefill_token_threshold` (default 0=disabled) caps per-step prefill and
  would hurt TTFT, not relevant here.

## Results (vs E baseline: --max-num-batched-tokens 16384)

| test        | E (watermark 0)          | G (watermark 0.03)       | delta |
|-------------|--------------------------|--------------------------|-------|
| pp8192 c1   | 2529.24 ±0.94 t/s         | 2528.38 ±3.05 t/s         | -0.0% |
| ttfr c1     | 3355 ±4 ms               | 3355 ±4 ms               | flat  |
| tg256 c1    | 66.88 ±0.08 t/s          | 66.49 ±0.03 t/s          | -0.6% |
| pp8192 c8   | 2462.75 ±10.65 t/s        | 2448.03 ±9.67 t/s         | -0.6% |
| ttfr c8     | 18311 ±7764 ms           | 20467 ±7801 ms           | +11% (within variance) |
| tg256 c8    | 72.56 ±0.24 t/s          | 72.22 ±0.24 t/s          | -0.5% |

c8 ttfr variance remains ~7.8s in both configs (preemption/eviction dynamics).
Watermark reserves 3% of KV (~0.12 GiB/GPU) and slightly reduces effective KV,
hurting concurrent prefill on this 262k, 98%-VRAM box.

## Verdict
No win. Keep `watermark 0` (default). The host is KV-tight at 262144;
reserving headroom does not stabilize TTFR here. No further watermark values
tested.

## Replay
```bash
./serve.sh --watermark 0.03
.venv/bin/llama-benchy --base-url http://127.0.0.1:8000/v1 --model unsloth/Qwen3.8-27B-NVFP4 --pp 8192 --tg 256 --concurrency 1 8 --runs 2 --latency-mode generation --extra-body '{"chat_template_kwargs":{"enable_thinking":false}}' --save-result bench/G_scheduler/bench_watermark03.md --format md
```
