# =============================================================================
# terraform/modules/dns/variables.tf
# Purpose: Inputs for the DNS module.
#
# Linked: environments/{dev,prod}/main.tf module.dns.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Identity - used in role names and the derived FQDN
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
# 2) Domain - one zone and one wildcard certificate, shared by both envs
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Public parent domain that owns the hosted zone, e.g. example.com."
  type        = string
}

variable "create_hosted_zone" {
  description = "Create the public hosted zone instead of looking it up. True in at most one environment; prod always looks up."
  type        = bool
  default     = false
}

variable "create_acm_certificate" {
  description = "Issue the *.{domain} wildcard certificate. True in at most one environment (typically dev); the other looks it up. Issuing from both states collides on the validation record."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# 3) Cluster wiring - from the vpc and eks modules
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID the Load Balancer Controller manages load balancers in."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name the Load Balancer Controller targets."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN, used as the federated principal in both IRSA trust policies."
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL, used to build the IRSA trust policy condition keys."
  type        = string
}

# -----------------------------------------------------------------------------
# 4) Cluster add-ons - gated the same way as install_eso
# -----------------------------------------------------------------------------

variable "install_lb_controller" {
  description = "Install the AWS Load Balancer Controller with Helm. False skips the release so a root with no cluster can still plan."
  type        = bool
}

variable "lb_controller_chart_version" {
  description = "Version of the aws-load-balancer-controller Helm chart. Pinned, never 'latest'."
  type        = string
}

variable "install_external_dns" {
  description = "Install ExternalDNS with Helm. False skips the release so a root with no cluster can still plan."
  type        = bool
}

variable "external_dns_chart_version" {
  description = "Version of the external-dns Helm chart. Pinned, never 'latest'."
  type        = string
}

# -----------------------------------------------------------------------------
# 5) Argo CD / ops ALB - ops SG when shared_alb is false; else app ALB
# -----------------------------------------------------------------------------

variable "shared_alb" {
  description = "true = app+ops on one ALB. false = public app ALB + shared ops ALB."
  type        = bool
  default     = false
}

variable "argocd_ingress_enabled" {
  description = "Create the dedicated Argo CD ALB security group. Ingress YAML is k8s/argocd/ingress/{env}.yaml."
  type        = bool
}

variable "node_sg_id" {
  description = "EKS node security group ID. Argo CD ALB health checks and traffic land on container port 8080."
  type        = string
}

variable "argocd_ingress_cidrs" {
  description = "CIDRs allowed to reach the Argo CD ALB (typically the same operator /32 as EKS public_access_cidrs)."
  type        = list(string)
}

# -----------------------------------------------------------------------------
# 6) Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto resources created by this module."
  type        = map(string)
  default     = {}
}
