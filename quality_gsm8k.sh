#!/usr/bin/env bash
# gsm8k A/B against the CURRENTLY served model (standard lm_eval stops).
# Usage: ./quality_gsm8k.sh <label>    (label = w4a16 | nvfp4)
set -u
cd "$(dirname "$0")"
LABEL=$1
OUT=bench/H_w4a16_autoround/quality_${LABEL}_gsm8k
mkdir -p "$OUT"
OPENAI_API_KEY=EMPTY .venv/bin/lm_eval \
  --model openai-chat-completions \
  --model_args "model=unsloth/Qwen3.8-27B-NVFP4,base_url=http://127.0.0.1:8000/v1/chat/completions,num_requests_per_batch=1" \
  --tasks gsm8k \
  --limit 64 --batch_size 1 \
  --apply_chat_template \
  --log_samples \
  --output_path "$OUT" \
  --log > "$OUT/lm_eval.log" 2>&1
echo "rc=$?"
tail -4 "$OUT/lm_eval.log"
