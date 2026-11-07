---
type: concept
title: Operation & Maintenance Guide
description: Daily operations, secret rotation, offline air-gap deployment, and custom package additions.
generated: false
status: active
tags: [operations, maintenance, runbook]
---

# Operation Guide / 運用・保守ガイド

## 1. 日常の運用コマンド

### サービスの起動・停止
```bash
# 起動
./setup.sh

# 停止
docker compose down

# 再起動
docker compose restart
```

### シークレットの安全なローテーション
```bash
# 全シークレット & 全鍵ペアの再生成
./setup.sh --rotate all

# JWT 認証鍵ペアのみ再生成
./setup.sh --rotate jwt

# サンドボックス実行マニフェスト鍵ペアのみ再生成
./setup.sh --rotate manifest
```

---

## 2. 独自 Python ライブラリ / パッケージの追加 (設置者向け)

1. `sandbox/requirements-extra.txt` に追加したいパッケージをバージョン固定で記述します。
   ```text
   japanize-matplotlib==1.1.3
   lightgbm==4.5.0
   ```
2. 必要に応じて `sandbox/apt-extra.txt` にシステムライブラリ（`libgomp1` など）を追加します。
3. `--build` オプションを付けてセットアップを実行します。
   ```bash
   ./setup.sh --build
   ```
   ローカルで新しい Sandbox Runner イメージがビルドされ、即座に反映されます。

---

## 3. 完全オフライン（閉域環境）へのデプロイ

インターネット接続環境で事前にイメージをエクスポートし、閉域環境へ持ち込みます。

```bash
# 1. イメージの pull & 保存 (接続環境)
docker compose --env-file upstream.lock pull
docker save $(docker compose --env-file upstream.lock config --images) -o rce-stack-images.tar

# 2. 閉域環境でのロード
docker load -i rce-stack-images.tar

# 3. 閉域環境での起動
./setup.sh
```
