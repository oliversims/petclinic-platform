# =============================================================================
# terraform/modules/eks/addons.tf
# Purpose: EKS managed add-ons and gp3 StorageClass for PVCs.
#
# Flow: CoreDNS/kube-proxy/vpc-cni always; EBS CSI (+ IRSA) when install_ebs_csi.
# gp3 StorageClass for observability PVCs.
#
# Linked: main.tf cluster/OIDC; observability module PVCs.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Locals - managed add-on set including metrics-server for HPAs (PETPLAT-72)
# -----------------------------------------------------------------------------

locals {
  managed_addons = toset([
    "coredns",
    "kube-proxy",
    "vpc-cni",
    "aws-ebs-csi-driver",
    "metrics-server",
  ])
}

# -----------------------------------------------------------------------------
# 2) EBS CSI assume-role - IRSA trust for ebs-csi-controller-sa
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  count = var.install_ebs_csi ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 3) EBS CSI IAM role - ASCII-only description; attaches/detaches volumes
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ebs_csi" {
  count = var.install_ebs_csi ? 1 : 0

  name               = "${local.name_prefix}-ebs-csi-role"
  description        = "EBS CSI driver - manages EBS volumes for ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ebs-csi-role"
  })
}

# -----------------------------------------------------------------------------
# 4) EBS CSI policy attachment - AmazonEBSCSIDriverPolicy
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = var.install_ebs_csi ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# -----------------------------------------------------------------------------
# 5) Add-on versions - most_recent concrete version per cluster Kubernetes version
# -----------------------------------------------------------------------------

data "aws_eks_addon_version" "this" {
  for_each = var.install_ebs_csi ? local.managed_addons : toset([])

  addon_name         = each.value
  kubernetes_version = var.cluster_version
  most_recent        = true
}

# -----------------------------------------------------------------------------
# 6) Managed add-ons - networking/DNS/CSI/metrics; vpc-cni enables NetworkPolicy
# -----------------------------------------------------------------------------

resource "aws_eks_addon" "this" {
  for_each = var.install_ebs_csi ? local.managed_addons : toset([])

  cluster_name             = aws_eks_cluster.this.name
  addon_name               = each.value
  addon_version            = data.aws_eks_addon_version.this[each.value].version
  service_account_role_arn = each.value == "aws-ebs-csi-driver" ? aws_iam_role.ebs_csi[0].arn : null

  configuration_values = each.value == "vpc-cni" ? jsonencode({
    enableNetworkPolicy = "true"
  }) : null

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${each.value}"
  })

  depends_on = [
    aws_eks_node_group.this,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

# -----------------------------------------------------------------------------
# 7) gp3 StorageClass - default class for Prometheus/Grafana/Loki PVCs
# -----------------------------------------------------------------------------

resource "kubernetes_storage_class" "gp3" {
  count = var.install_ebs_csi ? 1 : 0

  metadata {
    name = "gp3"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.this]
}
