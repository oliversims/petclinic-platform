# ADR-0002: EKS over ECS

**Status:** Accepted
**Date:** 2026-09-02

## Context
The application is eight containerised Spring Boot services that need an orchestrator on
AWS. The realistic options are ECS with Fargate, EKS, or plain EC2 with Docker Compose.

## Decision
Amazon EKS with a managed node group.

ECS is simpler to operate, cheaper (no $73/month control plane), and integrates more
directly with other AWS services. It was rejected anyway because Kubernetes skills
transfer between clouds and employers, and ECS skills largely do not. The point of this
platform is what its operators learn from running it.

## Consequences
**Positive**

- Kubernetes is the industry default; the concepts transfer to GKE, AKS, and on-premises.
- Access to the Kubernetes ecosystem: Helm, ArgoCD, External Secrets Operator,
  Prometheus, and the rest of this platform's tooling.
- Declarative, portable manifests rather than AWS-specific task definitions.

**Negative**

- The control plane costs about $73/month per cluster and cannot be turned off — with two
  environments that is the largest fixed cost in the project.
- Substantially more moving parts than ECS: CNI, CoreDNS, kube-proxy, CSI drivers, and
  add-on version compatibility all become the operator's problem.
- Steeper learning curve before the first deployment works.

