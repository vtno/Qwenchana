#!/usr/bin/env bash
# Humaneval A/B (fence-fixed custom task) against the CURRENTLY served model.
# Usage: ./quality_humaneval.sh <label>    (label = w4a16 | nvfp4)
set -u
cd "$(dirname "$0")"
LABEL=$1
OUT=bench/H_w4a16_autoround/quality_${LABEL}_humaneval_fixed
mkdir -p "$OUT"
OPENAI_API_KEY=EMPTY HF_ALLOW_CODE_EVAL=1 .venv/bin/lm_eval \
  --model openai-chat-completions \
  --model_args "model=unsloth/Qwen3.8-27B-NVFP4,base_url=http://127.0.0.1:8000/v1/chat/completions,num_requests_per_batch=1" \
  --include_path bench/H_w4a16_autoround/humaneval_fixed \
  --tasks humaneval_fixed \
  --limit 64 --batch_size 1 \
  --apply_chat_template \
  --confirm_run_unsafe_code \
  --log_samples \
  --output_path "$OUT" \
  --log > "$OUT/lm_eval.log" 2>&1
echo "rc=$?"
tail -4 "$OUT/lm_eval.log"
