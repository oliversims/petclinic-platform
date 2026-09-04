# =============================================================================
# terraform/modules/eks/variables.tf
# Purpose: Inputs for the EKS module.
#
# Linked: environments/{dev,prod}/main.tf module.eks.
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
# 2) Cluster - version, placement, and who may reach the public API
# -----------------------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes version for the cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control plane and the worker nodes."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Operator public IPv4 /32 — never 0.0.0.0/0."
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security group ID for the EKS control plane."
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for the worker nodes."
  type        = string
}

# -----------------------------------------------------------------------------
# 3) Node group - sizing/shape; AMI must be AL2023_ARM_64_STANDARD (API name)
# -----------------------------------------------------------------------------

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
}

variable "node_ami_type" {
  description = "AMI type for the managed node group. ARM64 (Graviton) to match t4g instances. Spec short name AL2023_ARM_64 maps to AWS API AL2023_ARM_64_STANDARD."
  type        = string
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
}

variable "node_disk_size" {
  description = "Root volume size in GB for each worker node."
  type        = number
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
# 5) Add-ons and storage
# -----------------------------------------------------------------------------

variable "install_ebs_csi" {
  description = "Create the EKS managed add-ons, the EBS CSI IRSA role, and the gp3 StorageClass. False skips them so a root with no cluster can still plan."
  type        = bool
}
