# =============================================================================
# terraform/modules/eks/versions.tf
# Purpose: Terraform and provider version pins for this module.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Terraform block - aws + kubernetes (gp3 StorageClass) provider pins
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}
