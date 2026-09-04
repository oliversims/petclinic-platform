# =============================================================================
# terraform/modules/secrets/versions.tf
# Purpose: Terraform and provider version pins for this module.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Terraform block - required version and provider pins
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}
