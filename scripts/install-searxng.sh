#!/usr/bin/env bash
# Install SearXNG via pip (no Docker) as a systemd service.
# Tested on Ubuntu 22.04. Run with sudo or as root.
set -euo pipefail

SEARXNG_DIR="/opt/searxng"
SEARXNG_PORT="${SEARXNG_PORT:-8888}"
SEARXNG_BIND="${SEARXNG_BIND:-127.0.0.1}"
SEARXNG_USER="searxng"
SETTINGS_DIR="/etc/searxng"

echo "==> Installing SearXNG (pip) to ${SEARXNG_DIR}"

# Install system dependencies
apt-get update -qq
apt-get install -y -qq software-properties-common > /dev/null

# SearXNG requires Python 3.11+. Ubuntu 22.04 ships 3.10, so use deadsnakes PPA.
PYTHON_BIN="python3"
CURRENT_PY_MINOR=$("${PYTHON_BIN}" -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "0")
if [ "${CURRENT_PY_MINOR}" -lt 11 ]; then
  echo "==> System Python is 3.${CURRENT_PY_MINOR}; installing Python 3.11 from deadsnakes PPA..."
  add-apt-repository -y ppa:deadsnakes/ppa > /dev/null 2>&1
  apt-get update -qq
  apt-get install -y -qq python3.11 python3.11-venv python3.11-dev > /dev/null
  PYTHON_BIN="python3.11"
fi

apt-get install -y -qq libxml2-dev libxslt1-dev zlib1g-dev libffi-dev libssl-dev > /dev/null

# Create service user (no login shell, no home)
if ! id -u "${SEARXNG_USER}" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "${SEARXNG_USER}"
  echo "==> Created system user: ${SEARXNG_USER}"
fi

# Clone SearXNG source (the real project is not on PyPI)
SEARXNG_SRC="/opt/searxng-src"
if [ -d "${SEARXNG_SRC}" ]; then
  echo "==> Updating SearXNG source..."
  git -C "${SEARXNG_SRC}" pull --rebase
else
  echo "==> Cloning SearXNG from GitHub..."
  git clone https://github.com/searxng/searxng.git "${SEARXNG_SRC}"
fi

# Create venv and install from source
if [ -d "${SEARXNG_DIR}" ]; then
  rm -rf "${SEARXNG_DIR}"
fi
"${PYTHON_BIN}" -m venv "${SEARXNG_DIR}"
"${SEARXNG_DIR}/bin/pip" install --quiet --upgrade pip setuptools wheel
# Install SearXNG's dependencies first (setup.py imports msgspec at build time,
# and pip's build isolation creates a temp env that won't have it).
echo "==> Installing SearXNG dependencies..."
"${SEARXNG_DIR}/bin/pip" install --quiet -r "${SEARXNG_SRC}/requirements.txt"
echo "==> Installing SearXNG from source..."
"${SEARXNG_DIR}/bin/pip" install --quiet --no-build-isolation "${SEARXNG_SRC}"

# Generate a random secret key
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

# Write minimal settings
mkdir -p "${SETTINGS_DIR}"
cat > "${SETTINGS_DIR}/settings.yml" <<SETTINGS
use_default_settings: true

general:
  instance_name: "OpenClaw SearXNG"

server:
  secret_key: "${SECRET_KEY}"
  bind_address: "${SEARXNG_BIND}"
  port: ${SEARXNG_PORT}

search:
  formats:
    - html
    - json

# Limit engines to avoid slow responses
engines:
  - name: google
    disabled: false
  - name: duckduckgo
    disabled: false
  - name: bing
    disabled: false
  - name: wikipedia
    disabled: false
SETTINGS

chown -R "${SEARXNG_USER}:${SEARXNG_USER}" "${SEARXNG_DIR}" "${SETTINGS_DIR}"

# Write systemd unit
cat > /etc/systemd/system/searxng.service <<UNIT
[Unit]
Description=SearXNG meta-search engine
After=network.target

[Service]
Type=exec
User=${SEARXNG_USER}
Group=${SEARXNG_USER}
Environment=SEARXNG_SETTINGS_PATH=${SETTINGS_DIR}/settings.yml
ExecStart=${SEARXNG_DIR}/bin/python -m searx.webapp
Restart=on-failure
RestartSec=5
MemoryMax=512M

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable searxng.service
systemctl restart searxng.service

# Wait briefly and verify
sleep 2
if curl -sf "http://${SEARXNG_BIND}:${SEARXNG_PORT}/search?q=test&format=json" > /dev/null 2>&1; then
  echo "==> SearXNG is running at http://${SEARXNG_BIND}:${SEARXNG_PORT}"
  echo "==> JSON API: curl 'http://${SEARXNG_BIND}:${SEARXNG_PORT}/search?q=hello&format=json'"
else
  echo "==> SearXNG installed but health check failed. Check: systemctl status searxng"
  echo "==> Logs: journalctl -u searxng -n 50"
fi
