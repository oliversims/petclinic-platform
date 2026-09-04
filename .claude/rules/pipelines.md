---
paths:
  - ".github/workflows/**/*.yml"
  - ".github/workflows/**/*.yaml"
---

# GitHub Actions Workflow Rules

## Two repositories

```
# Application fork (spring-petclinic-microservices) — Claude may add this file only
.github/workflows/build-push.yml

# This platform repo
.github/workflows/update-image-tags.yml
.github/workflows/checkov.yml          # E-13 — Terraform scan only
```

Do **not** put `build-push.yml` in the platform repo. Do **not** create `.github/workflows/reusable/` in E-10 (PETPLAT-53 is parked). Do **not** change Java, pom.xml, or Dockerfiles in the app fork.

## Architecture: CI (GitHub Actions) + CD (ArgoCD)

GitHub Actions handles **CI only**. ArgoCD handles **CD**. CI never runs `kubectl apply` or `helm upgrade`.

## Triggers

- `build-push.yml` (app fork): `on: push: branches: [main]`
- `update-image-tags.yml` (platform): `on: repository_dispatch: types: [app-image-built]`
- **Never** `workflow_run` — that only works inside one repo

## Job Naming

- `build` — Maven + Docker image
- `scan` — Trivy
- `push` — ECR
- `update-tags` — commit `image.tag` in `helm-values/{service}.yaml`

## Required Practices

1. **No secrets in YAML** — GitHub Secrets only
2. **AWS auth via OIDC** on build-push — `aws-actions/configure-aws-credentials` with `role-to-assume: ${{ secrets.AWS_ROLE_ARN }}`. update-image-tags does **not** assume AWS
3. **No kubectl/helm in CI**
4. **Image tags** — `${GITHUB_SHA::7}`, never `latest`
5. **Push both prefixes** — `petclinic-dev/{service}:{sha}` and `petclinic-prod/{service}:{sha}`
6. **Maven module paths** for filters: `spring-petclinic-config-server`, `spring-petclinic-discovery-server`, `spring-petclinic-api-gateway`, `spring-petclinic-customers-service`, `spring-petclinic-visits-service`, `spring-petclinic-vets-service`, `spring-petclinic-genai-service`, `spring-petclinic-admin-server`. Shared `docker/**` and root `pom.xml` → all 8
7. **Retag** `springcommunity/spring-petclinic-{artifact}` to the short Helm name (`customers-service`, …)
8. **Trivy** before push — fail on CRITICAL, warn on HIGH, upload artifact. Do not create `.trivyignore`
9. **Checkov** on this repo: `.github/workflows/checkov.yml` scans `terraform/`. Skip known accepts in `.checkov.yml` (see `.claude/rules/security.md`)
10. **Actions pinned to commit SHA**, not `@v1` / `@latest`
11. **`permissions:` least privilege** — build-push: `id-token: write`, `contents: read`. update-tags: `contents: write`. checkov: `contents: read`

## GitHub Secrets (app fork, operator sets these)

- `AWS_ROLE_ARN`, `AWS_REGION`, `AWS_ACCOUNT_ID`, `PLATFORM_REPO_TOKEN`
- No `ECR_REGISTRY`, no `EKS_CLUSTER_NAME`, no GitHub Environments

## Error Handling

- Fail the workflow on any non-zero exit code
- Fail the workflow on Trivy CRITICAL findings
- On failure: do not retry automatically
