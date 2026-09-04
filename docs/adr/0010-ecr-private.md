# ADR-0010: ECR Private for container images

**Status:** Accepted
**Date:** 2026-09-02

## Context
The eight service images need a registry the EKS nodes can pull from. The options are ECR
Private, ECR Public, or Docker Hub.

## Decision
ECR Private, one repository per service per environment:
`petclinic-{env}/{service}`.

- Scan-on-push enabled.
- Lifecycle policy: expire untagged after 7 days, keep the last 10 tagged.
- Tag mutability MUTABLE in dev (a tag can be re-pushed while iterating), IMMUTABLE in
  prod (a deployed tag cannot be overwritten).
- CI pushes the same commit SHA to both prefixes, so one Helm `image.tag` works in both
  environments.

## Consequences
**Positive**

- Access is IAM-controlled; the node role carries read-only pull permission and CI holds
  push permission scoped to these repositories.
- No Docker Hub rate limits.
- Scan-on-push gives CVE visibility without extra tooling.
- Immutable prod tags mean a deployed artefact cannot be swapped underneath a running
  release.
- Pulls stay in-region and, via the S3 Gateway endpoint, off NAT.

**Negative**

- Roughly $1/month beyond the 500 MB free tier — negligible, but not zero.
- Immutable prod tags mean a re-run of CI on an unchanged commit fails the push; pipeline
  retry logic has to tolerate that.
- Images must be pushed to both prefixes, doubling storage for the same artefact.

