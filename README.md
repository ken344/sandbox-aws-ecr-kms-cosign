# sandbox-aws-ecr-kms-cosign

AWS ECR、KMS、Cosignを使用したコンテナイメージの署名とライフサイクル管理の検証プロジェクト

## 📋 プロジェクト概要

このプロジェクトは以下の検証を目的としています：

- ✅ AWS ECRへのコンテナイメージのプッシュ
- ✅ AWS KMSを使用したイメージへの署名（Cosign）
- ✅ 署名ファイルのECRへの保存
- ✅ 複数のコンテナイメージの同時ビルド
- ✅ ECRライフサイクルポリシーの検証
- ✅ GitHub Workflowによる自動化とレポート生成

## 🚀 セットアップガイド

### 前提条件

- AWSアカウント
- Gitリポジトリ（GitHub）
- Terraform CLI
- Docker

### セットアップ手順

1. **AWS CLIとIAMの設定** ✅
   - [AWS CLI と IAM設定ガイド](./docs/setup-aws-cli-iam.md) を参照してください

2. **Terraform Backendの構築** ✅
   - [Terraform セットアップガイド](./docs/terraform-setup-guide.md) を参照してください
   - S3バケットの作成（tfstate保存用）
   - 各コンポーネントのBackend設定

3. **AWSリソースのデプロイ**（準備中）
   - IAMロール（GitHub Actions用）
   - KMSキー
   - ECRリポジトリ

4. **GitHub Workflowの設定**（準備中）
   - シークレットの設定
   - Workflowの実行

## 📁 プロジェクト構成

```
.
├── docs/                           # ドキュメント
│   ├── adr/                       # Architecture Decision Records
│   ├── setup-aws-cli-iam.md       # AWS CLI/IAM設定ガイド ✅
│   └── terraform-setup-guide.md   # Terraform セットアップガイド ✅
│
├── scripts/                        # セットアップスクリプト
│   └── setup-tfstate-bucket.sh   # tfstate用S3バケット作成 ✅
│
├── terraform/                      # Terraformコード
│   ├── tfstate/                   # リソース用バケット管理 ✅
│   │   ├── main.tf               # terraform-aws-moduleでバケット作成
│   │   ├── locals.tf             # バケット定義（for_each対応）
│   │   ├── versions.tf           # Terraform/Provider設定
│   │   ├── backend.tf            # S3 backend設定（.gitignoreで除外）
│   │   ├── backend.tf.example    # Backend設定テンプレート
│   │   ├── providers.tf          # AWSプロバイダー
│   │   ├── data.tf               # データソース
│   │   ├── variables.tf          # 変数定義
│   │   ├── outputs.tf            # 出力定義
│   │   ├── .gitignore            # Git除外設定
│   │   └── README.md             # ドキュメント
│   │
│   ├── iam/                       # IAMリソース（準備中）
│   ├── kms/                       # KMSリソース（準備中）
│   └── ecr/                       # ECRリソース（準備中）
│
└── README.md                       # このファイル
```

## 🔧 技術スタック

- **Infrastructure as Code**: Terraform
- **Container Registry**: AWS ECR
- **Signing**: Cosign + AWS KMS
- **CI/CD**: GitHub Actions
- **Container Runtime**: Docker

## 📚 ドキュメント

### セットアップガイド

- **[📖 クイックスタートガイド](./docs/QUICKSTART.md)** - 最速でセットアップする方法 ⭐
- [AWS CLI と IAM設定ガイド](./docs/setup-aws-cli-iam.md) - AWS認証の設定方法
- [Terraform State用バケット作成ガイド](./docs/setup-tfstate-bucket.md) - tfstate保存用S3バケットの作成
- [Terraform State Lock について](./docs/terraform-state-lock.md) - v1.10の新機能（DynamoDB不要）
- [Terraform リソース用バケット管理](./terraform/tfstate/README.md) - リソース用バケットの作成と管理
- [ローカル検証ガイド](./docs/local-verification-guide.md) - ECR & Cosign署名の検証手順
- [ライフサイクル手動テストガイド](./docs/manual-lifecycle-test.md) - ライフサイクルポリシーの手動検証
- [GitHub Secrets 設定ガイド](./docs/github-secrets-setup.md) - Secrets設定とエイリアス使用の推奨
- [Cosign バージョン移行ガイド](./docs/cosign-version-migration.md) - v2.x から v3.x への移行
- [Transparency Log (Rekor) 詳細ガイド](./docs/transparency-log-rekor.md) - Rekorの仕組みと使用判断
- [コマンドリファレンス](./docs/command-reference.md) - よく使うコマンド一覧

### 実行手順

#### 1. AWS CLI設定（完了している場合はスキップ）

```bash
# AWS CLIの設定
aws configure

# 認証確認
aws sts get-caller-identity
```

#### 2. Terraform State用S3バケット作成

```bash
# スクリプトで作成（推奨）
cd scripts
./setup-tfstate-bucket.sh

# または手動でAWS CLIコマンド実行
# 詳細は docs/setup-tfstate-bucket.md を参照
```

#### 3. Backend設定とリソース用バケット作成

```bash
cd terraform/tfstate

# Backend設定ファイルを作成
cp backend.tf.example backend.tf
# backend.tf を編集してバケット名を更新

# Terraform初期化
terraform init

# リソース用バケット作成
terraform apply

# 作成されたバケットを確認
terraform output
```

#### 4. 他のコンポーネントのデプロイ（準備中）

```bash
# 順番にデプロイ
cd terraform/iam && terraform init && terraform apply
cd terraform/kms && terraform init && terraform apply
cd terraform/ecr && terraform init && terraform apply
```

## ⚠️ 注意事項

このプロジェクトは**検証用サンドボックス**です。

- 検証後はリソースを削除してください（`terraform destroy`）
- KMSキーは課金が発生します（約$1/月）
- IAMユーザーやアクセスキーは適切に管理してください

## 📝 ライセンス

MIT License

## 🤝 コントリビューション

このプロジェクトは個人の検証用です。
