# Image Registry - ECR, KMS, IAM

このディレクトリは、コンテナイメージレジストリ（ECR）、署名用KMSキー、関連IAMポリシーを管理します。

## 📋 概要

### 作成されるリソース

1. **ECR Repositories** (3個) - コンテナイメージ保存
   - `sample-app-1`
   - `sample-app-2`
   - `sample-app-3`

2. **KMS Key** (1個) - Cosignでのイメージ署名用
   - 非対称キー（RSA_2048）
   - SIGN_VERIFY用途

3. **IAM Policies** (2個)
   - KMS署名権限（特定キー）
   - ECR Push/Pull権限（特定リポジトリ）

### 使用しているモジュール

- **ECR**: [terraform-aws-modules/ecr/aws](https://registry.terraform.io/modules/terraform-aws-modules/ecr/aws/latest)
- **KMS**: [terraform-aws-modules/kms/aws](https://registry.terraform.io/modules/terraform-aws-modules/kms/aws/latest)

---

## 🚀 セットアップ手順

### 前提条件

- ✅ tfstate用S3バケットが作成済み
- ✅ IAMリソース（terraform/iam）が作成済み

---

### Step 1: backend.tf の作成

```bash
cd terraform/image-registry

# テンプレートをコピー
cp backend.tf.example backend.tf

# backend.tf を編集
# <YOUR_BUCKET_NAME> を実際のバケット名に置換
```

**バケット名の確認:**
```bash
aws s3 ls | grep tfstate
# 出力例: sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1
```

---

### Step 2: terraform.tfvars の作成

```bash
# テンプレートをコピー
cp terraform.tfvars.example terraform.tfvars

# terraform.tfvars を編集
```

**必須設定項目:**

```hcl
# tfstate用S3バケット名
tfstate_bucket_name = "sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"

# ECRライフサイクル設定（この数を超えるイメージは削除）
ecr_lifecycle_image_count = 10
```

---

### Step 3: Terraform実行

```bash
# 初期化
terraform init

# 実行計画の確認
terraform plan

# リソース作成
terraform apply
```

---

### Step 4: 出力の確認

```bash
# 全ての出力を表示
terraform output

# デプロイサマリーを表示
terraform output deployment_summary

# GitHub Secrets用の値を表示
terraform output github_secrets
```

---

## 📁 ファイル構成

```
terraform/image-registry/
├── versions.tf              # Terraform/Provider設定
├── backend.tf               # S3 Backend設定（.gitignoreで除外）
├── backend.tf.example       # Backend設定テンプレート
├── providers.tf             # AWSプロバイダー設定
├── data.tf                  # データソース
├── locals.tf                # ローカル変数、ECRリポジトリ定義
├── main.tf                  # ECR、KMS、IAMリソース定義
├── variables.tf             # 変数定義
├── outputs.tf               # 出力定義
├── terraform.tfvars.example # 変数ファイルのサンプル
├── .gitignore               # Git除外設定
└── README.md                # このファイル
```

---

## 🎯 主要な設定

### ECRライフサイクルポリシー

デフォルトで**10個**のイメージを保持します。これを超えるイメージは自動的に削除されます。

**変更方法:**

`terraform.tfvars` で設定：

```hcl
ecr_lifecycle_image_count = 15  # 15個に変更
```

または、`terraform apply` 時に指定：

```bash
terraform apply -var="ecr_lifecycle_image_count=15"
```

**ライフサイクルポリシーの内容:**

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last N images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

---

### KMS Key 設定

**キー仕様:**
- **Key Usage**: `SIGN_VERIFY`（署名専用）
- **Algorithm**: `RSA_2048`
- **Rotation**: 非対応（非対称キーのため）
- **Deletion Window**: 7日（変更可能）

**キーポリシー:**
- Root アカウント: 完全な権限
- GitHub Actions Role: Sign, Verify, GetPublicKey, DescribeKey

---

### ECR設定

**各リポジトリの設定:**
- **Image Tag Mutability**: `MUTABLE`（同じタグで上書き可能）
- **Scan on Push**: `true`（プッシュ時に脆弱性スキャン）
- **Force Delete**: `true`（削除時にイメージがあっても削除可能）

---

## 🔑 GitHub Secrets の設定

Terraform実行後、以下の値をGitHubリポジトリのSecretsに追加してください。

### 設定方法

1. GitHubリポジトリ → **Settings** → **Secrets and variables** → **Actions**
2. **New repository secret** をクリック
3. 以下を追加：

| Name | Value | 取得方法 |
|------|-------|---------|
| `KMS_KEY_ARN` | `arn:aws:kms:...:alias/...` | `terraform output -raw kms_key_alias_arn` （エイリアス推奨） |
| `ECR_REGISTRY` | `123456789012.dkr.ecr.ap-northeast-1.amazonaws.com` | `terraform output -json github_secrets \| jq -r .ECR_REGISTRY` |
| `ECR_REPOSITORY_1` | `sample-app-1` | 固定値 |
| `ECR_REPOSITORY_2` | `sample-app-2` | 固定値 |
| `ECR_REPOSITORY_3` | `sample-app-3` | 固定値 |

**Note**: `AWS_REGION` と `AWS_ROLE_ARN` は terraform/iam で既に設定済みです。

---

## 📝 GitHub Workflow での使用例

```yaml
name: Build, Sign, and Push to ECR

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Install Cosign
        uses: sigstore/cosign-installer@v3

      - name: Build, tag, and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: ${{ secrets.ECR_REPOSITORY_1 }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

      - name: Sign image with Cosign
        env:
          IMAGE: ${{ steps.build.outputs.image }}
          KMS_KEY_ID: ${{ secrets.KMS_KEY_ID }}
        run: |
          cosign sign --key awskms:///$KMS_KEY_ID $IMAGE

      - name: Verify signature
        env:
          IMAGE: ${{ steps.build.outputs.image }}
          KMS_KEY_ID: ${{ secrets.KMS_KEY_ID }}
        run: |
          cosign verify --key awskms:///$KMS_KEY_ID $IMAGE
```

---

## 🔍 確認コマンド

### ECRリポジトリの確認

```bash
# リポジトリ一覧
aws ecr describe-repositories --query 'repositories[*].repositoryName' --output table

# 特定のリポジトリの詳細
aws ecr describe-repositories --repository-names sample-app-1

# イメージ一覧
aws ecr list-images --repository-name sample-app-1

# ライフサイクルポリシーの確認
aws ecr get-lifecycle-policy --repository-name sample-app-1
```

### KMSキーの確認

```bash
# KMS Key IDを取得
KMS_KEY_ID=$(terraform output -raw kms_key_id)

# キーの詳細
aws kms describe-key --key-id $KMS_KEY_ID

# キーポリシーの確認
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default

# パブリックキーの取得
aws kms get-public-key --key-id $KMS_KEY_ID
```

### IAMポリシーの確認

```bash
# アタッチされたポリシー一覧
aws iam list-attached-role-policies --role-name sandbox-ecr-kms-github-actions-role

# 特定のポリシーの内容
POLICY_ARN=$(terraform output -raw kms_cosign_policy_arn)
aws iam get-policy --policy-arn $POLICY_ARN
aws iam get-policy-version --policy-arn $POLICY_ARN --version-id v1
```

---

## 🧪 イメージのプッシュとライフサイクルテスト

### テスト手順

```bash
# 1. ECRログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.ap-northeast-1.amazonaws.com

# 2. テストイメージを複数プッシュ
for i in {1..15}; do
  docker pull alpine:latest
  docker tag alpine:latest \
    123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/sample-app-1:test-$i
  docker push \
    123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/sample-app-1:test-$i
  echo "Pushed image $i"
done

# 3. イメージ数を確認（10個まで保持されることを確認）
aws ecr describe-images \
  --repository-name sample-app-1 \
  --query 'sort_by(imageDetails,& imagePushedAt)[*].[imageTags[0], imagePushedAt]' \
  --output table

# ライフサイクルポリシーの適用は数時間かかる場合があります
```

---

## 🧹 新しいリポジトリの追加

### Step 1: locals.tf を編集

```hcl
ecr_repositories = {
  # 既存のリポジトリ...
  
  # 新しいリポジトリを追加
  sample-app-4 = {
    image_tag_mutability = "MUTABLE"
    scan_on_push         = true
    lifecycle_count      = var.ecr_lifecycle_image_count
  }
}
```

### Step 2: Terraform apply

```bash
terraform plan
terraform apply
```

新しいリポジトリが作成されます！

---

## 🗑️ リソースの削除

```bash
# ECRリポジトリを空にする（force_delete=trueなので不要だが念のため）
aws ecr batch-delete-image \
  --repository-name sample-app-1 \
  --image-ids "$(aws ecr list-images --repository-name sample-app-1 --query 'imageIds[*]' --output json)" \
  || true

# Terraform destroy
terraform destroy
```

**注意**: KMSキーは削除待機期間（デフォルト7日）があります。この期間中は課金されますが、削除をキャンセルすることも可能です。

---

## 🔒 セキュリティ考慮事項

### 1. IAMロールの制限

GitHub Actionsロールは以下に限定されています：
- 特定のKMSキーのみ署名可能
- 特定のECRリポジトリのみアクセス可能

### 2. KMSキーポリシー

キーポリシーで、GitHub Actionsロールのみが署名できるように制限しています。

### 3. ECRリポジトリポリシー

各リポジトリは、GitHub Actionsロールからのアクセスのみを許可しています。

---

## 💰 コスト

### KMSキー
- **月額**: 約 $1/月
- **API呼び出し**: Sign/Verify操作ごとに課金（非常に安価）

### ECR
- **ストレージ**: 約 $0.10/GB/月
- **データ転送**: アウトバウンドのみ課金（インバウンドは無料）

### 想定コスト
```
KMSキー: $1/月
ECR（10GB想定）: $1/月
合計: 約 $2/月
```

---

## 🧪 ローカルでの検証

リソース作成後、ローカルから動作確認を行うことができます。

### 検証スクリプトの実行

```bash
# 基本的な検証（イメージプッシュ、署名、検証）
cd scripts
./verify-ecr-cosign.sh

# ライフサイクルポリシーのテスト（15個のイメージをプッシュ）
./test-ecr-lifecycle.sh 15

# 特定のリポジトリで実行
ECR_REPOSITORY=sample-app-2 ./verify-ecr-cosign.sh
```

### 詳細な手順

- [ローカル検証ガイド](../../docs/local-verification-guide.md) - 詳細な手順
- [コマンドリファレンス](../../docs/command-reference.md) - コマンド一覧

---

## 📚 参考リンク

- [terraform-aws-modules/ecr](https://registry.terraform.io/modules/terraform-aws-modules/ecr/aws/latest)
- [terraform-aws-modules/kms](https://registry.terraform.io/modules/terraform-aws-modules/kms/aws/latest)
- [Cosign with AWS KMS](https://docs.sigstore.dev/cosign/kms_support/)
- [ECR Lifecycle Policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

