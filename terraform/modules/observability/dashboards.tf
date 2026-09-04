# =============================================================================
# terraform/modules/observability/dashboards.tf
# Purpose: Ship Git dashboard JSON into Grafana as ConfigMaps.
#
# Flow: Files under monitoring/dashboards become ConfigMaps Grafana loads.
#
# Linked: prometheus-stack.tf (Grafana), monitoring/dashboards/.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Locals - dashboard JSON files keyed by basename
# -----------------------------------------------------------------------------

locals {
  dashboards_dir = "${path.module}/../../../k8s/observability/grafana-dashboards"
  dashboards = {
    for f in fileset(local.dashboards_dir, "*.json") :
    trimsuffix(f, ".json") => file("${local.dashboards_dir}/${f}")
  }
}

# -----------------------------------------------------------------------------
# 2) Grafana dashboard ConfigMaps - sidecar label + Petclinic folder
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "grafana_dashboards" {
  for_each = var.install_observability ? local.dashboards : {}

  metadata {
    name      = "grafana-dashboard-${each.key}"
    namespace = local.monitoring_namespace

    labels = {
      grafana_dashboard = "1"
    }

    annotations = {
      grafana_folder = "Petclinic"
    }
  }

  data = {
    "${each.key}.json" = each.value
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
