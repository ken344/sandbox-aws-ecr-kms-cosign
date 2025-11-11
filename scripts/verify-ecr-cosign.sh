#!/bin/bash

# ECR & Cosign 検証スクリプト
# 
# このスクリプトは以下を実行します:
# 1. イメージのビルドとECRへのプッシュ
# 2. Cosignでの署名
# 3. 署名の検証
#
# 使用方法:
#   ./verify-ecr-cosign.sh
#   ECR_REPOSITORY=sample-app-2 ./verify-ecr-cosign.sh

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_section "ECR & Cosign 検証スクリプト"

# Step 1: 前提条件の確認
print_info "前提条件を確認しています..."

# Docker確認
if ! command -v docker &> /dev/null; then
    print_error "Docker がインストールされていません"
    exit 1
fi
print_success "Docker: $(docker --version | cut -d' ' -f3)"

# AWS CLI確認
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI がインストールされていません"
    exit 1
fi
print_success "AWS CLI: $(aws --version | cut -d' ' -f1 | cut -d'/' -f2)"

# Cosign確認
if ! command -v cosign &> /dev/null; then
    print_error "Cosign がインストールされていません"
    print_info "インストール方法: brew install cosign"
    exit 1
fi
print_success "Cosign: $(cosign version --json 2>/dev/null | jq -r .gitVersion || cosign version 2>&1 | head -1)"

# jq確認（オプション）
if ! command -v jq &> /dev/null; then
    print_warning "jq がインストールされていません（オプション）"
    print_info "インストール推奨: brew install jq"
fi

# Step 2: 環境変数の設定
print_section "環境変数の設定"

export AWS_REGION="${AWS_REGION:-ap-northeast-1}"

# AWS認証確認
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS認証に失敗しました"
    print_info "AWS CLIを設定してください: aws configure"
    exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# KMS Key ARNをTerraformから取得
if [ -d "$PROJECT_ROOT/terraform/image-registry" ]; then
    cd "$PROJECT_ROOT/terraform/image-registry"
    export KMS_KEY_ARN=$(terraform output -raw kms_key_arn 2>/dev/null || echo "")
    export KMS_KEY_ID=$(terraform output -raw kms_key_id 2>/dev/null || echo "")
    cd - > /dev/null
fi

if [ -z "$KMS_KEY_ARN" ]; then
    print_error "KMS_KEY_ARN を取得できませんでした"
    print_info "Terraformでリソースを作成してください"
    print_info "または手動で設定: export KMS_KEY_ARN='arn:aws:kms:...'"
    exit 1
fi

export ECR_REPOSITORY="${ECR_REPOSITORY:-sample-app-1}"
export IMAGE_TAG="test-$(date +%Y%m%d-%H%M%S)"
export IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

print_info "AWS Region:      $AWS_REGION"
print_info "AWS Account ID:  $AWS_ACCOUNT_ID"
print_info "ECR Registry:    $ECR_REGISTRY"
print_info "Repository:      $ECR_REPOSITORY"
print_info "Image Tag:       $IMAGE_TAG"
print_info "KMS Key ID:      $KMS_KEY_ID"

# Step 3: イメージの準備
print_section "Step 1: イメージの準備"

print_info "Alpine Linuxイメージをプルしています..."
docker pull alpine:latest > /dev/null 2>&1
docker tag alpine:latest $IMAGE_URI
print_success "イメージを準備しました: $IMAGE_URI"

# Step 4: ECRログイン
print_section "Step 2: ECRログイン"

print_info "ECRにログインしています..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY > /dev/null 2>&1
print_success "ECRログインに成功しました"

# Step 5: イメージのプッシュ
print_section "Step 3: イメージのプッシュ"

print_info "イメージをプッシュしています（数秒かかります）..."
docker push $IMAGE_URI > /dev/null 2>&1
print_success "イメージをプッシュしました"

# Step 6: ダイジェストの取得
print_section "Step 4: ダイジェストの取得"

print_info "イメージダイジェストを取得しています..."
sleep 3  # ECRの反映を待つ

IMAGE_DIGEST=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG \
  --region $AWS_REGION \
  --query 'imageDetails[0].imageDigest' \
  --output text 2>/dev/null)

if [ -z "$IMAGE_DIGEST" ]; then
    print_error "イメージダイジェストを取得できませんでした"
    print_info "ECRの反映を待っています（5秒）..."
    sleep 5
    IMAGE_DIGEST=$(aws ecr describe-images \
      --repository-name $ECR_REPOSITORY \
      --image-ids imageTag=$IMAGE_TAG \
      --region $AWS_REGION \
      --query 'imageDetails[0].imageDigest' \
      --output text)
fi

IMAGE_URI_WITH_DIGEST="${ECR_REGISTRY}/${ECR_REPOSITORY}@${IMAGE_DIGEST}"
print_info "Image Digest: $IMAGE_DIGEST"
print_success "イメージURI:  $IMAGE_URI_WITH_DIGEST"

# Step 7: Cosign署名
print_section "Step 5: Cosign署名"

print_info "Cosignで署名しています..."

# Git情報を取得（オプション）
GIT_SHA=""
if git rev-parse HEAD &> /dev/null; then
    GIT_SHA=$(git rev-parse HEAD)
fi

# 署名実行
if [ -n "$GIT_SHA" ]; then
    cosign sign \
      --key awskms:///$KMS_KEY_ARN \
      --annotations="test-run=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --annotations="builder=local-script" \
      --annotations="git-sha=$GIT_SHA" \
      --yes \
      $IMAGE_URI_WITH_DIGEST
else
    cosign sign \
      --key awskms:///$KMS_KEY_ARN \
      --annotations="test-run=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --annotations="builder=local-script" \
      --yes \
      $IMAGE_URI_WITH_DIGEST
fi

print_success "署名が完了しました"

# Step 8: 署名の検証
print_section "Step 6: 署名の検証"

print_info "署名を検証しています..."

if cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST > /dev/null 2>&1; then
    print_success "✓ 署名の検証に成功しました！"
else
    print_error "署名の検証に失敗しました"
    
    # デバッグ情報
    print_info "デバッグ情報:"
    print_info "署名イメージ: $(cosign triangulate $IMAGE_URI_WITH_DIGEST)"
    
    aws ecr describe-images \
      --repository-name $ECR_REPOSITORY \
      --query 'imageDetails[?contains(imageTags[0], `.sig`)].{Tag:imageTags[0]}' \
      --output table
    
    exit 1
fi

# Step 9: 結果の表示
print_section "検証結果"

print_info "署名情報:"
if command -v jq &> /dev/null; then
    cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST 2>/dev/null | jq -r '.[0].optional' || true
else
    cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST 2>/dev/null | grep -A 10 "optional" || true
fi

echo ""
print_info "署名イメージのリファレンス:"
SIGNATURE_REF=$(cosign triangulate $IMAGE_URI_WITH_DIGEST)
echo "  $SIGNATURE_REF"

# Step 10: ECR上の確認
print_section "ECR上のイメージ確認"

print_info "リポジトリ内のイメージ（最新5件）:"
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'sort_by(imageDetails,& imagePushedAt)[-5:].[imageTags[0], imagePushedAt, imageSizeInBytes]' \
  --output table 2>/dev/null || true

print_info "署名イメージ:"
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'imageDetails[?contains(imageTags[0], `.sig`)].{Tag:imageTags[0], Size:imageSizeInBytes, Pushed:imagePushedAt}' \
  --output table 2>/dev/null || true

# 完了
print_section "検証完了"

print_success "全ての検証が正常に完了しました！"

echo ""
print_info "作成されたリソース:"
echo "  Repository:  $ECR_REPOSITORY"
echo "  Image Tag:   $IMAGE_TAG"
echo "  Image URI:   $IMAGE_URI"
echo "  Digest:      $IMAGE_DIGEST"
echo "  Signature:   $SIGNATURE_REF"

echo ""
print_info "次のステップ:"
echo "  1. GitHub Workflowでの自動化"
echo "  2. 複数イメージのプッシュでライフサイクルテスト"
echo "  3. CI/CDパイプラインへの統合"

echo ""
print_info "クリーンアップ:"
echo "  # このイメージを削除"
echo "  aws ecr batch-delete-image --repository-name $ECR_REPOSITORY --image-ids imageTag=$IMAGE_TAG"

