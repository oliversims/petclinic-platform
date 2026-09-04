# Technical Specification — Petclinic Platform

> **Purpose:** Single source of truth for all infrastructure values. Jira stories reference sections of this document via anchor links. Read the relevant section before implementing any story.
>
> **Convention:** Dev environment is built during the course. Prod values are defined here but implementation is a **student assignment** unless noted otherwise.

---

## Table of Contents

1. [General Project Parameters](#general-project-parameters)
2. [Terraform State Backend](#terraform-state-backend)
3. [VPC Network Design](#vpc-network-design)
4. [Security Groups](#security-groups)
5. [EKS Cluster](#eks-cluster)
6. [ECR Container Registry](#ecr-container-registry)
7. [RDS Database](#rds-database)
8. [Secrets Management](#secrets-management)
9. [DNS and Ingress](#dns-and-ingress)
10. [Application Services](#application-services)
11. [Kubernetes Manifests](#kubernetes-manifests)
12. [Kubernetes Overlays](#kubernetes-overlays)
13. [CI/CD Pipeline](#cicd-pipeline)
14. [Observability](#observability)
15. [IRSA Roles](#irsa-roles)
16. [Security Controls](#security-controls)
17. [Scaling and Cost](#scaling-and-cost)
18. [Docker Build](#docker-build)
19. [Terraform Modules](#terraform-modules)
20. [Helm Charts](#helm-charts)
21. [GitOps with ArgoCD](#gitops-with-argocd)
22. [Karpenter (Node Autoscaling)](#karpenter-node-autoscaling)
23. [Documentation](#documentation)
24. [ADR Index](#adr-index)

---

## General Project Parameters

| Parameter | Value |
|-----------|-------|
| AWS Region | `us-east-1` |
| Availability Zones | `us-east-1a`, `us-east-1b` |
| Project Name | `petclinic` |
| Naming Convention | `petclinic-{env}-{resource}` (e.g., `petclinic-dev-vpc`, `petclinic-prod-eks`) |
| Environments | `dev`, `prod` |
| Terraform Version | `>= 1.6.0` |
| AWS Provider Version | `~> 5.0` |
| Spring Boot Version | `4.0.1` (parent POM: `org.springframework.boot:spring-boot-starter-parent`) |
| Spring Cloud Version | `2025.1.0` (Oakwood) |
| Java Version | `17` |

### Required Tags (All AWS Resources)

| Tag Key | Value | Purpose |
|---------|-------|---------|
| `Project` | `petclinic` | Cost allocation, resource grouping |
| `Environment` | `dev` or `prod` | Environment identification |
| `ManagedBy` | `terraform` | Drift detection, ownership |

These tags are applied via `default_tags` in the AWS provider configuration. Modules accept an additional `tags` variable to merge service-specific tags.

### Optional Tags

| Tag Key | Example | When Used |
|---------|---------|-----------|
| `Service` | `customers-service` | Per-service resources (ECR repos, log groups) |
| `Component` | `networking`, `compute` | Module-level classification |

---

## Terraform State Backend

| Parameter | Value |
|-----------|-------|
| Backend Type | S3 with DynamoDB locking |
| S3 Bucket | `petclinic-terraform-state-{account-id}` |
| S3 Encryption | AES256 (SSE-S3) |
| S3 Versioning | Enabled |
| S3 Public Access | All blocked (4 settings) |
| DynamoDB Table | `petclinic-terraform-locks` |
| DynamoDB Partition Key | `LockID` (String) |

### Per-Environment State Keys

| Environment | State Key | Purpose |
|-------------|-----------|---------|
| Dev | `petclinic/dev/terraform.tfstate` | Dev infrastructure state |
| Prod | `petclinic/prod/terraform.tfstate` | Prod infrastructure state |

### Bootstrap Script

`scripts/bootstrap-state.sh` provisions the S3 bucket and DynamoDB table. It is:
- Idempotent (safe to run multiple times)
- Accepts `--region` parameter (default: `us-east-1`)
- Run once before `terraform init`

---

## VPC Network Design

### Architecture Decision

Production layout: **public edge, private compute/data**. NAT count is per environment: **1 NAT in dev**, **2 NAT (one per AZ) in prod**. See [ADR-0001](#adr-index).

```
Internet → IGW → public subnets (ALB, NAT Gateways)
                      ↓
                 private subnets (EKS nodes, RDS) — no public IPs
                      ↓
                 NAT Gateway in the same AZ (outbound: ECR, patches, APIs)
```

### CIDR Allocation

| Parameter | Dev | Prod |
|-----------|-----|------|
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Public subnet AZ a | `10.0.1.0/24` | `10.1.1.0/24` |
| Public subnet AZ b | `10.0.2.0/24` | `10.1.2.0/24` |
| Private subnet AZ a | `10.0.11.0/24` | `10.1.11.0/24` |
| Private subnet AZ b | `10.0.12.0/24` | `10.1.12.0/24` |
| Availability Zones | `us-east-1a`, `us-east-1b` | `us-east-1a`, `us-east-1b` |

CIDRs are non-overlapping to allow future VPC peering if needed.

### What lives where

| Subnet | Resources | Public IP |
|--------|-----------|-----------|
| Public (2 AZs) | ALB, NAT Gateway (+ EIP) | yes |
| Private (2 AZs) | EKS nodes, RDS | no |

### VPC Settings

| Setting | Value |
|---------|-------|
| DNS Support | `true` |
| DNS Hostnames | `true` |
| Internet Gateway | 1 per VPC, attached |
| Public route table | 1 table, `0.0.0.0/0` → IGW, **both public subnets associated** |
| NAT Gateway | **Dev: 1** (in public AZ a). Both private subnets route outbound through it. **Prod: 2** (one per AZ, HA). EIP per NAT. |
| Private route tables | 1 per AZ. Dev: both `0.0.0.0/0` → the single NAT. Prod: each `0.0.0.0/0` → that AZ's NAT. Matching private subnet associated. |
| VPC Endpoints | **S3 Gateway** (free). Associate with **private** route tables. No Interface endpoints in E-2 (those cost money; HTTPS APIs still use NAT). |

### Subnet Settings

| Setting | Public | Private |
|---------|--------|---------|
| `map_public_ip_on_launch` | `true` | `false` |
| AZ distribution | 1 subnet per AZ (2 AZs) | 1 subnet per AZ (2 AZs) |

### Resource Names (`Name` tag)

| Resource | Name |
|----------|------|
| VPC | `petclinic-{env}-vpc` |
| Public subnet AZ a / b | `petclinic-{env}-subnet-public-a` / `-public-b` |
| Private subnet AZ a / b | `petclinic-{env}-subnet-private-a` / `-private-b` |
| IGW | `petclinic-{env}-igw` |
| Public route table | `petclinic-{env}-rt-public` |
| Private route table AZ a / b | `petclinic-{env}-rt-private-a` / `-private-b` |
| NAT Gateway AZ a / b | `petclinic-{env}-nat-a` always; `-nat-b` in **prod only** |
| EIP for NAT | `petclinic-{env}-nat-eip-a` always; `-eip-b` in **prod only** |
| S3 Gateway endpoint | `petclinic-{env}-vpce-s3` |

### EKS Subnet Tags (Required)

| Tag Key | Public subnets | Private subnets | Purpose |
|---------|----------------|-----------------|---------|
| `kubernetes.io/cluster/petclinic-{env}` | `shared` | `shared` | EKS cluster association |
| `kubernetes.io/role/elb` | `1` | — | Internet-facing ALB |
| `kubernetes.io/role/internal-elb` | — | `1` | Internal load balancers |

### S3 Gateway VPC endpoint (E-2)

Free **Gateway** endpoint (`com.amazonaws.us-east-1.s3`). Prefix-list routes are added to **both private route tables** so S3 (including ECR image layers in S3) does not use NAT.

- Does **not** replace NAT: ECR API, Secrets Manager, and other HTTPS APIs still go out via NAT.
- No Interface endpoints in E-2 (hourly charge).

---

## Security Groups

Four custom security groups **in the VPC module** (not a separate module). Subnets are the first perimeter; SGs still apply on every ENI. The only `0.0.0.0/0` **ingress** is ALB 80/443.

### Names (`Name` tag)

| SG | Name |
|----|------|
| ALB | `petclinic-{env}-sg-alb` |
| EKS cluster | `petclinic-{env}-sg-eks-cluster` |
| EKS node | `petclinic-{env}-sg-eks-node` |
| RDS | `petclinic-{env}-sg-rds` |

### Default VPC security group

Do **not** use the AWS default SG. Leave it with no extra rules (or strip all rules). Workloads use only the four named SGs above.

### EKS Cluster Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| API Server access from nodes | Ingress | TCP | 443 | EKS Node SG |
| Control plane egress | Egress | All | All | `0.0.0.0/0` |

### EKS Node Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| All from cluster SG | Ingress | All | All | EKS Cluster SG |
| Inter-node communication | Ingress | All | All | Self (EKS Node SG) |
| Kubelet API from cluster | Ingress | TCP | 10250 | EKS Cluster SG |
| NodePort services | Ingress | TCP | 30000-32767 | ALB SG |
| All outbound (via NAT from private subnets) | Egress | All | All | `0.0.0.0/0` |

### RDS Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| MySQL from nodes | Ingress | TCP | 3306 | EKS Node SG |
| No other ingress | — | — | — | — |

**Critical:** RDS SG allows `3306` from EKS Node SG **only**. Never `0.0.0.0/0`.

### ALB Security Group

| Rule | Type | Protocol | Port | Source/Destination |
|------|------|----------|------|--------------------|
| HTTP from internet | Ingress | TCP | 80 | `0.0.0.0/0` |
| HTTPS from internet | Ingress | TCP | 443 | `0.0.0.0/0` |
| To nodes (target group) | Egress | TCP | 30000-32767 | EKS Node SG |
| Health checks to nodes | Egress | TCP | 8080 | EKS Node SG |

### Outputs

`eks_cluster_sg_id`, `eks_node_sg_id`, `rds_sg_id`, `alb_sg_id`

---

## EKS Cluster

### Cluster Configuration

| Parameter | Dev | Prod |
|-----------|-----|------|
| Cluster Name | `petclinic-dev` | `petclinic-prod` |
| Kubernetes Version | `1.34` | `1.34` |
| API Server Endpoint | Public + private | Public + private |
| `endpoint_public_access` | `true` (hardcoded) | `true` (hardcoded) |
| `endpoint_private_access` | `true` (hardcoded) | `true` (hardcoded) |
| Public Access CIDRs | From `terraform.tfvars` (`<your-public-ipv4>/32`). No default. | From `terraform.tfvars` (`<your-public-ipv4>/32`). No default. |
| Authentication Mode | `API_AND_CONFIG_MAP` | `API_AND_CONFIG_MAP` |
| kubectl access | Access entry for `data.aws_caller_identity.current` + `AmazonEKSClusterAdminPolicy` (cluster-scoped). Do not manage `aws-auth` via Terraform. | Access entry for `data.aws_caller_identity.current` + `AmazonEKSClusterAdminPolicy` (cluster-scoped). Do not manage `aws-auth` via Terraform. |
| Cluster Logging | `api`, `audit`, `authenticator` | `api`, `audit`, `authenticator` |
| Subnets | Private (AZ a + b) for control plane and nodes. ALB uses public subnets. | Private (AZ a + b) for control plane and nodes. ALB uses public subnets. |

### Cluster IAM Role

| Policy | Type |
|--------|------|
| `AmazonEKSClusterPolicy` | AWS Managed |

### OIDC Provider

Created from EKS cluster identity issuer URL. Required for IRSA (IAM Roles for Service Accounts).

### Managed Node Group

| Parameter | Dev | Prod |
|-----------|-----|------|
| Node Group Name | `petclinic-dev-nodes` | `petclinic-prod-nodes` |
| Instance Types | `["t4g.small"]` | `["t4g.small"]` |
| Architecture | ARM64 (Graviton) | ARM64 (Graviton) |
| Capacity Type | `ON_DEMAND` (free trial until Dec 2026) | `ON_DEMAND` (free trial until Dec 2026) |
| Min Size | 2 | 2 |
| Max Size | 4 | 4 |
| Desired Size | 2 | 2 |
| Disk Size | 20 GB | 20 GB |
| AMI Type | `AL2023_ARM_64` | `AL2023_ARM_64` |

> **Cost note:** t4g.small instances (2 vCPU, 2 GiB) are eligible for the AWS Graviton free trial (750 hrs/month until Dec 2026). Both dev and prod use identical sizing — this is a cost optimization for a learning project. In production, you would use larger instances (e.g., m7g.xlarge). Students should understand this trade-off.

### Node IAM Role Policies

| Policy | Type |
|--------|------|
| `AmazonEKSWorkerNodePolicy` | AWS Managed |
| `AmazonEKS_CNI_Policy` | AWS Managed |
| `AmazonEC2ContainerRegistryReadOnly` | AWS Managed |

### EKS Managed Add-ons

| Add-on | Purpose | IRSA Required |
|--------|---------|---------------|
| `coredns` | Cluster DNS | No |
| `kube-proxy` | Network proxy | No |
| `vpc-cni` | Pod networking | No |
| `aws-ebs-csi-driver` | EBS PersistentVolumes (Prometheus, Grafana) | Yes (`AmazonEBSCSIDriverPolicy`) |
| `metrics-server` | HPA / `kubectl top` (PETPLAT-72) | No |

Add-on versions pinned (not `latest`). Resolve conflicts strategy: `OVERWRITE` for initial setup. `metrics-server` uses the same `install_ebs_csi` gate as the other add-ons (cluster already exists). Version from `data.aws_eks_addon_version` (`most_recent`), never the string `latest`.

---

## ECR Container Registry

### Repository Configuration

| Parameter | Dev | Prod |
|-----------|-----|------|
| Registry Type | ECR Private | ECR Private |
| Terraform Resource | `aws_ecr_repository` | `aws_ecr_repository` |
| Region | `us-east-1` (same as infra) | `us-east-1` |
| Tag Mutability | `MUTABLE` | `IMMUTABLE` |
| Image Scanning | Scan-on-push enabled | Scan-on-push enabled |
| Encryption | `encryption_configuration { encryption_type = "AES256" }` on every repo (no KMS) | `encryption_configuration { encryption_type = "AES256" }` on every repo (no KMS) |

### Repositories (8 per environment)

| Repository Name | Service | Image URI Pattern |
|-----------------|---------|-------------------|
| `petclinic-{env}/config-server` | Config Server | `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/config-server:{tag}` |
| `petclinic-{env}/discovery-server` | Discovery Server | `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/discovery-server:{tag}` |
| `petclinic-{env}/api-gateway` | API Gateway | `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/api-gateway:{tag}` |
| `petclinic-{env}/customers-service` | Customers Service | `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/customers-service:{tag}` |
| `petclinic-{env}/visits-service` | Visits Service | `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/visits-service:{tag}` |
| `petclinic-{env}/vets-service` | Vets Service | `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/vets-service:{tag}` |
| `petclinic-{env}/genai-service` | GenAI Service | `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/genai-service:{tag}` |
| `petclinic-{env}/admin-server` | Admin Server | `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/admin-server:{tag}` |

### ECR Authentication

```bash
# Login (same region as infra)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin {account}.dkr.ecr.us-east-1.amazonaws.com

# Push
docker push {account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service}:{tag}
```

### Image Tag Strategy

| Context | Tag Format | Example |
|---------|------------|---------|
| CI/CD builds | Short commit SHA (7 chars) | `a1b2c3d` |
| Initial manual push | Semantic version | `v1.0.0` |
| Never used | `latest` | — |

### Lifecycle Policies

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Expire untagged images after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "Keep last 10 tagged images",
      "selection": {
        "tagStatus": "tagged",
        "tagPatternList": ["*"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": { "type": "expire" }
    }
  ]
}
```

### Cost

ECR Private: 500 MB free tier, then $0.10/GB/month. With 8 services at ~200 MB each, total storage is ~8-10 GB = **~$1/month** beyond free tier. Negligible cost that buys production-correct patterns: private images, lifecycle policies, scan-on-push, tag immutability.

---

## RDS Database

### Instance Configuration

| Parameter | Dev | Prod |
|-----------|-----|------|
| Engine | MySQL 8.0 | MySQL 8.0 |
| Instance Class | `db.t4g.micro` | `db.t4g.micro` |
| Multi-AZ | `false` | `false` (single-AZ, cost optimization for learning) |
| Allocated Storage | 20 GB | 20 GB |
| Max Allocated Storage (autoscaling) | 20 GB | 20 GB |
| Storage Type | `gp2` | `gp2` |
| Storage Encrypted | `true` (AWS default KMS key) | `true` (AWS default KMS key) |
| Publicly accessible | `false` (private subnets) | `false` (private subnets) |
| Backup Retention | 7 days | 7 days |
| Skip Final Snapshot | `true` | `true` |
| Deletion Protection | `false` | `false` |

> **Cost note:** db.t4g.micro (2 vCPU, 1 GiB) is AWS RDS free tier eligible (750 hrs/month for 12 months, 20 GB gp2 storage). Both dev and prod use identical sizing — this is a cost optimization for a learning project. In production, you would use db.r7g.large or higher with Multi-AZ, gp3 storage, 30-day backups, deletion protection, and a final snapshot. Students should understand these implications.
| DB Identifier | `petclinic-dev-mysql` | `petclinic-prod-mysql` |
| Master Username | `petclinic` | `petclinic` |
| Master Password | Generated via `random_password` | Generated via `random_password` |

### Parameter Group

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `character_set_server` | `utf8mb4` | Full Unicode support |
| `collation_server` | `utf8mb4_unicode_ci` | Unicode collation |

### Database Schema

All three database services use a shared `petclinic` database. Each service's schema.sql begins with `CREATE DATABASE IF NOT EXISTS petclinic; USE petclinic;`.

#### Tables (7 total across 3 services)

**Customers Service** — 3 tables:

| Table | Columns | Foreign Keys |
|-------|---------|-------------|
| `types` | `id` (PK, AUTO_INCREMENT), `name` | None |
| `owners` | `id` (PK), `first_name`, `last_name`, `address`, `city`, `telephone` | None |
| `pets` | `id` (PK), `name`, `birth_date`, `type_id`, `owner_id` | `owner_id` → `owners(id)`, `type_id` → `types(id)` |

**Vets Service** — 3 tables:

| Table | Columns | Foreign Keys |
|-------|---------|-------------|
| `vets` | `id` (PK, AUTO_INCREMENT), `first_name`, `last_name` | None |
| `specialties` | `id` (PK), `name` | None |
| `vet_specialties` | `vet_id`, `specialty_id` | `vet_id` → `vets(id)`, `specialty_id` → `specialties(id)` |

**Visits Service** — 1 table:

| Table | Columns | Foreign Keys |
|-------|---------|-------------|
| `visits` | `id` (PK, AUTO_INCREMENT), `pet_id`, `visit_date`, `description` | `pet_id` → `pets(id)` |

#### Schema Initialization Order

**Critical:** The `visits` table has `FOREIGN KEY (pet_id) REFERENCES pets(id)`, which is in the customers service schema. Initialization order:

1. **Customers Service** schema — creates `types`, `owners`, `pets`
2. **Vets Service** schema — creates `vets`, `specialties`, `vet_specialties` (independent)
3. **Visits Service** schema — creates `visits` (depends on `pets` from step 1)

**Strategy:** Let Spring Boot auto-initialize schemas on first startup with `spring.sql.init.mode=always` and `mysql` profile. The init order is enforced by deploying customers-service before visits-service.

### Connection String Format

```
jdbc:mysql://{rds-endpoint}:3306/petclinic
```

Example: `jdbc:mysql://petclinic-dev-mysql.abc123.us-east-1.rds.amazonaws.com:3306/petclinic`

---

## Secrets Management

### Why AWS Secrets Manager

AWS Secrets Manager is purpose-built for storing secrets (database credentials, API keys). It provides built-in rotation, cross-account access, and fine-grained IAM policies. At $0.40/secret/month (~$1.20/month for 3 secrets), the cost is minimal and teaches students the industry-standard approach.

### Secrets

| Secret Name | Type | Content | Created By |
|-------------|------|---------|------------|
| `petclinic/{env}/rds-credentials` | JSON (`{"username":"...","password":"..."}`) | RDS master credentials | RDS module (PETPLAT-23) |
| `petclinic/{env}/openai-api-key` | Plaintext | OpenAI API key value | Secrets module (PETPLAT-33) |

> **Note:** Secret names use forward-slash convention (`petclinic/{env}/...`). All secrets are encrypted with the default AWS KMS key (`aws/secretsmanager`).

RDS credentials are created by the RDS module with `random_password` (16+ chars, special characters) and stored as a JSON object. The secrets module handles non-RDS secrets only.

### External Secrets Operator (ESO)

| Parameter | Value |
|-----------|-------|
| Version | `v2.10.0` (Helm chart `2.10.0` — do not use `latest`) |
| API version | `external-secrets.io/v1` (`v1beta1` is obsolete) |
| Installation | Terraform `helm_release` in the secrets module (PETPLAT-34). Chart `external-secrets/external-secrets` `2.10.0`, namespace `external-secrets`, `create_namespace = true`, Helm-managed CRDs. Gated by `install_eso` (`true` only when the EKS cluster already exists). Do **not** create ClusterSecretStore or ExternalSecret via the Kubernetes provider in the same apply (CRD race). |
| Namespace | `external-secrets` |
| Store Type | `ClusterSecretStore` |
| Provider | AWS Secrets Manager |
| Auth | IRSA (see [IRSA Roles](#irsa-roles)) |

### ClusterSecretStore Configuration

Git YAML at `k8s/base/external-secrets/cluster-secret-store.yaml` (apply after the Helm release is ready — not a Terraform `kubernetes_manifest`).

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

### ExternalSecret Manifests

**RDS Credentials** (`k8s/base/external-secrets/rds-credentials.yaml`):

| Field | Value |
|-------|-------|
| `apiVersion` | `external-secrets.io/v1` |
| `secretStoreRef.name` | `aws-secrets-manager` |
| `secretStoreRef.kind` | `ClusterSecretStore` |
| `refreshInterval` | `1h` |
| `target.name` | `rds-credentials` |
| `data[0].secretKey` | `username` |
| `data[0].remoteRef.key` | `petclinic/{env}/rds-credentials` |
| `data[0].remoteRef.property` | `username` |
| `data[1].secretKey` | `password` |
| `data[1].remoteRef.key` | `petclinic/{env}/rds-credentials` |
| `data[1].remoteRef.property` | `password` |

**OpenAI API Key** (`k8s/base/external-secrets/openai-api-key.yaml`):

| Field | Value |
|-------|-------|
| `apiVersion` | `external-secrets.io/v1` |
| `refreshInterval` | `1h` |
| `target.name` | `openai-api-key` |
| `data[0].secretKey` | `OPENAI_API_KEY` |
| `data[0].remoteRef.key` | `petclinic/{env}/openai-api-key` |

---

## DNS and Ingress

Public HTTPS for the API Gateway. Terraform owns the hosted-zone **lookup** (optional create in **one** env), **one** wildcard ACM certificate (created in at most one env), and two cluster add-ons (AWS Load Balancer Controller + ExternalDNS). The Ingress is Helm, synced by ArgoCD. **ExternalDNS** writes the Route 53 alias when the ALB exists. Terraform does **not** create `aws_route53_record` aliases to the ALB (chicken-and-egg). See [ADR-0012](#adr-index).

Claude writes Terraform + Helm YAML only (`terraform validate`, `helm template` / `helm lint`). The operator applies Terraform, delegates NS if a zone was created, and confirms HTTPS after images + ArgoCD are running.

### Hostnames

| Environment | FQDN |
|-------------|------|
| Dev | `petclinic-dev.{domain}` |
| Prod | `petclinic.{domain}` |

`{domain}` is `var.domain_name` (operator-owned public domain). Derive the FQDN from `environment` + `domain_name` — do not take a separate hostname variable.

### Route 53 hosted zone

Dev and prod are **two Terraform states in the same AWS account**. Do **not** create the same public hosted zone from both roots.

| Parameter | Value |
|-----------|-------|
| Zone name | `{domain}` (public) |
| Default | **Look up** an existing zone: `data.aws_route53_zone` by `domain_name`, `private_zone = false` |
| Optional create | `create_hosted_zone` — **true in at most one environment** (typically none; the operator already has a zone). Prod wiring always looks up. |
| NS delegation | Operator, after apply, if Terraform created the zone |

ACM DNS-validation CNAMEs are Terraform `aws_route53_record`s in this zone (that is not the ALB alias).

### ACM Certificate

**One** wildcard cert for the account: `*.{domain}`. That covers `petclinic-dev.{domain}` and `petclinic.{domain}`. It does **not** cover the apex `{domain}`.

Dev and prod must **not** both call `aws_acm_certificate` for `*.{domain}` — the DNS validation CNAME is the same record and the two states will fight.

| Parameter | Value |
|-----------|-------|
| Domain | `*.{domain}` (wildcard) |
| Validation | DNS, records in the shared hosted zone |
| Region | `us-east-1` (same as the ALB) |
| Create | `create_acm_certificate` — true in **at most one** env (typically **dev**). That env owns `aws_acm_certificate` + validation records + `aws_acm_certificate_validation` |
| Lookup | Other env (prod): `data.aws_acm_certificate` for `*.{domain}`, most recent `ISSUED` |
| Ingress | Both env Helm files use the **same** wildcard ARN (`CERT_ARN`) |

`aws_acm_certificate_validation` waits until the validation CNAME answers. That requires the zone to be delegated at the registrar (or already serving). Hang/timeout on apply is an **operator** problem, not a Claude AC. Apply the env that **creates** the cert (dev) before prod can look it up.

### AWS Load Balancer Controller

Terraform `helm_release` in the **dns** module, same gate pattern as ESO (`install_eso`). Do **not** `helm install` from the CLI.

| Parameter | Value |
|-----------|-------|
| Chart repo | `https://aws.github.io/eks-charts` |
| Chart | `aws-load-balancer-controller` |
| Chart version | **3.5.0** (app `v3.5.0`) — pin, never `latest` |
| Namespace | `kube-system` |
| ServiceAccount | `aws-load-balancer-controller` (Helm creates it; IRSA annotation) |
| IngressClass | `alb` (`createIngressClassResource: true`) |
| clusterName | `petclinic-{env}` |
| vpcId | from the VPC module |
| Region | `us-east-1` |
| Gate | `install_lb_controller` — true only when this env's EKS cluster already exists |

IAM: **not** an AWS-managed policy. Vendor the official JSON from tag `v3.5.0` (unmodified) into `terraform/modules/dns/iam/` and attach it to `petclinic-{env}-lb-controller-role`.

Public subnets are already tagged `kubernetes.io/role/elb=1` and `kubernetes.io/cluster/petclinic-{env}=shared`. Do not hardcode subnet IDs on the Ingress.

### ExternalDNS

Writes the Route 53 **A alias** to the ALB after the Ingress is synced. Terraform never looks up `data.aws_lb` for that record.

| Parameter | Value |
|-----------|-------|
| Chart repo | `https://kubernetes-sigs.github.io/external-dns/` |
| Chart | `external-dns` |
| Chart version | **1.21.1** (app `v0.21.0`) — pin |
| Namespace | `kube-system` |
| ServiceAccount | `external-dns` (Helm creates it; IRSA annotation) |
| Provider | `aws`, public zones only |
| Sources | `ingress` only (not `service`) |
| domainFilters | `[var.domain_name]` |
| txtOwnerId | `petclinic-{env}` (dev and prod must differ) |
| policy | `upsert-only` (do not delete unrelated records in a shared zone) |
| Gate | `install_external_dns` — true only when this env's EKS cluster already exists |

IRSA: `route53:ChangeResourceRecordSets` on **this** hosted zone ARN; `route53:ListHostedZones`, `route53:ListResourceRecordSets`, `route53:ListTagsForResource` on `*`. Role `petclinic-{env}-external-dns-role`.

ExternalDNS uses `spec.rules[].host` on the Ingress. Do not add a Terraform alias "to make it faster."

### Ingress (Helm, api-gateway only)

Not `k8s/base/ingress/`. Chart template `helm/petclinic-service/templates/ingress.yaml`, gated by `ingress.enabled` (default **false**). Enable only in `helm-values/api-gateway.yaml`. Host, cert ARN, ALB SG, and load-balancer name come from `helm-values/{env}.yaml` (env file is merged last).

Placeholders (same idea as `ACCOUNT` in `image.registry`): `DOMAIN`, `CERT_ARN`, `ALB_SG_ID`. Never commit a real account ID or a real ACM ARN.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "petclinic-service.name" . }}
  namespace: {{ .Values.namespace }}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: "{{ .Values.ingress.certificateArn }}"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
    alb.ingress.kubernetes.io/healthcheck-port: "8080"
    alb.ingress.kubernetes.io/security-groups: "{{ .Values.ingress.albSecurityGroupId }}"
    alb.ingress.kubernetes.io/manage-backend-security-group-rules: "false"
    alb.ingress.kubernetes.io/load-balancer-name: "{{ .Values.ingress.loadBalancerName }}"
spec:
  ingressClassName: alb
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "petclinic-service.name" . }}
                port:
                  number: {{ .Values.service.port }}
```

Do **not** set `kubernetes.io/ingress.class` (deprecated). `target-type: ip` matches VPC CNI; node SG already allows TCP 8080 from the ALB. Attach the **existing** VPC `alb_sg_id` — do not let the controller create a second internet SG.

`loadBalancerName`: `petclinic-dev` / `petclinic-prod`.

### Ingress routing

| Path | Backend Service | Port |
|------|-----------------|------|
| `/` | `api-gateway` | 8080 |

All routing to backend services is handled by the API Gateway (Spring Cloud Gateway), not by the ALB Ingress.

NetworkPolicy "ALB → gateway" is **E-13**, not this epic.

---

## Application Services

### Service Inventory

| Service | Spring Name | Port | MySQL | Config Server | Discovery | Startup Order |
|---------|-------------|------|-------|---------------|-----------|---------------|
| Config Server | `config-server` | 8888 | No | Self (Git backend) | No | 1st (must be healthy first) |
| Discovery Server | `discovery-server` | 8761 | No | Yes | Self (Eureka) | 2nd (depends on Config) |
| API Gateway | `api-gateway` | 8080 | No | Yes | Yes | 3rd+ |
| Customers Service | `customers-service` | 8081 | Yes | Yes | Yes | 3rd+ (before Visits) |
| Visits Service | `visits-service` | 8082 | Yes | Yes | Yes | After Customers (FK dependency) |
| Vets Service | `vets-service` | 8083 | Yes | Yes | Yes | 3rd+ |
| GenAI Service | `genai-service` | 8084 | Optional | Yes | Yes | 3rd+ |
| Admin Server | `admin-server` | 9090 | No | Yes | Yes | 3rd+ (Spring Boot Admin 3.4.1) |

### Spring Profiles

| Profile | Purpose | When Active |
|---------|---------|-------------|
| `docker` | Changes Config Server URL from `localhost` to `config-server` (Docker DNS) | Set in Dockerfile: `SPRING_PROFILES_ACTIVE=docker` |
| `mysql` | Switches from HSQLDB to MySQL | Added for RDS-backed services: `SPRING_PROFILES_ACTIVE=docker,mysql` |
| `production` | Default active profile for vets-service and genai-service. **Required for vets-service Caffeine cache** — the `CacheConfig` class is gated on `@Profile("production")` so caching only works when this profile is active. | Set in application.yml |
| `chaos-monkey` | Chaos engineering (latency, exceptions) | Optional, testing only |
| `native` | Config Server uses local filesystem instead of Git repo | Local/dev only. Requires `GIT_REPO`. **Do not use on EKS.** |

### Config Server Details

| Parameter | Value |
|-----------|-------|
| Git URI | `https://github.com/spring-petclinic/spring-petclinic-microservices-config` (already in the app; do not set `GIT_REPO` on EKS) |
| Default Label (branch) | `main` |
| Config Import | All services use `optional:configserver:${CONFIG_SERVER_URL:http://localhost:8888/}` |
| Docker Profile Override | `configserver:http://config-server:8888` |

### API Gateway Routes

| Route ID | Path | Target | Filters |
|----------|------|--------|---------|
| `vets-service` | `/api/vet/**` | `lb://vets-service` | `StripPrefix=2` |
| `visits-service` | `/api/visit/**` | `lb://visits-service` | `StripPrefix=2` |
| `customers-service` | `/api/customer/**` | `lb://customers-service` | `StripPrefix=2` |
| `genai-service` | `/api/genai/**` | `lb://genai-service` | `StripPrefix=2`, CircuitBreaker |

Default filters on all routes: `CircuitBreaker` (with `/fallback` URI), `Retry` (1 retry on `SERVICE_UNAVAILABLE`). Resilience4j `TimeLimiter` is configured with a 10-second timeout.

The API Gateway also serves an **AngularJS frontend** (static files: AngularJS 1.8.3, Bootstrap 5.3.3, Font Awesome 4.7.0) — this is the only user-facing service. All backend service API calls go through the gateway routes above.

### GenAI Service Configuration

| Parameter | Value |
|-----------|-------|
| AI Provider | OpenAI (default) |
| Model | `gpt-4o-mini` |
| Temperature | 0.7 |
| Spring AI Version | `2.0.0-M1` (milestone release) |
| API Key Env Var | `OPENAI_API_KEY` (defaults to `demo` if not set) |
| Alternate Provider | Azure OpenAI (`AZURE_OPENAI_KEY`, `AZURE_OPENAI_ENDPOINT`) |
| Application Type | Reactive (WebFlux) |
| Database | Has JPA + MySQL dependencies but no schema files. Includes `vectorstore.json` (124KB pre-populated vet embeddings for RAG) |
| Config Import Extra | Also imports `optional:classpath:/creds.yaml` (not present by default, used for local credential overrides) |

---

## Kubernetes Manifests

### Namespaces

| Namespace | Environment | PSA Labels |
|-----------|-------------|------------|
| `petclinic-dev` | Dev | `pod-security.kubernetes.io/enforce: baseline`, `pod-security.kubernetes.io/warn: restricted`, `pod-security.kubernetes.io/audit: restricted` |
| `petclinic-prod` | Prod | `pod-security.kubernetes.io/enforce: baseline`, `pod-security.kubernetes.io/warn: restricted`, `pod-security.kubernetes.io/audit: restricted` |

### Standard Labels (All Resources)

```yaml
app.kubernetes.io/name: "{service-name}"
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: "{server|service|gateway|admin}"
```

### Health Probes (All Services)

| Probe | Path | Port | Period | Timeout | Failure Threshold |
|-------|------|------|--------|---------|-------------------|
| Startup | `/actuator/health` | Service port | 10s | 5s | 30 (allows up to 5 min) |
| Readiness | `/actuator/health/readiness` | Service port | 10s | 5s | 3 |
| Liveness | `/actuator/health/liveness` | Service port | 15s | 5s | 3 |

The startupProbe runs first and disables readiness and liveness checks until Spring Boot has fully initialized. Once startup passes, readiness and liveness take over. Config Server uses `/actuator/health` for all three probes.

### Resource Requests and Limits

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit |
|---------|-------------|-----------|----------------|--------------|
| config-server | 100m | 500m | 128Mi | 512Mi |
| discovery-server | 100m | 500m | 128Mi | 512Mi |
| api-gateway | 200m | 1000m | 128Mi | 512Mi |
| customers-service | 100m | 500m | 128Mi | 512Mi |
| visits-service | 100m | 500m | 128Mi | 512Mi |
| vets-service | 100m | 500m | 128Mi | 512Mi |
| genai-service | 100m | 500m | 128Mi | 512Mi |
| admin-server | 100m | 500m | 128Mi | 512Mi |

API Gateway gets higher CPU (200m/1000m) because it handles all incoming traffic routing. Memory requests are set to 128Mi (with 512Mi limit) to fit on t4g.small nodes (2 GiB RAM). Spring Boot services idle around 200-300 MiB — the 512Mi limit provides headroom for spikes.

### Environment Variables per Service

**All services:**

| Variable | Value | Source |
|----------|-------|--------|
| `SPRING_PROFILES_ACTIVE` | See below | Deployment spec |
| `CONFIG_SERVER_URL` | `http://config-server:8888` | ConfigMap |

Do **not** set `DISCOVERY_SERVER_URL` (the app does not use it). Do **not** set `GIT_REPO` on Config Server (that is the unused `native` profile).

| Service | `SPRING_PROFILES_ACTIVE` |
|---------|--------------------------|
| config-server, discovery-server, api-gateway, admin-server | `docker` |
| customers-service, visits-service | `docker,mysql` |
| vets-service | `docker,mysql,production` |
| genai-service | `docker,production` |

**DB services (customers, visits, vets) — additional:**

| Variable | Value | Source |
|----------|-------|--------|
| `SPRING_DATASOURCE_URL` | `jdbc:mysql://{rds-endpoint}:3306/petclinic` | ConfigMap |
| `SPRING_DATASOURCE_USERNAME` | From secret | K8s Secret (ESO) |
| `SPRING_DATASOURCE_PASSWORD` | From secret | K8s Secret (ESO) |

**GenAI service — additional:**

| Variable | Value | Source |
|----------|-------|--------|
| `OPENAI_API_KEY` | From secret | K8s Secret (ESO) |

### Init Containers (Startup Order Enforcement)

**Config Server:** no init containers.

**Discovery Server:** wait for Config Server only. Do **not** wait for Discovery (that would deadlock).

```yaml
initContainers:
  - name: wait-for-config-server
    image: busybox:1.36
    command: ['sh', '-c', 'until wget -qO- http://config-server:8888/actuator/health; do sleep 5; done']
```

**All other services** (API Gateway, customers, visits, vets, GenAI, Admin): wait for Config Server **and** Discovery Server.

```yaml
initContainers:
  - name: wait-for-config-server
    image: busybox:1.36
    command: ['sh', '-c', 'until wget -qO- http://config-server:8888/actuator/health; do sleep 5; done']
  - name: wait-for-discovery-server
    image: busybox:1.36
    command: ['sh', '-c', 'until wget -qO- http://discovery-server:8761/actuator/health; do sleep 5; done']
```

### SecurityContext (All Deployments)

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      readOnlyRootFilesystem: false  # Spring Boot needs /tmp for file uploads and caching
```

### Manifest File Structure

Each service directory contains:

| File | Content |
|------|---------|
| `deployment.yaml` | Deployment with probes, resources, env vars, init containers |
| `service.yaml` | ClusterIP Service exposing the service port |
| `configmap.yaml` | Environment-specific configuration (URLs, non-secret settings) |
| `serviceaccount.yaml` | ServiceAccount (annotated with IRSA role ARN where needed) |

---

## Kubernetes Overlays (reference — `k8s-reference/`)

Pre-Helm Kustomize tree. Live deploy uses Helm + Argo CD. Do not apply for the current path.

### Dev Overlay (`k8s-reference/overlays/dev/`)

| Parameter | Value |
|-----------|-------|
| Namespace | `petclinic-dev` |
| Replicas (all services) | 1 |
| Image Tag | Placeholder `TAG` until PETPLAT-85 / CI. Then commit SHA (CI updates `helm-values/{service}.yaml` in E-16+) |

### Prod Overlay (`k8s-reference/overlays/prod/`)

| Service | Replicas | Notes |
|---------|----------|-------|
| config-server | 2 | HA for config distribution |
| discovery-server | 2 | HA for service registry |
| api-gateway | 2 | HA, public-facing entry point |
| customers-service | 2 | HA |
| visits-service | 2 | HA |
| vets-service | 2 | HA |
| genai-service | 1 | Lower priority, cost saving |
| admin-server | 1 | Monitoring tool, single replica sufficient |

### Horizontal Pod Autoscaler (Prod only)

| Service | Min | Max | CPU Target |
|---------|-----|-----|------------|
| api-gateway | 2 | 6 | 70% |
| customers-service | 2 | 4 | 70% |
| visits-service | 2 | 4 | 70% |
| vets-service | 2 | 4 | 70% |
| genai-service | 1 | 3 | 70% |

HPA YAML lives in the prod overlay (PETPLAT-47). Metrics Server install is PETPLAT-72 — HPA does not function in-cluster until then.

### Pod Disruption Budgets (Prod only)

| Service | minAvailable |
|---------|-------------|
| config-server | 1 |
| discovery-server | 1 |
| api-gateway | 1 |
| customers-service | 1 |
| visits-service | 1 |
| vets-service | 1 |

### Resource Quotas

Out of scope for E-9. See PETPLAT-89 (E-13). YAML lives in `k8s/security/{dev,prod}/`, not overlays.

| Parameter | Dev | Prod |
|-----------|-----|------|
| Max CPU | 4 | 6 |
| Max Memory | 4Gi | 6Gi |
| Max Pods | 40 | 50 |

### Helm Values Structure (replaces Kustomize overlays)

Environment-specific configuration is managed via Helm values files in `helm-values/`:
- `helm-values/dev.yaml` — dev overrides (replicas=1, no HPA, no PDB)
- `helm-values/prod.yaml` — prod overrides (replicas=2, HPA enabled, PDB enabled)
- Per-service files hold service-specific config (ports, env vars, init containers)
- ArgoCD merges service + environment values when deploying

> **E-9:** Kustomize overlays under `k8s-reference/overlays/{dev,prod}` were the source of truth for namespace, ESO keys, replicas, HPA, and PDB. E-16 copied those settings into `helm-values/{dev,prod}.yaml`. After Helm/ArgoCD, `k8s-reference/` is reference only. Live namespaces/ESO stay in `k8s/base/`. Do **not** create `helm-values/` in E-9.

---

## CI/CD Pipeline

### Architecture: CI + GitOps

GitHub Actions handles **CI only** (build, scan, push images, commit Helm tags). **ArgoCD handles CD** (deployment to EKS). Two repositories:

| Repo | Workflow | Trigger |
|------|----------|---------|
| Application fork (`spring-petclinic-microservices`) | `.github/workflows/build-push.yml` | Push to `main` |
| Platform (`petclinic-platform`) | `.github/workflows/update-image-tags.yml` | `repository_dispatch` type `app-image-built` |

`workflow_run` is **not** used — it only works inside one repo.

| Concern | Tool | How |
|---------|------|-----|
| Build & Push images | GitHub Actions (app fork) | Maven `buildDocker`, ARM64, Trivy, push to ECR |
| Update image tags | GitHub Actions (platform) | `yq` commits `image.tag` in `helm-values/{service}.yaml` |
| Deploy to Kubernetes | ArgoCD (E-17) | Watches Git, syncs Helm releases |

> **No deploy workflows.** ArgoCD watches `helm-values/` and auto-syncs (dev) or waits for manual approval (prod). CI never runs `kubectl apply` or `helm upgrade`.

### OIDC Federation (No Long-Lived Credentials)

GitHub → AWS OIDC is **account-scoped** and **separate from EKS IRSA OIDC**. Terraform module `terraform/modules/github-oidc/`, called from **dev only** (creating it in prod would duplicate the IAM role).

| Parameter | Value |
|-----------|-------|
| OIDC Provider | `token.actions.githubusercontent.com` |
| Audience | `sts.amazonaws.com` |
| Subject Filter | `repo:{github_org}/{github_app_repo}:ref:refs/heads/main` |
| IAM Role | `petclinic-github-actions-role` (no `{env}` in the name) |
| Permissions | ECR get-auth + push/layer upload on `petclinic-dev/*` and `petclinic-prod/*` only — no S3, DynamoDB, or EKS |
| Terraform output | `github_actions_role_arn` (dev root) |

### GitHub Secrets

Set on the **application fork** by the operator (never committed):

| Secret Name | Purpose |
|-------------|---------|
| `AWS_REGION` | `us-east-1` |
| `AWS_ROLE_ARN` | OIDC role ARN (`github_actions_role_arn`) |
| `AWS_ACCOUNT_ID` | AWS account ID (ECR registry host) |
| `PLATFORM_REPO_TOKEN` | PAT/fine-grained token that can `repository_dispatch` the platform repo |

The platform `update-image-tags` workflow uses `GITHUB_TOKEN` (`contents: write` only). No AWS secrets on the platform repo. No `EKS_CLUSTER_NAME`. No GitHub Environments — prod approval is ArgoCD.

### Build Steps (build-push.yml, app fork)

1. Path-filter Maven modules (`spring-petclinic-{service}/`). Shared `docker/**` or root `pom.xml` → all 8.
2. Skip the build job if nothing matched.
3. JDK 17, Docker Buildx, QEMU (`linux/arm64`).
4. OIDC (`id-token: write`) → ECR login.
5. Per changed service: `./mvnw clean install -P buildDocker -Dcontainer.platform=linux/arm64 -pl spring-petclinic-{service} -am`
6. Retag `springcommunity/spring-petclinic-{artifact}` to `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service}:{sha}` for **both** `dev` and `prod`. Helm `{service}` is the short name (`customers-service`, not `spring-petclinic-customers-service`).
7. Trivy before push: fail on CRITICAL, warn on HIGH, upload the report as an artifact. Use `.trivyignore` only if that file already exists.
8. Tag: `${GITHUB_SHA::7}`. Never `latest`.
9. `repository_dispatch` `app-image-built` to the platform repo with `{ sha, services }` (Helm names).

> **ARM cross-compilation:** GitHub-hosted runners are x86_64. QEMU via `docker/setup-qemu-action` and `docker/setup-buildx-action` is required. Build time is ~5 min per image, acceptable for this project.

> **Why both ECR prefixes:** `helm-values/{service}.yaml` has one `image.tag`. Env files only change `image.registry` (`…/petclinic-dev` vs `…/petclinic-prod`). The same SHA must exist in both registries.

### Update Image Tags Steps (update-image-tags.yml, platform)

1. Trigger: `repository_dispatch` / `app-image-built` only.
2. `yq` update `image.tag` in `helm-values/{service}.yaml` for services in the payload — not all 8.
3. Commit + push: `ci: update image tags to ${SHA} (${service-list})`.

ArgoCD (E-17) later syncs that commit. This workflow does not talk to the cluster.

### Image Tag Update Mechanism

```bash
# Update image tag only for services included in the repository_dispatch payload
SERVICES="${{ github.event.client_payload.services }}"  # e.g. "customers-service vets-service"
SHA="${{ github.event.client_payload.sha }}"

for service in ${SERVICES}; do
  yq -i ".image.tag = \"${SHA}\"" helm-values/${service}.yaml
done

git add helm-values/
git commit -m "ci: update image tags to ${SHA} (${SERVICES})"
git push
```

---

## Observability

In-cluster stack. No CloudWatch Logs, no FluentBit IRSA. See [ADR-0013](#adr-index).

Claude writes Terraform + Git YAML (`terraform validate`, `helm template` / `helm lint`). The operator applies. Grafana is reached at `https://grafana-{env}.{domain}` (prod: `https://grafana.{domain}`) and Zipkin at `https://zipkin-{env}.{domain}` (prod: `https://zipkin.{domain}`) on dedicated ALBs, CIDR-locked to `public_access_cidrs`. **No** Ingress for Prometheus or Alertmanager — those stay port-forward.

Install with Terraform `helm_release` in `terraform/modules/observability/`, gated like ESO (`install_observability` true only when this env's EKS cluster already exists). Do **not** `helm install` from the CLI. Do **not** add `monitoring` / `tracing` to ArgoCD AppProjects — those stay app namespaces only.

EBS PersistentVolumes need the **EBS CSI Driver** (PETPLAT-84) in the **EKS module**, plus a `gp3` StorageClass.

### kube-prometheus-stack

One chart for Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporter (the last two are required for PodRestartLoop and HighMemoryUsage).

| Parameter | Value |
|-----------|-------|
| Chart repo | `https://prometheus-community.github.io/helm-charts` |
| Chart | `kube-prometheus-stack` |
| Chart version | **88.6.2** (pin) |
| Release name | `kube-prometheus-stack` |
| Namespace | `monitoring` (`create_namespace = true`) |
| Gate | `install_observability` |

| Parameter | Dev | Prod |
|-----------|-----|------|
| Prometheus retention | 7 days | 15 days |
| Prometheus PVC | 10Gi gp3 | 50Gi gp3 |
| Grafana PVC | 5Gi gp3 | 5Gi gp3 |
| Scrape / evaluation | 15s | 15s |

**Learning-size resources** (two `t4g.small` nodes). Do not ship chart defaults (multi-GiB Prometheus):

| Component | CPU request | Memory request | Memory limit |
|-----------|-------------|----------------|--------------|
| Prometheus | 100m | 256Mi | 512Mi |
| Grafana | 50m | 128Mi | 256Mi |
| Alertmanager | 20m | 64Mi | 128Mi |
| kube-state-metrics / node-exporter | chart min | keep small | keep small |

Grafana admin password: Terraform `random_password`, passed into Helm, **sensitive output**. Never commit it. Operator: `terraform output grafana_admin_password`.

Alertmanager: in-cluster only. Slack receiver when `slack_webhook_url` is set in gitignored `terraform.tfvars`; otherwise **blackhole**. Never commit the webhook.

Access: Grafana and Zipkin HTTPS Ingress (dedicated ALBs, operator CIDRs only). Prometheus and Alertmanager: `kubectl port-forward` only.

Do **not** set `pod-security.kubernetes.io/enforce=restricted` on `monitoring` (node-exporter and Fluent Bit need hostPath). Leave the namespace unlabeled or `privileged`.

#### Scrape targets

Static additional scrape jobs (Prometheus in `monitoring` talking to DNS `service.petclinic-{env}.svc`):

| Job Name | Target | Metrics Path | Port |
|----------|--------|-------------|------|
| `config-server` | `config-server.petclinic-{env}.svc:8888` | `/actuator/prometheus` | 8888 |
| `discovery-server` | `discovery-server.petclinic-{env}.svc:8761` | `/actuator/prometheus` | 8761 |
| `api-gateway` | `api-gateway.petclinic-{env}.svc:8080` | `/actuator/prometheus` | 8080 |
| `customers-service` | `customers-service.petclinic-{env}.svc:8081` | `/actuator/prometheus` | 8081 |
| `visits-service` | `visits-service.petclinic-{env}.svc:8082` | `/actuator/prometheus` | 8082 |
| `vets-service` | `vets-service.petclinic-{env}.svc:8083` | `/actuator/prometheus` | 8083 |
| `genai-service` | `genai-service.petclinic-{env}.svc:8084` | `/actuator/prometheus` | 8084 |
| `admin-server` | `admin-server.petclinic-{env}.svc:9090` | `/actuator/prometheus` | 9090 |

### Grafana dashboards

Provisioned from Git ConfigMaps / chart dashboard sidecar. Path: `k8s/observability/grafana-dashboards/` (not `k8s/base/`).

| Dashboard | Key Metrics |
|-----------|-------------|
| Service Overview | All 8 services: up/down, RPS, error rate |
| Per-Service (x8) | Request rate, error rate, p95/p99 latency |
| JVM Metrics | Heap usage, GC pauses, thread count |

### Alert rules (Prometheus)

Stored as `PrometheusRule` YAML in `k8s/observability/prometheus-rules/` and loaded by the chart (`additionalPrometheusRulesMap` or equivalent). kube-state-metrics must be enabled for restart/memory alerts.

| Alert | Condition | Duration | Severity |
|-------|-----------|----------|----------|
| ServiceDown | `up == 0` for any target | 1m | `critical` |
| HighErrorRate | `rate(http_server_requests_seconds_count{status=~"5.."}[5m]) / rate(http_server_requests_seconds_count[5m]) > 0.05` | 5m | `warning` |
| HighLatency | `histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m])) > 0.5` | 5m | `warning` |
| PodRestartLoop | `increase(kube_pod_container_status_restarts_total[15m]) > 3` | 0m | `critical` |
| HighMemoryUsage | `container_memory_working_set_bytes / container_spec_memory_limit_bytes > 0.8` | 5m | `warning` |

### Loki

| Parameter | Value |
|-----------|-------|
| Chart repo | `https://grafana-community.github.io/helm-charts` |
| Chart | `loki` |
| Chart version | **18.7.6** (pin) |
| Release name | `loki` |
| Namespace | `monitoring` |
| Mode | SingleBinary (no MinIO, no object storage) |
| Service DNS | `loki.monitoring.svc` port **3100** (Fluent Bit must use this; do not assume `loki-gateway`) |

| Parameter | Dev | Prod |
|-----------|-----|------|
| PVC | 10Gi gp3 | 50Gi gp3 |
| Log retention | 7 days | 30 days |
| CPU / memory request | 100m / 256Mi | 100m / 256Mi |

#### Loki alert rules

| Alert | LogQL Condition | Duration | Severity |
|-------|----------------|----------|----------|
| `LogErrorSpike` | `rate({namespace=~"petclinic-.*"} \|= "ERROR" [5m]) > 0.5` | 5m | `warning` |
| `JVMOutOfMemory` | `count_over_time({namespace=~"petclinic-.*"} \|= "OutOfMemoryError" [5m]) > 0` | 0m | `critical` |

Route through Loki ruler → Alertmanager in `monitoring` if the chart supports it without extra object storage; otherwise ship the rule YAML and document that the ruler is best-effort on SingleBinary.

### Fluent Bit

| Parameter | Value |
|-----------|-------|
| Chart repo | `https://fluent.github.io/helm-charts` |
| Chart | `fluent-bit` |
| Chart version | **0.53.0** (pin) |
| Release name | `fluent-bit` |
| Namespace | `monitoring` |
| Kind | DaemonSet |
| Output | Loki plugin, Host `loki.monitoring.svc`, Port `3100` |
| Labels | `namespace`, `pod`, `container` |
| IRSA | None |

### Zipkin

Small **in-repo** chart `helm/zipkin/` (Deployment + ClusterIP Service + optional Ingress). Terraform `helm_release` into `tracing`. Image `openzipkin/zipkin`, port 9411, emptyDir (no PVC). Resources 100m / 256Mi.

When `zipkin_ingress_enabled` is true: dedicated ALB `petclinic-{env}-zipkin`, host `zipkin-{env}.{domain}` (prod: `zipkin.{domain}`), same wildcard cert and operator CIDRs as Grafana. Apps still POST spans to `http://zipkin.tracing.svc:9411/api/v2/spans`.

Do **not** edit the app repo. Spring Boot 4 Zipkin starter on: api-gateway, customers-service, visits-service, vets-service, genai-service. Add to those `helm-values/{service}.yaml` `configData`:

```yaml
MANAGEMENT_TRACING_EXPORT_ZIPKIN_ENDPOINT: "http://zipkin.tracing.svc:9411/api/v2/spans"
MANAGEMENT_TRACING_SAMPLING_PROBABILITY: "1.0"
```

Not on config-server, discovery-server, or admin-server.

---

## IRSA Roles

IRSA roles use an OIDC trust policy scoped to one Kubernetes ServiceAccount. FluentBit does not need IRSA (logs go to Loki in-cluster). Skip `petclinic-{env}-argocd-role`.

| Role Name Pattern | K8s ServiceAccount | Namespace | IAM Policy | Used By |
|-------------------|--------------------|-----------|------------|---------|
| `petclinic-{env}-eso-role` | `external-secrets-sa` | `external-secrets` | `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` on `arn:aws:secretsmanager:us-east-1:{account}:secret:petclinic/*` | ESO |
| `petclinic-{env}-lb-controller-role` | `aws-load-balancer-controller` | `kube-system` | Official AWS Load Balancer Controller IAM JSON from tag `v3.5.0` (not an AWS-managed policy) | ALB Controller |
| `petclinic-{env}-external-dns-role` | `external-dns` | `kube-system` | `route53:ChangeResourceRecordSets` on the env's hosted zone; `ListHostedZones`, `ListResourceRecordSets`, `ListTagsForResource` | ExternalDNS |
| `petclinic-{env}-ebs-csi-role` | `ebs-csi-controller-sa` | `kube-system` | `AmazonEBSCSIDriverPolicy` (AWS managed) | EBS CSI Driver |
| `petclinic-{env}-argocd-role` | `argocd-server` | `argocd` | **Not created.** ArgoCD stays in-cluster and only reads Git. Skip this IRSA. | — |
| `petclinic-{env}-karpenter-role` | `karpenter` | `karpenter` | Official Karpenter 1.14 controller policy JSON, vendored unmodified (same idea as the LB controller). Do **not** use `ec2:*`. | Karpenter |

### IRSA Trust Policy Template

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::{account}:oidc-provider/{oidc-provider}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "{oidc-provider}:sub": "system:serviceaccount:{namespace}:{sa-name}",
        "{oidc-provider}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

---

## Security Controls

### Encryption Matrix

| Resource | Encryption at Rest | Encryption in Transit | Key |
|----------|-------------------|----------------------|-----|
| RDS MySQL | KMS (AWS default key) | SSL available (not enforced by default) | AWS managed |
| S3 (state bucket) | SSE-S3 (AES256) | HTTPS enforced | AWS managed |
| EBS Volumes | Default encryption enabled | N/A | AWS managed |
| ECR Images | AES256 | HTTPS | AWS managed |
| Secrets Manager | KMS (AWS default `aws/secretsmanager` key) | HTTPS | AWS managed |
| ALB | N/A | TLS termination (ACM cert) | ACM |

### Kubernetes Network Policies

Git YAML under `k8s/security/{dev,prod}/`. Operator `kubectl apply` (same as namespaces). Do **not** add `monitoring` / `tracing` to ArgoCD AppProjects. Do **not** put NetworkPolicies on `monitoring` or `tracing` (node-exporter and Fluent Bit use hostPath).

**CNI:** Amazon VPC CNI network policy (EKS 1.25+). Set `enableNetworkPolicy = "true"` on the existing `aws_eks_addon` `vpc-cni` (gated by `install_ebs_csi`). Do **not** install Calico or Cilium.

**Default deny ingress only.** Do not default-deny egress (DNS, NAT, GitHub, OpenAI, RDS, Zipkin).

ALB uses `target-type: ip`: packets arrive from ALB ENIs in the VPC, not from the controller pod. Gateway allow is **VPC CIDR**, not `kube-system`.

| Policy | Namespace | Effect |
|--------|-----------|--------|
| Default deny ingress | `petclinic-{env}` | Deny all ingress |
| Config Server | `petclinic-{env}` | Allow 8888 from pods in this namespace |
| Discovery Server | `petclinic-{env}` | Allow 8761 from pods in this namespace |
| API Gateway | `petclinic-{env}` | Allow 8080 from VPC CIDR (`10.0.0.0/16` dev, `10.1.0.0/16` prod) **and** from namespace `monitoring` |
| Domain services (customers, visits, vets, genai) | `petclinic-{env}` | Allow their ports from API Gateway pods **and** from namespace `monitoring` |
| Admin Server | `petclinic-{env}` | Allow 9090 from pods in this namespace **and** from namespace `monitoring` |
| Prometheus scrape | `petclinic-{env}` | All 8 services: ingress from namespace `monitoring` on the service port |

### Resource quotas

Only `petclinic-{env}`. Never `monitoring` / `tracing`. Cluster is 2× `t4g.small` (4 vCPU / 4 GiB).

| Parameter | Dev | Prod |
|-----------|-----|------|
| Max CPU | 4 | 6 |
| Max Memory | 4Gi | 6Gi |
| Max Pods | 40 | 50 |

LimitRange defaults match the Helm chart: request `100m` / `128Mi`, limit `500m` / `512Mi`.

### Pod Security Admission

Already on `k8s/base/namespaces.yaml`. Helm already sets SecurityContext (`runAsNonRoot`, drop ALL, `readOnlyRootFilesystem: false`). Do not duplicate in E-13.

| Namespace | Enforce | Warn | Audit |
|-----------|---------|------|-------|
| `petclinic-dev` | `baseline` | `restricted` | `restricted` |
| `petclinic-prod` | `baseline` | `restricted` | `restricted` |
| `monitoring` | unlabeled / privileged | — | — |

### IAM exceptions (do not rewrite)

These wildcards / managed policies stay. Checkov skips them.

| Policy | Why |
|--------|-----|
| AWS managed: `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEBSCSIDriverPolicy` | Required by EKS |
| Vendored LB controller IAM JSON (chart tag `v3.5.0`) | Official AWS policy; do not edit |
| `ecr:GetAuthorizationToken` on `*` | AWS API does not support a resource ARN |

Custom IRSA (ESO, ExternalDNS, EBS CSI) stays resource-scoped. No bastion role.

### Checkov

Platform repo: `.checkov.yml` skip list for the exceptions above plus ALB `0.0.0.0/0` on 80/443, EKS public API limited to operator CIDR, node SG self-referencing all traffic. GitHub Actions workflow scans `terraform/`. Claude does not paste a scan report as “done.”

Trivy and ECR scan-on-push are already E-10 / E-4. Security group shape is already E-2.

---

## Scaling and Cost

### Monthly Cost Estimate (Free Tier Optimized)

This is a learning project. Instance choices maximize AWS free tier eligibility.

| Resource | Dev (~) | Prod (~) | Free Tier |
|----------|---------|----------|-----------|
| EKS Control Plane | $73 | $73 | None — unavoidable cost |
| EC2 Nodes (2x t4g.small) | $0 | $0 | Graviton free trial (750 hrs/mo until Dec 2026) |
| RDS MySQL (db.t4g.micro) | $0 | $0 | RDS free tier (750 hrs/mo, 12 months) |
| ALB | $0 | $0 | Free tier (750 hrs/mo, 12 months) |
| S3 + DynamoDB (state) | $1 | $1 | Mostly free tier |
| ECR Storage | ~$1 | ~$1 | 500 MB free, then $0.10/GB/month |
| NAT Gateway | ~$33 (1×) | ~$65 (2×) | ~$0.045/hr each + data processing |
| EBS (PVs — Prometheus, Grafana, Loki) | $2 | $2 | 30 GB gp2 free (12 months) |
| Route 53 | $1 | $1 | $0.50/zone + queries |
| Secrets Manager | $1 | $1 | $0.40/secret/month (~3 secrets) |
| Data Transfer | $1 | $1 | 100 GB/mo free |
| **Total** | **~$113/mo** | **~$145/mo** | EKS control plane + NAT are the main costs |

> **Students should `terraform destroy` after each session** to minimize EKS control plane and NAT charges. Dev has 1 NAT; prod has 2. Target: destroy when not in use.

NAT Gateway is required for private-subnet outbound (ECR API, Secrets Manager, patches). The **S3 Gateway endpoint** (free) keeps S3/ECR-layer traffic off NAT.

### Spot Instance Configuration (Dev — Optional)

| Parameter | Value |
|-----------|-------|
| Instance Types (mixed) | `t4g.small`, `t4g.medium` |
| Capacity Type | `SPOT` (with on-demand fallback) |
| Savings | ~60-70% on compute (when free trial expires) |

> **Note:** While the Graviton free trial is active, spot instances provide no cost benefit. This configuration is documented for when the free trial expires or for production use with larger instances.

### Budget Alerts

PETPLAT-75. `aws_budgets_budget` in each env root (`terraform/environments/{env}/`), not inside the Karpenter Helm release. Email from gitignored `terraform.tfvars` (`budget_notification_email`, sensitive). Never commit an address.

| Environment | Monthly Budget | Alert at |
|-------------|---------------|----------|
| Dev | $200 | 50%, 80%, 100% |
| Prod | $200 | 50%, 80%, 100% |
| Notification | Email to `var.budget_notification_email` | — |

---

## Docker Build

### Build Command

```bash
# Build all 8 Docker images for ARM64 (required for t4g Graviton nodes)
./mvnw clean install -P buildDocker -Dcontainer.platform="linux/arm64"
```

> **Important:** EKS nodes are ARM64 (Graviton). All Docker images MUST be built for `linux/arm64`. The base image `eclipse-temurin:17` supports multi-arch. Local builds on Apple Silicon (M1/M2/M3) produce ARM images natively. CI/CD builds on x86 GitHub Actions runners require `docker buildx` with QEMU emulation (see [CI/CD Pipeline](#cicd-pipeline)).

### Dockerfile Details

| Parameter | Value |
|-----------|-------|
| Dockerfile Location | `docker/Dockerfile` (shared by all services) |
| Base Image | `eclipse-temurin:17` |
| Build Strategy | Multi-stage (builder + runtime) |
| Layer Extraction | `java -Djarmode=layertools -jar application.jar extract` |
| Layers | `dependencies/`, `spring-boot-loader/`, `snapshot-dependencies/`, `application/` |
| Entrypoint | `java org.springframework.boot.loader.launch.JarLauncher` |
| Build Args | `ARTIFACT_NAME` (JAR name), `EXPOSED_PORT` (service port) |
| Default Profile | `SPRING_PROFILES_ACTIVE=docker` (ENV in Dockerfile) |
| Target Platform | `linux/arm64` (for Graviton t4g nodes) |
| Memory Limit | 512M (set in Docker Compose, enforce in K8s) |
| Local Image Prefix | `springcommunity/` (from Maven pom.xml, e.g., `springcommunity/spring-petclinic-api-gateway`) |

> **Note:** The Maven build produces images with the `springcommunity/` prefix (e.g., `springcommunity/spring-petclinic-customers-service`). The CI/CD pipeline re-tags and pushes to ECR using the `petclinic-{env}/{service}` naming convention.

> **Warning:** The `docker.image.exposed.port` property in each service's pom.xml is a build-time metadata value for the Dockerfile `EXPOSE` directive. Several services have **incorrect values** (copy-paste from template): API Gateway, Visits, Vets, and GenAI all show `8081` in their pom.xml. The actual runtime ports come from the Config Server's Git repository, not from this property. Do NOT rely on pom.xml exposed ports — use the Service Inventory table above.

### Artifact-to-Image Mapping

| Maven Module | JAR Artifact | ECR Repository |
|--------------|-------------|----------------|
| `spring-petclinic-config-server` | `spring-petclinic-config-server-*.jar` | `petclinic-{env}/config-server` |
| `spring-petclinic-discovery-server` | `spring-petclinic-discovery-server-*.jar` | `petclinic-{env}/discovery-server` |
| `spring-petclinic-api-gateway` | `spring-petclinic-api-gateway-*.jar` | `petclinic-{env}/api-gateway` |
| `spring-petclinic-customers-service` | `spring-petclinic-customers-service-*.jar` | `petclinic-{env}/customers-service` |
| `spring-petclinic-visits-service` | `spring-petclinic-visits-service-*.jar` | `petclinic-{env}/visits-service` |
| `spring-petclinic-vets-service` | `spring-petclinic-vets-service-*.jar` | `petclinic-{env}/vets-service` |
| `spring-petclinic-genai-service` | `spring-petclinic-genai-service-*.jar` | `petclinic-{env}/genai-service` |
| `spring-petclinic-admin-server` | `spring-petclinic-admin-server-*.jar` | `petclinic-{env}/admin-server` |

---

## Terraform Modules

### Module: `vpc`

**Path:** `terraform/modules/vpc/`

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | `"petclinic"` |
| `environment` | string | Environment (dev/prod) | — |
| `vpc_cidr` | string | VPC CIDR block | — |
| `public_subnet_cidrs` | list(string) | Public subnet CIDRs (ALB, NAT) | — |
| `private_subnet_cidrs` | list(string) | Private subnet CIDRs (EKS, RDS) | — |
| `availability_zones` | list(string) | AZs for subnets | — |
| `single_nat_gateway` | bool | `true` = one NAT (dev). `false` = NAT per AZ (prod). | — |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `vpc_id` | string | VPC ID |
| `public_subnet_ids` | list(string) | Public subnet IDs |
| `private_subnet_ids` | list(string) | Private subnet IDs |
| `nat_gateway_ids` | list(string) | NAT Gateway IDs (1 in dev, 2 in prod) |
| `s3_gateway_endpoint_id` | string | S3 Gateway VPC endpoint ID |
| `eks_cluster_sg_id` | string | EKS cluster security group ID |
| `eks_node_sg_id` | string | EKS node security group ID |
| `rds_sg_id` | string | RDS security group ID |
| `alb_sg_id` | string | ALB security group ID |

### Module: `eks`

**Path:** `terraform/modules/eks/`

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | — |
| `environment` | string | Environment | — |
| `cluster_version` | string | Kubernetes version | `"1.34"` |
| `subnet_ids` | list(string) | **Private** subnet IDs for cluster and nodes | — |
| `public_access_cidrs` | list(string) | CIDRs allowed to reach the public API. Root passes this from `terraform.tfvars` (operator public IPv4 `/32`). | — |
| `cluster_sg_id` | string | Cluster security group ID | — |
| `node_sg_id` | string | Node security group ID | — |
| `node_instance_types` | list(string) | Instance types for nodes | `["t4g.small"]` |
| `node_ami_type` | string | AMI type for nodes | `"AL2023_ARM_64"` |
| `node_min_size` | number | Min node count | `2` |
| `node_max_size` | number | Max node count | `4` |
| `node_desired_size` | number | Desired node count | `2` |
| `node_disk_size` | number | Disk size in GB | `20` |
| `install_ebs_csi` | bool | Create EBS CSI IRSA + `aws_eks_addon` + gp3 StorageClass. True only when the cluster already exists (same gate as `install_eso`) | — |
| `tags` | map(string) | Additional tags | `{}` |

Add-ons: `coredns`, `kube-proxy`, `vpc-cni`, `aws-ebs-csi-driver`, `metrics-server`. Versions from `data.aws_eks_addon_version` (`most_recent` for `cluster_version`) — do not set the addon version to the string `latest`. EBS CSI SA `ebs-csi-controller-sa` in `kube-system`, role `petclinic-{env}-ebs-csi-role`, policy `AmazonEBSCSIDriverPolicy`. StorageClass name `gp3`, default, `WaitForFirstConsumer`, type `gp3`. Kubernetes provider on the env root (same exec as Helm) is required for the StorageClass. `metrics-server` has no extra IRSA.

On `vpc-cni`, set `configuration_values` so network policy is on: `enableNetworkPolicy = "true"` (Amazon VPC CNI, not Calico). Same `install_ebs_csi` gate as the add-on itself.

| Output | Type | Description |
|--------|------|-------------|
| `cluster_name` | string | EKS cluster name |
| `cluster_endpoint` | string | EKS API endpoint |
| `cluster_ca_certificate` | string | Cluster CA certificate (base64) |
| `oidc_provider_arn` | string | OIDC provider ARN |
| `oidc_provider_url` | string | OIDC provider URL |
| `node_group_name` | string | Managed node group name |
| `node_role_arn` | string | Node IAM role ARN |
| `ebs_csi_role_arn` | string | IRSA role for the EBS CSI controller |

### Module: `ecr`

**Path:** `terraform/modules/ecr/`

Uses `aws_ecr_repository` with lifecycle policies, scan-on-push, AES256 `encryption_configuration`, and configurable tag immutability.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | — |
| `environment` | string | Environment (dev/prod) | — |
| `service_names` | list(string) | Service names for repos | — |
| `image_tag_mutability` | string | `MUTABLE` (dev) or `IMMUTABLE` (prod) | — |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `repository_urls` | map(string) | Map of service_name → ECR repository URL |
| `repository_arns` | map(string) | Map of service_name → ECR repository ARN |

> **Note:** ECR repos are created per environment (`petclinic-dev/`, `petclinic-prod/`). Tag mutability is `MUTABLE` for dev, `IMMUTABLE` for prod — both `service_names` and `image_tag_mutability` come from `terraform.tfvars`. Root `outputs.tf` exports `repository_urls` only; `repository_arns` stay on the module. CI (PETPLAT-49) pushes the same SHA to both prefixes.

### Module: `github-oidc`

**Path:** `terraform/modules/github-oidc/`

Account-scoped GitHub Actions → AWS OIDC. **Not** the EKS IRSA provider. Called from `terraform/environments/dev/` only.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `github_org` | string | GitHub org or user that owns the app fork | — |
| `github_app_repo` | string | App repo name (no org prefix), e.g. `spring-petclinic-microservices` | — |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `github_actions_role_arn` | string | IAM role ARN for `AWS_ROLE_ARN` on the app fork |

Trust: `repo:{github_org}/{github_app_repo}:ref:refs/heads/main`. Role name: `petclinic-github-actions-role`. ECR push on `petclinic-dev/*` and `petclinic-prod/*` only.

### Module: `rds`

**Path:** `terraform/modules/rds/`

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | — |
| `environment` | string | Environment | — |
| `subnet_ids` | list(string) | **Private** subnet IDs for DB subnet group | — |
| `security_group_id` | string | RDS security group ID | — |
| `instance_class` | string | RDS instance class | `"db.t4g.micro"` |
| `allocated_storage` | number | Initial storage in GB | `20` |
| `max_allocated_storage` | number | Max autoscale storage in GB | `20` |
| `multi_az` | bool | Multi-AZ deployment | `false` |
| `backup_retention_period` | number | Backup retention in days | `7` |
| `skip_final_snapshot` | bool | Skip final snapshot on delete | `true` |
| `deletion_protection` | bool | Deletion protection | `false` |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `endpoint` | string | RDS endpoint hostname |
| `port` | number | RDS port (3306) |
| `db_instance_id` | string | RDS instance ID |
| `secret_arn` | string | Secrets Manager secret ARN for RDS credentials |

### Module: `dns`

**Path:** `terraform/modules/dns/`

Route 53 zone lookup (optional create), **one** wildcard ACM cert (create in at most one env; others look it up), AWS Load Balancer Controller IRSA + `helm_release`, ExternalDNS IRSA + `helm_release`. Does **not** create an ALB alias record. OIDC comes from the EKS module. Helm/Kubernetes providers live on the env root (same as ESO).

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | — |
| `environment` | string | `dev` or `prod` | — |
| `domain_name` | string | Public parent domain (hosted zone name) | — |
| `create_hosted_zone` | bool | Create the public zone. True in **at most one** env; prod wiring is always lookup | `false` |
| `create_acm_certificate` | bool | Create the `*.{domain}` wildcard cert. True in **at most one** env (typically dev). Prod is always lookup | `false` |
| `vpc_id` | string | VPC ID (LB controller `vpcId`) | — |
| `cluster_name` | string | EKS cluster name (`petclinic-{env}`) | — |
| `oidc_provider_arn` | string | EKS OIDC provider ARN | — |
| `oidc_provider_url` | string | EKS OIDC provider URL | — |
| `install_lb_controller` | bool | `helm_release` for the LB controller. True only if the cluster already exists | — |
| `install_external_dns` | bool | `helm_release` for ExternalDNS. True only if the cluster already exists | — |
| `lb_controller_chart_version` | string | Pin **3.5.0** | — |
| `external_dns_chart_version` | string | Pin **1.21.1** | — |
| `argocd_ingress_enabled` | bool | Dedicated Argo CD ALB security group. Ingress YAML is operator-applied | — |
| `node_sg_id` | string | Node SG the Argo CD ALB may reach on :8080 | — |
| `argocd_ingress_cidrs` | list(string) | Operator CIDRs allowed to the Argo CD ALB | — |
| `tags` | map(string) | Additional tags | `{}` |

FQDN is derived: `petclinic-dev.{domain_name}` or `petclinic.{domain_name}` (Ingress host). The ACM cert itself is `*.{domain_name}`.

| Output | Type | Description |
|--------|------|-------------|
| `zone_id` | string | Route 53 hosted zone ID |
| `name_servers` | list(string) | NS records (needed if this module created the zone) |
| `fqdn` | string | Env hostname (`petclinic-dev.{domain}` / `petclinic.{domain}`) |
| `certificate_arn` | string | Wildcard ACM ARN `*.{domain}` (operator copies into **both** `helm-values/{env}.yaml` as `CERT_ARN`) |
| `lb_controller_role_arn` | string | IRSA role for the LB controller |
| `external_dns_role_arn` | string | IRSA role for ExternalDNS |
| `argocd_url` | string | `https://argocd-{env}.{domain}` when ingress is enabled |
| `argocd_host` | string | Hostname only |
| `ops_alb_sg_id` | string | Ops ALB SG when `shared_alb=false`; replaces `OPS_ALB_SG_ID` in prod Argo ingress. Empty when shared (use root `alb_sg_id`) |
| `argocd_load_balancer_name` | string | ALB name annotation |

### Module: `secrets`

**Path:** `terraform/modules/secrets/`

Non-RDS Secrets Manager secret, the ESO IRSA role (PETPLAT-33, PETPLAT-37), and the ESO Helm release (PETPLAT-34). Uses `aws_secretsmanager_secret` / `aws_secretsmanager_secret_version` and `helm_release`. OIDC comes from the EKS module — this module does not create an OIDC provider. ClusterSecretStore and app ExternalSecrets are Git YAML, not Terraform.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | — |
| `environment` | string | Environment | — |
| `openai_api_key` | string | OpenAI API key value (sensitive; from tfvars / `TF_VAR_`, never hardcoded) | — |
| `oidc_provider_arn` | string | EKS OIDC provider ARN (for ESO IRSA) | — |
| `oidc_provider_url` | string | EKS OIDC provider URL (for ESO IRSA trust) | — |
| `install_eso` | bool | When true, `helm_release` installs ESO 2.10.0. Must be true only if the cluster already exists. | — |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `openai_secret_arn` | string | Secrets Manager ARN for OpenAI API key |
| `eso_role_arn` | string | IAM role ARN for ESO (`petclinic-{env}-eso-role`) |

Note: RDS credentials are NOT managed by this module — they are in the `rds` module (PETPLAT-23). Do not add `kms:Decrypt`; secrets use the default `aws/secretsmanager` key.

### Module: `observability`

**Path:** `terraform/modules/observability/`

In-cluster metrics, logs, and traces. **Not** CloudWatch. Helm releases gated by `install_observability`. Helm + Kubernetes providers on the env root.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name | — |
| `environment` | string | `dev` or `prod` | — |
| `install_observability` | bool | `helm_release` for the stack. True only if the cluster already exists | — |
| `kube_prometheus_stack_chart_version` | string | Pin **88.6.2** | — |
| `loki_chart_version` | string | Pin **18.7.6** | — |
| `fluent_bit_chart_version` | string | Pin **0.53.0** | — |
| `grafana_ingress_enabled` | bool | Dedicated HTTPS ALB for Grafana | — |
| `zipkin_ingress_enabled` | bool | Dedicated HTTPS ALB for the Zipkin UI | — |
| `domain_name` | string | Parent domain for grafana/zipkin hostnames | — |
| `certificate_arn` | string | Wildcard ACM ARN | — |
| `vpc_id` | string | VPC for the Grafana and Zipkin ALB security groups | — |
| `node_sg_id` | string | Node SG Grafana ALB may reach on :3000; Zipkin on :9411 | — |
| `grafana_ingress_cidrs` | list(string) | Operator CIDRs allowed to the Grafana and Zipkin ALBs (same as EKS `public_access_cidrs`) | — |
| `slack_webhook_url` | string | Sensitive Slack incoming webhook. Empty = blackhole. Never Git | `""` |
| `slack_channel` | string | Slack channel including `#` | `#petclinic-alerts` |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `grafana_admin_password` | string | Sensitive. Operator retrieves after apply. Never Git |
| `grafana_url` | string | `https://grafana-{env}.{domain}` when ingress is enabled |
| `grafana_host` | string | Hostname only |
| `zipkin_url` | string | `https://zipkin-{env}.{domain}` when ingress is enabled |
| `zipkin_host` | string | Hostname only |

### Module: `karpenter`

**Path:** `terraform/modules/karpenter/`

IAM, SQS interruption queue, EventBridge, instance profile wrapping the **existing** EKS node role, and gated Helm (`karpenter` + `karpenter-crd`). NodePool / EC2NodeClass are Git YAML, not the Kubernetes provider. Follow `.claude/rules/karpenter.md`.

| Input Variable | Type | Description | Default |
|---------------|------|-------------|---------|
| `project` | string | Project name (root passes `var.project`; no module default) | — |
| `environment` | string | Environment | — |
| `cluster_name` | string | EKS cluster name (`petclinic-{env}`) | — |
| `cluster_endpoint` | string | EKS API endpoint (Helm settings if the chart needs it) | — |
| `oidc_provider_arn` | string | OIDC provider ARN (IRSA) | — |
| `oidc_provider_url` | string | OIDC issuer URL (IRSA trust `sub`) | — |
| `node_role_arn` | string | Existing managed-node IAM role ARN (`module.eks.node_role_arn`). Do **not** create a second node role. | — |
| `install_karpenter` | bool | `helm_release` for Karpenter + CRD chart. True only when this env's cluster already exists | — |
| `tags` | map(string) | Additional tags | `{}` |

| Output | Type | Description |
|--------|------|-------------|
| `karpenter_role_arn` | string | Controller IRSA role ARN |
| `karpenter_queue_name` | string | SQS interruption queue name (Helm `settings.interruptionQueue`) |
| `karpenter_instance_profile_name` | string | `petclinic-{env}-karpenter-node-profile` |

Do not default `project` to `"petclinic"`. Do not shrink the managed node group.

## Helm Charts

### Architecture Decision

Helm replaces plain K8s YAML + Kustomize overlays. A **single generic chart** (`helm/petclinic-service/`) is shared by all 8 services. Per-service and per-environment configuration is in `helm-values/`. See [ADR-0007](#adr-index).

### Chart Structure

```
helm/
└── petclinic-service/
    ├── Chart.yaml              # name: petclinic-service, version: 0.1.0
    ├── values.yaml             # Defaults (common to all services)
    └── templates/
        ├── deployment.yaml     # Deployment with probes, resources, env vars, init containers
        ├── service.yaml        # ClusterIP Service
        ├── configmap.yaml      # Non-secret configuration
        ├── serviceaccount.yaml # ServiceAccount with IRSA annotation
        ├── hpa.yaml            # HPA (conditional on .Values.autoscaling.enabled)
        ├── pdb.yaml            # PDB (conditional on .Values.podDisruptionBudget.enabled)
        ├── ingress.yaml        # ALB Ingress (conditional on .Values.ingress.enabled)
        └── _helpers.tpl        # Template helpers (labels, names, selectors)
```

### values.yaml Defaults

```yaml
name: ""        # Service name; used for replicaOverrides lookup and every label
component: service   # app.kubernetes.io/component: server | gateway | service | admin
replicaCount: 1
replicaOverrides: {}   # Prod: genai-service: 1, admin-server: 1

image:
  registry: ""   # Env file: ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}
  name: ""       # Service file: config-server, api-gateway, ...
  tag: "TAG"     # Never latest. CI replaces with commit SHA later
  pullPolicy: IfNotPresent

service:
  port: 8080       # Overridden per-service

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

probes:
  startup:
    path: /actuator/health
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30
  readiness:
    path: /actuator/health/readiness
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3
  liveness:
    path: /actuator/health/liveness
    periodSeconds: 15
    timeoutSeconds: 5
    failureThreshold: 3

springProfiles: docker
configData: {}       # Non-secret ConfigMap entries; SERVER_PORT is added from service.port
env: []              # Additional plain env vars: [{name, value}]
secrets: []          # Secret-backed env vars: [{name, secretName, key}] — never values
initContainers: []   # Wait-for containers (set per-service)

serviceAccount:
  create: true
  annotations: {}    # IRSA role ARN goes here if a service ever needs AWS access

autoscaling:
  enabled: false     # Per-service: true only for gateway, customers, visits, vets, genai
  minReplicas: 2
  maxReplicas: 4
  targetCPUUtilizationPercentage: 70

podDisruptionBudget:
  enabled: false     # Per-service: true only for the six E-9 PDB services
  minAvailable: 1

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: false   # Spring Boot writes to /tmp

ingress:
  enabled: false     # true only in helm-values/api-gateway.yaml
  className: alb
  host: ""
  certificateArn: ""
  albSecurityGroupId: ""
  loadBalancerName: ""
```

Image render: `{{ .Values.image.registry }}/{{ .Values.image.name }}:{{ .Values.image.tag }}`. Replica render: `replicaOverrides.{name}` if set, else `replicaCount`. Config Server probe paths are all `/actuator/health`.

### Per-Service Values (`helm-values/`)

```
helm-values/
├── config-server.yaml         # port: 8888, no init containers, no MySQL
├── discovery-server.yaml      # port: 8761, wait-for-config init container
├── api-gateway.yaml           # port: 8080, higher CPU (200m/1000m), ingress.enabled: true
├── customers-service.yaml     # port: 8081, MySQL env vars, wait-for inits
├── visits-service.yaml        # port: 8082, MySQL env vars, wait-for inits
├── vets-service.yaml          # port: 8083, MySQL env vars, wait-for inits
├── genai-service.yaml         # port: 8084, OPENAI_API_KEY env var, HPA on, PDB off
├── admin-server.yaml          # port: 9090, no HPA, no PDB
├── dev.yaml                   # replicaCount=1, HPA/PDB forced off, image.registry .../petclinic-dev, ingress host/cert/SG
└── prod.yaml                  # replicaCount=2, replicaOverrides genai/admin=1, registry .../petclinic-prod, ingress host/cert/SG
                               # Do not globally enable HPA/PDB here
```

`dev.yaml` sets `autoscaling.enabled: false` and `podDisruptionBudget.enabled: false` (env is merged last). `prod.yaml` omits those keys so per-service flags apply.

Chart default `ingress.enabled: false`. Only `api-gateway.yaml` sets it true. Env files set `ingress.host`, `ingress.certificateArn` (`CERT_ARN`), `ingress.albSecurityGroupId` (`ALB_SG_ID`), `ingress.loadBalancerName` (`petclinic-{env}`). Host is `petclinic-dev.DOMAIN` / `petclinic.DOMAIN`.

### Helm Install / Upgrade Command

```bash
# Deploy a service (example: customers-service to dev)
helm upgrade --install customers-service helm/petclinic-service/ \
  -n petclinic-dev \
  -f helm-values/customers-service.yaml \
  -f helm-values/dev.yaml \
  --set image.tag=${SHA}
```

Operator runs live install. Claude uses `helm template` and `kubectl apply --dry-run=client` only.

Validate every release before committing:

```bash
# All 8 services x both environments: lint, template, dry-run
./scripts/validate-helm.sh

# Narrow it down
./scripts/validate-helm.sh --env prod --service api-gateway
```

Adding a service: add `helm-values/{service}.yaml` (name, component, image.name,
service.port, springProfiles, configData, secrets, initContainers, resources,
autoscaling/podDisruptionBudget flags), then add it to the service list in
`scripts/validate-helm.sh`. Its ArgoCD ApplicationSet comes from E-17.

ArgoCD automates this — see [GitOps with ArgoCD](#gitops-with-argocd).

---

## GitOps with ArgoCD

### Architecture Decision

ArgoCD handles all deployments (CD). GitHub Actions is CI-only (build, push, commit image tags). **One ArgoCD per EKS cluster** (dev and prod are separate clusters). Same Git install overlay; apply `applications/dev/` only on the dev cluster and `applications/prod/` only on prod. In-cluster destination (`https://kubernetes.default.svc`) is correct **because** ArgoCD is not a hub talking to the other cluster. See [ADR-0008](#adr-index).

Do **not** create `petclinic-{env}-argocd-role` IRSA — ArgoCD only reads Git and applies to its own cluster.

### ArgoCD Installation

| Parameter | Value |
|-----------|-------|
| Namespace | `argocd` |
| Version | **v3.5.2** (pinned) |
| Manifest | Non-HA official `manifests/install.yaml` |
| Git | `k8s/argocd/install/` — Kustomize references the pinned URL; do not rewrite upstream objects |
| Apply (operator) | `kubectl apply -k k8s/argocd/install/ --server-side --force-conflicts` on **each** cluster (server-side avoids ApplicationSet CRD annotation size limit) |
| Access | Dedicated HTTPS ALB `https://argocd-{env}.{domain}` (prod: `https://argocd.{domain}`), CIDR-locked. Port-forward fallback: `kubectl port-forward svc/argocd-server -n argocd 8443:443` |
| Admin password | Cluster secret `argocd-initial-admin-secret` — never commit |

Private GitHub repo: operator adds a repository credential Secret in `argocd`. Claude does not put tokens in Git.

### Directory layout

```
k8s/argocd/
  install/           # Kustomize: namespace + pinned official install.yaml
  ingress/           # dedicated ALB UI YAML per env (not in the install kustomization)
  projects/          # AppProject per env (destination lock)
  applications/
    dev/applicationset.yaml
    prod/applicationset.yaml
```

### AppProjects

| Project | Applied on | Allowed destination |
|---------|------------|---------------------|
| `petclinic-dev` | Dev cluster | namespace `petclinic-dev`, in-cluster |
| `petclinic-prod` | Prod cluster | namespace `petclinic-prod`, in-cluster |

`sourceRepos`: `https://github.com/GITHUB_ORG/petclinic-platform.git` (placeholder).

### ApplicationSet (not 16 copied Applications)

List generator over the 8 service names. Template name `{service}-{env}`. Labels include `environment: {env}` (for `argocd app sync -l environment=dev`).

Helm values live **outside** the chart, so use **multiple sources** and `$values` — never `../../helm-values/`. Last values file wins (env after service).

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: petclinic-dev
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - list:
        elements:
          - service: config-server
          - service: discovery-server
          - service: api-gateway
          - service: customers-service
          - service: visits-service
          - service: vets-service
          - service: genai-service
          - service: admin-server
  template:
    metadata:
      name: "{{.service}}-dev"
      namespace: argocd
      labels:
        environment: dev
        app.kubernetes.io/name: "{{.service}}"
        app.kubernetes.io/part-of: petclinic
        app.kubernetes.io/managed-by: argocd
    spec:
      project: petclinic-dev
      sources:
        - repoURL: https://github.com/GITHUB_ORG/petclinic-platform.git
          targetRevision: main
          path: helm/petclinic-service
          helm:
            releaseName: "{{.service}}"
            valueFiles:
              - $values/helm-values/{{.service}}.yaml
              - $values/helm-values/dev.yaml
        - repoURL: https://github.com/GITHUB_ORG/petclinic-platform.git
          targetRevision: main
          ref: values
      destination:
        server: https://kubernetes.default.svc
        namespace: petclinic-dev
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

Prod ApplicationSet: name `{service}-prod`, project `petclinic-prod`, namespace `petclinic-prod`, values file `prod.yaml`, **omit** `syncPolicy.automated`. `CreateNamespace=true` may remain.

### Sync Policies

| Environment | Auto-Sync | Prune | Self-Heal | Manual Approval |
|-------------|-----------|-------|-----------|-----------------|
| Dev | Yes | Yes | Yes | No |
| Prod | No | No | No | Yes (ArgoCD UI/CLI on the **prod** cluster) |

### Bootstrap (operator, not Helm)

Before the first sync: apply `k8s/base/namespaces.yaml` and ESO CRs (`ClusterSecretStore`, `rds-credentials`, `openai-api-key`). Do **not** apply `k8s-reference/base/*/deployment.yaml` once ArgoCD owns the workloads. The API Gateway Ingress is part of the Helm chart (E-6), not a separate ArgoCD Application.

### GitOps Flow

```
Developer pushes code to the app fork → GitHub Actions builds + pushes ARM64 images to ECR (dev and prod prefixes)
  → repository_dispatch to the platform repo
  → GitHub Actions commits image tag to helm-values/{service}.yaml
    → ArgoCD on the matching cluster detects Git change
      → Dev cluster: auto-syncs immediately
      → Prod cluster: OutOfSync until manual sync
```

---

## Karpenter (Node Autoscaling)

Claude writes Terraform + Git YAML (`terraform validate`, `helm template` / `helm lint`). The operator applies. **Not** ArgoCD. **Not** `helm upgrade --install` from the CLI. Follow `.claude/rules/karpenter.md`.

### Architecture Decision

Karpenter provisions **additional** nodes via the EC2 Fleet API when pods are Pending. It does **not** replace the managed node group. See [ADR-0009](#adr-index).

Keep the EKS managed node group at min/desired **2** `t4g.small` ON_DEMAND. Those nodes run Karpenter, CoreDNS, and the rest of the system. Karpenter only deletes nodes **it** created. Do not set the node group min to 0.

### This build: on-demand only

Graviton free trial is active until Dec 2026. NodePool `karpenter.sh/capacity-type` is **`["on-demand"]` only**. PETPLAT-74 (add `spot`) is parked. A comment in the YAML may note the future values; do not require spot instances.

### Prerequisites (Terraform, `terraform/modules/karpenter/`)

| Resource | Purpose |
|----------|---------|
| Controller IRSA `petclinic-{env}-karpenter-role` | SA `karpenter` in namespace `karpenter`. Vendored official 1.14 controller policy. No `ec2:*`. |
| Instance profile `petclinic-{env}-karpenter-node-profile` | Wraps **existing** `module.eks.node_role_arn`. No second node IAM role (no extra access entry / `aws-auth`). |
| SQS interruption queue | Helm `settings.interruptionQueue` = this queue's **name** |
| EventBridge rules | Spot interruption, rebalance, instance state-change, health → SQS (harmless while on-demand; ready for PETPLAT-74) |

Gate: `install_karpenter` (same idea as `install_eso`). Wire `module.karpenter` in **dev and prod**.

### Installation

| Parameter | Value |
|-----------|-------|
| Namespace | `karpenter` (`create_namespace = true`). Do **not** add it to ArgoCD AppProjects. |
| Charts | OCI `oci://public.ecr.aws/karpenter/karpenter` **1.14.0** and `karpenter-crd` **1.14.0** |
| ServiceAccount | `karpenter`, annotation `eks.amazonaws.com/role-arn` = controller role |
| Helm settings | `settings.clusterName` = cluster name; `settings.interruptionQueue` = SQS queue name |

Install CRDs via the `karpenter-crd` chart, then the controller. Do **not** `kubernetes_manifest` NodePool/EC2NodeClass in the same apply as the CRD chart (CRD race, same as ESO).

### NodePool / EC2NodeClass (Git YAML)

Path: `k8s/karpenter/{dev,prod}/`. Operator `kubectl apply`. Cluster-scoped — not ArgoCD.

**EC2NodeClass selectors must match this VPC** (the old `petclinic-{env}-node-sg` name is wrong):

- Subnets: `kubernetes.io/role/internal-elb: "1"` (private only). Do **not** select only `kubernetes.io/cluster/petclinic-{env}=shared` — public subnets have that tag too.
- Security group: tag `Name: petclinic-{env}-sg-eks-node` (resource `petclinic-{env}-sg-eks-node`).
- `instanceProfile: petclinic-{env}-karpenter-node-profile`
- `amiSelectorTerms: alias: al2023@latest` — this is Karpenter's AMI **alias**, not the EKS add-on string `latest`. Allowed.

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
          # After Graviton trial (Dec 2026): ["spot", "on-demand"] — PETPLAT-74
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t4g.small", "t4g.medium"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: "8"
    memory: "16Gi"
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
```

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  subnetSelectorTerms:
    - tags:
        kubernetes.io/role/internal-elb: "1"
        kubernetes.io/cluster/petclinic-{env}: "shared"
  securityGroupSelectorTerms:
    - tags:
        Name: "petclinic-{env}-sg-eks-node"
  instanceProfile: "petclinic-{env}-karpenter-node-profile"
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
```

Instance types belong on the **NodePool**, not on EC2NodeClass. Do not invent a second NodePool "weight" to prefer spot in this build.

### Scale tests and quotas

`petclinic-dev` ResourceQuota is 4 CPU / 4Gi — the same as two `t4g.small`s. Extra Deployments in that namespace will hit the quota and never go Pending on a node, so Karpenter will not scale. Live scale tests (operator) use a throwaway namespace **without** that quota, not `petclinic-dev`. Claude does not run those tests.

### Metrics Server

PETPLAT-72. EKS managed add-on `metrics-server` in `terraform/modules/eks/`, same `install_ebs_csi` gate, version from `data.aws_eks_addon_version`. HPA YAML already exists in Helm; this add-on makes it work after apply. `kubectl top` is operator, not the Claude story.

---

## Documentation

Operational docs live in `docs/`. Claude writes **markdown only** (E-15). No Terraform, no Helm install, no `kubectl apply`, no `terraform destroy`.

Follow `.claude/rules/docs.md`. Filenames are locked:

| File | Story | Notes |
|------|-------|--------|
| `docs/architecture.md` | PETPLAT-77 | Diagrams + links to this spec. Do not copy every table. Cost: link [Scaling and Cost](#scaling-and-cost). No `docs/cost.md`. |
| `docs/runbook.md` | PETPLAT-78 | Day-2 ops. Includes EKS upgrade, Terraform state, GitOps deploy. |
| `docs/secret-rotation.md` | PETPLAT-78 | Manual rotation only. No `aws_secretsmanager_secret_rotation`. |
| `docs/incident-playbook.md` | PETPLAT-79 | Failure scenarios + SEV/RCA (folded PETPLAT-104). |
| `docs/onboarding.md` | PETPLAT-80 | Role placeholders only. No personal names/emails. |
| `docs/monitoring-guide.md` | PETPLAT-97 | Not `monitoring-alerting-guide.md`. |
| `docs/dr-plan.md` | PETPLAT-99 | Not `disaster-recovery.md`. No “lessons from PETPLAT-90.” |
| `docs/compliance-checklist.md` | PETPLAT-100 | CloudTrail is **not** in this stack — say so. |
| `docs/adr/0001` … `0013-*.md` | PETPLAT-81 | Filenames in [ADR Index](#adr-index). Include 0009 Karpenter (E-14 unbuilt) and 0011/0012. |

**Placeholders in docs:** `{domain}`, `{account}`, `{env}` — never a real AWS account ID, never a real domain, never secrets.

**Access that is true of this stack:**

- App URL: `https://petclinic-dev.{domain}` / `https://petclinic.{domain}` (ExternalDNS). Live “open the app” is operator (PETPLAT-48).
- Grafana: `https://grafana-dev.{domain}` / `https://grafana.{domain}` (dedicated ALB, CIDR-locked). Password: `terraform output grafana_admin_password` (sensitive). Never write a sample password.
- Zipkin: `https://zipkin-dev.{domain}` / `https://zipkin.{domain}` (dedicated ALB, CIDR-locked). Apps still send spans in-cluster.
- Argo CD: `https://argocd-dev.{domain}` / `https://argocd.{domain}` (dedicated ALB, CIDR-locked). Password: cluster secret `argocd-initial-admin-secret`.
- Prometheus, Alertmanager: `kubectl port-forward` only. No Ingress.
- Alertmanager: Slack via gitignored `slack_webhook_url`, or blackhole if empty. No webhook URLs in Git.
- App deploy/rollback: ArgoCD ApplicationSet + Git tag, not `helm upgrade --install` or `kubectl apply` on Spring Deployments.
- Logs: Loki via Grafana Explore (not CloudWatch).
- RDS: debug pod (`kubectl run` MySQL client). Not a bastion.
- NetworkPolicy YAML: `k8s/security/{dev,prod}/` after VPC CNI `enableNetworkPolicy`. Not ArgoCD.

PETPLAT-90 (live `terraform destroy` + rebuild) is **parked**. Do not run destroy. Document rebuild steps in `dr-plan.md` from this spec.

---

## ADR Index

Architecture Decision Records are stored in `docs/adr/`. Write them in E-15 (PETPLAT-81). Date: **2026-09-02**. ADR-0009 is still written even though Karpenter (E-14) is unbuilt.

| File | Title | Status | Summary |
|------|-------|--------|---------|
| `docs/adr/0001-network-layout.md` | Public/private subnets + NAT | Accepted | Production layout. Public: ALB + NAT. Private: EKS + RDS (no public IPs). Dev: 1 NAT. Prod: NAT per AZ (HA). Supersedes the original all-public / no-NAT lab design. |
| `docs/adr/0002-eks-over-ecs.md` | EKS over ECS | Accepted | EKS chosen for industry relevance and Kubernetes learning. ECS would be simpler but less transferable. |
| `docs/adr/0003-shared-rds.md` | Shared RDS instance for all services | Accepted | Single `petclinic` database shared by 3 services. Matches app design (FK constraints cross-service). Simpler ops, lower cost. |
| `docs/adr/0004-plain-yaml-over-helm.md` | Plain K8s YAML over Helm | Superseded by ADR-0007 | Originally chose Kustomize for transparency. Superseded by Helm for industry relevance. |
| `docs/adr/0005-github-actions-oidc.md` | GitHub Actions with OIDC federation | Accepted | No long-lived AWS credentials. OIDC federation is the AWS-recommended pattern. GitHub Actions for CI. |
| `docs/adr/0006-single-az-rds.md` | Single-AZ RDS for both environments | Accepted | Cost optimization for learning. Multi-AZ doubles RDS cost. Students learn when to enable it. |
| `docs/adr/0007-helm-over-plain-yaml.md` | Helm over plain K8s YAML | Accepted | Generic Helm chart shared across 8 services. Per-service values files. Industry-standard packaging. Enables ArgoCD GitOps. Trade-off: Helm templating is less transparent than raw YAML. |
| `docs/adr/0008-argocd-gitops.md` | ArgoCD for GitOps (CD) | Accepted | ArgoCD watches Git, syncs Helm releases. CI (GitHub Actions) pushes images and commits tags. CD is fully declarative. Dev auto-syncs, prod requires manual approval. |
| `docs/adr/0009-karpenter.md` | Karpenter over Cluster Autoscaler | Accepted | Faster node provisioning, better Spot diversification, EC2 Fleet API. Industry trend replacing CAS. Trade-off: more complex IAM setup. E-14 is unbuilt; the ADR still stands. |
| `docs/adr/0010-ecr-private.md` | ECR Private (production-correct pattern) | Accepted | Private ECR teaches the production pattern: IAM-controlled access, lifecycle policies, scan-on-push, tag immutability. Cost: ~$1/month — negligible. |
| `docs/adr/0011-secrets-manager.md` | Secrets Manager for secrets storage | Accepted | Industry-standard secrets management ($0.40/secret/month, ~$1.20 total). Built-in rotation capability, fine-grained IAM. Teaches students the production-grade approach. |
| `docs/adr/0012-externaldns.md` | ExternalDNS for ALB hostnames | Accepted | ALB is created by the AWS Load Balancer Controller after Ingress sync, so Terraform cannot alias on first apply. ExternalDNS watches Ingress hosts and writes Route 53. Terraform owns zone lookup + ACM only. |
| `docs/adr/0013-loki-over-cloudwatch.md` | Loki over CloudWatch Logs | Accepted | Logs stay in-cluster (Fluent Bit → Loki → Grafana). No CloudWatch log groups or FluentBit IRSA. |
