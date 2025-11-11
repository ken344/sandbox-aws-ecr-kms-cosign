# AWS CLI とIAM設定ガイド

このドキュメントでは、本プロジェクトで必要なAWS CLIとIAMユーザーの設定手順を説明します。

## 目次

- [前提条件](#前提条件)
- [Step 1: AWS CLIのインストール確認](#step-1-aws-cliのインストール確認)
- [Step 2: 検証用IAMユーザーの作成](#step-2-検証用iamユーザーの作成)
- [Step 3: AWS CLIの設定](#step-3-aws-cliの設定)
- [Step 4: 認証確認](#step-4-認証確認)
- [Step 5: 設定ファイルの確認](#step-5-設定ファイルの確認)
- [セキュリティのベストプラクティス](#セキュリティのベストプラクティス)
- [トラブルシューティング](#トラブルシューティング)

---

## 前提条件

- AWSアカウントが作成済み
- AWSマネジメントコンソールへのアクセス権限
- ターミナル/コマンドラインへのアクセス

---

## Step 1: AWS CLIのインストール確認

### 1.1 インストール確認

ターミナルで以下のコマンドを実行してAWS CLIがインストールされているか確認します：

```bash
aws --version
```

期待される出力例：
```
aws-cli/2.x.x Python/3.x.x Darwin/24.6.0 source/arm64
```

### 1.2 AWS CLIのインストール（必要な場合）

#### macOSの場合

**方法A: Homebrew（推奨）**
```bash
brew install awscli
```

**方法B: 公式インストーラー**
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

#### Linuxの場合

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

#### インストール確認

```bash
aws --version
which aws
```

---

## Step 2: 検証用IAMユーザーの作成

### 2.1 IAMコンソールにアクセス

1. [AWSマネジメントコンソール](https://console.aws.amazon.com/)にログイン
2. 検索バーで「IAM」を検索して開く
3. 左メニューから「ユーザー」を選択
4. 「ユーザーを追加」ボタンをクリック

### 2.2 ユーザー詳細の設定

以下の情報を入力します：

| 項目 | 設定値 |
|------|--------|
| ユーザー名 | `terraform-admin` |
| AWS認証情報タイプ | ✅ アクセスキー - プログラムによるアクセス |
| AWSマネジメントコンソールへのアクセス | ❌ 不要（チェックなし） |

### 2.3 権限の設定

#### Option A: 検証用に広範な権限を付与（推奨）

**注意**: これは検証用です。本番環境では使用しないでください。

1. 「既存のポリシーを直接アタッチ」を選択
2. 以下のポリシーを検索して選択：
   - `AdministratorAccess`

#### Option B: 必要最小限の権限のみ付与（本番推奨）

1. 「ポリシーを直接アタッチ」を選択
2. 「ポリシーの作成」をクリック
3. JSONタブを選択して以下を貼り付け：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformECRKMSAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:*",
        "kms:*",
        "iam:*",
        "s3:*",
        "sts:GetCallerIdentity",
        "sts:GetAccessKeyInfo"
      ],
      "Resource": "*"
    }
  ]
}
```

4. ポリシー名: `TerraformECRKMSPolicy`
5. 「ポリシーの作成」をクリック
6. 作成したポリシーをユーザーにアタッチ

### 2.4 タグの追加（オプション）

タグを追加して管理を容易にします：

| キー | 値 |
|------|-----|
| `Purpose` | `ECR-KMS-Testing` |
| `Project` | `sandbox-aws-ecr-kms-cosign` |
| `ManagedBy` | `Manual` |

### 2.5 確認と作成

1. 設定内容を確認
2. 「ユーザーの作成」ボタンをクリック

### 2.6 アクセスキーの保存

**⚠️ 重要**: この画面は一度しか表示されません！

表示される以下の情報を**必ず**保存してください：

- **アクセスキーID**: `AKIA...` （20文字）
- **シークレットアクセスキー**: `wJalrXUt...` （40文字）

**推奨される保存方法:**
1. 「.csvのダウンロード」ボタンをクリック
2. ファイルを安全な場所に保存
3. パスワードマネージャーに保存（1Password、LastPass等）

---

## Step 3: AWS CLIの設定

### 3.1 設定コマンドの実行

ターミナルで以下のコマンドを実行します：

```bash
aws configure
```

### 3.2 情報の入力

対話形式で以下を入力します：

```
AWS Access Key ID [None]: <Step 2.6で取得したアクセスキーID>
AWS Secret Access Key [None]: <Step 2.6で取得したシークレットアクセスキー>
Default region name [None]: ap-northeast-1
Default output format [None]: json
```

#### リージョンの選択

| リージョンコード | リージョン名 | 推奨用途 |
|-----------------|-------------|----------|
| `ap-northeast-1` | 東京 | 日本国内プロジェクト（推奨） |
| `ap-northeast-3` | 大阪 | 冗長性が必要な場合 |
| `us-east-1` | バージニア北部 | グローバルプロジェクト |
| `us-west-2` | オレゴン | グローバルプロジェクト |

#### 出力形式の選択

| 形式 | 説明 | 推奨用途 |
|------|------|----------|
| `json` | JSON形式（デフォルト） | プログラム処理、一般用途 |
| `yaml` | YAML形式 | 可読性重視 |
| `text` | タブ区切りテキスト | シェルスクリプト |
| `table` | 表形式 | 人間が読む用途 |

---

## Step 4: 認証確認

### 4.1 呼び出し元の確認

現在の認証情報が正しく設定されているか確認します：

```bash
aws sts get-caller-identity
```

**期待される出力:**
```json
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/terraform-admin"
}
```

**確認ポイント:**
- `Account`: あなたのAWSアカウントID（12桁の数字）
- `Arn`: IAMユーザーのARN（作成したユーザー名が含まれる）

### 4.2 リージョンの確認

```bash
aws configure get region
```

**期待される出力:**
```
ap-northeast-1
```

### 4.3 権限の確認

S3バケットの一覧を取得して、権限が正しく設定されているか確認します：

```bash
aws s3 ls
```

エラーが出なければ成功です（バケットが存在しない場合は何も表示されません）。

### 4.4 アカウントIDの取得（メモ推奨）

Terraformで使用するため、アカウントIDを取得してメモします：

```bash
aws sts get-caller-identity --query Account --output text
```

**出力例:**
```
123456789012
```

この値は後で使用するのでメモしておいてください。

---

## Step 5: 設定ファイルの確認

AWS CLIの設定は、ホームディレクトリの `.aws/` フォルダに保存されます。

### 5.1 認証情報ファイル

```bash
cat ~/.aws/credentials
```

**内容:**
```ini
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = wJalrXUt...
```

### 5.2 設定ファイル

```bash
cat ~/.aws/config
```

**内容:**
```ini
[default]
region = ap-northeast-1
output = json
```

### 5.3 ファイルパーミッションの確認

セキュリティのため、認証情報ファイルのパーミッションを確認します：

```bash
ls -la ~/.aws/
```

**期待される出力:**
```
-rw-------  1 username  staff   credentials
-rw-------  1 username  staff   config
```

パーミッションが `600` (rw-------) であることを確認してください。

もし異なる場合は、以下で修正します：

```bash
chmod 600 ~/.aws/credentials
chmod 600 ~/.aws/config
```

---

## セキュリティのベストプラクティス

### 1. アクセスキーの保護

- ✅ 認証情報ファイルのパーミッションを `600` に設定
- ✅ Gitリポジトリにコミットしない（`.gitignore` に追加済み）
- ✅ 公開リポジトリに誤ってプッシュしない
- ✅ チームメンバーと共有しない

### 2. 定期的なローテーション

アクセスキーは定期的にローテーション（更新）することを推奨します：

```bash
# 現在のアクセスキーの確認
aws iam list-access-keys --user-name terraform-admin

# 新しいアクセスキーの作成
aws iam create-access-key --user-name terraform-admin

# 古いアクセスキーの削除（新しいキーで設定更新後）
aws iam delete-access-key --access-key-id <OLD_KEY_ID> --user-name terraform-admin
```

### 3. 検証終了後の削除

プロジェクトの検証が終了したら、IAMユーザーとアクセスキーを削除します：

#### 方法A: AWSコンソールから削除

1. IAMコンソールを開く
2. 「ユーザー」→ `terraform-admin` を選択
3. 「セキュリティ認証情報」タブ
4. アクセスキーを削除
5. ユーザーを削除

#### 方法B: AWS CLIから削除

```bash
# アクセスキーの削除
aws iam delete-access-key \
  --access-key-id <YOUR_ACCESS_KEY_ID> \
  --user-name terraform-admin

# ポリシーのデタッチ
aws iam detach-user-policy \
  --user-name terraform-admin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# ユーザーの削除
aws iam delete-user --user-name terraform-admin
```

### 4. MFAの有効化（推奨）

長期的に使用する場合は、IAMユーザーに多要素認証（MFA）を設定することを強く推奨します。

---

## トラブルシューティング

### 問題1: `aws: command not found`

**原因**: AWS CLIがインストールされていない、またはPATHが通っていない

**解決方法**:
```bash
# インストール確認
which aws

# PATHの確認
echo $PATH

# 再インストール
brew reinstall awscli
```

### 問題2: `An error occurred (InvalidClientTokenId)`

**原因**: アクセスキーIDが間違っている

**解決方法**:
```bash
# 設定を確認
aws configure list

# 再設定
aws configure
```

### 問題3: `An error occurred (SignatureDoesNotMatch)`

**原因**: シークレットアクセスキーが間違っている

**解決方法**:
```bash
# 再設定
aws configure

# または直接編集
nano ~/.aws/credentials
```

### 問題4: `An error occurred (AccessDenied)`

**原因**: IAMユーザーに必要な権限がない

**解決方法**:
1. AWSコンソールでIAMユーザーのポリシーを確認
2. 必要な権限を追加
3. 数分待ってから再試行（権限反映に時間がかかる場合がある）

### 問題5: リージョンが正しくない

**原因**: デフォルトリージョンの設定ミス

**解決方法**:
```bash
# 現在のリージョン確認
aws configure get region

# リージョン変更
aws configure set region ap-northeast-1

# または環境変数で上書き
export AWS_DEFAULT_REGION=ap-northeast-1
```

---

## 複数プロファイルの使用（オプション）

本番用と検証用など、複数のAWS環境を使い分ける場合：

### プロファイルの作成

```bash
# プロファイルを指定して設定
aws configure --profile sandbox
```

### プロファイルの使用

```bash
# コマンドごとに指定
aws s3 ls --profile sandbox

# 環境変数で指定（セッション全体に適用）
export AWS_PROFILE=sandbox
aws s3 ls

# 確認
echo $AWS_PROFILE
```

### 設定ファイルの例

`~/.aws/credentials`:
```ini
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[sandbox]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[production]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

`~/.aws/config`:
```ini
[default]
region = ap-northeast-1
output = json

[profile sandbox]
region = ap-northeast-1
output = json

[profile production]
region = us-west-2
output = json
```

---

## 次のステップ

AWS CLIとIAMの設定が完了したら、次は以下のステップに進みます：

1. **Terraform Backendの構築** - S3バケットの作成
2. **Terraformの初期化** - プロバイダーとモジュールの設定
3. **IAMロールの作成** - GitHub Actions用のOIDC設定

詳細は各ドキュメントを参照してください。

---

## 参考リンク

- [AWS CLI 公式ドキュメント](https://docs.aws.amazon.com/cli/)
- [IAM ベストプラクティス](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS CLI 設定と認証情報ファイル](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
- [AWS リージョンとアベイラビリティーゾーン](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)

---

## 更新履歴

| 日付 | 変更内容 |
|------|---------|
| 2025-11-10 | 初版作成 |

