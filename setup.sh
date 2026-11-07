#!/usr/bin/env bash
# ==============================================================================
# setup.sh
# LibreChat RCE Stack - ワンコマンド自動セットアップ & 起動スクリプト
# ==============================================================================
#
# 使用方法:
#   ./setup.sh [オプション]
#
# オプション:
#   --domain <DOMAIN>    ドメイン名（デフォルト: localhost）
#   --build              イメージをローカルで自前ビルド（GHCR pull の代わり）
#   --rotate <target>    指定シークレットをローテーション（all, jwt, manifest 等）
#   --no-up              環境変数・証明書生成のみ行い、docker compose 起動はスキップ
#   --help, -h           ヘルプを表示
#
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"

PROJECT_ROOT="${SCRIPT_DIR}"
cd "${PROJECT_ROOT}"

DOMAIN="localhost"
BUILD_LOCAL=false
DO_UP=true
ROTATE_TARGET=""

usage() {
    cat <<EOF
Usage: ./setup.sh [OPTIONS]

One-command setup and launch for LibreChat + Code Interpreter (RCE).

Options:
  --domain <DOMAIN>    Set public FQDN (default: localhost)
  --build              Force local build of Sandbox Runner instead of pulling GHCR
  --rotate <target>    Rotate specific secrets (all, jwt, manifest, JWT_SECRET, etc.)
  --no-up              Prepare configs/certs/secrets without running docker compose up
  -h, --help           Show this message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="${2:?Missing domain argument}"
            shift 2
            ;;
        --build)
            BUILD_LOCAL=true
            shift
            ;;
        --rotate)
            ROTATE_TARGET="${2:?Missing rotate target}"
            shift 2
            ;;
        --no-up)
            DO_UP=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            die "Unknown option: $1 (Use --help for usage)"
            ;;
    esac
done

echo "===================================================================="
echo "          LibreChat RCE Stack - Enterprise Hardening"
echo "===================================================================="
echo ""

# 1. 必須コマンド検証
require_cmd openssl
if [[ "${DO_UP}" == "true" ]]; then
    require_cmd docker
fi

# 2. シークレット & Ed25519 鍵ペア自動生成
log_info "Step 1/5: Provisioning cryptographic secrets and Ed25519 keys..."
if [[ -n "${ROTATE_TARGET}" ]]; then
    bash "${PROJECT_ROOT}/scripts/generate-secrets.sh" --rotate "${ROTATE_TARGET}"
else
    bash "${PROJECT_ROOT}/scripts/generate-secrets.sh"
fi

# 3. KVM デバイス検出 & 実行プロファイル自動判定
log_info "Step 2/5: Detecting virtualization capabilities..."
COMPOSE_MODE_FILE="compose.kvm.yaml"
RUNNER_TARGET="kvm"
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    log_success "KVM detected (/dev/kvm is accessible). MicroVM hardware virtualization enabled."
    bash "${PROJECT_ROOT}/scripts/generate-secrets.sh" # .env の KVM_ENABLED 設定
    sed -i 's/^KVM_ENABLED=.*/KVM_ENABLED=true/' "${PROJECT_ROOT}/.env" 2>/dev/null || true
    COMPOSE_MODE_FILE="compose.kvm.yaml"
    RUNNER_TARGET="kvm"
else
    log_warn "/dev/kvm is not accessible or not supported on this host."
    log_info "Falling back to hardened NsJail Direct container isolation mode."
    sed -i 's/^KVM_ENABLED=.*/KVM_ENABLED=false/' "${PROJECT_ROOT}/.env" 2>/dev/null || true
    COMPOSE_MODE_FILE="compose.direct.yaml"
    RUNNER_TARGET="direct"
fi

# COMPOSE_FILE を .env に同期（単体 docker compose 実行時にも自動適用されるよう配慮）
if grep -q "^COMPOSE_FILE=" "${PROJECT_ROOT}/.env" 2>/dev/null; then
    sed -i "s|^COMPOSE_FILE=.*|COMPOSE_FILE=compose.yaml:${COMPOSE_MODE_FILE}|" "${PROJECT_ROOT}/.env"
else
    echo "COMPOSE_FILE=compose.yaml:${COMPOSE_MODE_FILE}" >> "${PROJECT_ROOT}/.env"
fi

# ドメイン設定を .env に同期
sed -i "s/^DOMAIN=.*/DOMAIN=${DOMAIN}/" "${PROJECT_ROOT}/.env" 2>/dev/null || true
sed -i "s|^DOMAIN_CLIENT=.*|DOMAIN_CLIENT=https://${DOMAIN}|" "${PROJECT_ROOT}/.env" 2>/dev/null || true
sed -i "s|^DOMAIN_SERVER=.*|DOMAIN_SERVER=https://${DOMAIN}|" "${PROJECT_ROOT}/.env" 2>/dev/null || true

# 4. SSL/TLS 証明書生成
log_info "Step 3/5: Generating TLS certificates for domain: ${DOMAIN}..."
bash "${PROJECT_ROOT}/scripts/generate-cert.sh" "${DOMAIN}"

if [[ "${DO_UP}" != "true" ]]; then
    log_success "Setup complete (--no-up specified). Environment is ready."
    exit 0
fi

# 5. コンテナイメージ取得 or ローカルビルド
COMPOSE_CMD=(docker compose --env-file upstream.lock --env-file .env -f compose.yaml -f "${COMPOSE_MODE_FILE}")

if [[ "${BUILD_LOCAL}" == "true" ]]; then
    log_info "Step 4/5: Building Sandbox Runner locally (--build requested)..."
    bash "${PROJECT_ROOT}/sandbox/build.sh" "${RUNNER_TARGET}"
else
    log_info "Step 4/5: Pulling prebuilt images from GHCR..."
    "${COMPOSE_CMD[@]}" pull --ignore-pull-failures || true
fi

# 6. スタック起動
log_info "Step 5/5: Starting LibreChat RCE Stack..."
if ! "${COMPOSE_CMD[@]}" up -d; then
    log_error "Failed to start Docker Compose stack."
    log_info "Collecting container status and logs for diagnostics..."
    "${COMPOSE_CMD[@]}" ps -a || true
    "${COMPOSE_CMD[@]}" logs --tail 50 sandbox-runner || true
    die "Docker Compose startup failed. Please inspect the logs above."
fi

# 7. ヘルスチェック待機
log_info "Waiting for container orchestration to become healthy..."
bash "${PROJECT_ROOT}/scripts/healthcheck.sh" 30 5

echo ""
echo "===================================================================="
log_success "LibreChat RCE Stack is up and ready!"
echo "Access URL: https://${DOMAIN}"
echo "===================================================================="
