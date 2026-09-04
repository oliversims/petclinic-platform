# =============================================================================
# terraform/environments/dev/providers.tf
# Purpose: AWS, Helm, and Kubernetes providers; default_tags for Project/Env.
#
# Linked: versions.tf; main.tf modules inherit default_tags.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) AWS - default_tags apply to every taggable resource
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# -----------------------------------------------------------------------------
# 2) Helm - EKS auth via aws eks get-token (no kubeconfig or long-lived creds)
# -----------------------------------------------------------------------------

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

# -----------------------------------------------------------------------------
# 3) Kubernetes - gp3 StorageClass and Grafana dashboards; same exec auth as Helm
# -----------------------------------------------------------------------------

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}
