#!/usr/bin/env bash
# ==============================================================================
# scripts/generate-secrets.sh
# ゼロトラスト暗号論的シークレットおよび Ed25519 非対称鍵ペア自動生成スクリプト
# ==============================================================================
# 機能:
#   1. .env が未存在の場合は .env.example よりコピー
#   2. 未設定またはプレースホルダのキーのみをランダム生成（既存値は保持 = 冪等）
#   3. LibreChat 署名用 (JWT_SECRET, CREDS_KEY, CREDS_IV)
#   4. 各種パスワード (REDIS, MINIO, 内部サービストークン)
#   5. サンドボックス実行マニフェスト鍵ペア (Ed25519 PKCS#8 / SPKI DER Base64)
#   6. LibreChat ↔ CodeAPI 連携用 Ed25519 JWK / JWKS (EdDSA)
#   7. オプション: --rotate <KEY|jwt|manifest|all> での明示的ローテーション
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROJECT_ROOT="$(get_project_root)"
ENV_FILE="${PROJECT_ROOT}/.env"
ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"

require_cmd openssl

# base64url エンコード (パディング '=' なし、'+' -> '-', '/' -> '_')
base64url_encode() {
    openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

# .env ファイルの存在保証
ensure_env_file() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        if [[ -f "${ENV_EXAMPLE}" ]]; then
            cp "${ENV_EXAMPLE}" "${ENV_FILE}"
            chmod 600 "${ENV_FILE}"
            log_info "Created .env from .env.example"
        else
            touch "${ENV_FILE}"
            chmod 600 "${ENV_FILE}"
            log_info "Created new empty .env"
        fi
    fi
}

# .env 内の変数値を取得
get_env_val() {
    local key="$1"
    grep -E "^[[:space:]]*${key}=" "${ENV_FILE}" 2>/dev/null | head -n1 | cut -d'=' -f2- || true
}

# .env 内の変数を更新（存在すれば置換、なければ末尾追記）
set_env_val() {
    local key="$1"
    local val="$2"
    local tmp_file
    tmp_file="$(mktemp)"
    
    if grep -q -E "^[[:space:]]*${key}=" "${ENV_FILE}"; then
        awk -v k="${key}" -v v="${val}" 'BEGIN {FS="="} $1 ~ "^[[:space:]]*"k"$" {print k"="v; next} {print}' "${ENV_FILE}" > "${tmp_file}"
        mv "${tmp_file}" "${ENV_FILE}"
    else
        cat "${ENV_FILE}" > "${tmp_file}"
        echo "${key}=${val}" >> "${tmp_file}"
        mv "${tmp_file}" "${ENV_FILE}"
    fi
    chmod 600 "${ENV_FILE}"
}

# Ed25519 Manifest 鍵ペア生成 (service-worker ↔ sandbox-runner 署名用)
# フォーマット: PKCS#8 DER base64 (private), SPKI DER base64 (public)
generate_manifest_keypair() {
    local workdir priv_pem pub_pem priv_der pub_der priv_b64 pub_b64
    workdir="$(mktemp -d)"
    
    priv_pem="${workdir}/manifest_priv.pem"
    pub_pem="${workdir}/manifest_pub.pem"
    priv_der="${workdir}/manifest_priv.der"
    pub_der="${workdir}/manifest_pub.der"
    
    openssl genpkey -algorithm ed25519 -out "${priv_pem}" >/dev/null 2>&1
    openssl pkey -in "${priv_pem}" -pubout -out "${pub_pem}" >/dev/null 2>&1
    
    openssl pkey -in "${priv_pem}" -outform DER -out "${priv_der}" >/dev/null 2>&1
    openssl pkey -in "${pub_pem}" -pubin -outform DER -out "${pub_der}" >/dev/null 2>&1
    
    priv_b64="$(openssl base64 -in "${priv_der}" -A)"
    pub_b64="$(openssl base64 -in "${pub_der}" -A)"
    
    rm -rf "${workdir}"
    
    set_env_val "CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY" "${priv_b64}"
    set_env_val "SANDBOX_EXECUTION_MANIFEST_PUBLIC_KEY" "${pub_b64}"
    log_success "Generated new Ed25519 Manifest keypair"
}

# Ed25519 JWT 鍵ペア生成 (LibreChat ↔ CodeAPI 相互認証用)
# RFC 8037 (OKP / Ed25519 / EdDSA) 準拠の JWK / JWKS
generate_jwt_keypair() {
    local workdir priv_pem pub_pem priv_der pub_der
    local d_b64url x_b64url kid priv_jwk pub_jwk jwks
    workdir="$(mktemp -d)"
    
    priv_pem="${workdir}/jwt_priv.pem"
    pub_pem="${workdir}/jwt_pub.pem"
    priv_der="${workdir}/jwt_priv.der"
    pub_der="${workdir}/jwt_pub.der"
    
    openssl genpkey -algorithm ed25519 -out "${priv_pem}" >/dev/null 2>&1
    openssl pkey -in "${priv_pem}" -pubout -out "${pub_pem}" >/dev/null 2>&1
    
    openssl pkey -in "${priv_pem}" -outform DER -out "${priv_der}" >/dev/null 2>&1
    openssl pkey -in "${pub_pem}" -pubin -outform DER -out "${pub_der}" >/dev/null 2>&1
    
    # Ed25519 PKCS#8 DER の末尾 32 バイトが秘密鍵シード (d)
    d_b64url="$(tail -c 32 "${priv_der}" | base64url_encode)"
    # Ed25519 SubjectPublicKeyInfo DER の末尾 32 バイトが公開鍵 (x)
    x_b64url="$(tail -c 32 "${pub_der}" | base64url_encode)"
    
    rm -rf "${workdir}"
    
    local today
    today="$(date -u +%Y%m%d)"
    kid="lc-codeapi-${today}"
    
    priv_jwk="{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"d\":\"${d_b64url}\",\"x\":\"${x_b64url}\",\"kid\":\"${kid}\",\"alg\":\"EdDSA\"}"
    pub_jwk="{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"x\":\"${x_b64url}\",\"kid\":\"${kid}\",\"alg\":\"EdDSA\"}"
    jwks="{\"keys\":[${pub_jwk}]}"
    
    set_env_val "CODEAPI_JWT_PRIVATE_JWK_JSON" "${priv_jwk}"
    set_env_val "CODEAPI_JWT_JWKS_JSON" "${jwks}"
    set_env_val "CODEAPI_JWT_KID" "${kid}"
    set_env_val "CODEAPI_JWT_ALGORITHM" "EdDSA"
    set_env_val "CODEAPI_JWT_ISSUER" "librechat"
    set_env_val "CODEAPI_JWT_AUDIENCE" "codeapi"
    set_env_val "CODEAPI_JWT_SINGLE_TENANT_ID" "default"
    log_success "Generated new Ed25519 JWT keypair (JWK & JWKS, kid=${kid})"
}

main() {
    local rotate_target=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rotate)
                rotate_target="${2:-all}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    ensure_env_file
    
    log_info "Checking cryptographic secrets and Ed25519 keys..."
    
    # 1. JWT_SECRET (32 hex bytes)
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "JWT_SECRET" || -z "$(get_env_val "JWT_SECRET")" ]]; then
        set_env_val "JWT_SECRET" "$(openssl rand -hex 32)"
        log_success "Generated JWT_SECRET"
    fi
    
    # 2. JWT_REFRESH_SECRET (32 hex bytes)
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "JWT_REFRESH_SECRET" || -z "$(get_env_val "JWT_REFRESH_SECRET")" ]]; then
        set_env_val "JWT_REFRESH_SECRET" "$(openssl rand -hex 32)"
        log_success "Generated JWT_REFRESH_SECRET"
    fi
    
    # 3. CREDS_KEY (64 hex characters = 32 bytes AES-256)
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "CREDS_KEY" || -z "$(get_env_val "CREDS_KEY")" ]]; then
        set_env_val "CREDS_KEY" "$(openssl rand -hex 32)"
        log_success "Generated CREDS_KEY (AES-256)"
    fi
    
    # 4. CREDS_IV (32 hex characters = 16 bytes AES IV)
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "CREDS_IV" || -z "$(get_env_val "CREDS_IV")" ]]; then
        set_env_val "CREDS_IV" "$(openssl rand -hex 16)"
        log_success "Generated CREDS_IV"
    fi
    
    # 5. REDIS_PASSWORD (32 chars safe)
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "REDIS_PASSWORD" || -z "$(get_env_val "REDIS_PASSWORD")" ]]; then
        set_env_val "REDIS_PASSWORD" "$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"
        log_success "Generated REDIS_PASSWORD"
    fi
    
    # 6. MINIO_ROOT_PASSWORD (32 chars safe)
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "MINIO_ROOT_PASSWORD" || -z "$(get_env_val "MINIO_ROOT_PASSWORD")" ]]; then
        set_env_val "MINIO_ROOT_PASSWORD" "$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"
        log_success "Generated MINIO_ROOT_PASSWORD"
    fi
    
    # 7. CODEAPI_INTERNAL_SERVICE_TOKEN (32 hex bytes)
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "CODEAPI_INTERNAL_SERVICE_TOKEN" || -z "$(get_env_val "CODEAPI_INTERNAL_SERVICE_TOKEN")" || "$(get_env_val "CODEAPI_INTERNAL_SERVICE_TOKEN")" == "localdev-internal-service-token" ]]; then
        set_env_val "CODEAPI_INTERNAL_SERVICE_TOKEN" "$(openssl rand -hex 32)"
        log_success "Generated secure CODEAPI_INTERNAL_SERVICE_TOKEN"
    fi
    
    # 8. CODEAPI_EGRESS_GRANT_SECRET (32 hex bytes)
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "CODEAPI_EGRESS_GRANT_SECRET" || -z "$(get_env_val "CODEAPI_EGRESS_GRANT_SECRET")" || "$(get_env_val "CODEAPI_EGRESS_GRANT_SECRET")" =~ localdev ]]; then
        set_env_val "CODEAPI_EGRESS_GRANT_SECRET" "$(openssl rand -hex 32)"
        log_success "Generated secure CODEAPI_EGRESS_GRANT_SECRET"
    fi
    
    # 9. Ed25519 Manifest Keypair
    local known_insecure_manifest_priv="MC4CAQAwBQYDK2VwBCIEIBoxzSJjQ5jTVyuohHtlD+uDGqv/tZ6hQS2CmxuOg2Wn"
    local current_manifest_priv
    current_manifest_priv="$(get_env_val "CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY")"
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "manifest" || -z "${current_manifest_priv}" || "${current_manifest_priv}" == "${known_insecure_manifest_priv}" ]]; then
        if [[ "${current_manifest_priv}" == "${known_insecure_manifest_priv}" ]]; then
            log_warn "Detected known insecure upstream default manifest key! Auto-replacing with fresh Ed25519 keypair..."
        fi
        generate_manifest_keypair
    fi
    
    # 10. Ed25519 JWT Keypair (JWK & JWKS)
    local current_jwt_jwk
    current_jwt_jwk="$(get_env_val "CODEAPI_JWT_PRIVATE_JWK_JSON")"
    if [[ "${rotate_target}" == "all" || "${rotate_target}" == "jwt" || -z "${current_jwt_jwk}" ]]; then
        generate_jwt_keypair
    fi
    
    log_success "All secrets and asymmetric keys are verified and ready in .env"
}

main "$@"
