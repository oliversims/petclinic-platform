# =============================================================================
# terraform/modules/observability/loki.tf
# Purpose: Loki log store and Fluent Bit log shipper.
#
# Flow: Fluent Bit ships pod logs to Loki; Grafana queries Loki.
# Gated by install_observability.
#
# Linked: main.tf sizing locals; prometheus-stack Grafana datasource.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Loki Helm - SingleBinary store; retention/PVC from main.tf locals
# -----------------------------------------------------------------------------

resource "helm_release" "loki" {
  count = var.install_observability ? 1 : 0

  name             = "loki"
  repository       = "https://grafana-community.github.io/helm-charts"
  chart            = "loki"
  version          = var.loki_chart_version
  namespace        = local.monitoring_namespace
  create_namespace = false

  values = [
    templatefile("${path.module}/values/loki.yaml.tftpl", {
      retention_hours = local.loki_retention_hours
      pvc_size        = local.loki_pvc_size
    })
  ]

  depends_on = [kubernetes_config_map.loki_alerting_rules]
}

# -----------------------------------------------------------------------------
# 2) Loki alerting rules ConfigMap - petclinic log alerts from Git
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "loki_alerting_rules" {
  count = var.install_observability ? 1 : 0

  metadata {
    name      = "loki-alerting-rules"
    namespace = local.monitoring_namespace
  }

  data = {
    "petclinic-log-alerts.yaml" = file("${path.module}/../../../k8s/observability/loki-rules/petclinic-log-alerts.yaml")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# -----------------------------------------------------------------------------
# 3) Fluent Bit Helm - ship to loki.monitoring.svc; wait=false for DaemonSet
# -----------------------------------------------------------------------------

resource "helm_release" "fluent_bit" {
  count = var.install_observability ? 1 : 0

  name             = "fluent-bit"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  version          = var.fluent_bit_chart_version
  namespace        = local.monitoring_namespace
  create_namespace = false

  values = [
    file("${path.module}/values/fluent-bit.yaml")
  ]

  wait    = false
  timeout = 300

  depends_on = [helm_release.loki]
}
