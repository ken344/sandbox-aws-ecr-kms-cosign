# 変数定義

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-northeast-1"
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

variable "force_destroy" {
  description = "Allow bucket destruction even with objects (use with caution)"
  type        = bool
  default     = true # 検証環境用
}

# 必要に応じて追加のバケット設定を外部から注入できるようにする（オプション）
variable "additional_buckets" {
  description = "Additional buckets to create beyond the default ones"
  type = map(object({
    name_suffix = string
    purpose     = string
    versioning  = bool
    lifecycle_rules = object({
      enabled                    = bool
      expire_noncurrent_days     = number
      abort_incomplete_upload_days = number
    })
    allowed_principals = list(string)
  }))
  default = {}
}

