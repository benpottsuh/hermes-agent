#!/usr/bin/env bash
# One-shot setup: SSH key, Hostinger API attach, ssh config, hostinger.env, connectivity test.
#
# Where to run: Cursor terminal OR any terminal on YOUR LAPTOP (not on the VPS).
#   cd ~/projects/hermes-agent
#   ./deploy/hostinger/bootstrap.sh
#
# What still needs you manually: see deploy/hostinger/BOOTSTRAP.md
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DEPLOY_DIR}/../.." && pwd)"
ENV_FILE="${DEPLOY_DIR}/hostinger.env"
SSH_KEY="${HOME}/.ssh/id_ed25519_hostinger"
SSH_PUB="${SSH_KEY}.pub"
SSH_CONFIG="${HOME}/.ssh/config"
SSH_HOST_ALIAS="hermes-hostinger"
API_BASE="https://developers.hostinger.com"

# Override via hostinger.env or environment (bootstrap discovers via API when unset)
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${ENV_FILE}" 2>/dev/null || true
fi
VM_ID="${HOSTINGER_VM_ID:-}"
VPS_IP="${HOSTINGER_VPS_IP:-}"
DOCKER_PROJECT="${DOCKER_PROJECT:-}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-}"
SSH_USER="${SSH_USER:-root}"

DRY_RUN=false
SKIP_API=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --skip-api) SKIP_API=true ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
  esac
done

log() { printf '==> %s\n' "$*"; }
run() {
  if [[ "${DRY_RUN}" == true ]]; then
    printf '[dry-run] '; printf '%q ' "$@"; printf '\n'
  else
    "$@"
  fi
}

load_api_token() {
  if [[ -n "${HOSTINGER_API_TOKEN:-}" ]]; then
    return 0
  fi
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}" 2>/dev/null || true
  fi
  if [[ -n "${HOSTINGER_API_TOKEN:-}" ]]; then
    return 0
  fi
  if [[ -f "${HOME}/.cursor/mcp.json" ]]; then
    HOSTINGER_API_TOKEN="$(
      python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.cursor/mcp.json")
d = json.load(open(p))
srv = d.get("mcpServers", {}).get("hostinger-mcp", {})
env = srv.get("env", {})
print(env.get("HOSTINGER_API_TOKEN") or env.get("API_TOKEN") or "")
PY
    )"
  fi
  [[ -n "${HOSTINGER_API_TOKEN:-}" ]]
}

api() {
  local method="$1" path="$2"
  shift 2
  if ! load_api_token; then
    echo "No Hostinger API token. Set HOSTINGER_API_TOKEN or fix ~/.cursor/mcp.json hostinger-mcp." >&2
    return 1
  fi
  if [[ "${DRY_RUN}" == true ]]; then
    echo "[dry-run] curl -X ${method} ${API_BASE}${path}" >&2
    return 0
  fi
  curl -fsS -X "${method}" \
    -H "Authorization: Bearer ${HOSTINGER_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_BASE}${path}" "$@"
}

discover_vm() {
  [[ -n "${VM_ID}" && -n "${VPS_IP}" ]] && return 0
  [[ "${SKIP_API}" == true ]] && return 0
  load_api_token || return 1
  log "Discovering VPS from Hostinger API"
  if [[ "${DRY_RUN}" == true ]]; then
    VM_ID="${VM_ID:-0}"
    VPS_IP="${VPS_IP:-0.0.0.0}"
    return 0
  fi
  local parsed
  parsed="$(
    api GET "/api/vps/v1/virtual-machines" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('data', [])
if not items:
    sys.exit(1)
vm = items[0]
print(vm.get('id', ''), vm.get('ipv4', {}).get('address', vm.get('ip', '')), sep='|')
" 2>/dev/null || true
  )"
  if [[ -z "${parsed}" ]]; then
    echo "Could not discover VPS. Set HOSTINGER_VM_ID and HOSTINGER_VPS_IP in hostinger.env." >&2
    return 1
  fi
  VM_ID="${VM_ID:-${parsed%%|*}}"
  VPS_IP="${VPS_IP:-${parsed#*|}}"
}

discover_docker() {
  [[ -n "${DOCKER_PROJECT}" && -n "${DOCKER_CONTAINER}" ]] && return 0
  [[ "${SKIP_API}" == true ]] && return 0
  load_api_token || return 0
  log "Discovering Docker project from Hostinger API"
  if [[ "${DRY_RUN}" == true ]]; then
    return 0
  fi
  local parsed
  parsed="$(
    api GET "/api/vps/v1/projects" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('data', [])
for p in items:
    name = (p.get('name') or '').lower()
    if 'hermes' in name:
        print(p.get('name', ''), p.get('container_id', p.get('id', '')), sep='|')
        break
" 2>/dev/null || true
  )"
  if [[ -n "${parsed}" ]]; then
    DOCKER_PROJECT="${DOCKER_PROJECT:-${parsed%%|*}}"
    DOCKER_CONTAINER="${DOCKER_CONTAINER:-${parsed#*|}}"
  fi
}

ensure_ssh_key() {
  if [[ -f "${SSH_KEY}" && -f "${SSH_PUB}" ]]; then
    log "SSH key already exists: ${SSH_KEY}"
    return 0
  fi
  log "Creating SSH key at ${SSH_KEY}"
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  run ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "hermes-cursor-$(hostname -s 2>/dev/null || echo laptop)"
}

register_and_attach_key() {
  [[ "${SKIP_API}" == true ]] && { log "Skipping Hostinger API (--skip-api)"; return 0; }
  load_api_token || return 1

  local pubkey name key_id
  pubkey="$(tr -d '\r' <"${SSH_PUB}")"
  name="cursor-hermes-$(date +%Y%m%d)"

  log "Registering SSH public key with Hostinger API"
  if [[ "${DRY_RUN}" == true ]]; then
    api POST "/api/vps/v1/public-keys" -d "{\"name\":\"${name}\",\"key\":\"...\"}"
    api POST "/api/vps/v1/public-keys/attach/${VM_ID}" -d '{"ids":[0]}'
    return 0
  fi

  # Reuse existing key with same content if present
  key_id="$(
    api GET "/api/vps/v1/public-keys" | python3 -c "
import json, sys
pub = '''${pubkey}'''.strip()
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('data', [])
for k in items:
    if (k.get('key') or '').strip() == pub:
        print(k.get('id', ''))
        break
" 2>/dev/null || true
  )"

  if [[ -z "${key_id}" ]]; then
    resp="$(api POST "/api/vps/v1/public-keys" -d "$(python3 -c "import json; print(json.dumps({'name': '''${name}''', 'key': open('${SSH_PUB}').read().strip()}))")")"
    key_id="$(echo "${resp}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id', d.get('data',{}).get('id','')))" 2>/dev/null || true)"
  fi

  if [[ -z "${key_id}" ]]; then
    echo "Could not create or find public key ID. Add ${SSH_PUB} manually in hPanel." >&2
    return 1
  fi

  log "Attaching key id ${key_id} to VM ${VM_ID}"
  api POST "/api/vps/v1/public-keys/attach/${VM_ID}" \
    -d "$(python3 -c "import json; print(json.dumps({'ids': [int('${key_id}')]}))")" >/dev/null
}

write_ssh_config() {
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  touch "${SSH_CONFIG}"
  chmod 600 "${SSH_CONFIG}"

  if grep -q "Host ${SSH_HOST_ALIAS}" "${SSH_CONFIG}" 2>/dev/null; then
    log "SSH config already has Host ${SSH_HOST_ALIAS} in ${SSH_CONFIG}"
    return 0
  fi

  log "Appending Host ${SSH_HOST_ALIAS} to ${SSH_CONFIG}"
  if [[ "${DRY_RUN}" == true ]]; then
    return 0
  fi
  cat >>"${SSH_CONFIG}" <<EOF

# --- hermes-agent bootstrap (Cursor) ---
Host ${SSH_HOST_ALIAS}
  HostName ${VPS_IP}
  User ${SSH_USER}
  IdentityFile ${SSH_KEY}
  IdentitiesOnly yes
# --- end hermes-agent bootstrap ---
EOF
}

write_hostinger_env() {
  log "Writing ${ENV_FILE}"
  if [[ "${DRY_RUN}" == true ]]; then
    return 0
  fi
  cat >"${ENV_FILE}" <<EOF
# Generated by deploy/hostinger/bootstrap.sh — safe to edit
SSH_HOST=${SSH_HOST_ALIAS}
HOSTINGER_VM_ID=${VM_ID}
HOSTINGER_VPS_IP=${VPS_IP}
DOCKER_PROJECT=${DOCKER_PROJECT}
DOCKER_CONTAINER=${DOCKER_CONTAINER}
SSH_USER=${SSH_USER}
HERMES_INSTALL=/opt/hermes
HERMES_USER=hermes
HERMES_DATA=/home/hermes/.hermes
GATEWAY_RESTART_CMD='docker restart ${DOCKER_CONTAINER} 2>/dev/null || true'
EOF
}

test_ssh() {
  log "Testing SSH: ssh -o BatchMode=yes ${SSH_HOST_ALIAS} true"
  if [[ "${DRY_RUN}" == true ]]; then
    return 0
  fi
  sleep 2
  if ssh -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none \
    -i "${SSH_KEY}" "${SSH_USER}@${VPS_IP}" true 2>/dev/null; then
    return 0
  fi
  echo ""
  echo "SSH failed: key is attached in Hostinger API but not accepted on the VPS."
  echo "This is common — fix in the browser terminal (see deploy/hostinger/FIX-SSH.md):"
  echo ""
  echo "  WHERE: https://hpanel.hostinger.com/ → VPS → Browser terminal"
  echo "  PASTE: authorized_keys steps from deploy/hostinger/FIX-SSH.md"
  echo ""
  echo "Your public key file: ${SSH_PUB}"
  echo "Then run: ./deploy/hostinger/bootstrap.sh --skip-api"
  echo ""
  return 1
}

test_docker() {
  log "Checking Hermes container on VPS"
  if [[ "${DRY_RUN}" == true ]]; then
    return 0
  fi
  ssh -o BatchMode=yes "${SSH_HOST_ALIAS}" \
    "docker ps --filter name=hermes --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'"
}

main() {
  log "Hermes Hostinger bootstrap (repo: ${ROOT})"
  discover_vm || exit 1
  discover_docker || true
  ensure_ssh_key
  register_and_attach_key || {
    echo ""
    echo "MANUAL FALLBACK — Hostinger hPanel:"
    echo "  1. Open https://hpanel.hostinger.com/"
    echo "  2. VPS → your server (IP ${VPS_IP:-unknown}) → SSH access / SSH keys"
    echo "  3. Paste contents of: ${SSH_PUB}"
    echo "  4. Re-run: ./deploy/hostinger/bootstrap.sh --skip-api"
    echo ""
    exit 1
  }
  write_ssh_config
  write_hostinger_env
  if ! test_ssh; then
    exit 1
  fi
  test_docker
  log "Running collect-context.sh"
  if [[ "${DRY_RUN}" != true ]]; then
    "${DEPLOY_DIR}/collect-context.sh" || true
  fi
  log "Done. Cursor reads deploy/hostinger/.server-context.md"
}

main "$@"
