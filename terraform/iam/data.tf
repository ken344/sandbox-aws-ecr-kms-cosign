# 現在のAWSアカウント情報を取得
data "aws_caller_identity" "current" {}

# 現在のリージョンを取得
data "aws_region" "current" {}

# tfstate モジュールの出力を参照
data "terraform_remote_state" "tfstate" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket_name
    key    = "tfstate/terraform.tfstate"
    region = var.aws_region
  }
}

