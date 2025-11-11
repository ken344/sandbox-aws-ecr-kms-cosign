# 現在のAWSアカウントの情報を取得
data "aws_caller_identity" "current" {}

# 現在のRegionを取得
data "aws_region" "current" {}
