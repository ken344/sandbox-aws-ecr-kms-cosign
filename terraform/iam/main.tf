# GitHub Actions用のOIDCプロバイダーとIAMロールを作成

# 1. GitHub Actions用のOIDC Provider
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # GitHub ActionsのOIDC証明書のthumbprint
  # 2023年以降はこの値を使用
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "github-actions-oidc-provider"
    }
  )
}

# 2. GitHub Actions用のIAMロール
resource "aws_iam_role" "github_actions" {
  name               = "${local.project_name}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name    = "${local.project_name}-github-actions-role"
      Purpose = "GitHub Actions workflow execution"
    }
  )
}

# 3. IAMロールの信頼ポリシー（AssumeRole Policy）
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # GitHubリポジトリを制限
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.github_org}/${local.github_repo}:*"
      ]
    }
  }
}

# 4. ECRへのアクセス権限ポリシー
data "aws_iam_policy_document" "ecr_access" {
  # ECR Repository への権限
  statement {
    sid    = "ECRRepositoryAccess"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]

    resources = ["*"]
  }

  # ECR認証トークン取得（リポジトリを指定できないため*）
  statement {
    sid    = "ECRGetAuthorizationToken"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecr_access" {
  name        = "${local.project_name}-github-actions-ecr-access"
  description = "Allow GitHub Actions to push images to ECR"
  policy      = data.aws_iam_policy_document.ecr_access.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-ecr-access-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_access.arn
}

# 5. KMS署名権限ポリシー（KMSキー作成後に具体的なARNを設定）
data "aws_iam_policy_document" "kms_signing" {
  statement {
    sid    = "KMSSigningAccess"
    effect = "Allow"

    actions = [
      "kms:Sign",
      "kms:Verify",
      "kms:GetPublicKey",
      "kms:DescribeKey"
    ]

    # 現時点では全てのKMSキーを許可（後で具体的なARNに制限可能）
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:KeyUsage"
      values   = ["SIGN_VERIFY"]
    }
  }
}

resource "aws_iam_policy" "kms_signing" {
  name        = "${local.project_name}-github-actions-kms-signing"
  description = "Allow GitHub Actions to sign with KMS"
  policy      = data.aws_iam_policy_document.kms_signing.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-kms-signing-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "kms_signing" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.kms_signing.arn
}

# 6. S3 Artifacts バケットへのアクセス権限
data "aws_iam_policy_document" "s3_artifacts" {
  # Artifacts バケットへの書き込み権限
  statement {
    sid    = "S3ArtifactsAccess"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      "${local.artifacts_bucket_arn}",
      "${local.artifacts_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "s3_artifacts" {
  count = local.artifacts_bucket_arn != "" ? 1 : 0

  name        = "${local.project_name}-github-actions-s3-artifacts"
  description = "Allow GitHub Actions to write to S3 artifacts bucket"
  policy      = data.aws_iam_policy_document.s3_artifacts.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-s3-artifacts-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "s3_artifacts" {
  count = local.artifacts_bucket_arn != "" ? 1 : 0

  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.s3_artifacts[0].arn
}

# 7. CloudWatch Logs への書き込み権限（オプション）
data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    sid    = "CloudWatchLogsAccess"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/github-actions/${local.project_name}*"
    ]
  }
}

resource "aws_iam_policy" "cloudwatch_logs" {
  name        = "${local.project_name}-github-actions-cloudwatch-logs"
  description = "Allow GitHub Actions to write logs to CloudWatch"
  policy      = data.aws_iam_policy_document.cloudwatch_logs.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-cloudwatch-logs-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

