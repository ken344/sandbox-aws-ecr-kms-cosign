# 変数定義

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "tfstate_bucket_name" {
  description = "Name of the S3 bucket for terraform state"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "sandbox-ecr-kms"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "ecr_lifecycle_image_count" {
  description = "Number of images to keep in ECR lifecycle policy"
  type        = number
  default     = 10

  validation {
    condition     = var.ecr_lifecycle_image_count > 0 && var.ecr_lifecycle_image_count <= 1000
    error_message = "ECR lifecycle image count must be between 1 and 1000"
  }
}

variable "kms_deletion_window_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days"
  }
}

