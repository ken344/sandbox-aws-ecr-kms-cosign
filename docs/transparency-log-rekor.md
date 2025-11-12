# Transparency Log (Rekor) 詳細ガイド

このドキュメントでは、Sigstore Transparency Log（Rekor）について詳しく説明し、プライベートECR環境で使用しない理由と、それでも安全性が保たれる根拠を示します。

## 📋 目次

- [概要](#概要)
- [Transparency Logとは](#transparency-logとは)
- [Rekorの仕組み](#rekorの仕組み)
- [なぜ必要なのか](#なぜ必要なのか)
- [プライベート環境での扱い](#プライベート環境での扱い)
- [このプロジェクトでRekorを使わない理由](#このプロジェクトでrekorを使わない理由)
- [Rekorなしでも安全な理由](#rekorなしでも安全な理由)
- [代替の監査方法](#代替の監査方法)
- [利用判断基準](#利用判断基準)
- [参考リンク](#参考リンク)

---

## 概要

### Transparency Log (Rekor) とは？

```
Rekor = Record Korpus（記録の集合体）

署名の「公開台帳」として機能する
改ざん防止のタイムスタンプ付き記録システム
```

**一言で言うと**:
```
コンテナイメージの署名記録を
公開サーバーに保存し、
誰でも検証できるようにする仕組み
```

---

### プロジェクト背景

| 項目 | 内容 |
|------|------|
| **開発元** | Sigstore Project（Linux Foundation） |
| **目的** | ソフトウェアサプライチェーンのセキュリティ向上 |
| **公開サーバー** | https://rekor.sigstore.dev |
| **無料** | ✅ パブリックRekorは無料 |
| **オープンソース** | ✅ [github.com/sigstore/rekor](https://github.com/sigstore/rekor) |

---

## Transparency Logとは

### 基本概念

**Transparency Log（透明性ログ）**は、暗号学的に改ざん防止された公開ログです。

```
特徴:
1. 追記専用（Append-only）
2. 公開アクセス可能
3. Merkle Tree構造で改ざん防止
4. タイムスタンプ付き
5. 独立した監査が可能
```

---

### Certificate Transparency との類似性

Google Chrome等で使われている**Certificate Transparency**と同じ原理：

```
Certificate Transparency:
├─ SSL証明書の発行を記録
├─ 不正な証明書を検出
└─ 誰でも監査可能

Rekor (Software Transparency):
├─ ソフトウェア署名を記録
├─ 不正な署名を検出
└─ 誰でも監査可能
```

---

## Rekorの仕組み

### 署名からRekor記録までの流れ

```
1. イメージをビルド
   ↓
2. Cosignで署名
   ↓
3. 署名データをコンテナレジストリに保存
   ↓
4. 署名情報をRekorに送信  ← ここ！
   ↓
5. Rekorがタイムスタンプ付きで記録
   ↓
6. Rekorから署名付きタイムスタンプを受け取る
```

---

### Rekorに記録される情報

```json
{
  "kind": "hashedrekord",
  "apiVersion": "0.0.1",
  "spec": {
    "signature": {
      "content": "MEUCIQC...",  // 署名データ（Base64）
      "publicKey": {
        "content": "LS0tLS1..."  // 公開鍵（Base64）
      }
    },
    "data": {
      "hash": {
        "algorithm": "sha256",
        "value": "abc123..."  // イメージダイジェスト
      }
    }
  },
  "integratedTime": 1699564800,  // Unix timestamp
  "logIndex": 123456789,         // ログエントリ番号
  "logID": "c0d23d6...",         // ログID
  "verification": {
    "signedEntryTimestamp": "MEYCIQDxxx..."  // Rekorの署名
  }
}
```

**含まれる情報**:
- ✅ 署名データ
- ✅ 公開鍵
- ✅ イメージダイジェスト
- ✅ タイムスタンプ（いつ署名されたか）
- ✅ Rekor自身の署名（改ざん防止）

**含まれない情報**:
- ❌ プライベートキー（絶対に送信されない）
- ❌ イメージの内容
- ⚠️ リポジトリ名やタグ（場合による）

---

### Merkle Tree による改ざん防止

```
Rekorは Merkle Tree 構造を使用:

        Root Hash
       /         \
    Hash1       Hash2
   /    \      /    \
 Entry Entry Entry Entry
  1     2     3     4

特徴:
- 一つのエントリを改ざんすると Root Hash が変わる
- 過去のエントリも検証可能
- 誰でも整合性を確認できる
```

---

## なぜ必要なのか

### 問題: 秘密鍵の漏洩

```
攻撃者が秘密鍵を盗む
  ↓
悪意あるイメージに署名
  ↓
正規の署名と区別できない
  ↓
セキュリティ侵害
```

**従来の署名だけでは**:
- いつ署名されたか不明
- 鍵漏洩前か後か判断できない
- 過去の署名を無効化できない

---

### 解決: Transparency Log

```
全ての署名がRekorに記録される
  ↓
タイムスタンプ付きで公開
  ↓
秘密鍵漏洩後の署名を特定可能
  ↓
影響範囲を明確化
```

**具体例**:

```
Rekorの記録:
2025-11-01 12:00 - myapp:v1.0 に署名 ✅
2025-11-05 08:00 - myapp:v1.1 に署名 ✅
2025-11-10 14:00 - myapp:v1.2 に署名 ✅
2025-11-11 02:00 - myapp:v1.3 に署名 ⚠️

秘密鍵漏洩発覚: 2025-11-11 01:00
  ↓
判断:
- v1.0, v1.1, v1.2 → 信頼できる（漏洩前）
- v1.3 → 信頼できない（漏洩後）
```

---

### 公開監査の重要性

```
誰でもRekorを監視できる
  ↓
不正な署名を検出
  ↓
コミュニティが警告
  ↓
セキュリティ向上
```

**例**: 
- セキュリティ研究者が異常な署名パターンを検出
- 自動化ツールで継続的に監視
- インシデント時の影響範囲調査

---

## プライベート環境での扱い

### コンテナレジストリの種類

#### パブリックレジストリ

```
例:
- Docker Hub（公開リポジトリ）
- public.ecr.aws
- GitHub Container Registry（公開）

特徴:
- 🌐 誰でもイメージをPull可能
- ✅ Rekor使用が推奨
- ✅ 透明性が重要
```

#### プライベートレジストリ

```
例:
- AWS ECR（プライベート）← このプロジェクト
- Google Artifact Registry（プライベート）
- Azure Container Registry（プライベート）
- 自社運用のDocker Registry

特徴:
- 🔒 認証が必要
- ⚠️ パブリックRekorは非推奨
- 🏢 企業内でのみ使用
```

---

### このプロジェクトの環境

```yaml
コンテナレジストリ: プライベートECR
URL: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
アクセス: IAMで制御（AWSアカウント内のみ）
用途: 検証・学習
```

**判断**: パブリックRekorは**使用しない**

---

## このプロジェクトでRekorを使わない理由

### 理由1: プライバシーとセキュリティ

```
プライベートECR
  ↓
社内・プロジェクト内専用
  ↓
外部に情報を送信すべきでない
```

**リスク**:
```
パブリックRekorに記録すると:
- イメージダイジェストが公開される
- リポジトリ名が漏洩する可能性
- 攻撃者の標的になりうる
- コンプライアンス違反の可能性
```

**例**:
```json
// Rekorに記録される情報（公開される）
{
  "data": {
    "hash": {
      "value": "abc123def456..."  // ← これが公開される
    }
  },
  "integratedTime": 1699564800  // ← いつビルドされたか分かる
}

攻撃者の視点:
「この企業は11月11日にイメージをビルドした」
「このダイジェストを探してみよう」
```

---

### 理由2: 必要性の欠如

```
Rekorの主な用途:
1. 鍵漏洩時の影響範囲特定
2. 公開監査
3. タイムスタンプの証明

このプロジェクトの状況:
- 検証・学習目的
- 短期間の使用
- AWS KMSで鍵を厳重に管理
  └─ KMSキーは漏洩しない
- 公開する必要なし
  ↓
Rekorのメリットが少ない
```

---

### 理由3: 外部依存の回避

```
パブリックRekor依存
  ↓
外部サービス（rekor.sigstore.dev）に依存
  ↓
リスク:
- ネットワーク障害
- サービス停止
- レイテンシ増加
- データ主権の問題
```

**プライベート環境の原則**:
```
完全に自社内で完結させる
  ↓
外部サービス依存を最小化
  ↓
可用性とパフォーマンスの向上
```

---

### 理由4: コンプライアンス

```
企業によっては:
- データの国外持ち出し禁止
- 外部サービスへの情報送信禁止
- プライベート情報の公開禁止

Rekor使用 → コンプライアンス違反の可能性
```

---

## Rekorなしでも安全な理由

### セキュリティモデルの違い

#### Rekorあり（パブリック環境）

```
信頼の連鎖:
1. 署名の存在
   └─ Cosignで検証
2. タイムスタンプ
   └─ Rekorで証明
3. 鍵の正当性
   └─ Fulcio証明書で確認
4. 公開監査
   └─ 誰でも検証可能

セキュリティの根拠:
「公開監査」と「透明性」
```

#### Rekorなし（プライベート環境）← このプロジェクト

```
信頼の連鎖:
1. 署名の存在
   └─ Cosignで検証
2. 鍵の管理
   └─ AWS KMS + IAM
3. アクセス制御
   └─ GitHub Actions OIDC
4. 監査ログ
   └─ AWS CloudTrail

セキュリティの根拠:
「厳格なアクセス制御」と「内部監査」
```

---

### このプロジェクトのセキュリティ対策

```
レイヤー1: KMSキー管理
├─ AWS KMSで鍵を保護
├─ キーは外部に出ない
├─ IAMで厳格なアクセス制御
└─ キーローテーション可能

レイヤー2: GitHub Actions認証
├─ OIDC（OpenID Connect）
├─ 一時的な認証情報のみ
├─ 特定のブランチ・リポジトリのみ
└─ 長期的な認証情報なし

レイヤー3: ECRアクセス制御
├─ IAMポリシーで厳格に制限
├─ リポジトリポリシー
├─ VPC Endpoint（オプション）
└─ プライベートネットワーク

レイヤー4: 監査とロギング
├─ AWS CloudTrail（全API呼び出し記録）
├─ GitHub Actions ログ
├─ ECRイメージスキャン
└─ タグの不変性（Immutable tags）
```

**結論**: Rekorがなくても多層防御で保護されている

---

### AWS KMSの優位性

```
パブリックキー署名 vs AWS KMS:

パブリックキー（秘密鍵ファイル）:
❌ ファイルが盗まれるリスク
❌ GitHub Secretsに保存
❌ 漏洩したら全て無効化
  ↓
Rekorが重要！

AWS KMS:
✅ キーは外部に出ない
✅ API経由でのみ署名
✅ IAMで厳格に制御
✅ CloudTrailで全て記録
  ↓
Rekorの必要性が低い
```

---

### タイムスタンプの代替

```
Rekorなしでもタイムスタンプは取得可能:

1. CloudTrail
   └─ KMS署名APIの呼び出し時刻

2. GitHub Actions
   └─ Workflowの実行時刻

3. ECRイメージ
   └─ imagePushedAt（プッシュ時刻）

4. Gitコミット
   └─ コミット時刻とSHA
```

**例**:

```bash
# ECRから取得
aws ecr describe-images \
  --repository-name sample-app-1 \
  --image-ids imageTag=v1.0 \
  --query 'imageDetails[0].imagePushedAt'

# 出力: "2025-11-11T12:34:56Z"

# CloudTrailから取得
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=Sign \
  --max-items 10

# GitHub Actionsから
# Workflow実行時刻、run_number、git SHA
```

---

## 代替の監査方法

### AWS CloudTrail

```yaml
記録内容:
  - KMS署名APIの呼び出し
  - ECRへのプッシュ
  - IAMロールの引き受け
  - 全てのAWS API呼び出し

特徴:
  ✅ 詳細なログ
  ✅ タイムスタンプ
  ✅ 改ざん防止（S3に保存）
  ✅ 長期保存可能
```

**使用例**:

```bash
# 過去24時間のKMS署名を確認
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=Sign \
  --start-time $(date -u -d '24 hours ago' +%s) \
  --query 'Events[*].[EventTime,Username,CloudTrailEvent]' \
  --output table
```

---

### GitHub Actions ログ

```yaml
記録内容:
  - Workflowの実行時刻
  - 誰がトリガーしたか
  - どのブランチから
  - 実行結果（成功/失敗）
  - 詳細なログ

特徴:
  ✅ 完全なトレーサビリティ
  ✅ UIで閲覧可能
  ✅ アーティファクトとして保存
  ✅ 再現性の担保
```

---

### ECRイメージメタデータ

```yaml
記録内容:
  - imagePushedAt（プッシュ時刻）
  - imageDigest（一意識別子）
  - imageTags
  - imageScanFindings（脆弱性情報）

特徴:
  ✅ イメージごとに記録
  ✅ API/CLIで取得可能
  ✅ ライフサイクル管理
```

**使用例**:

```bash
# イメージの詳細情報
aws ecr describe-images \
  --repository-name sample-app-1 \
  --query 'sort_by(imageDetails,&imagePushedAt)[*].[imageTags[0],imagePushedAt,imageDigest]' \
  --output table
```

---

### 組み合わせた監査

```
監査トレイル:

1. Gitコミット
   ├─ コミットSHA: abc123
   ├─ 作成者: developer@example.com
   └─ 時刻: 2025-11-11 10:00:00

2. GitHub Actions
   ├─ Workflow run: #42
   ├─ トリガー: push to main
   ├─ 開始: 2025-11-11 10:05:00
   └─ 終了: 2025-11-11 10:08:00

3. AWS KMS（CloudTrail）
   ├─ イベント: kms:Sign
   ├─ 時刻: 2025-11-11 10:07:23
   ├─ ロール: github-actions-role
   └─ キー: alias/sandbox-ecr-kms/cosign

4. ECR
   ├─ イメージ: sample-app-1@sha256:def456
   ├─ プッシュ時刻: 2025-11-11 10:07:45
   └─ 署名イメージ: sha256-def456.sig

完全なトレーサビリティ ✅
```

---

## 利用判断基準

### Rekorを使うべき環境

```
✅ パブリックコンテナレジストリ
   └─ Docker Hub、public.ecr.aws等

✅ オープンソースプロジェクト
   └─ 透明性が重要

✅ 広く配布するソフトウェア
   └─ 多数のユーザーが使用

✅ コミュニティの監査が必要
   └─ 信頼性の証明

✅ 規制要件
   └─ 公開監査が必須の業界
```

**例**:
- Kubernetesの公式イメージ
- 広く使われるOSSライブラリ
- パブリックAPI/SDK

---

### Rekorを使わない環境

```
✅ プライベートコンテナレジストリ
   └─ プライベートECR（このプロジェクト）

✅ 社内専用システム
   └─ 外部に公開しない

✅ 検証・開発環境
   └─ 短期間の使用

✅ コンプライアンス制約
   └─ データ持ち出し禁止

✅ AWS KMS等のHSM使用
   └─ 鍵漏洩リスクが低い
```

**例**:
- 社内業務システム
- マイクロサービス（内部専用）
- 検証・テスト環境

---

### プライベートRekorの検討

```
大企業・エンタープライズで検討すべきケース:

✅ 大規模な社内利用
   └─ 数百～数千のイメージ

✅ 複数チーム・部門
   └─ 横断的な監査が必要

✅ 厳格なコンプライアンス
   └─ 内部監査要件

✅ 長期運用
   └─ 数年～数十年

❌ このプロジェクト
   └─ 検証目的、小規模、短期
```

**コスト**:
- サーバー運用コスト
- 人的リソース
- メンテナンス
  ↓
費用対効果を検討

---

## 判断フローチャート

```
Rekorを使うべきか？

├─ コンテナレジストリはパブリック？
│  ├─ はい → ✅ Rekorを使用
│  └─ いいえ → 次へ
│
├─ オープンソースプロジェクト？
│  ├─ はい → ✅ Rekorを使用
│  └─ いいえ → 次へ
│
├─ 外部ユーザーに配布？
│  ├─ はい → ✅ Rekorを使用
│  └─ いいえ → 次へ
│
├─ 大規模・長期運用？
│  ├─ はい → プライベートRekorを検討
│  └─ いいえ → 次へ
│
├─ AWS KMS等のHSM使用？
│  ├─ はい → ❌ Rekorは不要（このプロジェクト）
│  └─ いいえ → プライベートRekorを検討
│
└─ 結論: Rekorなしで十分
```

---

## 実装例

### Rekorを使わない設定（このプロジェクト）

```yaml
# .github/workflows/single-image-test.yml

- name: Install Cosign
  uses: sigstore/cosign-installer@v3
  with:
    cosign-release: 'v3.0.2'

- name: Sign image
  run: |
    cosign sign \
      --key awskms:///${{ secrets.KMS_KEY_ARN }} \
      --yes \
      --tlog-upload=false \  # ← Rekorをスキップ
      $IMAGE_URI_WITH_DIGEST

- name: Verify signature
  run: |
    cosign verify \
      --key awskms:///${{ secrets.KMS_KEY_ARN }} \
      --insecure-ignore-tlog \  # ← Rekor検証をスキップ
      $IMAGE_URI_WITH_DIGEST
```

**理由の明記**:

```yaml
# プライベートECR環境のため、パブリックTransparency Logは使用しない
# セキュリティは以下で担保:
# - AWS KMS による鍵管理
# - IAM による厳格なアクセス制御
# - CloudTrail による監査ログ
# - GitHub Actions によるトレーサビリティ
```

---

### Rekorを使う設定（パブリック環境）

```yaml
# パブリックレジストリの場合

- name: Sign image
  run: |
    cosign sign \
      --key key.pem \
      --yes \
      public.ecr.aws/myorg/myapp:v1.0
    # --tlog-upload=false は付けない（デフォルトでRekor使用）

- name: Verify signature
  run: |
    cosign verify \
      --key key.pub \
      public.ecr.aws/myorg/myapp:v1.0
    # --insecure-ignore-tlog は付けない（Rekorで検証）
```

---

## まとめ

### Transparency Log (Rekor) の本質

```
目的:
  ソフトウェアサプライチェーンの透明性向上
  不正な署名の検出
  公開監査の実現

実現方法:
  署名記録を改ざん防止可能な公開ログに保存
  誰でもアクセス・検証可能
  タイムスタンプ付き
```

---

### このプロジェクトでの結論

```
プライベートECR環境において、
パブリックTransparency Log（Rekor）は使用しない

理由:
1. ✅ プライバシーとセキュリティ（情報漏洩リスク回避）
2. ✅ 必要性の欠如（AWS KMSで鍵を厳重管理）
3. ✅ 外部依存の回避（完全に自社内で完結）
4. ✅ コンプライアンス（データ持ち出し制約）

安全性の担保:
1. ✅ AWS KMS（鍵は外部に出ない）
2. ✅ IAM + OIDC（厳格なアクセス制御）
3. ✅ CloudTrail（詳細な監査ログ）
4. ✅ GitHub Actions（完全なトレーサビリティ）

結論:
  Rekorなしでも十分に安全
  プライベート環境では使わないことが正しい判断
```

---

### 環境別の推奨

| 環境 | Rekor使用 | 理由 |
|------|----------|------|
| **パブリックレジストリ** | ✅ 使う | 透明性が重要 |
| **オープンソース** | ✅ 使う | コミュニティ監査 |
| **プライベートECR**（このプロジェクト） | ❌ 使わない | プライバシー優先 |
| **社内専用システム** | ❌ 使わない | 外部依存回避 |
| **エンタープライズ大規模** | 🤔 プライベートRekorを検討 | 内部監査要件 |

---

## 参考リンク

### 公式ドキュメント

- [Sigstore Project](https://www.sigstore.dev/)
- [Sigstore Documentation](https://docs.sigstore.dev/)
- [Rekor GitHub Repository](https://github.com/sigstore/rekor)
- [Cosign GitHub Repository](https://github.com/sigstore/cosign)
- [Rekor Public Instance](https://rekor.sigstore.dev/)

### 関連技術

- [Certificate Transparency](https://certificate.transparency.dev/)
- [Merkle Tree](https://en.wikipedia.org/wiki/Merkle_tree)
- [AWS CloudTrail](https://aws.amazon.com/cloudtrail/)
- [AWS KMS](https://aws.amazon.com/kms/)

### このプロジェクトの関連ドキュメント

- [Cosign バージョン移行ガイド](./cosign-version-migration.md)
- [GitHub Secrets 設定ガイド](./github-secrets-setup.md)
- [ローカル検証ガイド](./local-verification-guide.md)

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-11 | 初版作成（Transparency Log詳細ガイド） |

