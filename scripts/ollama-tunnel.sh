#!/usr/bin/env bash
# Reverse SSH tunnel: forward local Ollama to this VPS.
#
# Run this on the VPS to expose the remote Ollama instance at localhost:11434.
# Requires SSH access to the machine running Ollama.
#
# Usage:
#   ./scripts/ollama-tunnel.sh user@ollama-host
#   OLLAMA_PORT=11434 ./scripts/ollama-tunnel.sh user@ollama-host
#
# The tunnel keeps running until you Ctrl-C or the SSH connection drops.
# For persistent tunnels, consider autossh:
#   sudo apt install autossh
#   autossh -M 0 -N -R 11434:localhost:11434 user@ollama-host
set -euo pipefail

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
REMOTE_HOST="${1:?Usage: $0 user@ollama-host}"

echo "==> Opening reverse tunnel: localhost:${OLLAMA_PORT} -> ${REMOTE_HOST}:${OLLAMA_PORT}"
echo "==> Press Ctrl-C to stop"

ssh -N -R "${OLLAMA_PORT}:localhost:${OLLAMA_PORT}" "${REMOTE_HOST}"
