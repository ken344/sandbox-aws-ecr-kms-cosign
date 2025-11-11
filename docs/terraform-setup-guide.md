# Terraform セットアップガイド

このドキュメントでは、プロジェクト全体のTerraform構成とセットアップ手順を説明します。

## 📋 目次

- [概要](#概要)
- [ディレクトリ構成](#ディレクトリ構成)
- [設計思想](#設計思想)
- [セットアップ手順](#セットアップ手順)
- [各コンポーネントの説明](#各コンポーネントの説明)
- [運用ガイド](#運用ガイド)
- [トラブルシューティング](#トラブルシューティング)

---

## 概要

このプロジェクトでは、以下の設計方針でTerraformを構成しています：

### 設計方針

1. **リソース単位でディレクトリを分割**
   - 各リソース（IAM、KMS、ECR等）を独立したディレクトリで管理
   - コンポーネントごとに独立したライフサイクル

2. **独立したtfstate管理**
   - 各ディレクトリが独自のtfstateを持つ
   - 変更の影響範囲を限定し、安全性を向上

3. **S3 Backend使用**
   - tfstateをS3に保存してチーム共有可能
   - バージョニングと暗号化を有効化

4. **Import対応**
   - 既存リソースにも対応可能
   - 段階的な移行が可能

---

## ディレクトリ構成

```
terraform/
├── bootstrap/                   # S3バケット作成（Backend用）
│   ├── main.tf                 # S3バケットリソース定義
│   ├── versions.tf             # Terraform設定（ローカルbackend）
│   ├── variables.tf            # 変数定義
│   ├── outputs.tf              # 出力定義
│   ├── terraform.tfvars.example # 変数ファイルのサンプル
│   ├── backend-template.tf     # 他コンポーネント用テンプレート
│   ├── setup.sh                # セットアップスクリプト
│   ├── destroy.sh              # 削除スクリプト
│   ├── .gitignore              # Git除外設定
│   └── README.md               # ドキュメント
│
├── iam/                        # IAMリソース（準備中）
│   ├── main.tf
│   ├── versions.tf             # S3 backend使用
│   ├── variables.tf
│   └── outputs.tf
│
├── kms/                        # KMSリソース（準備中）
│   ├── main.tf
│   ├── versions.tf             # S3 backend使用
│   ├── variables.tf
│   └── outputs.tf
│
└── ecr/                        # ECRリソース（準備中）
    ├── main.tf
    ├── versions.tf             # S3 backend使用
    ├── variables.tf
    └── outputs.tf
```

---

## 設計思想

### なぜディレクトリを分割するのか？

#### メリット

1. **変更の影響範囲を限定**
   ```
   IAMの変更 → IAMのみ再デプロイ
   KMSの変更 → KMSのみ再デプロイ
   ```

2. **並列作業が可能**
   - 複数人が異なるコンポーネントを同時に編集可能
   - tfstateのロック競合を回避

3. **リスクの分散**
   - 1つのコンポーネントの障害が全体に影響しない
   - `terraform destroy`の誤実行リスクを軽減

4. **メンテナンス性の向上**
   - コードの見通しが良い
   - 依存関係が明確

#### デメリットと対策

1. **コンポーネント間の依存関係管理**
   - **対策**: `terraform_remote_state`でデータソースとして参照
   - **対策**: outputsを明示的に定義

2. **初期セットアップが複雑**
   - **対策**: セットアップスクリプトを提供
   - **対策**: 詳細なドキュメント作成

### なぜBootstrapが必要か？

Terraformのtfstateを保存するS3バケット自体をTerraformで管理するため、**鶏卵問題**が発生します：

```
tfstateを保存するにはS3が必要
  ↓
S3を作るにはTerraformが必要
  ↓
TerraformにはtfstateのS3が必要
  ↓ （ループ）
```

**解決策**: Bootstrapディレクトリのみローカルstateを使用

```
1. Bootstrap（ローカルstate）でS3バケット作成
2. 他のコンポーネントはS3 backendを使用
```

---

## セットアップ手順

### Phase 1: Bootstrap（S3バケット作成）

#### 方法A: スクリプトを使用（推奨）

```bash
cd terraform/bootstrap
./setup.sh
```

スクリプトが以下を自動実行します：
- 前提条件のチェック（AWS CLI、Terraform CLI）
- AWS認証の確認
- terraform.tfvarsの作成
- Terraform初期化
- リソースの作成

#### 方法B: 手動実行

```bash
cd terraform/bootstrap

# 1. 変数ファイルの作成
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # 必要に応じて編集

# 2. Terraform初期化
terraform init

# 3. 実行計画の確認
terraform plan

# 4. リソースの作成
terraform apply

# 5. 出力の確認
terraform output
```

#### 重要な出力

```bash
# バケット名を確認（他コンポーネントで使用）
terraform output -raw terraform_state_bucket_name

# Backend設定を表示
terraform output -raw backend_config_formatted
```

**出力例:**
```
sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1
```

この値を**メモ**してください！

---

### Phase 2: 各コンポーネントのセットアップ

各コンポーネント（IAM、KMS、ECR）で以下の手順を実行します。

#### Step 1: ディレクトリ作成

```bash
mkdir -p terraform/iam
cd terraform/iam
```

#### Step 2: Backend設定のコピー

```bash
cp ../bootstrap/backend-template.tf versions.tf
```

#### Step 3: Backend設定の編集

`versions.tf`を開いて以下を置換：

```hcl
terraform {
  required_version = ">= 1.10.0"  # use_lockfile 機能を使用するため

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"  # ← Bootstrap の output
    key          = "iam/terraform.tfstate"  # ← コンポーネント名
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true  # State Lock（Terraform v1.10+、DynamoDB不要）
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "sandbox-aws-ecr-kms-cosign"
      ManagedBy  = "Terraform"
      Component  = "IAM"  # ← コンポーネント名
      Repository = "sandbox-aws-ecr-kms-cosign"
    }
  }
}
```

#### Step 4: リソース定義の作成

`main.tf`、`variables.tf`、`outputs.tf`を作成してリソースを定義します。

#### Step 5: Terraform初期化

```bash
terraform init
```

**成功すると:**
```
Initializing the backend...
Successfully configured the backend "s3"!
```

#### Step 6: リソースのデプロイ

```bash
terraform plan
terraform apply
```

---

## 各コンポーネントの説明

### 1. Bootstrap

**目的**: Terraform backend用のS3バケット作成

**特徴**:
- ローカルstateを使用
- バージョニング、暗号化を有効化
- アクセスログを別バケットに保存

**作成されるリソース**:
- `aws_s3_bucket.terraform_state` - メインバケット
- `aws_s3_bucket.terraform_state_logs` - ログバケット
- バージョニング、暗号化、パブリックアクセスブロック等

**詳細**: [terraform/bootstrap/README.md](../terraform/bootstrap/README.md)

---

### 2. IAM（準備中）

**目的**: GitHub Actions用のIAMロールとOIDCプロバイダー

**特徴**:
- S3 backendを使用
- OIDCベースの認証（アクセスキー不要）

**作成予定のリソース**:
- `aws_iam_openid_connect_provider` - GitHub OIDC
- `aws_iam_role` - GitHub Actions用ロール
- `aws_iam_role_policy` - ECR/KMS権限

---

### 3. KMS（準備中）

**目的**: コンテナイメージ署名用のKMSキー

**特徴**:
- 非対称キー（SIGN_VERIFY）
- IAMロールに署名権限を付与

**作成予定のリソース**:
- `aws_kms_key` - 署名用キー
- `aws_kms_alias` - キーエイリアス
- `aws_kms_key_policy` - キーポリシー

---

### 4. ECR（準備中）

**目的**: コンテナレジストリとライフサイクルポリシー

**特徴**:
- 複数のリポジトリ作成
- ライフサイクルポリシーで自動削除

**作成予定のリソース**:
- `aws_ecr_repository` - リポジトリ（複数）
- `aws_ecr_lifecycle_policy` - ライフサイクルポリシー

---

## 運用ガイド

### コンポーネント間の依存関係

コンポーネント間でリソース情報を共有する方法：

#### 方法A: terraform_remote_state（推奨）

**IAMのoutputs.tf:**
```hcl
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
```

**KMSのmain.tf:**
```hcl
data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"
    key    = "iam/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

# IAMロールARNを参照
locals {
  github_role_arn = data.terraform_remote_state.iam.outputs.github_actions_role_arn
}
```

#### 方法B: 手動で値を渡す

`terraform.tfvars`で明示的に指定：

```hcl
github_actions_role_arn = "arn:aws:iam::123456789012:role/github-actions-role"
```

---

### 実行順序

コンポーネントには依存関係があるため、以下の順序で実行してください：

```
1. Bootstrap   ← 最初（他の全てのベース）
2. IAM         ← 2番目（KMS/ECRがIAMロールを参照）
3. KMS         ← 3番目（ECRが使用）
4. ECR         ← 最後
```

**削除時は逆順**:
```
1. ECR
2. KMS
3. IAM
4. Bootstrap   ← 最後（全てのstateを保持）
```

---

### よく使うコマンド

#### 初期化

```bash
terraform init
```

#### 計画確認

```bash
terraform plan
```

#### 変更の適用

```bash
terraform apply
```

#### 出力の確認

```bash
terraform output
terraform output -json  # JSON形式
terraform output -raw <name>  # 生の値
```

#### リソースの削除

```bash
terraform destroy
```

#### Stateの確認

```bash
terraform state list  # リソース一覧
terraform state show <resource>  # リソース詳細
```

#### Import

```bash
terraform import <resource_type>.<name> <resource_id>

# 例: S3バケットをImport
terraform import aws_s3_bucket.terraform_state my-bucket-name
```

---

### セキュリティベストプラクティス

1. **認証情報の保護**
   - `terraform.tfvars`をGitにコミットしない
   - アクセスキーをコードに含めない

2. **tfstateの保護**
   - S3バケットの暗号化を有効化（実装済み）
   - バージョニングを有効化（実装済み）
   - パブリックアクセスをブロック（実装済み）

3. **最小権限の原則**
   - IAMポリシーは必要最小限に
   - 各ロールに適切なスコープを設定

4. **バックアップ**
   - S3バケットのバージョニングで自動バックアップ
   - 定期的な完全バックアップを推奨

---

## トラブルシューティング

### 問題1: Backend初期化エラー

**エラー**: `Error: Failed to get existing workspaces`

**原因**: S3バケットが存在しない、またはアクセス権限がない

**解決方法**:
```bash
# Bootstrap が実行済みか確認
cd ../bootstrap
terraform output terraform_state_bucket_name

# バケットが存在するか確認
aws s3 ls | grep tfstate

# アクセス権限を確認
aws s3 ls s3://your-bucket-name/
```

---

### 問題2: tfstate ロック

**エラー**: `Error: Error acquiring the state lock`

**原因**: 別のプロセスがtfstateをロックしている

**解決方法**:
```bash
# ロックを確認（DynamoDBを使用している場合）
# このプロジェクトではDynamoDBを使用しないため、通常は発生しない

# 強制的にロック解除（最終手段）
terraform force-unlock <lock-id>
```

---

### 問題3: リソースが既に存在

**エラー**: `Error: resource already exists`

**原因**: AWSに既にリソースが存在する

**解決方法**:
```bash
# Import実行
terraform import <resource_type>.<name> <resource_id>

# 例: IAMロール
terraform import aws_iam_role.github_actions github-actions-role
```

---

### 問題4: 依存関係エラー

**エラー**: `Error: data source not found`

**原因**: 参照先のコンポーネントが未デプロイ

**解決方法**:
1. 依存するコンポーネントを先にデプロイ
2. 実行順序を確認（Bootstrap → IAM → KMS → ECR）

---

### 問題5: プロバイダーバージョン不一致

**エラー**: `Error: Incompatible provider version`

**解決方法**:
```bash
# .terraform.lock.hclを削除
rm .terraform.lock.hcl

# 再初期化
terraform init -upgrade
```

---

## 参考リンク

- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [Terraform Remote State](https://developer.hashicorp.com/terraform/language/state/remote-state-data)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Import](https://developer.hashicorp.com/terraform/cli/import)

---

## 次のステップ

Bootstrap が完了したら、次は以下のドキュメントを参照してください：

1. [IAM Setup Guide](./iam-setup-guide.md)（準備中）
2. [KMS Setup Guide](./kms-setup-guide.md)（準備中）
3. [ECR Setup Guide](./ecr-setup-guide.md)（準備中）

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成（Bootstrap完成） |

