#!/usr/bin/env bash
# Remote runner for Qwenchana — no clone, no install. Temp dir cleaned up after.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/vtno/Qwenchana/main/run.sh | bash -s -- run claude
#   curl -fsSL https://raw.githubusercontent.com/vtno/Qwenchana/main/run.sh | bash -s -- install opencode
set -euo pipefail

RAW="https://raw.githubusercontent.com/vtno/Qwenchana/main"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

mkdir "$D/assets"
curl -fsSL "$RAW/qcn" -o "$D/qcn"
for f in opencode.json claude-code-env.sh; do
  curl -fsSL "$RAW/assets/$f" -o "$D/assets/$f"
done

bash "$D/qcn" "$@"
