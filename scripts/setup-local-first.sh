#!/usr/bin/env bash
# Full setup for openclaw-fork with Ollama + SearXNG (local-first, no paid APIs).
#
# Run as root or with sudo on a fresh Ubuntu 22.04+ VPS.
# This script:
#   1. Creates an "openclaw" system user (if not root/ubuntu)
#   2. Installs Node 22+, pnpm, system deps
#   3. Clones and builds openclaw-fork
#   4. Installs SearXNG (pip, systemd)
#   5. Writes the OpenClaw config for Ollama + SearXNG
#   6. Verifies connectivity
set -euo pipefail

# --- Config ---
OPENCLAW_USER="${OPENCLAW_USER:-openclaw}"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"
FORK_REPO="${FORK_REPO:-https://github.com/nexusjuan12/openclaw-fork.git}"
FORK_DIR="${OPENCLAW_HOME}/openclaw-fork"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3-16k}"
OLLAMA_BASE_MODEL="${OLLAMA_BASE_MODEL:-qwen3:14b}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-nomic-embed-text}"
SEARXNG_PORT="${SEARXNG_PORT:-8888}"

echo "=== OpenClaw Local-First Setup ==="
echo "    User:         ${OPENCLAW_USER}"
echo "    Fork:         ${FORK_REPO}"
echo "    Ollama:       ${OLLAMA_HOST}:${OLLAMA_PORT}"
echo "    Model:        ${OLLAMA_MODEL}"
echo "    Embeddings:   ${EMBEDDING_MODEL}"
echo "    SearXNG port: ${SEARXNG_PORT}"
echo ""

# --- Step 1: Create user ---
if ! id -u "${OPENCLAW_USER}" &>/dev/null; then
  echo "==> Creating user: ${OPENCLAW_USER}"
  adduser --disabled-password --gecos "OpenClaw" "${OPENCLAW_USER}"
  echo "==> Set a password for ${OPENCLAW_USER}:"
  passwd "${OPENCLAW_USER}"
  usermod -aG sudo "${OPENCLAW_USER}"
fi

# --- Step 2: System deps ---
echo "==> Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq curl git build-essential python3 python3-venv python3-pip \
  libxml2-dev libxslt1-dev zlib1g-dev libffi-dev libssl-dev > /dev/null

# Node 22+ via NodeSource
if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]]; then
  echo "==> Installing Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
  apt-get install -y -qq nodejs > /dev/null
fi

# pnpm
if ! command -v pnpm &>/dev/null; then
  echo "==> Installing pnpm..."
  npm install -g pnpm > /dev/null 2>&1
fi

echo "    Node: $(node -v), pnpm: $(pnpm -v)"

# --- Step 3: Clone and build ---
echo "==> Cloning openclaw-fork..."
if [ ! -d "${FORK_DIR}" ]; then
  sudo -u "${OPENCLAW_USER}" git clone "${FORK_REPO}" "${FORK_DIR}"
else
  echo "    ${FORK_DIR} already exists, pulling latest..."
  sudo -u "${OPENCLAW_USER}" git -C "${FORK_DIR}" pull --rebase
fi

echo "==> Installing dependencies and building..."
sudo -u "${OPENCLAW_USER}" bash -c "cd ${FORK_DIR} && pnpm install && pnpm build"

# --- Step 4: SearXNG ---
echo "==> Installing SearXNG..."
SEARXNG_PORT="${SEARXNG_PORT}" bash "${FORK_DIR}/scripts/install-searxng.sh"

# --- Step 5: OpenClaw config ---
OPENCLAW_CONFIG_DIR="${OPENCLAW_HOME}/.openclaw"
mkdir -p "${OPENCLAW_CONFIG_DIR}"

cat > "${OPENCLAW_CONFIG_DIR}/openclaw.json" <<CONFIG
{
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://${OLLAMA_HOST}:${OLLAMA_PORT}/v1",
        "apiKey": "ollama-local",
        "api": "openai-completions",
        "models": [
          {
            "id": "${OLLAMA_MODEL}",
            "name": "Qwen3 14B (16K)",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 16384,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "ollama/${OLLAMA_MODEL}" },
      "memorySearch": {
        "enabled": false
      }
    }
  },
  "tools": {
    "web": {
      "search": {
        "provider": "searxng",
        "searxng": {
          "baseUrl": "http://127.0.0.1:${SEARXNG_PORT}"
        }
      }
    }
  }
}
CONFIG

chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_CONFIG_DIR}"

# Add OLLAMA_API_KEY to profile
PROFILE="${OPENCLAW_HOME}/.profile"
if ! grep -q "OLLAMA_API_KEY" "${PROFILE}" 2>/dev/null; then
  echo 'export OLLAMA_API_KEY="ollama-local"' >> "${PROFILE}"
  chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${PROFILE}"
fi

# --- Step 6: Verify ---
echo ""
echo "=== Verification ==="

# SearXNG
if curl -sf "http://127.0.0.1:${SEARXNG_PORT}/search?q=test&format=json" > /dev/null 2>&1; then
  echo "[OK] SearXNG running on port ${SEARXNG_PORT}"
else
  echo "[!!] SearXNG not responding. Check: systemctl status searxng"
fi

# Ollama (may not be available if tunnel isn't up yet)
if curl -sf "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/tags" > /dev/null 2>&1; then
  echo "[OK] Ollama reachable at ${OLLAMA_HOST}:${OLLAMA_PORT}"
else
  echo "[--] Ollama not reachable (tunnel may not be up yet)"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. On your GPU machine, pull base model and create custom 16K model:"
echo "       ollama pull ${OLLAMA_BASE_MODEL}"
echo "       ollama pull ${EMBEDDING_MODEL}"
echo ""
echo "       # Create Modelfile for 16K context:"
echo "       cat > Modelfile <<EOF"
echo "FROM ${OLLAMA_BASE_MODEL}"
echo "PARAMETER num_ctx 16384"
echo "EOF"
echo "       ollama create ${OLLAMA_MODEL} -f Modelfile"
echo ""
echo "  2. Start the reverse tunnel (from GPU machine):"
echo "       ssh -N -R ${OLLAMA_PORT}:localhost:${OLLAMA_PORT} ${OPENCLAW_USER}@$(hostname -I | awk '{print $1}')"
echo "       # Or with autossh for persistence:"
echo "       autossh -M 0 -N -R ${OLLAMA_PORT}:localhost:${OLLAMA_PORT} ${OPENCLAW_USER}@$(hostname -I | awk '{print $1}')"
echo ""
echo "  3. Switch to the openclaw user and start the gateway:"
echo "       su - ${OPENCLAW_USER}"
echo "       cd ${FORK_DIR}"
echo "       pnpm openclaw models list"
echo "       pnpm openclaw gateway run --bind lan --port 18789"
echo ""
echo "  4. Access web UI:"
echo "       http://$(hostname -I | awk '{print $1}'):18789/chat?session=main"
echo ""
