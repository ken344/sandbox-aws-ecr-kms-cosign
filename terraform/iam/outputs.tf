# 出力定義

# OIDC Provider
output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "oidc_provider_url" {
  description = "URL of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.url
}

# IAM Role
output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.name
}

# Policies
output "ecr_access_policy_arn" {
  description = "ARN of the ECR access policy"
  value       = aws_iam_policy.ecr_access.arn
}

output "kms_signing_policy_arn" {
  description = "ARN of the KMS signing policy"
  value       = aws_iam_policy.kms_signing.arn
}

output "s3_artifacts_policy_arn" {
  description = "ARN of the S3 artifacts policy"
  value       = try(aws_iam_policy.s3_artifacts[0].arn, "")
}

output "cloudwatch_logs_policy_arn" {
  description = "ARN of the CloudWatch Logs policy"
  value       = aws_iam_policy.cloudwatch_logs.arn
}

# GitHub Workflow で使用する情報
output "github_workflow_config" {
  description = "Configuration for GitHub Workflow"
  value = {
    aws_region       = var.aws_region
    role_arn         = aws_iam_role.github_actions.arn
    role_session_name = "github-actions-session"
  }
}

# GitHub Secrets に設定する値
output "github_secrets" {
  description = "Values to set as GitHub Secrets"
  value = {
    AWS_REGION  = var.aws_region
    AWS_ROLE_ARN = aws_iam_role.github_actions.arn
  }
  sensitive = false
}

