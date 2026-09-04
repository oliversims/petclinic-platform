# =============================================================================
# terraform/modules/observability/main.tf
# Purpose: In-cluster metrics, logs, and traces (not CloudWatch).
#
# Flow: Prometheus scrapes the 8 services; Loki+Fluent Bit ship logs; Zipkin
# takes spans. Grafana reads Prometheus + Loki. Releases gated by
# install_observability (wave 2). Learning-size values for two t4g.small nodes.
#
# Linked: prometheus-stack.tf, loki.tf, zipkin.tf, dashboards.tf,
# grafana-ingress.tf, zipkin-ingress.tf; StorageClass from eks/addons.tf;
# called from environments/{dev,prod}/main.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Locals - namespaces, retention/PVC sizing, Grafana/Zipkin hosts, ALB flags
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  app_namespace        = "petclinic-${var.environment}"
  monitoring_namespace = "monitoring"
  tracing_namespace    = "tracing"

  prometheus_retention = var.environment == "prod" ? "15d" : "7d"
  prometheus_pvc_size  = var.environment == "prod" ? "50Gi" : "10Gi"
  loki_retention_hours = var.environment == "prod" ? "720h" : "168h"
  loki_pvc_size        = var.environment == "prod" ? "50Gi" : "10Gi"

  grafana_host = var.environment == "prod" ? "grafana.${var.domain_name}" : "grafana-${var.environment}.${var.domain_name}"
  grafana_url  = "https://${local.grafana_host}"

  grafana_ingress_active = var.install_observability && var.grafana_ingress_enabled && var.install_lb_controller
  zipkin_ingress_active  = var.install_observability && var.zipkin_ingress_enabled && var.install_lb_controller

  alb_group_name  = var.shared_alb ? local.name_prefix : "${local.name_prefix}-ops"
  grafana_lb_name = var.shared_alb ? local.name_prefix : "${local.name_prefix}-ops"
  zipkin_lb_name  = var.shared_alb ? local.name_prefix : "${local.name_prefix}-ops"
  ingress_alb_sg_id = var.shared_alb ? var.alb_sg_id : var.ops_alb_sg_id
  grafana_alb_sg_id = local.grafana_ingress_active ? local.ingress_alb_sg_id : ""
  zipkin_alb_sg_id  = local.zipkin_ingress_active ? local.ingress_alb_sg_id : ""

  zipkin_host = var.environment == "prod" ? "zipkin.${var.domain_name}" : "zipkin-${var.environment}.${var.domain_name}"
  zipkin_url  = "https://${local.zipkin_host}"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 2) Grafana admin password - generated here, never stored in Git
# -----------------------------------------------------------------------------

resource "random_password" "grafana_admin" {
  count = var.install_observability ? 1 : 0

  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?."
}
