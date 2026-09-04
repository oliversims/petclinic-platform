# Onboarding

**Last Updated:** 2026-09-02

Get from "I have Git and AWS access" to "I have shipped a change" in about 90 minutes.
Assumes working knowledge of AWS and Kubernetes.

## Contents

- [Time budget](#time-budget)
- [1. Install tools (15 min)](#1-install-tools-15-min)
- [2. Get access (10 min)](#2-get-access-10-min)
- [3. Clone and orient (15 min)](#3-clone-and-orient-15-min)
- [4. Connect to a cluster (10 min)](#4-connect-to-a-cluster-10-min)
- [5. See the platform running (20 min)](#5-see-the-platform-running-20-min)
- [6. Make your first change (20 min)](#6-make-your-first-change-20-min)
- [Where to go next](#where-to-go-next)
- [Who to ask](#who-to-ask)

## Time budget

| Section | Time |
|---------|------|
| Install tools | 15 min |
| Get access | 10 min |
| Clone and orient | 15 min |
| Connect to a cluster | 10 min |
| See the platform running | 20 min |
| First change | 20 min |
| **Total** | **90 min** |

---

## 1. Install tools (15 min)

| Tool | Minimum | Check |
|------|---------|-------|
| git | any recent | `git --version` |
| AWS CLI | v2 | `aws --version` |
| kubectl | within one minor of the cluster | `kubectl version --client` |
| terraform | >= 1.6.0 | `terraform version` |
| helm | v3 | `helm version --short` |
| gh (GitHub CLI) | any recent | `gh --version` |

```bash
# macOS
brew install git awscli kubernetes-cli terraform helm gh

# Windows
choco install git awscli kubernetes-cli terraform kubernetes-helm gh
```

Optional but useful: `argocd` CLI for prod syncs, and `jq`.

---

## 2. Get access (10 min)

Ask your team lead for:

- **GitHub**: write access to this repo and to the application fork.
- **AWS**: an IAM principal in the platform account with permission to read Terraform
  state and to run `eks:DescribeCluster`. Configure a named profile:

  ```bash
  aws configure --profile petclinic
  export AWS_PROFILE=petclinic
  aws sts get-caller-identity
  ```

- **EKS access**: your IAM principal needs an EKS access entry. Cluster admin is granted
  through an access entry with `AmazonEKSClusterAdminPolicy`, created in Terraform for
  the deploying principal. A team lead adds yours.
- **Your public IP allowed**: the EKS API endpoint is restricted to specific CIDRs. Your
  `/32` must be in `public_access_cidrs` for the environment, or `kubectl` will time out.

  ```bash
  curl -s https://checkip.amazonaws.com
  ```

No shared credentials, no long-lived access keys. CI uses OIDC federation
([ADR-0005](./adr/0005-github-actions-oidc.md)).

---

## 3. Clone and orient (15 min)

```bash
git clone https://github.com/{org}/petclinic-platform.git
cd petclinic-platform
```

What lives where:

```
terraform/
  modules/{vpc,eks,ecr,rds,secrets,dns,observability,github-oidc}/   reusable modules
  environments/{dev,prod}/                                          one state each
helm/petclinic-service/     one generic chart, all 8 services
helm/zipkin/                tracing backend
helm-values/                per-service and per-environment values (CI edits image.tag)
k8s/base/                   namespaces, ExternalSecret CRs (live)
k8s/security/{dev,prod}/    NetworkPolicies, quotas
k8s/observability/          dashboards, alert rules
k8s/argocd/                 ArgoCD install, projects, ApplicationSets
k8s-reference/              pre-Helm service YAML + overlays (reference only)
scripts/                    bootstrap, start/stop, validate-helm
docs/                       you are here
```

Read in this order, about 10 minutes:

1. [architecture.md](./architecture.md) — the diagrams, at least
2. [`technical-spec.md`](./technical-spec.md) — skim the tables; it is the source of truth
3. `CLAUDE.md` — the conventions every change is held to

The application source is a **separate** repository and is read-only from here.

---

## 4. Connect to a cluster (10 min)

```bash
aws eks update-kubeconfig --name petclinic-dev --region us-east-1
kubectl config current-context
kubectl get nodes
kubectl get pods -n petclinic-dev
```

Expect two nodes and eight Deployments. If `kubectl` hangs, your IP is not allowed —
back to step 2.

Switching environments is the same command with `petclinic-prod`. Check
`kubectl config current-context` before anything destructive; the two contexts look
alike.

---

## 5. See the platform running (20 min)

**The application** is public over HTTPS:

- Dev: `https://petclinic-dev.{domain}`
- Prod: `https://petclinic.{domain}`

`{domain}` is the operator's domain — ask your team lead. The record is written by
ExternalDNS after the Ingress syncs ([ADR-0012](./adr/0012-externaldns.md)). If it does
not resolve, the environment may not be fully deployed yet; that is expected in a
freshly rebuilt environment.

**Grafana**, **Zipkin**, and **Argo CD** are HTTPS on dedicated ALBs (operator CIDR only):

- Dev: `https://grafana-dev.{domain}` / `https://zipkin-dev.{domain}` / `https://argocd-dev.{domain}`
- Prod: `https://grafana.{domain}` / `https://zipkin.{domain}` / `https://argocd.{domain}`

```bash
cd terraform/environments/dev && terraform output -raw grafana_admin_password
# Grafana user: admin. Zipkin UI has no login.
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d; echo
# Argo CD user: admin
```

**Everything else is port-forward only.** Prometheus and Alertmanager have no Ingress.

```bash
# Grafana / Zipkin / Argo CD fallback if the hostname is unreachable
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
kubectl port-forward svc/zipkin -n tracing 9411:9411
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

Worth doing now: open the **Petclinic / Service Overview** dashboard in Grafana, and in
**Explore** run `{namespace="petclinic-dev"}` against the Loki datasource. That is where
you will spend most incident time. See [monitoring-guide.md](./monitoring-guide.md).

---

## 6. Make your first change (20 min)

Everything is deployed from Git. You will not run `helm upgrade` or `kubectl apply` on an
application Deployment — ArgoCD owns those, and manual changes get reverted.

A safe first change is a documentation edit or a dev replica count.

```bash
git checkout -b onboarding/{your-initials}
```

Edit something small — for example, in `helm-values/dev.yaml`:

```yaml
replicaCount: 1     # unchanged; try a comment edit first if you prefer
```

Validate before pushing. This renders all 16 releases and dry-runs them:

```bash
./scripts/validate-helm.sh
```

For Terraform changes:

```bash
terraform fmt -recursive terraform
cd terraform/environments/dev && terraform validate
```

Then:

```bash
git add -p
git commit -m "docs: {what you changed}"
git push origin onboarding/{your-initials}
gh pr create --fill
```

After merge to `main`:

- **Dev** auto-syncs within a few minutes. Watch it in the ArgoCD UI, or:

  ```bash
  kubectl get applications -n argocd
  ```

- **Prod** waits for a manual sync — that is the approval gate. Deliberate, not
  forgotten.

To see the full loop, an app-repo commit triggers `build-push.yml`, which pushes an
image and dispatches to this repo's `update-image-tags.yml`, which commits the new
`image.tag`. ArgoCD takes it from there.

---

## Where to go next

| If you need to | Read |
|----------------|------|
| Deploy, roll back, scale, restart | [runbook.md](./runbook.md) |
| Handle an outage | [incident-playbook.md](./incident-playbook.md) |
| Find the right dashboard or alert | [monitoring-guide.md](./monitoring-guide.md) |
| Rotate a credential | [secret-rotation.md](./secret-rotation.md) |
| Rebuild from nothing | [dr-plan.md](./dr-plan.md) |
| Answer a security question | [compliance-checklist.md](./compliance-checklist.md) |
| Understand why something is the way it is | [adr/](./adr/) |

## Who to ask

Roles, not names — check the team's rota for who currently holds each.

| Question | Role |
|----------|------|
| Access, environments, priorities | Team lead |
| Something is broken right now | On-call engineer |
| Terraform, IAM, networking | Senior platform engineer |
| Architectural change or new AWS service | Platform architect |

Two habits worth forming immediately: check `kubectl config current-context` before you
act, and never commit a secret — `*.tfvars` is gitignored for that reason, and real
values belong in AWS Secrets Manager.
