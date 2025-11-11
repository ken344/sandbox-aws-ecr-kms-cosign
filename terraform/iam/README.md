# IAM リソース - GitHub Actions用

このディレクトリは、GitHub ActionsからAWSリソースにアクセスするためのIAMロールとOIDCプロバイダーを管理します。

## 📋 概要

### 作成されるリソース

1. **OIDC Provider** - GitHub Actions用
2. **IAM Role** - GitHub Actionsが引き受けるロール
3. **IAM Policies**:
   - ECRへのプッシュ権限
   - KMSでの署名権限
   - S3 Artifactsバケットへのアクセス
   - CloudWatch Logsへの書き込み

### 認証フロー

```
GitHub Actions Workflow
  ↓ (OIDC Token)
GitHub OIDC Provider (AWS)
  ↓ (AssumeRoleWithWebIdentity)
IAM Role
  ↓ (一時認証情報)
AWS Services (ECR, KMS, S3)
```

---

## 🚀 セットアップ手順

### 前提条件

- ✅ tfstate用S3バケットが作成済み
- ✅ リソース用S3バケットが作成済み（terraform/tfstate）
- ✅ GitHubリポジトリが存在する

---

### Step 1: backend.tf の作成

```bash
cd terraform/iam

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

# GitHub情報
github_org  = "your-github-username"  # あなたのGitHubユーザー名
github_repo = "sandbox-aws-ecr-kms-cosign"  # リポジトリ名
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

# GitHub Secrets用の値を表示
terraform output github_secrets
```

**出力例:**
```json
{
  "AWS_REGION": "ap-northeast-1",
  "AWS_ROLE_ARN": "arn:aws:iam::123456789012:role/sandbox-ecr-kms-github-actions-role"
}
```

---

## 🔐 GitHub Secrets の設定

Terraform実行後、以下の値をGitHubリポジトリのSecretsに設定してください。

### 設定方法

1. GitHubリポジトリのページを開く
2. **Settings** → **Secrets and variables** → **Actions**
3. **New repository secret** をクリック
4. 以下を追加：

| Name | Value | 取得方法 |
|------|-------|---------|
| `AWS_REGION` | `ap-northeast-1` | `terraform output -raw github_secrets | jq -r .AWS_REGION` |
| `AWS_ROLE_ARN` | `arn:aws:iam::...` | `terraform output -raw github_actions_role_arn` |

---

## 📝 GitHub Workflow での使用例

```yaml
name: Build and Push to ECR

on:
  push:
    branches: [main]

permissions:
  id-token: write  # OIDC用に必要
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
          role-session-name: github-actions-session

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: my-app
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
```

---

## 🔧 設定内容

### OIDC Provider

- **URL**: `https://token.actions.githubusercontent.com`
- **Client ID**: `sts.amazonaws.com`
- **Thumbprints**: GitHub公式の証明書thumbprint

### IAM Role

- **名前**: `sandbox-ecr-kms-github-actions-role`
- **信頼ポリシー**: GitHubリポジトリからのAssumeRoleを許可
- **リポジトリ制限**: 指定したリポジトリのみアクセス可能

### 権限

#### 1. ECRへのアクセス

```
- ecr:GetAuthorizationToken
- ecr:BatchCheckLayerAvailability
- ecr:InitiateLayerUpload
- ecr:UploadLayerPart
- ecr:CompleteLayerUpload
- ecr:PutImage
- ecr:DescribeImages
- ecr:ListImages
```

#### 2. KMS署名

```
- kms:Sign
- kms:Verify
- kms:GetPublicKey
- kms:DescribeKey
```

#### 3. S3 Artifacts

```
- s3:PutObject
- s3:GetObject
- s3:DeleteObject
- s3:ListBucket
```

#### 4. CloudWatch Logs

```
- logs:CreateLogGroup
- logs:CreateLogStream
- logs:PutLogEvents
```

---

## 📁 ファイル構成

```
terraform/iam/
├── versions.tf              # Terraform/Provider設定
├── backend.tf               # S3 Backend設定（.gitignoreで除外）
├── backend.tf.example       # Backend設定テンプレート
├── providers.tf             # AWSプロバイダー設定
├── data.tf                  # データソース
├── locals.tf                # ローカル変数
├── main.tf                  # OIDC、IAMロール、ポリシー定義
├── variables.tf             # 変数定義
├── outputs.tf               # 出力定義
├── terraform.tfvars.example # 変数ファイルのサンプル
├── .gitignore               # Git除外設定
└── README.md                # このファイル
```

---

## 🔍 確認コマンド

### IAMロールの確認

```bash
# ロールARNを取得
ROLE_ARN=$(terraform output -raw github_actions_role_arn)

# ロールの詳細を確認
aws iam get-role --role-name sandbox-ecr-kms-github-actions-role
```

### OIDC Providerの確認

```bash
# OIDC Provider一覧
aws iam list-open-id-connect-providers

# 詳細確認
OIDC_ARN=$(terraform output -raw oidc_provider_arn)
aws iam get-open-id-connect-provider --open-id-connect-provider-arn $OIDC_ARN
```

### アタッチされたポリシーの確認

```bash
# ロールにアタッチされたポリシー一覧
aws iam list-attached-role-policies --role-name sandbox-ecr-kms-github-actions-role

# ポリシーの内容を確認
POLICY_ARN=$(terraform output -raw ecr_access_policy_arn)
aws iam get-policy --policy-arn $POLICY_ARN
aws iam get-policy-version --policy-arn $POLICY_ARN --version-id v1
```

---

## 🧪 テスト

### ローカルでのテスト（AWS CLI）

```bash
# IAMロールをAssumeできるか確認（GitHub Actionsからのみ可能）
# ローカルからは実行できません

# 代わりに、GitHub Actionsで簡単なテストワークフローを実行
```

### GitHub Actionsでのテスト

最小限のテストワークフロー:

```yaml
name: Test IAM Role

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Test AWS access
        run: |
          aws sts get-caller-identity
          aws ecr describe-repositories --max-results 1 || true
```

---

## 🔒 セキュリティ上の注意

### 1. リポジトリの制限

IAMロールの信頼ポリシーで、特定のGitHubリポジトリのみがAssumeRoleできるように制限しています：

```hcl
condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values = [
    "repo:your-org/your-repo:*"
  ]
}
```

### 2. 最小権限の原則

各ポリシーは必要最小限の権限のみを付与しています。

### 3. ブランチ制限（オプション）

より厳密に制限したい場合、特定のブランチのみを許可：

```hcl
values = [
  "repo:your-org/your-repo:ref:refs/heads/main"
]
```

---

## 🧹 リソースの削除

```bash
# IAMリソースを削除
terraform destroy

# 確認
aws iam list-roles | grep sandbox-ecr-kms
```

---

## 📚 参考リンク

- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC Provider](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [configure-aws-credentials Action](https://github.com/aws-actions/configure-aws-credentials)

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

