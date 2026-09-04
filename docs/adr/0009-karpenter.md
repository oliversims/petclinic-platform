# ADR-0009: Karpenter over Cluster Autoscaler

**Status:** Accepted
**Date:** 2026-09-02

## Context
The cluster runs a fixed managed node group of two `t4g.small` instances. That is enough
for the current workload but has no response to load: pods pend until a human changes the
desired count.

The two established options are the Kubernetes Cluster Autoscaler, which adjusts an
Auto Scaling Group, and Karpenter, which provisions instances directly through the EC2
Fleet API.

## Decision
Karpenter, when node autoscaling is implemented.

Karpenter provisions nodes in well under a minute against Cluster Autoscaler's several,
picks instance types per pending pod rather than per node group, and handles Spot
diversification and interruption natively. It is where the industry has moved.

**This is not built.** Epic E-14 is unimplemented; nodes today are a fixed managed node
group. This ADR records the decision so the design is settled when the work is scheduled.

## Consequences
**Positive**

- Faster scale-up, which matters when a single pending pod blocks a deploy.
- Instance selection per workload instead of per node group.
- Better Spot handling once the Graviton free trial expires and Spot starts to pay.
- Consolidation reclaims underused nodes automatically.

**Negative**

- More IAM setup than Cluster Autoscaler: a controller role, an instance profile, an SQS
  interruption queue, and EventBridge rules.
- Karpenter manages nodes outside the managed node group, so two mechanisms coexist
  during migration.
- Nothing is implemented, so this ADR describes intent rather than the running system.
  Do not read the platform as Karpenter-managed today.

