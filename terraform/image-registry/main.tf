# ECR、KMS、IAMリソースの作成
# Reference:
# - ECR: https://registry.terraform.io/modules/terraform-aws-modules/ecr/aws/latest
# - KMS: https://registry.terraform.io/modules/terraform-aws-modules/kms/aws/latest

# ============================================================================
# KMS Key for Image Signing (Cosign)
# ============================================================================

module "kms_cosign" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 3.0"

  description = "KMS key for container image signing with Cosign"
  key_usage   = "SIGN_VERIFY"

  # 非対称キー（署名用）
  customer_master_key_spec = "RSA_2048"

  # キーポリシー
  enable_key_rotation = false # 非対称キーはローテーション非対応

  # キーの削除保護期間
  deletion_window_in_days = 7

  # キーエイリアス
  aliases = ["${local.project_name}/cosign"]

  # タグ
  tags = merge(
    local.common_tags,
    {
      Name    = "${local.project_name}-cosign-key"
      Purpose = "Container image signing"
    }
  )
}

# KMS Key Policy: GitHub Actionsロールに署名権限を付与
resource "aws_kms_key_policy" "cosign" {
  key_id = module.kms_cosign.key_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Root アカウントに完全な権限
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # GitHub Actionsロールに署名権限
      {
        Sid    = "Allow GitHub Actions to use the key for signing"
        Effect = "Allow"
        Principal = {
          AWS = local.github_actions_role_arn
        }
        Action = [
          "kms:Sign",
          "kms:Verify",
          "kms:GetPublicKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:KeyUsage" = "SIGN_VERIFY"
          }
        }
      }
    ]
  })
}

# ============================================================================
# ECR Repositories
# ============================================================================

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 2.0"

  for_each = local.ecr_repositories

  repository_name = each.key

  # リポジトリ設定
  repository_image_tag_mutability = each.value.image_tag_mutability
  repository_image_scan_on_push   = each.value.scan_on_push

  # 削除保護（検証環境なのでfalse）
  repository_force_delete = true

  # ライフサイクルポリシー
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${each.value.lifecycle_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = each.value.lifecycle_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  # リポジトリポリシー（GitHub Actionsからのアクセスを許可）
  repository_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGitHubActions"
        Effect = "Allow"
        Principal = {
          AWS = local.github_actions_role_arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
      }
    ]
  })

  # タグ
  tags = merge(
    local.common_tags,
    {
      Name       = each.key
      Repository = each.key
    }
  )
}

# ============================================================================
# IAM Policy Update: Specific KMS Key Access
# ============================================================================

# KMS署名権限を特定のキーに限定するポリシー
resource "aws_iam_policy" "kms_cosign_specific" {
  name        = "${local.project_name}-github-actions-kms-cosign-specific"
  description = "Allow GitHub Actions to sign with specific KMS key"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSCosignSigningAccess"
        Effect = "Allow"
        Action = [
          "kms:Sign",
          "kms:Verify",
          "kms:GetPublicKey",
          "kms:DescribeKey"
        ]
        Resource = module.kms_cosign.key_arn
        Condition = {
          StringEquals = {
            "kms:KeyUsage" = "SIGN_VERIFY"
          }
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-kms-cosign-specific-policy"
    }
  )
}

# 既存のGitHub ActionsロールにKMSポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "kms_cosign_specific" {
  role       = local.github_actions_role_name
  policy_arn = aws_iam_policy.kms_cosign_specific.arn
}

# ============================================================================
# IAM Policy: ECR Repository Specific Access
# ============================================================================

# ECRリポジトリへの具体的なアクセス権限
resource "aws_iam_policy" "ecr_repositories_specific" {
  name        = "${local.project_name}-github-actions-ecr-repos-specific"
  description = "Allow GitHub Actions to access specific ECR repositories"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRRepositoriesAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:DescribeRepositories"
        ]
        Resource = [
          for repo_name, repo in module.ecr : repo.repository_arn
        ]
      },
      {
        Sid    = "ECRGetAuthorizationToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-ecr-repos-specific-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "ecr_repositories_specific" {
  role       = local.github_actions_role_name
  policy_arn = aws_iam_policy.ecr_repositories_specific.arn
}

