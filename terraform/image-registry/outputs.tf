# 出力定義

# ============================================================================
# KMS Outputs
# ============================================================================

output "kms_key_id" {
  description = "KMS key ID for Cosign signing"
  value       = module.kms_cosign.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN for Cosign signing"
  value       = module.kms_cosign.key_arn
}

output "kms_key_alias" {
  description = "KMS key alias"
  value       = try(module.kms_cosign.aliases["${local.project_name}/cosign"], "")
}

# ============================================================================
# ECR Outputs
# ============================================================================

output "ecr_repository_urls" {
  description = "Map of ECR repository URLs"
  value = {
    for name, repo in module.ecr : name => repo.repository_url
  }
}

output "ecr_repository_arns" {
  description = "Map of ECR repository ARNs"
  value = {
    for name, repo in module.ecr : name => repo.repository_arn
  }
}

output "ecr_repository_names" {
  description = "List of ECR repository names"
  value       = [for name, repo in module.ecr : name]
}

output "ecr_registry_id" {
  description = "ECR registry ID"
  value       = try(module.ecr["sample-app-1"].repository_registry_id, "")
}

# ============================================================================
# IAM Outputs
# ============================================================================

output "kms_cosign_policy_arn" {
  description = "ARN of the KMS Cosign specific policy"
  value       = aws_iam_policy.kms_cosign_specific.arn
}

output "ecr_repositories_policy_arn" {
  description = "ARN of the ECR repositories specific policy"
  value       = aws_iam_policy.ecr_repositories_specific.arn
}

# ============================================================================
# GitHub Workflow Configuration
# ============================================================================

output "github_workflow_config" {
  description = "Configuration values for GitHub Workflow"
  value = {
    aws_region            = var.aws_region
    kms_key_id            = module.kms_cosign.key_id
    kms_key_arn           = module.kms_cosign.key_arn
    ecr_registry          = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
    ecr_repositories      = { for name, repo in module.ecr : name => repo.repository_url }
    lifecycle_image_count = var.ecr_lifecycle_image_count
  }
}

# ============================================================================
# GitHub Secrets Values
# ============================================================================

output "github_secrets" {
  description = "Values to set as GitHub Secrets"
  value = {
    AWS_REGION         = var.aws_region
    KMS_KEY_ID         = module.kms_cosign.key_id
    ECR_REGISTRY       = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
    ECR_REPOSITORY_1   = "sample-app-1"
    ECR_REPOSITORY_2   = "sample-app-2"
    ECR_REPOSITORY_3   = "sample-app-3"
  }
  sensitive = false
}

# ============================================================================
# Summary Output
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    kms_key_id           = module.kms_cosign.key_id
    kms_key_alias        = try(module.kms_cosign.aliases["${local.project_name}/cosign"], "")
    ecr_repository_count = length(module.ecr)
    ecr_repositories     = keys(module.ecr)
    lifecycle_policy     = "Keep last ${var.ecr_lifecycle_image_count} images"
  }
}

