# =============================================================================
# terraform/modules/karpenter/main.tf
# Purpose: Karpenter controller IAM, instance profile, interruption queue wiring.
#
# Flow: IRSA + instance profile for nodes Karpenter launches. Queue IAM when
# install_karpenter. Helm lives in helm.tf; EventBridge in interruption.tf.
#
# Linked: helm.tf, interruption.tf; eks OIDC; called from environments/{dev,prod}.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Caller identity - account ID for IAM policy templates
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# 2) Current region - region segment for IAM policy templates
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# 3) Current partition - aws / aws-cn / aws-us-gov for ARNs
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

# -----------------------------------------------------------------------------
# 4) Locals - IRSA host, queue name, policy template vars, controller policies
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  oidc_provider_host = replace(var.oidc_provider_url, "https://", "")

  queue_name = var.cluster_name

  policy_vars = var.install_karpenter ? {
    partition              = data.aws_partition.current.partition
    region                 = data.aws_region.current.name
    account_id             = data.aws_caller_identity.current.account_id
    cluster_name           = var.cluster_name
    node_role_arn          = var.node_role_arn
    interruption_queue_arn = aws_sqs_queue.interruption[0].arn
  } : {}

  controller_policies = var.install_karpenter ? {
    node-lifecycle     = "Node lifecycle - launch, tag, and terminate instances"
    iam-integration    = "IAM integration - pass the node role, manage instance profiles"
    eks-integration    = "EKS integration - describe the cluster"
    interruption       = "Interruption - read and delete SQS messages"
    zonal-shift        = "Zonal shift - read ARC zonal shift state"
    resource-discovery = "Resource discovery - describe EC2, pricing, and SSM parameters"
  } : {}

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 5) Controller assume-role - IRSA trust for karpenter SA in karpenter ns
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "controller_assume_role" {
  count = var.install_karpenter ? 1 : 0

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
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 6) Controller IRSA role - ASCII description; provisions nodes for this env
# -----------------------------------------------------------------------------

resource "aws_iam_role" "controller" {
  count = var.install_karpenter ? 1 : 0

  name               = "${local.name_prefix}-karpenter-role"
  description        = "Karpenter controller - provisions nodes for ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.controller_assume_role[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-karpenter-role"
  })
}

# -----------------------------------------------------------------------------
# 7) Controller policies - vendored Karpenter 1.14 docs (do not hand-edit)
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "controller" {
  for_each = local.controller_policies

  name        = "${local.name_prefix}-karpenter-${each.key}"
  description = "Karpenter 1.14 upstream policy - ${each.value}"
  policy      = templatefile("${path.module}/iam/karpenter-controller-${each.key}.json.tftpl", local.policy_vars)

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-karpenter-${each.key}"
  })
}

# -----------------------------------------------------------------------------
# 8) Controller policy attachments - one managed policy per upstream doc
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "controller" {
  for_each = local.controller_policies

  role       = aws_iam_role.controller[0].name
  policy_arn = aws_iam_policy.controller[each.key].arn
}

# -----------------------------------------------------------------------------
# 9) Node instance profile - wraps existing node role (no second role/aws-auth)
# -----------------------------------------------------------------------------

resource "aws_iam_instance_profile" "node" {
  count = var.install_karpenter ? 1 : 0

  name = "${local.name_prefix}-karpenter-node-profile"
  role = element(split("/", var.node_role_arn), length(split("/", var.node_role_arn)) - 1)

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-karpenter-node-profile"
  })
}
