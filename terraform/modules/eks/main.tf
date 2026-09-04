# =============================================================================
# terraform/modules/eks/main.tf
# Purpose: EKS control plane — cluster IAM, cluster, OIDC, access entries.
#
# Flow: cluster role -> EKS cluster -> OIDC provider for IRSA.
#
# Linked: node-group.tf, addons.tf; vpc module; called from environments/{dev,prod}.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Caller identity - account context for the deploying principal
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# 2) Session context - resolve session ARNs to the IAM user/role EKS accepts
# -----------------------------------------------------------------------------

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# -----------------------------------------------------------------------------
# 3) Current region - used in kubeconfig helper output
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# 4) Locals - cluster name, OIDC host for IRSA conditions, extra tags
# -----------------------------------------------------------------------------

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = local.name_prefix

  oidc_provider_host = replace(aws_iam_openid_connect_provider.this.url, "https://", "")

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 5) Cluster assume-role policy - eks.amazonaws.com may assume the role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 6) Cluster IAM role - EKS assumes this to manage AWS resources
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
  })
}

# -----------------------------------------------------------------------------
# 7) Cluster policy attachment - AmazonEKSClusterPolicy
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -----------------------------------------------------------------------------
# 8) EKS cluster - private subnets; public API CIDR-limited; access entries own kubectl
# -----------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_sg_id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = false
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(local.tags, {
    Name = local.cluster_name
  })

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# -----------------------------------------------------------------------------
# 9) OIDC provider - lets service accounts assume IAM roles (IRSA)
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-oidc"
  })
}

# -----------------------------------------------------------------------------
# 10) Access entry - deploying principal gets a STANDARD entry
# -----------------------------------------------------------------------------

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_iam_session_context.current.issuer_arn
  type          = "STANDARD"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-access-admin"
  })
}

# -----------------------------------------------------------------------------
# 11) Access policy - cluster-admin for the deploying principal
# -----------------------------------------------------------------------------

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_iam_session_context.current.issuer_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
