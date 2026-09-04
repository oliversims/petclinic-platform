---
paths:
  - "helm/**"
  - "helm-values/**/*.yaml"
  - "helm-values/**/*.yml"
---

# Helm Rules

## Chart Structure

Single generic chart shared by all 8 services:

```
helm/petclinic-service/
├── Chart.yaml              # Chart metadata (name, version, appVersion)
├── values.yaml             # Default values (overridden by per-service/env files)
└── templates/
    ├── _helpers.tpl         # Template helpers (labels, names, selectors)
    ├── deployment.yaml      # Deployment with probes, resources, init containers
    ├── service.yaml         # ClusterIP service
    ├── configmap.yaml       # ConfigMap
    ├── serviceaccount.yaml  # ServiceAccount
    ├── hpa.yaml             # HPA (conditionally enabled)
    ├── pdb.yaml             # PDB (conditionally enabled)
    └── ingress.yaml         # ALB Ingress (conditionally enabled; api-gateway only)
```

No `NOTES.txt`: ArgoCD applies the chart, so post-install notes have no reader.

Zipkin is a **second** in-repo chart (`helm/zipkin/`), not a ninth petclinic-service release. Terraform installs it (`helm_release`, ns `tracing`). Do not add Zipkin to ArgoCD ApplicationSets.

## Zipkin / tracing env (E-11)

On **api-gateway, customers-service, visits-service, vets-service, genai-service** only, add to `configData`:

```yaml
MANAGEMENT_TRACING_EXPORT_ZIPKIN_ENDPOINT: "http://zipkin.tracing.svc:9411/api/v2/spans"
MANAGEMENT_TRACING_SAMPLING_PROBABILITY: "1.0"
```

Do **not** set those keys on config-server, discovery-server, or admin-server. Do not edit the app repo.

## Values Hierarchy

ArgoCD merges values files in this order (last wins):

1. `helm/petclinic-service/values.yaml` — chart defaults
2. `helm-values/{service}.yaml` — per-service config (ports, env vars, init containers, HPA/PDB flags)
3. `helm-values/{env}.yaml` — per-environment overrides (replicaCount, image.registry, ingress host/cert/SG)

ApplicationSets load (2) and (3) via multi-source `$values/helm-values/...` (see `.claude/rules/argocd.md`). Never `../../helm-values/`.

Because env is last: `dev.yaml` must set `autoscaling.enabled: false` and `podDisruptionBudget.enabled: false`. `prod.yaml` must **not** set those keys to true globally (that would HPA/PDB every service).

## Per-Service Values (`helm-values/{service}.yaml`)

Each service file MUST specify:
- `name` — service name (for `replicaOverrides` lookup)
- `service.port` — 8888, 8761, 8080, 8081, 8082, 8083, 8084, or 9090
- `image.name` — ECR image name only (e.g., `config-server`); registry is set per-environment
- `springProfiles` — e.g. `docker`, `docker,mysql`, `docker,mysql,production`
- `env` — extra static environment variables beyond `SPRING_PROFILES_ACTIVE`
- `secrets` — secret-backed env vars (list of `{name, secretName, key}`)
- `initContainers` — config-server none; discovery wait-for-config; others wait-for-config and wait-for-discovery
- `autoscaling.enabled` — true only for api-gateway, customers, visits, vets, genai (E-9 min/max)
- `podDisruptionBudget.enabled` — true only for config, discovery, gateway, customers, visits, vets
- `ingress.enabled` — true **only** in `api-gateway.yaml`; omit or false everywhere else

## Per-Environment Values (`helm-values/{env}.yaml`)

- `dev.yaml` — `replicaCount: 1`, HPA/PDB forced off, `image.registry` for petclinic-dev, ingress host/cert/SG placeholders
- `prod.yaml` — `replicaCount: 2`, `replicaOverrides: { genai-service: 1, admin-server: 1 }`, `image.registry` for petclinic-prod; do not globally enable HPA/PDB; ingress host/cert/SG placeholders

**ECR registry** is set in the env file (`image.registry`), not per-service:
- dev: `ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev`
- prod: `ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/petclinic-prod`

`ACCOUNT` comes from Terraform output `ecr_registry` (the host). Never hardcode an AWS account ID. Never use `latest`; tag is `TAG` until CI.

## Template Conventions

- Use Go template syntax: `{{ .Values.x }}`, `{{ include "helper" . }}`, `{{ tpl .Values.x . }}`
- Use `_helpers.tpl` for reusable labels, names, and selectors — do not duplicate label blocks
- Replicas: `replicaOverrides.{name}` if set, else `replicaCount`
- Use `{{- if .Values.autoscaling.enabled }}` and `{{- if .Values.podDisruptionBudget.enabled }}`
- Ingress: `{{- if .Values.ingress.enabled }}`. Default false. Only `helm-values/api-gateway.yaml` sets true.
- `spec.ingressClassName: alb`. Never `kubernetes.io/ingress.class`.
- Attach `ingress.albSecurityGroupId` (VPC ALB SG). Set `manage-backend-security-group-rules: "false"`.
- Host / `CERT_ARN` / `ALB_SG_ID` placeholders in env values — same idea as `ACCOUNT` in the registry.
- Use `{{- with }}` to scope into nested values
- Use `{{- toYaml . | nindent N }}` for rendering YAML blocks with correct indentation
- NEVER hardcode environment-specific values in templates — use values files
- NEVER put secrets in values files — use ExternalSecret CRs in `k8s/base/external-secrets/`
- Probes match E-8 (startupProbe required). Config Server: `/actuator/health` for all three

## Validation

Before committing any Helm changes, validate with:

```bash
# Render templates for a specific service + environment
helm template petclinic helm/petclinic-service/ \
  -f helm-values/{service}.yaml \
  -f helm-values/{env}.yaml

# Lint the chart
helm lint helm/petclinic-service/ \
  -f helm-values/{service}.yaml \
  -f helm-values/{env}.yaml

# Zipkin in-repo chart (not one of the 16 petclinic-service releases)
helm lint helm/zipkin/
helm template zipkin helm/zipkin/
```

Do not `helm upgrade --install` on a live cluster.

## Image Tags

- Use commit SHA tags later (CI); until then `TAG`. Never `latest`
- CI updates `image.tag` in `helm-values/{service}.yaml` — ArgoCD detects and syncs
- Template renders: `image: "{{ .Values.image.registry }}/{{ .Values.image.name }}:{{ .Values.image.tag }}"`
- `image.registry` comes from the env values file; `image.name` from the per-service file

## Validation Script

Run `scripts/validate-helm.sh` to lint, template, and dry-run all 16 releases (8 services × 2 envs).
Supports `--env dev|prod` and `--service <name>` filters.

## Startup Order

Init containers enforce the dependency chain:
- **config-server**: no init containers
- **discovery-server**: wait for config-server:8888
- **all other services**: wait for config-server:8888 AND discovery-server:8761

Per-service values files define the init containers — the template renders them.
