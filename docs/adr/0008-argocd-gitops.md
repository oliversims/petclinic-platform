# ADR-0008: ArgoCD for continuous delivery

**Status:** Accepted
**Date:** 2026-09-02

## Context
Something has to deploy the application to the cluster. The obvious approach is a CI step
that runs `helm upgrade --install` or `kubectl apply` after a successful build.

That gives CI credentials to the production cluster, makes the cluster's actual state
invisible outside CI logs, and leaves manual `kubectl` changes undetected indefinitely.

## Decision
ArgoCD runs in-cluster and reconciles from Git. GitHub Actions is CI only — it builds,
scans, pushes images, and commits the new tag to `helm-values/{service}.yaml`. It never
talks to a cluster.

- One `ApplicationSet` per environment generates all eight Applications.
- Dev: `automated` with `prune` and `selfHeal`.
- Prod: no `automated` block — a human syncs.
- AppProjects restrict each environment to a single namespace and to this repository.

## Consequences
**Positive**

- Git is the source of truth; the cluster converges on it.
- CI holds no cluster credentials at all.
- Drift is visible in the ArgoCD UI, and in dev it is corrected automatically.
- Prod approval is a deliberate sync rather than a checkbox in a pipeline.
- Rollback is `git revert`.

**Negative**

- Another component to install, upgrade, and secure.
- Manual `kubectl` changes are reverted, which surprises people once.
- The sync is asynchronous: a merged commit is not immediately live, and diagnosing "why
  is it not deployed" means reading ArgoCD rather than a pipeline log.
- Prod releases wait on a person being available to sync.

