# =============================================================================
# terraform/environments/prod/main.tf
# Purpose: Prod root — wires every module for the petclinic prod stack.
#
# Flow: vpc (NAT per AZ) -> ecr/rds/eks/secrets/github-oidc ->
# dns/karpenter/observability (Helm add-ons gated by install_*).
#
# Linked: sibling backend/providers/variables/outputs/budget.tf; modules/*.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Locals - common_tags for default_tags in providers.tf
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# 2) VPC - public ALB/NAT, private EKS/RDS, NAT per AZ (10.1.0.0/16)
# -----------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  single_nat_gateway   = var.single_nat_gateway

  tags = {
    Component = "networking"
  }
}

# -----------------------------------------------------------------------------
# 3) EKS - petclinic-prod cluster, three t4g.medium nodes (one per AZ)
# -----------------------------------------------------------------------------

module "eks" {
  source = "../../modules/eks"

  project             = var.project
  environment         = var.environment
  cluster_version     = var.cluster_version
  subnet_ids          = module.vpc.private_subnet_ids
  cluster_sg_id       = module.vpc.eks_cluster_sg_id
  node_sg_id          = module.vpc.eks_node_sg_id
  public_access_cidrs = var.public_access_cidrs
  node_instance_types = var.node_instance_types
  node_ami_type       = var.node_ami_type
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
  node_disk_size      = var.node_disk_size
  install_ebs_csi     = var.install_ebs_csi

  tags = {
    Component = "compute"
  }
}

# -----------------------------------------------------------------------------
# 4) ECR - one private repository per microservice
# -----------------------------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  project              = var.project
  environment          = var.environment
  service_names        = var.service_names
  image_tag_mutability = var.image_tag_mutability

  tags = {
    Component = "registry"
  }
}

# -----------------------------------------------------------------------------
# 5) Caller identity - account ID for ECR image URLs in root outputs
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# 6) RDS - MySQL for customers/vets/visits, credentials in Secrets Manager
# -----------------------------------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  project                 = var.project
  environment             = var.environment
  subnet_ids              = module.vpc.private_subnet_ids
  security_group_id       = module.vpc.rds_sg_id
  engine_version          = var.rds_engine_version
  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage
  max_allocated_storage   = var.rds_max_allocated_storage
  multi_az                = var.rds_multi_az
  backup_retention_period = var.rds_backup_retention_period
  skip_final_snapshot     = var.rds_skip_final_snapshot
  deletion_protection     = var.rds_deletion_protection

  tags = {
    Component = "database"
  }
}

# -----------------------------------------------------------------------------
# 7) Secrets - OpenAI key and ESO IRSA role
# -----------------------------------------------------------------------------

module "secrets" {
  source = "../../modules/secrets"

  project           = var.project
  environment       = var.environment
  openai_api_key    = var.openai_api_key
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  install_eso       = var.install_eso
  eso_chart_version = var.eso_chart_version

  tags = {
    Component = "secrets"
  }
}

# -----------------------------------------------------------------------------
# 8) GitHub Actions OIDC - account-scoped role lives in the dev root only
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 9) DNS and Ingress - zone, ACM, ALB controller, ExternalDNS (ADR-0012)
# -----------------------------------------------------------------------------

module "dns" {
  source = "../../modules/dns"

  project                     = var.project
  environment                 = var.environment
  domain_name                 = var.domain_name
  create_hosted_zone          = var.create_hosted_zone
  create_acm_certificate      = var.create_acm_certificate
  vpc_id                      = module.vpc.vpc_id
  cluster_name                = module.eks.cluster_name
  oidc_provider_arn           = module.eks.oidc_provider_arn
  oidc_provider_url           = module.eks.oidc_provider_url
  install_lb_controller       = var.install_lb_controller
  lb_controller_chart_version = var.lb_controller_chart_version
  install_external_dns        = var.install_external_dns
  external_dns_chart_version  = var.external_dns_chart_version
  argocd_ingress_enabled      = var.argocd_ingress_enabled
  shared_alb                  = var.shared_alb
  node_sg_id                  = module.vpc.eks_node_sg_id
  argocd_ingress_cidrs        = var.public_access_cidrs

  tags = {
    Component = "dns"
  }
}

# -----------------------------------------------------------------------------
# 10) Observability - in-cluster metrics/logs/traces; Grafana/Zipkin HTTPS
# -----------------------------------------------------------------------------

module "observability" {
  source = "../../modules/observability"

  project                             = var.project
  environment                         = var.environment
  install_observability               = var.install_observability
  install_lb_controller               = var.install_lb_controller
  kube_prometheus_stack_chart_version = var.kube_prometheus_stack_chart_version
  loki_chart_version                  = var.loki_chart_version
  fluent_bit_chart_version            = var.fluent_bit_chart_version
  grafana_ingress_enabled             = var.grafana_ingress_enabled
  zipkin_ingress_enabled              = var.zipkin_ingress_enabled
  shared_alb                          = var.shared_alb
  alb_sg_id                           = module.vpc.alb_sg_id
  ops_alb_sg_id                       = module.dns.ops_alb_sg_id
  domain_name                         = var.domain_name
  certificate_arn                     = module.dns.certificate_arn
  vpc_id                              = module.vpc.vpc_id
  node_sg_id                          = module.vpc.eks_node_sg_id
  grafana_ingress_cidrs               = var.public_access_cidrs
  slack_webhook_url                   = var.slack_webhook_url
  slack_channel                       = var.slack_channel

  tags = {
    Component = "observability"
  }

  depends_on = [module.eks, module.dns]
}

# -----------------------------------------------------------------------------
# 11) Karpenter - extra nodes on Pending; NodePool/EC2NodeClass are operator YAML
# -----------------------------------------------------------------------------

module "karpenter" {
  source = "../../modules/karpenter"

  project                 = var.project
  environment             = var.environment
  cluster_name            = module.eks.cluster_name
  cluster_endpoint        = module.eks.cluster_endpoint
  node_role_arn           = module.eks.node_role_arn
  oidc_provider_arn       = module.eks.oidc_provider_arn
  oidc_provider_url       = module.eks.oidc_provider_url
  install_karpenter       = var.install_karpenter
  karpenter_chart_version = var.karpenter_chart_version

  tags = {
    Component = "scaling"
  }

  depends_on = [module.eks]
}
