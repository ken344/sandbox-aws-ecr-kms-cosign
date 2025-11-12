# GitHub Secrets 設定ガイド

このドキュメントでは、GitHub Workflowで使用するSecretsの設定方法を説明します。

## 📋 必要なSecrets

| Secret Name | 説明 | 推奨形式 |
|------------|------|----------|
| `AWS_ROLE_ARN` | GitHub ActionsがAssumeするIAMロールのARN | キーARN |
| `KMS_KEY_ARN` | Cosign署名用のKMSキーのARN | **エイリアスARN（推奨）** |

---

## 🔑 KMS Key: エイリアス vs キーID

### エイリアスARN（推奨）✅

```
arn:aws:kms:ap-northeast-1:123456789012:alias/sandbox-ecr-kms/cosign
```

**メリット**:
- ✅ 分かりやすい名前
- ✅ キーローテーション時にエイリアスを付け替えるだけ
- ✅ 環境間で同じ名前を使用可能
- ✅ ドキュメント化が容易

### キーID/キーARN

```
# キーID
6f4d52da-19f9-495a-904f-518c0e7f67e7

# キーARN
arn:aws:kms:ap-northeast-1:123456789012:key/6f4d52da-19f9-495a-904f-518c0e7f67e7
```

**デメリット**:
- ❌ UUIDで読みにくい
- ❌ キーローテーション時にSecrets更新が必要
- ❌ 複数環境での管理が煩雑

---

## 🚀 設定手順

### Step 1: Terraformから値を取得

```bash
cd terraform/iam

# AWS_ROLE_ARN を取得
terraform output -raw github_actions_role_arn
```

**出力例**:
```
arn:aws:iam::123456789012:role/sandbox-ecr-kms-github-actions-role
```

この値をコピーします。

```bash
cd ../image-registry

# KMS_KEY_ARN を取得（エイリアスARN）
terraform output -raw kms_key_alias_arn
```

**出力例**:
```
arn:aws:kms:ap-northeast-1:123456789012:alias/sandbox-ecr-kms/cosign
```

この値もコピーします。

### 便利なコマンド

```bash
# 両方を一度に表示
echo "=== GitHub Secrets 設定値 ==="
echo ""
echo "AWS_ROLE_ARN:"
cd terraform/iam && terraform output -raw github_actions_role_arn
echo ""
echo ""
echo "KMS_KEY_ARN (エイリアスARN):"
cd ../image-registry && terraform output -raw kms_key_alias_arn
echo ""
```

または、`github_secrets` outputを使用：

```bash
cd terraform/image-registry
terraform output -json github_secrets | jq .
```

---

### Step 2: GitHubリポジトリでSecretsを設定

1. **GitHubリポジトリのページを開く**
   ```
   https://github.com/<your-username>/sandbox-aws-ecr-kms-cosign
   ```

2. **Settings タブをクリック**

3. **左サイドバー**から以下を選択：
   - **Secrets and variables** を展開
   - **Actions** をクリック

4. **Secretsを追加**

---

### Secret 1: AWS_ROLE_ARN

1. **New repository secret** ボタンをクリック

2. 入力：
   ```
   Name: AWS_ROLE_ARN
   
   Secret: arn:aws:iam::123456789012:role/sandbox-ecr-kms-github-actions-role
   ```

3. **Add secret** をクリック

---

### Secret 2: KMS_KEY_ARN（エイリアスARN）

1. **New repository secret** ボタンをクリック

2. 入力：
   ```
   Name: KMS_KEY_ARN
   
   Secret: arn:aws:kms:ap-northeast-1:123456789012:alias/sandbox-ecr-kms/cosign
   ```

3. **Add secret** をクリック

---

## ✅ 設定の確認

Secretsページで以下が表示されれば成功：

```
Repository secrets
├── AWS_REGION      (オプション)
├── AWS_ROLE_ARN    ✅ 必須
└── KMS_KEY_ARN     ✅ 必須（エイリアスARN）
```

---

## 🔄 既存のSecretを更新する場合

既に `KMS_KEY_ARN` がキーIDで設定されている場合：

1. `KMS_KEY_ARN` の右側の **鉛筆アイコン**（Edit）をクリック

2. 値をエイリアスARNに変更：
   ```
   変更前: arn:aws:kms:ap-northeast-1:123456789012:key/6f4d52da-19f9-495a-904f-518c0e7f67e7
   
   変更後: arn:aws:kms:ap-northeast-1:123456789012:alias/sandbox-ecr-kms/cosign
   ```

3. **Update secret** をクリック

---

## 💡 エイリアス使用のメリット

### キーローテーションが容易

```bash
# シナリオ: KMSキーをローテーション

# 1. 新しいKMSキーを作成
cd terraform/image-registry
# main.tf でキーを追加

# 2. エイリアスを新しいキーに付け替え
aws kms update-alias \
  --alias-name alias/sandbox-ecr-kms/cosign \
  --target-key-id <new-key-id>

# 3. GitHub Secretsは変更不要！
# エイリアスARNは変わらないため
```

### 複数環境での管理

```yaml
# Dev環境
KMS_KEY_ARN: arn:aws:kms:ap-northeast-1:111111111111:alias/myapp/cosign

# Prod環境
KMS_KEY_ARN: arn:aws:kms:ap-northeast-1:222222222222:alias/myapp/cosign

# 同じエイリアス名で統一可能
```

---

## 🧪 動作確認

### テストWorkflowで確認（オプション）

簡単なWorkflowで動作確認：

```yaml
name: Test KMS Alias

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-northeast-1
      
      - uses: sigstore/cosign-installer@v3
      
      - name: Test KMS key access with alias
        run: |
          echo "Testing KMS key with alias..."
          echo "KMS_KEY_ARN: ${{ secrets.KMS_KEY_ARN }}"
          
          # KMSキー情報を取得（エイリアスで）
          aws kms describe-key --key-id ${{ secrets.KMS_KEY_ARN }}
          
          echo "✅ KMS key accessible with alias"
```

---

## 📚 参考リンク

- [AWS KMS Aliases](https://docs.aws.amazon.com/kms/latest/developerguide/kms-alias.html)
- [Cosign AWS KMS Support](https://docs.sigstore.dev/cosign/key_management/overview/)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-11 | 初版作成、エイリアスARN推奨に変更 |

