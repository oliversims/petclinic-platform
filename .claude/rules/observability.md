---
paths:
  - "terraform/modules/observability/**"
  - "terraform/modules/eks/**"
  - "k8s/observability/**"
  - "helm/zipkin/**"
---

# Observability rules (E-11)

In-cluster Prometheus, Grafana, Alertmanager, Loki, Fluent Bit, Zipkin. Not CloudWatch.

## Split

| Piece | Where |
|-------|--------|
| EBS CSI, add-ons, gp3 StorageClass | `terraform/modules/eks/` |
| Helm releases | `terraform/modules/observability/` |
| Dashboards / PrometheusRules | `k8s/observability/` |
| Zipkin chart | `helm/zipkin/` |
| Zipkin env on apps | `helm-values/` for the five traced services |

Claude: `terraform validate` and `helm template` / `helm lint` only. Operator applies and port-forwards.

## Install

- `helm_release` gated by `install_observability` (same as `install_eso`)
- Kubernetes provider on env roots (same exec as Helm) for the gp3 StorageClass; add `hashicorp/kubernetes` to `versions.tf` if missing
- Charts: kube-prometheus-stack **88.6.2**, loki **18.7.6** (grafana-community), fluent-bit **0.53.0**, zipkin in-repo
- Namespaces `monitoring` and `tracing`. Do **not** add them to ArgoCD AppProjects
- Grafana Ingress is allowed: dedicated ALB, HTTPS, CIDR-locked to `public_access_cidrs`. Host `grafana-{env}.{domain}` (prod: `grafana.{domain}`)
- Zipkin Ingress is allowed the same way: dedicated ALB, host `zipkin-{env}.{domain}` (prod: `zipkin.{domain}`). Apps still POST to `zipkin.tracing.svc:9411`
- No Ingress for Prometheus or Alertmanager — those stay port-forward
- Learning-size resources (two t4g.small). Do not use chart default memory
- Grafana password: `random_password`, sensitive output, never Git
- Alertmanager: Slack receiver when `slack_webhook_url` is set in gitignored tfvars; otherwise blackhole. Never put the webhook in Git.
- Fluent Bit Host `loki.monitoring.svc` port 3100
- Do not set PSA `restricted` on `monitoring`

## Zipkin

Boot 4 env on api-gateway, customers, visits, vets, genai only:

`MANAGEMENT_TRACING_EXPORT_ZIPKIN_ENDPOINT=http://zipkin.tracing.svc:9411/api/v2/spans`

Do not edit the app repo.

## Forbidden

- CloudWatch log groups, FluentBit IRSA
- SMTP / Slack tokens in Git
- `k8s/base/observability/` Deployments
- `helm install` / `kubectl apply` / port-forward as acceptance
