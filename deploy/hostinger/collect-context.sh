#!/usr/bin/env bash
# Pull Hermes server facts over SSH into deploy/hostinger/.server-context.md
# so Cursor can read them without manual copy-paste.
#
# Setup once:
#   cp deploy/hostinger/hostinger.env.example deploy/hostinger/hostinger.env
#   # edit SSH_HOST etc., configure ~/.ssh/config, test: ssh $SSH_HOST true
#
# Run anytime (or after deploy):
#   ./deploy/hostinger/collect-context.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${DEPLOY_DIR}/hostinger.env"
OUT_MD="${DEPLOY_DIR}/.server-context.md"
OUT_JSON="${DEPLOY_DIR}/.server-context.json"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}"
  echo "  cp deploy/hostinger/hostinger.env.example deploy/hostinger/hostinger.env"
  exit 1
fi
# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${SSH_HOST:?Set SSH_HOST in hostinger.env}"
HERMES_INSTALL="${HERMES_INSTALL:-/opt/hermes}"
HERMES_USER="${HERMES_USER:-hermes}"
HERMES_DATA="${HERMES_DATA:-/home/${HERMES_USER}/.hermes}"

run_remote() {
  local remote_script
  remote_script="$(cat <<'REMOTE_EOF'
set -eu
HERMES_INSTALL="${HERMES_INSTALL:-/opt/hermes}"
HERMES_USER="${HERMES_USER:-hermes}"
HERMES_DATA="${HERMES_DATA:-/home/${HERMES_USER}/.hermes}"

section() { printf '\n## %s\n\n' "$1"; }
run() { printf '```\n'; "$@" 2>&1 || true; printf '\n```\n'; }

section "Collected at"
date -u +"%Y-%m-%dT%H:%M:%SZ"

section "1) Server identity"
run hostname
run whoami
run uname -a
run pwd

section "2) Hermes install"
run which hermes
run bash -c 'hermes --version 2>/dev/null || hermes doctor 2>&1 | head -8 || true'
run ls -la "${HERMES_INSTALL}" 2>/dev/null | head -25
if [[ -d "${HERMES_INSTALL}/.git" ]]; then
  run bash -c "cd '${HERMES_INSTALL}' && git remote -v && git branch --show-current && git rev-parse --short HEAD"
else
  printf '```\n(no git repo at %s)\n```\n' "${HERMES_INSTALL}"
fi

section "3) Hermes data (${HERMES_DATA})"
run ls -la "${HERMES_DATA}" 2>/dev/null
for f in config.yaml .env MEMORY.md USER.md SOUL.md state.db; do
  if [[ -e "${HERMES_DATA}/${f}" ]]; then echo "- ${f}: yes"; else echo "- ${f}: no"; fi
done
run ls -la "${HERMES_DATA}/skills" 2>/dev/null | head -20

section "4) Gateway / processes"
run hermes gateway status 2>&1
run bash -c 'ps aux 2>/dev/null | grep -E "[h]ermes|[g]ateway" | head -15 || true'

section "5) SSH (from inside server)"
run bash -c '[[ -n "${SSH_CONNECTION:-}" ]] && echo "SSH_CONNECTION=${SSH_CONNECTION}" || echo "SSH_CONNECTION=(not an ssh session)"'
run bash -c 'curl -fsS --max-time 5 ifconfig.me 2>/dev/null || curl -fsS --max-time 5 icanhazip.com 2>/dev/null || echo unknown'

REMOTE_EOF
)"

  if [[ -n "${DOCKER_CONTAINER:-}" ]]; then
    ssh "${SSH_HOST}" docker exec -i "${DOCKER_CONTAINER}" env \
      HERMES_INSTALL="${HERMES_INSTALL}" \
      HERMES_USER="${HERMES_USER}" \
      HERMES_DATA="${HERMES_DATA}" \
      bash -s <<<"${remote_script}"
  else
    ssh "${SSH_HOST}" env \
      HERMES_INSTALL="${HERMES_INSTALL}" \
      HERMES_USER="${HERMES_USER}" \
      HERMES_DATA="${HERMES_DATA}" \
      bash -s <<<"${remote_script}"
  fi
}

echo "Collecting from ${SSH_HOST}${DOCKER_CONTAINER:+ → docker ${DOCKER_CONTAINER}} ..."
BODY="$(run_remote)" || true
if [[ -n "${DOCKER_CONTAINER:-}" ]]; then
  HOST_DOCKER="$(ssh "${SSH_HOST}" docker ps --filter "id=${DOCKER_CONTAINER}" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>&1 || true)"
  BODY="${BODY}

## 6) Docker (VPS host)

\`\`\`
${HOST_DOCKER}
\`\`\`
"
fi
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat >"${OUT_MD}" <<EOF
# Hermes server context (auto-generated)

> Do not commit. Regenerate: \`./deploy/hostinger/collect-context.sh\`
> Source: \`${SSH_HOST:-${DOCKER_CONTAINER}}\` at ${TS}

${BODY}
EOF

# Minimal JSON for tooling
python3 - <<PY
import json, re
from pathlib import Path
md = Path("${OUT_MD}").read_text()
json.dump({
  "collected_at": "${TS}",
  "ssh_host": "${SSH_HOST:-}",
  "docker_container": "${DOCKER_CONTAINER:-}",
  "hermes_install": "${HERMES_INSTALL}",
  "hermes_user": "${HERMES_USER}",
  "hermes_data": "${HERMES_DATA}",
  "markdown_path": "deploy/hostinger/.server-context.md",
}, Path("${OUT_JSON}").open("w"), indent=2)
PY

echo "Wrote ${OUT_MD}"
echo "Wrote ${OUT_JSON}"
echo "Cursor agents read deploy/hostinger/.server-context.md when helping with deploy."
