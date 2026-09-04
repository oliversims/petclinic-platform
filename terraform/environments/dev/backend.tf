# =============================================================================
# terraform/environments/dev/backend.tf
# Purpose: Remote state — S3 + DynamoDB lock. Key: petclinic/dev/terraform.tfstate.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Backend - S3 state and DynamoDB lock table
# -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-742934034265"
    key            = "petclinic/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
