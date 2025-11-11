# ローカル検証ガイド - ECR & Cosign署名

このドキュメントでは、ローカル環境からECRへのイメージプッシュ、Cosignでの署名、署名検証の手順を説明します。

## 📋 目次

- [前提条件](#前提条件)
- [環境変数の設定](#環境変数の設定)
- [Step 1: サンプルイメージの準備](#step-1-サンプルイメージの準備)
- [Step 2: ECRログイン](#step-2-ecrログイン)
- [Step 3: イメージのビルドとプッシュ](#step-3-イメージのビルドとプッシュ)
- [Step 4: Cosignでの署名](#step-4-cosignでの署名)
- [Step 5: 署名の検証](#step-5-署名の検証)
- [Step 6: 署名情報の確認](#step-6-署名情報の確認)
- [完全な検証スクリプト](#完全な検証スクリプト)
- [トラブルシューティング](#トラブルシューティング)

---

## 前提条件

### 必要なツール

1. **Docker**
   ```bash
   docker --version
   # Docker version 20.x 以降
   ```

2. **AWS CLI**
   ```bash
   aws --version
   # aws-cli/2.x 以降
   ```

3. **Cosign**
   ```bash
   # macOS
   brew install cosign
   
   # または直接ダウンロード
   curl -O -L "https://github.com/sigstore/cosign/releases/latest/download/cosign-darwin-arm64"
   sudo mv cosign-darwin-arm64 /usr/local/bin/cosign
   sudo chmod +x /usr/local/bin/cosign
   
   # バージョン確認
   cosign version
   ```

4. **jq**（オプション、JSONパース用）
   ```bash
   brew install jq
   ```

### AWS認証情報

AWS CLIが正しく設定されていることを確認：

```bash
aws sts get-caller-identity
```

---

## 環境変数の設定

Terraformの出力から必要な値を取得して環境変数に設定します。

### Step 1: Terraform出力の取得

```bash
cd terraform/image-registry

# 必要な値を取得
export AWS_REGION=$(terraform output -raw github_workflow_config | jq -r .aws_region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export KMS_KEY_ID=$(terraform output -raw kms_key_id)
export KMS_KEY_ARN=$(terraform output -raw kms_key_arn)

# ECRリポジトリ名
export ECR_REPOSITORY="sample-app-1"
export IMAGE_TAG="test-$(date +%Y%m%d-%H%M%S)"
export IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

# 確認
echo "AWS Region:      $AWS_REGION"
echo "AWS Account ID:  $AWS_ACCOUNT_ID"
echo "ECR Registry:    $ECR_REGISTRY"
echo "KMS Key ID:      $KMS_KEY_ID"
echo "Image URI:       $IMAGE_URI"
```

### Step 2: 環境変数の保存（オプション）

毎回設定するのが面倒な場合は、ファイルに保存：

```bash
cat > ~/ecr-test-env.sh << EOF
export AWS_REGION="ap-northeast-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ECR_REGISTRY="\${AWS_ACCOUNT_ID}.dkr.ecr.\${AWS_REGION}.amazonaws.com"
export KMS_KEY_ID="$(cd terraform/image-registry && terraform output -raw kms_key_id)"
export KMS_KEY_ARN="$(cd terraform/image-registry && terraform output -raw kms_key_arn)"
export ECR_REPOSITORY="sample-app-1"
EOF

# 使用時
source ~/ecr-test-env.sh
export IMAGE_TAG="test-$(date +%Y%m%d-%H%M%S)"
export IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
```

---

## Step 1: サンプルイメージの準備

### オプション A: 既存のイメージを使用

```bash
# Alpine Linuxを使用（軽量）
docker pull alpine:latest
docker tag alpine:latest $IMAGE_URI
```

### オプション B: 簡単なDockerfileを作成

```bash
# 作業ディレクトリ作成
mkdir -p ~/ecr-test-app
cd ~/ecr-test-app

# Dockerfileを作成
cat > Dockerfile << 'EOF'
FROM alpine:latest

# メタデータを追加
LABEL org.opencontainers.image.source="https://github.com/your-org/sandbox-aws-ecr-kms-cosign"
LABEL org.opencontainers.image.description="Test application for ECR and Cosign"
LABEL org.opencontainers.image.version="1.0.0"

# シンプルなスクリプトを追加
RUN echo '#!/bin/sh' > /app.sh && \
    echo 'echo "Hello from ECR!"' >> /app.sh && \
    echo 'echo "Image signed with Cosign"' >> /app.sh && \
    chmod +x /app.sh

CMD ["/app.sh"]
EOF

# ビルド
docker build -t $IMAGE_URI .
```

### オプション C: マルチアーキテクチャイメージ

```bash
# buildxを使用してマルチアーキテクチャビルド
docker buildx create --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t $IMAGE_URI \
  --push \
  .
```

---

## Step 2: ECRログイン

```bash
# ECRにログイン
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# 成功メッセージ:
# Login Succeeded
```

**トラブルシューティング:**

```bash
# 認証情報の有効期限は12時間
# 再ログインが必要な場合は上記コマンドを再実行

# ログイン状態の確認
docker info | grep -A 5 "Registry:"
```

---

## Step 3: イメージのビルドとプッシュ

### イメージのプッシュ

```bash
# イメージをECRにプッシュ
docker push $IMAGE_URI

# 成功メッセージ例:
# The push refers to repository [123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/sample-app-1]
# abc123def456: Pushed
# test-20251110-123456: digest: sha256:... size: 1234
```

### プッシュ結果の確認

```bash
# ECR上のイメージを確認
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'sort_by(imageDetails,& imagePushedAt)[-5:].[imageTags[0], imagePushedAt, imageSizeInBytes]' \
  --output table

# 特定のイメージの詳細
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG \
  --region $AWS_REGION
```

### イメージのダイジェスト取得

```bash
# イメージのダイジェストを取得（署名に必要）
IMAGE_DIGEST=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG \
  --region $AWS_REGION \
  --query 'imageDetails[0].imageDigest' \
  --output text)

echo "Image Digest: $IMAGE_DIGEST"

# ダイジェスト付きイメージURI
IMAGE_URI_WITH_DIGEST="${ECR_REGISTRY}/${ECR_REPOSITORY}@${IMAGE_DIGEST}"
echo "Image URI with Digest: $IMAGE_URI_WITH_DIGEST"
```

---

## Step 4: Cosignでの署名

### 基本的な署名

```bash
# AWS KMSキーを使用して署名
cosign sign --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST

# 成功メッセージ:
# Generating ephemeral keys...
# Retrieving signed certificate...
# Successfully uploaded signature for ...
```

**重要**: ダイジェスト（`@sha256:...`）を使用することを推奨。タグ（`:test-...`）は変更される可能性があるため。

### 署名にアノテーションを追加

```bash
# メタデータを含めて署名
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --annotations="git-sha=$(git rev-parse HEAD)" \
  --annotations="build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --annotations="builder=local" \
  $IMAGE_URI_WITH_DIGEST
```

### 署名の確認（ECR上）

```bash
# 署名もECRにイメージとして保存されます
# 署名のタグは sha256-<digest>.sig 形式

aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'imageDetails[?contains(imageTags[0], `.sig`)].{Tag:imageTags[0], Size:imageSizeInBytes, Pushed:imagePushedAt}' \
  --output table
```

---

## Step 5: 署名の検証

### 基本的な検証

```bash
# AWS KMSキーを使用して検証
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST

# 成功時の出力例:
# Verification for 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/sample-app-1@sha256:... --
# The following checks were performed on each of these signatures:
#   - The cosign claims were validated
#   - The signatures were verified against the specified public key
```

### 検証結果をJSON形式で取得

```bash
# 詳細な検証結果
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST --output=json | jq .

# 出力例:
# [
#   {
#     "critical": {
#       "identity": {
#         "docker-reference": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/sample-app-1"
#       },
#       "image": {
#         "docker-manifest-digest": "sha256:..."
#       },
#       "type": "cosign container image signature"
#     },
#     "optional": {
#       "git-sha": "abc123...",
#       "build-date": "2025-11-10T12:34:56Z",
#       "builder": "local"
#     }
#   }
# ]
```

### アノテーションの検証

```bash
# 特定のアノテーションが含まれていることを確認
cosign verify \
  --key awskms:///$KMS_KEY_ARN \
  --annotations="builder=local" \
  $IMAGE_URI_WITH_DIGEST

# アノテーションが一致しない場合はエラーになります
```

---

## Step 6: 署名情報の確認

### 署名の存在確認

```bash
# 署名が存在するか確認
cosign triangulate $IMAGE_URI_WITH_DIGEST

# 出力例（署名イメージのリファレンス）:
# 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/sample-app-1:sha256-abc123def456.sig
```

### パブリックキーの取得

```bash
# KMSからパブリックキーを取得
aws kms get-public-key \
  --key-id $KMS_KEY_ID \
  --region $AWS_REGION \
  --query 'PublicKey' \
  --output text | base64 -d > public-key.der

# PEM形式に変換
openssl rsa -pubin -inform DER -in public-key.der -outform PEM -out public-key.pem

# パブリックキーの確認
cat public-key.pem
```

### パブリックキーを使用した検証

```bash
# PEMファイルを使用して検証（KMSキーへのアクセス不要）
cosign verify --key public-key.pem $IMAGE_URI_WITH_DIGEST
```

---

## 完全な検証スクリプト

以下は、全ての手順を自動化したスクリプトです。

### スクリプトの作成

```bash
cat > ~/ecr-cosign-test.sh << 'SCRIPT_END'
#!/bin/bash
set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
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

# 環境変数の設定
print_section "環境変数の設定"

export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# KMS Key IDをTerraformから取得
if [ -d "terraform/image-registry" ]; then
    cd terraform/image-registry
    export KMS_KEY_ARN=$(terraform output -raw kms_key_arn 2>/dev/null)
    cd - > /dev/null
fi

if [ -z "$KMS_KEY_ARN" ]; then
    print_error "KMS_KEY_ARN が設定されていません"
    print_info "手動で設定してください: export KMS_KEY_ARN='arn:aws:kms:...'"
    exit 1
fi

export ECR_REPOSITORY="${ECR_REPOSITORY:-sample-app-1}"
export IMAGE_TAG="test-$(date +%Y%m%d-%H%M%S)"
export IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

print_info "AWS Region:      $AWS_REGION"
print_info "ECR Registry:    $ECR_REGISTRY"
print_info "Repository:      $ECR_REPOSITORY"
print_info "Image Tag:       $IMAGE_TAG"
print_info "KMS Key ARN:     $KMS_KEY_ARN"

# Step 1: イメージの準備
print_section "Step 1: イメージの準備"

print_info "Alpine Linuxをプルしています..."
docker pull alpine:latest
docker tag alpine:latest $IMAGE_URI
print_success "イメージを準備しました: $IMAGE_URI"

# Step 2: ECRログイン
print_section "Step 2: ECRログイン"

print_info "ECRにログインしています..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
print_success "ECRログインに成功しました"

# Step 3: イメージのプッシュ
print_section "Step 3: イメージのプッシュ"

print_info "イメージをプッシュしています..."
docker push $IMAGE_URI
print_success "イメージをプッシュしました"

# Step 4: ダイジェストの取得
print_section "Step 4: ダイジェストの取得"

sleep 2  # ECRの反映を待つ

IMAGE_DIGEST=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG \
  --region $AWS_REGION \
  --query 'imageDetails[0].imageDigest' \
  --output text)

IMAGE_URI_WITH_DIGEST="${ECR_REGISTRY}/${ECR_REPOSITORY}@${IMAGE_DIGEST}"
print_info "Image Digest: $IMAGE_DIGEST"
print_info "Image URI:    $IMAGE_URI_WITH_DIGEST"

# Step 5: Cosign署名
print_section "Step 5: Cosign署名"

print_info "Cosignで署名しています..."
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --annotations="test-run=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --annotations="builder=local-script" \
  $IMAGE_URI_WITH_DIGEST
print_success "署名が完了しました"

# Step 6: 署名の検証
print_section "Step 6: 署名の検証"

print_info "署名を検証しています..."
if cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST > /dev/null 2>&1; then
    print_success "署名の検証に成功しました！"
else
    print_error "署名の検証に失敗しました"
    exit 1
fi

# Step 7: 結果の表示
print_section "検証結果"

print_info "署名情報:"
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST --output=json | jq -r '.[0].optional'

print_success "全ての検証が完了しました！"

echo ""
print_info "作成されたリソース:"
echo "  Image URI:  $IMAGE_URI"
echo "  Digest:     $IMAGE_DIGEST"
echo "  Signature:  $(cosign triangulate $IMAGE_URI_WITH_DIGEST)"
SCRIPT_END

# 実行権限を付与
chmod +x ~/ecr-cosign-test.sh
```

### スクリプトの実行

```bash
# 実行
~/ecr-cosign-test.sh

# または、特定のリポジトリを指定
ECR_REPOSITORY=sample-app-2 ~/ecr-cosign-test.sh
```

---

## トラブルシューティング

### 問題1: ECRログインエラー

**エラー:**
```
Error saving credentials: error storing credentials
```

**解決方法:**
```bash
# Docker credentialsヘルパーの設定
rm ~/.docker/config.json
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
```

### 問題2: Cosign署名エラー

**エラー:**
```
Error: signing [awskms:///arn:...]: getting signer: fetching public key: AccessDenied
```

**解決方法:**
```bash
# IAMポリシーを確認
aws iam list-attached-user-policies --user-name $(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)

# KMSキーへのアクセス権限を確認
aws kms describe-key --key-id $KMS_KEY_ID
```

### 問題3: 署名検証エラー

**エラー:**
```
Error: no matching signatures
```

**解決方法:**
```bash
# 署名が存在するか確認
cosign triangulate $IMAGE_URI_WITH_DIGEST

# ECR上の署名イメージを確認
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --query 'imageDetails[?contains(imageTags[0], `.sig`)]' \
  --output table
```

### 問題4: ダイジェスト取得エラー

**エラー:**
```
An error occurred (ImageNotFoundException)
```

**解決方法:**
```bash
# イメージがプッシュされるまで少し待つ
sleep 5

# イメージの存在確認
aws ecr describe-images --repository-name $ECR_REPOSITORY
```

---

## 📝 GitHub Workflowとの比較

### ローカル検証

- ✅ 即座にテスト可能
- ✅ デバッグが容易
- ✅ インタラクティブな操作
- ❌ 手動実行が必要
- ❌ 環境依存

### GitHub Workflow

- ✅ 自動化
- ✅ CI/CD統合
- ✅ 再現性が高い
- ✅ マルチプラットフォーム対応
- ❌ デバッグが難しい
- ❌ 実行時間が長い

**推奨**: ローカルで検証後、GitHub Workflowで自動化

---

## 📚 参考コマンド集

### ECR関連

```bash
# リポジトリ一覧
aws ecr describe-repositories

# イメージ一覧（最新5件）
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --query 'sort_by(imageDetails,& imagePushedAt)[-5:]' \
  --output table

# イメージの削除
aws ecr batch-delete-image \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG

# すべてのイメージを削除
aws ecr batch-delete-image \
  --repository-name $ECR_REPOSITORY \
  --image-ids "$(aws ecr list-images --repository-name $ECR_REPOSITORY --query 'imageIds[*]' --output json)"
```

### Cosign関連

```bash
# バージョン確認
cosign version

# 署名の存在確認
cosign triangulate $IMAGE_URI

# 署名情報の詳細表示
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI --output=text

# 複数の署名を確認
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI | jq -r '.[].optional'
```

### KMS関連

```bash
# キー情報の取得
aws kms describe-key --key-id $KMS_KEY_ID

# パブリックキーの取得
aws kms get-public-key --key-id $KMS_KEY_ID

# キーポリシーの確認
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default
```

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

