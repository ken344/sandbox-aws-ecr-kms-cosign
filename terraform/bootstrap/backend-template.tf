# Backend Configuration Template
# 
# このファイルは各コンポーネント（iam, kms, ecr等）で使用するbackend設定のテンプレートです。
# 
# 使い方:
# 1. このファイルを各コンポーネントディレクトリにコピー
# 2. <COMPONENT_NAME> を実際のコンポーネント名に置換（例: iam, kms, ecr）
# 3. ファイル名を versions.tf に変更
# 4. 必要に応じてprovider設定を追加
#
# 例:
#   cd terraform/iam
#   cp ../bootstrap/backend-template.tf versions.tf
#   # versions.tf 内の <COMPONENT_NAME> を iam に置換

terraform {
  required_version = ">= 1.10.0"  # use_lockfile 機能を使用するため

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # バケット名は bootstrap の output から取得した値を設定
    # または terraform output -raw terraform_state_bucket_name で確認
    bucket = "<BUCKET_NAME>"  # 例: sandbox-ecr-kms-tfstate-123456789012-ap-northeast-1
    
    # コンポーネントごとに一意のキーを設定
    key = "<COMPONENT_NAME>/terraform.tfstate"  # 例: iam/terraform.tfstate
    
    # リージョンは bootstrap と同じリージョンを使用
    region = "ap-northeast-1"  # bootstrap の region と一致させる
    
    # 暗号化を有効化
    encrypt = true
    
    # State Lock（Terraform v1.10+、DynamoDB不要）
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "sandbox-aws-ecr-kms-cosign"
      ManagedBy  = "Terraform"
      Component  = "<COMPONENT_NAME>"  # 例: IAM, KMS, ECR
      Repository = "sandbox-aws-ecr-kms-cosign"
    }
  }
}

