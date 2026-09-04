# =============================================================================
# terraform/modules/github-oidc/main.tf
# Purpose: GitHub Actions OIDC role to push images to ECR without static keys.
#
# Flow: GitHub OIDC provider -> IAM role scoped to this repo -> ECR push.
#
# Linked: ecr module; GitHub Actions workflow AWS_ROLE_ARN;
# called from environments/{dev,prod}/main.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Caller identity - account ID for ECR repository ARNs
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# 2) Current region - ECR ARN region segment
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# 3) Locals - main-branch subject, role name, ECR envs, tags
# -----------------------------------------------------------------------------

locals {
  subject = "repo:${var.github_org}/${var.github_app_repo}:ref:refs/heads/main"

  role_name = "petclinic-github-actions-role"

  ecr_environments = ["dev", "prod"]

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 4) OIDC provider - GitHub Actions token issuer
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(local.tags, {
    Name = "${var.project}-github-actions-oidc"
  })
}

# -----------------------------------------------------------------------------
# 5) Assume-role policy - trust only app repo main branch via OIDC
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.subject]
    }
  }
}

# -----------------------------------------------------------------------------
# 6) GitHub Actions role - assumed only by the app repo main branch
# -----------------------------------------------------------------------------

resource "aws_iam_role" "github_actions" {
  name               = local.role_name
  description        = "GitHub Actions CI - pushes images to the petclinic ECR repositories"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(local.tags, {
    Name = local.role_name
  })
}

# -----------------------------------------------------------------------------
# 7) ECR push policy - auth token *; push scoped to petclinic-{env}/*
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]

    resources = [
      for env in local.ecr_environments :
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${var.project}-${env}/*"
    ]
  }
}

# -----------------------------------------------------------------------------
# 8) ECR push inline policy - attach push permissions to the CI role
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "ecr_push" {
  name   = "${local.role_name}-ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
