---
paths:
  - "terraform/modules/karpenter/**"
  - "k8s/karpenter/**"
---

# Karpenter rules (E-14)

Extra nodes when pods are Pending. Does **not** replace the managed node group.

## Split

| Piece | Where |
|-------|--------|
| IAM, SQS, EventBridge, instance profile, Helm | `terraform/modules/karpenter/` |
| Metrics Server add-on | `terraform/modules/eks/addons.tf` (PETPLAT-72) |
| NodePool / EC2NodeClass | `k8s/karpenter/{dev,prod}/` |
| Budgets | `terraform/environments/{env}/` (PETPLAT-75) |

Claude: `terraform validate` and `helm template` / `helm lint` only. Operator applies.

## Install

- `helm_release` gated by `install_karpenter` (same idea as `install_eso`)
- Charts: OCI `oci://public.ecr.aws/karpenter/karpenter-crd` **1.14.0**, then `karpenter` **1.14.0**
- Namespace **`karpenter`** (`create_namespace = true`). Do **not** add it to ArgoCD AppProjects
- Helm: `settings.clusterName` = cluster name; `settings.interruptionQueue` = SQS queue **name**
- Do **not** `helm upgrade --install` from the CLI
- Do **not** `kubernetes_manifest` NodePool/EC2NodeClass in the same apply as the CRD chart
- Do **not** change managed node group min/desired (stay 2)

## IAM

- Controller role `petclinic-{env}-karpenter-role`, SA `karpenter` in `karpenter`
- Vendor official Karpenter **1.14** controller policy JSON. Do **not** use `ec2:*`. Do **not** rewrite it to “fix” Checkov — skip like the LB controller
- Instance profile `petclinic-{env}-karpenter-node-profile` on **existing** `module.eks.node_role_arn`. No second node role. No `aws-auth`

## NodePool / EC2NodeClass

This Claude build: **`capacity-type: ["on-demand"]` only.** PETPLAT-74 (spot) is parked.

Selectors that match this VPC:

- Subnets: `kubernetes.io/role/internal-elb: "1"` **and** `kubernetes.io/cluster/petclinic-{env}: "shared"` (private only; public subnets also have the cluster tag)
- SG tag `Name: petclinic-{env}-sg-eks-node` (not `…-node-sg`)
- `amiSelectorTerms: alias: al2023@latest` is Karpenter’s AMI alias — allowed (not the EKS add-on string `latest`)
- Instance types `t4g.small` / `t4g.medium` on the **NodePool**, not on EC2NodeClass

`petclinic-dev` ResourceQuota is 4 CPU / 4Gi. Scale tests must not use that namespace.

## Forbidden

- Shrinking or deleting the managed node group
- Spot in this build
- A second NodePool or `weight` to prefer spot
- ArgoCD Applications for Karpenter
- Live `kubectl top`, pause-pod scale-up, or k6 (PETPLAT-102)
- Committing `budget_notification_email`
