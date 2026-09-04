# =============================================================================
# terraform/modules/vpc/main.tf
# Purpose: Isolated VPC — public edge (ALB, NAT) and private workloads (EKS, RDS).
#
# Flow: VPC -> public/private subnets -> IGW/NAT -> routes -> S3 gateway endpoint.
#
# Linked: security-groups.tf; called from environments/{dev,prod}/main.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Current region - used for the S3 gateway endpoint service name
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# 2) Locals - name prefix, AZ suffixes for Name tags, NAT count, extra tags
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  az_suffixes       = [for az in var.availability_zones : substr(az, length(az) - 1, 1)]
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 3) VPC - DNS on; Name tag for the isolated network
# -----------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# -----------------------------------------------------------------------------
# 4) Default SG - emptied so workloads never accidentally use it
# -----------------------------------------------------------------------------

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sg-default-unused"
  })
}

# -----------------------------------------------------------------------------
# 5) Internet gateway - public subnet egress/ingress path
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# -----------------------------------------------------------------------------
# 6) Public subnets - ALB/NAT; no auto public IPs; ELB role tags
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name                                         = "${local.name_prefix}-subnet-public-${local.az_suffixes[count.index]}"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  })
}

# -----------------------------------------------------------------------------
# 7) Private subnets - EKS/RDS; internal-ELB role tags
# -----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name                                         = "${local.name_prefix}-subnet-private-${local.az_suffixes[count.index]}"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/internal-elb"            = "1"
  })
}

# -----------------------------------------------------------------------------
# 8) NAT EIPs - one in dev; one per AZ in prod
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-nat-eip-${local.az_suffixes[count.index]}"
  })
}

# -----------------------------------------------------------------------------
# 9) NAT gateways - private subnet egress via public subnets
# -----------------------------------------------------------------------------

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-nat-${local.az_suffixes[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

# -----------------------------------------------------------------------------
# 10) Public route table - shared by all public subnets
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rt-public"
  })
}

# -----------------------------------------------------------------------------
# 11) Public default route - 0.0.0.0/0 via IGW
# -----------------------------------------------------------------------------

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# -----------------------------------------------------------------------------
# 12) Public RT associations - one per public subnet
# -----------------------------------------------------------------------------

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# 13) Private route tables - one per AZ
# -----------------------------------------------------------------------------

resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rt-private-${local.az_suffixes[count.index]}"
  })
}

# -----------------------------------------------------------------------------
# 14) Private default routes - shared NAT in dev; per-AZ NAT in prod
# -----------------------------------------------------------------------------

resource "aws_route" "private_nat" {
  count = length(aws_route_table.private)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
}

# -----------------------------------------------------------------------------
# 15) Private RT associations - one per private subnet
# -----------------------------------------------------------------------------

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# -----------------------------------------------------------------------------
# 16) S3 gateway endpoint - private RTs so ECR layers skip NAT
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-s3"
  })
}
