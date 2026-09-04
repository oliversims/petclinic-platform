# =============================================================================
# terraform/modules/observability/outputs.tf
# Purpose: Grafana/Zipkin URLs and admin password for the operator.
#
# Linked: environments/{dev,prod}/outputs.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Operator access - admin password and HTTPS URLs when ingress is active
# -----------------------------------------------------------------------------

output "grafana_admin_password" {
  description = "Grafana admin password. Null until install_observability is true. Read with `terraform output -raw grafana_admin_password`."
  value       = var.install_observability ? random_password.grafana_admin[0].result : null
  sensitive   = true
}

output "grafana_url" {
  description = "HTTPS URL for Grafana when ingress is active."
  value       = local.grafana_ingress_active ? local.grafana_url : null
}

output "zipkin_url" {
  description = "HTTPS URL for Zipkin when ingress is active."
  value       = local.zipkin_ingress_active ? local.zipkin_url : null
}
