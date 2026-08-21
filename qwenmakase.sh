#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="$DIR/litellm/.env"
ENV_EXAMPLE="$DIR/litellm/.env.example"
MODEL_DIR="$DIR/models"
MODEL_ID="unsloth/Qwen3.8-27B-NVFP4"
MODEL_REV="7d6f8d4d72f56b92b3cdbf22f156b90e1bab0108"

# ---------- helpers ----------
die()  { printf "\033[31mError: %s\033[0m\n" "$1" >&2; exit 1; }
info() { printf "\033[36m==> %s\033[0m\n" "$1"; }
ok()   { printf "\033[32m    %s\033[0m\n" "$1"; }

random_hex() { openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# ---------- pre-flight ----------
command -v docker >/dev/null || die "docker is not installed"
docker info --format '{{.Driver}}' >/dev/null 2>&1 || die "docker daemon is not running (or no permission)"

# nvidia runtime? (soft check)
if ! docker info 2>/dev/null | grep -qi nvidia; then
  printf "\033[33mWarning: nvidia container runtime not detected. The vllm service will fail without GPU support.\033[0m\n"
  read -rp "Continue anyway? [y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 1
fi

# ---------- 1. models ----------
if [ -f "$MODEL_DIR/config.json" ]; then
  ok "Models already present at $MODEL_DIR"
else
  info "Model weights (~22 GB) not found at $MODEL_DIR"
  read -rp "Download now? (requires huggingface_hub) [Y/n] " yn
  yn="${yn:-Y}"
  if [[ ! "$yn" =~ ^[Nn]$ ]]; then
    if ! command -v hf >/dev/null 2>&1; then
      info "Installing huggingface_hub CLI..."
      pip install -U "huggingface_hub[cli]"
    fi
    info "Downloading $MODEL_ID (revision ${MODEL_REV:0:8})..."
    hf download "$MODEL_ID" --revision "$MODEL_REV" --local-dir "$MODEL_DIR"
    ok "Download complete."
  else
    die "Cannot start vLLM without model weights. Run manually:\n  hf download $MODEL_ID --revision $MODEL_REV --local-dir $MODEL_DIR"
  fi
fi

# ---------- 2. env ----------
if [ ! -f "$ENV" ]; then
  info "Creating litellm/.env from template..."
  cp "$ENV_EXAMPLE" "$ENV"

  # --- master key ---
  KEY_DEFAULT=$(random_hex)
  printf "  LITELLM_MASTER_KEY (gateway API key) [%s]: " "$KEY_DEFAULT" >&2
  read -r KEY_INPUT
  KEY_INPUT="${KEY_INPUT:-$KEY_DEFAULT}"
  sed -i "s/^LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY=$KEY_INPUT/" "$ENV"
  ok "LITELLM_MASTER_KEY=$KEY_INPUT"

  # --- admin UI ---
  UI_USER_DEFAULT="${USER:-admin}"
  printf "  UI_USERNAME (admin panel) [%s]: " "$UI_USER_DEFAULT" >&2
  read -r UI_USER
  UI_USER="${UI_USER:-$UI_USER_DEFAULT}"
  sed -i "s/^UI_USERNAME=.*/UI_USERNAME=$UI_USER/" "$ENV"

  UI_PASS_DEFAULT=$(random_hex)
  printf "  UI_PASSWORD (admin panel) [%s]: " "$UI_PASS_DEFAULT" >&2
  read -r UI_PASS
  UI_PASS="${UI_PASS:-$UI_PASS_DEFAULT}"
  sed -i "s/^UI_PASSWORD=.*/UI_PASSWORD=$UI_PASS/" "$ENV"
  ok "UI_USERNAME=$UI_USER  UI_PASSWORD=$UI_PASS"

  ok "litellm/.env ready."
else
  ok "litellm/.env already exists."
fi

# ---------- 3. start stack ----------
info "Starting stack (docker compose up -d --build)..."
cd "$DIR"
docker compose up -d --build

# ---------- 4. wait for vllm ----------
info "Waiting for vllm to become healthy (typically 4-8 min; up to ~20 min on a flaky boot)..."
HEALTHY=false
for i in $(seq 1 60); do
  STATUS=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' qwen38-vllm 2>/dev/null || echo "missing")
  if [ "$STATUS" = "healthy" ]; then
    HEALTHY=true
    break
  fi
  if [ "$STATUS" = "missing" ]; then
    printf "\r  [%4ds] vllm container not found - check docker ps   " "$((i*20))"
  else
    printf "\r  [%4ds] %s   " "$((i*20))" "$STATUS"
  fi
  sleep 20
done
echo ""

if [ "$HEALTHY" = true ]; then
  ok "vllm is healthy!"
else
  printf "\033[33mWarning: vllm did not become healthy within 20 minutes.\033[0m\n"
  printf "  Check logs: docker logs qwen38-vllm --tail 20\n"
  printf "  The container will keep restarting; try again in a few minutes.\n"
fi

# ---------- 5. summary ----------
KEY=$(grep '^LITELLM_MASTER_KEY=' "$ENV" | cut -d= -f2-)

echo ""
echo "=========================================="
echo " Qwenmakase is running!"
echo "=========================================="
echo ""
echo "  vLLM API (direct, no auth):  http://127.0.0.1:8000/v1"
echo "  Gateway (auth + rate limits): http://localhost:4000/v1"
echo "  Admin UI:                     http://localhost:4000/ui"
echo ""
echo "  LITELLM_BASE_URL=http://localhost:4000"
echo "  LITELLM_API_KEY=$KEY"
echo ""
echo "Connect a client:"
echo "  OPENCODE_CONFIG=assets/opencode.json opencode"
echo "  source assets/claude-code-env.sh && claude"
echo ""
