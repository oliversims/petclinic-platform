# =============================================================================
# terraform/modules/ecr/variables.tf
# Purpose: Inputs for the ECR module.
#
# Linked: environments/{dev,prod}/main.tf module.ecr.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Identity - repositories live under petclinic-{env}/
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
# 2) Repositories - one per service, mutability set per environment
# -----------------------------------------------------------------------------

variable "service_names" {
  description = "Service names to create repositories for, one repository per name."
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Tag mutability for every repository. MUTABLE in dev (tags can be re-pushed), IMMUTABLE in prod."
  type        = string

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either 'MUTABLE' or 'IMMUTABLE'."
  }
}

# -----------------------------------------------------------------------------
# 3) Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto resources created by this module."
  type        = map(string)
  default     = {}
}
