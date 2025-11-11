# 変数定義

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "tfstate_bucket_name" {
  description = "Name of the S3 bucket for terraform state (from bootstrap)"
  type        = string
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
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

