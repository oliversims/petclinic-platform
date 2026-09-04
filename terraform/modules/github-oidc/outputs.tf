# =============================================================================
# terraform/modules/github-oidc/outputs.tf
# Purpose: Role ARN for the AWS_ROLE_ARN GitHub secret.
#
# Linked: environments/{dev,prod}/outputs.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) CI role - set as AWS_ROLE_ARN on the app fork
# -----------------------------------------------------------------------------

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions. Set as the AWS_ROLE_ARN secret on the app fork."
  value       = aws_iam_role.github_actions.arn
}
