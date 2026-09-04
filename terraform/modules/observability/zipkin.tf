# =============================================================================
# terraform/modules/observability/zipkin.tf
# Purpose: Install the in-repo Zipkin chart into the tracing namespace.
#
# Flow: Helm release when install_observability is true. Apps push spans
# in-cluster; optional HTTPS UI via zipkin-ingress.tf.
#
# Linked: helm/zipkin, zipkin-ingress.tf, main.tf hosts.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Zipkin Helm - in-repo chart; optional ALB Ingress for the UI
# -----------------------------------------------------------------------------

resource "helm_release" "zipkin" {
  count = var.install_observability ? 1 : 0

  name             = "zipkin"
  chart            = "${path.module}/../../../helm/zipkin"
  namespace        = local.tracing_namespace
  create_namespace = true

  set = [
    {
      name  = "ingress.enabled"
      value = var.zipkin_ingress_enabled ? "true" : "false"
    },
    {
      name  = "ingress.host"
      value = local.zipkin_host
    },
    {
      name  = "ingress.certificateArn"
      value = var.certificate_arn
    },
    {
      name  = "ingress.albSecurityGroupId"
      value = local.zipkin_alb_sg_id
    },
    {
      name  = "ingress.loadBalancerName"
      value = local.zipkin_lb_name
    },
    {
      name  = "ingress.groupName"
      value = local.alb_group_name
    },
  ]
}
