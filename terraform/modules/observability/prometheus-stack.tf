# =============================================================================
# terraform/modules/observability/prometheus-stack.tf
# Purpose: kube-prometheus-stack — Prometheus, Grafana, Alertmanager.
#
# Flow: Helm release into monitoring namespace when install_observability is true.
# Grafana Ingress uses grafana-ingress.tf ALB SG when enabled.
#
# Linked: main.tf locals, values/kube-prometheus-stack.yaml.tftpl,
# grafana-ingress.tf, dashboards.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Locals - static scrape ports per service; alert rules from Git
# -----------------------------------------------------------------------------

locals {
  scrape_targets = {
    config-server     = 8888
    discovery-server  = 8761
    api-gateway       = 8080
    customers-service = 8081
    visits-service    = 8082
    vets-service      = 8083
    genai-service     = 8084
    admin-server      = 9090
  }

  rules_dir = "${path.module}/../../../k8s/observability/prometheus-rules"
  prometheus_rules = {
    for f in fileset(local.rules_dir, "*.yaml") :
    trimsuffix(f, ".yaml") => file("${local.rules_dir}/${f}")
  }
}

# -----------------------------------------------------------------------------
# 2) kube-prometheus-stack Helm - admin password via set_sensitive only
# -----------------------------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  count = var.install_observability ? 1 : 0

  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_chart_version
  namespace        = local.monitoring_namespace
  create_namespace = true

  values = [
    templatefile("${path.module}/values/kube-prometheus-stack.yaml.tftpl", {
      app_namespace              = local.app_namespace
      scrape_targets             = local.scrape_targets
      retention                  = local.prometheus_retention
      prometheus_pvc_size        = local.prometheus_pvc_size
      loki_url                   = "http://loki.${local.monitoring_namespace}.svc:3100"
      prometheus_rules           = local.prometheus_rules
      grafana_ingress_enabled    = var.grafana_ingress_enabled
      grafana_host               = local.grafana_host
      grafana_certificate_arn    = var.certificate_arn
      grafana_alb_sg_id          = local.grafana_alb_sg_id
      grafana_load_balancer_name = local.grafana_lb_name
      grafana_alb_group_name     = local.alb_group_name
      slack_enabled              = trimspace(var.slack_webhook_url) != ""
      slack_webhook_url          = var.slack_webhook_url
      slack_channel              = var.slack_channel
    })
  ]

  set_sensitive = [
    {
      name  = "grafana.adminPassword"
      value = random_password.grafana_admin[0].result
    },
  ]

  timeout = 600
}
