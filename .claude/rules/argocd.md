---
paths:
  - "k8s/argocd/**/*.yaml"
  - "k8s/argocd/**/*.yml"
---

# ArgoCD Rules

These files are GitOps CRDs and install overlays. They are **not** Spring Deployments. Do not add probes, resource limits, or ECR image fields on ApplicationSet / AppProject / Kustomization.

## Layout

```
k8s/argocd/
  install/                         # Kustomize → official install.yaml v3.5.2
    kustomization.yaml
    namespace.yaml
  ingress/
    dev.yaml                       # dedicated ALB UI — apply after install
    prod.yaml
  projects/
    petclinic-dev.yaml
    petclinic-prod.yaml
  applications/
    dev/applicationset.yaml        # auto-sync
    prod/applicationset.yaml       # manual sync
```

Do **not** create eight Application YAML files per env. Use one ApplicationSet per env.

## Install

- Pin **v3.5.2** non-HA: `https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml`
- Kustomize `namespace: argocd`. Do not vendor/rewrite the upstream install objects.
- No `ha/install.yaml`. No Terraform `helm_release`. No `petclinic-{env}-argocd-role`.
- UI Ingress is `k8s/argocd/ingress/{env}.yaml`, not the install kustomization. Dev joins shared app ALB (`ALB_SG_ID`); prod joins ops ALB (`OPS_ALB_SG_ID`). Placeholders DOMAIN / CERT_ARN / ALB_SG_ID or OPS_ALB_SG_ID.
- Validate with `kubectl kustomize k8s/argocd/install/`. Do **not** `kubectl apply` on a cluster.

## Per cluster

Dev and prod are **separate EKS clusters**. Destination is always `https://kubernetes.default.svc`.
- Dev cluster gets: install + `k8s/argocd/ingress/dev.yaml` + `petclinic-dev` project + `applications/dev/`
- Prod cluster gets: install + `k8s/argocd/ingress/prod.yaml` + `petclinic-prod` project + `applications/prod/`
- Never apply the prod ApplicationSet on the dev cluster (or the reverse).

## Helm sources

Values live in `helm-values/`, not in the chart. Use **multiple sources**:

1. `path: helm/petclinic-service` with `helm.valueFiles` using `$values/...`
2. Same `repoURL`, `ref: values`, no `path`

Order (last wins): `$values/helm-values/{service}.yaml` then `$values/helm-values/{env}.yaml`.
Never `../../helm-values/`.
`helm.releaseName` is the service name.
`repoURL` is `https://github.com/GITHUB_ORG/petclinic-platform.git` — do not invent an org.

## Sync

- Dev: `automated.prune` and `selfHeal` true
- Prod: **omit** `automated`
- Both: `syncOptions: [CreateNamespace=true]`
- Labels on generated Applications: `environment: {env}`, `app.kubernetes.io/part-of: petclinic`, `app.kubernetes.io/managed-by: argocd`

## Secrets

- No admin password, PAT, or SSH key in Git
- Operator stores repo credentials in the cluster if GitHub is private

## Bootstrap (operator, not these files)

Namespaces + ESO CRs are applied first. NetworkPolicies and quotas in `k8s/security/` are operator `kubectl apply`, not an ApplicationSet. Do not tell anyone to `kubectl apply` `k8s-reference/base/*/deployment.yaml` after ArgoCD owns workloads. The api-gateway Ingress is in the Helm chart, not a second ApplicationSet.

Do **not** add `monitoring`, `tracing`, or `karpenter` to AppProject destinations. Observability and Karpenter are Terraform `helm_release`, not ArgoCD.
