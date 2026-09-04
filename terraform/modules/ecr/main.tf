# =============================================================================
# terraform/modules/ecr/main.tf
# Purpose: One private ECR repo per microservice under petclinic-{env}/.
#
# Flow: service_names -> repository (scan on push) -> lifecycle policy.
#
# Linked: github-oidc (CI push), eks node role (pull), helm-values image.registry;
# called from environments/{dev,prod}/main.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Locals - naming, tags, lifecycle (untagged 7d then keep last 10 tagged)
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = var.tags

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# 2) Repositories - one per service, scanned on push, AES256
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = toset(var.service_names)

  name                 = "${local.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}/${each.value}"
    Service = each.value
  })
}

# -----------------------------------------------------------------------------
# 3) Lifecycle policies - bound storage and cost per repository
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy     = local.lifecycle_policy
}
