# terraform-aws-modules/s3-bucket を使用してリソース用バケットを作成
# Reference: https://registry.terraform.io/modules/terraform-aws-modules/s3-bucket/aws/latest

module "resource_buckets" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.2"  # 最新の4.xバージョン

  for_each = local.resource_buckets

  # バケット基本設定
  bucket        = local.bucket_names[each.key]
  force_destroy = true # 検証環境用：削除時にオブジェクトがあっても削除可能

  # バージョニング設定
  versioning = {
    enabled = each.value.versioning
  }

  # サーバーサイド暗号化設定（デフォルトでAES256）
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
      bucket_key_enabled = true
    }
  }

  # パブリックアクセスブロック設定（全てブロック）
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # ライフサイクルルール設定
  lifecycle_rule = each.value.lifecycle_rules.enabled ? [
    {
      id      = "cleanup-old-versions"
      enabled = true

      # 古いバージョンの削除
      noncurrent_version_expiration = {
        days = each.value.lifecycle_rules.expire_noncurrent_days
      }

      # 不完全なマルチパートアップロードのクリーンアップ
      abort_incomplete_multipart_upload_days = each.value.lifecycle_rules.abort_incomplete_upload_days
    }
  ] : []

  # オブジェクト所有権設定
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # タグ設定
  tags = merge(
    local.common_tags,
    {
      Name    = local.bucket_names[each.key]
      Purpose = each.value.purpose
      Type    = each.key
    }
  )
}

# アクセスログ用バケット（オプション）
module "access_logs_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.2"  # 最新の4.xバージョン

  bucket        = "${local.project_name}-access-logs-${local.account_id}-${local.region}"
  force_destroy = true

  # ログバケット用の設定
  versioning = {
    enabled = false
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # パブリックアクセスブロック
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # ライフサイクルルール（ログの保持期間）
  lifecycle_rule = [
    {
      id      = "expire-logs"
      enabled = true

      expiration = {
        days = 90 # 90日後にログを削除
      }
    }
  ]

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  tags = merge(
    local.common_tags,
    {
      Name    = "${local.project_name}-access-logs"
      Purpose = "S3 Access Logs"
    }
  )
}

# リソースバケットへのアクセスログ設定
resource "aws_s3_bucket_logging" "resource_buckets" {
  for_each = local.resource_buckets

  bucket = module.resource_buckets[each.key].s3_bucket_id

  target_bucket = module.access_logs_bucket.s3_bucket_id
  target_prefix = "${each.key}/"
}

