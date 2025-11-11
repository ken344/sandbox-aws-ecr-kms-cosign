# ローカル変数定義
locals {
  # アカウント情報
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id

  # プロジェクト設定
  project_name = "sandbox-ecr-kms"
  environment  = "dev"

  # GitHub情報（変数から取得、またはデフォルト値）
  github_org  = var.github_org
  github_repo = var.github_repo

  # tfstateモジュールから取得したバケット情報
  artifacts_bucket_arn = try(data.terraform_remote_state.tfstate.outputs.artifacts_bucket_arn, "")

  # 共通タグ
  common_tags = {
    Project     = "sandbox-aws-ecr-kms-cosign"
    Environment = local.environment
    ManagedBy   = "Terraform"
    Component   = "IAM"
  }
}

