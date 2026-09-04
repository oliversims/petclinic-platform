# ADR-0006: Single-AZ RDS for both environments

**Status:** Accepted
**Date:** 2026-09-02

## Context
RDS Multi-AZ maintains a synchronous standby in a second availability zone and fails over
automatically. It also doubles the instance cost and takes the deployment outside the free
tier.

## Decision
Single-AZ `db.t4g.micro` in both dev and prod, with 7-day automated backups.

Prod is deliberately identical to dev here. The cost of Multi-AZ is not justified for a
learning platform, and having prod visibly single-AZ makes the trade-off legible rather
than hidden.

## Consequences
**Positive**

- Stays within the RDS free tier for the first 12 months.
- Halves the database bill relative to Multi-AZ.
- Operators see explicitly what Multi-AZ would buy and what it costs.

**Negative**

- An availability-zone failure takes the database down, and with it the three data
  services and effectively the application.
- Maintenance windows and instance changes cause a brief outage rather than a failover.
- Recovery from an AZ loss means restoring from backup, so the RPO is the backup window
  rather than near-zero — see [dr-plan.md](../dr-plan.md).
- `skip_final_snapshot = true` compounds this: a destroy discards the data.

Enabling Multi-AZ is a one-line change (`multi_az = true`) when the trade-off changes.

