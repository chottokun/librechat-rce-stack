#!/usr/bin/env bash
# ==============================================================================
# scripts/healthcheck.sh
# 全コンテナの起動・ヘルスチェック待機スクリプト
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MAX_ATTEMPTS="${1:-40}"
SLEEP_INTERVAL="${2:-5}"

require_cmd docker

log_info "Waiting for all services to become healthy (max ${MAX_ATTEMPTS} attempts)..."

for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    unhealthy_containers=$(docker compose ps -a --format '{{.Name}}: {{.Health}}' 2>/dev/null | grep -E "unhealthy|starting" || true)
    healthy_count=$(docker compose ps -a --format '{{.Health}}' 2>/dev/null | grep -c "healthy" || true)
    total_count=$(docker compose ps -a --format '{{.Name}}' 2>/dev/null | grep -v -c "minio-init" || true)
    
    if [[ "${unhealthy_containers}" == "" && "${healthy_count}" -ge "${total_count}" && "${total_count}" -gt 0 ]]; then
        log_success "All services are healthy! (${healthy_count}/${total_count})"
        docker compose ps
        exit 0
    fi
    
    log_info "Attempt ${attempt}/${MAX_ATTEMPTS}: Healthy containers ${healthy_count}/${total_count}. Waiting..."
    sleep "${SLEEP_INTERVAL}"
done

log_error "Healthcheck timed out! Inspecting container statuses:"
docker compose ps -a
docker compose logs --tail 50
exit 1
