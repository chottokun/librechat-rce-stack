#!/usr/bin/env bash
# ==============================================================================
# scripts/upstream-sync.sh
# 上流 code-interpreter の最新 main コミット検知 & lockfile 更新スクリプト
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROJECT_ROOT="$(get_project_root)"
LOCK_FILE="${PROJECT_ROOT}/upstream.lock"

require_cmd git
require_cmd curl

CURRENT_SHA=$(grep -E "^CODEAPI_UPSTREAM_SHA=" "${LOCK_FILE}" | cut -d'=' -f2-)
UPSTREAM_REPO="https://github.com/LibreChat-AI/code-interpreter.git"

log_info "Querying latest commit of upstream code-interpreter main..."
LATEST_SHA=$(git ls-remote "${UPSTREAM_REPO}" refs/heads/main | awk '{print $1}')

if [[ -z "${LATEST_SHA}" ]]; then
    die "Failed to query latest commit from ${UPSTREAM_REPO}"
fi

log_info "Current pinned SHA: ${CURRENT_SHA}"
log_info "Latest upstream SHA: ${LATEST_SHA}"

if [[ "${CURRENT_SHA}" == "${LATEST_SHA}" ]]; then
    log_success "Upstream is already up-to-date at ${CURRENT_SHA}"
    exit 0
fi

log_info "New upstream version detected! Verifying patch compatibility..."
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

git clone --depth 1 "${UPSTREAM_REPO}" "${WORK_DIR}/code-interpreter"
(
    cd "${WORK_DIR}/code-interpreter"
    git fetch --depth 1 origin "${LATEST_SHA}"
    git checkout "${LATEST_SHA}"
    if ! git apply --check "${PROJECT_ROOT}/sandbox/patches/0001-ja-extras.patch"; then
        die "Patch 0001-ja-extras.patch failed to apply to upstream ${LATEST_SHA}! Manual intervention required."
    fi
)

log_success "Patch applied cleanly to new upstream SHA ${LATEST_SHA}"

# upstream.lock の SHA とタグを更新
sed -i "s|^CODEAPI_UPSTREAM_SHA=.*|CODEAPI_UPSTREAM_SHA=${LATEST_SHA}|" "${LOCK_FILE}"
sed -i "s|^CODEAPI_IMAGE_TAG=.*|CODEAPI_IMAGE_TAG=sha-${LATEST_SHA}|" "${LOCK_FILE}"
sed -i "s|:sha-[a-f0-9]*|:sha-${LATEST_SHA}|g" "${LOCK_FILE}"
sed -i "s|:${CURRENT_SHA:0:7}-ja1|:${LATEST_SHA:0:7}-ja1|g" "${LOCK_FILE}"

log_success "Updated ${LOCK_FILE} to ${LATEST_SHA}"
