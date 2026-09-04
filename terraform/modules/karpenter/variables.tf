# =============================================================================
# terraform/modules/karpenter/variables.tf
# Purpose: Inputs for the Karpenter module.
#
# Linked: environments/{dev,prod}/main.tf module.karpenter.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Identity - used in role, policy, and instance profile names
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
# 2) Cluster wiring - from the eks module
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name. Also the SQS interruption queue name, matching upstream."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API server endpoint. Passed to Helm as settings.clusterEndpoint so the controller does not have to discover it."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN, used as the federated principal in the IRSA trust policy."
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL, used to build the IRSA trust policy condition keys."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EXISTING managed node group IAM role. Karpenter nodes reuse it through an instance profile; this module never creates a second node role."
  type        = string
}

# -----------------------------------------------------------------------------
# 3) Install gate - same pattern as install_eso
# -----------------------------------------------------------------------------

variable "install_karpenter" {
  description = "Install the Karpenter CRD and controller charts. False skips them so a root with no cluster can still plan."
  type        = bool
}

variable "karpenter_chart_version" {
  description = "Version of the karpenter and karpenter-crd charts. Pinned, never 'latest'."
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
