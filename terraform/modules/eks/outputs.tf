# =============================================================================
# terraform/modules/eks/outputs.tf
# Purpose: Cluster endpoint, CA, OIDC, and security group IDs for dependents.
#
# Linked: environments/{dev,prod}/outputs.tf; secrets/karpenter/dns modules.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Cluster
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

# -----------------------------------------------------------------------------
# 2) IRSA
# -----------------------------------------------------------------------------

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IAM Roles for Service Accounts."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL for IAM Roles for Service Accounts."
  value       = aws_iam_openid_connect_provider.this.url
}

# -----------------------------------------------------------------------------
# 3) Node group
# -----------------------------------------------------------------------------

output "node_role_arn" {
  description = "Worker node IAM role ARN."
  value       = aws_iam_role.node.arn
}

# -----------------------------------------------------------------------------
# 4) Access
# -----------------------------------------------------------------------------

output "kubeconfig_command" {
  description = "Command that points kubectl at this cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${data.aws_region.current.name}"
}
