# =============================================================================
# terraform/modules/dns/outputs.tf
# Purpose: FQDN, cert ARN, Argo URL, and ops ALB SG for Helm and ingress YAML.
#
# Linked: environments/{dev,prod}/outputs.tf; helm-values DOMAIN/CERT_ARN.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Ingress inputs - operator copies these into helm-values/{env}.yaml
# -----------------------------------------------------------------------------

output "fqdn" {
  description = "Hostname this environment's Ingress serves. Replaces DOMAIN in helm-values/{env}.yaml."
  value       = local.fqdn
}

output "certificate_arn" {
  description = "Wildcard ACM certificate ARN. The same value goes in BOTH helm-values/dev.yaml and prod.yaml as CERT_ARN."
  value       = local.certificate_arn
}

# -----------------------------------------------------------------------------
# 2) Argo CD and ops ALB
# -----------------------------------------------------------------------------

output "argocd_url" {
  description = "HTTPS URL for Argo CD when ingress is active (enabled and LB controller installed)."
  value       = local.argocd_ingress_active ? local.argocd_url : null
}

output "ops_alb_sg_id" {
  description = "Ops ALB security group ID (Grafana/Zipkin/Argo). Empty when shared_alb; use alb_sg_id for Argo on shared ALB."
  value       = local.ops_alb_active ? aws_security_group.ops_alb[0].id : ""
}
