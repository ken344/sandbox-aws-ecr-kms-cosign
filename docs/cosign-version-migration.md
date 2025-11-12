# Cosign バージョン移行ガイド - v2.x から v3.x へ

このドキュメントでは、Cosign v2.x から v3.x への移行に関する変更点と対処方法を説明します。

## 📋 目次

- [概要](#概要)
- [主な変更点](#主な変更点)
- [このプロジェクトでの対応](#このプロジェクトでの対応)
- [移行手順](#移行手順)
- [トラブルシューティング](#トラブルシューティング)
- [参考リンク](#参考リンク)

---

## 概要

### バージョン情報

| バージョン | リリース日 | ステータス |
|-----------|-----------|----------|
| v2.2.4 | 2024年 | 安定版 |
| v3.0.0 | 2024年後半 | 最新メジャーバージョン |
| v3.0.2 | 2024年末 | 現在の推奨版 |

### 互換性

- v2.x と v3.x は基本的に**互換性あり**
- AWS KMS使用時は特に問題なし
- 一部のオプションが非推奨化
- Transparency Log（Rekor）の扱いに変更

---

## 主な変更点

### 1. Transparency Log (Rekor) の扱い

#### v2.x のデフォルト動作

```bash
cosign sign --key awskms:///... image@sha256:...

# デフォルトでRekorにアップロードを試みる
# プライベートレジストリでは警告が出るが続行
```

#### v3.x のデフォルト動作

```bash
cosign sign --key awskms:///... image@sha256:...

# Rekorへのアップロード動作が変更
# 環境によっては明示的な指定が必要
```

**対処方法**:

```bash
# プライベートレジストリの場合は明示的にスキップ
cosign sign --key awskms:///... --tlog-upload=false image@sha256:...
```

---

### 2. コマンドラインオプションの変更

#### 非推奨になったオプション

| オプション | v2.x | v3.x | 代替 |
|-----------|------|------|------|
| `--force` | 有効 | 非推奨 | `--yes` |
| `--upload` | 有効 | 削除 | `--tlog-upload` |

#### 新しいオプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--tlog-upload` | Transparency Logへのアップロード | `true` |
| `--insecure-ignore-tlog` | 検証時にRekorを無視 | `false` |

---

### 3. 検証（verify）の動作変更

#### v2.x

```bash
cosign verify --key awskms:///... image@sha256:...

# Rekorの存在を確認するが、なくても続行
```

#### v3.x

```bash
cosign verify --key awskms:///... image@sha256:...

# Rekorの扱いが厳密に
# プライベート環境では以下を追加
cosign verify --key awskms:///... --insecure-ignore-tlog image@sha256:...
```

---

### 4. AWS KMS サポート

#### 両バージョン共通

AWS KMSの基本的な使用方法は**変更なし**：

```bash
# v2.x
cosign sign --key awskms:///arn:aws:kms:... image@sha256:...

# v3.x
cosign sign --key awskms:///arn:aws:kms:... image@sha256:...

# どちらも動作 ✅
```

---

## このプロジェクトでの対応

### 現在の設定

#### GitHub Workflows

```yaml
# .github/workflows/single-image-test.yml
- name: Install Cosign
  uses: sigstore/cosign-installer@v3
  with:
    cosign-release: 'v3.0.2'  # v3.x を使用
```

#### 署名コマンド

```bash
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --annotations="..." \
  --yes \
  $IMAGE_URI
```

**現状**: 
- ✅ v3.0.2 で動作確認済み
- ✅ AWS KMS使用時は追加オプション不要
- ✅ プライベートECRでも問題なし

---

### 推奨される設定（より明示的）

#### オプションA: 最小限（現在の設定）

```bash
# 現在の設定（動作する）
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE_URI
```

**メリット**:
- シンプル
- v2とv3で動作

**デメリット**:
- Rekorへのアップロード試行（失敗しても続行）
- ログに警告が出る可能性

---

#### オプションB: 明示的な設定（推奨）

```bash
# 明示的にRekorをスキップ
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --yes \
  --tlog-upload=false \
  $IMAGE_URI

# 検証時も明示的
cosign verify \
  --key awskms:///$KMS_KEY_ARN \
  --insecure-ignore-tlog \
  $IMAGE_URI
```

**メリット**:
- 意図が明確
- 不要なネットワーク試行なし
- ログがクリーン

**デメリット**:
- コマンドが少し長い
- v3専用（v2では一部のオプションが使えない）

---

## 移行手順

### Step 1: バージョン確認

```bash
# ローカル環境
cosign version

# 出力例:
#   GitVersion:    v3.0.2
#   GitCommit:     ...
```

### Step 2: Workflowのバージョン指定

```yaml
# .github/workflows/*.yml

- name: Install Cosign
  uses: sigstore/cosign-installer@v3
  with:
    cosign-release: 'v3.0.2'  # 明示的にバージョン指定
```

**推奨**:
- `v3.0.2` のように具体的なバージョンを指定
- `v3` や `latest` は避ける（予期しない変更を防ぐ）

---

### Step 3: 署名コマンドの更新（オプション）

#### 最小限の対応（現在の設定）

```bash
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE_URI
```

このままでOK（動作確認済み）

#### より明示的な設定

```bash
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --yes \
  --tlog-upload=false \
  $IMAGE_URI
```

---

### Step 4: 検証コマンドの確認

```bash
# 現在の設定
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI

# より明示的（プライベート環境）
cosign verify \
  --key awskms:///$KMS_KEY_ARN \
  --insecure-ignore-tlog \
  $IMAGE_URI
```

**注意**: `--insecure-ignore-tlog` は、Transparency Logを使わない場合に推奨

---

## トラブルシューティング

### 問題1: Rekor 関連のエラー

**症状**:
```
Error: getting Rekor entries: ...
Warning: transparency log entry not found
```

**原因**: プライベートレジストリでRekorを使用できない

**解決方法**:

```bash
# 署名時
cosign sign --key awskms:///$KMS_KEY_ARN --yes --tlog-upload=false $IMAGE_URI

# 検証時
cosign verify --key awskms:///$KMS_KEY_ARN --insecure-ignore-tlog $IMAGE_URI
```

---

### 問題2: `--force` オプションのエラー

**症状**:
```
Error: unknown flag: --force
```

**原因**: v3.xで `--force` が削除された

**解決方法**:

```bash
# ❌ v2.x
cosign sign --key ... --force

# ✅ v3.x
cosign sign --key ... --yes
```

---

### 問題3: 署名の検証失敗

**症状**:
```
Error: no signatures found
```

**原因1**: v2で署名したイメージをv3で検証（またはその逆）

**解決方法**: 基本的に互換性あり。以下を確認：

```bash
# 署名が存在するか確認
cosign triangulate $IMAGE_URI

# ECR上の署名イメージを確認
aws ecr describe-images \
  --repository-name $REPO \
  --query 'imageDetails[?imageTags && contains(to_string(imageTags), `.sig`)]'
```

**原因2**: キーまたはエイリアスが間違っている

**解決方法**:

```bash
# キーにアクセスできるか確認
aws kms describe-key --key-id $KMS_KEY_ARN

# エイリアスが正しいか確認
aws kms list-aliases | grep sandbox
```

---

### 問題4: AWS認証エラー

**症状**:
```
Error: getting public key: operation error KMS: GetPublicKey, https response error
```

**原因**: IAMポリシーに権限がない

**解決方法**:

```bash
# IAMポリシーを確認
aws iam get-role-policy --role-name ... --policy-name ...

# 必要な権限:
# - kms:Sign
# - kms:GetPublicKey
# - kms:DescribeKey
```

---

## ベストプラクティス

### 1. バージョンを固定

```yaml
# ✅ Good
cosign-release: 'v3.0.2'

# ❌ Avoid
cosign-release: 'v3'
cosign-release: 'latest'
```

### 2. プライベートレジストリでは明示的にRekorをスキップ

```bash
# 署名
cosign sign --key awskms:///$KMS_KEY_ARN --yes --tlog-upload=false $IMAGE

# 検証
cosign verify --key awskms:///$KMS_KEY_ARN --insecure-ignore-tlog $IMAGE
```

### 3. ログを確認

```bash
# デバッグモード
export COSIGN_EXPERIMENTAL=1
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE
```

---

## v2.x と v3.x の比較表

| 機能 | v2.x | v3.x | 推奨設定 |
|------|------|------|---------|
| AWS KMS署名 | ✅ | ✅ | 変更不要 |
| `--yes` オプション | ✅ | ✅ | そのまま使用 |
| `--force` オプション | ✅ | ❌ | `--yes` に変更 |
| Rekorアップロード | デフォルト試行 | デフォルト試行 | `--tlog-upload=false` 推奨 |
| Rekor検証 | 柔軟 | 厳密 | `--insecure-ignore-tlog` 推奨 |
| エイリアス対応 | ✅ | ✅ | 変更不要 |
| アノテーション | ✅ | ✅ | 変更不要 |

---

## GitHub Actions での推奨設定

### 完全な例

```yaml
- name: Install Cosign
  uses: sigstore/cosign-installer@v3
  with:
    cosign-release: 'v3.0.2'

- name: Sign image
  run: |
    cosign sign \
      --key awskms:///${{ secrets.KMS_KEY_ARN }} \
      --annotations="workflow-run=${{ github.run_number }}" \
      --annotations="git-sha=${{ github.sha }}" \
      --yes \
      --tlog-upload=false \
      $IMAGE_URI_WITH_DIGEST

- name: Verify signature
  run: |
    cosign verify \
      --key awskms:///${{ secrets.KMS_KEY_ARN }} \
      --insecure-ignore-tlog \
      $IMAGE_URI_WITH_DIGEST
```

---

## ローカル環境での対応

### インストール

```bash
# Homebrew（最新版）
brew install cosign

# 特定バージョン
brew install cosign@3.0.2

# またはバイナリダウンロード
curl -O -L "https://github.com/sigstore/cosign/releases/download/v3.0.2/cosign-darwin-arm64"
sudo mv cosign-darwin-arm64 /usr/local/bin/cosign
sudo chmod +x /usr/local/bin/cosign
```

### バージョン確認

```bash
cosign version
```

### 使用方法

```bash
# v2.x と同じコマンドが基本的に動作
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE_URI

# プライベート環境でRekor警告を避ける場合
cosign sign --key awskms:///$KMS_KEY_ARN --yes --tlog-upload=false $IMAGE_URI
cosign verify --key awskms:///$KMS_KEY_ARN --insecure-ignore-tlog $IMAGE_URI
```

---

## このプロジェクトでの実装

### 現在の設定（v3.0.2）

#### GitHub Workflows

**single-image-test.yml**:
```yaml
cosign-release: 'v3.0.2'
```

**ecr-kms-lifecycle-test.yml**:
```yaml
cosign-release: 'v3.0.2'  # v2.2.4 から更新
```

#### 署名コマンド

```bash
# 現在の実装（シンプル版、動作確認済み）
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE_URI
```

**動作確認**:
- ✅ AWS KMS で正常に署名
- ✅ 検証も成功
- ✅ エイリアス対応

---

### 推奨される改善（オプション）

より明示的にする場合：

```bash
# 署名（Rekorを明示的にスキップ）
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --yes \
  --tlog-upload=false \
  --annotations="..." \
  $IMAGE_URI

# 検証（Rekorを明示的にスキップ）
cosign verify \
  --key awskms:///$KMS_KEY_ARN \
  --insecure-ignore-tlog \
  $IMAGE_URI
```

**メリット**:
- ログがクリーン
- 不要なネットワークアクセスなし
- 意図が明確

---

## 移行チェックリスト

プロジェクトをv2からv3に移行する場合：

- [ ] Cosignバージョンを `v3.0.2` に更新
- [ ] `--force` を `--yes` に変更（該当する場合）
- [ ] プライベートレジストリの場合、`--tlog-upload=false` を追加（推奨）
- [ ] 検証コマンドに `--insecure-ignore-tlog` を追加（必要な場合）
- [ ] ローカル環境のCosignを更新
- [ ] テスト実行で動作確認
- [ ] ドキュメント更新

---

## 環境別の推奨設定

### プライベートレジストリ（ECR等）

```bash
# 署名
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --yes \
  --tlog-upload=false \
  $IMAGE_URI

# 検証
cosign verify \
  --key awskms:///$KMS_KEY_ARN \
  --insecure-ignore-tlog \
  $IMAGE_URI
```

### パブリックレジストリ（Docker Hub等）

```bash
# 署名（Rekorを使用）
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --yes \
  $IMAGE_URI

# 検証（Rekorで確認）
cosign verify \
  --key awskms:///$KMS_KEY_ARN \
  $IMAGE_URI
```

---

## よくある質問

### Q1: v2で署名したイメージはv3で検証できますか？

**A**: はい、可能です。

```bash
# v2で署名
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE_URI

# v3で検証
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI
# ✅ 動作する
```

---

### Q2: v3で署名したイメージはv2で検証できますか？

**A**: 基本的に可能です。

```bash
# v3で署名
cosign sign --key awskms:///$KMS_KEY_ARN --yes --tlog-upload=false $IMAGE_URI

# v2で検証
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI
# ✅ 動作する
```

---

### Q3: `--tlog-upload=false` は必須ですか？

**A**: 必須ではありませんが、プライベートレジストリでは推奨。

```bash
# なくても動作する（警告が出る可能性）
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE_URI

# 明示的にスキップ（推奨）
cosign sign --key awskms:///$KMS_KEY_ARN --yes --tlog-upload=false $IMAGE_URI
```

---

### Q4: エイリアスはv3でも動作しますか？

**A**: はい、完全に動作します。

```bash
# ✅ v2
cosign sign --key awskms:///alias/my-key --yes $IMAGE_URI

# ✅ v3
cosign sign --key awskms:///alias/my-key --yes $IMAGE_URI
```

---

### Q5: アノテーションは？

**A**: 変更なし、そのまま使用可能。

```bash
# v2とv3で同じ
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --annotations="key1=value1" \
  --annotations="key2=value2" \
  --yes \
  $IMAGE_URI
```

---

## パフォーマンスの違い

### 署名速度

| バージョン | 署名速度 | 備考 |
|-----------|---------|------|
| v2.2.4 | ベースライン | - |
| v3.0.2 | ほぼ同じ | 最適化あり |

**結論**: 体感できるほどの差はない

---

### ネットワークアクセス

| 設定 | v2.x | v3.x |
|------|------|------|
| デフォルト | Rekor試行 | Rekor試行 |
| `--tlog-upload=false` | - | スキップ |

プライベート環境では `--tlog-upload=false` でネットワークアクセスを削減できます。

---

## 推奨される最終設定

### このプロジェクトでの推奨

```yaml
# GitHub Workflow
- uses: sigstore/cosign-installer@v3
  with:
    cosign-release: 'v3.0.2'

# 署名（シンプル版、現在の設定）
cosign sign --key awskms:///${{ secrets.KMS_KEY_ARN }} --yes $IMAGE_URI

# 検証
cosign verify --key awskms:///${{ secrets.KMS_KEY_ARN }} $IMAGE_URI
```

**理由**:
- AWS KMS使用時は追加オプション不要
- 動作確認済み
- シンプルで分かりやすい

---

## 参考リンク

### 公式ドキュメント

- [Cosign v3.0.0 Release Notes](https://github.com/sigstore/cosign/releases/tag/v3.0.0)
- [Cosign Documentation](https://docs.sigstore.dev/)
- [Cosign GitHub Repository](https://github.com/sigstore/cosign)
- [Cosign - Signing with KMS](https://github.com/sigstore/cosign/blob/main/KMS.md)
- [Sigstore Blog](https://blog.sigstore.dev/)

### このプロジェクトの関連ドキュメント

- [Transparency Log (Rekor) 詳細ガイド](./transparency-log-rekor.md) - Rekorの仕組みと使用判断
- [GitHub Secrets 設定ガイド](./github-secrets-setup.md) - Secrets設定とエイリアス使用の推奨
- [ローカル検証ガイド](./local-verification-guide.md) - ECR & Cosign署名の検証手順

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-11 | 初版作成（v2.2.4 → v3.0.2 移行ガイド） |

