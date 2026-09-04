# =============================================================================
# terraform/modules/vpc/security-groups.tf
# Purpose: Baseline SGs — ALB, EKS cluster, EKS nodes, RDS.
#
# Flow: ALB accepts HTTPS from operator CIDRs; nodes accept app traffic from ALB;
# RDS accepts 3306 from nodes only. egress = [] on these SGs.
#
# Linked: main.tf VPC/subnets; eks, rds, dns, observability modules.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) ALB SG - clear default egress; ignore_changes keeps separate rules intact
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "ALB - public 80/443, forwards to api-gateway pods"
  vpc_id      = aws_vpc.this.id

  egress = []

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sg-alb"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes = [egress]
  }
}

# -----------------------------------------------------------------------------
# 2) EKS cluster SG - control plane; rules attached below
# -----------------------------------------------------------------------------

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-sg-eks-cluster"
  description = "EKS control plane - API from worker nodes"
  vpc_id      = aws_vpc.this.id

  egress = []

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sg-eks-cluster"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [egress]
  }
}

# -----------------------------------------------------------------------------
# 3) EKS node SG - workers; rules attached below
# -----------------------------------------------------------------------------

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-sg-eks-node"
  description = "EKS workers - control plane, inter-node, ALB"
  vpc_id      = aws_vpc.this.id

  egress = []

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sg-eks-node"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [egress]
  }
}

# -----------------------------------------------------------------------------
# 4) RDS SG - MySQL from nodes only; no egress
# -----------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-sg-rds"
  description = "RDS MySQL - 3306 from EKS nodes only, no egress"
  vpc_id      = aws_vpc.this.id

  egress = []

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sg-rds"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [egress]
  }
}

# -----------------------------------------------------------------------------
# 5) ALB ingress HTTP - port 80 from the internet
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# -----------------------------------------------------------------------------
# 6) ALB ingress HTTPS - port 443 from the internet
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# -----------------------------------------------------------------------------
# 7) ALB egress to gateway - api-gateway/argocd pods on :8080
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "alb_to_gateway" {
  security_group_id            = aws_security_group.alb.id
  description                  = "api-gateway / argocd-server pods (target-type ip)"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

# -----------------------------------------------------------------------------
# 8) ALB egress to Grafana - pods on :3000 via shared ALB
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "alb_to_grafana" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Grafana pods (shared ALB)"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

# -----------------------------------------------------------------------------
# 9) ALB egress to Zipkin - pods on :9411 via shared ALB
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "alb_to_zipkin" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Zipkin pods (shared ALB)"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 9411
  to_port                      = 9411
}

# -----------------------------------------------------------------------------
# 10) Cluster ingress - Kubernetes API :443 from worker nodes
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "cluster_from_node_api" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Kubernetes API from worker nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# -----------------------------------------------------------------------------
# 11) Cluster egress - control plane outbound allow-all
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Control plane outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# 12) Node ingress from cluster - all traffic from the control plane
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "All traffic from the control plane"
  referenced_security_group_id = aws_security_group.eks_cluster.id
  ip_protocol                  = "-1"
}

# -----------------------------------------------------------------------------
# 13) Node ingress from self - inter-node communication
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_from_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Inter-node communication"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "-1"
}

# -----------------------------------------------------------------------------
# 14) Node ingress from ALB - api-gateway/argocd on :8080
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_gateway_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "api-gateway / argocd-server from the shared app ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

# -----------------------------------------------------------------------------
# 15) Node ingress from ALB - Grafana on :3000
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_grafana_from_shared_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Grafana from the shared app ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

# -----------------------------------------------------------------------------
# 16) Node ingress from ALB - Zipkin on :9411
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_zipkin_from_shared_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Zipkin from the shared app ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 9411
  to_port                      = 9411
}

# -----------------------------------------------------------------------------
# 17) Node egress - outbound allow-all via NAT
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "Node outbound via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# 18) RDS ingress - MySQL :3306 from EKS nodes only
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_node" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from EKS nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}
