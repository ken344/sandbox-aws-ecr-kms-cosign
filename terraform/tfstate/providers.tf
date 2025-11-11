provider "aws" {
    # AWSリージョンを指定(東京リージョン)
    region = "ap-northeast-1"

    default_tags {

        tags = {
            Project    = "sandbox-aws-ecr-kms-cosign"
            ManagedBy  = "terraform"
        }
    }
}