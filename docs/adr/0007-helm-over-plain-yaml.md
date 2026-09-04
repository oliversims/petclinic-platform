# ADR-0007: Helm over plain Kubernetes YAML

**Status:** Accepted
**Date:** 2026-09-02

## Context
The plain-YAML approach ([ADR-0004](./0004-plain-yaml-over-helm.md)) produced eight
directories of nearly identical manifests. The eight services differ in perhaps a dozen
values — port, Spring profile, init containers, resources, and which of them get an HPA,
a PDB, or an Ingress — but each carried a full copy of every manifest.

Changing a probe path meant eight edits, and ArgoCD's multi-source values pattern fits
Helm more naturally than Kustomize overlays.

## Decision
A single generic chart, `helm/petclinic-service/`, deployed once per service.

- Per-service values in `helm-values/{service}.yaml` — port, profile, init containers,
  secrets, autoscaling and PDB flags.
- Per-environment values in `helm-values/{env}.yaml` — namespace, image registry, replica
  count, Ingress host and certificate.
- Merge order, last wins: chart defaults, then service, then environment.
- Sixteen releases: eight services times two environments.

Zipkin is a second, separate in-repo chart because it is infrastructure rather than a
Petclinic service.

## Consequences
**Positive**

- One change to a probe, a security context, or a label reaches all eight services.
- Environment differences are visible in two small files rather than spread across
  overlays.
- ArgoCD's multi-source `$values` pattern works directly.
- `scripts/validate-helm.sh` renders and dry-runs all sixteen releases in one command.

**Negative**

- Go templating is less transparent than raw YAML; what reaches the cluster requires
  `helm template` to see.
- A mistake in the shared chart affects all eight services at once.
- One more tool to know, on top of Kubernetes itself.

