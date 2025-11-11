# クイックスタートガイド

このガイドでは、プロジェクトを最速でセットアップする方法を説明します。

## 📋 前提条件

- ✅ AWSアカウント
- ✅ AWS CLI設定済み（`aws configure`）
- ✅ Terraform CLI（>= 1.10.0）
- ✅ Git

---

## 🚀 5ステップでセットアップ

### Step 1: リポジトリのクローン

```bash
git clone <repository-url>
cd sandbox-aws-ecr-kms-cosign
```

### Step 2: AWS認証確認

```bash
# AWS CLIが正しく設定されているか確認
aws sts get-caller-identity

# アカウントIDをメモ（後で使用）
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"
```

### Step 3: tfstate用S3バケット作成

```bash
# スクリプトで自動作成（推奨）
cd scripts
./setup-tfstate-bucket.sh
```

このスクリプトが以下を自動実行します：
- ✅ S3バケット作成
- ✅ バージョニング有効化
- ✅ 暗号化有効化  
- ✅ パブリックアクセスブロック

**作成されるバケット名をメモしてください！**

例: `sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1`

### Step 4: Terraform Backend設定

Backend設定ファイルを作成します：

```bash
cd terraform/tfstate

# テンプレートをコピー
cp backend.tf.example backend.tf

# エディタで backend.tf を開く
# <YOUR_BUCKET_NAME> を Step 3で作成したバケット名に置き換え
```

**例:**
```hcl
terraform {
  backend "s3" {
    bucket       = "sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"  # ← 実際のバケット名
    key          = "tfstate/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

**Note:** `backend.tf` は `.gitignore` に追加されており、Gitにコミットされません（セキュリティのため）。

### Step 5: リソース用バケット作成

```bash
cd ../terraform/tfstate
terraform init
terraform apply
```

以下のバケットが作成されます：
- ✅ IAM用バケット
- ✅ KMS用バケット
- ✅ ECR用バケット
- ✅ Artifacts用バケット
- ✅ アクセスログ用バケット

---

## ✅ 完了！

セットアップが完了しました。次は各コンポーネント（IAM、KMS、ECR）の作成に進めます。

---

## 📝 次のステップ

### 1. IAMリソースの作成（準備中）

```bash
cd terraform/iam
terraform init
terraform apply
```

### 2. KMSキーの作成（準備中）

```bash
cd terraform/kms
terraform init
terraform apply
```

### 3. ECRリポジトリの作成（準備中）

```bash
cd terraform/ecr
terraform init
terraform apply
```

### 4. GitHub Workflowの設定（準備中）

- GitHubシークレットの設定
- Workflowの実行

---

## 🔍 確認コマンド

### 作成されたバケットの確認

```bash
# S3バケット一覧
aws s3 ls | grep sandbox-ecr-kms

# Terraformの出力確認
cd terraform/tfstate
terraform output
```

### 各バケットの確認

```bash
# バケット名を取得
terraform output bucket_names_by_type

# 特定のバケットの詳細
aws s3api head-bucket --bucket $(terraform output -raw iam_bucket_name)
```

---

## 🧹 削除手順

検証が終了したら、以下の順序でリソースを削除します：

### 1. 各コンポーネントを削除

```bash
cd terraform/ecr && terraform destroy
cd terraform/kms && terraform destroy
cd terraform/iam && terraform destroy
```

### 2. リソース用バケットを削除

```bash
cd terraform/tfstate
terraform destroy
```

### 3. tfstate用バケットを削除

```bash
BUCKET_NAME="sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"

# バケットを空にする
aws s3 rm s3://$BUCKET_NAME/ --recursive

# バケットを削除
aws s3 rb s3://$BUCKET_NAME
```

---

## 🆘 トラブルシューティング

### AWS認証エラー

```bash
# 設定を確認
aws configure list

# 再設定
aws configure
```

### Terraform初期化エラー

```bash
# versions.tf のバケット名が正しいか確認
cat terraform/tfstate/versions.tf | grep bucket

# キャッシュをクリアして再初期化
rm -rf .terraform
terraform init
```

### バケット名の重複エラー

S3バケット名はグローバルに一意である必要があります。

```bash
# スクリプト内の PROJECT_NAME を変更
# または手動で異なる名前を使用
```

---

## 📚 詳細ドキュメント

より詳しい情報は以下を参照してください：

- [AWS CLI と IAM設定ガイド](./setup-aws-cli-iam.md)
- [Terraform State用バケット作成ガイド](./setup-tfstate-bucket.md)
- [Terraform リソース用バケット管理](../terraform/tfstate/README.md)

---

## 💡 Tips

### コマンドのエイリアス

`.bashrc` または `.zshrc` に追加：

```bash
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
```

### よく使うコマンド

```bash
# 全バケットを一覧表示
aws s3 ls | grep sandbox

# Terraform出力をJSON形式で表示
terraform output -json | jq .

# 特定の出力のみ表示
terraform output -raw iam_bucket_name
```

---

## 🎯 成功の確認

以下が全て確認できれば、セットアップ完了です：

- [ ] AWS CLI認証が成功する
- [ ] tfstate用S3バケットが作成された
- [ ] `terraform init` が成功する
- [ ] リソース用バケットが5個作成された
- [ ] `terraform output` で全バケットが確認できる

---

Happy Hacking! 🚀

