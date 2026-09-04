# =============================================================================
# terraform/modules/secrets/eso.tf
# Purpose: Install External Secrets Operator with Helm.
#
# Flow: Helm release gated by install_external_secrets (wave 2).
# Uses IRSA role from main.tf.
#
# Linked: main.tf eso-role; k8s ClusterSecretStore / ExternalSecrets.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) External Secrets Helm - CRDs, fixed SA name, IRSA role annotation
# -----------------------------------------------------------------------------

resource "helm_release" "external_secrets" {
  count = var.install_eso ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.eso_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "external-secrets-sa"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.eso[0].arn
    },
  ]
}
