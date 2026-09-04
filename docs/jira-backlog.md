# Jira Backlog — Petclinic Platform

**Project Key:** PETPLAT (suggested)
**Board:** Kanban or Scrum
**Workflow:** Backlog → To Do → In Progress → In Review → Done

---

## Epics Overview

| Epic # | Epic | Priority | Stories |
|--------|------|----------|---------|
| E-0 | Claude Code Setup | P0 | 5 |
| E-1 | Foundation & Remote State | P0 | 5 |
| E-2 | Networking (VPC) | P0 | 5 |
| E-3 | EKS Cluster | P0 | 7 |
| E-4 | Container Registry (ECR) | P0 | 6 |
| E-5 | Database (RDS MySQL) | P0 | 6 |
| E-6 | DNS & Ingress | P1 | 6 |
| E-7 | Secrets Management (Secrets Manager) | P0 | 6 |
| E-8 | Kubernetes Manifests — Base | P0 | 8 |
| E-9 | Kubernetes Manifests — Overlays | P1 | 5 |
| E-10 | CI Pipeline (CI-only, ArgoCD handles CD) | P0 | 5 |
| E-11 | Observability | P1 | 8 |
| ~~E-12~~ | ~~Bastion Host~~ | ~~P2~~ | ~~0 (removed)~~ |
| E-13 | Security & Compliance | P1 | 4 |
| E-14 | Scaling & Cost Optimization (Karpenter) | P2 | 3 |
| E-15 | Documentation & Runbooks | P1 | 8 |
| E-16 | Helm Charts | P0 | 5 |
| E-17 | GitOps with ArgoCD | P0 | 5 |
| | | **Total** | **97** |

---

## Epic Dependencies

```
E-0 (Claude Code Setup) ──→ E-1 (Foundation)
E-1 (Foundation)
 └─→ E-2 (VPC)
      └─→ E-3 (EKS) ──→ E-8 (K8s Base) ──→ E-16 (Helm Charts) ──→ E-10 (CI-only)
      │                    │                    │
      │                    │                    └──→ E-17 (ArgoCD) ──→ E-14 (Scaling/Karpenter)
      │                    │
      └─→ E-5 (RDS) ──┐
      │                │
      (E-12 Bastion — removed)
                       │
 E-4 (ECR) ──────────→│──→ E-10 (CI-only)
                       │
 E-7 (Secrets Mgr) ───→│──→ E-8 (K8s Base)
                       │
 E-11 (Observability) — after E-3 (EBS CSI), Terraform Helm into monitoring/tracing. Not ArgoCD.
 E-6 (DNS/Ingress) — after E-2 (VPC SG/tags), E-3 (EKS), E-16 (Helm Ingress). ExternalDNS writes Route 53.
 E-13 (Security) — after E-3 (CNI) and E-11 (Prometheus scrape). NetworkPolicy in petclinic-{env} only. Not ArgoCD.
 E-14 (Karpenter) — after E-3. Terraform Helm + Git NodePool YAML, not ArgoCD. On-demand only. PETPLAT-74 (spot) and PETPLAT-102 parked.
 E-15 (Docs) — markdown only from spec. No Terraform/Helm/kubectl apply. PETPLAT-90 parked (live destroy).
 E-16 (Helm Charts) — depends on E-8 (base manifests define what gets templated)
 E-10 (CI-only) — depends on E-4 (ECR), E-16 (Helm values are what CI tags)
 E-17 (ArgoCD) — depends on E-3 (EKS), E-7 (ESO), E-8 (namespaces), E-16 (Helm). One ArgoCD per cluster.
```

---

# EPIC E-0: Claude Code Setup

**Priority:** P0
**Description:** Configure Claude Code for the petclinic-platform repo before writing any infrastructure code. This sets up the AI agent's context, safety guardrails, workflows, and tooling so every subsequent task benefits from intelligent assistance.
**Blocked by:** None
**Blocks:** E-1 (all subsequent work uses this configuration)

---

### PETPLAT-001: Configure MCP servers for petclinic-platform

**Type:** Task
**Priority:** P0
**Epic:** E-0 Claude Code Setup
**Story Points:** 2
**Labels:** claude, mcp, foundation
**Blocked by:** None

**Description:**
Create `.mcp.json` at the project root with all MCP servers needed for the infrastructure workflow. These servers give Claude Code access to Terraform docs, AWS knowledge, pricing data, library documentation, and Jira.

**Acceptance Criteria:**
- [ ] `.mcp.json` at petclinic-platform root
- [ ] Terraform MCP server configured (`terraform-mcp-server`, HashiCorp official via Docker)
- [ ] AWS Knowledge MCP configured (`aws-knowledge-mcp`)
- [ ] AWS Pricing MCP configured (`awslabs.aws-pricing-mcp-server`, region: us-east-1)
- [ ] Context7 MCP configured (library documentation)
- [ ] Atlassian MCP configured (Jira ticket management)
- [ ] No secrets stored in `.mcp.json` — credentials come from user's local environment

---

### PETPLAT-002: Create Claude Code safety hooks

**Type:** Task
**Priority:** P0
**Epic:** E-0 Claude Code Setup
**Story Points:** 3
**Labels:** claude, safety, foundation
**Blocked by:** PETPLAT-001

**Description:**
Create safety hook scripts in `.claude/hooks/` and configure them in `.claude/settings.json`. Hooks prevent Claude Code from running dangerous commands (terraform destroy, rm -rf on infra dirs, committing secrets) and warn about risky operations (apply without saved plan). Also add an informational hook that suggests `terraform validate` after editing .tf files.

**Acceptance Criteria:**
- [ ] `.claude/settings.json` with PreToolUse and PostToolUse hook configuration
- [ ] `block-destroy.sh` — blocks `terraform destroy` (exit 2, hard deny)
- [ ] `block-dangerous-rm.sh` — blocks `rm -rf` on terraform/, k8s/, .github/, docs/, scripts/
- [ ] `warn-apply-without-plan.sh` — warns on `terraform apply` without plan.out (exit 1, ask user)
- [ ] `suggest-validate.sh` — suggests `terraform validate` after .tf edits (exit 0, informational)
- [ ] `block-secret-commit.sh` — blocks git add/commit of .env, .tfvars, .pem, credentials files
- [ ] All scripts use `jq` for JSON parsing, include educational comments
- [ ] 3-tier model: block (exit 2) / warn (exit 1) / inform (exit 0)

---

### PETPLAT-003: Create Claude Code rules, agents, and skills

**Type:** Task
**Priority:** P0
**Epic:** E-0 Claude Code Setup
**Story Points:** 5
**Labels:** claude, automation, foundation
**Blocked by:** PETPLAT-82

**Description:**
Create file-pattern rules (`.claude/rules/`), review subagents (`.claude/agents/`), and operational skills (`.claude/skills/`) for the infrastructure workflow.

**Rules** load automatically when editing matching files:
- `terraform.md` — conventions for `terraform/**/*.tf`
- `kubernetes.md` — conventions for `k8s/**/*.yaml`
- `pipelines.md` — conventions for `.github/workflows/**/*.yml`
- `docs.md` — conventions for `docs/**/*.md`

**Agents** are read-only reviewers (no Write/Edit):
- `terraform-reviewer.md` — security, cost, best-practice review
- `k8s-validator.md` — manifest validation with dry-run
- `security-auditor.md` — comprehensive cross-IaC security audit
- `cost-reviewer.md` — AWS cost estimation and optimization
- `doc-reviewer.md` — documentation quality and accuracy review
- `pipeline-reviewer.md` — CI/CD pipeline security and best practices

**Skills** are slash commands for common operations:
- `/terraform-plan [env]` — init + plan (manual only)
- `/terraform-apply [env]` — apply saved plan with confirmation (manual only)
- `/security-scan [module|all]` — Checkov scan (manual only)
- `/deploy-dev [service|all]` — deploy to dev namespace (manual only)
- `/deploy-prod [service|all]` — deploy to prod with extra safety (manual only)
- `/smoke-test [env]` — health check all services (manual only)
- `/logs [service] [env]` — fetch and filter pod logs (manual only)
- `/rollback [service] [env]` — rollback deployment (manual only)
- `/review-terraform [path]` — review against checklist (auto-invocable)

**Acceptance Criteria:**
- [ ] 4 rule files with `paths:` frontmatter for selective loading (terraform, kubernetes, pipelines, docs)
- [ ] 6 agent files — read-only tools only, structured output format
- [ ] 9 skill directories with SKILL.md — 8 manual (`disable-model-invocation: true`), 1 auto-invocable
- [ ] All skills accept arguments (environment or service name)
- [ ] Deploy-prod has extra confirmation step vs deploy-dev
- [ ] Agents report findings in structured format with file:line references

---

### PETPLAT-004: Verify Claude Code configuration end-to-end

**Type:** Task
**Priority:** P0
**Epic:** E-0 Claude Code Setup
**Story Points:** 1
**Labels:** claude, verification
**Blocked by:** PETPLAT-003

**Description:**
Start a new Claude Code session in petclinic-platform/ and verify the full configuration is working: CLAUDE.md loads, MCP servers connect, skills appear, hooks fire, rules activate on file patterns.

**Acceptance Criteria:**
- [ ] CLAUDE.md project conventions visible in Claude's context
- [ ] Type `/` and all 7 skills appear in autocomplete
- [ ] Ask Claude to run `terraform destroy` — blocked by hook
- [ ] Create a test .tf file — terraform rules activate
- [ ] MCP servers respond (test with a Terraform docs search)
- [ ] All files committed to git

---

---

# EPIC E-1: Foundation & Remote State

**Priority:** P0
**Description:** Set up Terraform project structure, remote state backend (S3 + DynamoDB), provider configuration, and environment layout. This is the foundation everything else builds on.
**Blocked by:** None
**Blocks:** E-2, E-3, E-4, E-5, E-6, E-7

---

### PETPLAT-1: Create Terraform project directory structure

**Type:** Task
**Priority:** P0
**Epic:** E-1 Foundation & Remote State
**Story Points:** 2
**Labels:** terraform, foundation

**Description:**
Create the Terraform directory structure in petclinic-platform with separate environment root modules and shared reusable modules.

**Technical Spec:** [General Project Parameters](./technical-spec.md#general-project-parameters), [Terraform Modules](./technical-spec.md#terraform-modules)

**Acceptance Criteria:**
- [ ] `terraform/environments/dev/` directory exists with main.tf, variables.tf, outputs.tf, backend.tf, terraform.tfvars
- [ ] `terraform/environments/prod/` directory exists with same files
- [ ] `terraform/modules/` directory exists with subdirectories: vpc, eks, ecr, rds, dns, secrets, observability
- [ ] Each module dir has placeholder main.tf, variables.tf, outputs.tf
- [ ] .gitignore includes .terraform/, *.tfstate, *.tfstate.backup, *.tfvars (sensitive), plan.out, .env, *.pem, *.key, IDE files, OS files
- [ ] .terraform.lock.hcl is NOT in .gitignore (must be committed for reproducible builds)

---

### PETPLAT-2: Create S3 bucket and DynamoDB table for Terraform state

**Type:** Task
**Priority:** P0
**Epic:** E-1 Foundation & Remote State
**Story Points:** 3
**Labels:** terraform, foundation, aws

**Description:**
Create a bootstrap script that provisions the S3 bucket (versioning enabled, encryption enabled) and DynamoDB table (LockID partition key) used for Terraform remote state. This is a one-time setup done outside Terraform itself.

**Technical Spec:** [Terraform State Backend](./technical-spec.md#terraform-state-backend)

**Acceptance Criteria:**
- [ ] `scripts/bootstrap-state.sh` script created
- [ ] S3 bucket created with versioning enabled
- [ ] S3 bucket has server-side encryption (AES256 or KMS)
- [ ] S3 bucket has public access blocked (all 4 settings)
- [ ] DynamoDB table created with `LockID` as partition key (String)
- [ ] Script is idempotent (safe to run multiple times)
- [ ] Script accepts region as parameter (default: us-east-1)

---

### PETPLAT-3: Configure Terraform backend for dev environment

**Type:** Task
**Priority:** P0
**Epic:** E-1 Foundation & Remote State
**Story Points:** 2
**Labels:** terraform, foundation
**Blocked by:** PETPLAT-2

**Description:**
Configure the S3 backend in `terraform/environments/dev/backend.tf` pointing to the state bucket with key `petclinic/dev/terraform.tfstate`. Configure DynamoDB locking.

**Technical Spec:** [Terraform State Backend](./technical-spec.md#terraform-state-backend)

**Acceptance Criteria:**
- [ ] `backend.tf` configured with S3 backend
- [ ] State key: `petclinic/dev/terraform.tfstate`
- [ ] DynamoDB table referenced for locking
- [ ] Encryption enabled
- [ ] Region set to us-east-1
- [ ] `terraform init` succeeds

---

### PETPLAT-4: Configure Terraform backend for prod environment

**Type:** Task
**Priority:** P0
**Epic:** E-1 Foundation & Remote State
**Story Points:** 1
**Labels:** terraform, foundation
**Blocked by:** PETPLAT-2

**Description:**
Configure the S3 backend in `terraform/environments/prod/backend.tf` with key `petclinic/prod/terraform.tfstate`. Same bucket, different state key.

**Technical Spec:** [Terraform State Backend](./technical-spec.md#terraform-state-backend)

**Acceptance Criteria:**
- [ ] `backend.tf` configured with S3 backend
- [ ] State key: `petclinic/prod/terraform.tfstate`
- [ ] DynamoDB table referenced for locking
- [ ] Encryption enabled
- [ ] `terraform init` succeeds

---

### PETPLAT-5: Configure AWS provider and Terraform versions

**Type:** Task
**Priority:** P0
**Epic:** E-1 Foundation & Remote State
**Story Points:** 2
**Labels:** terraform, foundation

**Description:**
Set up provider configuration and version constraints in both environment root modules. Pin Terraform >= 1.6.0 and AWS provider ~> 5.0.

**Technical Spec:** [General Project Parameters](./technical-spec.md#general-project-parameters)

**Acceptance Criteria:**
- [ ] `versions.tf` in both dev/ and prod/ with required_version >= 1.6.0
- [ ] AWS provider source and version constraint (~> 5.0) defined
- [ ] `providers.tf` in both environments configuring AWS provider with `var.aws_region`
- [ ] `variables.tf` defines aws_region, environment, and project (no defaults)
- [ ] `terraform.tfvars` sets aws_region, environment, and project for that env
- [ ] Common tags defined: Project, Environment, ManagedBy=terraform
- [ ] `terraform validate` passes in both environments

---

# EPIC E-2: Networking (VPC)

**Priority:** P0
**Description:** Build the VPC module with public and private subnets across 2 AZs, Internet Gateway, NAT (1 in dev, 2 in prod), and baseline security groups. Production layout: ALB and NAT in public subnets; EKS nodes and RDS in private subnets (no public IPs). See ADR-0001.
**Blocked by:** E-1
**Blocks:** E-3, E-5, E-6

---

### PETPLAT-6: Create VPC module — VPC, subnets, IGW, NAT

**Type:** Story
**Priority:** P0
**Epic:** E-2 Networking
**Story Points:** 8
**Labels:** terraform, networking, vpc
**Blocked by:** PETPLAT-5

**Description:**
Create a reusable VPC module in `terraform/modules/vpc/` that provisions a production-style network:

**Technical Spec:** [VPC Network Design](./technical-spec.md#vpc-network-design), [Terraform Modules](./technical-spec.md#terraform-modules)
- VPC with configurable CIDR block
- 2 public subnets (ALB, NAT) and 2 private subnets (EKS, RDS) across `us-east-1a` and `us-east-1b`
- Internet Gateway attached to VPC
- Public route table: `0.0.0.0/0` → IGW; **both public subnets associated**
- NAT Gateway count is an input (`single_nat_gateway`): **dev = 1**, **prod = 2** (one per AZ)
- Inputs: `vpc_cidr`, `public_subnet_cidrs`, `private_subnet_cidrs`, `availability_zones`, `single_nat_gateway`
- Module files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`

**Acceptance Criteria:**
- [ ] Module in `terraform/modules/vpc/` with main.tf, variables.tf, outputs.tf, versions.tf
- [ ] VPC created with DNS support and DNS hostnames enabled
- [ ] 2 public subnets with `map_public_ip_on_launch = true`
- [ ] 2 private subnets with `map_public_ip_on_launch = false`
- [ ] Subnets spread across `us-east-1a` and `us-east-1b`
- [ ] Internet Gateway attached
- [ ] Public route table: 0.0.0.0/0 → IGW; both public subnets associated
- [ ] NAT: `single_nat_gateway` input — when true, 1 NAT + EIP in public AZ a; both private route tables `0.0.0.0/0` → that NAT
- [ ] When `single_nat_gateway` is false: NAT + EIP in each public subnet; each private RT → that AZ's NAT
- [ ] Name tags: `petclinic-{env}-vpc`, `-subnet-public-a/b`, `-subnet-private-a/b`, `-igw`, `-rt-public`, `-rt-private-a/b`, `-nat-a` (and `-nat-b` when two NATs)
- [ ] Public subnets tagged: `kubernetes.io/cluster/petclinic-{env}` = shared, `kubernetes.io/role/elb` = 1
- [ ] Private subnets tagged: `kubernetes.io/cluster/petclinic-{env}` = shared, `kubernetes.io/role/internal-elb` = 1
- [ ] All resources tagged with Project, Environment, ManagedBy
- [ ] Outputs: vpc_id, public_subnet_ids, private_subnet_ids, nat_gateway_ids
- [ ] `terraform validate` passes

---

### PETPLAT-7: Add S3 Gateway VPC endpoint

**Type:** Story
**Priority:** P0
**Epic:** E-2 Networking
**Story Points:** 2
**Labels:** terraform, networking, vpc
**Blocked by:** PETPLAT-6

**Description:**
Add a free S3 Gateway VPC endpoint in the VPC module so private subnets reach S3 (including ECR image layers) without NAT. Interface endpoints are out of scope for E-2.

**Technical Spec:** [VPC Network Design](./technical-spec.md#vpc-network-design)

**Acceptance Criteria:**
- [ ] Gateway endpoint for `com.amazonaws.us-east-1.s3` in the VPC module
- [ ] Associated with **both private** route tables
- [ ] Name: `petclinic-{env}-vpce-s3`
- [ ] Tagged Project, Environment, ManagedBy
- [ ] No Interface endpoints (ecr, secretsmanager, logs, etc.)
- [ ] `terraform validate` passes

---

### PETPLAT-8: Create baseline security groups

**Type:** Story
**Priority:** P0
**Epic:** E-2 Networking
**Story Points:** 3
**Labels:** terraform, networking, security
**Blocked by:** PETPLAT-6

**Description:**
Create four custom security groups **inside** `terraform/modules/vpc/` (not a separate module). Follow the full matrix in the technical spec. Private subnets are the first perimeter; SGs stay least-privilege. No extra SGs (no bastion, no SSH).

**Technical Spec:** [Security Groups](./technical-spec.md#security-groups)

**Acceptance Criteria:**
- [ ] SGs created in the VPC module: ALB, EKS cluster, EKS node, RDS
- [ ] Names: `petclinic-{env}-sg-alb`, `-sg-eks-cluster`, `-sg-eks-node`, `-sg-rds`
- [ ] EKS cluster SG: ingress TCP 443 from node SG; egress as spec
- [ ] EKS node SG: ingress all from cluster SG; ingress all from self; ingress TCP 10250 from cluster SG; ingress TCP 30000-32767 from ALB SG; egress all
- [ ] RDS SG: ingress TCP 3306 from node SG **only** (never 0.0.0.0/0)
- [ ] ALB SG: ingress TCP 80 and 443 from 0.0.0.0/0; egress TCP 30000-32767 and 8080 to node SG
- [ ] Only ALB 80/443 may use 0.0.0.0/0 on **ingress**
- [ ] Default VPC SG is not used (no extra rules / not attached to workloads)
- [ ] All SGs tagged Project, Environment, ManagedBy
- [ ] Outputs: `eks_cluster_sg_id`, `eks_node_sg_id`, `rds_sg_id`, `alb_sg_id`
- [ ] `terraform validate` passes

---

### PETPLAT-9: Wire VPC module into dev environment

**Type:** Task
**Priority:** P0
**Epic:** E-2 Networking
**Story Points:** 2
**Labels:** terraform, networking
**Blocked by:** PETPLAT-6, PETPLAT-7, PETPLAT-8

**Description:**
Call the VPC module from `terraform/environments/dev/main.tf` with dev-appropriate values.

**Technical Spec:** [VPC Network Design](./technical-spec.md#vpc-network-design)

**Acceptance Criteria:**
- [ ] VPC module called in dev main.tf
- [ ] VPC CIDR: 10.0.0.0/16
- [ ] Public subnets: 10.0.1.0/24, 10.0.2.0/24
- [ ] Private subnets: 10.0.11.0/24, 10.0.12.0/24
- [ ] AZs: us-east-1a, us-east-1b
- [ ] `single_nat_gateway = true` (1 NAT)
- [ ] `terraform plan` shows VPC, 2 public + 2 private subnets, IGW, **1 NAT Gateway**, route tables, SGs
- [ ] Root outputs: vpc_id, public_subnet_ids, private_subnet_ids, SG IDs
- [ ] `terraform apply` succeeds and creates the VPC

---

### PETPLAT-10: Wire VPC module into prod environment

**Type:** Task
**Priority:** P1
**Epic:** E-2 Networking
**Story Points:** 1
**Labels:** terraform, networking
**Blocked by:** PETPLAT-6, PETPLAT-7, PETPLAT-8

**Description:**
Call the VPC module from `terraform/environments/prod/main.tf` with prod-appropriate values.

**Technical Spec:** [VPC Network Design](./technical-spec.md#vpc-network-design)

**Acceptance Criteria:**
- [ ] VPC module called in prod main.tf
- [ ] VPC CIDR: 10.1.0.0/16 (non-overlapping with dev)
- [ ] Public subnets: 10.1.1.0/24, 10.1.2.0/24
- [ ] Private subnets: 10.1.11.0/24, 10.1.12.0/24
- [ ] AZs: us-east-1a, us-east-1b
- [ ] `single_nat_gateway = false` (2 NAT, one per AZ)
- [ ] `terraform plan` shows expected resources (including **2 NAT Gateways**)

---

### PETPLAT-11: Deploy and verify dev VPC

**Type:** Task
**Priority:** P0
**Epic:** E-2 Networking
**Story Points:** 2
**Labels:** terraform, networking, deployment
**Blocked by:** PETPLAT-9

**Description:**
Run `terraform apply` for the dev environment and verify the VPC is created correctly.

**Technical Spec:** [VPC Network Design](./technical-spec.md#vpc-network-design)

**Acceptance Criteria:**
- [ ] `terraform apply` succeeds without errors
- [ ] VPC visible in AWS Console with CIDR 10.0.0.0/16
- [ ] 2 public + 2 private subnets across us-east-1a and us-east-1b
- [ ] **1 NAT Gateway** (public AZ a) with EIP
- [ ] Public route table: 0.0.0.0/0 → IGW
- [ ] Both private route tables: 0.0.0.0/0 → that NAT
- [ ] Public/private subnets tagged for EKS (elb / internal-elb)
- [ ] State file updated in S3

---

# EPIC E-3: EKS Cluster

**Priority:** P0
**Description:** Create the EKS cluster module with managed node groups, OIDC provider for IRSA (IAM Roles for Service Accounts), and required IAM roles. The cluster will host all 8 microservices.
**Blocked by:** E-2
**Blocks:** E-8, E-9, E-10, E-11

---

### PETPLAT-12: Create EKS module — cluster and IAM roles

**Type:** Story
**Priority:** P0
**Epic:** E-3 EKS Cluster
**Story Points:** 5
**Labels:** terraform, eks, iam
**Blocked by:** PETPLAT-6

**Description:**
Create the EKS module in `terraform/modules/eks/` that provisions:

**Technical Spec:** [EKS Cluster](./technical-spec.md#eks-cluster), [Terraform Modules](./technical-spec.md#terraform-modules)
- EKS cluster with Kubernetes version 1.34
- Cluster IAM role with AmazonEKSClusterPolicy
- OIDC provider for IRSA (IAM Roles for Service Accounts)
- Cluster placed in **private** subnets (public/private + NAT design, see ADR-0001)
- API server: `endpoint_public_access = true` and `endpoint_private_access = true` (hardcoded). `public_access_cidrs` is a required module input with **no default** — the root module passes `var.public_access_cidrs` from `terraform.tfvars` (operator public IPv4 `/32`). Do not use `0.0.0.0/0`.

**Acceptance Criteria:**
- [ ] Module in `terraform/modules/eks/`
- [ ] EKS cluster created with specified K8s version
- [ ] Cluster IAM role with AmazonEKSClusterPolicy attached
- [ ] OIDC provider created from cluster identity issuer
- [ ] Cluster uses **private** subnets
- [ ] Cluster security group attached
- [ ] `endpoint_public_access = true`, `endpoint_private_access = true`
- [ ] `public_access_cidrs` required input, no default
- [ ] Cluster logging enabled (api, audit, authenticator)
- [ ] Outputs: cluster_name, cluster_endpoint, cluster_ca_certificate, oidc_provider_arn, oidc_provider_url
- [ ] `terraform validate` passes

---

### PETPLAT-13: Add managed node group to EKS module

**Type:** Story
**Priority:** P0
**Epic:** E-3 EKS Cluster
**Story Points:** 5
**Labels:** terraform, eks, compute
**Blocked by:** PETPLAT-12

**Description:**
Add a managed node group configuration to the EKS module:

**Technical Spec:** [EKS Cluster](./technical-spec.md#eks-cluster)
- Node IAM role with required policies (EKSWorkerNodePolicy, EKS_CNI_Policy, EC2ContainerRegistryReadOnly)
- Configurable instance types, min/max/desired sizes
- Nodes in **private** subnets (outbound via NAT)
- Node labels: `environment`, `managed-by` (no taints)

**Acceptance Criteria:**
- [ ] Managed node group resource created
- [ ] Node IAM role with AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly
- [ ] Instance types configurable (default: ["t4g.small"] for dev — ARM/Graviton, free trial)
- [ ] Scaling config: min_size, max_size, desired_size as variables
- [ ] Nodes launched in **private** subnets
- [ ] Disk size configurable (default: 20 GB — fits within 30 GB EBS free tier)
- [ ] Node security group attached
- [ ] Labels: environment, managed-by
- [ ] Outputs: node_group_name, node_role_arn
- [ ] `terraform validate` passes

---

### PETPLAT-14: Create kubectl access configuration

**Type:** Task
**Priority:** P0
**Epic:** E-3 EKS Cluster
**Story Points:** 2
**Labels:** eks, access
**Blocked by:** PETPLAT-12

**Description:**
Add an EKS **access entry** for the IAM principal that runs Terraform, associated with `AmazonEKSClusterAdminPolicy` (cluster-scoped). Output the `aws eks update-kubeconfig` command. Do **not** manage the `aws-auth` ConfigMap (no Kubernetes provider).

**Technical Spec:** [EKS Cluster](./technical-spec.md#eks-cluster)

**Acceptance Criteria:**
- [ ] EKS access entry for the deploying IAM principal (`data.aws_caller_identity.current`)
- [ ] Access policy association: `AmazonEKSClusterAdminPolicy`, cluster-scoped
- [ ] No `aws-auth` ConfigMap resource and no Kubernetes provider
- [ ] Output: kubeconfig update command (`aws eks update-kubeconfig --name <cluster> --region <region>`)

---

### PETPLAT-15: Wire EKS module into dev environment

**Type:** Task
**Priority:** P0
**Epic:** E-3 EKS Cluster
**Story Points:** 2
**Labels:** terraform, eks
**Blocked by:** PETPLAT-12, PETPLAT-13, PETPLAT-9

**Description:**
Call the EKS module from dev environment with dev-appropriate sizing.

**Technical Spec:** [EKS Cluster](./technical-spec.md#eks-cluster)

**Acceptance Criteria:**
- [ ] EKS module called in dev main.tf
- [ ] Cluster name: petclinic-dev
- [ ] Node group: t4g.small (ARM/Graviton free trial), min=2, max=4, desired=2
- [ ] Passed from VPC module: `private_subnet_ids`, `eks_cluster_sg_id`, `eks_node_sg_id` (no `vpc_id`)
- [ ] `public_access_cidrs` passed from `var.public_access_cidrs` (root variable, no default; set in `terraform.tfvars` to the operator public IPv4 `/32`)
- [ ] `terraform plan` shows expected resources

---

### PETPLAT-16: Deploy and verify dev EKS cluster

**Type:** Task
**Priority:** P0
**Epic:** E-3 EKS Cluster
**Story Points:** 3
**Labels:** terraform, eks, deployment
**Blocked by:** PETPLAT-15, PETPLAT-11

**Description:**
Run `terraform apply` and verify the EKS cluster is operational.

**Technical Spec:** [EKS Cluster](./technical-spec.md#eks-cluster)

**Acceptance Criteria:**
- [ ] `terraform apply` succeeds
- [ ] Cluster status: ACTIVE
- [ ] Nodes visible: `kubectl get nodes` shows 2 Ready nodes
- [ ] OIDC provider visible in IAM console
- [ ] CoreDNS and kube-proxy running: `kubectl get pods -n kube-system`

---

### PETPLAT-17: Wire EKS module into prod environment

**Type:** Task
**Priority:** P1
**Epic:** E-3 EKS Cluster
**Story Points:** 1
**Labels:** terraform, eks
**Blocked by:** PETPLAT-12, PETPLAT-13, PETPLAT-10

**Description:**
Call the EKS module from prod environment with prod-appropriate sizing.

**Technical Spec:** [EKS Cluster](./technical-spec.md#eks-cluster)

**Acceptance Criteria:**
- [ ] Cluster name: petclinic-prod
- [ ] Node group: t4g.small (ARM/Graviton free trial), min=2, max=4, desired=2
- [ ] Passed from VPC module: `private_subnet_ids`, `eks_cluster_sg_id`, `eks_node_sg_id` (no `vpc_id`)
- [ ] `public_access_cidrs` passed from `var.public_access_cidrs` (root variable, no default; set in `terraform.tfvars` to the operator public IPv4 `/32`)
- [ ] `terraform plan` shows expected resources

---

# EPIC E-4: Container Registry (ECR)

**Priority:** P0
**Description:** Create ECR private repositories for all 8 microservices with lifecycle policies, scan-on-push, and configurable tag immutability (MUTABLE dev, IMMUTABLE prod). Images stored at `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service}:{tag}`. Cost: ~$1/month beyond 500 MB free tier.
**Blocked by:** E-1
**Blocks:** E-10, E-17

---

### PETPLAT-18: Create ECR module

**Type:** Story
**Priority:** P0
**Epic:** E-4 Container Registry (ECR)
**Story Points:** 3
**Labels:** terraform, ecr
**Blocked by:** PETPLAT-5

**Description:**
Create the ECR module in `terraform/modules/ecr/` that provisions one ECR private repository per microservice using `aws_ecr_repository`. Accept a list of service names and environment as variables. Configure lifecycle policies, scan-on-push, and tag immutability per environment.

**Technical Spec:** [ECR Container Registry](./technical-spec.md#ecr-container-registry), [Terraform Modules](./technical-spec.md#terraform-modules)

**Acceptance Criteria:**
- [ ] Module in `terraform/modules/ecr/`
- [ ] Uses `aws_ecr_repository` resource
- [ ] Accepts `service_names` list variable and `environment` variable
- [ ] Creates one ECR repo per service name under `petclinic-{env}/` namespace
- [ ] Scan-on-push enabled (`image_scanning_configuration`)
- [ ] Encryption: `encryption_configuration { encryption_type = "AES256" }` on every repository (no KMS)
- [ ] Tag mutability configurable (MUTABLE for dev, IMMUTABLE for prod)
- [ ] Lifecycle policy: expire untagged after 7 days; keep last 10 tagged images
- [ ] Outputs: map of service_name → repository_url, map of service_name → repository_arn
- [ ] `terraform validate` passes

---

### PETPLAT-19: Add lifecycle policy and tag immutability configuration

**Type:** Task
**Priority:** P1
**Epic:** E-4 Container Registry (ECR)
**Story Points:** 2
**Labels:** terraform, ecr, cost-optimization
**Blocked by:** PETPLAT-18

**Description:**
Configure ECR lifecycle policies to automatically clean up old images and manage storage costs. Set tag immutability per environment: MUTABLE for dev (allows re-pushing same tag during development), IMMUTABLE for prod (ensures deployed tags cannot be overwritten).

**Technical Spec:** [ECR Container Registry](./technical-spec.md#ecr-container-registry)

**Acceptance Criteria:**
- [ ] Lifecycle policy JSON: expire untagged after 7 days; keep last 10 tagged images
- [ ] `aws_ecr_lifecycle_policy` resource attached to each repository
- [ ] Tag immutability: `MUTABLE` for dev, `IMMUTABLE` for prod (variable-driven)
- [ ] `terraform validate` passes

---

### PETPLAT-20: Wire ECR module into dev environment

**Type:** Task
**Priority:** P0
**Epic:** E-4 Container Registry (ECR)
**Story Points:** 2
**Labels:** terraform, ecr
**Blocked by:** PETPLAT-18, PETPLAT-19

**Description:**
Call the ECR module from the dev environment. Pass `service_names` and `image_tag_mutability` from `terraform.tfvars` (`MUTABLE`). Do not apply — validate and plan only.

**Technical Spec:** [ECR Container Registry](./technical-spec.md#ecr-container-registry)

**Acceptance Criteria:**
- [ ] ECR module called in dev main.tf
- [ ] `service_names` and `image_tag_mutability` from `var.*` / `terraform.tfvars` (no hardcoded list in main.tf)
- [ ] tfvars: the 8 services; `image_tag_mutability = "MUTABLE"`
- [ ] Repos named `petclinic-dev/{service}`
- [ ] Scan-on-push enabled
- [ ] Root output: `repository_urls` only (do not re-export ARNs at root)
- [ ] `terraform plan` shows 8 repositories (no apply)

---

### PETPLAT-106: Wire ECR module into prod environment

**Type:** Task
**Priority:** P1
**Epic:** E-4 Container Registry (ECR)
**Story Points:** 1
**Labels:** terraform, ecr
**Blocked by:** PETPLAT-18, PETPLAT-19

**Description:**
Call the ECR module from the prod environment. Pass `service_names` and `image_tag_mutability` from `terraform.tfvars` (`IMMUTABLE`). Do not apply — validate and plan only.

**Technical Spec:** [ECR Container Registry](./technical-spec.md#ecr-container-registry)

**Acceptance Criteria:**
- [ ] ECR module called in prod main.tf
- [ ] `service_names` and `image_tag_mutability` from `var.*` / `terraform.tfvars` (no hardcoded list in main.tf)
- [ ] tfvars: the same 8 services as dev; `image_tag_mutability = "IMMUTABLE"`
- [ ] Repos named `petclinic-prod/{service}`
- [ ] Scan-on-push enabled
- [ ] Root output: `repository_urls` only (do not re-export ARNs at root)
- [ ] `terraform plan` shows 8 repositories (no apply)

---

### PETPLAT-21: Create ECR login helper script

**Type:** Task
**Priority:** P2
**Epic:** E-4 Container Registry (ECR)
**Story Points:** 1
**Labels:** ecr, scripts
**Blocked by:** PETPLAT-20

**Description:**
Create `scripts/ecr-login.sh` that authenticates Docker to the ECR private registry in us-east-1.

**Technical Spec:** [ECR Container Registry](./technical-spec.md#ecr-container-registry)

**Acceptance Criteria:**
- [ ] Script at `scripts/ecr-login.sh`
- [ ] Uses `aws ecr get-login-password --region us-east-1` and pipes to `docker login {account}.dkr.ecr.us-east-1.amazonaws.com`
- [ ] Works on macOS and Linux
- [ ] Accepts optional `--region` parameter (defaults to us-east-1)

---

# EPIC E-5: Database (RDS MySQL)

**Priority:** P0
**Description:** Provision RDS MySQL for the three database-backed services (customers, visits, vets). All three share a single `petclinic` database on the same RDS instance (confirmed by cross-service FK constraints). Include encryption, backup, and secrets.
**Blocked by:** E-2
**Blocks:** E-7, E-8

---

### PETPLAT-22: Create RDS module

**Type:** Story
**Priority:** P0
**Epic:** E-5 Database
**Story Points:** 5
**Labels:** terraform, rds, database
**Blocked by:** PETPLAT-6, PETPLAT-8

**Description:**
Create the RDS module in `terraform/modules/rds/` for a MySQL instance.

**Technical Spec:** [RDS Database](./technical-spec.md#rds-database), [Terraform Modules](./technical-spec.md#terraform-modules)

**Acceptance Criteria:**
- [ ] Module in `terraform/modules/rds/`
- [ ] RDS MySQL 8.0 instance (single shared `petclinic` database for all 3 domain services)
- [ ] DB subnet group using **private** subnet IDs passed in (`subnet_ids` — no `vpc_id`)
- [ ] `publicly_accessible = false`
- [ ] Attaches the existing VPC RDS SG (`security_group_id` input). Do **not** create a new security group. 3306-from-nodes is already on that SG.
- [ ] Storage encryption enabled (KMS or default)
- [ ] Multi-AZ configurable (false for both envs — cost optimization; teach students when to enable)
- [ ] Instance class configurable (default: db.t4g.micro — free tier, ARM/Graviton)
- [ ] Allocated storage configurable (default: 20 GB; `max_allocated_storage` also 20 GB — no storage autoscaling)
- [ ] Backup retention: 7 days (both envs, configurable)
- [ ] Skip final snapshot: true (both envs — destroy deletes the instance and its automated backups; no leftover snapshot)
- [ ] DB parameter group with character set utf8mb4
- [ ] Master username `petclinic`; password generated in the module (`random_password`) and stored in Secrets Manager (PETPLAT-23) — not from tfvars
- [ ] Outputs: endpoint, port, db_instance_id
- [ ] `terraform validate` passes

---

### PETPLAT-23: Create database credentials in Secrets Manager

**Type:** Story
**Priority:** P0
**Epic:** E-5 Database
**Story Points:** 3
**Labels:** terraform, rds, secrets-manager
**Blocked by:** PETPLAT-22

**Description:**
Store the RDS master credentials in AWS Secrets Manager via Terraform. Generate a random password. Use Secrets Manager for encrypted storage of sensitive values.

**Technical Spec:** [RDS Database](./technical-spec.md#rds-database), [Secrets Management](./technical-spec.md#secrets-management)

**Acceptance Criteria:**
- [ ] Random password generated using `random_password` resource (16+ chars, special chars)
- [ ] Secrets created using `aws_secretsmanager_secret` and `aws_secretsmanager_secret_version` resources
- [ ] Secret name: `petclinic/{env}/rds-credentials` (single JSON secret with `username` and `password` keys)
- [ ] RDS instance uses that generated password
- [ ] Outputs that include the secret mark `sensitive = true` (the password is still in Terraform state; this only hides it in CLI/plan)
- [ ] Output: secret ARN (for External Secrets Operator later)
- [ ] `terraform validate` passes

---

### PETPLAT-24: Create database initialization strategy

**Type:** Story
**Priority:** P0
**Epic:** E-5 Database
**Story Points:** 3
**Labels:** rds, database
**Blocked by:** PETPLAT-22

**Description:**
Document (do not implement in Terraform) how the shared `petclinic` MySQL database gets its **tables**. The spec already chose Spring Boot auto-init: `spring.sql.init.mode=always` and the `mysql` profile, using SQL in the app repo `src/main/resources/db/mysql/`. Terraform (PETPLAT-22) creates the empty `petclinic` database via `db_name`. The seven tables are created on first pod startup — deploy customers, then vets, then visits (PETPLAT-48). Do **not** copy schema SQL into the RDS module or run `CREATE TABLE` from Terraform.

**Technical Spec:** [RDS Database](./technical-spec.md#rds-database)

**Acceptance Criteria:**
- [ ] Strategy documented: Spring auto-init (`spring.sql.init.mode=always` + `mysql` profile) — not manual SQL and not Terraform
- [ ] Documented: RDS `db_name` creates the empty shared `petclinic` database (all 3 services use it — FK `visits.pet_id` → `pets.id`)
- [ ] Schema scripts identified in the app repo: customers (owners, pets, types), visits (visits), vets (vets, specialties, vet_specialties)
- [ ] Connection string format documented for K8s ConfigMaps
- [ ] Documented: tables appear at PETPLAT-48 (first deploy of customers → vets → visits), not at RDS apply. No "tables exist" test on this story.

---

### PETPLAT-25: Wire RDS module into dev environment

**Type:** Task
**Priority:** P0
**Epic:** E-5 Database
**Story Points:** 2
**Labels:** terraform, rds
**Blocked by:** PETPLAT-22, PETPLAT-23, PETPLAT-9

**Description:**
Call the RDS module from dev environment.

**Technical Spec:** [RDS Database](./technical-spec.md#rds-database)

**Acceptance Criteria:**
- [ ] RDS module called in dev main.tf
- [ ] Instance class: db.t4g.micro (free tier)
- [ ] Multi-AZ: false
- [ ] Skip final snapshot: true
- [ ] Backup retention: 7 days
- [ ] Subnets and RDS SG from VPC module: `private_subnet_ids`, `rds_sg_id` (no `vpc_id`, no new SG)
- [ ] `terraform plan` shows expected resources

---

### PETPLAT-26: Deploy and verify dev RDS

**Type:** Task
**Priority:** P0
**Epic:** E-5 Database
**Story Points:** 2
**Labels:** terraform, rds, deployment
**Blocked by:** PETPLAT-25, PETPLAT-11

**Description:**
Deploy RDS to dev and verify connectivity from EKS pod.

**Technical Spec:** [RDS Database](./technical-spec.md#rds-database)

**Acceptance Criteria:**
- [ ] `terraform apply` succeeds
- [ ] RDS instance status: available
- [ ] Endpoint accessible from EKS node (test via debug pod: `kubectl run`)
- [ ] Can connect with credentials from Secrets Manager
- [ ] Secrets stored correctly in Secrets Manager (`petclinic/{env}/rds-credentials`)

---

### PETPLAT-27: Wire RDS module into prod environment

**Type:** Task
**Priority:** P1
**Epic:** E-5 Database
**Story Points:** 1
**Labels:** terraform, rds
**Blocked by:** PETPLAT-22, PETPLAT-23, PETPLAT-10

**Description:**
Call the RDS module from prod environment with prod-appropriate config.

**Technical Spec:** [RDS Database](./technical-spec.md#rds-database)

**Acceptance Criteria:**
- [ ] Instance class: db.t4g.micro (free tier, same as dev — cost optimization for learning)
- [ ] Multi-AZ: false (single-AZ to save cost; note: in real production, enable Multi-AZ)
- [ ] Skip final snapshot: true
- [ ] Backup retention: 7 days
- [ ] Passed from VPC module: `private_subnet_ids`, `rds_sg_id` (no `vpc_id`, no new SG)
- [ ] `terraform plan` shows expected resources

---

# EPIC E-6: DNS & Ingress

**Priority:** P1
**Description:** Route 53 zone lookup (optional create), **one** wildcard ACM cert (`*.{domain}`, create in at most one env), AWS Load Balancer Controller + ExternalDNS via Terraform `helm_release`, and a Helm Ingress on api-gateway. ExternalDNS writes the ALB alias. Follow `.claude/rules/dns.md` and `.claude/rules/helm.md`.
**Blocked by:** E-2 (ALB SG + subnet tags), E-3 (EKS + OIDC), E-16 (Helm chart)
**Blocks:** Operator HTTPS check (needs images + ArgoCD). Does **not** block E-8.

**Claude E-6 build:** PETPLAT-28, PETPLAT-29, PETPLAT-30, PETPLAT-31, PETPLAT-32, PETPLAT-117. Terraform + Helm YAML, `terraform validate`, `helm lint` / `helm template` / `scripts/validate-helm.sh`. Do **not** `terraform apply`, `helm install`, or `kubectl apply`. HTTPS-in-the-browser is operator, after apply.

---

### PETPLAT-28: Create DNS module — Route 53 zone + ACM

**Type:** Story
**Priority:** P1
**Epic:** E-6 DNS & Ingress
**Story Points:** 3
**Labels:** terraform, dns, route53, acm
**Blocked by:** PETPLAT-5

**Description:**
Fill `terraform/modules/dns/` for a **public** hosted zone **lookup** (optional create) and **one** wildcard ACM certificate `*.{domain}`. Create that cert in at most one state (`create_acm_certificate`). Do not create an ALB alias record.

**Technical Spec:** [DNS and Ingress](./technical-spec.md#dns-and-ingress), [Terraform Modules](./technical-spec.md#terraform-modules)

**Acceptance Criteria:**
- [ ] Module files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (AWS provider; Helm provider needed by PETPLAT-29/31 — add it here so later stories do not reshuffle versions)
- [ ] Inputs: `project`, `environment`, `domain_name`, `create_hosted_zone` (default false), `create_acm_certificate` (default false), plus the cluster/OIDC/install inputs listed in the spec (can be unused until 29/31)
- [ ] Default path: `data.aws_route53_zone` public zone named `domain_name`
- [ ] Optional `aws_route53_zone` only when `create_hosted_zone` is true
- [ ] ACM: domain `*.{domain}` (wildcard). When `create_acm_certificate` is true: `aws_acm_certificate` + DNS validation records + `aws_acm_certificate_validation`. When false: `data.aws_acm_certificate` for `*.{domain}` (ISSUED)
- [ ] Do **not** create the wildcard cert from both roots (validation CNAME collision)
- [ ] Ingress host FQDN is still derived: dev `petclinic-dev.{domain}`, prod `petclinic.{domain}` — that is not the cert CN
- [ ] Outputs: `zone_id`, `name_servers`, `fqdn`, `certificate_arn` (add-on role outputs can wait for 29/31)
- [ ] No `aws_route53_record` alias to an ALB / `data.aws_lb`
- [ ] `terraform fmt` + `terraform validate` (module or a root that calls it)
- [ ] Do **not** apply

---

### PETPLAT-29: AWS Load Balancer Controller (Terraform Helm)

**Type:** Story
**Priority:** P1
**Epic:** E-6 DNS & Ingress
**Story Points:** 5
**Labels:** terraform, eks, ingress, helm
**Blocked by:** PETPLAT-16, PETPLAT-28

**Description:**
Install the AWS Load Balancer Controller with `helm_release` in the dns module, gated like ESO. IRSA role `petclinic-{env}-lb-controller-role`. Do **not** `helm install` from the CLI. Do not test by creating a throwaway Ingress.

**Operator (not Claude):** `terraform apply` when the cluster exists and `install_lb_controller` is true. Confirm controller pods in `kube-system` after apply.

**Technical Spec:** [DNS and Ingress](./technical-spec.md#dns-and-ingress), [IRSA Roles](./technical-spec.md#irsa-roles)

**Acceptance Criteria:**
- [ ] IRSA: SA `aws-load-balancer-controller` in `kube-system`; official IAM JSON from controller tag `v3.5.0` vendored unmodified under `terraform/modules/dns/iam/`
- [ ] `helm_release` chart `aws-load-balancer-controller` repo `https://aws.github.io/eks-charts` version **3.5.0**, namespace `kube-system`, gated by `install_lb_controller`
- [ ] Values: `clusterName`, `vpcId`, region `us-east-1`, IngressClass `alb`, `createIngressClassResource: true`, Helm creates the SA with the role annotation
- [ ] Root variables `install_lb_controller` and `lb_controller_chart_version` (same pattern as `install_eso`)
- [ ] Do **not** `helm install` / `kubectl apply` on a cluster
- [ ] `terraform validate`

---

### PETPLAT-30: Helm Ingress for API Gateway

**Type:** Story
**Priority:** P1
**Epic:** E-6 DNS & Ingress
**Story Points:** 3
**Labels:** helm, ingress, networking
**Blocked by:** PETPLAT-107, PETPLAT-108, PETPLAT-109

**Description:**
Add an optional Ingress template to the generic chart. Enable it only for api-gateway. Host / cert / ALB SG come from env values with placeholders. ArgoCD already deploys this chart — do **not** add `k8s/base/ingress/`.

**Technical Spec:** [DNS and Ingress](./technical-spec.md#dns-and-ingress), [Helm Charts](./technical-spec.md#helm-charts)

**Acceptance Criteria:**
- [ ] `helm/petclinic-service/templates/ingress.yaml` rendered only when `ingress.enabled`
- [ ] Chart default `ingress.enabled: false`; `helm-values/api-gateway.yaml` sets `enabled: true`
- [ ] `spec.ingressClassName: alb` — no `kubernetes.io/ingress.class`
- [ ] Annotations match the spec (scheme, target-type ip, cert, listen-ports, ssl-redirect, ssl-policy, healthcheck, **existing** ALB SG, `manage-backend-security-group-rules: "false"`, load-balancer-name)
- [ ] Route `/` Prefix → this service port 8080
- [ ] `helm-values/dev.yaml` / `prod.yaml`: `ingress.host` (`petclinic-dev.DOMAIN` / `petclinic.DOMAIN`), `certificateArn: CERT_ARN` (**same** wildcard ARN in both files), `albSecurityGroupId: ALB_SG_ID`, `loadBalancerName: petclinic-{env}`
- [ ] `helm lint` + `helm template` (or `scripts/validate-helm.sh --service api-gateway`)
- [ ] No `k8s/base/ingress/`. No live apply. ALB existing in AWS is operator after sync.

---

### PETPLAT-31: ExternalDNS (Terraform Helm)

**Type:** Story
**Priority:** P1
**Epic:** E-6 DNS & Ingress
**Story Points:** 5
**Labels:** terraform, dns, helm
**Blocked by:** PETPLAT-28, PETPLAT-16

**Description:**
Install ExternalDNS with `helm_release` in the dns module so it creates the Route 53 alias from the Ingress host. Do **not** add Terraform `aws_route53_record` aliases to the ALB.

**Operator (not Claude):** after apply + Ingress sync, confirm `petclinic-dev.{domain}` (and later prod) is an alias to the ALB and HTTPS works. That needs running gateway pods — not part of this Claude story.

**Technical Spec:** [DNS and Ingress](./technical-spec.md#dns-and-ingress), [IRSA Roles](./technical-spec.md#irsa-roles), [ADR-0012](./technical-spec.md#adr-index)

**Acceptance Criteria:**
- [ ] IRSA `petclinic-{env}-external-dns-role`; SA `external-dns` in `kube-system`; Route 53 change on **this** zone only
- [ ] `helm_release` chart `external-dns` repo `https://kubernetes-sigs.github.io/external-dns/` version **1.21.1**, namespace `kube-system`, gated by `install_external_dns`
- [ ] provider `aws`, sources `[ingress]`, `domainFilters` = `[domain_name]`, `txtOwnerId` = `petclinic-{env}`, policy `upsert-only`, public zones
- [ ] Root variables `install_external_dns` and `external_dns_chart_version`
- [ ] Outputs include `external_dns_role_arn`
- [ ] No ALB alias in Terraform
- [ ] Do **not** require a live DNS lookup or browser HTTPS for this story
- [ ] `terraform validate`

---

### PETPLAT-32: Wire DNS module into dev environment

**Type:** Task
**Priority:** P1
**Epic:** E-6 DNS & Ingress
**Story Points:** 1
**Labels:** terraform, dns, dev
**Blocked by:** PETPLAT-28, PETPLAT-29, PETPLAT-31

**Description:**
Call the DNS module from the **dev** root. Pass VPC/EKS outputs, `domain_name` from tfvars, install flags (true only if the cluster already exists — same caution as `install_eso`).

**Technical Spec:** [DNS and Ingress](./technical-spec.md#dns-and-ingress)

**Acceptance Criteria:**
- [ ] `module "dns"` in `terraform/environments/dev/main.tf`
- [ ] `create_hosted_zone` false unless the operator has no zone yet (never true in both envs)
- [ ] `create_acm_certificate` **true** in dev when Terraform should issue the `*.{domain}` wildcard (typical). Never true in both envs
- [ ] `install_lb_controller` / `install_external_dns` follow the ESO gate
- [ ] Root `variables.tf` + outputs for `certificate_arn`, `fqdn`, `zone_id`, `name_servers`
- [ ] `terraform validate` / plan locally is enough — do **not** apply
- [ ] Do not put a real domain or cert ARN in Git (tfvars is gitignored)

---

### PETPLAT-117: Wire DNS module into prod environment

**Type:** Task
**Priority:** P1
**Epic:** E-6 DNS & Ingress
**Story Points:** 1
**Labels:** terraform, dns, prod
**Blocked by:** PETPLAT-28, PETPLAT-29, PETPLAT-31

**Description:**
Call the DNS module from the **prod** root. Always **look up** the hosted zone (`create_hosted_zone = false`) and the wildcard cert (`create_acm_certificate = false`). Install flags false until prod EKS exists (same as `install_eso`).

**Technical Spec:** [DNS and Ingress](./technical-spec.md#dns-and-ingress)

**Acceptance Criteria:**
- [ ] `module "dns"` in `terraform/environments/prod/main.tf`
- [ ] `create_hosted_zone = false`
- [ ] `create_acm_certificate = false` (look up `*.{domain}` after dev has issued it)
- [ ] Same inputs pattern as dev; Ingress FQDN is `petclinic.{domain}`
- [ ] `terraform plan` must work without talking to a cluster when install flags are false
- [ ] Do **not** apply

---

# EPIC E-7: Secrets Management (Secrets Manager)

**Priority:** P0
**Description:** Set up AWS Secrets Manager for all application secrets and install External Secrets Operator on EKS to sync secrets into Kubernetes Secrets. Secrets Manager provides encrypted storage and centralized secret management for the application.
**Blocked by:** E-3, E-5
**Blocks:** E-8

---

### PETPLAT-33: Create Secrets Manager Terraform resources (non-RDS secrets)

**Type:** Story
**Priority:** P0
**Epic:** E-7 Secrets Management (Secrets Manager)
**Story Points:** 3
**Labels:** terraform, secrets-manager
**Blocked by:** PETPLAT-5

**Description:**
Create the secrets module in `terraform/modules/secrets/` to manage **non-RDS** application secrets in AWS Secrets Manager using `aws_secretsmanager_secret` and `aws_secretsmanager_secret_version`. Call the module from both environment roots. RDS credentials are created by PETPLAT-23 in the RDS module — do NOT duplicate them here.

**Technical Spec:** [Secrets Management](./technical-spec.md#secrets-management), [Terraform Modules](./technical-spec.md#terraform-modules)

**Acceptance Criteria:**
- [ ] Module in `terraform/modules/secrets/`
- [ ] `module.secrets` called in `terraform/environments/dev/main.tf` and `terraform/environments/prod/main.tf`
- [ ] Inputs from the root: `project`, `environment`, `openai_api_key` (`sensitive = true`, value from tfvars — not hardcoded)
- [ ] Secrets created using `aws_secretsmanager_secret` and `aws_secretsmanager_secret_version` resources
- [ ] Secrets created: `petclinic/{env}/openai-api-key`
- [ ] RDS credentials NOT created here (owned by RDS module — PETPLAT-23)
- [ ] Outputs: `openai_secret_arn` (sensitive)
- [ ] `terraform validate` passes
- [ ] `terraform plan` shows the OpenAI secret in both environments

---

### PETPLAT-34: Install External Secrets Operator on EKS

**Type:** Story
**Priority:** P0
**Epic:** E-7 Secrets Management (Secrets Manager)
**Story Points:** 5
**Labels:** terraform, helm, secrets-manager, eks
**Blocked by:** PETPLAT-16, PETPLAT-37

**Description:**
Install External Secrets Operator on EKS with Terraform (`helm_release`) so a later `terraform apply` recreates it. The IAM role is **PETPLAT-37** — do **not** create another role. Annotate ServiceAccount `external-secrets-sa` with `eso_role_arn`. Do **not** create ClusterSecretStore / ExternalSecret with the Kubernetes provider in the same apply (CRDs are not ready yet). Those stay YAML (this story + PETPLAT-35/36).

**Technical Spec:** [Secrets Management](./technical-spec.md#secrets-management), [IRSA Roles](./technical-spec.md#irsa-roles), [Terraform Modules](./technical-spec.md#terraform-modules)

**Acceptance Criteria:**
- [ ] `helm_release` in `terraform/modules/secrets/` for chart `external-secrets/external-secrets` version **`2.10.0`** (not `latest`), namespace `external-secrets`, `create_namespace = true`, Helm-managed CRDs
- [ ] Input `install_eso` (bool): **true** in dev tfvars (cluster already exists); **false** in prod tfvars until prod EKS is applied (same apply as a new cluster will fail)
- [ ] Helm/Kubernetes providers in the **dev** root, authenticated to EKS (`aws eks get-token`). Prod root must still `terraform plan` without talking to a cluster (no helm_release when `install_eso = false`)
- [ ] ServiceAccount name **`external-secrets-sa`**; annotation `eks.amazonaws.com/role-arn` = this module's `eso_role_arn` — no new IAM role
- [ ] ClusterSecretStore YAML only: `k8s/base/external-secrets/cluster-secret-store.yaml`, `apiVersion: external-secrets.io/v1`, name `aws-secrets-manager`, region `us-east-1` — not `v1beta1`, not a Terraform `kubernetes_manifest`
- [ ] Sample ExternalSecret YAML for namespace `external-secrets` (smoke test after apply). Do **not** require `petclinic-dev` / `petclinic-prod`
- [ ] `terraform validate` passes; `terraform plan` in **dev** shows the Helm release (user applies — do not apply in this story)
- [ ] Documented: how to add new secrets (YAML in `k8s/base/external-secrets/`)

---

### PETPLAT-35: Create ExternalSecret for RDS credentials

**Type:** Task
**Priority:** P0
**Epic:** E-7 Secrets Management (Secrets Manager)
**Story Points:** 2
**Labels:** k8s, secrets-manager
**Blocked by:** PETPLAT-34, PETPLAT-23

**Description:**
Create the ExternalSecret manifest that syncs RDS credentials from Secrets Manager into Kubernetes. The YAML targets namespace `petclinic-{env}`. Do **not** treat live `kubectl get secret` as this story's gate — that namespace is PETPLAT-38 (E-8).

**Technical Spec:** [Secrets Management](./technical-spec.md#secrets-management)

**Acceptance Criteria:**
- [ ] ExternalSecret manifest at `k8s/base/external-secrets/rds-credentials.yaml`
- [ ] `metadata.namespace`: `petclinic-dev` or `petclinic-prod` (env overlay / per-env file — not `external-secrets`)
- [ ] References Secrets Manager secret: `petclinic/{env}/rds-credentials` (single JSON secret)
- [ ] Uses `remoteRef.key` with `remoteRef.property` to extract `username` and `password` from JSON
- [ ] Target K8s Secret keys: `username`, `password`
- [ ] Refresh interval: 1h
- [ ] `kubectl apply --dry-run=client` passes
- [ ] Live verify (`kubectl get secret` in `petclinic-{env}`) is after PETPLAT-38, not this story

---

### PETPLAT-36: Create ExternalSecret for OpenAI API key

**Type:** Task
**Priority:** P0
**Epic:** E-7 Secrets Management (Secrets Manager)
**Story Points:** 1
**Labels:** k8s, secrets-manager
**Blocked by:** PETPLAT-34, PETPLAT-33

**Description:**
Create the ExternalSecret manifest for the GenAI service's OpenAI API key. Same as PETPLAT-35: YAML now, live secret in `petclinic-{env}` after PETPLAT-38.

**Technical Spec:** [Secrets Management](./technical-spec.md#secrets-management)

**Acceptance Criteria:**
- [ ] ExternalSecret manifest at `k8s/base/external-secrets/openai-api-key.yaml`
- [ ] `metadata.namespace`: `petclinic-dev` or `petclinic-prod` (not `external-secrets`)
- [ ] References Secrets Manager secret: `petclinic/{env}/openai-api-key`
- [ ] Target K8s Secret key: `OPENAI_API_KEY`
- [ ] `kubectl apply --dry-run=client` passes
- [ ] Live verify (`kubectl get secret` in `petclinic-{env}`) is after PETPLAT-38, not this story

---

### PETPLAT-37: Create IRSA role for External Secrets Operator

**Type:** Task
**Priority:** P0
**Epic:** E-7 Secrets Management (Secrets Manager)
**Story Points:** 3
**Labels:** terraform, iam, secrets-manager
**Blocked by:** PETPLAT-12, PETPLAT-33

**Description:**
Add the ESO IRSA role to the **secrets module** (same module as PETPLAT-33). Do **not** put this role in the EKS module and do **not** create a second secrets module. Trust is scoped to ServiceAccount `external-secrets-sa` in namespace `external-secrets`. OIDC ARN/URL come from the EKS module.

**Technical Spec:** [IRSA Roles](./technical-spec.md#irsa-roles)

**Acceptance Criteria:**
- [ ] IAM role in `terraform/modules/secrets/`, name `petclinic-{env}-eso-role`
- [ ] Inputs from the root: `oidc_provider_arn` and `oidc_provider_url` from `module.eks` (not a new OIDC provider)
- [ ] Trust policy: `sts:AssumeRoleWithWebIdentity` for `system:serviceaccount:external-secrets:external-secrets-sa`
- [ ] Policy: `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` on `arn:aws:secretsmanager:us-east-1:{account}:secret:petclinic/*`
- [ ] No `kms:Decrypt` (default `aws/secretsmanager` key — not a customer-managed key)
- [ ] Output: `eso_role_arn` (for the ESO ServiceAccount annotation in PETPLAT-34)
- [ ] `terraform validate` passes

---

# EPIC E-8: Kubernetes Manifests — Base

**Priority:** P0
**Description:** Create base Kubernetes manifests for all 8 microservices (including Admin Server). Each service gets its own directory with Deployment, Service, ConfigMap, and ServiceAccount. Respect startup order dependencies. Write YAML and `kubectl apply --dry-run=client` only — the operator applies to the cluster.
**Blocked by:** E-3, E-5, E-7
**Blocks:** E-9, E-10, E-11

**All service manifests (PETPLAT-39 through PETPLAT-44):**
- Labels on every resource: `app.kubernetes.io/name`, `app.kubernetes.io/part-of=petclinic`, `app.kubernetes.io/managed-by=Helm`, `app.kubernetes.io/component`
- SecurityContext on every Deployment (see spec): `runAsNonRoot: true`, `runAsUser: 1000`, `fsGroup: 1000`; container `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`
- Image placeholder: `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service}:<TAG>`
- Init containers: Config Server none; Discovery waits for Config only; all others wait for Config **and** Discovery (busybox:1.36 as in spec). Do not make Discovery wait for itself.
- Probes: Config Server uses `/actuator/health` for startup, readiness, and liveness. All other services: startup `/actuator/health`, readiness `/actuator/health/readiness`, liveness `/actuator/health/liveness` (timings in spec).
- No Ingress manifests (E-6). No live `kubectl apply`.

---

### PETPLAT-38: Create K8s namespaces manifest

**Type:** Task
**Priority:** P0
**Epic:** E-8 K8s Base Manifests
**Story Points:** 1
**Labels:** k8s
**Blocked by:** PETPLAT-16

**Description:**
Create namespace definitions for dev and prod. After the operator applies this file, they apply the E-7 ExternalSecret YAML (`rds-credentials.yaml`, `openai-api-key.yaml`) so secrets can sync into `petclinic-dev`. This story does not apply anything to the cluster.

**Technical Spec:** [Kubernetes Manifests](./technical-spec.md#kubernetes-manifests)

**Acceptance Criteria:**
- [ ] `k8s/base/namespaces.yaml` with petclinic-dev and petclinic-prod namespaces
- [ ] Namespaces labeled: `app.kubernetes.io/part-of=petclinic`, `environment={dev,prod}`
- [ ] PSA labels on both namespaces: `pod-security.kubernetes.io/enforce=baseline`, `pod-security.kubernetes.io/warn=restricted`, `pod-security.kubernetes.io/audit=restricted`
- [ ] Documented for the operator (not Claude): after applying namespaces, apply `k8s/base/external-secrets/rds-credentials.yaml` and `openai-api-key.yaml`, then `kubectl get secret` in `petclinic-dev`
- [ ] `kubectl apply --dry-run=client` passes

---

### PETPLAT-39: Create Config Server K8s manifests

**Type:** Story
**Priority:** P0
**Epic:** E-8 K8s Base Manifests
**Story Points:** 3
**Labels:** k8s, config-server
**Blocked by:** PETPLAT-38

**Description:**
Config Server must deploy first. All other services depend on it.

**Technical Spec:** [Application Services](./technical-spec.md#application-services), [Kubernetes Manifests](./technical-spec.md#kubernetes-manifests)

**Acceptance Criteria:**
- [ ] `k8s-reference/base/config-server/deployment.yaml` — 1 replica, port 8888, SPRING_PROFILES_ACTIVE=docker
- [ ] `k8s-reference/base/config-server/service.yaml` — ClusterIP, port 8888
- [ ] `k8s-reference/base/config-server/configmap.yaml` — non-secret settings only. Do **not** set `GIT_REPO` or the `native` profile (Git URI is already in the app)
- [ ] No init containers
- [ ] Startup, readiness, and liveness probes: `/actuator/health`, port 8888
- [ ] Resource requests: cpu=100m, memory=128Mi; limits: cpu=500m, memory=512Mi
- [ ] Image: `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/config-server:<TAG>` (placeholder)
- [ ] ServiceAccount created
- [ ] Standard labels and SecurityContext (epic + spec)
- [ ] `kubectl apply --dry-run=client` passes

---

### PETPLAT-40: Create Discovery Server K8s manifests

**Type:** Story
**Priority:** P0
**Epic:** E-8 K8s Base Manifests
**Story Points:** 3
**Labels:** k8s, discovery-server
**Blocked by:** PETPLAT-39

**Description:**
Discovery Server (Eureka) depends on Config Server. Must be running before domain services start.

**Technical Spec:** [Application Services](./technical-spec.md#application-services), [Kubernetes Manifests](./technical-spec.md#kubernetes-manifests)

**Acceptance Criteria:**
- [ ] `k8s-reference/base/discovery-server/` — Deployment, Service (ClusterIP port 8761), ConfigMap, ServiceAccount
- [ ] SPRING_PROFILES_ACTIVE=docker; CONFIG_SERVER_URL=http://config-server:8888
- [ ] Init container: wait-for-config-server only (do **not** wait for Discovery)
- [ ] Startup `/actuator/health`; readiness `/actuator/health/readiness`; liveness `/actuator/health/liveness`; port 8761
- [ ] Resources: requests cpu=100m, memory=128Mi; limits cpu=500m, memory=512Mi
- [ ] Image: `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/discovery-server:<TAG>` (placeholder)
- [ ] Standard labels and SecurityContext (epic + spec)
- [ ] `kubectl apply --dry-run=client` passes

---

### PETPLAT-41: Create domain services K8s manifests (customers, visits, vets)

**Type:** Story
**Priority:** P0
**Epic:** E-8 K8s Base Manifests
**Story Points:** 5
**Labels:** k8s, domain-services, rds
**Blocked by:** PETPLAT-40, PETPLAT-35

**Description:**
Create manifests for the three database-backed services. They need MySQL connection config and credentials from Secrets Manager (synced to K8s Secrets via ESO).

**Technical Spec:** [Application Services](./technical-spec.md#application-services), [Kubernetes Manifests](./technical-spec.md#kubernetes-manifests), [RDS Database](./technical-spec.md#rds-database)

**Acceptance Criteria:**
- [ ] Manifests for customers-service (port 8081), visits-service (port 8082), vets-service (port 8083)
- [ ] Each: Deployment, Service (ClusterIP), ConfigMap, ServiceAccount
- [ ] Spring profiles: customers and visits `docker,mysql`; vets `docker,mysql,production` (vets cache requires `production`)
- [ ] ConfigMap: SPRING_DATASOURCE_URL=`jdbc:mysql://{rds-endpoint}:3306/petclinic` (placeholder, not a real hostname)
- [ ] Secret refs: SPRING_DATASOURCE_USERNAME / SPRING_DATASOURCE_PASSWORD from K8s secret `rds-credentials` keys `username` / `password` (ESO)
- [ ] CONFIG_SERVER_URL=http://config-server:8888
- [ ] Init containers: wait-for-config-server and wait-for-discovery-server
- [ ] Startup `/actuator/health`; readiness `/actuator/health/readiness`; liveness `/actuator/health/liveness`
- [ ] Resources: cpu=100m/500m, memory=128Mi/512Mi
- [ ] Image placeholder per service: `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service}:<TAG>`
- [ ] Standard labels and SecurityContext (epic + spec)
- [ ] `kubectl apply --dry-run=client` passes for all three

---

### PETPLAT-42: Create GenAI Service K8s manifests

**Type:** Story
**Priority:** P0
**Epic:** E-8 K8s Base Manifests
**Story Points:** 2
**Labels:** k8s, genai
**Blocked by:** PETPLAT-40, PETPLAT-36

**Description:**
GenAI service needs the OpenAI API key from Secrets Manager (synced to K8s Secret via ESO).

**Technical Spec:** [Application Services](./technical-spec.md#application-services), [Kubernetes Manifests](./technical-spec.md#kubernetes-manifests)

**Acceptance Criteria:**
- [ ] `k8s-reference/base/genai-service/` — Deployment (port 8084), Service (ClusterIP), ConfigMap, ServiceAccount
- [ ] SPRING_PROFILES_ACTIVE=`docker,production`
- [ ] OPENAI_API_KEY from K8s secret `openai-api-key` key `OPENAI_API_KEY` (ESO)
- [ ] CONFIG_SERVER_URL=http://config-server:8888
- [ ] Init containers: wait-for-config-server and wait-for-discovery-server
- [ ] Startup `/actuator/health`; readiness `/actuator/health/readiness`; liveness `/actuator/health/liveness`
- [ ] Resources: cpu=100m/500m, memory=128Mi/512Mi
- [ ] Image: `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/genai-service:<TAG>` (placeholder)
- [ ] Standard labels and SecurityContext (epic + spec)
- [ ] `kubectl apply --dry-run=client` passes

---

### PETPLAT-43: Create API Gateway K8s manifests

**Type:** Story
**Priority:** P0
**Epic:** E-8 K8s Base Manifests
**Story Points:** 3
**Labels:** k8s, api-gateway
**Blocked by:** PETPLAT-40

**Description:**
API Gateway routes traffic to all domain services and serves the frontend. This is the entry point from the ALB ingress.

**Technical Spec:** [Application Services](./technical-spec.md#application-services), [Kubernetes Manifests](./technical-spec.md#kubernetes-manifests)

**Acceptance Criteria:**
- [ ] `k8s-reference/base/api-gateway/` — Deployment (port 8080), Service (ClusterIP), ConfigMap, ServiceAccount
- [ ] SPRING_PROFILES_ACTIVE=docker; CONFIG_SERVER_URL=http://config-server:8888. Do **not** set DISCOVERY_SERVER_URL (app does not use it)
- [ ] Init containers: wait-for-config-server and wait-for-discovery-server
- [ ] Startup `/actuator/health`; readiness `/actuator/health/readiness`; liveness `/actuator/health/liveness`
- [ ] Resources: cpu=200m/1000m, memory=128Mi/512Mi (gateway handles more traffic)
- [ ] Image: `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/api-gateway:<TAG>` (placeholder)
- [ ] This ClusterIP Service is the future Ingress backend. Do **not** create an Ingress manifest (E-6)
- [ ] Standard labels and SecurityContext (epic + spec)
- [ ] `kubectl apply --dry-run=client` passes

---

### PETPLAT-44: Create Admin Server K8s manifests

**Type:** Story
**Priority:** P1
**Epic:** E-8 K8s Base Manifests
**Story Points:** 2
**Labels:** k8s, admin-server
**Blocked by:** PETPLAT-40

**Description:**
Spring Boot Admin for monitoring all services.

**Technical Spec:** [Application Services](./technical-spec.md#application-services), [Kubernetes Manifests](./technical-spec.md#kubernetes-manifests)

**Acceptance Criteria:**
- [ ] `k8s-reference/base/admin-server/` — Deployment (port 9090), Service (ClusterIP), ConfigMap, ServiceAccount
- [ ] SPRING_PROFILES_ACTIVE=docker; CONFIG_SERVER_URL=http://config-server:8888
- [ ] Init containers: wait-for-config-server and wait-for-discovery-server
- [ ] Startup `/actuator/health`; readiness `/actuator/health/readiness`; liveness `/actuator/health/liveness`
- [ ] Resources: cpu=100m/500m, memory=128Mi/512Mi
- [ ] Image: `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/admin-server:<TAG>` (placeholder)
- [ ] Standard labels and SecurityContext (epic + spec)
- [ ] `kubectl apply --dry-run=client` passes

---

# EPIC E-9: Kubernetes Manifests — Overlays

**Priority:** P1
**Description:** Extend the existing `k8s-reference/overlays/{dev,prod}` Kustomize overlays with replica counts, HPA, and PDBs. Do **not** recreate the overlays (namespace, image prefix, and ESO secret keys are already there). Do **not** create `helm-values/` — E-16 copies these overlay settings into Helm values. Write YAML and `kubectl apply --dry-run=client` only. No live apply. No extra README. Overlay YAML is the documentation for E-16.
**Blocked by:** E-8
**Blocks:** E-14, E-16

**Do not include in this epic's Claude build:** PETPLAT-48 (operator live deploy). ResourceQuotas are PETPLAT-89 (E-13). Metrics Server install is PETPLAT-72 (E-14).

---

### PETPLAT-45: Create dev overlay patches

**Type:** Story
**Priority:** P0
**Epic:** E-9 K8s Overlays
**Story Points:** 3
**Labels:** k8s, overlays
**Blocked by:** PETPLAT-38 through PETPLAT-44

**Description:**
Extend `k8s-reference/overlays/dev/` (already sets namespace `petclinic-dev`). Add replica patches only. Keep E-8 CPU/memory. Keep image tag `TAG` until PETPLAT-85 / CI. Do not create `helm-values/dev.yaml`. Do not add a README.

**Technical Spec:** [Kubernetes Overlays](./technical-spec.md#kubernetes-overlays)

**Acceptance Criteria:**
- [ ] Extends existing `k8s-reference/overlays/dev/kustomization.yaml` — does not recreate the overlay
- [ ] All 8 services: 1 replica
- [ ] Resource requests/limits unchanged from E-8 / spec (do not shrink)
- [ ] Namespace remains `petclinic-dev`
- [ ] Image tag remains `TAG` (SHA comes from PETPLAT-85 / CI later)
- [ ] No `helm-values/` files. No extra markdown. Overlay YAML is the E-16 input
- [ ] `kubectl apply --dry-run=client -k k8s-reference/overlays/dev` passes

---

### PETPLAT-46: Create prod overlay patches

**Type:** Story
**Priority:** P1
**Epic:** E-9 K8s Overlays
**Story Points:** 3
**Labels:** k8s, overlays
**Blocked by:** PETPLAT-38 through PETPLAT-44

**Description:**
Extend `k8s-reference/overlays/prod/` (already sets namespace, `petclinic-prod` image prefix, and prod ESO keys). Add replica patches from the spec table. Keep E-8 CPU/memory. Keep image tag `TAG`. Do not create `helm-values/prod.yaml`. Do not add a README.

**Technical Spec:** [Kubernetes Overlays](./technical-spec.md#kubernetes-overlays)

**Acceptance Criteria:**
- [ ] Extends existing `k8s-reference/overlays/prod/kustomization.yaml` — does not recreate the overlay
- [ ] Replicas exactly as spec: config-server 2, discovery-server 2, api-gateway 2, customers/visits/vets 2, genai-service 1, admin-server 1
- [ ] Resource requests/limits unchanged from E-8 / spec (do not increase)
- [ ] Namespace remains `petclinic-prod`
- [ ] Image tag remains `TAG` (SHA comes from PETPLAT-85 / CI later)
- [ ] No `helm-values/` files. No extra markdown. Overlay YAML is the E-16 input
- [ ] `kubectl apply --dry-run=client -k k8s-reference/overlays/prod` passes

---

### PETPLAT-47: Add Horizontal Pod Autoscaler for prod

**Type:** Story
**Priority:** P1
**Epic:** E-9 K8s Overlays
**Story Points:** 3
**Labels:** k8s, scaling, prod
**Blocked by:** PETPLAT-46

**Description:**
Add HPA YAML in the prod overlay for stateless services. Do **not** install Metrics Server (PETPLAT-72). HPA will not function in-cluster until then. YAML + dry-run only.

**Technical Spec:** [Kubernetes Overlays](./technical-spec.md#kubernetes-overlays)

**Acceptance Criteria:**
- [ ] HPA for api-gateway: min=2, max=6, target CPU=70%
- [ ] HPA for customers, visits, vets: min=2, max=4, target CPU=70%
- [ ] HPA for genai-service: min=1, max=3, target CPU=70%
- [ ] No HPA for config-server, discovery-server, or admin-server
- [ ] No Metrics Server install in this story
- [ ] `kubectl apply --dry-run=client -k k8s-reference/overlays/prod` passes

---

### PETPLAT-48: Deploy all services to dev namespace and verify

**Type:** Story
**Priority:** P0
**Epic:** E-9 K8s Overlays
**Story Points:** 5
**Labels:** k8s, deployment, verification
**Blocked by:** PETPLAT-45, PETPLAT-16, PETPLAT-24, PETPLAT-26, PETPLAT-35, PETPLAT-36, PETPLAT-85

**Description:**
**Operator live story — not part of the Claude E-9 build.** Come back after images exist (PETPLAT-85), overlays are applied, and ESO secrets are in `petclinic-dev`. Deploy all 8 services to dev and verify. Domain services: **customers-service first**, then vets-service, then visits-service so Spring auto-init can create tables in FK order.

**Technical Spec:** [Application Services](./technical-spec.md#application-services), [Kubernetes Overlays](./technical-spec.md#kubernetes-overlays), [RDS Database](./technical-spec.md#rds-database)

**Acceptance Criteria:**
- [ ] All 8 deployments running in petclinic-dev namespace
- [ ] All pods in Ready state
- [ ] Config Server healthy: `curl config-server:8888/actuator/health`
- [ ] Discovery Server shows all services registered: `curl discovery-server:8761/eureka/apps`
- [ ] API Gateway accessible and routing to domain services
- [ ] First deploy order for domain services: customers, then vets, then visits
- [ ] Confirmed: the 7 tables exist in RDS (`types`, `owners`, `pets`, `vets`, `specialties`, `vet_specialties`, `visits`) — Spring auto-init from PETPLAT-24 / spec, not Terraform
- [ ] Customers, Visits, Vets services can read/write to RDS
- [ ] GenAI service responds (with valid API key)
- [ ] Admin Server shows all services

---

# EPIC E-10: CI Pipeline (CI-only, ArgoCD handles CD)

**Priority:** P0
**Description:** Two-repo GitHub Actions CI. The app fork builds ARM64 images and pushes to ECR. The platform repo receives `repository_dispatch` and commits the new SHA into `helm-values/{service}.yaml`. ArgoCD (E-17) deploys. OIDC only — no long-lived AWS keys, no `kubectl apply`, no `helm upgrade`. Follow `.claude/rules/pipelines.md`.
**Blocked by:** E-4, E-16
**Blocks:** E-17 (ArgoCD syncs the tags this epic writes)

**Claude E-10 build:** PETPLAT-52, PETPLAT-49, PETPLAT-50. YAML + Terraform only. Do not create GitHub secrets, PATs, or live-apply IAM. Do not verify ArgoCD (E-17). PETPLAT-53 and PETPLAT-54 are parked.

---

### PETPLAT-52: Configure OIDC federation (Terraform)

**Type:** Task
**Priority:** P0
**Epic:** E-10 CI Pipeline
**Story Points:** 3
**Labels:** cicd, github-actions, terraform
**Blocked by:** E-1

**Description:**
Add an account-scoped GitHub Actions OIDC role in Terraform. This is **not** the EKS IRSA OIDC provider. Call the module from **dev only** — creating it in prod as well would duplicate the same IAM role. Prod approval stays on ArgoCD (E-17), not GitHub Environments.

**Operator (not Claude):** `terraform apply` in dev, then set GitHub Secrets on the **app fork** from the outputs. Do not commit secret values.

**Technical Spec:** [CI/CD Pipeline](./technical-spec.md#cicd-pipeline)

**Acceptance Criteria:**
- [ ] Module `terraform/modules/github-oidc/` (`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`)
- [ ] `aws_iam_openid_connect_provider` for `token.actions.githubusercontent.com` (audience `sts.amazonaws.com`) — separate from the EKS OIDC provider
- [ ] IAM role name `petclinic-github-actions-role` (account-scoped, no `{env}` in the name)
- [ ] Trust subject: `repo:{github_org}/{github_app_repo}:ref:refs/heads/main` (values from tfvars, no hardcoded org)
- [ ] Permissions: ECR auth + push/layer upload on `petclinic-dev/*` **and** `petclinic-prod/*` only. No S3, DynamoDB, EKS, or `*/*`
- [ ] Wired from `terraform/environments/dev/` only. **Do not** call this module from prod
- [ ] Root inputs (dev): `github_org`, `github_app_repo` — no defaults, values in `terraform.tfvars`
- [ ] Root output: `github_actions_role_arn`
- [ ] OIDC details stay in `docs/technical-spec.md` and `CLAUDE.md` — no new markdown file
- [ ] `terraform fmt` + `terraform validate` (no apply)

---

### PETPLAT-49: Create build and push pipeline

**Type:** Story
**Priority:** P0
**Epic:** E-10 CI Pipeline
**Story Points:** 5
**Labels:** cicd, github-actions, ecr
**Blocked by:** PETPLAT-52, PETPLAT-20

**Description:**
Create `build-push.yml` in the **application repo fork**. This is the only app-repo file Claude may add (no Java, pom, or Dockerfile edits). Trigger on push to `main`. Build only services whose Maven modules changed; if `docker/` or the parent `pom.xml` changed, build all 8.

Use the app’s Maven Docker profile, then retag `springcommunity/spring-petclinic-{artifact}` to ECR. Push the same SHA to **both** `petclinic-dev` and `petclinic-prod` so one Helm `image.tag` works in both env registries (prod EKS is not required; prod ECR repos are). Then `repository_dispatch` the platform repo.

**Operator (not Claude):** GitHub Secrets on the **app fork**: `AWS_ROLE_ARN`, `AWS_REGION`, `AWS_ACCOUNT_ID`, `PLATFORM_REPO_TOKEN`. First live run is the operator.

**Technical Spec:** [CI/CD Pipeline](./technical-spec.md#cicd-pipeline), [Docker Build](./technical-spec.md#docker-build), [ECR Container Registry](./technical-spec.md#ecr-container-registry)

**Acceptance Criteria:**
- [ ] `.github/workflows/build-push.yml` in the application repo fork only (not the platform repo)
- [ ] Trigger: `on: push: branches: [main]`
- [ ] `permissions:` least privilege — `id-token: write`, `contents: read`
- [ ] Path filter uses **Maven module dirs**: `spring-petclinic-config-server`, `spring-petclinic-discovery-server`, `spring-petclinic-api-gateway`, `spring-petclinic-customers-service`, `spring-petclinic-visits-service`, `spring-petclinic-vets-service`, `spring-petclinic-genai-service`, `spring-petclinic-admin-server`
- [ ] Shared paths `docker/**` and `pom.xml` (repo root) mark all 8 services as changed
- [ ] Matrix builds only services whose filter is true — skip the build job when none changed
- [ ] JDK 17 + Docker Buildx + QEMU (`linux/arm64` on x86 runners)
- [ ] AWS via OIDC: `aws-actions/configure-aws-credentials` with `role-to-assume: ${{ secrets.AWS_ROLE_ARN }}` — no access keys
- [ ] ECR login: `aws-actions/amazon-ecr-login`
- [ ] Per changed service: `./mvnw clean install -P buildDocker -Dcontainer.platform=linux/arm64 -pl spring-petclinic-{service} -am`
- [ ] Retag `springcommunity/spring-petclinic-{artifact}` → `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service}:{sha}` for **env = dev and prod**. Helm name is the short service name (no `spring-petclinic-` prefix)
- [ ] Tag is 7-character SHA (`${GITHUB_SHA::7}`). Never `latest`
- [ ] Trivy **before** push: fail the job on CRITICAL; HIGH warns only; upload the report as a workflow artifact. Honor `.trivyignore` in the app repo if it exists — do not create that file
- [ ] After successful pushes, `repository_dispatch` to the platform repo: event type `app-image-built`, secret `PLATFORM_REPO_TOKEN`, payload `{ "sha": "<7-char>", "services": ["customers-service", ...] }` (Helm names, not Maven dirs)
- [ ] Third-party actions pinned to a commit SHA, not `@v1` / `@latest`
- [ ] No `kubectl`, no `helm upgrade`, no live run required for this story

---

### PETPLAT-50: Create update-image-tags workflow

**Type:** Story
**Priority:** P0
**Epic:** E-10 CI Pipeline
**Story Points:** 5
**Labels:** cicd, github-actions, gitops
**Blocked by:** PETPLAT-49, PETPLAT-107

**Description:**
Create `update-image-tags.yml` in the **platform** repo. Triggered only by `repository_dispatch` from the app workflow (`app-image-built`) — not `workflow_run` (that only works in the same repo). Update `image.tag` with `yq` for services in the payload, commit, push. ArgoCD verification is E-17, not this story.

**Technical Spec:** [CI/CD Pipeline](./technical-spec.md#cicd-pipeline)

**Acceptance Criteria:**
- [ ] `.github/workflows/update-image-tags.yml` in the platform repo (this repo)
- [ ] Trigger: `on: repository_dispatch: types: [app-image-built]`
- [ ] `permissions:` `contents: write` — no AWS, no `id-token`
- [ ] Reads `github.event.client_payload.sha` and `github.event.client_payload.services`
- [ ] `yq -i '.image.tag = "<sha>"' helm-values/{service}.yaml` for each service in the payload only
- [ ] Commit + push: `ci: update image tags to {sha} ({service-list})`
- [ ] No `kubectl apply`, no `helm upgrade`, no `aws eks update-kubeconfig`
- [ ] Do **not** require ArgoCD UI/sync for this story (E-17)
- [ ] Third-party actions pinned to a commit SHA

---

### ~~PETPLAT-51: REMOVED — deploy-to-prod pipeline replaced by ArgoCD~~

_Prod deployment is now handled by ArgoCD (E-17) with manual sync policy. No separate deploy-prod workflow needed. See PETPLAT-114._

---

### PETPLAT-53: Create reusable pipeline templates

**Type:** Task
**Priority:** P2
**Epic:** E-10 CI Pipeline
**Story Points:** 3
**Labels:** cicd, github-actions
**Blocked by:** PETPLAT-49, PETPLAT-50

**Description:**
**Parked — not part of the Claude E-10 build.** Build-push and update-tags live in different repos, so platform reusable workflows cannot be called from the app fork without publishing them. Revisit later if both workflows move to one repo.

**Technical Spec:** [CI/CD Pipeline](./technical-spec.md#cicd-pipeline)

**Acceptance Criteria:**
- [ ] Out of scope for the E-10 Claude pass
- [ ] Do not create `.github/workflows/reusable/` in E-10

---

### PETPLAT-54: Implement rollback strategy

**Type:** Story
**Priority:** P1
**Epic:** E-10 CI Pipeline
**Story Points:** 3
**Labels:** cicd, operations, gitops
**Blocked by:** PETPLAT-50, E-17, PETPLAT-78

**Description:**
**Parked — not part of the Claude E-10 build.** Rollback needs ArgoCD (E-17) and the operations runbook (PETPLAT-78 / E-15). GitOps rollback is: revert the image-tag commit, ArgoCD syncs. Come back after E-17.

**Technical Spec:** [GitOps with ArgoCD](./technical-spec.md#gitops-with-argocd), [CI/CD Pipeline](./technical-spec.md#cicd-pipeline)

**Acceptance Criteria:**
- [ ] Out of scope for the E-10 Claude pass
- [ ] Do not add a new runbook file in E-10

---

# EPIC E-11: Observability

**Priority:** P1
**Description:** In-cluster Prometheus, Grafana, Alertmanager, Loki, Fluent Bit, and Zipkin via Terraform `helm_release`. EBS CSI lives in the EKS module. No CloudWatch. Follow `.claude/rules/observability.md`.
**Blocked by:** E-3 (cluster + add-ons)
**Blocks:** None (E-13 NetworkPolicy must keep Prometheus scrape working)

**Claude E-11 build:** PETPLAT-84, PETPLAT-55, PETPLAT-57, PETPLAT-58, PETPLAT-59, PETPLAT-60, PETPLAT-118, PETPLAT-119. Terraform + Helm YAML, `terraform validate`, `helm lint` / `helm template`. Do **not** apply, port-forward, or send a test Slack/email. PETPLAT-56 and PETPLAT-103 are folded into PETPLAT-55.

---

### PETPLAT-84: EBS CSI Driver and gp3 StorageClass

**Type:** Story
**Priority:** P1
**Epic:** E-11 Observability
**Story Points:** 3
**Labels:** terraform, eks, storage
**Blocked by:** PETPLAT-16

**Description:**
Add EKS managed add-ons and the EBS CSI IRSA role in `terraform/modules/eks/` so Prometheus/Grafana/Loki PVCs can bind. This was the E-3 gap; it is part of the E-11 Claude build.

**Technical Spec:** [EKS Cluster](./technical-spec.md#eks-cluster), [IRSA Roles](./technical-spec.md#irsa-roles), [Terraform Modules](./technical-spec.md#terraform-modules)

**Acceptance Criteria:**
- [ ] `aws_eks_addon` for coredns, kube-proxy, vpc-cni, **aws-ebs-csi-driver**
- [ ] Addon versions from `data.aws_eks_addon_version` (most recent for `cluster_version`), not the string `latest`
- [ ] IRSA `petclinic-{env}-ebs-csi-role`, SA `ebs-csi-controller-sa` in `kube-system`, `AmazonEBSCSIDriverPolicy`
- [ ] StorageClass `gp3` (default, `WaitForFirstConsumer`, type gp3)
- [ ] Input `install_ebs_csi` (true only if the cluster exists)
- [ ] Output `ebs_csi_role_arn`
- [ ] Kubernetes provider on the env root if needed for StorageClass (same exec as Helm)
- [ ] `terraform validate`. Do **not** apply

---

### PETPLAT-55: kube-prometheus-stack (Prometheus, Grafana, Alertmanager)

**Type:** Story
**Priority:** P1
**Epic:** E-11 Observability
**Story Points:** 5
**Labels:** terraform, helm, observability
**Blocked by:** PETPLAT-84

**Description:**
Install kube-prometheus-stack with a gated `helm_release` in the observability module. Includes Grafana datasources (Prometheus + Loki URL), Alertmanager with a blackhole receiver, kube-state-metrics, and node-exporter. Learning-size resources. No public Ingress.

**Operator (not Claude):** apply when `install_observability` is true; port-forward Grafana/Prometheus; `terraform output grafana_admin_password`.

**Technical Spec:** [Observability](./technical-spec.md#observability)

**Acceptance Criteria:**
- [ ] Chart `kube-prometheus-stack` **88.6.2**, repo `https://prometheus-community.github.io/helm-charts`, ns `monitoring`, release name `kube-prometheus-stack`
- [ ] Gated by `install_observability`
- [ ] Scrape jobs for all 8 services as in the spec (`*.petclinic-{env}.svc`)
- [ ] Retention and PVC sizes per env (7d/10Gi vs 15d/50Gi); Grafana PVC 5Gi; storageClass `gp3`
- [ ] Resource requests at or below the spec table (not chart defaults)
- [ ] Grafana password from `random_password`, sensitive output, not in Git
- [ ] Alertmanager default receiver is blackhole — no SMTP/Slack secrets
- [ ] Loki datasource URL `http://loki.monitoring.svc:3100`
- [ ] No Ingress. No live UI check

---

### ~~PETPLAT-56: Deploy Grafana on EKS~~ *(Folded into PETPLAT-55)*

---

### PETPLAT-57: Grafana dashboards (Git)

**Type:** Story
**Priority:** P1
**Epic:** E-11 Observability
**Story Points:** 5
**Labels:** observability, grafana, dashboards
**Blocked by:** PETPLAT-55

**Description:**
Dashboard JSON in Git, provisioned by the stack (sidecar / extra ConfigMaps). Not `k8s/base/`.

**Technical Spec:** [Observability](./technical-spec.md#observability)

**Acceptance Criteria:**
- [ ] `k8s/observability/grafana-dashboards/` — overview, 8 per-service, JVM
- [ ] Wired into kube-prometheus-stack Grafana provisioning
- [ ] No live Grafana click-through for this story

---

### PETPLAT-58: Prometheus alerting rules (Git)

**Type:** Story
**Priority:** P1
**Epic:** E-11 Observability
**Story Points:** 3
**Labels:** observability, prometheus, alerts
**Blocked by:** PETPLAT-55

**Description:**
PrometheusRule YAML for the five spec alerts. kube-state-metrics must stay enabled.

**Technical Spec:** [Observability](./technical-spec.md#observability)

**Acceptance Criteria:**
- [ ] `k8s/observability/prometheus-rules/` (or chart `additionalPrometheusRulesMap`) with ServiceDown, HighErrorRate, HighLatency, PodRestartLoop, HighMemoryUsage
- [ ] Durations and severity labels match the spec
- [ ] Do not require a firing alert for this story

---

### PETPLAT-59: Loki and Fluent Bit

**Type:** Story
**Priority:** P1
**Epic:** E-11 Observability
**Story Points:** 5
**Labels:** terraform, helm, logging
**Blocked by:** PETPLAT-84

**Description:**
Loki SingleBinary + Fluent Bit DaemonSet. No IRSA. Output Host must be `loki.monitoring.svc` port 3100.

**Technical Spec:** [Observability](./technical-spec.md#observability)

**Acceptance Criteria:**
- [ ] Loki chart **18.7.6** from `https://grafana-community.github.io/helm-charts`, release `loki`, ns `monitoring`
- [ ] No MinIO / object storage. PVC 10Gi dev / 50Gi prod. Retention 7d / 30d
- [ ] Fluent Bit chart **0.53.0** from `https://fluent.github.io/helm-charts`, DaemonSet, Loki plugin
- [ ] Loki alert rules from the spec (ruler best-effort on SingleBinary)
- [ ] Gated by `install_observability`
- [ ] No “logs visible in Grafana” AC for Claude

---

### PETPLAT-60: Zipkin chart and Helm env

**Type:** Story
**Priority:** P1
**Epic:** E-11 Observability
**Story Points:** 3
**Labels:** helm, tracing
**Blocked by:** PETPLAT-107, PETPLAT-108

**Description:**
In-repo `helm/zipkin/` + terraform `helm_release` into `tracing`. Set Boot 4 Zipkin env on the five traced services. Do not edit the app repo. Traces in the UI is operator.

**Technical Spec:** [Observability](./technical-spec.md#observability), [Helm Charts](./technical-spec.md#helm-charts)

**Acceptance Criteria:**
- [ ] `helm/zipkin/` Deployment + ClusterIP 9411, image `openzipkin/zipkin`, emptyDir
- [ ] `helm_release` ns `tracing`, `create_namespace = true`, gated by `install_observability`
- [ ] `configData` on api-gateway, customers, visits, vets, genai only: `MANAGEMENT_TRACING_EXPORT_ZIPKIN_ENDPOINT` and `MANAGEMENT_TRACING_SAMPLING_PROBABILITY`
- [ ] `scripts/validate-helm.sh` still passes
- [ ] No live Zipkin UI check

---

### PETPLAT-118: Wire observability into dev

**Type:** Task
**Priority:** P1
**Epic:** E-11 Observability
**Story Points:** 1
**Labels:** terraform, observability, dev
**Blocked by:** PETPLAT-84, PETPLAT-55, PETPLAT-59, PETPLAT-60

**Description:**
Call the observability module from the **dev** root. `install_observability` true only if the cluster exists (same as `install_eso`). Pass `install_ebs_csi` on the EKS module.

**Technical Spec:** [Observability](./technical-spec.md#observability)

**Acceptance Criteria:**
- [ ] `module "observability"` in `terraform/environments/dev/main.tf`
- [ ] Root variables for install flags and chart versions
- [ ] Sensitive output `grafana_admin_password`
- [ ] `terraform validate`. Do **not** apply

---

### PETPLAT-119: Wire observability into prod

**Type:** Task
**Priority:** P1
**Epic:** E-11 Observability
**Story Points:** 1
**Labels:** terraform, observability, prod
**Blocked by:** PETPLAT-84, PETPLAT-55, PETPLAT-59, PETPLAT-60

**Description:**
Same module in **prod**. `install_observability` and `install_ebs_csi` **false** until prod EKS exists.

**Technical Spec:** [Observability](./technical-spec.md#observability)

**Acceptance Criteria:**
- [ ] `module "observability"` in `terraform/environments/prod/main.tf`
- [ ] Plan works without talking to a cluster when install flags are false
- [ ] Do **not** apply

---

### ~~PETPLAT-103: Deploy Alertmanager with notification channels~~ *(Folded into PETPLAT-55 — blackhole receiver; operator adds SMTP/Slack later)*

---

# ~~EPIC E-12: Bastion Host — REMOVED~~

_Bastion host removed from project scope. Not needed for this learning environment:_
- _kubectl access: run locally with `aws eks update-kubeconfig`_
- _RDS debugging: use a debug pod (`kubectl run -it debug --image=mysql:8 -- mysql -h <endpoint>`)_
- _Emergency access: AWS Systems Manager Session Manager (free, no SSH keys)_

_PETPLAT-62, 63, 64, 65 all removed. Saves ~$15/mo per student + eliminates SSH key management._

---

# EPIC E-13: Security & Compliance

**Priority:** P1
**Description:** NetworkPolicies (VPC CNI), ResourceQuotas, Checkov in CI, IAM exception list. PSA, SecurityContext, Trivy, ECR scan, and SG shape are already in place. Follow `.claude/rules/security.md`.
**Blocked by:** E-3 (CNI add-on), E-11 (Prometheus scrape from `monitoring`)
**Blocks:** None

**Claude E-13 build:** PETPLAT-67, PETPLAT-89, PETPLAT-66, PETPLAT-68. Git YAML + Terraform + Checkov workflow. `terraform validate`, `kubectl apply --dry-run=client`. Do **not** apply, do **not** require pods to start, do **not** review ECR CVEs. PETPLAT-69, 70, 71, 101 are folded (already done). PETPLAT-100 is E-15.

---

### PETPLAT-67: NetworkPolicies and VPC CNI policy agent

**Type:** Story
**Priority:** P1
**Epic:** E-13 Security
**Story Points:** 5
**Labels:** k8s, security, networking
**Blocked by:** PETPLAT-38, PETPLAT-55

**Description:**
Default-deny **ingress** in `petclinic-{env}` only. Enable Amazon VPC CNI network policy on the existing `vpc-cni` add-on. No Calico. No default-deny egress.

**Operator (not Claude):** apply YAML after CNI flag is applied; confirm ALB and Prometheus still work.

**Technical Spec:** [Security Controls](./technical-spec.md#security-controls), [EKS Cluster](./technical-spec.md#eks-cluster)

**Acceptance Criteria:**
- [ ] `vpc-cni` add-on `configuration_values` includes `enableNetworkPolicy = "true"` (gated by `install_ebs_csi`)
- [ ] `k8s/security/dev/` and `k8s/security/prod/` NetworkPolicies matching the spec table
- [ ] Gateway 8080 from VPC CIDR (not kube-system) **and** from namespace `monitoring`
- [ ] Domain services from API Gateway pods **and** `monitoring`
- [ ] Admin 9090 from the same namespace **and** `monitoring`
- [ ] Config 8888 and Discovery 8761 from the same namespace
- [ ] No NetworkPolicy on `monitoring` or `tracing`
- [ ] `kubectl apply --dry-run=client` passes. Do **not** apply

---

### PETPLAT-89: ResourceQuota and LimitRange

**Type:** Story
**Priority:** P1
**Epic:** E-13 Security
**Story Points:** 3
**Labels:** k8s, security, governance
**Blocked by:** PETPLAT-38

**Description:**
Quotas on `petclinic-{env}` only, sized for two `t4g.small` nodes. LimitRange defaults match the Helm chart.

**Technical Spec:** [Security Controls](./technical-spec.md#security-controls), [Kubernetes Overlays](./technical-spec.md#kubernetes-overlays)

**Acceptance Criteria:**
- [ ] Dev: 4 CPU, 4Gi, 40 pods
- [ ] Prod: 6 CPU, 6Gi, 50 pods
- [ ] LimitRange default request `100m`/`128Mi`, default limit `500m`/`512Mi`
- [ ] Not applied to `monitoring` / `tracing`
- [ ] `kubectl apply --dry-run=client` passes. Do **not** require a live “pod without requests” test

---

### PETPLAT-66: Checkov in CI

**Type:** Story
**Priority:** P1
**Epic:** E-13 Security
**Story Points:** 3
**Labels:** security, terraform, checkov
**Blocked by:** PETPLAT-11

**Description:**
Checkov on the platform Terraform in GitHub Actions. Skip known accepts (ALB 80/443 internet, operator-CIDR EKS API, node SG self-all, IAM exceptions in the spec). Fix only remaining CRITICAL/HIGH that are not those exceptions.

**Technical Spec:** [Security Controls](./technical-spec.md#security-controls)

**Acceptance Criteria:**
- [ ] `.checkov.yml` (or equivalent) with documented skips
- [ ] `.github/workflows/checkov.yml` on `terraform/**` (and the workflow file). Actions pinned to commit SHA
- [ ] Remaining CRITICAL/HIGH either fixed or skipped with a comment pointing at the spec
- [ ] Do **not** require a pasted scan report as done. Do **not** apply Terraform to “fix” findings

---

### PETPLAT-68: IAM least privilege (exceptions stay)

**Type:** Story
**Priority:** P1
**Epic:** E-13 Security
**Story Points:** 3
**Labels:** security, iam, terraform
**Blocked by:** PETPLAT-16, PETPLAT-26

**Description:**
Confirm custom IRSA stays scoped. Do **not** rewrite AWS managed policies or the vendored LB controller JSON.

**Technical Spec:** [IRSA Roles](./technical-spec.md#irsa-roles), [Security Controls](./technical-spec.md#security-controls)

**Acceptance Criteria:**
- [ ] ESO, ExternalDNS, EBS CSI policies remain resource-scoped
- [ ] No bastion IAM role
- [ ] Spec IAM exception table matches what is in Terraform
- [ ] Do **not** edit the vendored LB controller policy JSON
- [ ] `terraform validate` passes

---

### ~~PETPLAT-69: Enable image vulnerability scanning~~ *(Folded — ECR scan-on-push is PETPLAT-18; Trivy is PETPLAT-49. Console review is operator after images exist.)*

---

### ~~PETPLAT-70: Run Trivy scan on Docker images~~ *(Folded into PETPLAT-49)*

---

### ~~PETPLAT-71: Security group audit~~ *(Folded — SGs already match the spec; do not narrow node self-all)*

---

### ~~PETPLAT-101: Enforce Pod Security Standards~~ *(Folded — namespaces.yaml PSA + Helm SecurityContext already exist)*

---

# EPIC E-14: Scaling & Cost Optimization (Karpenter)

**Priority:** P2
**Description:** Metrics Server add-on, Karpenter (extra nodes, on-demand), AWS Budget alerts. Follow `.claude/rules/karpenter.md`. Does not replace the managed node group.
**Blocked by:** E-3 (cluster + OIDC)
**Blocks:** None

**Claude E-14 build:** PETPLAT-72, PETPLAT-73, PETPLAT-75. Terraform + Git YAML. `terraform validate`, `helm template` / `helm lint`. Do **not** apply, `kubectl top`, or scale-test. PETPLAT-74 (spot) and PETPLAT-102 (live k6) are parked. PETPLAT-76 is folded (cost table is already in the spec).

---

### PETPLAT-72: Install Metrics Server on EKS

**Type:** Task
**Priority:** P1
**Epic:** E-14 Scaling & Cost (Karpenter)
**Story Points:** 2
**Labels:** k8s, scaling
**Blocked by:** PETPLAT-16

**Description:**
EKS managed add-on `metrics-server` so prod HPA (already in Helm) can see CPU. Same add-on gate as the other EKS add-ons.

**Operator (not Claude):** `kubectl top nodes` / `kubectl top pods` after apply.

**Technical Spec:** [EKS Cluster](./technical-spec.md#eks-cluster), [Karpenter (Node Autoscaling)](./technical-spec.md#karpenter-node-autoscaling)

**Acceptance Criteria:**
- [ ] `metrics-server` in `terraform/modules/eks/addons.tf` `for_each` with the other add-ons
- [ ] Version from `data.aws_eks_addon_version` (`most_recent`), never the string `latest`
- [ ] Same `install_ebs_csi` gate. No extra IRSA
- [ ] `terraform validate` passes. Do **not** require `kubectl top` as done

---

### PETPLAT-73: Install Karpenter on EKS

**Type:** Story
**Priority:** P2
**Epic:** E-14 Scaling & Cost (Karpenter)
**Story Points:** 8
**Labels:** k8s, scaling, eks, karpenter
**Blocked by:** PETPLAT-16

**Description:**
Karpenter as extra capacity. Managed node group stays at 2. On-demand only. Namespace `karpenter`. Wire **dev and prod**.

**Operator (not Claude):** apply Helm via Terraform; `kubectl apply` NodePool YAML; scale tests in a throwaway namespace (not `petclinic-dev` — quota is 4 CPU / 4Gi).

**Technical Spec:** [Karpenter Node Autoscaling](./technical-spec.md#karpenter-node-autoscaling), [IRSA Roles](./technical-spec.md#irsa-roles), [Module: karpenter](./technical-spec.md#module-karpenter)

**Acceptance Criteria:**
- [ ] Module `terraform/modules/karpenter/` with `versions.tf`; no `project` default `"petclinic"`
- [ ] `module.karpenter` in `terraform/environments/dev/main.tf` **and** prod
- [ ] IRSA `petclinic-{env}-karpenter-role` for SA `karpenter` / namespace `karpenter`; official 1.14 controller policy JSON vendored; **no** `ec2:*`
- [ ] Instance profile `petclinic-{env}-karpenter-node-profile` on **existing** `module.eks.node_role_arn` — no second node role, no `aws-auth`
- [ ] SQS queue + EventBridge (spot interruption, rebalance, instance state, health)
- [ ] `helm_release` gated by `install_karpenter`: charts `karpenter-crd` **1.14.0** then `karpenter` **1.14.0** (OCI). `settings.clusterName` + `settings.interruptionQueue` = queue **name**
- [ ] `k8s/karpenter/{dev,prod}/` NodePool + EC2NodeClass matching the spec YAML (on-demand; SG `petclinic-{env}-sg-eks-node`; private subnet tags). Do **not** `kubernetes_manifest` them in the Helm apply
- [ ] Managed node group sizes **unchanged** (min/desired 2)
- [ ] `terraform validate` / Helm lint. Do **not** apply. Do **not** require a scale-up/down test

---

### PETPLAT-74: Configure Karpenter NodePool for spot instances in dev

**Type:** Story
**Priority:** P2
**Epic:** E-14 Scaling & Cost (Karpenter)
**Story Points:** 3
**Labels:** k8s, karpenter, cost-optimization
**Blocked by:** PETPLAT-73

**Parked — not this Claude build.** Graviton trial until Dec 2026; spec NodePool is on-demand. PETPLAT-73 already writes the NodePool. Come back after the trial (or when you want spot) and add `"spot"` to `capacity-type`.

**Description:**
Add spot to the existing NodePool. Do not create a second NodePool or a "weight" field for this.

**Technical Spec:** [Karpenter Node Autoscaling](./technical-spec.md#karpenter-node-autoscaling)

**Acceptance Criteria:**
- [ ] Dev NodePool `karpenter.sh/capacity-type` includes `spot` and `on-demand` (operator / later change)
- [ ] Prod stays on-demand unless explicitly changed
- [ ] Live “provisioned a spot instance” is operator

---

### PETPLAT-75: Create CloudWatch budget alerts

**Type:** Story
**Priority:** P2
**Epic:** E-14 Scaling & Cost (Karpenter)
**Story Points:** 3
**Labels:** terraform, cost-optimization, cloudwatch
**Blocked by:** PETPLAT-5

**Description:**
AWS Budgets in each env root. Email from tfvars only.

**Technical Spec:** [Scaling and Cost](./technical-spec.md#scaling-and-cost)

**Acceptance Criteria:**
- [ ] `aws_budgets_budget` in `terraform/environments/{dev,prod}/` (not a new module unless needed)
- [ ] Monthly limit `$200` per env; notify at 50%, 80%, 100%
- [ ] Subscriber: `var.budget_notification_email` (`sensitive = true`) from gitignored `terraform.tfvars`. No address in Git
- [ ] `terraform validate` passes. Do **not** apply. Do **not** send a test email

---

### PETPLAT-76: Document cost breakdown

**Type:** Task
**Priority:** P2
**Epic:** E-14 Scaling & Cost (Karpenter)
**Story Points:** 2
**Labels:** documentation, cost
**Blocked by:** PETPLAT-16, PETPLAT-26

**Folded — cost table already lives in** `docs/technical-spec.md` § Scaling and Cost. PETPLAT-77 links it. Do **not** create `docs/cost.md`.

**Description:**
Document the estimated monthly cost of the full stack.

**Technical Spec:** [Scaling and Cost](./technical-spec.md#scaling-and-cost)

**Acceptance Criteria:**
- [ ] Cost table in the spec (already present)
- [ ] Architecture doc links the spec table (PETPLAT-77)
- [ ] No separate `docs/cost.md`

---

# EPIC E-15: Documentation & Runbooks

**Priority:** P1
**Description:** Operational markdown for handover: architecture, runbook, incident playbook, onboarding, ADRs 0001–0013, monitoring guide, DR plan, compliance checklist. Follow `.claude/rules/docs.md`.
**Blocked by:** Spec + Git for the built epics (Claude does not need a live cluster)
**Blocks:** None

**Claude E-15 build:** PETPLAT-77, 78, 79, 80, 81, 97, 99, 100. **Markdown only.** Do **not** Terraform, Helm install, `kubectl apply`, or `terraform destroy`. Do **not** require PETPLAT-48. Filenames are locked in `.claude/rules/docs.md` (not the old `monitoring-alerting-guide.md` / `disaster-recovery.md`). PETPLAT-91, 92, 98-docs, and 104 are folded into 78/79. PETPLAT-90 is parked (operator live destroy). PETPLAT-76 cost table stays in the spec (architecture links it). No `docs/helm-guide.md`.

---

### PETPLAT-77: Create architecture document

**Type:** Story
**Priority:** P1
**Epic:** E-15 Documentation
**Story Points:** 3
**Labels:** documentation
**Blocked by:** None (write from spec)

**Description:**
Document the infrastructure architecture. Link `docs/technical-spec.md` for ports, quotas, chart versions, and cost — do not copy every table. No `docs/cost.md` (PETPLAT-76 folded).

**Technical Spec:** [Documentation](./technical-spec.md#documentation), [General Project Parameters](./technical-spec.md#general-project-parameters), [Application Services](./technical-spec.md#application-services), [Scaling and Cost](./technical-spec.md#scaling-and-cost)

**Acceptance Criteria:**
- [ ] `docs/architecture.md` (H1, Last Updated, purpose, TOC)
- [ ] Mermaid (or equivalent) diagrams: AWS resources, 8-service topology, VPC/subnets/NAT/ALB
- [ ] Request path: Internet → ALB → api-gateway → services; RDS via customers/visits/vets only
- [ ] GitOps: CI pushes images + tags; ArgoCD syncs Helm. Observability/ESO/LB controller are Terraform Helm, not ArgoCD
- [ ] Env differences: link spec tables (replicas, NAT count, image mutability). Placeholders `{domain}`, `{account}`
- [ ] Cost: link spec Scaling and Cost. Karpenter called out as E-14 / ADR-0009 (not built yet)
- [ ] Technology choices: link ADRs rather than restating them in full

---

### PETPLAT-78: Create operations runbook

**Type:** Story
**Priority:** P1
**Epic:** E-15 Documentation
**Story Points:** 5
**Labels:** documentation, operations
**Blocked by:** None (write from spec; not blocked on PETPLAT-48)

**Description:**
Day-2 operations. Folded: PETPLAT-91 (EKS upgrade), PETPLAT-92 (Terraform state), PETPLAT-98 docs (manual secret rotation). Each procedure uses the When/Who/Time/Steps/Verify/Rollback format in `.claude/rules/docs.md`.

**Technical Spec:** [Documentation](./technical-spec.md#documentation), [GitOps with ArgoCD](./technical-spec.md#gitops-with-argocd), [Observability](./technical-spec.md#observability), [Secrets Management](./technical-spec.md#secrets-management), [EKS Cluster](./technical-spec.md#eks-cluster), [Terraform State Backend](./technical-spec.md#terraform-state-backend)

**Acceptance Criteria:**
- [ ] `docs/runbook.md` and `docs/secret-rotation.md` (no `docs/terraform-ops.md`)
- [ ] Deploy / rollback a service: Git image tag + ArgoCD ApplicationSet. **Not** `helm upgrade --install` or `kubectl apply` on Spring Deployments
- [ ] Restart (`kubectl rollout restart` in `petclinic-{env}`), scale (replicas in `helm-values/` for GitOps; HPA where enabled)
- [ ] Logs: Loki in Grafana Explore (LogQL) and `kubectl logs`. Not CloudWatch
- [ ] RDS: debug pod `kubectl run -it debug --image=mysql:8` in `petclinic-{env}`. No bastion
- [ ] Terraform: `plan` then `apply` from `terraform/environments/{env}`. Destroy procedure documented with hook warnings — do **not** run destroy (PETPLAT-90 is parked)
- [ ] Grafana / Zipkin / ArgoCD: `kubectl port-forward` only. Grafana password: `terraform output grafana_admin_password`
- [ ] NetworkPolicy: `kubectl apply -f k8s/security/{env}/` after VPC CNI (operator). Not ArgoCD
- [ ] EKS upgrade (folded 91): check notes → add-ons → control plane → node groups; pre-check + rollback; schedule
- [ ] Terraform state (folded 92): list / import / `state rm` / `state mv` / S3 versioning rollback / DynamoDB force-unlock; when **not** to use these
- [ ] Secret rotation (folded 98 docs): OpenAI key + RDS password **manual** steps; ESO refresh `1h`; pod restart. **No** `aws_secretsmanager_secret_rotation`

---

### PETPLAT-79: Create incident playbook

**Type:** Story
**Priority:** P1
**Epic:** E-15 Documentation
**Story Points:** 3
**Labels:** documentation, operations
**Blocked by:** None (not blocked on PETPLAT-48)

**Description:**
Failure scenarios plus severity/escalation/RCA (folded PETPLAT-104). Contacts are **roles**, not names or emails. Alertmanager is a blackhole — do not invent Slack/PagerDuty paging.

**Technical Spec:** [Documentation](./technical-spec.md#documentation), [Application Services](./technical-spec.md#application-services), [Observability](./technical-spec.md#observability)

**Acceptance Criteria:**
- [ ] `docs/incident-playbook.md`
- [ ] Scenarios: CrashLoopBackOff; Eureka registration; RDS connection; ECR image pull; node NotReady; high latency/timeouts — each with symptoms, diagnosis commands, resolution
- [ ] SEV1 (down) / SEV2 (degraded) / SEV3 (minor); response targets 15 min / 1 hour / next business day
- [ ] Escalation: L1 on-call engineer → L2 senior engineer → L3 architect/vendor (placeholders only)
- [ ] RCA template: timeline, root cause, contributing factors, action items, prevention
- [ ] Status-update template for stakeholders
- [ ] Point at Grafana/Loki via port-forward; do not claim Alertmanager pages anyone

---

### PETPLAT-80: Create onboarding guide

**Type:** Story
**Priority:** P1
**Epic:** E-15 Documentation
**Story Points:** 3
**Labels:** documentation
**Blocked by:** None (not blocked on PETPLAT-48)

**Description:**
Get a new engineer productive in ≤ 90 minutes from Git + AWS access. Live “open the running app” is operator (PETPLAT-48); document the URL pattern and port-forward fallbacks from spec.

**Technical Spec:** [Documentation](./technical-spec.md#documentation), [General Project Parameters](./technical-spec.md#general-project-parameters), [GitOps with ArgoCD](./technical-spec.md#gitops-with-argocd)

**Acceptance Criteria:**
- [ ] `docs/onboarding.md`
- [ ] Prerequisites: git, AWS CLI, kubectl, terraform, helm, gh — no personal account emails
- [ ] Clone this repo, AWS profile, `aws eks update-kubeconfig` for `petclinic-{env}`
- [ ] View app: `https://petclinic-dev.{domain}` (and prod host). Dashboards: Grafana/Zipkin/ArgoCD port-forward
- [ ] First change: edit Git (values or docs) → push → ArgoCD sync. Not `helm upgrade`
- [ ] Contacts: role placeholders only
- [ ] Estimated time per section (total ≤ 90 minutes of reading/setup)

---

### PETPLAT-81: Create Architecture Decision Records (ADRs)

**Type:** Story
**Priority:** P2
**Epic:** E-15 Documentation
**Story Points:** 3
**Labels:** documentation, adr
**Blocked by:** None

**Description:**
One file per row in the spec ADR Index. **Do not** use the old numbering that put ECR at 0009. Include 0011 and 0012. Write 0009 Karpenter even though E-14 is unbuilt.

**Technical Spec:** [ADR Index](./technical-spec.md#adr-index)

**Acceptance Criteria:**
- [ ] `docs/adr/0001-network-layout.md`
- [ ] `docs/adr/0002-eks-over-ecs.md`
- [ ] `docs/adr/0003-shared-rds.md`
- [ ] `docs/adr/0004-plain-yaml-over-helm.md` — **Superseded by ADR-0007**
- [ ] `docs/adr/0005-github-actions-oidc.md`
- [ ] `docs/adr/0006-single-az-rds.md`
- [ ] `docs/adr/0007-helm-over-plain-yaml.md`
- [ ] `docs/adr/0008-argocd-gitops.md`
- [ ] `docs/adr/0009-karpenter.md` — Karpenter (not ECR)
- [ ] `docs/adr/0010-ecr-private.md`
- [ ] `docs/adr/0011-secrets-manager.md`
- [ ] `docs/adr/0012-externaldns.md`
- [ ] `docs/adr/0013-loki-over-cloudwatch.md`
- [ ] Each ADR: Status, Date **2026-09-02**, Context, Decision, Consequences

---

### PETPLAT-97: Create monitoring guide

**Type:** Task
**Priority:** P1
**Epic:** E-15 Documentation
**Story Points:** 3
**Labels:** documentation, observability, handover
**Blocked by:** None (write from spec + `k8s/observability/`)

**Description:**
What to look at when something is wrong. Filename is **`docs/monitoring-guide.md`**, not `monitoring-alerting-guide.md`.

**Technical Spec:** [Observability](./technical-spec.md#observability)

**Acceptance Criteria:**
- [ ] `docs/monitoring-guide.md`
- [ ] PrometheusRules / dashboards from `k8s/observability/` listed with thresholds as they exist in Git
- [ ] Alertmanager is a **blackhole**. No Slack, PagerDuty, email, or public Grafana URL
- [ ] Access: `kubectl port-forward` for Grafana, Prometheus, Zipkin. Password: `terraform output grafana_admin_password`
- [ ] How to silence in the UI (local port-forward). How to add a rule: Git → `k8s/observability/` (not live kubectl as the source of truth)
- [ ] Loki: Grafana Explore + example LogQL. Zipkin: which five services send traces

---

### PETPLAT-99: Create disaster recovery plan

**Type:** Task
**Priority:** P1
**Epic:** E-15 Documentation
**Story Points:** 5
**Labels:** documentation, disaster-recovery, handover
**Blocked by:** None (not blocked on PETPLAT-90)

**Description:**
Living DR document from the spec. Do **not** wait for a live destroy test. Do **not** write “lessons from PETPLAT-90.” Filename is **`docs/dr-plan.md`**, not `disaster-recovery.md`.

**Technical Spec:** [Documentation](./technical-spec.md#documentation), [RDS Database](./technical-spec.md#rds-database), [Terraform State Backend](./technical-spec.md#terraform-state-backend), [ECR Container Registry](./technical-spec.md#ecr-container-registry)

**Acceptance Criteria:**
- [ ] `docs/dr-plan.md`
- [ ] RTO/RPO (learning targets: RTO ~60 min, RPO = RDS backup window / 1 hour)
- [ ] Backups: RDS automated backups, S3 state versioning, ECR lifecycle
- [ ] Full-stack rebuild procedure (Terraform then ESO/ArgoCD/Helm path as built). Commands for the operator — Claude does not run them
- [ ] RDS PITR procedure
- [ ] Terraform state recovery from S3 versioning
- [ ] Single-region acknowledged; multi-region is a future enhancement
- [ ] Communication: roles, not names. No status-page URL unless it is a placeholder
- [ ] Recommended DR test cadence (quarterly). PETPLAT-90 remains parked

---

### PETPLAT-100: Create compliance checklist

**Type:** Task
**Priority:** P1
**Epic:** E-15 Documentation
**Story Points:** 3
**Labels:** security, compliance, handover
**Blocked by:** None (write from spec + Git; not E-13 YAML)

**Description:**
Handover checklist of controls that exist in Git. **CloudTrail is not deployed** — say that explicitly. RBAC: document IRSA + Helm ServiceAccounts + ArgoCD as they exist; do not invent extra ClusterRoles.

**Technical Spec:** [Security Controls](./technical-spec.md#security-controls), [Documentation](./technical-spec.md#documentation)

**Acceptance Criteria:**
- [ ] `docs/compliance-checklist.md`
- [ ] Encryption at rest: RDS, EBS (default), S3 state, Secrets Manager — as in spec
- [ ] Encryption in transit: TLS at ALB (ACM); in-cluster HTTP documented as-is
- [ ] IAM / IRSA inventory from spec (ESO, LB controller, ExternalDNS, EBS CSI, GitHub OIDC)
- [ ] K8s: PSA on app namespaces, SecurityContext in Helm, NetworkPolicy in `k8s/security/{env}/`, ResourceQuota
- [ ] Audit logging: **CloudTrail not in this stack**. EKS control-plane logs `api`, `audit`, `authenticator` (as in the EKS module). Loki retention as in the observability spec
- [ ] Data classification: owner/pet/visit as sample app PII; stored in RDS `petclinic`; OpenAI key in Secrets Manager
- [ ] Data residency: us-east-1; not EU/GDPR residency
- [ ] Scanning: Checkov workflow, Trivy in app CI, ECR scan-on-push
- [ ] Remediation SLAs: Critical 24h, High 72h, Medium 1 week, Low next sprint

---

### PETPLAT-90: Disaster recovery test — full teardown and rebuild

**Type:** Story
**Priority:** P1
**Epic:** E-15 Documentation
**Story Points:** 5
**Labels:** operations, disaster-recovery, verification
**Blocked by:** PETPLAT-48, PETPLAT-78

**Operator live story — not part of the Claude E-15 build.** Do not `terraform destroy` in this epic. Claude writes rebuild steps in PETPLAT-99 without claiming this test ran.

**Description:**
Execute a full `terraform destroy` of the dev environment and rebuild from scratch to prove the IaC is complete. Parked until the operator chooses to run it.

**Technical Spec:** [Terraform State Backend](./technical-spec.md#terraform-state-backend), [Terraform Modules](./technical-spec.md#terraform-modules)

**Acceptance Criteria:**
- [ ] `terraform destroy` completes for dev (operator)
- [ ] All AWS resources confirmed deleted (no orphans)
- [ ] `terraform apply` recreates the full stack
- [ ] Apps back via ArgoCD; smoke test passes
- [ ] Manual steps documented
- [ ] Time to rebuild documented (target: < 60 minutes)
- [ ] Findings added to runbook / dr-plan

---


### PETPLAT-82: Create CLAUDE.md for petclinic-platform repo

**Type:** Task
**Priority:** P0
**Epic:** E-0 Claude Code Setup
**Story Points:** 3
**Labels:** claude, foundation
**Blocked by:** None

**Description:**
Create a CLAUDE.md in petclinic-platform that gives Claude Code full context about the infrastructure repo. This is the first file created — it establishes conventions before any infrastructure code is written.

**Acceptance Criteria:**
- [ ] `CLAUDE.md` at petclinic-platform root (< 200 lines)
- [ ] Repo purpose and directory layout
- [ ] Terraform conventions (module pattern, naming, state, tags)
- [ ] K8s manifest conventions (labels, probes, resources, secrets)
- [ ] Security rules (non-negotiable, 8 rules)
- [ ] AWS environment details (dev vs prod table)
- [ ] Application services table (8 services, ports, MySQL needs)
- [ ] MCP servers documented
- [ ] Does NOT duplicate workspace-level CLAUDE.md (app details)

---

---

# Additional Stories (Gap Analysis — from PO/Architect/Lead Dev review)

The following stories were identified during the backlog review session to close gaps for a true production-ready deployment.

---

### ~~PETPLAT-83: Define AWS resource tagging strategy~~ *(Removed — redundant with PETPLAT-5 which already covers `default_tags` and tag propagation)*

---

### ~~PETPLAT-84: Manage EKS add-ons via Terraform~~ *(Moved to E-11 — see PETPLAT-84 under Observability)*

---

### PETPLAT-85: Build and push Docker images to ECR (initial)

**Type:** Story
**Priority:** P0
**Epic:** E-4 Container Registry (ECR)
**Story Points:** 3
**Labels:** docker, ecr, deployment
**Blocked by:** PETPLAT-20

**Operator live story — not part of the Claude E-10 build.** First-time manual images so you can deploy before CI runs. CI (PETPLAT-49) handles later builds. Come back when you want images in ECR without waiting on GitHub Actions.

**Description:**
Perform the first-time manual build of all 8 Docker images from the application repo and push them to ECR. This is needed before K8s manifests can be deployed (images must exist in ECR). CI will handle subsequent builds.

**Technical Spec:** [Docker Build](./technical-spec.md#docker-build), [ECR Container Registry](./technical-spec.md#ecr-container-registry)

**Acceptance Criteria:**
- [ ] Application repo cloned locally
- [ ] `./mvnw clean install -P buildDocker` succeeds (all 8 images built)
- [ ] ECR login successful: `aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin {account}.dkr.ecr.us-east-1.amazonaws.com`
- [ ] All 8 images tagged with initial version (e.g., `v1.0.0` or commit SHA)
- [ ] All 8 images pushed to ECR (`{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/{service}:{tag}`)
- [ ] Verified: images visible in AWS ECR Console
- [ ] Documented: the build and push commands for reference

---

### PETPLAT-86: Create reusable smoke test script

**Type:** Story
**Priority:** P1
**Epic:** E-8 K8s Base Manifests
**Story Points:** 3
**Labels:** scripts, testing, verification
**Blocked by:** PETPLAT-48

**Description:**
Create a smoke test script that validates all 8 services are running, healthy, and interconnected. Used after every deployment (manual, CI/CD, or disaster recovery).

**Technical Spec:** [Application Services](./technical-spec.md#application-services)

**Acceptance Criteria:**
- [ ] `scripts/smoke-test.sh` created
- [ ] Accepts namespace as parameter
- [ ] Checks: all 8 deployments have desired replicas ready
- [ ] Checks: Config Server /actuator/health returns UP
- [ ] Checks: Discovery Server /eureka/apps shows all services registered
- [ ] Checks: API Gateway can route to each domain service
- [ ] Checks: customers/visits/vets services can connect to RDS (create + read a test record via API)
- [ ] Returns exit code 0 on success, 1 on failure
- [ ] Output: clear pass/fail per service with error details
- [ ] Runs from within the cluster (kubectl exec) or locally via kubectl

---

### ~~PETPLAT-87: REMOVED — folded into PETPLAT-50~~

_Image-tag updates (`yq` on `helm-values/{service}.yaml`, commit, push) are PETPLAT-50. No separate story._

---

### PETPLAT-88: Add Pod Disruption Budgets for prod

**Type:** Story
**Priority:** P1
**Epic:** E-9 K8s Overlays
**Story Points:** 2
**Labels:** k8s, prod, availability
**Blocked by:** PETPLAT-46

**Description:**
Add PodDisruptionBudgets in the prod overlay. Spec list only (no GenAI, no Admin). YAML + dry-run only. Do not drain nodes.

**Technical Spec:** [Kubernetes Overlays](./technical-spec.md#kubernetes-overlays)

**Acceptance Criteria:**
- [ ] PDB minAvailable=1 for: config-server, discovery-server, api-gateway, customers-service, visits-service, vets-service
- [ ] No PDB for genai-service or admin-server
- [ ] `kubectl apply --dry-run=client -k k8s-reference/overlays/prod` passes

---

### ~~PETPLAT-89: Add resource quotas and limit ranges per namespace~~ *(Moved to E-13 — see PETPLAT-89 under Security)*

---

### ~~PETPLAT-90: Disaster recovery test — full teardown and rebuild~~ *(Parked — operator live destroy; see PETPLAT-90 under E-15)*

---

### ~~PETPLAT-91: Define EKS version upgrade strategy~~ *(Folded into PETPLAT-78 runbook)*

---

### ~~PETPLAT-92: Terraform state management operations guide~~ *(Folded into PETPLAT-78 runbook; no docs/terraform-ops.md)*

---

---

# Additional Stories (Production Readiness & Handover Audit — Session 3)

The following stories were identified during a comprehensive end-to-end audit to ensure the platform is fully production-ready and can be handed over to an internal team.

---

### ~~PETPLAT-97: Create monitoring and alerting guide~~ *(Moved — see PETPLAT-97 under E-15; file is docs/monitoring-guide.md)*

---

### PETPLAT-98: Create secret rotation procedures

**Type:** Task
**Priority:** P1
**Epic:** E-7 Secrets Management (Secrets Manager)
**Story Points:** 3
**Labels:** secrets-manager, operations, security, handover
**Blocked by:** PETPLAT-23, PETPLAT-34

**Markdown is PETPLAT-78 (`docs/secret-rotation.md`) in E-15 — manual rotation only.** Do **not** add `aws_secretsmanager_secret_rotation` in this epic. Live “RDS rotation reconnects services” is operator, not the Claude E-15 build.

**Description:**
Document (and later, if chosen, enable) secret rotation. Secrets Manager can rotate RDS credentials natively; this repo does not turn that on in Terraform for E-15.

**Technical Spec:** [Secrets Management](./technical-spec.md#secrets-management)

**Acceptance Criteria:**
- [ ] Manual procedures in `docs/secret-rotation.md` (E-15 / PETPLAT-78)
- [ ] OpenAI API key: update Secrets Manager, ESO syncs, restart genai pod
- [ ] RDS password: manual rotation documented (no Terraform rotation resource in E-15)
- [ ] ESO refresh interval (`1h`) and pod restart requirements documented
- [ ] Verification steps documented
- [ ] Operator later: optional native RDS rotation + reconnect test (not Claude E-15)

---

### ~~PETPLAT-99: Create disaster recovery plan~~ *(Moved — see PETPLAT-99 under E-15; file is docs/dr-plan.md; not blocked on PETPLAT-90)*

---

### ~~PETPLAT-100: Create compliance checklist~~ *(Moved to E-15)*

---

### ~~PETPLAT-101: Enforce Pod Security Standards~~ *(Folded — namespaces.yaml PSA + Helm SecurityContext already exist)*

---

### PETPLAT-102: Create load testing framework

**Type:** Story
**Priority:** P1
**Epic:** E-14 Scaling & Cost (Karpenter)
**Story Points:** 5
**Labels:** testing, performance, capacity
**Blocked by:** PETPLAT-48

**Parked — not part of the Claude E-14 build.** Needs a live app (PETPLAT-48). Scripts in Git are optional later; baseline RPS/p99 is operator.

**Description:**
Load test scripts and a baseline against dev. Not Terraform/Karpenter.

**Technical Spec:** [Application Services](./technical-spec.md#application-services), [Scaling and Cost](./technical-spec.md#scaling-and-cost)

**Acceptance Criteria:**
- [ ] Tool chosen (k6 recommended)
- [ ] Scripts in `scripts/load-tests/`
- [ ] Scenarios: list owners, create visit, get vets, gateway routing
- [ ] Baseline results documented (operator, live cluster)
- [ ] Bottlenecks and capacity notes

---

### ~~PETPLAT-103: Deploy Alertmanager with notification channels~~ *(Folded into PETPLAT-55)*

---

### ~~PETPLAT-104: Add incident escalation paths and RCA template~~ *(Folded into PETPLAT-79)*

---

### ~~PETPLAT-105: REMOVED — folded into PETPLAT-49~~

_Trivy (fail on CRITICAL, HIGH warn, artifact upload) is an acceptance criterion on PETPLAT-49. No separate story._

---

### ~~PETPLAT-106: Implement Terraform drift detection~~ *(Removed — Day-2 operations task, requires CI pipeline from Section 11. Covered naturally in Section 18 lecture 18.4)*

---

# EPIC E-16: Helm Charts

**Priority:** P0
**Description:** Create a generic Helm chart for all 8 Petclinic services and per-service / per-env values. Copy replica, HPA, and PDB settings from E-9 overlays. Write chart + values + `helm template` / dry-run only. Do **not** `helm upgrade --install` on a cluster. Do **not** delete `k8s/base/` or `k8s-reference/`. Follow `.claude/rules/helm.md`.
**Blocked by:** E-8, E-9
**Blocks:** E-17 (ArgoCD deploys Helm charts)

**Image:** `image.registry` in the env file (`ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}` — ACCOUNT from Terraform output `ecr_registry`). `image.name` in the service file. `image.tag` is `TAG` until CI. Never `latest`. Never hardcode an AWS account ID.

---

### PETPLAT-107: Create generic Helm chart for Petclinic services

**Type:** Story
**Priority:** P0
**Epic:** E-16 Helm Charts
**Story Points:** 8
**Labels:** helm, k8s
**Blocked by:** PETPLAT-38 through PETPLAT-47, PETPLAT-88

**Description:**
Create a generic, reusable Helm chart at `helm/petclinic-service/` that can deploy any of the 8 Petclinic microservices. Templates: Deployment, Service, ConfigMap, ServiceAccount, HPA, PDB. Per-service differences come from values files.

Replica count: use `.Values.replicaCount`, then `.Values.replicaOverrides.{service-name}` if set (prod GenAI and Admin stay at 1). HPA/PDB templates honor `.Values.autoscaling.enabled` and `.Values.podDisruptionBudget.enabled` per service — do not enable them globally in a way that covers config-server, discovery-server, or admin-server (HPA) or genai-service / admin-server (PDB).

**Technical Spec:** [Helm Charts](./technical-spec.md#helm-charts)

**Acceptance Criteria:**
- [ ] Chart at `helm/petclinic-service/` with Chart.yaml, values.yaml, templates/, `_helpers.tpl`
- [ ] Templates: deployment.yaml, service.yaml, configmap.yaml, serviceaccount.yaml, hpa.yaml, pdb.yaml
- [ ] HPA and PDB templates render only when enabled in values
- [ ] Chart honors `replicaOverrides` so a global prod `replicaCount: 2` does not force GenAI/Admin to 2
- [ ] Image: `{{ .Values.image.registry }}/{{ .Values.image.name }}:{{ .Values.image.tag }}`
- [ ] Probes match E-8: startupProbe plus readiness/liveness. Config Server uses `/actuator/health` for all three. Others: startup `/actuator/health`, readiness `/actuator/health/readiness`, liveness `/actuator/health/liveness`
- [ ] SecurityContext from spec. Init containers from values
- [ ] Labels: app.kubernetes.io/name, part-of=petclinic, managed-by=Helm, component
- [ ] `helm lint helm/petclinic-service/` passes
- [ ] No live `helm install` / `helm upgrade`

---

### PETPLAT-108: Create per-service Helm values files

**Type:** Story
**Priority:** P0
**Epic:** E-16 Helm Charts
**Story Points:** 5
**Labels:** helm, k8s
**Blocked by:** PETPLAT-107

**Description:**
Create per-service values at `helm-values/{service}.yaml`. Ports, profiles, init containers, secrets, HPA/PDB flags, and `image.name` live here. `image.registry` is **not** in these files (env file). Copy E-8/E-9 settings. Do not set `GIT_REPO` or `DISCOVERY_SERVER_URL`.

**Technical Spec:** [Helm Charts](./technical-spec.md#helm-charts), [Application Services](./technical-spec.md#application-services)

**Acceptance Criteria:**
- [ ] Files for all 8 services under `helm-values/`
- [ ] `image.name` is the service name only (e.g. `config-server`). Tag `TAG`
- [ ] Ports: 8888, 8761, 8080, 8081, 8082, 8083, 8084, 9090
- [ ] Profiles: config/discovery/gateway/admin `docker`; customers/visits `docker,mysql`; vets `docker,mysql,production`; genai `docker,production`
- [ ] DB services: SPRING_DATASOURCE_URL placeholder `jdbc:mysql://{rds-endpoint}:3306/petclinic`; secrets `rds-credentials` keys `username`/`password`
- [ ] GenAI: secret `openai-api-key` key `OPENAI_API_KEY`
- [ ] CONFIG_SERVER_URL for every service except config-server does not need it as a client; still set where E-8 did
- [ ] Init: config-server none; discovery wait-for-config only; all others wait-for-config and wait-for-discovery
- [ ] `autoscaling.enabled: true` only on api-gateway, customers, visits, vets, genai (with E-9 min/max). False on config, discovery, admin
- [ ] `podDisruptionBudget.enabled: true` only on config, discovery, gateway, customers, visits, vets. False on genai and admin
- [ ] API Gateway CPU 200m/1000m; others 100m/500m; memory 128Mi/512Mi
- [ ] `helm template` with each service file + `helm-values/dev.yaml` renders

---

### PETPLAT-109: Create per-environment Helm values files

**Type:** Story
**Priority:** P0
**Epic:** E-16 Helm Charts
**Story Points:** 3
**Labels:** helm, k8s, environments
**Blocked by:** PETPLAT-107, PETPLAT-45, PETPLAT-46, PETPLAT-47, PETPLAT-88

**Description:**
Create `helm-values/dev.yaml` and `helm-values/prod.yaml`. Env files set namespace, `image.registry`, and replicaCount. Do **not** set a global `autoscaling.enabled: true` or `podDisruptionBudget.enabled: true` in prod.yaml (that would HPA/PDB every service). Service files already flag which services get HPA/PDB. Dev.yaml **must** set both to false so they stay off in dev (env file is merged last).

Do not change CPU/memory from E-8.

**Technical Spec:** [Helm Charts](./technical-spec.md#helm-charts), [Kubernetes Overlays](./technical-spec.md#kubernetes-overlays)

**Acceptance Criteria:**
- [ ] `helm-values/dev.yaml`: namespace `petclinic-dev`; `replicaCount: 1`; `autoscaling.enabled: false`; `podDisruptionBudget.enabled: false`; `image.registry: ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev`
- [ ] `helm-values/prod.yaml`: namespace `petclinic-prod`; `replicaCount: 2`; `replicaOverrides: { genai-service: 1, admin-server: 1 }`; `image.registry: ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/petclinic-prod`; do **not** globally enable HPA/PDB
- [ ] ACCOUNT is a placeholder — replace from Terraform output `ecr_registry` (host) + `/petclinic-{env}`. Never hardcode an account ID
- [ ] Resource requests/limits not overridden here (keep E-8)
- [ ] Merge: `-f helm-values/{service}.yaml -f helm-values/{env}.yaml` (env last)
- [ ] `helm template` with each service + each env: prod GenAI/Admin replicas=1; prod HPA only on gateway/customers/visits/vets/genai; prod PDB only on the six E-9 services

---

### PETPLAT-110: Test Helm template rendering and validate output

**Type:** Task
**Priority:** P0
**Epic:** E-16 Helm Charts
**Story Points:** 3
**Labels:** helm, testing
**Blocked by:** PETPLAT-108, PETPLAT-109

**Description:**
Validate Helm rendering for all 8 services × both envs. Dry-run only — do **not** `helm upgrade --install` or live `kubectl apply`.

**Technical Spec:** [Helm Charts](./technical-spec.md#helm-charts)

**Acceptance Criteria:**
- [ ] `helm lint helm/petclinic-service/` passes
- [ ] `helm template` for each of the 8 services with dev values and with prod values
- [ ] `kubectl apply --dry-run=client` passes on all rendered templates
- [ ] Prod render: GenAI and Admin replicas=1; no HPA on config/discovery/admin; no PDB on genai/admin
- [ ] Script at `scripts/validate-helm.sh` (optional `--env` / `--service` filters)
- [ ] No live install

---

### PETPLAT-111: Document Helm chart usage and conventions

**Type:** Task
**Priority:** P0
**Epic:** E-16 Helm Charts
**Story Points:** 3
**Labels:** helm, documentation
**Blocked by:** PETPLAT-110

**Already satisfied during E-16** (spec + `CLAUDE.md` + `.claude/rules/helm.md`). Do **not** create `docs/helm-guide.md` in E-15.

**Description:**
Helm usage is documented in the spec and Claude rules, not a separate guide.

**Technical Spec:** [Helm Charts](./technical-spec.md#helm-charts)

**Acceptance Criteria:**
- [ ] Helm section in `docs/technical-spec.md` matches the chart (done)
- [ ] `CLAUDE.md` Helm conventions match (done)
- [ ] `.claude/rules/helm.md` matches the chart (done)
- [ ] No `docs/helm-guide.md`

---

---

# EPIC E-17: GitOps with ArgoCD

**Priority:** P0
**Description:** Git YAML for ArgoCD on **each** EKS cluster (dev and prod are separate clusters). Same install manifests; `applications/dev/` goes only on the dev cluster, `applications/prod/` only on prod. ArgoCD deploys the Helm chart with multi-source values. CI never `kubectl apply`. Follow `.claude/rules/argocd.md`.
**Blocked by:** E-3 (EKS), E-7 (ESO CRs), E-8 (namespaces), E-16 (Helm)
**Blocks:** None (PETPLAT-116 needs E-10 tags + a live cluster)

**Claude E-17 build:** PETPLAT-112, PETPLAT-113, PETPLAT-114, PETPLAT-115. YAML + `kubectl kustomize` / `kubectl apply --dry-run=client` only. Do **not** live-apply, port-forward, change the admin password, or create ArgoCD IRSA. PETPLAT-116 is parked.

---

### PETPLAT-112: Install ArgoCD manifests (Git)

**Type:** Story
**Priority:** P0
**Epic:** E-17 GitOps with ArgoCD
**Story Points:** 5
**Labels:** k8s, argocd, gitops
**Blocked by:** PETPLAT-16

**Description:**
Put a **pinned** non-HA official install behind Kustomize at `k8s/argocd/install/`. Same overlay is applied to **each** cluster by the operator later. Do not vendor a rewritten copy of every upstream object — reference the pinned `install.yaml` URL. Do not use `ha/install.yaml`.

**Operator (not Claude):** `kubectl apply -k k8s/argocd/install/` on the **dev** cluster when you are ready (and on prod when that cluster exists). Retrieve the admin password from `argocd-initial-admin-secret` — never commit it. If the GitHub repo is private, add a repository Secret in namespace `argocd` (PAT/SSH/GitHub App).

**Technical Spec:** [GitOps with ArgoCD](./technical-spec.md#gitops-with-argocd)

**Acceptance Criteria:**
- [ ] `k8s/argocd/install/kustomization.yaml` + `namespace.yaml`
- [ ] Kustomize `resources` pin **Argo CD v3.5.2** non-HA: `https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml`
- [ ] `namespace: argocd` on the Kustomization
- [ ] No HA install, no Helm `helm_release` for ArgoCD, no Terraform for ArgoCD, no `petclinic-{env}-argocd-role`
- [ ] `kubectl kustomize k8s/argocd/install/` succeeds
- [ ] Do **not** `kubectl apply` on a cluster

---

### PETPLAT-113: Dev ApplicationSet

**Type:** Story
**Priority:** P0
**Epic:** E-17 GitOps with ArgoCD
**Story Points:** 5
**Labels:** k8s, argocd, gitops, dev
**Blocked by:** PETPLAT-112, PETPLAT-107, PETPLAT-108, PETPLAT-109

**Description:**
One **ApplicationSet** (not 8 copied Application files) for the eight services on the **dev cluster**. In-cluster destination only. Multi-source Helm so values come from `helm-values/` via `$values` (do **not** use `../../helm-values/`).

**Operator (not Claude):** apply this set on the **dev** cluster only, after namespaces + ESO CRs. Do not apply it on prod.

**Technical Spec:** [GitOps with ArgoCD](./technical-spec.md#gitops-with-argocd), [Helm Charts](./technical-spec.md#helm-charts)

**Acceptance Criteria:**
- [ ] `k8s/argocd/applications/dev/applicationset.yaml`
- [ ] List generator of the 8 Helm service names
- [ ] Application name `{service}-dev`; labels `environment: dev`, `app.kubernetes.io/part-of: petclinic`, `app.kubernetes.io/managed-by: argocd`
- [ ] `spec.project: petclinic-dev`
- [ ] Multi-source: chart `helm/petclinic-service` + `ref: values` on the same repo; `valueFiles` (env last): `$values/helm-values/{service}.yaml`, `$values/helm-values/dev.yaml`
- [ ] `helm.releaseName` is the service name
- [ ] `repoURL: https://github.com/GITHUB_ORG/petclinic-platform.git` — placeholder, never invent an org
- [ ] `targetRevision: main`
- [ ] Destination: `https://kubernetes.default.svc`, namespace `petclinic-dev`
- [ ] `syncPolicy.automated` with `prune: true`, `selfHeal: true`
- [ ] `syncOptions` include `CreateNamespace=true`
- [ ] Do **not** require ArgoCD UI or a live sync for this story

---

### PETPLAT-114: Prod ApplicationSet

**Type:** Story
**Priority:** P0
**Epic:** E-17 GitOps with ArgoCD
**Story Points:** 5
**Labels:** k8s, argocd, gitops, prod
**Blocked by:** PETPLAT-112, PETPLAT-107, PETPLAT-108, PETPLAT-109

**Description:**
Same ApplicationSet pattern as PETPLAT-113 for the **prod cluster**. **No** `automated` block — manual sync only. Apply this folder on prod only; it must not land on the dev cluster.

**Operator (not Claude):** apply on the prod cluster when it exists. First sync is `argocd app sync` / UI, not CI.

**Technical Spec:** [GitOps with ArgoCD](./technical-spec.md#gitops-with-argocd), [Helm Charts](./technical-spec.md#helm-charts)

**Acceptance Criteria:**
- [ ] `k8s/argocd/applications/prod/applicationset.yaml`
- [ ] Same generator, multi-source values, placeholders, and `releaseName` as dev
- [ ] Application name `{service}-prod`; labels `environment: prod`
- [ ] `spec.project: petclinic-prod`
- [ ] Values: `$values/helm-values/{service}.yaml` then `$values/helm-values/prod.yaml`
- [ ] Destination namespace `petclinic-prod`, in-cluster server
- [ ] **No** `syncPolicy.automated` (manual). `CreateNamespace=true` is still allowed
- [ ] Do **not** require a live prod cluster or UI for this story

---

### PETPLAT-115: AppProjects (destination lock)

**Type:** Task
**Priority:** P0
**Epic:** E-17 GitOps with ArgoCD
**Story Points:** 3
**Labels:** argocd, security, rbac
**Blocked by:** PETPLAT-112

**Description:**
Lock each ApplicationSet to one namespace via **AppProject**. Per-cluster install already keeps prod apps off the dev cluster — do not invent Dex/SSO, local htpasswd users, or a password-change procedure in Git.

**Technical Spec:** [GitOps with ArgoCD](./technical-spec.md#gitops-with-argocd)

**Acceptance Criteria:**
- [ ] `k8s/argocd/projects/petclinic-dev.yaml` — destinations only `petclinic-dev` on `https://kubernetes.default.svc`; `sourceRepos` is the platform repo URL placeholder
- [ ] `k8s/argocd/projects/petclinic-prod.yaml` — same for `petclinic-prod`
- [ ] Optional Kustomize patch `k8s/argocd/install/argocd-rbac-cm-patch.yaml` only if needed to keep default policy; no new markdown, no SSO section
- [ ] No ArgoCD IRSA, no admin password in Git, no extra docs file

---

### PETPLAT-116: Test GitOps loop end-to-end

**Type:** Task
**Priority:** P0
**Epic:** E-17 GitOps with ArgoCD
**Story Points:** 3
**Labels:** argocd, gitops, testing
**Blocked by:** PETPLAT-113, PETPLAT-114, PETPLAT-50

**Description:**
**Parked — not part of the Claude E-17 build.** Operator live test after images exist (E-10), namespaces + ESO are applied, and ArgoCD is running. Same idea as PETPLAT-48.

**Technical Spec:** [GitOps with ArgoCD](./technical-spec.md#gitops-with-argocd), [CI/CD Pipeline](./technical-spec.md#cicd-pipeline)

**Acceptance Criteria:**
- [ ] Out of scope for the Claude E-17 pass
- [ ] Come back after a live ArgoCD on dev: tag commit → auto-sync; prod stays manual
- [ ] Do not add a new runbook file here

---

---

## Summary

| Priority | Epics | Stories/Tasks |
|----------|-------|---------------|
| P0 | Claude Code Setup, Foundation, VPC, EKS, ECR, RDS, Secrets (Secrets Manager), K8s Base, CI Pipeline, Helm Charts, GitOps (ArgoCD) | 63 |
| P1 | DNS, K8s Overlays, Observability, Security, Docs | 38 |
| P2 | Scaling & Cost (Karpenter) | 6 |
| **Total** | **17 epics (E-12 removed = 16 active)** | **107 stories/tasks** |

**Estimated total story points:** ~341
