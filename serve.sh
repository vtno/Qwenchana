#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$DIR/.venv"
MODEL_ID="unsloth/Qwen3.8-27B-NVFP4"

if [ ! -x "$VENV_DIR/bin/vllm" ]; then
  echo "ERROR: vLLM not installed. Run $DIR/setup.sh first." >&2
  exit 1
fi

export PATH="$VENV_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$VENV_DIR/lib/python3.12/site-packages/nvidia/cu13/lib:$VENV_DIR/lib/python3.12/site-packages/nvidia/cuda_nvrtc/lib:$VENV_DIR/lib/python3.12/site-packages/nvidia/cuda_runtime/lib:${LD_LIBRARY_PATH:-}"
export VLLM_NVFP4_GEMM_BACKEND="${VLLM_NVFP4_GEMM_BACKEND:-marlin}"
export VLLM_TEST_FORCE_FP8_MARLIN=1

exec "$VENV_DIR/bin/vllm" serve "$MODEL_ID" \
  --tensor-parallel-size 2 \
  --max-model-len 262144 \
  --reasoning-parser qwen3 \
  --enable-prefix-caching \
  --max-num-batched-tokens 16384 \
  --skip-mm-profiling \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  "$@"