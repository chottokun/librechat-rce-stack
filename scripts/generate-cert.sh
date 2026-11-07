#!/usr/bin/env bash
# ==============================================================================
# scripts/generate-cert.sh
# 自己署名 SSL/TLS 証明書生成スクリプト（SAN 拡張対応）
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROJECT_ROOT="$(get_project_root)"
CERT_DIR="${PROJECT_ROOT}/config/nginx/certs"
DOMAIN="${1:-localhost}"
FORCE="${2:-false}"

require_cmd openssl

mkdir -p "${CERT_DIR}"

KEY_FILE="${CERT_DIR}/server.key"
CRT_FILE="${CERT_DIR}/server.crt"

if [[ -f "${KEY_FILE}" && -f "${CRT_FILE}" && "${FORCE}" != "true" && "${FORCE}" != "--force" ]]; then
    log_info "Certificates already exist in ${CERT_DIR}. Use --force to regenerate."
    exit 0
fi

log_info "Generating self-signed SSL/TLS certificate for domain: ${DOMAIN}"

SAN_ENTRY="DNS:${DOMAIN}"
if [[ "${DOMAIN}" != "localhost" ]]; then
    SAN_ENTRY="${SAN_ENTRY},DNS:localhost,IP:127.0.0.1"
else
    SAN_ENTRY="DNS:localhost,IP:127.0.0.1"
fi

CONFIG_FILE="$(mktemp)"
trap 'rm -f "${CONFIG_FILE}"' EXIT

cat > "${CONFIG_FILE}" <<EOF
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_req

[dn]
C  = JP
ST = Tokyo
L  = Chiyoda
O  = Enterprise RCE Lab
OU = Security Engineering
CN = ${DOMAIN}

[v3_req]
subjectAltName = ${SAN_ENTRY}
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "${KEY_FILE}" \
    -out "${CRT_FILE}" \
    -config "${CONFIG_FILE}" >/dev/null 2>&1

chmod 600 "${KEY_FILE}"
chmod 644 "${CRT_FILE}"

log_success "Generated TLS certificates in ${CERT_DIR} (CN=${DOMAIN}, valid for 10 years)"
