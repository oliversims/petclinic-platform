---
paths:
  - "k8s/security/**"
  - "terraform/modules/eks/**"
  - ".checkov.yml"
  - ".github/workflows/checkov.yml"
---

# Security rules (E-13)

NetworkPolicies, quotas, VPC CNI policy agent, Checkov. Not Calico. Not CloudTrail.

## Split

| Piece | Where |
|-------|--------|
| VPC CNI `enableNetworkPolicy` | `terraform/modules/eks/` (`vpc-cni` add-on, same gate as `install_ebs_csi`) |
| NetworkPolicies, ResourceQuota, LimitRange | `k8s/security/{dev,prod}/` |
| Checkov skips | `.checkov.yml` |
| Checkov CI | `.github/workflows/checkov.yml` |

Claude: `terraform validate` and `kubectl apply --dry-run=client` only. Operator applies.

## NetworkPolicy

- Only `petclinic-{env}`. Never `monitoring` or `tracing`
- Default deny **ingress** only — do not default-deny egress
- Gateway 8080 from **VPC CIDR** (ALB `target-type: ip`) plus namespace `monitoring`
- Domain services: from API Gateway pods plus `monitoring`
- Admin 9090: from the same namespace plus `monitoring`
- Config 8888 / Discovery 8761: from the same namespace
- Do not add these namespaces to ArgoCD AppProjects

## Quotas

Dev 4 CPU / 4Gi / 40 pods. Prod 6 CPU / 6Gi / 50 pods. LimitRange defaults = Helm chart (`100m`/`128Mi`, `500m`/`512Mi`).

## Forbidden

- Calico / Cilium
- Rewriting AWS managed IAM policies or the vendored LB controller / Karpenter 1.14 controller JSON
- Narrowing the node SG self-all rule
- PSA / SecurityContext / Trivy / ECR scan-on-push (already done)
- `docs/compliance-checklist.md` (E-15 / PETPLAT-100)
- Live apply, “pods still start”, ECR console CVE review
