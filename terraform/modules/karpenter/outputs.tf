# =============================================================================
# terraform/modules/karpenter/outputs.tf
# Purpose: Values NodePool YAML and the operator need after apply.
#
# Linked: environments/{dev,prod}/outputs.tf; k8s Karpenter manifests.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Operator wiring - IRSA ARN, queue name, instance profile for EC2NodeClass
# -----------------------------------------------------------------------------

output "karpenter_role_arn" {
  description = "Karpenter controller IRSA role ARN. Null until install_karpenter is true."
  value       = var.install_karpenter ? aws_iam_role.controller[0].arn : null
}

output "karpenter_queue_name" {
  description = "SQS interruption queue name. Null until install_karpenter is true."
  value       = var.install_karpenter ? aws_sqs_queue.interruption[0].name : null
}

output "karpenter_instance_profile_name" {
  description = "Instance profile for EC2NodeClass. Null until install_karpenter is true."
  value       = var.install_karpenter ? aws_iam_instance_profile.node[0].name : null
}
