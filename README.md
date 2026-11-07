# LibreChat RCE Stack

[![CI](https://github.com/chottokun/librechat-rce-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/chottokun/librechat-rce-stack/actions/workflows/ci.yml)
[![Security Scan](https://github.com/chottokun/librechat-rce-stack/actions/workflows/security.yml/badge.svg)](https://github.com/chottokun/librechat-rce-stack/actions/workflows/security.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[English](#english) | [日本語](#japanese)

---

<a name="japanese"></a>
## 日本語

### 概要
**LibreChat RCE Stack** は、オープンソースの AI チャットインターフェース「LibreChat」と、安全なコード実行機能「Code Interpreter」を統合して構築するための Docker Compose 構成です。

既存環境の知見（Nginx リバースプロキシ、MinIO オブジェクトストレージ、Redis、3層隔離ネットワーク）を整理・再構築し、上流の公式イメージ利用、Ed25519 JWT 相互認証の自動構成、日本語フォント内包ランナーの配信に対応しています。

### 主な特徴

- **ワンコマンド起動 (`./setup.sh`)**: 暗号シークレット、Ed25519 JWT 鍵ペア（JWK/JWKS）、マニフェスト鍵、自己署名証明書を自動生成してコンテナを起動します。
- **KVM / 非KVM 自動判定**: ホストの `/dev/kvm` の有無を検知し、KVM MicroVM 構成または NsJail Direct 構成を自動選択します。
- **公式コンテナイメージの活用**: Code Interpreter の中核サービス（API, Worker, File Server, Egress Gateway, Tool Call Server）は上流公式 GHCR イメージ（コミット SHA 固定）を利用します。
- **日本語グラフ描画対応**: `japanize-matplotlib`（IPAex フォント内包）を追加した Sandbox Runner を GitHub Actions CI でビルドし、GHCR 経由で提供します。
- **3層ネットワーク分離**:
  - `public-frontend`: Nginx および LibreChat Web UI 間の通信層
  - `rce-backend`: LibreChat API と Code API 間の連携層
  - `rce-isolated`: 外部通信を遮断（`internal: true`）したサンドボックス実行層
- **Ed25519 相互認証**: LibreChat と Code API 間の通信は短命な Ed25519 Bearer JWT（`librechat-jwt`）で認証されます。
- **サプライチェーン対策**:
  - `upstream.lock` によるイメージタグと上流コミット SHA の一元固定
  - GitHub Actions での Trivy による脆弱性スキャン（定期実行およびビルド時）
  - Dependabot による GitHub Actions 定期アップデート
  - 上流同期スクリプト（`scripts/upstream-sync.sh`）による更新検知 PR の自動作成

### 動作要件

- OS: Linux（Ubuntu 22.04 / 24.04 等）または macOS（Docker Desktop）
- ツール: Docker 24.0+、Docker Compose v2.20+、Bash、OpenSSL
- メモリ: 4GB 以上推奨（KVM MicroVM 起動時は 6GB 以上推奨）
- 仮想化: `/dev/kvm` が利用可能な場合はハードウェア仮想化（MicroVM）が有効になります。利用できない場合は NsJail Direct モードで起動します。

### セットアップ手順

```bash
# 1. リポジトリをクローン
git clone https://github.com/chottokun/librechat-rce-stack.git
cd librechat-rce-stack

# 2. セットアップスクリプトを実行
./setup.sh

# 3. ブラウザでアクセス
# https://localhost
```

#### スクリプトのオプション

| オプション | 説明 |
| :--- | :--- |
| `--domain <FQDN>` | 公開ドメイン名（デフォルト: `localhost`）。SAN 付き証明書を発行します。 |
| `--build` | GHCR からの pull の代わりに、ローカル環境で Sandbox Runner を自前ビルドします。 |
| `--rotate <target>` | 指定した暗号鍵を再生成します（`all`, `jwt`, `manifest`, `JWT_SECRET` 等）。 |
| `--no-up` | 設定ファイル、秘密情報、証明書の生成のみを行い、コンテナ起動は行いません。 |
| `-h, --help` | ヘルプメッセージを表示します。 |

### ディレクトリ構成

```text
├── compose.yaml          # 基本 Docker Compose 定義
├── compose.kvm.yaml      # KVM MicroVM 用オーバーライド
├── compose.direct.yaml   # NsJail Direct 用オーバーライド
├── upstream.lock         # 上流コミット SHA およびイメージの固定ファイル
├── setup.sh              # 自動セットアップ & 起動スクリプト
├── config/               # Nginx および LibreChat の設定
├── sandbox/              # Sandbox Runner ビルドスクリプト & 追加パッケージパッチ
├── scripts/              # 鍵生成・証明書発行・同期・ヘルスチェック用スクリプト
├── tests/                # 単体テスト (unit) および結合テスト (e2e)
└── docs/                 # 詳細仕様・アーキテクチャ・運用ドキュメント
```

---

<a name="english"></a>
## English

### Overview
**LibreChat RCE Stack** provides an automated Docker Compose deployment for LibreChat and its sandboxed Code Interpreter execution environment.

It brings together an isolated 3-tier network, official upstream container images, Ed25519 JWT mutual authentication, and pre-baked Japanese font support in an automated setup script.

### Key Features

- **One-Command Setup (`./setup.sh`)**: Automatically provisions cryptographic secrets, Ed25519 JWT key pairs (JWK/JWKS), execution manifest keys, and self-signed certificates idempotently.
- **Auto-Detection for Virtualization**: Detects `/dev/kvm` and selects either KVM MicroVM mode or NsJail Direct container isolation mode.
- **Upstream Official Images**: Runs Code Interpreter core services (API, Worker, File Server, Egress Gateway, Tool Call Server) from official GHCR images pinned by commit SHA.
- **Japanese Font Support**: Includes `japanize-matplotlib` (with embedded IPAex fonts) pre-baked into the Sandbox Runner image and distributed via GHCR.
- **3-Tier Network Architecture**:
  - `public-frontend`: Ingress from Nginx to LibreChat UI
  - `rce-backend`: Bridge between LibreChat API and Code API
  - `rce-isolated`: Sandboxed runtime layer (`internal: true`) with no direct external access
- **Ed25519 Mutual Auth**: Authenticates API requests between LibreChat and Code API with ephemeral Ed25519 Bearer JWTs (`librechat-jwt`).
- **Supply Chain Security**:
  - Immutable commit SHAs and container image digests pinned in `upstream.lock`
  - Automated Trivy vulnerability scans in CI and scheduled workflows
  - Dependabot updates for GitHub Actions
  - Upstream sync script (`scripts/upstream-sync.sh`) to detect and propose upstream updates via PR

### Requirements

- OS: Linux (Ubuntu 22.04 / 24.04 recommended) or macOS (Docker Desktop)
- Tools: Docker 24.0+, Docker Compose v2.20+, Bash, OpenSSL
- RAM: 4GB minimum (6GB+ recommended with KVM MicroVM)
- Virtualization: Access to `/dev/kvm` activates MicroVM hardware virtualization; otherwise NsJail Direct mode is used.

### Quick Start

```bash
git clone https://github.com/chottokun/librechat-rce-stack.git
cd librechat-rce-stack
./setup.sh
# Open https://localhost in your browser
```

---

## License / ライセンス
[MIT License](LICENSE) (c) 2026 chottokun
