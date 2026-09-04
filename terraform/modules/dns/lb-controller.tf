# =============================================================================
# terraform/modules/dns/lb-controller.tf
# Purpose: AWS Load Balancer Controller IRSA role and Helm release.
#
# Flow: IRSA + Helm when install_lb_controller. Creates ALBs from Ingresses.
#
# Linked: main.tf cert; vpc ALB SG; ExternalDNS for DNS records.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Assume-role policy - IRSA trust for aws-load-balancer-controller in kube-system
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "lb_controller_assume_role" {
  count = var.install_lb_controller ? 1 : 0

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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 2) IAM role - LB Controller IRSA role (ASCII-only description for IAM)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lb_controller" {
  count = var.install_lb_controller ? 1 : 0

  name               = "${local.name_prefix}-lb-controller-role"
  description        = "AWS Load Balancer Controller - manages ALBs for ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume_role[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lb-controller-role"
  })
}

# -----------------------------------------------------------------------------
# 3) IAM policy - official LB Controller permissions (vendored upstream v3.5.0)
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "lb_controller" {
  count = var.install_lb_controller ? 1 : 0

  name        = "${local.name_prefix}-lb-controller-policy"
  description = "Official AWS Load Balancer Controller policy (upstream v3.5.0, unmodified)"
  policy      = file("${path.module}/iam/lb-controller-iam-policy.json")

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lb-controller-policy"
  })
}

# -----------------------------------------------------------------------------
# 4) Policy attachment - bind controller policy to the IRSA role
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "lb_controller" {
  count = var.install_lb_controller ? 1 : 0

  role       = aws_iam_role.lb_controller[0].name
  policy_arn = aws_iam_policy.lb_controller[0].arn
}

# -----------------------------------------------------------------------------
# 5) Helm release - installs the controller and the alb IngressClass
# -----------------------------------------------------------------------------

resource "helm_release" "lb_controller" {
  count = var.install_lb_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "region"
      value = data.aws_region.current.name
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.lb_controller[0].arn
    },
    {
      name  = "ingressClass"
      value = "alb"
    },
    {
      name  = "createIngressClassResource"
      value = "true"
    },
  ]

  depends_on = [aws_iam_role_policy_attachment.lb_controller]
}
