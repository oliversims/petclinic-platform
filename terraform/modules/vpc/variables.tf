# =============================================================================
# terraform/modules/vpc/variables.tf
# Purpose: Inputs for the VPC module.
#
# Linked: environments/{dev,prod}/main.tf module.vpc.
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
# 2) Network layout - 2+ AZs; public for ALB/NAT, private for EKS/RDS
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (ALB, NAT Gateways), one per availability zone."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "public_subnet_cidrs must contain at least 2 CIDRs, one per availability zone."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (EKS nodes, RDS), one per availability zone."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "private_subnet_cidrs must contain at least 2 CIDRs, one per availability zone."
  }
}

variable "availability_zones" {
  description = "Availability zones the subnets are spread across."
  type        = list(string)

  validation {
    condition = (
      length(var.availability_zones) >= 2 &&
      length(var.availability_zones) == length(var.public_subnet_cidrs) &&
      length(var.availability_zones) == length(var.private_subnet_cidrs)
    )
    error_message = "availability_zones must have at least 2 zones and match the length of public_subnet_cidrs and private_subnet_cidrs."
  }
}

variable "single_nat_gateway" {
  description = "true creates one NAT Gateway in the AZ a public subnet (dev). false creates one NAT Gateway per AZ (prod)."
  type        = bool
}

variable "tags" {
  description = "Additional tags merged onto resources created by this module."
  type        = map(string)
  default     = {}
}
