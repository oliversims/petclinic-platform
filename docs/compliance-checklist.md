# Compliance Checklist

**Last Updated:** 2026-09-02

Security controls that exist in this repository, and the notable ones that do not. Written
for handover and for answering security questions honestly — every "yes" below points at
the file that implements it.

## Contents

- [How to read this](#how-to-read-this)
- [Encryption at rest](#encryption-at-rest)
- [Encryption in transit](#encryption-in-transit)
- [Identity and access](#identity-and-access)
- [Kubernetes controls](#kubernetes-controls)
- [Network controls](#network-controls)
- [Audit logging](#audit-logging)
- [Vulnerability scanning](#vulnerability-scanning)
- [Data classification](#data-classification)
- [Data residency](#data-residency)
- [Known gaps](#known-gaps)
- [Remediation SLAs](#remediation-slas)

## How to read this

| Mark | Meaning |
|------|---------|
| Yes | Implemented in Git and verifiable in the linked file |
| Partial | Implemented with a documented limitation |
| No | Deliberately not implemented — reason given |

This is a learning platform. Several controls are deliberately simplified for cost, and
those choices are recorded in ADRs rather than hidden.

## Encryption at rest

| Asset | Encrypted | Key | Where |
|-------|-----------|-----|-------|
| RDS MySQL | Yes | AWS-managed KMS (`aws/rds`) | `terraform/modules/rds/main.tf` — `storage_encrypted = true` |
| EBS volumes (nodes) | Yes | AWS-managed | `terraform/modules/eks/node-group.tf` — launch template `encrypted = true` |
| EBS volumes (PVCs) | Yes | AWS-managed | `terraform/modules/eks/addons.tf` — gp3 StorageClass `encrypted: "true"` |
| S3 Terraform state | Yes | SSE-S3 (AES256) | `scripts/bootstrap-state.sh` |
| Secrets Manager | Yes | AWS-managed (`aws/secretsmanager`) | Default; no customer-managed key |
| ECR images | Yes | AES256 | `terraform/modules/ecr/main.tf` |

No customer-managed KMS keys anywhere. AWS-managed keys meet the "encrypted at rest"
requirement but do not give per-key access control or independent rotation. Adding CMKs
is a per-service change and a cost increase.

## Encryption in transit

| Path | Encrypted | Notes |
|------|-----------|-------|
| Internet → ALB | Yes | TLS 1.2/1.3 via ACM wildcard cert; policy `ELBSecurityPolicy-TLS13-1-2-2021-06` |
| HTTP → HTTPS | Yes | ALB `ssl-redirect: "443"` |
| ALB → pods | **No** | Plain HTTP to pod IPs inside the VPC |
| Service → service | **No** | Plain HTTP within the cluster |
| Pods → RDS | Partial | MySQL supports TLS; not enforced (`require_secure_transport` is not set) |
| Pods → AWS APIs | Yes | AWS SDK uses HTTPS |
| Terraform → S3 state | Yes | Bucket policy denies `aws:SecureTransport = false` |
| CI → ECR | Yes | HTTPS |

**In-cluster traffic is unencrypted**, which is stated plainly rather than glossed. There
is no service mesh and no mTLS. Traffic stays inside private subnets, and NetworkPolicies
restrict who may talk to whom, but a workload with pod access could read traffic on the
node. A mesh (Istio, Linkerd) or `require_secure_transport` on RDS would close this;
neither is in scope.

## Identity and access

**No long-lived AWS credentials exist in this platform.** Everything is role assumption —
IRSA for pods, OIDC federation for CI ([ADR-0005](./adr/0005-github-actions-oidc.md)).

| Role | Trusted principal | Permissions | Scope |
|------|------------------|-------------|-------|
| `petclinic-{env}-eso-role` | SA `external-secrets:external-secrets-sa` | `secretsmanager:GetSecretValue`, `DescribeSecret` | `petclinic/*` secrets in this account |
| `petclinic-{env}-lb-controller-role` | SA `kube-system:aws-load-balancer-controller` | Official upstream policy, tag v3.5.0 | Vendored unmodified |
| `petclinic-{env}-external-dns-role` | SA `kube-system:external-dns` | `ChangeResourceRecordSets` on one zone; three `List*` on `*` | This hosted zone only |
| `petclinic-{env}-ebs-csi-role` | SA `kube-system:ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` (AWS managed) | Required by EKS |
| `petclinic-github-actions-role` | GitHub OIDC, `repo:{org}/{repo}:ref:refs/heads/main` | ECR auth + push | `petclinic-dev/*`, `petclinic-prod/*` only |
| EKS cluster role | `eks.amazonaws.com` | `AmazonEKSClusterPolicy` | Required by EKS |
| EKS node role | `ec2.amazonaws.com` | Worker node, CNI, ECR read-only | Required by EKS |

Documented wildcards, each unavoidable rather than lazy:

- `ecr:GetAuthorizationToken` on `*` — the AWS API defines no resource ARN for it.
- Route 53 `ListHostedZones`, `ListResourceRecordSets`, `ListTagsForResource` on `*` —
  no resource-level permissions exist for these calls.
- AWS managed policies for EKS and EBS CSI — cannot be narrowed without breaking EKS.
- The vendored Load Balancer Controller policy — official upstream JSON, not to be
  hand-edited.

Human cluster access is through EKS access entries with
`AmazonEKSClusterAdminPolicy`; the `aws-auth` ConfigMap is not managed. There is no
bastion host and no SSH access to nodes.

## Kubernetes controls

| Control | Status | Where |
|---------|--------|-------|
| Pod Security Admission | Yes | `k8s/base/namespaces.yaml` — enforce `baseline`, warn/audit `restricted` on both app namespaces |
| Non-root containers | Yes | `helm/petclinic-service/values.yaml` — `runAsNonRoot: true`, `runAsUser: 1000`, `fsGroup: 1000` |
| Dropped capabilities | Yes | `capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false` |
| Read-only root filesystem | **No** | `readOnlyRootFilesystem: false` — Spring Boot writes to `/tmp` |
| Resource requests and limits | Yes | Every container; enforced by LimitRange defaults |
| ResourceQuota | Yes | `k8s/security/{env}/resource-quota.yaml` — dev 4 CPU/4Gi/40 pods, prod 6/6Gi/50 |
| Health probes | Yes | startup, readiness, liveness on all 8 services |
| Image tags | Yes | Commit SHA, never `latest`; prod ECR is IMMUTABLE |
| Service account per workload | Yes | One per service, no IRSA annotation (none need AWS) |

The `monitoring` namespace is deliberately **not** PSA-restricted: node-exporter and
Fluent Bit need hostPath mounts.

## Network controls

| Control | Status | Where |
|---------|--------|-------|
| Private subnets for compute and data | Yes | EKS nodes and RDS have no public IP ([ADR-0001](./adr/0001-network-layout.md)) |
| Security groups least-privilege | Yes | `terraform/modules/vpc/security-groups.tf` |
| Only ALB is internet-facing | Yes | The single `0.0.0.0/0` ingress, ports 80 and 443 |
| RDS reachable from nodes only | Yes | 3306 from the node SG; no other ingress |
| EKS API endpoint restricted | Partial | Public endpoint enabled but limited to the operator CIDR via `public_access_cidrs` |
| NetworkPolicy default-deny | Yes | `k8s/security/{env}/network-policies.yaml` — ingress only |
| VPC CNI policy enforcement | Yes | `enableNetworkPolicy = "true"` on the `vpc-cni` add-on |
| Egress restrictions | **No** | Deliberate — pods need DNS, NAT, RDS, Secrets Manager, ECR, OpenAI |
| No public S3 buckets | Yes | State bucket blocks all four public-access settings |

## Audit logging

**AWS CloudTrail is not deployed in this stack.** No trail, no S3 log bucket, no
CloudTrail alarms. API-level audit of who changed what in AWS is therefore **not
available** beyond what AWS retains in the 90-day Event History console view. This is the
most significant gap on the page. Enabling an organisation trail is the single
highest-value security addition.

What does exist:

| Log source | Status | Retention |
|-----------|--------|-----------|
| EKS control plane | Yes — `api`, `audit`, `authenticator` | CloudWatch Logs, default retention |
| Application logs | Yes — Fluent Bit → Loki | 7 days dev, 30 days prod |
| ArgoCD sync history | Yes | In-cluster, ArgoCD UI |
| Git history | Yes | Full history of every infrastructure and config change |
| VPC Flow Logs | **No** | Not enabled |
| RDS audit log | **No** | Not exported to CloudWatch |

The three enabled EKS log types are set in `terraform/modules/eks/main.tf`
(`enabled_cluster_log_types`); `controllerManager` and `scheduler` are not enabled.

## Vulnerability scanning

| Scan | Tool | Where | Blocking |
|------|------|-------|----------|
| Terraform static analysis | Checkov | `.github/workflows/checkov.yml`, config in `.checkov.yml` | Yes — fails on findings not skipped |
| Container images (build time) | Trivy | App repo `build-push.yml` | CRITICAL fails, HIGH warns |
| Container images (at rest) | ECR scan-on-push | `terraform/modules/ecr/main.tf` | No — findings are advisory |
| Dependency scanning | **None** | — | No Dependabot or SCA configured |

Checkov skips are documented in `.checkov.yml`, each pointing at the decision in
`technical-spec.md`. They cover the ALB's public ingress, the EKS public endpoint, the
IAM exceptions above, and the deliberate RDS cost trade-offs.

## Data classification

| Data | Classification | Stored in | Protection |
|------|---------------|-----------|-----------|
| Owner name, address, city, telephone | Sample PII | RDS `petclinic` database | Encrypted at rest, private subnet, SG-restricted |
| Pet and visit records | Sample application data | Same | Same |
| Vet and specialty records | Reference data | Same | Same |
| RDS master credentials | Secret | Secrets Manager `petclinic/{env}/rds-credentials` | KMS, IRSA-scoped read |
| OpenAI API key | Secret | Secrets Manager `petclinic/{env}/openai-api-key` | KMS, IRSA-scoped read |
| Grafana admin password | Secret | Terraform state (sensitive output) | State bucket: versioned, encrypted, TLS-enforced |

The owner data is **sample data from the upstream Spring Petclinic project**, not real
personal data. If this platform were ever pointed at real records, the gaps in this
document — CloudTrail, in-cluster encryption, and the RDS destroy behaviour — would need
closing first.

Note that the RDS password and the OpenAI key exist in Terraform state in cleartext,
which is inherent to `random_password` and `sensitive` variables. State bucket access is
therefore equivalent to credential access.

## Data residency

All resources are in **us-east-1**. There is no EU region, no data-residency control, and
no GDPR-specific handling. Cross-border transfer is not restricted or monitored.

The one third-party egress path is genai-service calling the OpenAI API. Prompt content
leaves AWS. For real user data that would need a review; for the sample data it does not.

## Known gaps

Collected from above, in the order worth addressing:

1. **No CloudTrail** — no AWS API audit trail beyond 90-day Event History.
2. **No in-cluster encryption** — service-to-service and pod-to-RDS traffic is plaintext.
3. **No VPC Flow Logs** — no network-level forensics.
4. **No dependency scanning** — no Dependabot or SCA on the app or platform.
5. **AWS-managed keys only** — no CMKs, so no independent key rotation or per-key policy.
6. **`skip_final_snapshot = true`** — a destroy discards RDS data irrecoverably.
7. **Alertmanager is a blackhole** — alerts fire but notify no one, by design.

None of these is an oversight; each is a documented trade-off. They are listed so the
next owner inherits the list rather than discovering it.

## Remediation SLAs

Applies to findings from Checkov, Trivy, ECR scanning, or manual review.

| Severity | Fix within | Examples |
|----------|-----------|----------|
| **Critical** | 24 hours | Exposed credential; RCE in a running image; public exposure of a private resource |
| **High** | 72 hours | Privilege escalation path; unencrypted sensitive data; missing authn on an exposed service |
| **Medium** | 1 week | Overly broad IAM within the account; missing security header; outdated base image with no known exploit |
| **Low** | Next sprint | Informational findings; hardening improvements; documentation drift |

The clock starts when the finding is triaged, not when it is generated. A finding that is
accepted rather than fixed needs a written reason and a review date — add it to the known
gaps above rather than silencing it quietly.

## Related documents

- [Architecture](./architecture.md)
- [Secret rotation](./secret-rotation.md)
- [DR plan](./dr-plan.md)
- [`technical-spec.md` § Security Controls](./technical-spec.md#security-controls)
