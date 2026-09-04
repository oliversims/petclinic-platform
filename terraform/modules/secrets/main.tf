# =============================================================================
# terraform/modules/secrets/main.tf
# Purpose: Non-RDS secrets plus IRSA role for External Secrets Operator.
#
# Flow: OpenAI key -> Secrets Manager. EKS OIDC -> eso-role -> read petclinic/*.
# RDS credentials stay in the rds module.
#
# Linked: eso.tf, rds module, eks OIDC, k8s/base/external-secrets/;
# called from environments/{dev,prod}/main.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Caller identity - account ID for Secrets Manager ARNs
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# 2) Current region - Secrets Manager ARN region segment
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# 3) Locals - naming, OIDC host for IRSA conditions, tags
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  oidc_provider_host = replace(var.oidc_provider_url, "https://", "")

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 4) OpenAI API key secret - shell for genai-service via ESO
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "openai_api_key" {
  name                    = "${var.project}/${var.environment}/openai-api-key"
  description             = "OpenAI API key for ${local.name_prefix} genai-service"
  recovery_window_in_days = 0

  tags = merge(local.tags, {
    Name = "${var.project}/${var.environment}/openai-api-key"
  })
}

# -----------------------------------------------------------------------------
# 5) OpenAI secret version - value from root tfvars / TF_VAR
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key
}

# -----------------------------------------------------------------------------
# 6) ESO assume-role policy - IRSA trust for external-secrets-sa
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "eso_assume_role" {
  count = var.install_eso ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 7) ESO IRSA role - ASCII description; trusted by external-secrets SA only
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eso" {
  count = var.install_eso ? 1 : 0

  name               = "${local.name_prefix}-eso-role"
  description        = "External Secrets Operator - reads petclinic secrets from Secrets Manager"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eso-role"
  })
}

# -----------------------------------------------------------------------------
# 8) ESO permissions - GetSecretValue/DescribeSecret on petclinic/* only
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "eso" {
  count = var.install_eso ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/*",
    ]
  }
}

# -----------------------------------------------------------------------------
# 9) ESO inline policy attachment - secrets-read on the IRSA role
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "eso" {
  count = var.install_eso ? 1 : 0

  name   = "${local.name_prefix}-eso-secrets-read"
  role   = aws_iam_role.eso[0].id
  policy = data.aws_iam_policy_document.eso[0].json
}
