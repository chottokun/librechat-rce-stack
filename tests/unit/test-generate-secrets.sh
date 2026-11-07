#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test-generate-secrets.sh
# generate-secrets.sh の単体テスト（冪等性・Ed25519鍵署名検証）
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP}"' EXIT

cd "${TEST_TMP}"

echo "=== Test 1: 初回実行で .env 生成と全キー生成確認 ==="
cp "${PROJECT_ROOT}/.env.example" .env.example
# スクリプトを複製して隔離実行
mkdir -p scripts/lib
cp "${PROJECT_ROOT}/scripts/lib/common.sh" scripts/lib/
cp "${PROJECT_ROOT}/scripts/generate-secrets.sh" scripts/
chmod +x scripts/generate-secrets.sh

./scripts/generate-secrets.sh

# 必須キーの非空チェック
REQUIRED_KEYS=(
    "JWT_SECRET"
    "JWT_REFRESH_SECRET"
    "CREDS_KEY"
    "CREDS_IV"
    "REDIS_PASSWORD"
    "MINIO_ROOT_PASSWORD"
    "CODEAPI_INTERNAL_SERVICE_TOKEN"
    "CODEAPI_EGRESS_GRANT_SECRET"
    "CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY"
    "SANDBOX_EXECUTION_MANIFEST_PUBLIC_KEY"
    "CODEAPI_JWT_PRIVATE_JWK_JSON"
    "CODEAPI_JWT_JWKS_JSON"
    "CODEAPI_JWT_KID"
)

for k in "${REQUIRED_KEYS[@]}"; do
    val=$(grep -E "^${k}=" .env | cut -d'=' -f2-)
    if [[ -z "${val}" ]]; then
        echo "FAILED: Key ${k} is empty" >&2
        exit 1
    fi
done
echo "PASS: All required keys generated"

echo "=== Test 2: 2回目実行時の冪等性（既存値が不変であること） ==="
HASH1=$(sha256sum .env | cut -d' ' -f1)
./scripts/generate-secrets.sh
HASH2=$(sha256sum .env | cut -d' ' -f1)

if [[ "${HASH1}" != "${HASH2}" ]]; then
    echo "FAILED: generate-secrets.sh is not idempotent! Hash changed." >&2
    diff <(sha256sum .env) <(echo "${HASH1}")
    exit 1
fi
echo "PASS: Idempotency verified (.env hash identical across runs)"

echo "=== Test 3: Ed25519 Manifest 鍵ペアの署名・検証テスト ==="
MANIFEST_PRIV=$(grep -E "^CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY=" .env | cut -d'=' -f2-)
MANIFEST_PUB=$(grep -E "^SANDBOX_EXECUTION_MANIFEST_PUBLIC_KEY=" .env | cut -d'=' -f2-)

echo "${MANIFEST_PRIV}" | openssl base64 -d > priv.der
echo "${MANIFEST_PUB}" | openssl base64 -d > pub.der

echo "sample manifest payload" > payload.txt
openssl pkey -inform DER -in priv.der -out priv.pem >/dev/null 2>&1
openssl pkey -pubin -inform DER -in pub.der -out pub.pem >/dev/null 2>&1
openssl pkeyutl -sign -rawin -inkey priv.pem -in payload.txt -out payload.sig
openssl pkeyutl -verify -rawin -pubin -inkey pub.pem -in payload.txt -sigfile payload.sig >/dev/null 2>&1
echo "PASS: Manifest Ed25519 signature round-trip verified"

echo "=== Test 4: Ed25519 JWT JWK 整合性テスト ==="
JWT_PRIV_JWK=$(grep -E "^CODEAPI_JWT_PRIVATE_JWK_JSON=" .env | cut -d'=' -f2-)
JWT_JWKS=$(grep -E "^CODEAPI_JWT_JWKS_JSON=" .env | cut -d'=' -f2-)

# jq / python で JSON 妥当性確認
python3 -c "
import json
priv = json.loads('''${JWT_PRIV_JWK}''')
jwks = json.loads('''${JWT_JWKS}''')
assert priv['kty'] == 'OKP'
assert priv['crv'] == 'Ed25519'
assert len(priv['d']) > 40
assert len(priv['x']) > 40
assert jwks['keys'][0]['x'] == priv['x']
assert jwks['keys'][0]['kid'] == priv['kid']
print('PASS: JWT JWK & JWKS structure valid')
"

echo "=== Test 5: --rotate manifest で特定鍵のみ再生成されること ==="
OLD_JWT_KID=$(grep -E "^CODEAPI_JWT_KID=" .env | cut -d'=' -f2-)
OLD_MANIFEST_PRIV="${MANIFEST_PRIV}"
./scripts/generate-secrets.sh --rotate manifest
NEW_MANIFEST_PRIV=$(grep -E "^CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY=" .env | cut -d'=' -f2-)
NEW_JWT_KID=$(grep -E "^CODEAPI_JWT_KID=" .env | cut -d'=' -f2-)

if [[ "${OLD_MANIFEST_PRIV}" == "${NEW_MANIFEST_PRIV}" ]]; then
    echo "FAILED: Manifest key was not rotated" >&2
    exit 1
fi
if [[ "${OLD_JWT_KID}" != "${NEW_JWT_KID}" ]]; then
    echo "FAILED: JWT key should NOT have rotated" >&2
    exit 1
fi
echo "PASS: Selective rotation verified"

echo "ALL UNIT TESTS PASSED!"
