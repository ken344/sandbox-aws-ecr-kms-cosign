# Terraform State Lock について

## 概要

このドキュメントでは、Terraform v1.10で導入された新しいState Lock機能（`use_lockfile`）について説明します。

---

## State Lockとは？

### 目的

複数の人やプロセスが同時にTerraformを実行した場合、tfstateファイルが破損する可能性があります。State Lockは、この問題を防ぐために、Terraform実行中にstateファイルをロックする機能です。

### 動作

1. `terraform apply` 開始時にstateをロック
2. 他の人が同時に実行しようとするとエラーになる
3. `terraform apply` 完了時にロックを解除

---

## Terraform v1.10の新機能

### 従来の方式（~v1.9）: DynamoDB必須

S3 Backendでロックを有効にするには、**DynamoDBテーブルが必要**でした。

#### 設定例

```hcl
backend "s3" {
  bucket         = "my-tfstate-bucket"
  key            = "terraform.tfstate"
  region         = "ap-northeast-1"
  encrypt        = true
  dynamodb_table = "terraform-lock"  # DynamoDBテーブルが必要
}
```

#### DynamoDBテーブルの作成

```bash
aws dynamodb create-table \
  --table-name terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-1
```

#### デメリット

- ❌ 追加のDynamoDBテーブルが必要
- ❌ テーブルの作成・管理が必要
- ❌ IAMポリシーにDynamoDB権限が必要
- ❌ 追加コスト（わずかですが月額数円〜）
- ❌ 構成が複雑

---

### 新しい方式（v1.10~）: use_lockfile

Terraform v1.10から、**DynamoDBなし**でS3だけでロックが可能になりました。

#### 設定例

```hcl
terraform {
  required_version = ">= 1.10.0"
  
  backend "s3" {
    bucket       = "my-tfstate-bucket"
    key          = "terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true  # これだけでOK！
  }
}
```

#### メリット

- ✅ **DynamoDB不要**: S3だけで完結
- ✅ **シンプル**: 追加リソース不要
- ✅ **コスト削減**: DynamoDBコストがゼロ
- ✅ **管理が容易**: S3だけを管理すればOK
- ✅ **IAM権限がシンプル**: S3権限のみでOK

---

## 仕組み

### use_lockfile の動作

1. **ロック取得時**
   - S3バケット内に `.terraform.lock.info` ファイルを作成
   - このファイルにロック情報を記録

2. **ロック保持中**
   - 他のプロセスがロックファイルの存在を確認
   - ロックが存在する場合はエラーを返す

3. **ロック解放時**
   - `.terraform.lock.info` ファイルを削除

### ロックファイルの場所

```
s3://my-bucket/
├── terraform.tfstate
└── .terraform.lock.info  # ← ロックファイル（一時的）
```

### ロックファイルの内容

```json
{
  "ID": "abc123...",
  "Operation": "OperationTypeApply",
  "Info": "",
  "Who": "user@hostname",
  "Version": "1.10.0",
  "Created": "2025-11-10T12:34:56Z",
  "Path": "terraform.tfstate"
}
```

---

## 使用方法

### 1. Terraform v1.10以上を使用

```bash
# バージョン確認
terraform version

# 出力例
# Terraform v1.10.0
# on darwin_arm64
```

### 2. Backend設定を更新

```hcl
terraform {
  required_version = ">= 1.10.0"
  
  backend "s3" {
    bucket       = "sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1"
    key          = "terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true  # ← 追加
  }
}
```

### 3. 通常通りTerraformを実行

```bash
terraform init
terraform plan
terraform apply
```

ロックは自動的に管理されます！

---

## ロックの動作確認

### ロックの確認

別のターミナルで同時に実行してみます：

**ターミナル1:**
```bash
terraform apply
# 実行中...
```

**ターミナル2:**
```bash
terraform apply
# Error: Error acquiring the state lock
# 
# Error message: Lock Info:
#   ID:        abc123...
#   Path:      terraform.tfstate
#   Operation: OperationTypeApply
#   Who:       user@hostname
#   Version:   1.10.0
#   Created:   2025-11-10 12:34:56
#   Info:      
# 
# Terraform acquires a lock when accessing your state.
# This lock has already been acquired by another Terraform process.
```

### ロックの強制解除（緊急時のみ）

```bash
# プロセスが異常終了してロックが残ってしまった場合
terraform force-unlock <LOCK_ID>

# 例
terraform force-unlock abc123...
```

**⚠️ 警告**: 他のプロセスが実行中の場合、強制解除するとstateファイルが破損する可能性があります。

---

## 比較表

| 項目 | 従来の方式（DynamoDB） | 新しい方式（use_lockfile） |
|------|---------------------|------------------------|
| **Terraformバージョン** | ~v1.9 | v1.10~ |
| **必要なリソース** | S3 + DynamoDB | S3のみ |
| **設定の複雑さ** | 複雑 | シンプル |
| **追加コスト** | DynamoDBコスト | なし |
| **IAM権限** | S3 + DynamoDB | S3のみ |
| **管理の手間** | テーブル管理が必要 | S3のみ |
| **ロック速度** | 高速 | 高速 |
| **信頼性** | 高い | 高い |

---

## よくある質問

### Q1: 既存のDynamoDBベースのロックから移行できますか？

**A:** はい、可能です。

```hcl
# 旧設定（削除）
backend "s3" {
  bucket         = "my-bucket"
  dynamodb_table = "terraform-lock"  # ← これを削除
}

# 新設定
backend "s3" {
  bucket       = "my-bucket"
  use_lockfile = true  # ← これを追加
}
```

```bash
# 再初期化
terraform init -reconfigure

# DynamoDBテーブルは手動で削除
aws dynamodb delete-table --table-name terraform-lock
```

### Q2: use_lockfile を使わない場合はどうなりますか？

**A:** ロックが無効になり、複数人が同時に実行するとstateファイルが破損する可能性があります。

**推奨**: 必ず `use_lockfile = true` を設定してください。

### Q3: S3のバージョニングは必要ですか？

**A:** はい、推奨します。

- ロックとは別に、stateファイルの誤削除・破損対策としてバージョニングを有効にしてください。

### Q4: チーム開発で問題なく使えますか？

**A:** はい、問題ありません。

- 複数人が同時に実行した場合、正しくロックが働きます。
- DynamoDBベースのロックと同等の信頼性があります。

### Q5: ロックファイルはGitにコミットすべきですか？

**A:** いいえ。

- ロックファイルはS3上に作成される一時ファイルです。
- ローカルには作成されないため、Gitに含める必要はありません。

---

## トラブルシューティング

### 問題1: ロックが取得できない

**エラー:**
```
Error: Error acquiring the state lock
```

**原因:**
- 別のプロセスが実行中
- 前回の実行が異常終了してロックが残っている

**解決方法:**
```bash
# 1. 他のプロセスが実行中でないか確認
ps aux | grep terraform

# 2. 実行中のプロセスがない場合は強制解除
terraform force-unlock <LOCK_ID>
```

### 問題2: use_lockfile が認識されない

**エラー:**
```
Error: Unsupported argument
```

**原因:** Terraform バージョンが古い

**解決方法:**
```bash
# Terraformをv1.10以上にアップグレード
brew upgrade terraform

# または公式サイトからダウンロード
```

### 問題3: S3への書き込み権限エラー

**エラー:**
```
Error: Failed to save state: AccessDenied
```

**原因:** S3バケットへの書き込み権限がない

**解決方法:**

IAMポリシーに以下を追加：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::my-bucket/*"
    }
  ]
}
```

---

## まとめ

### 推奨設定

```hcl
terraform {
  required_version = ">= 1.10.0"
  
  backend "s3" {
    bucket       = "your-tfstate-bucket"
    key          = "terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true  # 必ず設定
  }
}
```

### チェックリスト

- [ ] Terraform v1.10以上を使用
- [ ] `use_lockfile = true` を設定
- [ ] S3バケットにバージョニングを有効化
- [ ] S3バケットに暗号化を有効化
- [ ] 適切なIAM権限を設定

---

## 参考リンク

- [Terraform v1.10 Release Notes](https://github.com/hashicorp/terraform/releases/tag/v1.10.0)
- [S3 Backend Documentation](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [State Locking](https://developer.hashicorp.com/terraform/language/state/locking)

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

