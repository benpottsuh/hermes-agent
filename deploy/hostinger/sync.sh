#!/usr/bin/env bash
# Sync local repo to Hostinger and reinstall editable package.
# Usage: ./deploy/hostinger/sync.sh [ssh-target] [remote-repo-path]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="${1:-}"
REMOTE_PATH="${2:-~/hermes-agent}"

if [[ -z "${TARGET}" ]]; then
  echo "Usage: $0 user@hostinger-vps [remote-path]"
  echo "Example: $0 deploy@123.45.67.89 ~/hermes-agent"
  exit 1
fi

echo "==> Rsync source (excludes venv, node_modules) to ${TARGET}:${REMOTE_PATH}"
rsync -avz --delete \
  --exclude '.git/' \
  --exclude 'venv/' \
  --exclude '.venv/' \
  --exclude 'node_modules/' \
  --exclude 'website/node_modules/' \
  --exclude '__pycache__/' \
  --exclude '.pytest_cache/' \
  "${ROOT}/" "${TARGET}:${REMOTE_PATH}/"

echo "==> Reinstall on remote and restart gateway if present"
ssh "${TARGET}" bash -s <<EOF
set -euo pipefail
cd "${REMOTE_PATH}"
export PATH="\${HOME}/.local/bin:\${PATH}"
if command -v uv >/dev/null 2>&1; then
  [[ -d venv ]] || uv venv venv --python 3.11
  export VIRTUAL_ENV="\$(pwd)/venv"
  uv pip install -e ".[all]"
else
  echo "uv not found on remote; run upstream install.sh first or install uv."
  exit 1
fi
if systemctl --user is-active hermes-gateway >/dev/null 2>&1; then
  systemctl --user restart hermes-gateway
  echo "Restarted systemd user service hermes-gateway"
elif command -v hermes >/dev/null 2>&1; then
  hermes gateway restart 2>/dev/null || true
fi
hermes doctor || true
EOF

echo "Done."
