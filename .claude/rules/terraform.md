---
paths:
  - "terraform/**/*.tf"
  - "terraform/**/*.tfvars"
---

# Terraform Rules

## Module Structure

Every module directory MUST contain:
- `main.tf` — resource definitions
- `variables.tf` — input variables with descriptions and types
- `outputs.tf` — exported values (IDs, ARNs, endpoints)
- `versions.tf` — required_providers block with version constraints

Environment root modules (`terraform/environments/{env}/`) additionally have:
- `backend.tf` — full S3 backend configuration (including bucket). No `backend.hcl` or `backend.hcl.example`.
- `terraform.tfvars` — MUST set `aws_region`, `environment`, and `project` for that env (do NOT commit secrets). No `terraform.tfvars.example`.

## Naming Conventions

- Resource names: `petclinic-{env}-{resource}` (e.g., `petclinic-dev-vpc`)
- Exception: GitHub Actions OIDC role is account-scoped `petclinic-github-actions-role` (module `github-oidc`, **dev root only** — do not add it to prod)
- DNS: do not create the same public hosted zone from both env roots. Do not `aws_route53_record` alias to an ALB (ExternalDNS does that). LB controller + ExternalDNS use gated `helm_release` like ESO.
- Observability: `helm_release` in `terraform/modules/observability/`, gated by `install_observability` (same as `install_eso`). Grafana password is `random_password` + sensitive output — never Git. No CloudWatch log groups.
- Karpenter: `helm_release` in `terraform/modules/karpenter/`, gated by `install_karpenter`. Charts **1.14.0** (`karpenter-crd` then `karpenter`). Namespace `karpenter`, not ArgoCD. On-demand only. Reuse `module.eks.node_role_arn`. Follow `.claude/rules/karpenter.md`.
- EBS CSI: add-ons + IRSA + gp3 StorageClass live in `terraform/modules/eks/`, gated by `install_ebs_csi`. Addon versions from `data.aws_eks_addon_version` (`most_recent`), never the string `latest`. Include `metrics-server` on that gate (PETPLAT-72).
- VPC CNI: `enableNetworkPolicy = "true"` on the `vpc-cni` add-on (same gate). Do not install Calico. Do not rewrite the vendored LB controller IAM JSON.
- Terraform resource identifiers: snake_case (e.g., `aws_vpc.main`, `aws_subnet.private`)
- Variable names: snake_case, descriptive (e.g., `vpc_cidr_block`, `eks_node_instance_type`)
- Output names: snake_case, prefixed by resource type (e.g., `vpc_id`, `eks_cluster_endpoint`)

## Required Tags

Every AWS resource that supports tags MUST include:

```hcl
tags = {
  Project     = "petclinic"
  Environment = var.environment
  ManagedBy   = "terraform"
}
```

## Variable Conventions

- Always include `description` and `type`
- Use `validation` blocks for constrained values (e.g., environment must be "dev" or "prod")
- Use `sensitive = true` for any secret values
- Root module: no defaults for `aws_region`, `environment`, or `project` — those come from `terraform.tfvars`
- Modules: no `default = "petclinic"`; the root module passes `var.project`
- Do not add files the story did not ask for (`*.example`, `backend.hcl`)

## Security Requirements

- No inline credentials or hardcoded secrets — use `data "aws_secretsmanager_secret_version"`
- No public S3 buckets — always include `aws_s3_bucket_public_access_block`
- **No wildcard IAM** — use specific actions and resource ARNs. Exception: vendored official controller JSON (LB controller, Karpenter 1.14) is skipped in Checkov, not hand-narrowed.
- Encrypt all storage — RDS, S3, EBS must have encryption enabled
- Private subnets + NAT — ALB in public subnets; EKS and RDS in private. **1 NAT in dev, NAT per AZ in prod.** SGs least-privilege (see ADR-0001)
- Security groups: deny-all default, allow only required ports

## State Management

- Backend: S3 bucket with versioning + DynamoDB for locking
- State key pattern: `petclinic/{env}/terraform.tfstate`
- Never store state locally in production
- Use `terraform_remote_state` data source for cross-module references

## Workflow

1. `terraform fmt -recursive` — format before committing
2. `terraform validate` — syntax check after every edit
3. `terraform plan -out plan.out` — always save the plan
4. Review the plan — check resource counts, changes, deletions
5. `terraform apply plan.out` — apply the saved plan only
