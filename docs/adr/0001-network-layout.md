# ADR-0001: Public/private subnets + NAT

**Status:** Accepted
**Date:** 2026-09-02

## Context
The platform needs somewhere to put an internet-facing load balancer and somewhere to put
workloads and data. An earlier iteration of this project put everything in public subnets
with no NAT Gateway, relying on security groups alone, because NAT costs roughly $33 per
gateway per month and this is a learning platform.

That layout is not what a production AWS account looks like, and the difference matters
for anyone who learns on it: it teaches that a public IP on a database node is normal.

## Decision
Public edge, private compute and data.

- Public subnets hold only the ALB and the NAT Gateways.
- Private subnets hold EKS nodes and RDS, with `map_public_ip_on_launch = false`.
- Dev runs one NAT Gateway; prod runs one per availability zone.
- A free S3 Gateway endpoint keeps S3 and ECR layer traffic off NAT.

This supersedes the original all-public, no-NAT design.

## Consequences
**Positive**

- Nothing that runs application code or stores data has a public IP.
- Matches the layout of a production AWS account, so the skills transfer.
- Prod survives the loss of one availability zone's NAT.

**Negative**

- NAT Gateways are the second-largest line on the bill after the EKS control plane —
  about $33/month in dev and $65 in prod, and they bill whether or not anything is
  deployed.
- Private subnets mean no direct `kubectl` or `mysql` from a laptop to a node or the
  database; access goes through the EKS API endpoint and debug pods.
- One more failure mode to understand: a broken NAT route breaks image pulls cluster-wide.

