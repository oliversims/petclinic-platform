# Monitoring Guide

**Last Updated:** 2026-09-02

What exists, where to look, and how to change it. The stack is entirely in-cluster:
Prometheus, Grafana, Alertmanager, Loki, Fluent Bit, and Zipkin. There are no CloudWatch
log groups ([ADR-0013](./adr/0013-loki-over-cloudwatch.md)).

## Contents

- [Access](#access)
- [Dashboards](#dashboards)
- [Alert rules](#alert-rules)
- [Alertmanager and Slack](#alertmanager-and-slack)
- [Logs with Loki](#logs-with-loki)
- [Traces with Zipkin](#traces-with-zipkin)
- [Silence an alert](#silence-an-alert)
- [Add or change a rule](#add-or-change-a-rule)
- [Add a dashboard](#add-a-dashboard)

## Access

Grafana and Zipkin have HTTPS hostnames on dedicated ALBs. Only the operator CIDRs
(`public_access_cidrs`) can reach them — not the public internet like the app.

| Env | Grafana | Zipkin |
|-----|---------|--------|
| Dev | `https://grafana-dev.{domain}` | `https://zipkin-dev.{domain}` |
| Prod | `https://grafana.{domain}` | `https://zipkin.{domain}` |

Login is `admin`. Password:

```bash
cd terraform/environments/{env}
terraform output -raw grafana_admin_password
terraform output grafana_url
terraform output zipkin_url
```

If the page does not load, your current IP is probably not in `public_access_cidrs`.
Port-forward still works as a fallback:

```bash
aws eks update-kubeconfig --name petclinic-{env} --region us-east-1

# Grafana fallback
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

# Prometheus — raw PromQL, target health
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090

# Alertmanager — what is firing, silences
kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093

# Zipkin fallback
kubectl port-forward svc/zipkin -n tracing 9411:9411
```

Never paste that value into a ticket, a commit, or a chat message.

**First check when metrics look wrong** — are the targets actually up? In Prometheus,
**Status → Targets**, or:

```promql
up{job=~"config-server|discovery-server|api-gateway|customers-service|visits-service|vets-service|genai-service|admin-server"}
```

All eight are scraped as static jobs at `{service}.petclinic-{env}.svc:{port}` on
`/actuator/prometheus`. The scrape comes from the `monitoring` namespace, which every
NetworkPolicy in `k8s/security/{env}/` explicitly allows — if targets go `DOWN` right
after a policy change, that is the first suspect.

## Dashboards

Ten dashboards, stored as JSON in `k8s/observability/grafana-dashboards/` and loaded
into Grafana by the sidecar as ConfigMaps labelled `grafana_dashboard=1`. They appear in
the **Petclinic** folder.

| Dashboard | File | Use it for |
|-----------|------|-----------|
| Service Overview | `service-overview.json` | First look. Up/down, total RPS, error rate, per-service breakdown |
| Per-service (x8) | `{service}.json` | One service: request rate by URI, responses by status, p95/p99 latency |
| JVM Metrics | `jvm-metrics.json` | Heap used, heap vs committed, GC pause rate, live threads |

Each dashboard has a `datasource` variable, so the same JSON works against any
Prometheus.

## Alert rules

Five Prometheus rules, defined in
`k8s/observability/prometheus-rules/petclinic-alerts.yaml` and loaded through the chart's
`additionalPrometheusRulesMap`. These are the thresholds as they exist in Git:

| Alert | Condition | For | Severity |
|-------|-----------|-----|----------|
| `ServiceDown` | `up == 0` | 1m | critical |
| `HighErrorRate` | 5xx rate / total rate > 0.05 | 5m | warning |
| `HighLatency` | p95 of `http_server_requests_seconds_bucket` > 0.5s | 5m | warning |
| `PodRestartLoop` | `increase(kube_pod_container_status_restarts_total[15m]) > 3` | 0m | critical |
| `HighMemoryUsage` | working set / limit > 0.8 | 5m | warning |

`PodRestartLoop` needs kube-state-metrics and `HighMemoryUsage` needs container metrics;
both are enabled in the chart values and must stay that way.

Two log-based rules live in `k8s/observability/loki-rules/petclinic-log-alerts.yaml`:

| Alert | Condition | For | Severity |
|-------|-----------|-----|----------|
| `LogErrorSpike` | `rate({namespace=~"petclinic-.*"} \|= "ERROR" [5m]) > 0.5` | 5m | warning |
| `JVMOutOfMemory` | `count_over_time({namespace=~"petclinic-.*"} \|= "OutOfMemoryError" [5m]) > 0` | 0m | critical |

These are **best-effort**. Loki runs in SingleBinary mode with no object store, so the
ruler has nowhere durable to keep its state — the rules evaluate but do not survive a
restart with history. Treat the Prometheus rules as the dependable ones.

## Alertmanager and Slack

If `slack_webhook_url` is set in gitignored `terraform.tfvars`, Alertmanager posts
to `slack_channel` (default `#petclinic-alerts`). If the URL is empty, every alert
still goes to a **blackhole** — nothing is sent.

The webhook never belongs in Git. Put it only in `terraform/environments/{env}/terraform.tfvars`.

To see what is firing (still no Ingress):

```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093
# http://localhost:9093
```

## Logs with Loki

Fluent Bit runs as a DaemonSet, tails container logs on every node, and pushes to
`loki.monitoring.svc:3100`. Labels are kept deliberately small — `namespace`, `pod`,
`container` — because label cardinality is what makes Loki expensive.

Query in Grafana → **Explore** → **Loki** datasource:

```logql
# Everything in an environment
{namespace="petclinic-{env}"}

# One service
{namespace="petclinic-{env}", pod=~"customers-service.*"}

# Errors across all services
{namespace=~"petclinic-.*"} |= "ERROR"

# Stack traces
{namespace="petclinic-{env}"} |= "Exception" |= "at com.petclinic"

# Rate of errors, for a graph
sum(rate({namespace="petclinic-{env}"} |= "ERROR" [5m])) by (pod)

# Out-of-memory events
{namespace=~"petclinic-.*"} |= "OutOfMemoryError"
```

Retention is 7 days in dev and 30 days in prod. Older logs are compacted away and cannot
be recovered — if something matters beyond that window, capture it into the RCA.

For a live tail of one pod, `kubectl logs -f` is faster than Loki.

## Traces with Zipkin

Five services emit spans: **api-gateway, customers-service, visits-service, vets-service,
genai-service**. config-server, discovery-server, and admin-server do not — they are
infrastructure, not request path.

Sampling is 1.0 (every request) because this is a learning platform with low traffic.
Storage is in-memory on an emptyDir, so **traces are lost when the pod restarts**. Zipkin
is for looking at a request that just happened, not for historical analysis.

Open `https://zipkin-{env}.{domain}` (prod: `https://zipkin.{domain}`). Port-forward
is the fallback if your IP is not in `public_access_cidrs`.

Use it to answer "where did the time go" — the trace shows gateway → service → JDBC
spans with durations.

## Silence an alert

Silences are created in the Alertmanager UI over a port-forward, and they live in the
cluster, not in Git.

1. `kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093`
2. Open `http://localhost:9093` → **Silences** → **New Silence**.
3. Match on labels, for example `alertname="HighLatency"` and
   `job="genai-service"`. Set the shortest duration that covers the work.
4. Put the reason and a ticket ID in the comment. A silence with no explanation is
   indistinguishable from a mistake.

Silences expire on their own. Prefer a short silence you renew over an open-ended one.

If an alert is wrong rather than temporarily noisy, change the rule in Git instead of
silencing it repeatedly.

## Add or change a rule

Git is the source of truth. Editing a PrometheusRule with `kubectl` works until the next
`terraform apply` overwrites it.

1. Edit `k8s/observability/prometheus-rules/petclinic-alerts.yaml`. It is a `groups:`
   fragment, not a full PrometheusRule manifest — the observability module wraps it.

   ```yaml
   - alert: MyNewAlert
     expr: |
       some_metric > 10
     for: 5m
     labels:
       severity: warning
     annotations:
       summary: "{{ $labels.job }} exceeded the threshold"
       description: "What this means and what to do about it."
   ```

2. Test the expression first in Prometheus (**Graph** tab) against real data.
3. Commit and push.
4. An operator applies it — the rules reach the cluster through
   `terraform apply` in `terraform/environments/{env}`, because the module reads the file
   at plan time.

**Verify** after apply: the rule appears in Prometheus under **Status → Rules**, and in
Alertmanager if it is firing.

## Add a dashboard

1. Build or edit the dashboard in Grafana.
2. **Share → Export → Save to file** (export for sharing externally, so the datasource
   becomes a variable).
3. Save the JSON into `k8s/observability/grafana-dashboards/{name}.json`.
4. Commit and push. The observability module creates a ConfigMap per file, and the
   sidecar loads it into the **Petclinic** folder.

Dashboards edited only in the Grafana UI are lost when the pod is replaced. Export and
commit, or it did not happen.

## Related documents

- [Incident playbook](./incident-playbook.md)
- [Runbook](./runbook.md)
- [Architecture](./architecture.md)
- [ADR-0013: Loki over CloudWatch](./adr/0013-loki-over-cloudwatch.md)
