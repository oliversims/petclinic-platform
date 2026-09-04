# =============================================================================
# terraform/modules/vpc/versions.tf
# Purpose: Terraform and provider version pins for this module.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Terraform block - required version and aws provider pin
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
