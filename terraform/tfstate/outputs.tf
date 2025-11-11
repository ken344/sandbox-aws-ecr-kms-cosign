# リソースバケットの出力

# 全バケットの情報をマップで出力
output "resource_buckets" {
  description = "Map of all resource buckets with their details"
  value = {
    for key, bucket in module.resource_buckets : key => {
      id                          = bucket.s3_bucket_id
      arn                         = bucket.s3_bucket_arn
      bucket_domain_name          = bucket.s3_bucket_bucket_domain_name
      bucket_regional_domain_name = bucket.s3_bucket_bucket_regional_domain_name
      region                      = bucket.s3_bucket_region
    }
  }
}

# 個別のバケット名出力（他のTerraformモジュールから参照しやすいように）
output "iam_bucket_name" {
  description = "Name of the IAM resources bucket"
  value       = module.resource_buckets["iam"].s3_bucket_id
}

output "iam_bucket_arn" {
  description = "ARN of the IAM resources bucket"
  value       = module.resource_buckets["iam"].s3_bucket_arn
}

output "kms_bucket_name" {
  description = "Name of the KMS resources bucket"
  value       = module.resource_buckets["kms"].s3_bucket_id
}

output "kms_bucket_arn" {
  description = "ARN of the KMS resources bucket"
  value       = module.resource_buckets["kms"].s3_bucket_arn
}

output "ecr_bucket_name" {
  description = "Name of the ECR resources bucket"
  value       = module.resource_buckets["ecr"].s3_bucket_id
}

output "ecr_bucket_arn" {
  description = "ARN of the ECR resources bucket"
  value       = module.resource_buckets["ecr"].s3_bucket_arn
}

output "artifacts_bucket_name" {
  description = "Name of the artifacts bucket for GitHub Workflows"
  value       = module.resource_buckets["artifacts"].s3_bucket_id
}

output "artifacts_bucket_arn" {
  description = "ARN of the artifacts bucket"
  value       = module.resource_buckets["artifacts"].s3_bucket_arn
}

# アクセスログバケット
output "access_logs_bucket_name" {
  description = "Name of the access logs bucket"
  value       = module.access_logs_bucket.s3_bucket_id
}

output "access_logs_bucket_arn" {
  description = "ARN of the access logs bucket"
  value       = module.access_logs_bucket.s3_bucket_arn
}

# 他のモジュールで使いやすい形式で出力
output "bucket_names_by_type" {
  description = "Map of bucket types to bucket names"
  value = {
    for key, bucket in module.resource_buckets :
    key => bucket.s3_bucket_id
  }
}

output "bucket_arns_by_type" {
  description = "Map of bucket types to bucket ARNs"
  value = {
    for key, bucket in module.resource_buckets :
    key => bucket.s3_bucket_arn
  }
}

# 便利な一覧表示用
output "all_bucket_names" {
  description = "List of all created bucket names"
  value = concat(
    [for bucket in module.resource_buckets : bucket.s3_bucket_id],
    [module.access_logs_bucket.s3_bucket_id]
  )
}

