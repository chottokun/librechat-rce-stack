#!/usr/bin/env bash
# ==============================================================================
# sandbox/build.sh
# Sandbox Runner イメージのローカル/CIビルドスクリプト (案D)
# ==============================================================================
# 上流 code-interpreter の特定 SHA を一時取得し、最小パッチを適用して
# 日本語フォント同梱の japanize-matplotlib を事前焼き込みしたイメージをビルドします。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../scripts/lib/common.sh"

PROJECT_ROOT="$(get_project_root)"
LOCK_FILE="${PROJECT_ROOT}/upstream.lock"

require_cmd docker
require_cmd git

if [[ ! -f "${LOCK_FILE}" ]]; then
    die "Lockfile not found at ${LOCK_FILE}"
fi

# upstream.lock から上流リポジトリと SHA を取得
UPSTREAM_REPO=$(grep -E "^CODEAPI_UPSTREAM_REPO=" "${LOCK_FILE}" | cut -d'=' -f2-)
UPSTREAM_SHA=$(grep -E "^CODEAPI_UPSTREAM_SHA=" "${LOCK_FILE}" | cut -d'=' -f2-)
TARGET_MODE="${1:-all}" # all, kvm, direct

BUILD_DIR="${SCRIPT_DIR}/.build"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
trap 'rm -rf "${BUILD_DIR}"' EXIT

log_info "Fetching upstream code-interpreter source at commit ${UPSTREAM_SHA}..."
git clone --depth 1 "${UPSTREAM_REPO}" "${BUILD_DIR}/code-interpreter"
(
    cd "${BUILD_DIR}/code-interpreter"
    git fetch --depth 1 origin "${UPSTREAM_SHA}"
    git checkout "${UPSTREAM_SHA}"
)

log_info "Applying extra requirements & patches..."
# requirements-extra.txt をビルドコンテキストへコピー
cp "${SCRIPT_DIR}/requirements-extra.txt" "${BUILD_DIR}/code-interpreter/docker/"

# パッチの適用
for patch_file in "${SCRIPT_DIR}/patches/"*.patch; do
    if [[ -f "${patch_file}" ]]; then
        (
            cd "${BUILD_DIR}/code-interpreter"
            git apply "${patch_file}"
        )
        log_success "Applied $(basename "${patch_file}") cleanly"
    fi
done

# Dockerfile 構築 & ビルド実行
(
    cd "${BUILD_DIR}/code-interpreter"
    
    if [[ "${TARGET_MODE}" == "all" || "${TARGET_MODE}" == "kvm" ]]; then
        log_info "Building KVM-enabled Sandbox Runner (sandbox-runner-true)..."
        docker build -f api/Dockerfile --target sandbox-runner-true \
            -t "ghcr.io/chottokun/librechat-rce-stack/sandbox-runner:${UPSTREAM_SHA:0:7}-ja1" \
            -t "ghcr.io/chottokun/librechat-rce-stack/sandbox-runner:latest" .
    fi
    
    if [[ "${TARGET_MODE}" == "all" || "${TARGET_MODE}" == "direct" ]]; then
        log_info "Building NsJail Direct Sandbox Runner (sandbox-runner-direct-baked)..."
        docker build -f api/Dockerfile --target sandbox-runner-direct-baked \
            -t "ghcr.io/chottokun/librechat-rce-stack/sandbox-runner-direct:${UPSTREAM_SHA:0:7}-ja1" \
            -t "ghcr.io/chottokun/librechat-rce-stack/sandbox-runner-direct:latest" .
    fi
)

log_success "Sandbox Runner build completed successfully"
