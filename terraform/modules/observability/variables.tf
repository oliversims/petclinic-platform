# =============================================================================
# terraform/modules/observability/variables.tf
# Purpose: Inputs for the observability module.
#
# Linked: environments/{dev,prod}/main.tf module.observability.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Identity - decides the scraped namespace and the per-env sizing
# -----------------------------------------------------------------------------

variable "project" {
  description = "Project name, used as the first segment of every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name. Must be 'dev' or 'prod'. Also selects retention and PVC sizes."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

# -----------------------------------------------------------------------------
# 2) Install gate - same pattern as install_eso
# -----------------------------------------------------------------------------

variable "install_observability" {
  description = "Install the monitoring, logging, and tracing releases. False skips them so a root with no cluster can still plan."
  type        = bool
}

variable "install_lb_controller" {
  description = "Must be true for Grafana/Zipkin Ingress ALB security groups. Same gate as the DNS module Argo CD ALB SG."
  type        = bool
}

# -----------------------------------------------------------------------------
# 3) Chart versions - pinned, never 'latest'
# -----------------------------------------------------------------------------

variable "kube_prometheus_stack_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart."
  type        = string
}

variable "loki_chart_version" {
  description = "Version of the loki Helm chart."
  type        = string
}

variable "fluent_bit_chart_version" {
  description = "Version of the fluent-bit Helm chart."
  type        = string
}

# -----------------------------------------------------------------------------
# 4) Grafana / Zipkin Ingress
# -----------------------------------------------------------------------------

variable "shared_alb" {
  description = "true = app+ops on one ALB. false = public app ALB + shared ops ALB (Grafana/Zipkin/Argo)."
  type        = bool
  default     = false
}

variable "alb_sg_id" {
  description = "App ALB security group ID. Used when shared_alb is true; otherwise Grafana/Zipkin use ops_alb_sg_id."
  type        = string
  default     = ""
}

variable "ops_alb_sg_id" {
  description = "Ops ALB security group ID from the dns module. Required when shared_alb is false and ingress is enabled."
  type        = string
  default     = ""
}

variable "grafana_ingress_enabled" {
  description = "Create a dedicated internet-facing ALB Ingress for Grafana. Alertmanager stays port-forward."
  type        = bool
}

variable "zipkin_ingress_enabled" {
  description = "Create a dedicated internet-facing ALB Ingress for the Zipkin UI. Apps still POST spans in-cluster."
  type        = bool
}

variable "domain_name" {
  description = "Public parent domain. Grafana is grafana-{env}.{domain} in dev and grafana.{domain} in prod."
  type        = string
}

variable "certificate_arn" {
  description = "Wildcard ACM certificate ARN for *.domain. Empty is fine while Grafana and Zipkin ingress flags are false."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the Grafana ALB security group."
  type        = string
}

variable "node_sg_id" {
  description = "EKS node security group ID. Grafana ALB uses :3000; Zipkin ALB uses :9411."
  type        = string
}

variable "grafana_ingress_cidrs" {
  description = "CIDRs allowed to reach the Grafana and Zipkin ALBs (typically the same operator /32 as EKS public_access_cidrs)."
  type        = list(string)
}

# -----------------------------------------------------------------------------
# 5) Slack - Alertmanager receiver. URL never in Git.
# -----------------------------------------------------------------------------

variable "slack_webhook_url" {
  description = "Incoming Slack webhook URL. Empty keeps the blackhole receiver. Set in terraform.tfvars (gitignored)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "slack_channel" {
  description = "Slack channel the webhook posts to, including the leading #."
  type        = string
  default     = "#petclinic-alerts"
}

# -----------------------------------------------------------------------------
# 6) Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto resources created by this module. Helm releases carry no AWS tags, so this is here for consistency."
  type        = map(string)
  default     = {}
}
