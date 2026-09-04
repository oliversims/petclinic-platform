---
paths:
  - "k8s/base/**/*.yaml"
  - "k8s/base/**/*.yml"
  - "k8s-reference/**/*.yaml"
  - "k8s-reference/**/*.yml"
---

# Kubernetes Rules

## Directory Structure

```
k8s/                          # Live manifests only
├── base/
│   ├── namespaces.yaml
│   └── external-secrets/
├── observability/
├── security/
├── karpenter/
└── argocd/

k8s-reference/                # Pre-Helm plain YAML (do not apply for live path)
├── base/{8 services}/
└── overlays/{dev,prod}/
```

Ingress for the API Gateway is Helm (`helm/petclinic-service/templates/ingress.yaml`), not `k8s/base/ingress/`. ArgoCD GitOps YAML lives in `k8s/argocd/` and follows `.claude/rules/argocd.md`. DNS/ACM/controllers follow `.claude/rules/dns.md`. Dashboards and PrometheusRules live in `k8s/observability/` and follow `.claude/rules/observability.md`. NetworkPolicies and quotas live in `k8s/security/` and follow `.claude/rules/security.md` — do not treat them as app Deployments (no actuator probes, no ECR SHA tags).

## Required Labels

Every Kubernetes resource MUST include these labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: {service-name}
    app.kubernetes.io/part-of: petclinic
    app.kubernetes.io/managed-by: kubectl
    app.kubernetes.io/component: {backend|frontend|infrastructure}
```

## Deployment Requirements

Every Deployment MUST include:

1. **Health probes** using Spring Boot Actuator:
   ```yaml
   readinessProbe:
     httpGet:
       path: /actuator/health/readiness
       port: http
     initialDelaySeconds: 30
     periodSeconds: 10
   livenessProbe:
     httpGet:
       path: /actuator/health/liveness
       port: http
     initialDelaySeconds: 60
     periodSeconds: 15
   ```

2. **Resource requests and limits**:
   ```yaml
   resources:
     requests:
       memory: "128Mi"
       cpu: "250m"
     limits:
       memory: "512Mi"
       cpu: "500m"
   ```

3. **Image with SHA tag** (never `latest`):
   ```yaml
   image: {account}.dkr.ecr.us-east-1.amazonaws.com/petclinic/{service}:{sha}
   ```

## Service Startup Order

Config Server MUST start before all other services. Discovery Server MUST start before application services.

Use init containers to wait for dependencies:
- All services (except config-server): wait for config-server:8888
- Application services: wait for discovery-server:8761

## Secrets

- NEVER put secrets directly in YAML manifests
- Use ExternalSecret CRs that reference AWS Secrets Manager
- Mount secrets as environment variables, not files (unless certificates)

## Namespaces

- Dev: `petclinic-dev`
- Prod: `petclinic-prod`
- All resources MUST specify their namespace explicitly

## Overlay Patterns

Dev overlay: single replica, smaller resource requests, relaxed probes
Prod overlay: 2+ replicas, HPA, full resource limits, strict probes
