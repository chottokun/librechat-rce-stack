---
type: concept
title: LibreChat RCE Stack
description: One-command production-ready LibreChat and Code Interpreter (RCE) stack in an isolated multi-tier network with Ed25519 JWT auth and auto-tracking upstream.
generated: false
status: active
tags: [readme, librechat, rce, sandbox, docker, security]
---

# LibreChat RCE Stack

[![CI](https://github.com/chottokun/librechat-rce-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/chottokun/librechat-rce-stack/actions/workflows/ci.yml)
[![Security Scan](https://github.com/chottokun/librechat-rce-stack/actions/workflows/security.yml/badge.svg)](https://github.com/chottokun/librechat-rce-stack/actions/workflows/security.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[English](#english) | [日本語](#japanese)

---

<a name="japanese"></a>
## 日本語

### 概要
**LibreChat RCE Stack** は、堅牢な3層隔離ネットワーク設計を基盤とし、公式 GHCR コンテナイメージと Ed25519 非対称鍵 JWT 認証を統合した、ワンコマンド起動対応のエンタープライズ・自閉環境向け AI プラットフォームです。

- **ワンコマンド起動 (`./setup.sh`)**: 暗号論的乱数シークレット、Ed25519 JWT/マニフェスト鍵ペア、自己署名SSL証明書の初回自動生成・冪等保持。
- **公式イメージ + ゼロビルド運用**: Code Interpreter の中核5サービスは上流公式 GHCR イメージ（`sha-` 固定）を直接 pull。
- **日本語グラフ描画対応 Sandbox (案D)**: IPAex フォント同梱の `japanize-matplotlib` を事前組み込みした Sandbox Runner を GitHub Actions CI でビルドし、自前 GHCR から配信。
- **3層完全分離ネットワーク**: `public-frontend`（Nginx/Web層）、`rce-backend`（API連携層）、`rce-isolated`（外部通信遮断・`internal: true` の実行層）。
- **ゼロトラスト認証**: 廃止推奨の `LOCAL_MODE=true`（認証バイパス）を排除し、LibreChat が発行する短命 Ed25519 Bearer JWT（`librechat-jwt`）でセッション・ユーザー単位の完全分離を実現。
- **継続的セキュリティ & 上流自動追従**: CI での Trivy スキャン・SBOM 生成・Cosign 署名、および `upstream.lock` による上流コミットの自動検知 PR ワークフロー。

### クイックスタート

```bash
# 1. クローン
git clone https://github.com/chottokun/librechat-rce-stack.git
cd librechat-rce-stack

# 2. ワンコマンドセットアップ（KVM自動判定・鍵自動生成・証明書発行・コンテナ起動）
./setup.sh

# 3. ブラウザでアクセス
# https://localhost
```

---

<a name="english"></a>
## English

### Overview
**LibreChat RCE Stack** is a production-grade, one-command deployment of LibreChat and the Sandboxed Code Interpreter (RCE), built upon an enterprise 3-tier isolated network architecture with official GHCR images and Ed25519 JWT zero-trust authentication.

- **One-Command Setup (`./setup.sh`)**: Auto-provisions cryptographic secrets, Ed25519 JWT/manifest key pairs, and SSL certificates idempotently.
- **Official GHCR Images**: Core Code Interpreter services run directly from upstream immutable `sha-` images.
- **Japanese-Ready Sandbox Runner**: Pre-bakes `japanize-matplotlib` (with IPAex fonts) via GitHub Actions CI and delivers prebuilt images from GHCR.
- **3-Tier Network Isolation**: `public-frontend` (Nginx/Web), `rce-backend` (API bridge), and `rce-isolated` (`internal: true`, fully air-gapped execution plane).
- **Zero-Trust JWT Auth**: Eliminates unauthenticated `LOCAL_MODE=true`, enforcing per-request Ed25519 signed JWTs (`librechat-jwt`).
- **Continuous Security**: Trivy scanning, SBOM, Cosign keyless signatures, and automated upstream tracking via `upstream.lock`.

### Quick Start

```bash
git clone https://github.com/chottokun/librechat-rce-stack.git
cd librechat-rce-stack
./setup.sh
# Open https://localhost
```

---

## License / ライセンス
[MIT License](LICENSE) (c) 2026 chottokun
