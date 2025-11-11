# Terraform リソース用バケット管理

このディレクトリは、プロジェクトで使用するリソース用のS3バケットを管理します。

## 📋 概要

このTerraformモジュールは、[terraform-aws-modules/s3-bucket](https://registry.terraform.io/modules/terraform-aws-modules/s3-bucket/aws/latest) を使用して、以下のバケットを作成します：

### 作成されるバケット

1. **IAM用バケット** - IAM関連リソースの保存
2. **KMS用バケット** - KMS関連リソースの保存
3. **ECR用バケット** - ECRイメージスキャン結果、脆弱性レポート等
4. **Artifacts用バケット** - GitHub Workflowのアーティファクト、テスト結果
5. **アクセスログ用バケット** - 全バケットのアクセスログ

### 設計のポイント

- **`locals.tf` で一元管理**: 新しいリソースディレクトリが増えるごとに、`locals.tf` にバケット定義を追加
- **`for_each` で柔軟に管理**: バケット定義を動的に展開して作成
- **terraform-aws-modules 使用**: ベストプラクティスに基づいた設定

---

## 🚀 セットアップ手順

### 前提条件

1. **tfstate用S3バケット**が作成済みであること
   - 手順: [docs/setup-tfstate-bucket.md](../../docs/setup-tfstate-bucket.md)
   - または: `scripts/setup-tfstate-bucket.sh` を実行

2. AWS CLIが設定済み
3. Terraform CLI（>= 1.10.0）がインストール済み

---

### Step 1: tfstate用バケットの作成

まだ作成していない場合は、以下を実行：

```bash
# スクリプトで作成（推奨）
cd ../../scripts
./setup-tfstate-bucket.sh

# または手動でAWS CLIコマンドを実行
# 詳細は docs/setup-tfstate-bucket.md を参照
```

---

### Step 2: backend.tf の作成

Backend設定は `backend.tf` に分離されています（セキュリティのため、実際のバケット名を含むファイルはGitにコミットしません）。

#### 方法A: テンプレートからコピー（初回セットアップ）

```bash
# backend.tf.example を backend.tf にコピー
cp backend.tf.example backend.tf

# backend.tf を編集してバケット名を置換
# <YOUR_BUCKET_NAME> を実際のバケット名に置き換える
```

**バケット名の確認方法:**

```bash
aws s3 ls | grep tfstate
# 出力例: sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1
```

#### 方法B: 直接作成

`backend.tf` を作成して、以下を記載：

```hcl
terraform {
  backend "s3" {
    bucket       = "sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"  # ← 実際のバケット名
    key          = "tfstate/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true  # State Lock（Terraform v1.10+、DynamoDB不要）
  }
}
```

**⚠️ 重要**: `backend.tf` は `.gitignore` に追加されており、Gitにコミットされません。

---

### Step 3: Terraform初期化

```bash
cd terraform/tfstate
terraform init
```

**成功すると:**
```
Initializing the backend...
Successfully configured the backend "s3"!
```

**Note:** このプロジェクトでは Terraform v1.10+ の `use_lockfile = true` を使用しているため、DynamoDBテーブルなしでState Lockが有効になります。

---

### Step 4: リソース用バケットの作成

```bash
# 実行計画の確認
terraform plan

# バケット作成
terraform apply
```

---

### Step 5: 作成されたバケットの確認

```bash
# 出力を確認
terraform output

# AWS CLIで確認
aws s3 ls | grep sandbox-ecr-kms
```

---

## 📁 ファイル構成

```
terraform/tfstate/
├── versions.tf            # Terraform/Provider設定
├── backend.tf             # S3 Backend設定（.gitignoreで除外）
├── backend.tf.example     # Backend設定テンプレート（Gitにコミット）
├── providers.tf           # AWSプロバイダー設定
├── data.tf                # データソース（アカウントID、リージョン取得）
├── locals.tf              # バケット定義（ここを編集して追加）★
├── main.tf                # terraform-aws-moduleを使用したバケット作成
├── variables.tf           # 変数定義
├── outputs.tf             # 出力定義
├── .gitignore             # Git除外設定
└── README.md              # このファイル
```

### ファイルの役割

| ファイル | 説明 | Gitコミット |
|---------|------|------------|
| `backend.tf` | 実際のBackend設定（バケット名含む） | ❌ 除外 |
| `backend.tf.example` | Backend設定のテンプレート | ✅ コミット |
| `versions.tf` | Terraform/Providerのバージョン指定 | ✅ コミット |
| その他の `.tf` ファイル | リソース定義 | ✅ コミット |

---

## ✏️ 新しいバケットの追加方法

新しいリソースディレクトリが増えた場合、`locals.tf` にバケット定義を追加します。

### Step 1: locals.tf を開く

`terraform/tfstate/locals.tf` を開きます。

### Step 2: resource_buckets に追加

```hcl
# locals.tf の resource_buckets マップに追加

resource_buckets = {
  # 既存のバケット定義...
  
  # 新しいバケット定義を追加 ↓
  monitoring = {
    name_suffix = "monitoring"
    purpose     = "Monitoring and alerting data"
    versioning  = false
    lifecycle_rules = {
      enabled                    = true
      expire_noncurrent_days     = 30
      abort_incomplete_upload_days = 7
    }
    allowed_principals = []
  }
}
```

### Step 3: outputs.tf に出力を追加（オプション）

他のモジュールから参照しやすいように、個別の出力を追加できます：

```hcl
output "monitoring_bucket_name" {
  description = "Name of the monitoring bucket"
  value       = module.resource_buckets["monitoring"].s3_bucket_id
}

output "monitoring_bucket_arn" {
  description = "ARN of the monitoring bucket"
  value       = module.resource_buckets["monitoring"].s3_bucket_arn
}
```

### Step 4: Terraform apply

```bash
terraform plan
terraform apply
```

新しいバケットが作成されます！

---

## 🔧 設定のカスタマイズ

### バケット設定項目

各バケットは以下の項目で設定できます：

```hcl
{
  name_suffix = "バケット名のサフィックス"
  purpose     = "バケットの用途（タグに使用）"
  versioning  = true/false  # バージョニングの有効/無効
  lifecycle_rules = {
    enabled                    = true/false  # ライフサイクルルールの有効/無効
    expire_noncurrent_days     = 30         # 古いバージョンの削除日数
    abort_incomplete_upload_days = 7       # 不完全アップロードのクリーンアップ日数
  }
  allowed_principals = []  # アクセスを許可するIAMロールのARN（将来の拡張用）
}
```

### バケット命名規則

自動生成されるバケット名：

```
{project_name}-{name_suffix}-{account_id}-{region}
```

**例:**
```
sandbox-ecr-kms-iam-123456789012-ap-northeast-1
sandbox-ecr-kms-kms-123456789012-ap-northeast-1
sandbox-ecr-kms-ecr-123456789012-ap-northeast-1
```

---

## 📤 Outputs（出力）

作成されたバケット情報は、outputs として他のモジュールから参照できます。

### 全バケット情報

```bash
terraform output resource_buckets
```

### 個別バケット名

```bash
terraform output iam_bucket_name
terraform output kms_bucket_name
terraform output ecr_bucket_name
terraform output artifacts_bucket_name
```

### マップ形式

```bash
# バケット名のマップ
terraform output bucket_names_by_type

# バケットARNのマップ
terraform output bucket_arns_by_type
```

### 他のTerraformモジュールからの参照

```hcl
# 例: terraform/iam/main.tf

data "terraform_remote_state" "tfstate" {
  backend = "s3"
  config = {
    bucket = "sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"
    key    = "tfstate/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

# IAM用バケットのARNを参照
locals {
  iam_bucket_arn = data.terraform_remote_state.tfstate.outputs.iam_bucket_arn
}
```

---

## 🔒 セキュリティ設定

全バケットに以下のセキュリティ設定が適用されます：

### 1. サーバーサイド暗号化

- **アルゴリズム**: AES256（S3管理キー）
- **バケットキー**: 有効（コスト削減）

### 2. パブリックアクセスブロック

全てのパブリックアクセスをブロック：
- ✅ 新しいACLを介したパブリックアクセスをブロック
- ✅ 任意のACLを介したパブリックアクセスをブロック
- ✅ 新しいパブリックバケットポリシーをブロック
- ✅ 任意のパブリックバケットポリシーをブロック

### 3. アクセスログ

全リソースバケットのアクセスログは、専用のログバケットに記録されます：

```
sandbox-ecr-kms-access-logs-{account-id}-{region}/
├── iam/
├── kms/
├── ecr/
└── artifacts/
```

### 4. ライフサイクル管理

- 古いバージョンの自動削除
- 不完全なマルチパートアップロードのクリーンアップ
- ログの自動削除（90日後）

---

## 🧹 リソースの削除

検証終了後、リソースを削除します。

### Step 1: 他のリソースを先に削除

他のコンポーネント（IAM、KMS、ECR）を先に削除してください。

### Step 2: バケット内のオブジェクトを確認

```bash
# 各バケットの内容を確認
aws s3 ls s3://sandbox-ecr-kms-iam-{account-id}-{region}/ --recursive
aws s3 ls s3://sandbox-ecr-kms-kms-{account-id}-{region}/ --recursive
# ...
```

### Step 3: Terraform destroy

```bash
cd terraform/tfstate
terraform destroy
```

`force_destroy = true` が設定されているため、オブジェクトがあっても削除されます。

### Step 4: tfstate用バケットの削除

最後に、tfstate用バケット自体を削除：

```bash
BUCKET_NAME="sandbox-ecr-kms-tfstate-{account-id}-{region}"

# バケットを空にする
aws s3 rm s3://$BUCKET_NAME/ --recursive

# バケットを削除
aws s3 rb s3://$BUCKET_NAME
```

---

## 💡 ベストプラクティス

### 1. バケット名の統一

`locals.tf` で命名規則を統一することで、管理が容易になります。

### 2. ライフサイクルルールの設定

不要なオブジェクトを自動削除することで、コストを削減できます。

### 3. タグの活用

適切なタグを設定することで、コスト管理やリソース管理が容易になります。

### 4. アクセスログの記録

セキュリティ監査やトラブルシューティングに役立ちます。

---

## 📚 参考リンク

- [terraform-aws-modules/s3-bucket](https://registry.terraform.io/modules/terraform-aws-modules/s3-bucket/aws/latest)
- [AWS S3 ベストプラクティス](https://docs.aws.amazon.com/AmazonS3/latest/userguide/best-practices.html)
- [S3 暗号化](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
- [S3 バージョニング](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)

---

## トラブルシューティング

### 問題1: Backend初期化エラー

**エラー**: `Error: Failed to get existing workspaces`

**解決方法**:
1. tfstate用バケットが作成されているか確認
2. `versions.tf` のバケット名が正しいか確認
3. AWS認証情報が正しいか確認

### 問題2: モジュールのダウンロードエラー

**エラー**: `Error: Failed to query available provider packages`

**解決方法**:
```bash
# プロバイダーを再初期化
terraform init -upgrade
```

### 問題3: バケット名の競合

**エラー**: `BucketAlreadyExists`

**解決方法**:
`locals.tf` の `project_name` を変更して、バケット名を変更します。

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

