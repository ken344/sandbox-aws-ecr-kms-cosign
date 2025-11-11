# ローカル変数定義
locals {
  # アカウント情報
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id

  # プロジェクト設定
  project_name = "sandbox-ecr-kms"
  environment  = "dev"

  # IAMモジュールから取得
  github_actions_role_arn  = try(data.terraform_remote_state.iam.outputs.github_actions_role_arn, "")
  github_actions_role_name = try(data.terraform_remote_state.iam.outputs.github_actions_role_name, "")

  # ECRリポジトリ定義
  # 新しいリポジトリを追加する場合は、ここに追加
  ecr_repositories = {
    sample-app-1 = {
      image_tag_mutability = "MUTABLE"
      scan_on_push         = true
      lifecycle_count      = var.ecr_lifecycle_image_count
    }
    sample-app-2 = {
      image_tag_mutability = "MUTABLE"
      scan_on_push         = true
      lifecycle_count      = var.ecr_lifecycle_image_count
    }
    sample-app-3 = {
      image_tag_mutability = "MUTABLE"
      scan_on_push         = true
      lifecycle_count      = var.ecr_lifecycle_image_count
    }
  }

  # 共通タグ
  common_tags = {
    Project     = "sandbox-aws-ecr-kms-cosign"
    Environment = local.environment
    ManagedBy   = "Terraform"
    Component   = "ImageRegistry"
  }
}

