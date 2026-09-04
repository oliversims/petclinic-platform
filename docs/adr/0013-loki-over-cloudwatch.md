# ADR-0013: Loki over CloudWatch Logs

**Status:** Accepted
**Date:** 2026-09-02

## Context
The eight services produce logs that need collecting, storing, and searching. On EKS the
default answer is Fluent Bit shipping to CloudWatch Logs with an IRSA role, queried with
CloudWatch Logs Insights.

## Decision
An in-cluster stack: Fluent Bit as a DaemonSet, pushing to Loki, queried through Grafana
Explore with LogQL.

- Loki runs in SingleBinary mode on an EBS PVC — no MinIO, no S3 bucket, no object store.
- Retention is 7 days in dev and 30 in prod.
- No CloudWatch log groups for application logs, and Fluent Bit needs no IRSA role because
  it writes to an in-cluster Service.
- Labels are kept to `namespace`, `pod`, and `container`.

## Consequences
**Positive**

- Logs and metrics share one interface: Grafana, with Loki and Prometheus side by side in
  Explore.
- No per-GB ingestion charge; storage is an EBS volume already paid for.
- No IAM role for the log shipper, so one less credential path.
- LogQL resembles PromQL, so one query language covers both.

**Negative**

- Logs live in the cluster, so **losing the cluster loses the logs** — including the logs
  that would explain why it was lost. CloudWatch would have survived.
- SingleBinary mode has no object store, so the Loki ruler cannot persist state and its
  alert rules are best-effort.
- Retention is bounded by the PVC; there is no cheap cold tier.
- Prometheus, Grafana, and Loki all compete for memory on two `t4g.small` nodes.

Exporting anything needed for an RCA before a rebuild is therefore part of the
[DR procedure](../dr-plan.md), not an afterthought.

