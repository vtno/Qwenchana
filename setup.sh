#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$DIR/models"
VENV_DIR="$DIR/.venv"
MODEL_ID="unsloth/Qwen3.8-27B-NVFP4"

echo "==> Creating virtualenv at $VENV_DIR"
python3 -m venv "$VENV_DIR"

echo "==> Activating venv and upgrading pip"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel

echo "==> Installing vLLM (pinned: matches the humming patch and the Docker image)"
pip install "vllm==0.27.1"

echo "==> Installing huggingface_hub CLI"
pip install -U "huggingface_hub[cli]"

# Resolve the venv site-packages dir (python minor version may vary)
SITE_PACKAGES="$("$VENV_DIR/bin/python" -c 'import site; print(site.getsitepackages()[0])')"
VLLM_PATCH="$DIR/patches/vllm-0.27.1-humming-utils-52434.patch"

if [ -f "$VLLM_PATCH" ]; then
  echo "==> Applying vLLM humming patch (vLLM #52434)"
  # cd + git apply: `git apply --directory` rejects absolute prefixes on git 2.34
  if (cd "$SITE_PACKAGES" && git apply --check "$VLLM_PATCH") 2>/dev/null; then
    (cd "$SITE_PACKAGES" && git apply "$VLLM_PATCH")
    echo "    Patch applied."
  else
    echo "    WARNING: patch did not apply cleanly to this vLLM version."
    echo "    It targets vLLM 0.27.1; a newer/older vllm may have changed"
    echo "    humming_utils.py or already fixed #52434. If serving fails with"
    echo "    \"'ParallelLMHead' object has no attribute 'output_partition_sizes'\","
    echo "    apply it manually or pin vllm==0.27.1."
  fi
fi

# pinned to a revision so the weights can't silently change out from under us
HF_MODEL_REVISION="7d6f8d4d72f56b92b3cdbf22f156b90e1bab0108"

echo "==> Downloading $MODEL_ID (revision $HF_MODEL_REVISION) into $MODEL_DIR"
hf download "$MODEL_ID" --revision "$HF_MODEL_REVISION" --local-dir "$MODEL_DIR"

echo "==> Done."
echo "    To serve:"
echo "      $VENV_DIR/bin/vllm serve $MODEL_ID --tensor-parallel-size 2 --max-model-len 262144 --reasoning-parser qwen3"
echo "    (or run $DIR/serve.sh)"