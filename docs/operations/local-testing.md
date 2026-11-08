---
type: runbook
title: Local Operational Testing Guide / ローカル実働テスト手順書
description: Step-by-step local testing and validation guide for librechat-rce-stack.
generated: false
status: active
tags: [testing, e2e, verification, runbook]
---

# Local Operational Testing Guide / ローカル実働テスト手順書

本手順書は、`librechat-rce-stack` をローカル環境にデプロイし、インフラ健全性、Ed25519 ゼロトラスト認証、完全閉域サンドボックス隔離、日本語フォント描画（Noto Sans CJK JP / japanize-matplotlib）、およびファイル出力を段階的に実機検証するための標準テストランブックです。

---

## 1. 事前準備（動作要件の確認）

### 必要ツール
- **Docker Engine**: 24.0 以上
- **Docker Compose**: v2.20 以上
- **OpenSSL**: v3.0 以上（Ed25519 鍵生成用）
- **curl**: v7.68 以上

### 実行モードの確認（KVM vs Direct）
```bash
# KVM (MicroVM) の利用可否を確認
ls -l /dev/kvm
```
- `/dev/kvm` が存在し、実行ユーザーに読み書き権限がある場合: **KVM MicroVM モード**（最も強固なハードウェア仮想化隔離）
- `/dev/kvm` がない場合（WSL2 の非ネスト環境、macOS、KVM 非対応 VM 等）: **NsJail Direct モード**（Linux Namespace + Seccomp による隔離）
※ `setup.sh` が自動判定して最適な Compose オーバーライドを構成します。手動切り替えも可能です。

---

## 2. リポジトリの取得とワンコマンド初期化

```bash
# 1. リポジトリのクローン
git clone https://github.com/chottokun/librechat-rce-stack.git
cd librechat-rce-stack

# 2. 自動セットアップの実行
./setup.sh
```

### セットアップスクリプトが自動実行する内容:
1. **秘密鍵・公開鍵 JWKS の自動生成** (`.secrets/` 配下):
   - `jwt-private.pem` (Ed25519 署名鍵)
   - `jwt-jwks.json` (CodeAPI 検証用 JWKS)
   - `manifest-private.pem` (サンドボックス実行マニフェスト鍵)
2. **自己署名 TLS 証明書の自動生成** (`config/nginx/certs/`)
3. **環境変数ファイル (`.env`) の自動作成**:
   - `COMPOSE_FILE`（KVM または Direct の自動設定）
   - 各種暗号ランダムトークン・パスワードの自動生成
4. **コンテナ起動とヘルスチェック待機**:
   - 全サービス（Nginx, LibreChat, MongoDB, Redis, MinIO, CodeAPI, Service Worker, Sandbox Runner）の起動確認

---

## 3. インフラ・コンテナの健全性確認

すべてのコンテナが `healthy` または `Up` 状態であることを確認します。

```bash
docker compose ps
```

**期待される出力例:**
```text
NAME                 IMAGE                                                   COMMAND                  SERVICE          CREATED         STATUS                   PORTS
rce-code-api         ghcr.io/danny-avila/librechat-code-api:2fa9f0d...       "docker-entrypoint.s…"   code-api         1 minute ago    Up (healthy)             8080/tcp
rce-librechat        ghcr.io/danny-avila/librechat-dev-api:v0.8.7            "entrypoint.sh npm r…"   librechat        1 minute ago    Up (healthy)             3080/tcp
rce-minio            pgsty/minio:latest                                      "/usr/bin/docker-ent…"   minio            1 minute ago    Up (healthy)             9000/tcp
rce-mongodb          mongo:7.0                                               "docker-entrypoint.s…"   mongodb          1 minute ago    Up (healthy)             27017/tcp
rce-nginx            nginx:alpine                                            "/docker-entrypoint.…"   nginx            1 minute ago    Up (healthy)             0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
rce-redis            redis:7-alpine                                          "docker-entrypoint.s…"   redis            1 minute ago    Up (healthy)             6379/tcp
rce-sandbox-runner   ghcr.io/chottokun/librechat-rce-stack/sandbox-runner... "/entrypoint.sh"        sandbox-runner   1 minute ago    Up (healthy)             
rce-service-worker   ghcr.io/danny-avila/librechat-service-worker:2fa9f0d... "npm run start:work…"   service-worker   1 minute ago    Up (healthy)             
```

---

## 4. ブラウザでの初期セットアップ

1. ブラウザで **`https://localhost`** にアクセスします。
   - ※ 開発用の自己署名証明書のため警告画面が表示されますが、「詳細設定」→「localhost に進む」を選択してください。
2. サインアップ画面で初期管理者アカウントを登録します。
   - メールアドレス（例: `admin@example.com`）
   - パスワード（8文字以上）
3. ログイン後、画面右上の歯車アイコン（設定）またはチャット画面が表示されます。
4. 設定画面（Settings）または `.env` に、利用する LLM の API キー（OpenAI、Anthropic、Google 等）を設定します。
   - ※ ローカル Ollama をご利用の場合は、ホスト側の Ollama（`http://host.docker.internal:11434`）を指定できます。

---

## 5. 実働テストシナリオ

### テスト 1: 基本的なコード実行（Hello World & 計算）
チャット画面でコードインタープリターを有効にして、以下のプロンプトを送信します。

**プロンプト:**
```text
Pythonを使って、1から100までの整数の2乗の合計を計算し、結果を出力してください。
```

**検証ポイント:**
- サンドボックスが起動し、数秒以内に出力 `338350` が返ることを確認。

---

### テスト 2: 完全閉域・エアギャップ遮断（外部通信遮断テスト）
サンドボックスが意図通り外部ネットワークから完全に遮断されていることを実証します。

**プロンプト:**
```text
Pythonで次のコードを実行して、結果を教えてください。
```python
import urllib.request
try:
    response = urllib.request.urlopen("https://example.com", timeout=3)
    print("ONLINE:", response.status)
except Exception as e:
    print("BLOCKED_SUCCESSFULLY:", type(e).__name__, e)
```
```

**検証ポイント:**
- `ONLINE` とならず、**`BLOCKED_SUCCESSFULLY: URLError <urlopen error [Errno 101] Network is unreachable>`** またはタイムアウト例外が出力されること。
- サンドボックス内から外部への通信流出が完全に防止されていることを確認。

---

### テスト 3: 日本語フォント描画（Noto Sans CJK JP ネイティブ描画）
**`japanize_matplotlib` を import しない状態**で、OS ネイティブの日本語フォント（Noto Sans CJK JP）によって日本語グラフが正常に描画されることを確認します。

**プロンプト:**
```text
以下の Python コードを実行してグラフを表示してください。japanize_matplotlib は import せずに実行してください。

```python
import matplotlib.pyplot as plt

categories = ["企画", "開発", "テスト", "運用"]
values = [25, 45, 20, 10]

plt.figure(figsize=(8, 4))
plt.bar(categories, values, color="#3498db")
plt.title("プロジェクト工数配分（日本語ネイティブ描画）", fontsize=14)
plt.xlabel("工程区分", fontsize=12)
plt.ylabel("工数比率 (%)", fontsize=12)
plt.grid(axis='y', linestyle='--', alpha=0.7)
plt.tight_layout()
plt.show()
```
```

**検証ポイント:**
- チャット画面上に棒グラフの画像が出力されること。
- タイトル「プロジェクト工数配分（日本語ネイティブ描画）」、横軸「企画・開発・テスト・運用」、縦軸「工数比率 (%)」が**豆腐（□□□）にならず、美麗なゴシック体で表示されること**。

---

### テスト 4: `japanize-matplotlib` 併用描画
明示的に `japanize_matplotlib` を指定した場合も正常に動作することを確認します。

**プロンプト:**
```text
以下の Python コードを実行して、円グラフを出力してください。

```python
import matplotlib.pyplot as plt
import japanize_matplotlib

labels = ["WebUI (Nginx)", "LibreChat Core", "Code Interpreter", "MinIO Storage"]
sizes = [15, 35, 30, 20]
colors = ["#2ecc71", "#3498db", "#e74c3c", "#f39c12"]

plt.figure(figsize=(6, 6))
plt.pie(sizes, labels=labels, autopct='%1.1f%%', colors=colors, startangle=140)
plt.title("システム構成要素比率")
plt.show()
```
```

**検証ポイント:**
- エラーなく実行され、日本語ラベル付きの円グラフが正常に生成・表示されること。

---

### テスト 5: ファイル生成と MinIO オブジェクトストレージ連携
サンドボックス内で作成した CSV や画像が、MinIO を経由してダウンロード可能か確認します。

**プロンプト:**
```text
Pythonで pandas を使って、ダミーの売上データを生成し、"sales_summary.csv" として保存してください。
保存したファイルのダウンロードリンクを提示してください。
```

**検証ポイント:**
- `sales_summary.csv` が生成され、チャット上でダウンロードリンクが表示されること。
- ダウンロードした CSV ファイルがローカルで正常に開けること。

---

## 6. トラブルシューティング & ログ確認

問題が発生した場合は、以下のコマンドでログを確認します。

```bash
# CodeAPI (認証・ディスパッチ) のログ
docker compose logs --tail=100 -f code-api

# Service Worker (ジョブキュー処理) のログ
docker compose logs --tail=100 -f service-worker

# サンドボックスランナーのログ
docker compose logs --tail=100 -f sandbox-runner

# 全サービスのログ
docker compose logs --tail=50
```

### よくある症状と対処法
1. **ブラウザで「401 Unauthorized」が表示される**:
   - WebUI から CodeAPI を直接叩いた場合は正常な仕様です（LibreChat 経由のみ Ed25519 JWT で認可されます）。
2. **KVM エラー (`/dev/kvm device not found`)**:
   - ホスト環境が KVM に対応していない場合、`COMPOSE_FILE=compose.yaml:compose.direct.yaml` に切り替えて `./setup.sh` を再実行してください。
3. **日本語フォントが豆腐化する場合**:
   - 最新の GHCR イメージが pull されているか確認してください (`docker compose pull sandbox-runner`)。

---

## 7. 停止・再起動・完全リセット

```bash
# サービスの通常停止
docker compose down

# サービスの再起動
docker compose restart

# 全ボリュームデータを含めた完全リセット（初期化前の状態に戻す）
docker compose down -v
rm -rf .env .secrets config/nginx/certs
```
