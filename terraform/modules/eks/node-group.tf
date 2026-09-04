# =============================================================================
# terraform/modules/eks/node-group.tf
# Purpose: Managed node group — node IAM, launch template, node group.
#
# Flow: Node role + launch template -> managed node group in private subnets.
#
# Linked: main.tf cluster; vpc private subnets / node SG.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Node assume-role policy - ec2.amazonaws.com may assume the role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 2) Node IAM role - EC2 instances assume this
# -----------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-node-role"
  })
}

# -----------------------------------------------------------------------------
# 3) Node policy attachments - worker, CNI, and ECR read-only
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# 4) Launch template - custom node SG, IMDSv2, encrypted gp3 root volume
# -----------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name = "${local.name_prefix}-eks-node"
  vpc_security_group_ids = [
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    var.node_sg_id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name = "${local.name_prefix}-eks-node"
    })
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-node"
  })
}

# -----------------------------------------------------------------------------
# 5) Managed node group - ARM ON_DEMAND in private subnets; CBD on replace
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  cluster_name           = aws_eks_cluster.this.name
  node_group_name_prefix = "${local.name_prefix}-nodes-"
  node_role_arn          = aws_iam_role.node.arn
  subnet_ids             = var.subnet_ids
  version                = aws_eks_cluster.this.version
  instance_types         = var.node_instance_types
  ami_type               = var.node_ami_type
  capacity_type          = "ON_DEMAND"

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-nodes"
  })

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}
