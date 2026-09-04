# =============================================================================
# terraform/modules/rds/variables.tf
# Purpose: Inputs for the RDS module.
#
# Linked: environments/{dev,prod}/main.tf module.rds.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Identity - used in every Name tag (petclinic-{env}-…)
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
# 2) Placement - private subnets and the SG created by the VPC module
# -----------------------------------------------------------------------------

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the instance. Created by the VPC module; this module never creates one."
  type        = string
}

# -----------------------------------------------------------------------------
# 3) Engine and database
# -----------------------------------------------------------------------------

variable "engine_version" {
  description = "MySQL engine version, pinned to an 8.0.x release."
  type        = string
}

# -----------------------------------------------------------------------------
# 4) Sizing and durability
# -----------------------------------------------------------------------------

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Initial storage in GB."
  type        = number
}

variable "max_allocated_storage" {
  description = "Maximum storage in GB. Equal to allocated_storage disables storage autoscaling."
  type        = number
}

variable "multi_az" {
  description = "Whether to run a standby in a second AZ. false in both envs as a cost optimization."
  type        = bool
}

variable "backup_retention_period" {
  description = "Days of automated backups to retain."
  type        = number
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when the instance is destroyed."
  type        = bool
}

variable "deletion_protection" {
  description = "Whether AWS blocks deletion of the instance."
  type        = bool
}

# -----------------------------------------------------------------------------
# 5) Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto resources created by this module."
  type        = map(string)
  default     = {}
}
