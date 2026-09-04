# =============================================================================
# terraform/environments/prod/outputs.tf
# Purpose: Values the operator copies into Helm/K8s after apply.
#
# Linked: helm-values/prod.yaml placeholders; k8s/argocd/ingress/prod.yaml.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Cluster access
# -----------------------------------------------------------------------------

output "kubeconfig_command" {
  description = "Command that points kubectl at this cluster."
  value       = module.eks.kubeconfig_command
}

# -----------------------------------------------------------------------------
# 2) Helm / app wiring
# -----------------------------------------------------------------------------

output "helm_image_registry" {
  description = "Helm image.registry value: {account}.dkr.ecr.{region}.amazonaws.com/petclinic-{environment}."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/petclinic-${var.environment}"
}

output "alb_sg_id" {
  description = "App ALB security group ID. Replaces ALB_SG_ID in helm-values/{env}.yaml."
  value       = module.vpc.alb_sg_id
}

output "fqdn" {
  description = "App hostname. Replaces DOMAIN in helm-values/{env}.yaml."
  value       = module.dns.fqdn
}

output "certificate_arn" {
  description = "Wildcard ACM ARN. Replaces CERT_ARN in helm-values and Argo ingress YAML."
  value       = module.dns.certificate_arn
}

output "rds_jdbc_url" {
  description = "JDBC URL for SPRING_DATASOURCE_URL in helm-values."
  value       = "jdbc:mysql://${module.rds.endpoint}:${module.rds.port}/${module.rds.database_name}"
}

# -----------------------------------------------------------------------------
# 3) Admin UIs
# -----------------------------------------------------------------------------

output "argocd_url" {
  description = "HTTPS URL for Argo CD. Null until ingress is active."
  value       = module.dns.argocd_url
}

output "ops_alb_sg_id" {
  description = "Ops ALB SG for Grafana/Zipkin/Argo. Replaces OPS_ALB_SG_ID in k8s/argocd/ingress/prod.yaml."
  value       = module.dns.ops_alb_sg_id
}

output "grafana_admin_password" {
  description = "Grafana admin password. Null until install_observability is true."
  value       = module.observability.grafana_admin_password
  sensitive   = true
}

output "grafana_url" {
  description = "HTTPS URL for Grafana. Null until ingress is active."
  value       = module.observability.grafana_url
}

output "zipkin_url" {
  description = "HTTPS URL for Zipkin. Null until ingress is active."
  value       = module.observability.zipkin_url
}

# -----------------------------------------------------------------------------
# 4) Karpenter (NodePool / EC2NodeClass YAML)
# -----------------------------------------------------------------------------

output "karpenter_queue_name" {
  description = "SQS interruption queue name. Null until install_karpenter is true."
  value       = module.karpenter.karpenter_queue_name
}

output "karpenter_role_arn" {
  description = "Karpenter controller IRSA role ARN. Null until install_karpenter is true."
  value       = module.karpenter.karpenter_role_arn
}

output "karpenter_instance_profile_name" {
  description = "Instance profile for EC2NodeClass. Null until install_karpenter is true."
  value       = module.karpenter.karpenter_instance_profile_name
}
