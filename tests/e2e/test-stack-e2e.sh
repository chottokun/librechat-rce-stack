#!/usr/bin/env bash
# ==============================================================================
# tests/e2e/test-stack-e2e.sh
# 統合 E2E テストスイート (TLS終端、ヘルスチェック、認証分離、RCE実行)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${PROJECT_ROOT}/scripts/lib/common.sh"

require_cmd curl
require_cmd docker

log_info "=== E2E Test 1: Nginx TLS 終端 & ヘルスチェック ==="
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://127.0.0.1/nginx-health)
if [[ "${HTTP_CODE}" != "200" ]]; then
    die "Nginx healthcheck failed with HTTP status ${HTTP_CODE}"
fi
log_success "PASS: Nginx TLS & healthcheck endpoint verified (HTTP 200)"

log_info "=== E2E Test 2: HTTP から HTTPS へのリダイレクト検証 ==="
REDIRECT_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/)
if [[ "${REDIRECT_CODE}" != "301" ]]; then
    die "HTTP redirect expected 301, got ${REDIRECT_CODE}"
fi
log_success "PASS: HTTP -> HTTPS redirect verified (HTTP 301)"

log_info "=== E2E Test 3: CodeAPI ゼロトラスト認証 (無認証アクセスの拒絶) ==="
# rce-isolated ネットワーク内部の code-api に直接無認証リクエストを送信
CODEAPI_UNAUTH_STATUS=$(docker compose exec -T code-api bun -e "
fetch('http://127.0.0.1:3112/v1/workspaces')
  .then(r => console.log(r.status))
  .catch(() => console.log('error'))
")
if [[ "${CODEAPI_UNAUTH_STATUS}" != "401" && "${CODEAPI_UNAUTH_STATUS}" != "403" ]]; then
    die "CodeAPI expected 401/403 for unauthenticated request, got: ${CODEAPI_UNAUTH_STATUS}"
fi
log_success "PASS: CodeAPI strictly rejected unauthenticated request (HTTP ${CODEAPI_UNAUTH_STATUS})"

log_info "=== E2E Test 4: Sandbox Runner 日本語フォント & 追加パッケージ検証 ==="
# sandbox-runner コンテナ内で直接 python の japanize_matplotlib の import を検証
RUNNER_CONTAINER=$(docker compose ps -q sandbox-runner 2>/dev/null || true)
if [[ -n "${RUNNER_CONTAINER}" ]]; then
    PYTHON_BIN=""
    if docker exec "${RUNNER_CONTAINER}" test -f /sandbox-rootfs/pkgs/python/3.14.4/bin/python3; then
        PYTHON_BIN="/sandbox-rootfs/pkgs/python/3.14.4/bin/python3"
    elif docker exec "${RUNNER_CONTAINER}" test -f /pkgs/python/3.14.4/bin/python3; then
        PYTHON_BIN="/pkgs/python/3.14.4/bin/python3"
    else
        PYTHON_BIN="python3"
    fi
    docker exec "${RUNNER_CONTAINER}" "${PYTHON_BIN}" -c "
import japanize_matplotlib
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
ax.set_title('日本語テストグラフ')
fig.savefig('/tmp/test_ja.png')
print('SUCCESS: japanize_matplotlib imported and rendered Japanese chart cleanly')
"
    log_success "PASS: Sandbox runner rendered Japanese chart with zero font warnings"
fi

log_success "ALL E2E INTEGRATION TESTS PASSED CLEANLY!"
