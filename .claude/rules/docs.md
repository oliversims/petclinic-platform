---
paths:
  - "docs/**/*.md"
---

# Documentation Rules

Claude writes **markdown only** for E-15. No Terraform, no Helm install, no `kubectl apply`, no `terraform destroy`. Do not create `docs/helm-guide.md` or `docs/cost.md`. Do **not** edit `docs/technical-spec.md` or `docs/jira-backlog.md` — those are already locked.

## Directory Structure

```
docs/
├── architecture.md          # PETPLAT-77 — diagrams; link the spec, do not copy every table
├── runbook.md               # PETPLAT-78 — deploy, rollback, scale, restart, state, EKS upgrade
├── secret-rotation.md       # PETPLAT-78 — manual rotation only (no TF rotation resources)
├── incident-playbook.md     # PETPLAT-79 — failures + SEV/RCA (folded PETPLAT-104)
├── onboarding.md            # PETPLAT-80 — tools, access, first GitOps change
├── monitoring-guide.md      # PETPLAT-97 — not monitoring-alerting-guide.md
├── dr-plan.md               # PETPLAT-99 — not disaster-recovery.md; no lessons from PETPLAT-90
├── compliance-checklist.md  # PETPLAT-100 — CloudTrail is not in this stack
└── adr/
    ├── 0001-network-layout.md
    ├── 0002-eks-over-ecs.md
    ├── 0003-shared-rds.md
    ├── 0004-plain-yaml-over-helm.md
    ├── 0005-github-actions-oidc.md
    ├── 0006-single-az-rds.md
    ├── 0007-helm-over-plain-yaml.md
    ├── 0008-argocd-gitops.md
    ├── 0009-karpenter.md
    ├── 0010-ecr-private.md
    ├── 0011-secrets-manager.md
    ├── 0012-externaldns.md
    └── 0013-loki-over-cloudwatch.md
```

ADR numbering matches `docs/technical-spec.md` § ADR Index. **0009 is Karpenter**, not ECR. **0010 is ECR Private**. **0011 is Secrets Manager**. **0012 is ExternalDNS**. Do not skip 0011 or 0012. Write 0009 even though E-14 is unbuilt. 0004 status: Superseded by ADR-0007. Date: 2026-09-02.

## Writing Conventions

1. **Audience:** Internal DevOps/Cloud team who inherit this platform. Assume AWS + K8s familiarity.
2. **Tone:** Direct, actionable, no filler. Prefer commands over descriptions.
3. **Format:** Every doc MUST have:
   - Title (H1)
   - Last Updated date
   - Purpose (1-2 sentences)
   - Table of Contents (for docs > 3 sections)
4. **Code blocks:** Every command must be copy-pasteable. Include the full command, not fragments.
5. **Environment awareness:** Always specify which env (dev/prod) or use `{env}` placeholder.
6. **Placeholders:** `{domain}`, `{account}`, `{env}` only. Never a real AWS account ID, never a real hostname, never a password.

## Runbook Format

Runbooks follow a strict format for each procedure:

```markdown
### Procedure: {name}

**When:** {trigger condition}
**Who:** {required role/access}
**Time:** {expected duration}

**Steps:**
1. {step with exact command}
2. {step with exact command}

**Verify:**
- {how to confirm success}

**Rollback:**
- {how to undo if it fails}
```

## What is true of this stack (do not invent the opposite)

- **App CD:** ArgoCD ApplicationSet + Git image tag. Not `helm upgrade --install` on Spring services. Not `kubectl apply` on app Deployments. CI never deploys.
- **Grafana / Zipkin / Argo CD:** HTTPS on dedicated ALBs, CIDR-locked to `public_access_cidrs`. Hosts `grafana-{env}.{domain}` / `zipkin-{env}.{domain}` / `argocd-{env}.{domain}` (prod: `grafana.{domain}` / `zipkin.{domain}` / `argocd.{domain}`). Port-forward is the fallback.
- **Prometheus / Alertmanager:** `kubectl port-forward` only. No public Ingress.
- **Grafana password:** `terraform output grafana_admin_password`. Never commit or sample a password.
- **Alertmanager:** Slack when `slack_webhook_url` is set in gitignored tfvars; otherwise blackhole. No webhook URLs in Git.
- **Logs:** Loki via Grafana Explore (LogQL). Not CloudWatch Logs. Not `k8s/observability/` Spring Deployments.
- **RDS access:** debug pod (`kubectl run` MySQL client in `petclinic-{env}`). No bastion.
- **NetworkPolicy:** `k8s/security/{dev,prod}/` after VPC CNI `enableNetworkPolicy`. Not ArgoCD. Operator applies.
- **CloudTrail:** not deployed. Say so in the compliance checklist.
- **Karpenter:** not built (E-14). Document as planned; do not write install steps as if nodes are Karpenter-managed today.
- **PETPLAT-90:** parked. Document destroy/rebuild as a procedure. Do **not** run it. Do **not** claim lessons from a test that has not happened.
- **Contacts:** role names only (`on-call engineer`, `team lead`). No personal names or emails.

## ADR Format

Architecture Decision Records use the standard template:

```markdown
# ADR-{number}: {title}

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-{N}
**Date:** YYYY-MM-DD
**Context:** {what is the problem or decision to be made}
**Decision:** {what was decided and why}
**Consequences:** {positive and negative outcomes}
```

## Cross-References

- Terraform modules: `terraform/modules/{module}/`
- App Helm: `helm/petclinic-service/`, `helm-values/`
- K8s: `k8s/` (live), `k8s-reference/` (pre-Helm reference), `k8s/security/{dev,prod}/`, `k8s/observability/`, `k8s/argocd/`
- Link `docs/technical-spec.md` for ports, quotas, cost, chart versions — do not duplicate those tables
- Link related ADRs when explaining “why” (ADR-0011 = Secrets Manager; ADR-0012 = ExternalDNS; ADR-0013 = Loki over CloudWatch)
- Include Jira ticket IDs (PETPLAT-xxx) where applicable

## What NOT to Include

- No secrets, passwords, or API keys (even examples)
- No personal names or emails (use role names: "on-call engineer", "team lead")
- No internal URLs that won't work for the handover team
- No screenshots without alt text describing the content
- No `docs/helm-guide.md`, `docs/cost.md`, `docs/terraform-ops.md`, `docs/monitoring-alerting-guide.md`, `docs/disaster-recovery.md`
