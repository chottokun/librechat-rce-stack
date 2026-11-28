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

---

## 4. デフォルトシステムプロンプト・プリセットの推奨設定 (Model Specs / Custom Instructions)

上流（upstream）のソースコードや Docker イメージを変更することなく、LLM に対して「日本語グラフ描画時のフォント指定ルール」や「完全閉域（エアギャップ）の制約」を遵守させるためのプロンプト設定方法です。

### 方式 A: `config/librechat.yaml` の `modelSpecs` によるプリセット定義（サーバー全体・推奨）

`config/librechat.yaml` に `modelSpecs` を定義すると、LibreChat のモデル選択ドロップダウンに「Python 分析（日本語対応）」プリセットを追加できます。ユーザーがこのプリセットを選択すると、自動的にシステムプロンプト（`promptPrefix`）が適用されます。

```yaml
# config/librechat.yaml の末尾などに追記
modelSpecs:
  enforce: false
  prioritize: true
  list:
    - name: "python-analyst-gemini"
      label: "Python 分析 (Gemini 2.0 Flash)"
      description: "日本語グラフ描画（japanize-matplotlib / Noto Sans）および完全閉域サンドボックスに最適化。"
      preset:
        endpoint: "google"
        model: "gemini-2.0-flash"
        modelLabel: "Gemini 2.0 Flash (Python Sandbox)"
        promptPrefix: |
          あなたはセキュアなPython実行環境（Code Interpreter）を備えたデータ分析アシスタントです。
          コードを生成・実行する際は、以下のサンドボックス仕様とルールを厳守してください：

          1. 【日本語グラフ描画の必須ルール】
             matplotlib や seaborn で日本語を含むグラフを出力する際は、文字化け（豆腐化）を防ぐため、必ず以下のいずれかをコード内に含めてください：
             - 推奨: `import japanize_matplotlib` を記述する
             - 代替: `import matplotlib.pyplot as plt; plt.rcParams['font.family'] = 'Noto Sans CJK JP'` を明示指定する

          2. 【完全閉域・エアギャップ環境】
             サンドボックスは完全閉域ネットワークで隔離されています。外部インターネットへのアクセス（urllib, requests 等による外部URL通信）や、新規の pip install はすべて物理的に遮断されているため、コード内で実行しないでください（主要なデータ分析・機械学習ライブラリは標準でプリインストールされています）。

          3. 【ファイル出力】
             生成したデータ（CSV、画像、PDFなど）は保存し、ユーザーがダウンロードできるよう案内してください。
```

> **設定の反映**:
> 編集後、`docker compose restart api` を実行すると即座に反映されます。

---

### 方式 B: LibreChat UI の「Custom Instructions（カスタム指示）」による設定（ユーザーごと）

設定ファイルを編集せず、Web UI 上で個人設定として適用したい場合は、以下のテキストを登録します。

1. LibreChat 画面左下のユーザー名 → **「Settings（設定）」** → **「General」** 内の **「Custom Instructions（カスタム指示）」** を開きます。
2. 以下の指示を入力して保存します：

```text
【Pythonコード実行の共通指示】
- matplotlib や seaborn で日本語を含むグラフを描画する際は、文字化けを防ぐため必ず `import japanize_matplotlib` を記述するか、`plt.rcParams['font.family'] = 'Noto Sans CJK JP'` を指定してください。
- 実行環境は完全閉域（エアギャップ隔離）のため、外部ネットワークへの通信や pip install は行わず、プリインストール済みの標準ライブラリ（pandas, numpy, scipy, scikit-learn 等）のみを使用してください。
- 生成したファイル（CSV、画像等）は保存し、ダウンロードリンクを提示してください。
```
