# ADR-0004: Plain Kubernetes YAML over Helm

**Status:** Superseded by ADR-0007
**Date:** 2026-09-02

## Context
The eight services needed packaging for deployment. The choice was between hand-written
Kubernetes manifests with Kustomize overlays for environment differences, and a Helm
chart with values files.

## Decision
Plain Kubernetes YAML in what is now `k8s-reference/base/` with Kustomize overlays in `k8s-reference/overlays/{dev,prod}/`.

The reasoning at the time: raw manifests are transparent. What is in the file is what
reaches the cluster, with no templating layer to reason about, which is easier to learn
from and to debug.

## Consequences
**Superseded by [ADR-0007](./0007-helm-over-plain-yaml.md).**

The approach worked but produced eight nearly identical directories of manifests — a
change to a probe or a security context meant editing eight files. ArgoCD also drives
Helm releases more naturally than Kustomize overlays for this repository's structure.

`k8s-reference/base/` and `k8s-reference/overlays/` remain in the repository as the reference the Helm values
were derived from, and as a readable illustration of what the chart renders. They are not
the deployment path. Live namespaces and ExternalSecrets are under `k8s/base/`.

