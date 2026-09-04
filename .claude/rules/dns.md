---
paths:
  - "terraform/modules/dns/**"
---

# DNS module rules (E-6)

Route 53 + ACM + AWS Load Balancer Controller + ExternalDNS. Not ALB alias records in Terraform.

## Split

| Piece | Where |
|-------|--------|
| Zone lookup / optional create, ACM, IRSA, `helm_release` | this module |
| Ingress YAML | Helm (`helm/petclinic-service/templates/ingress.yaml`) — see `helm.md` |
| ALB A-record | **ExternalDNS**, after Ingress sync |

Claude: `terraform validate` only. Operator applies.

## Hosted zone

- Default: `data.aws_route53_zone` public, `name = var.domain_name`
- `create_hosted_zone` true in **at most one** env (prod wiring is always lookup)
- ACM: **one** wildcard `*.{domain}`. `create_acm_certificate` true in **at most one** env (typically dev). Prod looks up the ISSUED cert. Do not issue the wildcard from both roots.
- Ingress FQDN: `petclinic-dev.{domain}` (dev) / `petclinic.{domain}` (prod) — covered by the wildcard, not the cert CN

## Helm releases

Same gate as ESO: `count = var.install_* ? 1 : 0`. Cluster must already exist.

- LB controller: chart **3.5.0**, repo `https://aws.github.io/eks-charts`, ns `kube-system`, IngressClass `alb`
- ExternalDNS: chart **1.21.1**, repo `https://kubernetes-sigs.github.io/external-dns/`, ns `kube-system`, source `ingress` only, `txtOwnerId` = `petclinic-{env}`, policy `upsert-only`

IAM for the LB controller is the official JSON from tag `v3.5.0`, vendored unmodified. Not an AWS-managed policy.

## Forbidden

- `aws_route53_record` alias to an ALB / `data.aws_lb`
- `helm install` / `kubectl apply` from this story
- NetworkPolicy (E-13)
- `k8s/base/ingress/`
