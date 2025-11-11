#!/bin/bash

# ECR ライフサイクルポリシー テストスクリプト
# 
# このスクリプトは、ECRのライフサイクルポリシーが正しく動作するかをテストします。
# 指定した数以上のイメージをプッシュして、古いイメージが削除されることを確認します。
#
# 使用方法:
#   ./test-ecr-lifecycle.sh [push-count]
#   
# 例:
#   ./test-ecr-lifecycle.sh 15  # 15個のイメージをプッシュ

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

# 引数の処理
PUSH_COUNT=${1:-15}  # デフォルト15個
LIFECYCLE_LIMIT=${2:-10}  # デフォルト10個（terraform.tfvarsの設定値）

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_section "ECR ライフサイクルポリシー テスト"

print_info "設定:"
echo "  プッシュするイメージ数: $PUSH_COUNT"
echo "  ライフサイクル上限: $LIFECYCLE_LIMIT"

# 環境変数の設定
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export ECR_REPOSITORY="${ECR_REPOSITORY:-sample-app-1}"

print_info "ECR Repository: $ECR_REPOSITORY"

# Step 1: 初期状態の確認
print_section "Step 1: 初期状態の確認"

INITIAL_COUNT=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'length(imageDetails)' \
  --output text 2>/dev/null || echo "0")

print_info "現在のイメージ数: $INITIAL_COUNT"

# Step 2: ECRログイン
print_section "Step 2: ECRログイン"

print_info "ECRにログインしています..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY > /dev/null 2>&1
print_success "ECRログインに成功しました"

# Step 3: イメージの連続プッシュ
print_section "Step 3: イメージの連続プッシュ"

print_info "Alpine Linuxイメージをプルしています..."
docker pull alpine:latest > /dev/null 2>&1

print_info "$PUSH_COUNT 個のイメージをプッシュします..."

for i in $(seq 1 $PUSH_COUNT); do
    IMAGE_TAG="lifecycle-test-$(printf "%03d" $i)"
    IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
    
    # タグ付け
    docker tag alpine:latest $IMAGE_URI
    
    # プッシュ
    print_info "[$i/$PUSH_COUNT] プッシュ中: $IMAGE_TAG"
    docker push $IMAGE_URI > /dev/null 2>&1
    
    # 少し待機（負荷軽減）
    sleep 1
done

print_success "全てのイメージをプッシュしました"

# Step 4: プッシュ直後のイメージ数確認
print_section "Step 4: プッシュ直後の確認"

sleep 2  # 反映を待つ

CURRENT_COUNT=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'length(imageDetails)' \
  --output text)

print_info "プッシュ直後のイメージ数: $CURRENT_COUNT"

# イメージ一覧を表示
print_info "イメージ一覧（最新10件）:"
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'sort_by(imageDetails,& imagePushedAt)[-10:].[imageTags[0], imagePushedAt]' \
  --output table

# Step 5: ライフサイクルポリシーの確認
print_section "Step 5: ライフサイクルポリシーの確認"

print_info "ライフサイクルポリシー:"
aws ecr get-lifecycle-policy \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'lifecyclePolicyText' \
  --output text | jq . || true

# Step 6: ライフサイクル適用待機の説明
print_section "Step 6: ライフサイクルポリシーの適用"

print_warning "重要: ライフサイクルポリシーの適用には時間がかかります"
echo ""
echo "  ECRのライフサイクルポリシーは、通常24時間ごとに評価されます。"
echo "  即座には削除されないため、以下の方法で確認してください:"
echo ""
echo "  1. 数時間後に再度イメージ数を確認"
echo "  2. AWSコンソールでライフサイクルポリシーの実行ログを確認"
echo "  3. GitHub Workflowで定期的に実行して自動チェック"
echo ""

# Step 7: 手動でのイメージ削除（オプション）
print_section "Step 7: 手動でのライフサイクルシミュレーション"

if [ "$CURRENT_COUNT" -gt "$LIFECYCLE_LIMIT" ]; then
    EXCESS_COUNT=$((CURRENT_COUNT - LIFECYCLE_LIMIT))
    print_info "ライフサイクル上限を超えています: $EXCESS_COUNT 個"
    
    echo ""
    read -p "古いイメージを手動で削除しますか？ (yes/no): " -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        print_info "最も古い $EXCESS_COUNT 個のイメージを削除します..."
        
        # 古いイメージから削除
        OLD_IMAGES=$(aws ecr describe-images \
          --repository-name $ECR_REPOSITORY \
          --region $AWS_REGION \
          --query "sort_by(imageDetails,& imagePushedAt)[0:$EXCESS_COUNT].imageDigest" \
          --output json)
        
        for digest in $(echo $OLD_IMAGES | jq -r '.[]'); do
            print_info "削除中: $digest"
            aws ecr batch-delete-image \
              --repository-name $ECR_REPOSITORY \
              --region $AWS_REGION \
              --image-ids imageDigest=$digest > /dev/null 2>&1
        done
        
        print_success "古いイメージを削除しました"
        
        # 削除後の確認
        sleep 2
        AFTER_DELETE_COUNT=$(aws ecr describe-images \
          --repository-name $ECR_REPOSITORY \
          --region $AWS_REGION \
          --query 'length(imageDetails)' \
          --output text)
        
        print_info "削除後のイメージ数: $AFTER_DELETE_COUNT"
    fi
fi

# Step 8: 最終結果
print_section "テスト結果サマリー"

FINAL_COUNT=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'length(imageDetails)' \
  --output text)

echo ""
print_info "リポジトリ: $ECR_REPOSITORY"
echo "  初期イメージ数:         $INITIAL_COUNT"
echo "  プッシュしたイメージ数: $PUSH_COUNT"
echo "  プッシュ直後:           $CURRENT_COUNT"
echo "  最終イメージ数:         $FINAL_COUNT"
echo "  ライフサイクル上限:     $LIFECYCLE_LIMIT"
echo ""

if [ "$FINAL_COUNT" -le "$LIFECYCLE_LIMIT" ]; then
    print_success "✓ ライフサイクルポリシーが正しく機能しています（または手動削除完了）"
else
    print_warning "ライフサイクルポリシーの自動適用を待っています"
    print_info "24時間後に再度確認してください"
fi

echo ""
print_info "確認コマンド:"
echo "  # 現在のイメージ数"
echo "  aws ecr describe-images --repository-name $ECR_REPOSITORY --query 'length(imageDetails)' --output text"
echo ""
echo "  # イメージ一覧"
echo "  aws ecr describe-images --repository-name $ECR_REPOSITORY --query 'sort_by(imageDetails,& imagePushedAt)[*].[imageTags[0], imagePushedAt]' --output table"

print_success "ライフサイクルテストが完了しました！"

