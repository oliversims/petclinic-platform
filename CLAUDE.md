# Petclinic Platform — Claude Code Instructions

This repo contains ALL infrastructure code for deploying Spring Petclinic Microservices to AWS.
The application repo (spring-petclinic-microservices) is READ-ONLY except one E-10 file: `.github/workflows/build-push.yml` in the app fork. Do not change Java, pom.xml, or Dockerfiles.

## Directory Layout

```
terraform/environments/{dev,prod}/   # Root modules (one per environment)
terraform/modules/{vpc,eks,ecr,rds,dns,secrets,observability,karpenter,github-oidc}/
helm/petclinic-service/              # Generic Helm chart (shared by all 8 services)
helm/zipkin/                         # In-repo Zipkin chart (Terraform helm_release, not ArgoCD)
helm-values/                         # Per-service YAML + per-env (dev.yaml, prod.yaml)
k8s/base/                            # Namespaces, external-secrets CRs (live)
k8s/security/{dev,prod}/             # NetworkPolicies, ResourceQuota, LimitRange (E-13)
k8s/observability/                   # Grafana dashboards + PrometheusRules (not Spring Deployments)
k8s/argocd/install/                  # ArgoCD install (Kustomize, pinned v3.5.2)
k8s/argocd/projects/                 # AppProject per env
k8s/argocd/applications/{dev,prod}/  # One ApplicationSet per env
k8s/karpenter/{dev,prod}/            # NodePool + EC2NodeClass (E-14; operator apply, not ArgoCD)
k8s-reference/                       # Pre-Helm plain YAML + overlays (do not apply for live path)
.github/workflows/                    # Platform CI: update-image-tags.yml only (build-push lives in the app fork)
scripts/                             # Operational scripts
docs/                                # Architecture docs, runbooks, ADRs
```

## Terraform Conventions

- **Provider:** AWS provider ~> 5.0, region us-east-1
- **ECR:** Uses `aws_ecr_repository` in us-east-1 with lifecycle policies, scan-on-push, AES256 `encryption_configuration`, and configurable tag immutability
- **State:** S3 + DynamoDB locking, key pattern: `petclinic/{env}/terraform.tfstate`
- **Modules:** All reusable modules in `terraform/modules/`. Environments call modules.
- **Naming:** `petclinic-{env}-{resource}` (e.g., `petclinic-dev-vpc`, `petclinic-prod-eks`)
- **Tagging:** Every resource MUST have tags: `Project=petclinic`, `Environment={dev|prod}`, `ManagedBy=terraform`
- **Variables:** Use `variable` blocks with `description` and `type`. Root-module `aws_region`, `environment`, and `project` have no defaults.
- **tfvars:** `terraform.tfvars` is the source of values: `aws_region`, `environment`, `project`. Do not repeat those values as defaults in `variables.tf`.
- **No extras:** Do not create `*.example` files or `backend.hcl`. Put the S3 backend fully in `backend.tf`. Only create what the Jira acceptance criteria ask for.
- **Outputs:** Export IDs, ARNs, and endpoints needed by downstream modules
- **Sensitive values:** Never hardcode secrets. Use `sensitive = true` for secret outputs.
- **Formatting:** Run `terraform fmt` before committing. Use `terraform validate` after edits.
- **Files per module:** `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (provider constraints). Modules do not default `project` to `"petclinic"`; the root module passes `var.project`.
- **ESO:** Installed with `helm_release` in the secrets module (`install_eso` true only when the EKS cluster already exists). ClusterSecretStore and ExternalSecrets are Git YAML, not the Kubernetes provider.
- **DNS / Ingress:** dns module looks up (or optionally creates once) the public hosted zone, issues **one** wildcard ACM cert `*.{domain}` from at most one env, and installs the AWS Load Balancer Controller + ExternalDNS with gated `helm_release`. No Terraform alias to the ALB. Ingress is Helm on api-gateway. Follow `.claude/rules/dns.md`.
- **Observability:** `terraform/modules/observability/` installs kube-prometheus-stack, Loki, Fluent Bit, and Zipkin with gated `helm_release` (`install_observability`). Grafana password is `random_password` + sensitive output. No CloudWatch, no public Ingress. Follow `.claude/rules/observability.md`.
- **Karpenter:** `terraform/modules/karpenter/` — IRSA, SQS, EventBridge, instance profile on the existing node role, gated `helm_release` (`install_karpenter`, charts **1.14.0**). Namespace `karpenter`. On-demand only. NodePool YAML in `k8s/karpenter/`. Do not shrink the managed node group. Follow `.claude/rules/karpenter.md`.
- **EBS CSI:** add-ons + IRSA + gp3 StorageClass in `terraform/modules/eks/`, gated by `install_ebs_csi`. Addon versions from `data.aws_eks_addon_version` (`most_recent`), never the string `latest`. Include `metrics-server`. VPC CNI: `enableNetworkPolicy = "true"` (E-13). Do not rewrite the vendored LB controller IAM JSON.

## Kubernetes Conventions

- **Namespaces:** `petclinic-dev`, `petclinic-prod` (app namespaces; ArgoCD AppProjects). `monitoring`, `tracing`, and `karpenter` are Terraform Helm only — do **not** add them to AppProjects.
- **Labels:** Every resource: `app.kubernetes.io/name`, `app.kubernetes.io/part-of=petclinic`, `app.kubernetes.io/managed-by=Helm`
- **Probes:** Every Deployment MUST have readinessProbe and livenessProbe using `/actuator/health/{readiness,liveness}`
- **Resources:** Every container MUST have requests and limits (memory: 128Mi request / 512Mi limit)
- **Image tags:** Use commit SHA tags, never `latest` in production
- **Secrets:** Use ExternalSecret CRs pointing to AWS Secrets Manager — never store secrets in YAML
- **Service startup order:** Config Server → Discovery Server → all others (use init containers)
- **Packaging:** Helm chart (`helm/petclinic-service/`), per-service + per-env values in `helm-values/`
- **Deployment:** ArgoCD GitOps — CI commits image tags to Git, ArgoCD syncs to cluster

## Helm Conventions

- **Single generic chart** in `helm/petclinic-service/` shared by all 8 services
- **Per-service config** in `helm-values/{service}.yaml` (ports, env vars, init containers, HPA/PDB flags)
- **Per-env config** in `helm-values/{dev,prod}.yaml` (replicaCount, image.registry). Prod uses `replicaOverrides` so GenAI and Admin stay at 1. Dev forces HPA/PDB off.
- **ArgoCD merges values:** service file then env file (env last)
- **Template outputs** validated with `helm template` before commit. No live `helm upgrade --install`.
- **Zipkin:** in-repo `helm/zipkin/`. Tracing env (`MANAGEMENT_TRACING_EXPORT_ZIPKIN_ENDPOINT`, `MANAGEMENT_TRACING_SAMPLING_PROBABILITY`) on api-gateway, customers, visits, vets, genai only — not config, discovery, or admin. Do not edit the app repo.
- **Ingress:** optional template, enabled only for api-gateway. Host/cert/ALB SG placeholders in `helm-values/{env}.yaml`. IngressClass `alb`. Attach the existing VPC ALB SG.
- **Images:** `{{ .Values.image.registry }}/{{ .Values.image.name }}:{{ .Values.image.tag }}`. Tag `TAG` until CI, never `latest`.

## ArgoCD Conventions

- **CI pushes images**, ArgoCD deploys. GitHub Actions NEVER runs `kubectl apply`.
- **One ArgoCD per cluster.** Apply `applications/dev/` only on dev, `applications/prod/` only on prod. Destination is always in-cluster.
- **Dev:** ApplicationSet with automated prune + self-heal
- **Prod:** ApplicationSet with no `automated` block (manual sync)
- **Helm values:** multi-source `$values/helm-values/...` — never `../../helm-values/`
- **AppProjects** lock destination namespaces to `petclinic-{env}` only. Do not add `monitoring` / `tracing`. No ArgoCD IRSA, no passwords in Git.
- Follow `.claude/rules/argocd.md`. After edits, run `k8s-validator` (it skips ApplicationSet kinds).

## Security Rules (NON-NEGOTIABLE)

1. **No secrets in code** — use AWS Secrets Manager + External Secrets Operator
2. **No public S3 buckets** — block public access on all buckets
3. **No open security groups** — no 0.0.0.0/0 ingress except ALB on 80/443
4. **Encryption everywhere** — RDS encryption at rest, S3 SSE, EBS encryption
5. **Least privilege IAM** — specific actions on specific resources. Exceptions: AWS managed EKS policies, vendored LB controller JSON, `ecr:GetAuthorizationToken` on `*`. See the spec IAM exception table.
6. **Private subnets + NAT** — ALB/NAT in public subnets; EKS and RDS in private subnets (no public IPs). **1 NAT in dev, 2 in prod.** SGs still least-privilege. See ADR-0001.
7. **No terraform destroy without approval** — hooks block this command
8. **No *.tfvars or .env files committed** — .gitignore enforces this
9. **NetworkPolicy** — default deny ingress in `petclinic-{env}` only. Gateway allow is VPC CIDR (ALB target-type ip). Prometheus scrape from `monitoring`. Follow `.claude/rules/security.md`.

## AWS Environment Details

| Setting | Dev | Prod |
|---------|-----|------|
| Region | us-east-1 | us-east-1 |
| K8s namespace | petclinic-dev | petclinic-prod |
| State key | petclinic/dev/terraform.tfstate | petclinic/prod/terraform.tfstate |
| RDS instance | db.t4g.micro, single-AZ (free tier) | db.t4g.micro, single-AZ (free tier) |
| EKS nodes | 2x t4g.small ARM (Graviton free trial) | 2x t4g.small ARM (Graviton free trial) |
| NAT Gateways | 1 (cost) | 2 (HA, one per AZ) |
| Deploy mode | ArgoCD auto-sync | ArgoCD manual sync |
| Replicas | 1 per service | 2 for request-path services (GenAI and Admin stay 1), HPA |

## Application Services (8 total)

| Service | Port | Needs MySQL | Notes |
|---------|------|-------------|-------|
| config-server | 8888 | No | Must start first, Git-backed config |
| discovery-server | 8761 | No | Eureka, must start second |
| api-gateway | 8080 | No | Frontend + routing, public-facing |
| customers-service | 8081 | Yes | Owners & pets |
| visits-service | 8082 | Yes | Visit records |
| vets-service | 8083 | Yes | Vet data, Caffeine cache |
| genai-service | 8084 | Optional | Needs OPENAI_API_KEY |
| admin-server | 9090 | No | Spring Boot Admin dashboard |

## Docker Image Details

- Base: `eclipse-temurin:17`, memory limit 512M
- **Target platform:** `linux/arm64` (required for Graviton t4g nodes)
- Profile: `SPRING_PROFILES_ACTIVE=docker` (set in container)
- MySQL profile: add `mysql` to active profiles for RDS-backed services
- ECR repos: `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service-name}`
- CI/CD builds require `docker buildx` + QEMU for ARM cross-compilation on x86 runners

## Workflow Commands

```bash
# Terraform workflow (always plan before apply)
terraform fmt -recursive
terraform validate
terraform plan -out plan.out
terraform apply plan.out        # Never apply without a saved plan

# Helm template validation
helm template my-release helm/petclinic-service/ -f helm-values/{service}.yaml -f helm-values/{env}.yaml

# ArgoCD (after install)
kubectl port-forward svc/argocd-server -n argocd 8443:443
argocd app sync {service}-{env}

# Security scanning
checkov -d terraform/modules/{module}
```

## MCP Servers (configured in .mcp.json)

Five MCP servers configured at the project level:

| Server | Purpose |
|--------|---------|
| `terraform-mcp-server` | HashiCorp official (Docker): Terraform Registry provider/module docs, policy search |
| `aws-knowledge-mcp` | AWS documentation search, regional availability, documentation reader |
| `awslabs.aws-pricing-mcp-server` | Cost estimation for AWS services (RDS, EKS, EC2, ALB) |
| `context7` | Up-to-date library documentation (Terraform, Kubernetes, Helm) |
| `atlassian` | Jira ticket lookup, creation, updates — drives the task-based workflow |

## CI/CD Pipeline Conventions

- **Architecture:** CI (GitHub Actions) + CD (ArgoCD). GitHub Actions NEVER deploys directly.
- **Two repos:** `build-push.yml` in the **app fork**; `update-image-tags.yml` in **this** repo. Trigger between them is `repository_dispatch` (`app-image-built`), never `workflow_run`.
- **App-repo exception:** Claude may add only `.github/workflows/build-push.yml` in the fork. No other app files.
- **OIDC:** `terraform/modules/github-oidc/`, called from **dev only**. Role `petclinic-github-actions-role`. Not the EKS IRSA provider.
- **Image tags:** Commit SHA (`${GITHUB_SHA::7}`), never `latest`. Same SHA pushed to `petclinic-dev/*` and `petclinic-prod/*`.
- **Helm update:** `yq` on `helm-values/{service}.yaml` `image.tag` for services in the dispatch payload only.
- **Prod gates:** ArgoCD manual sync (not GitHub Environments).
- **Scanning:** Trivy after Docker build, fail on CRITICAL, warn on HIGH.
- **Operator:** GitHub Secrets and `terraform apply` for the OIDC role. Claude writes YAML/Terraform only.
- **Follow** `.claude/rules/pipelines.md`. Launch `pipeline-reviewer` after edits.

## Safety Hooks (configured in .claude/settings.json)

| Hook | Type | What it catches |
|------|------|----------------|
| `block-destroy.sh` | Block | `terraform destroy`, `terraform apply -destroy`, `kubectl delete` ns/deploy/svc/ingress/secret in prod |
| `block-dangerous-rm.sh` | Block | `rm -rf` on terraform/, k8s/, helm/, helm-values/, .github/, .claude/ |
| `warn-apply-without-plan.sh` | Warn | `terraform apply` without saved plan.out file |
| `suggest-validate.sh` | Info | Suggests validate/dry-run after editing .tf, K8s .yaml, Helm, or pipeline files |
| `block-secret-commit.sh` | Block | `git add .`, committing .env, .tfvars, .pem, .key files |
| `block-mcp-destroy.sh` | Block | `destroy` via MCP Terraform/Terragrunt tools |

## Technical Specification

All infrastructure values (CIDRs, ports, instance sizes, security groups, K8s resources, probe timings, alert thresholds) are in [`docs/technical-spec.md`](docs/technical-spec.md). Every Jira story references the relevant spec section. **Read the spec before implementing any story.**

## Jira Backlog

Work is tracked in `docs/jira-backlog.md` (17 epics including Helm + ArgoCD, E-12 removed).
Dependency chain: E-0 → E-1 → VPC → EKS → K8s → Helm → ArgoCD; VPC → RDS → Secrets → K8s; E-6 DNS after EKS + Helm (ExternalDNS for the ALB hostname); E-11 Observability after EKS (EBS CSI) via Terraform Helm, not ArgoCD; E-13 Security after E-3 + E-11 (VPC CNI NetworkPolicy, not ArgoCD); E-14 Karpenter after E-3 via Terraform Helm (on-demand, not ArgoCD); E-15 Docs is markdown only (no apply/destroy). Follow `.claude/rules/docs.md`.
