#!/usr/bin/env bash
# Full quality A/B batch: w4a16 humaneval -> swap -> nvfp4 gsm8k+humaneval -> swap back.
# Run detached; final marker QUALITY-AB-DONE (or ABORT-*).
set -u
cd "$(dirname "$0")"
echo "[1/5] w4a16 humaneval_fixed $(date -u +%T)"
./quality_humaneval.sh w4a16 || true

echo "[2/5] swap to nvfp4 $(date -u +%T)"
if ! ./swap_model.sh nvfp4; then echo "ABORT-nvfp4-down"; exit 1; fi

echo "[3/5] nvfp4 gsm8k $(date -u +%T)"
./quality_gsm8k.sh nvfp4 || true
echo "[3b/5] nvfp4 humaneval_fixed $(date -u +%T)"
./quality_humaneval.sh nvfp4 || true

echo "[4/5] swap back to w4a16 $(date -u +%T)"
if ! ./swap_model.sh w4a16; then echo "ABORT-fell-back-to-nvfp4"; exit 1; fi

echo "[5/5] done $(date -u +%T)"
echo QUALITY-AB-DONE
