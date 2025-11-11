#!/bin/bash

# Terraform State用 S3バケット セットアップスクリプト
# このスクリプトは、Terraformのtfstateを保存するためのS3バケットを作成します。

set -e  # エラーが発生したら即座に終了

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ヘルパー関数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# メイン処理
print_section "Terraform State S3 Bucket Setup"

# Step 1: 前提条件の確認
print_info "前提条件を確認しています..."

# AWS CLIの確認
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI がインストールされていません"
    exit 1
fi
print_success "AWS CLI: $(aws --version)"

# AWS認証の確認
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS認証に失敗しました"
    print_info "以下のコマンドでAWS CLIを設定してください:"
    print_info "  aws configure"
    exit 1
fi

# Step 2: 変数の設定
print_section "設定情報"

PROJECT_NAME="sandbox-ecr-kms"
REGION="${AWS_REGION:-ap-northeast-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}-${REGION}"

print_info "プロジェクト名: $PROJECT_NAME"
print_info "AWSアカウントID: $ACCOUNT_ID"
print_info "リージョン: $REGION"
print_info "バケット名: $BUCKET_NAME"

# Step 3: 既存バケットの確認
print_section "既存バケットの確認"

if aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null; then
    print_warning "バケット '$BUCKET_NAME' は既に存在します"
    echo ""
    read -p "既存のバケットを使用しますか？ (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        print_info "セットアップをキャンセルしました"
        exit 0
    fi
    print_info "既存のバケットの設定を更新します"
    BUCKET_EXISTS=true
else
    print_info "バケット '$BUCKET_NAME' は存在しません（新規作成します）"
    BUCKET_EXISTS=false
fi

# Step 4: 確認プロンプト
echo ""
read -p "続行しますか？ (yes/no): " -r
echo ""
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    print_warning "セットアップをキャンセルしました"
    exit 0
fi

# Step 5: バケット作成または設定更新
print_section "S3バケットのセットアップ"

if [ "$BUCKET_EXISTS" = false ]; then
    # バケット作成
    print_info "1. S3バケットを作成しています..."
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
          --bucket $BUCKET_NAME \
          --region $REGION
    else
        aws s3api create-bucket \
          --bucket $BUCKET_NAME \
          --region $REGION \
          --create-bucket-configuration LocationConstraint=$REGION
    fi
    print_success "バケットを作成しました"
else
    print_info "1. 既存のバケットを使用します"
fi

# バージョニング有効化
print_info "2. バージョニングを有効化しています..."
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
print_success "バージョニングを有効化しました"

# 暗号化有効化
print_info "3. 暗号化を有効化しています..."
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'
print_success "暗号化を有効化しました"

# パブリックアクセスブロック
print_info "4. パブリックアクセスをブロックしています..."
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
print_success "パブリックアクセスをブロックしました"

# タグ追加
print_info "5. タグを追加しています..."
aws s3api put-bucket-tagging \
  --bucket $BUCKET_NAME \
  --tagging 'TagSet=[
    {Key=Project,Value=sandbox-aws-ecr-kms-cosign},
    {Key=Purpose,Value=TerraformState},
    {Key=ManagedBy,Value=Script},
    {Key=Environment,Value=dev}
  ]'
print_success "タグを追加しました"

# Step 6: 検証
print_section "設定の検証"

print_info "バージョニング:"
aws s3api get-bucket-versioning --bucket $BUCKET_NAME | jq .

print_info "暗号化:"
aws s3api get-bucket-encryption --bucket $BUCKET_NAME | jq .

print_info "パブリックアクセスブロック:"
aws s3api get-public-access-block --bucket $BUCKET_NAME | jq .

# Step 7: 完了メッセージ
print_section "セットアップ完了"

echo ""
print_success "Terraform State用S3バケットのセットアップが完了しました！"
echo ""

print_info "作成されたバケット:"
echo "  名前: $BUCKET_NAME"
echo "  リージョン: $REGION"
echo ""

print_info "次のステップ:"
echo "  1. terraform/tfstate/versions.tf を開く"
echo "  2. backend \"s3\" の bucket を以下に変更:"
echo "     bucket = \"$BUCKET_NAME\""
echo ""
echo "  3. Terraform を初期化:"
echo "     cd terraform/tfstate"
echo "     terraform init"
echo ""
echo "  4. リソース用バケットを作成:"
echo "     terraform apply"
echo ""

print_info "確認コマンド:"
echo "  # バケット一覧"
echo "  aws s3 ls | grep tfstate"
echo ""
echo "  # バケット設定確認"
echo "  aws s3api get-bucket-versioning --bucket $BUCKET_NAME"
echo "  aws s3api get-bucket-encryption --bucket $BUCKET_NAME"
echo ""

print_success "セットアップスクリプトが正常に完了しました！"

