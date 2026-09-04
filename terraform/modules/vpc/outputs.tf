# =============================================================================
# terraform/modules/vpc/outputs.tf
# Purpose: VPC/subnet IDs and security group IDs for later modules.
#
# Linked: environments/{dev,prod}/main.tf consumers (eks, rds, dns, …).
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Network
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes, RDS), ordered by availability zone."
  value       = aws_subnet.private[*].id
}

# -----------------------------------------------------------------------------
# 2) Security groups
# -----------------------------------------------------------------------------

output "eks_cluster_sg_id" {
  description = "EKS cluster (control plane) security group ID."
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID."
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "RDS security group ID."
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}
