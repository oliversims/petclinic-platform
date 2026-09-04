# =============================================================================
# terraform/modules/dns/main.tf
# Purpose: Hosted zone lookup/create, wildcard ACM cert, derived FQDNs.
#
# Flow: domain_name -> zone + *.{domain} cert. FQDNs: petclinic[-env].{domain},
# argocd[-env].{domain}. ExternalDNS and LB controller are sibling files.
#
# Linked: external-dns.tf, lb-controller.tf, ops-alb.tf;
# called from environments/{dev,prod}/main.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Current region - used by LB Controller and ExternalDNS Helm values
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# 2) Locals - naming, FQDNs, zone/cert selection, shared vs ops ALB flags
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  oidc_provider_host = replace(var.oidc_provider_url, "https://", "")

  fqdn = var.environment == "prod" ? "${var.project}.${var.domain_name}" : "${var.project}-${var.environment}.${var.domain_name}"

  wildcard_domain = "*.${var.domain_name}"

  argocd_host = var.environment == "prod" ? "argocd.${var.domain_name}" : "argocd-${var.environment}.${var.domain_name}"
  argocd_url  = "https://${local.argocd_host}"

  argocd_ingress_active = var.argocd_ingress_enabled && var.install_lb_controller
  ops_alb_active        = !var.shared_alb && var.install_lb_controller

  zone_id         = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.this[0].zone_id
  zone_arn        = "arn:aws:route53:::hostedzone/${local.zone_id}"
  certificate_arn = var.create_acm_certificate ? aws_acm_certificate_validation.this[0].certificate_arn : data.aws_acm_certificate.this[0].arn

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 3) Hosted zone lookup - used when create_hosted_zone is false
# -----------------------------------------------------------------------------

data "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 0 : 1

  name         = var.domain_name
  private_zone = false
}

# -----------------------------------------------------------------------------
# 4) Hosted zone create - used when create_hosted_zone is true (at most one env)
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0

  name    = var.domain_name
  comment = "Public zone for ${var.project}"

  tags = merge(local.tags, {
    Name = var.domain_name
  })
}

# -----------------------------------------------------------------------------
# 5) Wildcard ACM certificate - issued in one environment only
# -----------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  count = var.create_acm_certificate ? 1 : 0

  domain_name       = local.wildcard_domain
  validation_method = "DNS"

  tags = merge(local.tags, {
    Name = "wildcard.${var.domain_name}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 6) DNS validation records - CNAMEs for the wildcard certificate
# -----------------------------------------------------------------------------

resource "aws_route53_record" "certificate_validation" {
  for_each = var.create_acm_certificate ? {
    for option in aws_acm_certificate.this[0].domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# -----------------------------------------------------------------------------
# 7) Certificate validation wait - hangs if the zone is not delegated yet
# -----------------------------------------------------------------------------

resource "aws_acm_certificate_validation" "this" {
  count = var.create_acm_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

# -----------------------------------------------------------------------------
# 8) Wildcard certificate lookup - used when the other env issued the cert
# -----------------------------------------------------------------------------

data "aws_acm_certificate" "this" {
  count = var.create_acm_certificate ? 0 : 1

  domain      = local.wildcard_domain
  statuses    = ["ISSUED"]
  most_recent = true
}
