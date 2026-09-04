# =============================================================================
# terraform/modules/dns/ops-alb.tf
# Purpose: Shared ops ALB SG (Grafana + Zipkin + Argo) when shared_alb is false.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Ops ALB security group - CIDR-locked edge for Grafana, Zipkin, Argo CD
# -----------------------------------------------------------------------------

resource "aws_security_group" "ops_alb" {
  count = local.ops_alb_active ? 1 : 0

  name        = "${local.name_prefix}-sg-ops-alb"
  description = "Ops ALB - Grafana, Zipkin, Argo CD (CIDR-locked)"
  vpc_id      = var.vpc_id

  egress = []

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sg-ops-alb"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [egress]
  }
}

# -----------------------------------------------------------------------------
# 2) Ops ALB ingress - HTTP 80 from operator CIDRs
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "ops_alb_http" {
  for_each = local.ops_alb_active ? toset(var.argocd_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.ops_alb[0].id
  description       = "HTTP from operator CIDR"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# -----------------------------------------------------------------------------
# 3) Ops ALB ingress - HTTPS 443 from operator CIDRs
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "ops_alb_https" {
  for_each = local.ops_alb_active ? toset(var.argocd_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.ops_alb[0].id
  description       = "HTTPS from operator CIDR"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# -----------------------------------------------------------------------------
# 4) Ops ALB egress - Grafana pods on node port 3000
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "ops_alb_to_grafana" {
  count = local.ops_alb_active ? 1 : 0

  security_group_id            = aws_security_group.ops_alb[0].id
  description                  = "Grafana pods"
  referenced_security_group_id = var.node_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

# -----------------------------------------------------------------------------
# 5) Ops ALB egress - Zipkin pods on node port 9411
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "ops_alb_to_zipkin" {
  count = local.ops_alb_active ? 1 : 0

  security_group_id            = aws_security_group.ops_alb[0].id
  description                  = "Zipkin pods"
  referenced_security_group_id = var.node_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 9411
  to_port                      = 9411
}

# -----------------------------------------------------------------------------
# 6) Ops ALB egress - Argo CD server pods on node port 8080
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "ops_alb_to_argocd" {
  count = local.ops_alb_active ? 1 : 0

  security_group_id            = aws_security_group.ops_alb[0].id
  description                  = "argocd-server pods"
  referenced_security_group_id = var.node_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

# -----------------------------------------------------------------------------
# 7) Node ingress - Grafana from the ops ALB
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_grafana_from_ops_alb" {
  count = local.ops_alb_active ? 1 : 0

  security_group_id            = var.node_sg_id
  description                  = "Grafana from the ops ALB"
  referenced_security_group_id = aws_security_group.ops_alb[0].id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

# -----------------------------------------------------------------------------
# 8) Node ingress - Zipkin from the ops ALB
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_zipkin_from_ops_alb" {
  count = local.ops_alb_active ? 1 : 0

  security_group_id            = var.node_sg_id
  description                  = "Zipkin from the ops ALB"
  referenced_security_group_id = aws_security_group.ops_alb[0].id
  ip_protocol                  = "tcp"
  from_port                    = 9411
  to_port                      = 9411
}

# -----------------------------------------------------------------------------
# 9) Node ingress - Argo CD from the ops ALB
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_argocd_from_ops_alb" {
  count = local.ops_alb_active ? 1 : 0

  security_group_id            = var.node_sg_id
  description                  = "Argo CD from the ops ALB"
  referenced_security_group_id = aws_security_group.ops_alb[0].id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}
