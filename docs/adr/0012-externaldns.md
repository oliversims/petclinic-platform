# ADR-0012: ExternalDNS for ALB hostnames

**Status:** Accepted
**Date:** 2026-09-02

## Context
The application needs a public hostname for each environment — `petclinic-dev.{domain}`
in dev and `petclinic.{domain}` in prod — to resolve to its load balancer. The
natural Terraform approach is an `aws_route53_record` alias pointing at the ALB.

That cannot work on a first apply. The ALB does not exist until the AWS Load Balancer
Controller sees an Ingress, which happens after the cluster is up and ArgoCD has synced —
well after Terraform has finished. Terraform would have to look up a load balancer that
does not exist yet.

## Decision
Terraform owns the hosted zone lookup and the wildcard ACM certificate. ExternalDNS,
running in-cluster, watches Ingress resources and writes the Route 53 alias once the ALB
exists.

- No `aws_route53_record` alias to an ALB, and no `data.aws_lb`, anywhere in Terraform.
- ExternalDNS is scoped by `domainFilters` to the one domain, uses `txtOwnerId` per
  environment, and runs `policy: upsert-only` so it never deletes a record it did not
  create.
- Its IRSA role can change records in exactly one hosted zone.

## Consequences
**Positive**

- Breaks the chicken-and-egg cycle: the record is written when there is something to point
  it at.
- The Ingress host is the single source of truth for the hostname.
- A rebuilt ALB updates DNS automatically, with no Terraform run.
- `upsert-only` and `txtOwnerId` make it safe to share one hosted zone between two
  clusters.

**Negative**

- DNS is no longer fully described in Terraform; reading the code does not tell you the
  whole record set.
- Another controller in the cluster, with its own IAM role and failure modes.
- A propagation delay after the Ingress syncs — the hostname does not resolve instantly.
- If ExternalDNS is broken or uninstalled, records go stale silently rather than failing
  loudly.

