# =============================================================================
# terraform/environments/prod/variables.tf
# Purpose: Root inputs. Values come from terraform.tfvars (no defaults).
#
# Linked: terraform.tfvars; main.tf module arguments.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Identity
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for all resources in this environment."
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

variable "project" {
  description = "Project name, used as the first segment of every resource name."
  type        = string
}

# -----------------------------------------------------------------------------
# 2) Network - passed through to module.vpc
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (ALB, NAT Gateways), one per availability zone."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (EKS nodes, RDS), one per availability zone."
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones the subnets are spread across."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true creates one NAT Gateway (dev). false creates one NAT Gateway per AZ (prod)."
  type        = bool
}

# -----------------------------------------------------------------------------
# 3) EKS - cluster version, node shape, who may reach the public Kubernetes API
# -----------------------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Operator public IPv4 /32 — never 0.0.0.0/0."
  type        = list(string)
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
}

variable "node_ami_type" {
  description = "AMI type for the managed node group. ARM64 (Graviton) to match t4g instances."
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

variable "install_ebs_csi" {
  description = "Create the EKS managed add-ons, EBS CSI IRSA role, and gp3 StorageClass. Only true once this environment's cluster exists."
  type        = bool
}

# -----------------------------------------------------------------------------
# 4) ECR - repositories and tag mutability
# -----------------------------------------------------------------------------

variable "service_names" {
  description = "Service names to create ECR repositories for, one repository per name."
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Tag mutability for every ECR repository. MUTABLE in dev, IMMUTABLE in prod."
  type        = string
}

# -----------------------------------------------------------------------------
# 5) RDS - engine, sizing, and durability
# -----------------------------------------------------------------------------

variable "rds_engine_version" {
  description = "MySQL engine version, pinned to an 8.0.x release."
  type        = string
}

variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "rds_allocated_storage" {
  description = "Initial storage in GB."
  type        = number
}

variable "rds_max_allocated_storage" {
  description = "Maximum storage in GB. Equal to allocated storage disables autoscaling."
  type        = number
}

variable "rds_multi_az" {
  description = "Whether to run a standby in a second AZ."
  type        = bool
}

variable "rds_backup_retention_period" {
  description = "Days of automated backups to retain."
  type        = number
}

variable "rds_skip_final_snapshot" {
  description = "Skip the final snapshot when the instance is destroyed."
  type        = bool
}

variable "rds_deletion_protection" {
  description = "Whether AWS blocks deletion of the instance."
  type        = bool
}

# -----------------------------------------------------------------------------
# 6) Secrets - values supplied at plan time, never committed
# -----------------------------------------------------------------------------

variable "openai_api_key" {
  description = "OpenAI API key for genai-service. Set in terraform.tfvars (gitignored) or via TF_VAR_openai_api_key."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# 7) External Secrets Operator
# -----------------------------------------------------------------------------

variable "install_eso" {
  description = "Install External Secrets Operator with Helm. Only true once this environment's EKS cluster exists."
  type        = bool
}

variable "eso_chart_version" {
  description = "Version of the external-secrets Helm chart. Pinned, never 'latest'."
  type        = string
}

# -----------------------------------------------------------------------------
# 8) GitHub Actions OIDC - github_org / github_app_repo live in the dev root only
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 9) DNS and Ingress
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Public parent domain that owns the hosted zone. Set in terraform.tfvars (gitignored)."
  type        = string
}

variable "create_hosted_zone" {
  description = "Create the public hosted zone instead of looking it up. True in at most one environment."
  type        = bool
}

variable "create_acm_certificate" {
  description = "Issue the *.{domain} wildcard certificate here. True in at most one environment; the other looks it up."
  type        = bool
}

variable "install_lb_controller" {
  description = "Install the AWS Load Balancer Controller. Only true once this environment's EKS cluster exists."
  type        = bool
}

variable "lb_controller_chart_version" {
  description = "Version of the aws-load-balancer-controller Helm chart. Pinned, never 'latest'."
  type        = string
}

variable "install_external_dns" {
  description = "Install ExternalDNS. Only true once this environment's EKS cluster exists."
  type        = bool
}

variable "external_dns_chart_version" {
  description = "Version of the external-dns Helm chart. Pinned, never 'latest'."
  type        = string
}

variable "argocd_ingress_enabled" {
  description = "Create the Argo CD Ingress security group wiring. Operator applies k8s/argocd/ingress/{env}.yaml."
  type        = bool
}

variable "shared_alb" {
  description = "false = public app ALB + ops ALB (Grafana/Zipkin/Argo). true = one ALB for everything."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# 10) Observability
# -----------------------------------------------------------------------------

variable "install_observability" {
  description = "Install the monitoring, logging, and tracing releases. Only true once this environment's cluster exists."
  type        = bool
}

variable "grafana_ingress_enabled" {
  description = "Create a dedicated HTTPS ALB for Grafana. Alertmanager stays port-forward."
  type        = bool
}

variable "zipkin_ingress_enabled" {
  description = "Create a dedicated HTTPS ALB for the Zipkin UI. Apps still POST spans in-cluster."
  type        = bool
}

variable "slack_webhook_url" {
  description = "Incoming Slack webhook URL for Alertmanager. Empty keeps the blackhole. Set in terraform.tfvars (gitignored); never commit."
  type        = string
  sensitive   = true
  default     = ""
}

variable "slack_channel" {
  description = "Slack channel the webhook posts to, including the leading #."
  type        = string
  default     = "#petclinic-alerts"
}

variable "kube_prometheus_stack_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart. Pinned, never 'latest'."
  type        = string
}

variable "loki_chart_version" {
  description = "Version of the loki Helm chart. Pinned, never 'latest'."
  type        = string
}

variable "fluent_bit_chart_version" {
  description = "Version of the fluent-bit Helm chart. Pinned, never 'latest'."
  type        = string
}

# -----------------------------------------------------------------------------
# 11) Karpenter and cost
# -----------------------------------------------------------------------------

variable "install_karpenter" {
  description = "Install the Karpenter CRD and controller charts. Only true once this environment's EKS cluster exists."
  type        = bool
}

variable "karpenter_chart_version" {
  description = "Version of the karpenter and karpenter-crd charts. Pinned, never 'latest'."
  type        = string
}

variable "budget_limit_amount" {
  description = "Monthly budget ceiling in USD for this environment."
  type        = string
}

variable "budget_notification_email" {
  description = "Address that receives budget alerts. Set in terraform.tfvars (gitignored); never commit an address."
  type        = string
  sensitive   = true
}
