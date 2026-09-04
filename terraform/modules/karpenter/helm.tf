# =============================================================================
# terraform/modules/karpenter/helm.tf
# Purpose: Install Karpenter CRDs, then the controller Helm chart.
#
# Flow: Two Helm releases gated by install_karpenter (wave 2).
#
# Linked: main.tf IRSA; interruption.tf queue; k8s NodePool/EC2NodeClass YAML.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Karpenter CRDs Helm - install CRDs before the controller chart
# -----------------------------------------------------------------------------

resource "helm_release" "karpenter_crd" {
  count = var.install_karpenter ? 1 : 0

  name             = "karpenter-crd"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter-crd"
  version          = var.karpenter_chart_version
  namespace        = "karpenter"
  create_namespace = true
}

# -----------------------------------------------------------------------------
# 2) Karpenter controller Helm - queue name, IRSA annotation, MNG resources
# -----------------------------------------------------------------------------

resource "helm_release" "karpenter" {
  count = var.install_karpenter ? 1 : 0

  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_chart_version
  namespace        = "karpenter"
  create_namespace = false

  set = [
    {
      name  = "settings.clusterName"
      value = var.cluster_name
    },
    {
      name  = "settings.clusterEndpoint"
      value = var.cluster_endpoint
    },
    {
      name  = "settings.interruptionQueue"
      value = aws_sqs_queue.interruption[0].name
    },
    {
      name  = "serviceAccount.name"
      value = "karpenter"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.controller[0].arn
    },
    {
      name  = "controller.resources.requests.cpu"
      value = "100m"
    },
    {
      name  = "controller.resources.requests.memory"
      value = "256Mi"
    },
    {
      name  = "controller.resources.limits.memory"
      value = "512Mi"
    },
  ]

  depends_on = [
    helm_release.karpenter_crd,
    aws_iam_role_policy_attachment.controller,
    aws_sqs_queue_policy.interruption,
  ]
}
