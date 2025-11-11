# ローカル変数定義
locals {
  # アカウント情報
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id

  # プロジェクト共通設定
  project_name = "sandbox-ecr-kms"
  environment  = "dev"

  # リソース用バケット定義
  # 新しいリソースディレクトリが追加されるごとに、ここに追加する
  resource_buckets = {
    # IAMリソース用バケット（例：IAMポリシードキュメントの保存）
    iam = {
      name_suffix = "iam"
      purpose     = "IAM related resources"
      versioning  = false
      lifecycle_rules = {
        enabled                    = true
        expire_noncurrent_days     = 30
        abort_incomplete_upload_days = 7
      }
      # 特定のIAMロールにのみアクセスを許可する場合
      allowed_principals = []
    }

    # KMSリソース用バケット（例：KMS暗号化されたデータの保存）
    kms = {
      name_suffix = "kms"
      purpose     = "KMS related resources"
      versioning  = true
      lifecycle_rules = {
        enabled                    = true
        expire_noncurrent_days     = 90
        abort_incomplete_upload_days = 7
      }
      allowed_principals = []
    }

    # ECRリソース用バケット（例：イメージスキャン結果、脆弱性レポート等）
    ecr = {
      name_suffix = "ecr"
      purpose     = "ECR related resources"
      versioning  = true
      lifecycle_rules = {
        enabled                    = true
        expire_noncurrent_days     = 30
        abort_incomplete_upload_days = 7
      }
      allowed_principals = []
    }

    # GitHub Workflowアーティファクト用バケット（テスト結果、レポート等）
    artifacts = {
      name_suffix = "artifacts"
      purpose     = "GitHub Workflow artifacts and reports"
      versioning  = false
      lifecycle_rules = {
        enabled                    = true
        expire_noncurrent_days     = 7
        abort_incomplete_upload_days = 1
      }
      # GitHub Actions用IAMロールのARN（後で設定）
      allowed_principals = []
    }
  }

  # バケット名の生成（統一的な命名規則）
  bucket_names = {
    for key, config in local.resource_buckets :
    key => "${local.project_name}-${config.name_suffix}-${local.account_id}-${local.region}"
  }

  # 共通タグ
  common_tags = {
    Project     = "sandbox-aws-ecr-kms-cosign"
    Environment = local.environment
    ManagedBy   = "Terraform"
    Component   = "ResourceBuckets"
  }
}

