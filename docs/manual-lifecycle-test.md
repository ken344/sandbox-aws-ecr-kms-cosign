# ECR ライフサイクルポリシー 手動テストガイド

このドキュメントでは、ECRのライフサイクルポリシーをローカル環境から手動でテストする手順を説明します。

## 📋 目次

- [概要](#概要)
- [前提条件](#前提条件)
- [手動テスト手順](#手動テスト手順)
- [結果の解釈](#結果の解釈)
- [トラブルシューティング](#トラブルシューティング)

---

## 概要

### テストの目的

ECRのライフサイクルポリシーが正しく設定されているか確認：
- 設定した上限（デフォルト: 10個）を超えるイメージをプッシュ
- 古いイメージが自動削除されることを確認

### ライフサイクルポリシーの動作

- **評価タイミング**: 約24時間ごと
- **削除基準**: プッシュ時刻が古い順
- **削除対象**: `countNumber` を超えるイメージ

---

## 前提条件

- ✅ AWS CLI設定済み
- ✅ Docker インストール済み
- ✅ ECRリポジトリが作成済み（terraform/image-registry）
- ✅ ECRにログイン済み

---

## 手動テスト手順

### 準備: 環境変数の設定

```bash
# AWS設定
export AWS_REGION="ap-northeast-1"
export AWS_ACCOUNT_ID="123456789012"  # 対象のAWSアカウントIDに置き換えてください
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# ECR設定
export ECR_REPOSITORY="sample-app-1"
export LIFECYCLE_LIMIT=10

# 確認
echo "ECR Repository: $ECR_REPOSITORY"
echo "Lifecycle Limit: $LIFECYCLE_LIMIT"
```

---

### Step 1: 初期状態の確認

```bash
# 現在のイメージ数を確認
INITIAL_COUNT=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'length(imageDetails)' \
  --output text)

echo "=== 初期状態 ==="
echo "現在のイメージ数: $INITIAL_COUNT"
```

---

### Step 2: ライフサイクルポリシーの確認

```bash
# 設定されているライフサイクルポリシーを確認
echo "=== ライフサイクルポリシー ==="
aws ecr get-lifecycle-policy \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'lifecyclePolicyText' \
  --output text | jq .
```

**確認ポイント**:
```json
{
  "rules": [
    {
      "selection": {
        "countNumber": 10  // ← この値を確認
      }
    }
  ]
}
```

---

### Step 3: ECRログイン（必要な場合）

```bash
# ECRにログイン（12時間有効）
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
```

---

### Step 4: 異なる内容のイメージを15個作成

重要：**異なるダイジェスト**のイメージを作成する必要があります。

```bash
echo "=== イメージのビルド & プッシュ開始 ==="

# 作業ディレクトリ作成
mkdir -p ~/ecr-lifecycle-test
cd ~/ecr-lifecycle-test

# 15個の異なるイメージをビルド & プッシュ
for i in {1..15}; do
  IMAGE_TAG=$(printf "unique-test-%03d" $i)
  IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
  
  echo "[$i/15] ビルド & プッシュ中: $IMAGE_TAG"
  
  # 毎回異なる内容のDockerfileを作成
  cat > Dockerfile << EOF
FROM alpine:latest

RUN echo "Image number: $i" > /image-id.txt && \
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /image-id.txt && \
    echo "Random: \$RANDOM" >> /image-id.txt

CMD cat /image-id.txt
EOF
  
  # ビルド
  docker build -t $IMAGE_URI .
  
  # プッシュ
  docker push $IMAGE_URI
  
  echo "  ✓ 完了: $IMAGE_TAG"
  sleep 1
done

echo "=== ビルド & プッシュ完了 ==="

# 元のディレクトリに戻る
cd -
```

**所要時間**: 約5-7分

**ポイント**:
- 各Dockerfileに異なる内容を含める
- タイムスタンプと乱数で確実に異なるイメージにする
- 各イメージが異なるダイジェストを持つ

---

### Step 5: プッシュ後のイメージ数確認

```bash
# 少し待機（ECRの反映を待つ）
sleep 3

CURRENT_COUNT=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'length(imageDetails)' \
  --output text)

echo "=== プッシュ直後 ==="
echo "初期イメージ数:   $INITIAL_COUNT"
echo "プッシュしたイメージ: 15"
echo "現在の総イメージ数: $CURRENT_COUNT"
echo "期待値:           $(($INITIAL_COUNT + 15))"
echo ""

if [ $CURRENT_COUNT -eq $(($INITIAL_COUNT + 15)) ]; then
  echo "✓ 全てのイメージが正常にプッシュされました"
else
  echo "⚠ イメージ数が期待値と異なります"
fi
```

---

### Step 6: イメージの詳細一覧

```bash
# 全イメージを時系列で表示
echo "=== 全イメージ一覧（プッシュ順） ==="
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'sort_by(imageDetails,& imagePushedAt)[*].[imageTags[0], imagePushedAt, imageSizeInBytes]' \
  --output table
```

**確認ポイント**:
- 最も古いイメージは何か？
- 最も新しいイメージは何か？
- サイズはどのくらいか？

---

### Step 7: ユニークなダイジェスト数の確認

```bash
# 異なるダイジェストの数を確認
UNIQUE_DIGESTS=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'imageDetails[*].imageDigest' \
  --output text | tr '\t' '\n' | sort -u | wc -l)

echo "=== ダイジェストの確認 ==="
echo "ユニークなダイジェスト数: $UNIQUE_DIGESTS"
echo "総イメージ数:             $CURRENT_COUNT"
echo ""

if [ $UNIQUE_DIGESTS -eq $CURRENT_COUNT ]; then
  echo "✓ 全てのイメージが異なるダイジェストを持っています"
else
  echo "! 同じダイジェストを持つイメージがあります（タグのみ異なる）"
  echo "  同じダイジェスト: $(($CURRENT_COUNT - $UNIQUE_DIGESTS))個のタグが重複"
fi
```

---

### Step 8: ライフサイクル超過の状態確認

```bash
LIFECYCLE_LIMIT=10
EXCESS=$((CURRENT_COUNT - LIFECYCLE_LIMIT))

echo "=== ライフサイクル状態 ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "現在のイメージ数:   $CURRENT_COUNT"
echo "ライフサイクル上限: $LIFECYCLE_LIMIT"
echo "超過数:             $EXCESS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $EXCESS -gt 0 ]; then
  echo ""
  echo "⚠️  ライフサイクル上限を $EXCESS 個超えています"
  echo ""
  echo "自動削除について:"
  echo "  - ECRのライフサイクルポリシーは約24時間ごとに評価されます"
  echo "  - 最も古い $EXCESS 個のイメージが削除される予定です"
  echo "  - 削除を確認するには、24時間後に再度確認してください"
  echo ""
fi
```

---

### Step 9: 削除予定のイメージを表示

```bash
if [ $EXCESS -gt 0 ]; then
  echo "=== 削除予定のイメージ（最も古い${EXCESS}個） ==="
  aws ecr describe-images \
    --repository-name $ECR_REPOSITORY \
    --region $AWS_REGION \
    --query "sort_by(imageDetails,& imagePushedAt)[0:$EXCESS].[imageTags[0], imagePushedAt, imageDigest]" \
    --output table
fi
```

---

### Step 10: (オプション) 手動削除でライフサイクルをシミュレーション

自動削除を待たずに、今すぐ動作を確認したい場合：

```bash
if [ $EXCESS -gt 0 ]; then
  echo ""
  read -p "古いイメージを手動で削除しますか？ (yes/no): " -r
  echo ""
  
  if [[ $REPLY =~ ^[Yy]es$ ]]; then
    echo "=== 手動削除実行 ==="
    echo "最も古い $EXCESS 個のイメージを削除します..."
    
    # 削除対象のダイジェストを取得
    OLD_DIGESTS=$(aws ecr describe-images \
      --repository-name $ECR_REPOSITORY \
      --region $AWS_REGION \
      --query "sort_by(imageDetails,& imagePushedAt)[0:$EXCESS].imageDigest" \
      --output json)
    
    # 1つずつ削除
    COUNT=0
    for digest in $(echo $OLD_DIGESTS | jq -r '.[]'); do
      COUNT=$((COUNT + 1))
      echo "  [$COUNT/$EXCESS] 削除中: $digest"
      aws ecr batch-delete-image \
        --repository-name $ECR_REPOSITORY \
        --region $AWS_REGION \
        --image-ids imageDigest=$digest
    done
    
    echo "✓ 削除完了"
    
    # 削除後の確認
    sleep 2
    
    FINAL_COUNT=$(aws ecr describe-images \
      --repository-name $ECR_REPOSITORY \
      --region $AWS_REGION \
      --query 'length(imageDetails)' \
      --output text)
    
    echo ""
    echo "=== 削除後の状態 ==="
    echo "削除前: $CURRENT_COUNT 個"
    echo "削除後: $FINAL_COUNT 個"
    echo "削除数: $(($CURRENT_COUNT - $FINAL_COUNT)) 個"
    echo ""
    
    if [ $FINAL_COUNT -le $LIFECYCLE_LIMIT ]; then
      echo "✅ ライフサイクル上限内に収まりました"
    else
      echo "⚠️  まだ上限を超えています"
    fi
  else
    echo "削除をスキップしました"
    echo "24時間後に自動削除を待ちます"
  fi
fi
```

---

### Step 11: 残ったイメージの確認

```bash
# 最終的に残ったイメージを表示
FINAL_COUNT=$(aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'length(imageDetails)' \
  --output text)

echo ""
echo "=== 最終結果サマリー ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "リポジトリ:         $ECR_REPOSITORY"
echo "初期イメージ数:     $INITIAL_COUNT"
echo "プッシュ数:         15"
echo "プッシュ直後:       $CURRENT_COUNT"
echo "最終イメージ数:     $FINAL_COUNT"
echo "ライフサイクル上限: $LIFECYCLE_LIMIT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FINAL_COUNT -le $LIFECYCLE_LIMIT ]; then
  echo "✅ ライフサイクルポリシーが正しく機能しています"
else
  echo "⏳ ライフサイクルポリシーの自動適用を待っています"
fi

echo ""
echo "=== 残ったイメージ（新しい順） ==="
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --region $AWS_REGION \
  --query 'reverse(sort_by(imageDetails,& imagePushedAt))[*].[imageTags[0], imagePushedAt]' \
  --output table
```

---

### Step 12: 24時間後の確認コマンド

```bash
# 24時間後に実行するコマンド
echo ""
echo "=== 24時間後の確認コマンド ==="
echo ""
echo "# イメージ数を確認"
echo "aws ecr describe-images \\"
echo "  --repository-name $ECR_REPOSITORY \\"
echo "  --query 'length(imageDetails)' \\"
echo "  --output text"
echo ""
echo "# イメージ一覧を確認"
echo "aws ecr describe-images \\"
echo "  --repository-name $ECR_REPOSITORY \\"
echo "  --query 'sort_by(imageDetails,& imagePushedAt)[*].[imageTags[0], imagePushedAt]' \\"
echo "  --output table"
```

---

## 結果の解釈

### 期待される結果

#### プッシュ直後（自動削除前）

```
初期: 2個（既存のイメージ）
+ 新規: 15個（unique-test-001 〜 015）
= 合計: 17個
```

#### 24時間後（自動削除後）

```
ライフサイクル上限: 10個
残るイメージ: 10個（最新のもの）
削除されるイメージ: 7個（最も古いもの）
```

#### 削除されるイメージの例

```
削除される（古い順）:
1. manual-test-001（または最も古いイメージ）
2. その署名イメージ（sha256-....sig）
3. unique-test-001
4. unique-test-002
...
7. unique-test-005

残る:
1. unique-test-006
2. unique-test-007
...
10. unique-test-015
```

---

### 署名イメージについて

**重要**: 署名イメージも1つのイメージとしてカウントされます。

```
元のイメージ: unique-test-001
  ↓ 署名すると
署名イメージ: sha256-xxxxx.sig

両方で2個のイメージとしてカウント
```

**ライフサイクルポリシーの影響**:
- 元のイメージが削除 → 署名も無意味に
- 署名のみ削除 → 検証できなくなる

**対策**:
- ライフサイクル上限を偶数にする（推奨: 10, 20, 30...）
- または、署名が必要なイメージのみデプロイする運用

---

## トラブルシューティング

### 問題1: 全て同じダイジェストになる

**症状**:
```
イメージ数が増えない（タグだけ増える）
```

**原因**: 
同じベースイメージ（alpine:latest）をそのままプッシュ

**解決方法**:
Dockerfileで各イメージに異なる内容を追加（Step 4の方法）

---

### 問題2: イメージが削除されない

**症状**:
24時間経ってもイメージ数が減らない

**原因**:
- ライフサイクルポリシーが正しく設定されていない
- ECRの評価タイミングがまだ来ていない（最大48時間かかる場合も）

**確認方法**:
```bash
# ライフサイクルポリシーが設定されているか確認
aws ecr get-lifecycle-policy --repository-name $ECR_REPOSITORY
```

---

### 問題3: 手動削除でエラー

**症状**:
```
Error: ImageReferencedByManifestList
```

**原因**:
マルチアーキテクチャイメージ（マニフェストリスト）

**解決方法**:
```bash
# イメージの全参照を削除
aws ecr batch-delete-image \
  --repository-name $ECR_REPOSITORY \
  --image-ids imageDigest=$DIGEST imageTag=$TAG
```

---

## 定期的な確認

### イメージ数の監視コマンド

```bash
# 現在のイメージ数
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --query 'length(imageDetails)' \
  --output text

# 24時間ごとに確認
# 2025-11-11: 17個
# 2025-11-12: 10個（自動削除完了）
```

### 削除履歴の確認

残念ながらECRには削除ログがないため、以下で推測：

```bash
# 最も古いイメージのタイムスタンプを確認
aws ecr describe-images \
  --repository-name $ECR_REPOSITORY \
  --query 'sort_by(imageDetails,& imagePushedAt)[0].imagePushedAt' \
  --output text

# これより古いイメージは削除されたと推測できる
```

---

## まとめ

### チェックリスト

テスト実行時:
- [ ] 初期イメージ数を記録
- [ ] 15個の**異なる**イメージをプッシュ
- [ ] プッシュ後のイメージ数を確認（初期 + 15になるか）
- [ ] ライフサイクル上限を超えていることを確認

24時間後:
- [ ] イメージ数を再確認
- [ ] ライフサイクル上限内（10個以下）になっているか
- [ ] 最も古いイメージが削除されているか
- [ ] 最新のイメージが残っているか

---

## 参考リンク

- [ECR Lifecycle Policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)
- [ECR API Reference](https://docs.aws.amazon.com/AmazonECR/latest/APIReference/Welcome.html)

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

