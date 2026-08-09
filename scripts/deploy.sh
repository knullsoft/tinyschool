#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_HOST="${DEPLOY_HOST:-147.93.97.228}"
DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/tinyschool}"
DEPLOY_DOMAIN="${DEPLOY_DOMAIN:-tinyschool.${DEPLOY_HOST}.nip.io}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-}"
STACK_NAME="${STACK_NAME:-tinyschool}"
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"
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
[[ "${STACK_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail "STACK_NAME contains unsupported characters"
[[ "${PROXY_NETWORK}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail "PROXY_NETWORK contains unsupported characters"
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

log "Checking Docker Swarm"
"${SSH[@]}" "docker info --format '{{.Swarm.LocalNodeState}}' | grep -qx active" \
  || fail "Docker Swarm is not active on ${REMOTE}; bootstrap with ../deployer first"

log "Checking shared Traefik proxy network"
"${SSH[@]}" bash -s -- "${PROXY_NETWORK}" <<'CHECK'
set -Eeuo pipefail
network="$1"
docker network inspect "${network}" >/dev/null 2>&1 \
  || { echo "Docker network '${network}' is missing; bootstrap Traefik first" >&2; exit 1; }
driver="$(docker network inspect -f '{{.Driver}}' "${network}")"
[[ "${driver}" == "overlay" ]] \
  || { echo "network '${network}' driver is ${driver}, expected overlay" >&2; exit 1; }
CHECK

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
  "${DEPLOY_MODE}" "${APP_VERSION}" "${STACK_NAME}" <<'REMOTE'
set -Eeuo pipefail
release_path="$1"
deploy_path="$2"
domain="$3"
image_api="$4"
deploy_mode="$5"
app_version="$6"
stack_name="$7"

cd "${release_path}"
if [[ "${deploy_mode}" == "build" ]]; then
  docker build \
    -t "${image_api}" \
    --build-arg "APP_VERSION=${app_version}" \
    -f deploy/api.Dockerfile \
    .
else
  docker pull --quiet "${image_api}"
fi

export DOMAIN="${domain}" IMAGE_API="${image_api}"
# Local build tags are not on a registry; skip Swarm's default pull resolve.
resolve_image=always
if [[ "${deploy_mode}" == "build" ]]; then
  resolve_image=never
fi
docker stack deploy \
  --resolve-image "${resolve_image}" \
  -c deploy/stack.yaml \
  "${stack_name}"
ln -sfn "${release_path}" "${deploy_path}/current"

# Per-commit tags accumulate; drop unused images older than a week so the
# host does not slowly fill up.
docker image prune -af --filter 'until=168h' >/dev/null || true
REMOTE

if [[ -n "${REGISTRY_TOKEN}" ]]; then
  "${SSH[@]}" "docker logout '${REGISTRY}' >/dev/null" || true
fi

log "Waiting for swarm service ${STACK_NAME}_api"
"${SSH[@]}" bash -s -- "${STACK_NAME}" <<'WAIT'
set -Eeuo pipefail
stack_name="$1"
service_name="${stack_name}_api"
for attempt in $(seq 1 45); do
  replicas="$(docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | awk -v n="${service_name}" '$1==n {print $2}')"
  if [[ "${replicas}" == "1/1" ]]; then
    exit 0
  fi
  if [[ "${attempt}" -eq 45 ]]; then
    docker service ls || true
    docker service ps "${service_name}" --no-trunc 2>/dev/null || true
    docker service logs --tail 50 "${service_name}" 2>/dev/null || true
    echo "service ${service_name} did not reach 1/1 (last replicas=${replicas:-none})" >&2
    exit 1
  fi
  sleep 2
done
WAIT

log "Waiting for https://${DEPLOY_DOMAIN}/ready"
for attempt in {1..30}; do
  if curl --fail --silent --show-error --max-time 10 "https://${DEPLOY_DOMAIN}/ready" >/dev/null 2>&1; then
    log "Deployment complete: https://${DEPLOY_DOMAIN}"
    exit 0
  fi
  if (( attempt == 30 )); then
    "${SSH[@]}" "docker service ps '${STACK_NAME}_api' --no-trunc; docker service logs --tail 50 '${STACK_NAME}_api'" || true
    fail "service did not become ready at https://${DEPLOY_DOMAIN}/ready"
  fi
  sleep 2
done
