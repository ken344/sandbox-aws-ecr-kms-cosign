terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.14.1, < 7.0.0"
    }
  }

  # Backend設定は backend.tf に分離しています
  # backend.tf は .gitignore に追加されており、Gitにコミットされません
  # 
  # セットアップ方法:
  # 1. backend.tf.example を backend.tf にコピー
  # 2. バケット名を実際の値に置換
  # 3. terraform init を実行
  # 
  # 詳細は README.md を参照してください
}

