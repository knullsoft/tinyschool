#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI_DIR="${ROOT_DIR}/tinyschool-ui"
DIST_DIR="${ROOT_DIR}/tinyschool-api/internal/staticui/dist"
APP_VERSION="${TINYSCHOOL_APP_VERSION:-$(git -C "${ROOT_DIR}" describe --tags --always 2>/dev/null || echo dev)}"

if [[ ! -d "${UI_DIR}/node_modules" ]]; then
  echo "Installing UI dependencies..."
  (cd "${UI_DIR}" && bun install --no-save)
fi

echo "Building static UI (version=${APP_VERSION})..."
(
  cd "${UI_DIR}"
  env \
    NUXT_PUBLIC_API_BASE=/api/v1 \
    NUXT_PUBLIC_APP_VERSION="${APP_VERSION}" \
    bun run generate
)

PUBLIC_DIR="${UI_DIR}/.output/public"
if [[ ! -d "${PUBLIC_DIR}" ]]; then
  echo "error: expected ${PUBLIC_DIR} after generate" >&2
  exit 1
fi

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
cp -a "${PUBLIC_DIR}/." "${DIST_DIR}/"

echo "UI copied to ${DIST_DIR}"
