#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_HOST="${DEPLOY_HOST:-147.93.97.228}"
DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/tinyschool}"
DEPLOY_DOMAIN="${DEPLOY_DOMAIN:-tinyschool.${DEPLOY_HOST}.nip.io}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-}"
REGISTRY="${REGISTRY:-ghcr.io}"
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_TOKEN="${REGISTRY_TOKEN:-}"
IMAGE_API="${IMAGE_API:-}"
REMOTE="${DEPLOY_USER}@${DEPLOY_HOST}"
RELEASE_ID="${GITHUB_SHA:-$(date -u +%Y%m%d%H%M%S)}"
RELEASE_ID="${RELEASE_ID:0:16}"
APP_VERSION="${TINYSCHOOL_APP_VERSION:-$(git -C "${ROOT_DIR}" describe --tags --always 2>/dev/null || echo dev)}"
DEPLOY_MODE="pull"

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

fail() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

command -v ssh >/dev/null || fail "ssh is required"
command -v tar >/dev/null || fail "tar is required"
command -v curl >/dev/null || fail "curl is required"
[[ "${DEPLOY_PATH}" == /* && "${DEPLOY_PATH}" != "/" ]] || fail "DEPLOY_PATH must be an absolute, non-root path"
[[ "${DEPLOY_HOST}" =~ ^[a-zA-Z0-9.-]+$ ]] || fail "DEPLOY_HOST contains unsupported characters"
[[ "${DEPLOY_USER}" =~ ^[a-zA-Z0-9._-]+$ ]] || fail "DEPLOY_USER contains unsupported characters"
[[ "${DEPLOY_DOMAIN}" =~ ^[a-zA-Z0-9.-]+$ ]] || fail "DEPLOY_DOMAIN contains unsupported characters"
[[ "${RELEASE_ID}" =~ ^[a-zA-Z0-9._-]+$ ]] || fail "release ID contains unsupported characters"
if [[ -z "${IMAGE_API}" ]]; then
  DEPLOY_MODE="build"
  IMAGE_API="tinyschool-api:${RELEASE_ID}"
fi
[[ "${IMAGE_API}" =~ ^[a-zA-Z0-9./:_-]+$ ]] || fail "IMAGE_API contains unsupported characters"
[[ "${APP_VERSION}" =~ ^[a-zA-Z0-9._+-]+$ ]] || fail "app version contains unsupported characters"

# ServerAliveInterval keeps the TCP session alive through intermediate NAT while
# a long, silent remote build runs; without it the connection is dropped and ssh
# exits 255 with "client_loop: send disconnect: Broken pipe".
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=20)
if [[ -n "${DEPLOY_SSH_KEY}" ]]; then
  [[ -f "${DEPLOY_SSH_KEY}" ]] || fail "DEPLOY_SSH_KEY does not exist"
  SSH+=(-o IdentitiesOnly=yes -i "${DEPLOY_SSH_KEY}")
fi
SSH+=("${REMOTE}")
REMOTE_RELEASE="${DEPLOY_PATH}/releases/${RELEASE_ID}"

log "Checking SSH access to ${REMOTE}"
"${SSH[@]}" "true" || fail "SSH authentication failed for ${REMOTE}"

log "Checking Docker Compose"
"${SSH[@]}" "docker compose version >/dev/null 2>&1" \
  || fail "Docker Compose is not available on ${REMOTE}"

log "Uploading release ${RELEASE_ID}"
"${SSH[@]}" "mkdir -p '${REMOTE_RELEASE}'"
tar \
  --exclude=.git \
  --exclude=.github \
  --exclude=.keys \
  --exclude=.runs \
  --exclude=.env \
  --exclude='.env.*' \
  --exclude=.ssh \
  --exclude='*.key' \
  --exclude='*.pem' \
  --exclude=github \
  --exclude=github.pub \
  --exclude=node_modules \
  --exclude=.nuxt \
  --exclude=.output \
  -C "${ROOT_DIR}" -cf - . \
  | "${SSH[@]}" "tar -xf - -C '${REMOTE_RELEASE}'"

if [[ -n "${REGISTRY_TOKEN}" ]]; then
  log "Authenticating to ${REGISTRY}"
  # Piped over stdin so the token never lands in the remote process argv.
  printf '%s\n' "${REGISTRY_TOKEN}" \
    | "${SSH[@]}" "docker login '${REGISTRY}' -u '${REGISTRY_USER}' --password-stdin >/dev/null" \
    || fail "docker login to ${REGISTRY} failed"
fi

if [[ "${DEPLOY_MODE}" == "build" ]]; then
  log "Building ${IMAGE_API} on ${REMOTE}"
else
  log "Pulling ${IMAGE_API}"
fi
"${SSH[@]}" bash -s -- \
  "${REMOTE_RELEASE}" "${DEPLOY_PATH}" "${DEPLOY_DOMAIN}" "${IMAGE_API}" \
  "${DEPLOY_MODE}" "${APP_VERSION}" <<'REMOTE'
set -Eeuo pipefail
release_path="$1"
deploy_path="$2"
domain="$3"
image_api="$4"
deploy_mode="$5"
app_version="$6"

cd "${release_path}/deploy"
export DOMAIN="${domain}" IMAGE_API="${image_api}" APP_VERSION="${app_version}"
if [[ "${deploy_mode}" == "build" ]]; then
  docker compose build api
else
  docker compose pull --quiet api
fi
docker compose up -d --remove-orphans
ln -sfn "${release_path}" "${deploy_path}/current"
# Per-commit tags accumulate; drop unused images older than a week so the
# host does not slowly fill up.
docker image prune -af --filter 'until=168h' >/dev/null || true
REMOTE

if [[ -n "${REGISTRY_TOKEN}" ]]; then
  "${SSH[@]}" "docker logout '${REGISTRY}' >/dev/null" || true
fi

log "Waiting for https://${DEPLOY_DOMAIN}/ready"
for attempt in {1..30}; do
  if curl --fail --silent --show-error --max-time 10 "https://${DEPLOY_DOMAIN}/ready" >/dev/null 2>&1; then
    log "Deployment complete: https://${DEPLOY_DOMAIN}"
    exit 0
  fi
  if (( attempt == 30 )); then
    "${SSH[@]}" "cd '${REMOTE_RELEASE}/deploy' && DOMAIN='${DEPLOY_DOMAIN}' IMAGE_API='${IMAGE_API}' docker compose ps"
    fail "service did not become ready"
  fi
  sleep 2
done
