# Terraform State用 S3バケット セットアップガイド

このドキュメントでは、Terraformのtfstateファイルを保存するためのS3バケットを手動で作成する方法を説明します。

## 📋 目次

- [概要](#概要)
- [バケット命名規則](#バケット命名規則)
- [方法1: AWS CLIでの作成（推奨）](#方法1-aws-cliでの作成推奨)
- [方法2: AWSマネジメントコンソールでの作成](#方法2-awsマネジメントコンソールでの作成)
- [検証](#検証)
- [Terraform設定の更新](#terraform設定の更新)
- [トラブルシューティング](#トラブルシューティング)

---

## 概要

### なぜ手動作成するのか？

- **シンプル**: スクリプトより理解しやすい
- **確実**: 作成プロセスが明確
- **学習**: AWSリソース作成の理解が深まる

### 作成するリソース

1. **メインバケット**: Terraformのtfstateを保存
2. **必要な設定**:
   - バージョニング有効化
   - 暗号化有効化
   - パブリックアクセスブロック

---

## バケット命名規則

S3バケット名はグローバルに一意である必要があります。以下の形式を推奨します：

```
<project>-tfstate-<account-id>-<region>
```

**例:**
```
sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1
```

### アカウントIDの確認

```bash
aws sts get-caller-identity --query Account --output text
```

---

## 方法1: AWS CLIでの作成（推奨）

### Step 1: 変数の設定

```bash
# プロジェクト名
PROJECT_NAME="sandbox-ecr-kms"

# AWSアカウントIDの取得
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# リージョン
REGION="ap-northeast-1"

# バケット名の生成
BUCKET_NAME="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}-${REGION}"

echo "バケット名: $BUCKET_NAME"
```

### Step 2: S3バケットの作成

```bash
# バケット作成
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION

# 作成確認
aws s3 ls | grep tfstate
```

**期待される出力:**
```
2025-11-10 12:34:56 sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1
```

### Step 3: バージョニングの有効化

```bash
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# 確認
aws s3api get-bucket-versioning --bucket $BUCKET_NAME
```

**期待される出力:**
```json
{
    "Status": "Enabled"
}
```

### Step 4: 暗号化の有効化

```bash
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'

# 確認
aws s3api get-bucket-encryption --bucket $BUCKET_NAME
```

### Step 5: パブリックアクセスブロック

```bash
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 確認
aws s3api get-public-access-block --bucket $BUCKET_NAME
```

### Step 6: タグの追加（オプション）

```bash
aws s3api put-bucket-tagging \
  --bucket $BUCKET_NAME \
  --tagging 'TagSet=[
    {Key=Project,Value=sandbox-aws-ecr-kms-cosign},
    {Key=Purpose,Value=TerraformState},
    {Key=ManagedBy,Value=Manual},
    {Key=Environment,Value=dev}
  ]'

# 確認
aws s3api get-bucket-tagging --bucket $BUCKET_NAME
```

### 完全なセットアップスクリプト

上記をまとめた実行可能なスクリプト：

```bash
#!/bin/bash
set -e

# 設定
PROJECT_NAME="sandbox-ecr-kms"
REGION="ap-northeast-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}-${REGION}"

echo "==================================="
echo "Terraform State S3 Bucket Setup"
echo "==================================="
echo "バケット名: $BUCKET_NAME"
echo "リージョン: $REGION"
echo ""

# 1. バケット作成
echo "1. S3バケットを作成しています..."
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION
echo "✓ 完了"

# 2. バージョニング有効化
echo "2. バージョニングを有効化しています..."
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
echo "✓ 完了"

# 3. 暗号化有効化
echo "3. 暗号化を有効化しています..."
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'
echo "✓ 完了"

# 4. パブリックアクセスブロック
echo "4. パブリックアクセスをブロックしています..."
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "✓ 完了"

# 5. タグ追加
echo "5. タグを追加しています..."
aws s3api put-bucket-tagging \
  --bucket $BUCKET_NAME \
  --tagging 'TagSet=[
    {Key=Project,Value=sandbox-aws-ecr-kms-cosign},
    {Key=Purpose,Value=TerraformState},
    {Key=ManagedBy,Value=Manual},
    {Key=Environment,Value=dev}
  ]'
echo "✓ 完了"

echo ""
echo "==================================="
echo "セットアップ完了！"
echo "==================================="
echo ""
echo "バケット名: $BUCKET_NAME"
echo ""
echo "次のステップ:"
echo "1. terraform/tfstate/versions.tf を開く"
echo "2. backend \"s3\" の bucket を以下に変更:"
echo "   bucket = \"$BUCKET_NAME\""
echo ""
echo "確認コマンド:"
echo "  aws s3api get-bucket-versioning --bucket $BUCKET_NAME"
echo "  aws s3api get-bucket-encryption --bucket $BUCKET_NAME"
```

このスクリプトをファイルに保存して実行：

```bash
# スクリプトを保存
cat > setup-tfstate-bucket.sh << 'EOF'
[上記のスクリプト内容]
EOF

# 実行権限を付与
chmod +x setup-tfstate-bucket.sh

# 実行
./setup-tfstate-bucket.sh
```

---

## 方法2: AWSマネジメントコンソールでの作成

### Step 1: S3コンソールを開く

1. [AWSマネジメントコンソール](https://console.aws.amazon.com/)にログイン
2. 検索バーで「S3」を検索
3. 「バケットを作成」をクリック

### Step 2: 基本設定

| 項目 | 設定値 |
|------|--------|
| バケット名 | `sandbox-ecr-kms-tfstate-<account-id>-<region>` |
| AWSリージョン | `アジアパシフィック（東京）ap-northeast-1` |

**バケット名の確認:**
- アカウントIDは、右上のアカウント名をクリックして確認
- 例: `sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1`

### Step 3: オブジェクト所有者

- **推奨**: ACL無効（バケット所有者の強制）

### Step 4: パブリックアクセス設定

**全てのパブリックアクセスをブロック:**
- ✅ 新しいアクセスコントロールリスト(ACL)を介して付与されたバケットとオブジェクトへのパブリックアクセスをブロックする
- ✅ 任意のアクセスコントロールリスト(ACL)を介して付与されたバケットとオブジェクトへのパブリックアクセスをブロックする
- ✅ 新しいパブリックバケットポリシーまたはアクセスポイントポリシーを介して付与されたバケットとオブジェクトへのパブリックアクセスをブロックする
- ✅ 任意のパブリックバケットポリシーまたはアクセスポイントポリシーを介したバケットとオブジェクトへのパブリックアクセスとクロスアカウントアクセスをブロックする

### Step 5: バージョニング

- **バージョニング**: ✅ 有効にする

### Step 6: デフォルト暗号化

| 項目 | 設定値 |
|------|--------|
| 暗号化タイプ | `サーバー側の暗号化 (SSE-S3)` |
| バケットキー | ✅ 有効 |

### Step 7: 詳細設定（オプション）

- **オブジェクトロック**: 無効（デフォルト）

### Step 8: タグ（オプション）

| キー | 値 |
|------|-----|
| `Project` | `sandbox-aws-ecr-kms-cosign` |
| `Purpose` | `TerraformState` |
| `ManagedBy` | `Manual` |
| `Environment` | `dev` |

### Step 9: 作成

「バケットを作成」ボタンをクリック

---

## State Lock について

### Terraform v1.10の新機能: use_lockfile

Terraform v1.10から、S3 BackendでState Lockを有効にするために**DynamoDBテーブルが不要**になりました。

#### 従来の方式（~v1.9）

```hcl
backend "s3" {
  bucket         = "my-bucket"
  key            = "terraform.tfstate"
  region         = "ap-northeast-1"
  encrypt        = true
  dynamodb_table = "terraform-lock"  # DynamoDBテーブルが必要だった
}
```

**デメリット:**
- ❌ 追加のDynamoDBテーブルが必要
- ❌ テーブルの作成と管理が必要
- ❌ 追加のコスト（わずかですが）

#### 新しい方式（v1.10~）

```hcl
backend "s3" {
  bucket       = "my-bucket"
  key          = "terraform.tfstate"
  region       = "ap-northeast-1"
  encrypt      = true
  use_lockfile = true  # これだけでOK！
}
```

**メリット:**
- ✅ DynamoDB不要
- ✅ シンプルな構成
- ✅ コスト削減
- ✅ 管理が容易

### 仕組み

`use_lockfile = true` を設定すると、TerraformはS3バケット内に `.terraform.lock.info` ファイルを作成してロックを管理します。

---

## 検証

### バケットの存在確認

```bash
aws s3 ls | grep tfstate
```

### バージョニング確認

```bash
BUCKET_NAME="sandbox-ecr-kms-tfstate-<your-account-id>-ap-northeast-1"
aws s3api get-bucket-versioning --bucket $BUCKET_NAME
```

### 暗号化確認

```bash
aws s3api get-bucket-encryption --bucket $BUCKET_NAME
```

### パブリックアクセスブロック確認

```bash
aws s3api get-public-access-block --bucket $BUCKET_NAME
```

### 全体の設定確認

```bash
# バケット情報を一覧表示
aws s3api head-bucket --bucket $BUCKET_NAME
aws s3api get-bucket-location --bucket $BUCKET_NAME
```

---

## Terraform設定の更新

バケット作成後、Terraformの設定ファイルを更新します。

### Step 1: backend.tf の作成

Backend設定は `backend.tf` に分離されています（セキュリティ上の理由で、実際のバケット名を含むファイルはGitにコミットしません）。

#### テンプレートからコピー

```bash
cd terraform/tfstate

# テンプレートをコピー
cp backend.tf.example backend.tf

# backend.tf を編集
# <YOUR_BUCKET_NAME> を実際のバケット名に置き換えてください
```

**エディタで `backend.tf` を開いて編集:**

```hcl
terraform {
  backend "s3" {
    bucket       = "sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"  # ← 作成したバケット名に置き換え
    key          = "tfstate/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true  # State Lock（Terraform v1.10+、DynamoDB不要）
  }
}
```

**⚠️ 重要**: `backend.tf` は `.gitignore` に追加されており、Gitにコミットされません。

### Step 2: Terraform初期化

```bash
cd terraform/tfstate
terraform init
```

**成功すると:**
```
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
```

**Note:** `use_lockfile = true` により、DynamoDBテーブルなしでState Lockが有効になります（Terraform v1.10+の新機能）

### Step 3: リソース用バケットの作成

```bash
terraform plan
terraform apply
```

これで、tfstate以外のリソース用バケット（IAM、KMS、ECR、Artifacts）が作成されます。

---

## トラブルシューティング

### 問題1: バケット名が既に使用されている

**エラー**: `BucketAlreadyExists`

**原因**: S3バケット名はグローバルに一意である必要があります

**解決方法**:
```bash
# 異なるバケット名を使用
BUCKET_NAME="${PROJECT_NAME}-tfstate-v2-${ACCOUNT_ID}-${REGION}"
```

### 問題2: リージョンの制約エラー

**エラー**: `IllegalLocationConstraintException`

**原因**: `us-east-1` 以外のリージョンでは `LocationConstraint` が必要

**解決方法**:
```bash
# us-east-1 の場合
aws s3api create-bucket --bucket $BUCKET_NAME --region us-east-1

# その他のリージョンの場合
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION
```

### 問題3: 権限不足

**エラー**: `AccessDenied`

**原因**: IAMユーザーにS3バケット作成権限がない

**解決方法**:
IAMユーザーに以下の権限を付与：
- `s3:CreateBucket`
- `s3:PutBucketVersioning`
- `s3:PutEncryptionConfiguration`
- `s3:PutBucketPublicAccessBlock`
- `s3:PutBucketTagging`

### 問題4: Terraform初期化エラー

**エラー**: `Error: Failed to get existing workspaces`

**原因**: バケット名が間違っている、またはバケットにアクセスできない

**解決方法**:
```bash
# バケット名を確認
aws s3 ls | grep tfstate

# versions.tf のバケット名が正しいか確認
cat terraform/tfstate/versions.tf | grep bucket

# アクセス権限を確認
aws s3 ls s3://$BUCKET_NAME/
```

---

## バケットの削除（検証終了時）

検証が終了したら、以下の手順でバケットを削除します：

### Step 1: バケットを空にする

```bash
BUCKET_NAME="sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"

# 全オブジェクトを削除
aws s3 rm s3://$BUCKET_NAME/ --recursive

# バージョン管理されたオブジェクトも削除
aws s3api list-object-versions --bucket $BUCKET_NAME \
  --output json \
  --query 'Versions[].{Key:Key,VersionId:VersionId}' \
  | jq -r '.[] | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' \
  | xargs -I {} aws s3api delete-object --bucket $BUCKET_NAME {}
```

### Step 2: バケットを削除

```bash
aws s3 rb s3://$BUCKET_NAME
```

### Step 3: 削除確認

```bash
aws s3 ls | grep tfstate
# 何も表示されなければ削除成功
```

---

## まとめ

### 作成したもの

- ✅ Terraform State用S3バケット
- ✅ バージョニング有効化
- ✅ 暗号化有効化
- ✅ パブリックアクセスブロック
- ✅ タグ設定

### 次のステップ

1. `terraform/tfstate/versions.tf` のバケット名を更新
2. `terraform init` で初期化
3. `terraform apply` でリソース用バケットを作成
4. 各コンポーネント（IAM、KMS、ECR）の作成に進む

---

## 参考リンク

- [AWS S3 CLI Reference](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3api/index.html)
- [S3 バージョニング](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
- [S3 暗号化](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

