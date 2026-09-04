# =============================================================================
# terraform/modules/github-oidc/variables.tf
# Purpose: Inputs for the GitHub Actions OIDC role.
#
# Linked: environments/{dev,prod}/main.tf module.github_oidc.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Identity
# -----------------------------------------------------------------------------

variable "project" {
  description = "Project name, used as the ECR repository prefix and in tags."
  type        = string
}

# -----------------------------------------------------------------------------
# 2) GitHub repository allowed to assume the role
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organisation or user that owns the application fork."
  type        = string
}

variable "github_app_repo" {
  description = "Name of the application repository whose workflow assumes this role."
  type        = string
}

# -----------------------------------------------------------------------------
# 3) Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto resources created by this module."
  type        = map(string)
  default     = {}
}
