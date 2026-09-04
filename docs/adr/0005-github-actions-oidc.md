# ADR-0005: GitHub Actions with OIDC federation

**Status:** Accepted
**Date:** 2026-09-02

## Context
CI needs to push container images to ECR. The traditional approach stores an IAM access
key pair as a repository secret, which means a long-lived credential that never rotates,
can be exfiltrated by any workflow, and shows up in incident reports.

## Decision
GitHub Actions authenticates to AWS through OIDC federation. An IAM OIDC provider trusts
`token.actions.githubusercontent.com`, and the role
`petclinic-github-actions-role` trusts exactly one subject:
`repo:{org}/{repo}:ref:refs/heads/main`.

Permissions are ECR authentication plus push, scoped to `petclinic-dev/*` and
`petclinic-prod/*`. No S3, DynamoDB, or EKS access.

## Consequences
**Positive**

- No long-lived AWS credentials exist anywhere in either repository.
- Credentials are short-lived tokens minted per workflow run.
- The trust policy pins the branch, so a pull request from a fork cannot assume the role.
- This is the pattern AWS recommends.

**Negative**

- More setup than pasting an access key: an OIDC provider, a trust policy, and a subject
  string that must match exactly.
- The subject condition is easy to get subtly wrong, and the failure mode is an opaque
  `AssumeRoleWithWebIdentity` denial.
- Still requires one classic secret — `PLATFORM_REPO_TOKEN`, for the cross-repository
  `repository_dispatch`, which GitHub's own token cannot do.

