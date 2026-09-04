# =============================================================================
# terraform/modules/secrets/variables.tf
# Purpose: Inputs for the secrets module.
#
# Linked: environments/{dev,prod}/main.tf module.secrets.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Identity - used in secret names and the role name
# -----------------------------------------------------------------------------

variable "project" {
  description = "Project name, used as the first segment of every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name. Must be 'dev' or 'prod'."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

# -----------------------------------------------------------------------------
# 2) Secret values - supplied by the root, never hardcoded
# -----------------------------------------------------------------------------

variable "openai_api_key" {
  description = "OpenAI API key for genai-service. Comes from terraform.tfvars or TF_VAR_openai_api_key."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# 3) IRSA - OIDC provider created by the EKS module
# -----------------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN, used as the federated principal in the ESO trust policy."
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL, used to build the ESO trust policy condition keys."
  type        = string
}

# -----------------------------------------------------------------------------
# 4) Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto resources created by this module."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# 5) External Secrets Operator - install is gated on the cluster existing
# -----------------------------------------------------------------------------

variable "install_eso" {
  description = "Install External Secrets Operator with Helm. false skips the release so a root with no cluster can still plan."
  type        = bool
}

variable "eso_chart_version" {
  description = "Version of the external-secrets Helm chart. Pinned, never 'latest'."
  type        = string
}
