# コマンドリファレンス

ローカルからの検証で使用する主要なコマンド一覧です。

## 📋 目次

- [環境変数の設定](#環境変数の設定)
- [ECR操作](#ecr操作)
- [Cosign操作](#cosign操作)
- [KMS操作](#kms操作)
- [検証スクリプト](#検証スクリプト)

---

## 環境変数の設定

### 基本設定

```bash
# AWS設定
export AWS_REGION="ap-northeast-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# KMS設定（Terraformから取得）
cd terraform/image-registry
export KMS_KEY_ID=$(terraform output -raw kms_key_id)
export KMS_KEY_ARN=$(terraform output -raw kms_key_arn)
cd -

# ECR設定
export ECR_REPOSITORY="sample-app-1"
export IMAGE_TAG="test-$(date +%Y%m%d-%H%M%S)"
export IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

# 確認
echo "Registry: $ECR_REGISTRY"
echo "Image:    $IMAGE_URI"
echo "KMS Key:  $KMS_KEY_ID"
```

---

## ECR操作

### ログイン

```bash
# ECRにログイン（12時間有効）
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
```

### リポジトリ操作

```bash
# リポジトリ一覧
aws ecr describe-repositories

# 特定のリポジトリの詳細
aws ecr describe-repositories --repository-names $ECR_REPOSITORY

# ライフサイクルポリシーの確認
aws ecr get-lifecycle-policy --repository-name $ECR_REPOSITORY
```

### イメージ操作

```bash
# イメージ一覧
aws ecr list-images --repository-name $ECR_REPOSITORY

# イメージ詳細（最新10件）
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --query 'sort_by(imageDetails,& imagePushedAt)[-10:].[imageTags[0], imagePushedAt, imageSizeInBytes]' \
  --output table

# イメージ数のカウント
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --query 'length(imageDetails)' \
  --output text

# 特定のイメージの詳細
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG

# ダイジェストの取得
IMAGE_DIGEST=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG \
  --query 'imageDetails[0].imageDigest' \
  --output text)
```

### イメージのプッシュ

```bash
# ビルド（オプション）
docker build -t $IMAGE_URI .

# または既存イメージをタグ付け
docker pull alpine:latest
docker tag alpine:latest $IMAGE_URI

# プッシュ
docker push $IMAGE_URI
```

### イメージの削除

```bash
# 特定のイメージを削除
aws ecr batch-delete-image \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG

# ダイジェストで削除
aws ecr batch-delete-image \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageDigest=$IMAGE_DIGEST

# 複数イメージを削除
aws ecr batch-delete-image \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=test-1 imageTag=test-2

# 全イメージを削除
aws ecr batch-delete-image \
  --repository-name $ECR_REPOSITORY \
  --image-ids "$(aws ecr list-images --repository-name $ECR_REPOSITORY --query 'imageIds[*]' --output json)"

# 古いイメージから10個削除
OLD_DIGESTS=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --query 'sort_by(imageDetails,& imagePushedAt)[0:10].imageDigest' \
  --output json)

aws ecr batch-delete-image \
  --repository-name $ECR_REPOSITORY \
  --image-ids "$(echo $OLD_DIGESTS | jq -c '[.[] | {imageDigest: .}]')"
```

---

## Cosign操作

### 署名

```bash
# 基本的な署名
cosign sign --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST

# 非対話モード（スクリプト用）
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE_URI_WITH_DIGEST

# アノテーション付きで署名
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  --annotations="git-sha=$(git rev-parse HEAD)" \
  --annotations="build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --annotations="builder=local" \
  --yes \
  $IMAGE_URI_WITH_DIGEST

# 複数のアノテーション
cosign sign \
  --key awskms:///$KMS_KEY_ARN \
  -a version=1.0.0 \
  -a environment=dev \
  -a tested=true \
  --yes \
  $IMAGE_URI_WITH_DIGEST
```

### 検証

```bash
# 基本的な検証
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST

# JSON出力
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST --output=json

# 検証結果を整形
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST --output=json | jq .

# アノテーションを確認
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST --output=json | jq -r '.[0].optional'

# 特定のアノテーションで検証
cosign verify \
  --key awskms:///$KMS_KEY_ARN \
  --annotations="builder=local" \
  $IMAGE_URI_WITH_DIGEST
```

### 署名情報の確認

```bash
# 署名イメージのリファレンスを取得
cosign triangulate $IMAGE_URI
cosign triangulate $IMAGE_URI_WITH_DIGEST

# 署名が存在するか確認（終了コードで判定）
if cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI > /dev/null 2>&1; then
    echo "署名が存在します"
else
    echo "署名が存在しません"
fi
```

### パブリックキーの使用

```bash
# KMSからパブリックキーを取得
aws kms get-public-key \
  --key-id $KMS_KEY_ID \
  --query 'PublicKey' \
  --output text | base64 -d > public-key.der

# PEM形式に変換
openssl rsa -pubin -inform DER -in public-key.der -outform PEM -out public-key.pem

# パブリックキーで検証（KMSアクセス不要）
cosign verify --key public-key.pem $IMAGE_URI_WITH_DIGEST
```

---

## KMS操作

### キー情報の確認

```bash
# キーの詳細
aws kms describe-key --key-id $KMS_KEY_ID

# キーのメタデータのみ
aws kms describe-key --key-id $KMS_KEY_ID --query 'KeyMetadata' | jq .

# キーの状態確認
aws kms describe-key --key-id $KMS_KEY_ID --query 'KeyMetadata.KeyState' --output text

# キーの用途確認
aws kms describe-key --key-id $KMS_KEY_ID --query 'KeyMetadata.KeyUsage' --output text
# 出力: SIGN_VERIFY
```

### キーポリシー

```bash
# キーポリシーの取得
aws kms get-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --query 'Policy' \
  --output text | jq .

# キーポリシーのバックアップ
aws kms get-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --query 'Policy' \
  --output text > kms-policy-backup.json
```

### パブリックキー

```bash
# パブリックキーの取得
aws kms get-public-key --key-id $KMS_KEY_ID

# Base64デコードして保存
aws kms get-public-key \
  --key-id $KMS_KEY_ID \
  --query 'PublicKey' \
  --output text | base64 -d > public-key.der
```

### キーエイリアス

```bash
# エイリアス一覧
aws kms list-aliases --query 'Aliases[?contains(AliasName, `sandbox`)].{Alias:AliasName, KeyId:TargetKeyId}'

# 特定のエイリアスからキーIDを取得
aws kms describe-key --key-id alias/sandbox-ecr-kms/cosign --query 'KeyMetadata.KeyId' --output text
```

---

## 検証スクリプト

### 基本的な検証

```bash
# 簡単な検証（1イメージ）
cd scripts
./verify-ecr-cosign.sh

# 特定のリポジトリを指定
ECR_REPOSITORY=sample-app-2 ./verify-ecr-cosign.sh
```

### ライフサイクルテスト

```bash
# 15個のイメージをプッシュ（デフォルト）
./test-ecr-lifecycle.sh

# カスタム数を指定
./test-ecr-lifecycle.sh 20      # 20個プッシュ
./test-ecr-lifecycle.sh 20 10   # 20個プッシュ、ライフサイクル上限10個

# 特定のリポジトリで実行
ECR_REPOSITORY=sample-app-3 ./test-ecr-lifecycle.sh 15
```

---

## ワンライナーコマンド集

### イメージのプッシュから検証まで

```bash
# 環境変数設定 → ビルド → プッシュ → 署名 → 検証
export IMAGE_TAG="quick-test-$(date +%s)" && \
export IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}" && \
docker pull alpine:latest && \
docker tag alpine:latest $IMAGE_URI && \
docker push $IMAGE_URI && \
export IMAGE_DIGEST=$(aws ecr describe-images --repository-name $ECR_REPOSITORY --image-ids imageTag=$IMAGE_TAG --query 'imageDetails[0].imageDigest' --output text) && \
export IMAGE_URI_WITH_DIGEST="${ECR_REGISTRY}/${ECR_REPOSITORY}@${IMAGE_DIGEST}" && \
cosign sign --key awskms:///$KMS_KEY_ARN --yes $IMAGE_URI_WITH_DIGEST && \
cosign verify --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST
```

### 全リポジトリにイメージをプッシュ

```bash
for repo in sample-app-1 sample-app-2 sample-app-3; do
  echo "Processing $repo..."
  IMAGE_TAG="batch-$(date +%s)"
  IMAGE_URI="${ECR_REGISTRY}/${repo}:${IMAGE_TAG}"
  docker tag alpine:latest $IMAGE_URI
  docker push $IMAGE_URI
  sleep 2
  IMAGE_DIGEST=$(aws ecr describe-images --repository-name $repo --image-ids imageTag=$IMAGE_TAG --query 'imageDetails[0].imageDigest' --output text)
  cosign sign --key awskms:///$KMS_KEY_ARN --yes "${ECR_REGISTRY}/${repo}@${IMAGE_DIGEST}"
done
```

### 署名付きイメージのみ表示

```bash
# 署名イメージの一覧
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --query 'imageDetails[?imageTags && contains(to_string(imageTags), `.sig`)].{Tag:imageTags[0], Pushed:imagePushedAt}' \
  --output table
```

### イメージ数の監視

```bash
# 定期的にイメージ数を監視（10秒ごと）
watch -n 10 "aws ecr describe-images --repository-name $ECR_REPOSITORY --query 'length(imageDetails)' --output text"

# または
while true; do
  COUNT=$(aws ecr describe-images --repository-name $ECR_REPOSITORY --query 'length(imageDetails)' --output text)
  echo "$(date): Image count = $COUNT"
  sleep 60
done
```

---

## トラブルシューティング用コマンド

### Docker関連

```bash
# Dockerログイン状態の確認
docker info | grep -A 5 "Registry"

# ローカルイメージの確認
docker images | grep $ECR_REGISTRY

# ローカルイメージの削除
docker rmi $IMAGE_URI

# 未使用イメージの削除
docker image prune -a
```

### AWS認証

```bash
# 現在の認証情報
aws sts get-caller-identity

# 使用できるリージョン
aws ec2 describe-regions --query 'Regions[].RegionName' --output table

# IAMロールの確認
aws iam get-role --role-name sandbox-ecr-kms-github-actions-role
```

### デバッグ

```bash
# Cosignのデバッグログ
export COSIGN_VERBOSE=1
cosign sign --key awskms:///$KMS_KEY_ARN $IMAGE_URI_WITH_DIGEST

# AWS CLIのデバッグ
aws ecr describe-images --repository-name $ECR_REPOSITORY --debug

# Docker buildのデバッグ
docker build --progress=plain -t $IMAGE_URI .
```

---

## 便利なエイリアス

`.bashrc` または `.zshrc` に追加：

```bash
# ECR関連
alias ecr-login='aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-northeast-1.amazonaws.com'
alias ecr-list='aws ecr describe-repositories --query "repositories[].repositoryName" --output table'
alias ecr-images='aws ecr describe-images --repository-name'

# Cosign関連
alias cosign-sign-kms='cosign sign --key awskms:///$KMS_KEY_ARN --yes'
alias cosign-verify-kms='cosign verify --key awskms:///$KMS_KEY_ARN'

# 環境変数設定
alias set-ecr-env='export AWS_REGION=ap-northeast-1 && export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) && export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"'
```

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

