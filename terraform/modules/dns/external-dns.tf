# =============================================================================
# terraform/modules/dns/external-dns.tf
# Purpose: ExternalDNS IRSA role and Helm release for Route 53 aliases.
#
# Flow: IRSA + Helm when install_external_dns. Watches Ingresses in domain_name.
#
# Linked: main.tf zone; lb-controller Ingresses; helm-values / argocd ingress.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Assume-role policy - IRSA trust for external-dns in kube-system
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "external_dns_assume_role" {
  count = var.install_external_dns ? 1 : 0

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
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 2) IAM role - ExternalDNS IRSA role (ASCII-only description for IAM)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "external_dns" {
  count = var.install_external_dns ? 1 : 0

  name               = "${local.name_prefix}-external-dns-role"
  description        = "ExternalDNS - writes Route 53 records for ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-external-dns-role"
  })
}

# -----------------------------------------------------------------------------
# 3) IAM policy document - ChangeResourceRecordSets on this zone; List* unscoped
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "external_dns" {
  count = var.install_external_dns ? 1 : 0

  statement {
    sid       = "ChangeThisZoneOnly"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [local.zone_arn]
  }

  statement {
    sid    = "DiscoverZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]

    resources = ["*"]
  }
}

# -----------------------------------------------------------------------------
# 4) Inline role policy - attach Route 53 permissions to the ExternalDNS role
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "external_dns" {
  count = var.install_external_dns ? 1 : 0

  name   = "${local.name_prefix}-external-dns-route53"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns[0].json
}

# -----------------------------------------------------------------------------
# 5) Helm release - ingress sources only, scoped to this domain and env owner ID
# -----------------------------------------------------------------------------

resource "helm_release" "external_dns" {
  count = var.install_external_dns ? 1 : 0

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  set = [
    {
      name  = "provider.name"
      value = "aws"
    },
    {
      name  = "aws.region"
      value = data.aws_region.current.name
    },
    {
      name  = "aws.zoneType"
      value = "public"
    },
    {
      name  = "sources[0]"
      value = "ingress"
    },
    {
      name  = "domainFilters[0]"
      value = var.domain_name
    },
    {
      name  = "txtOwnerId"
      value = local.name_prefix
    },
    {
      name  = "policy"
      value = "upsert-only"
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "external-dns"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_dns[0].arn
    },
  ]

  depends_on = [aws_iam_role_policy.external_dns]
}
