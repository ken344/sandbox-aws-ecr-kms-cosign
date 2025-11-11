provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "sandbox-aws-ecr-kms-cosign"
      ManagedBy  = "Terraform"
      Component  = "IAM"
      Repository = "sandbox-aws-ecr-kms-cosign"
    }
  }
}

