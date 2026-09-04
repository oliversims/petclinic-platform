# Disaster Recovery Plan

**Last Updated:** 2026-09-02

How to rebuild this platform after losing part or all of it, and what is recoverable in
the first place. Commands here are for the operator to run — they are documented, not
executed, by whoever maintains this file.

## Contents

- [Objectives](#objectives)
- [What is backed up](#what-is-backed-up)
- [What is not recoverable](#what-is-not-recoverable)
- [Scenario: full environment rebuild](#scenario-full-environment-rebuild)
- [Scenario: RDS point-in-time recovery](#scenario-rds-point-in-time-recovery)
- [Scenario: Terraform state loss](#scenario-terraform-state-loss)
- [Scenario: accidental namespace or workload deletion](#scenario-accidental-namespace-or-workload-deletion)
- [Single-region risk](#single-region-risk)
- [Communication](#communication)
- [Testing this plan](#testing-this-plan)

## Objectives

Learning-project targets, not a commercial SLA.

| Metric | Target | What sets it |
|--------|--------|--------------|
| **RTO** — time to restore service | ~60 minutes | EKS cluster creation ~15 min, RDS ~8 min, add-ons and ArgoCD sync ~15 min, with headroom |
| **RPO** — acceptable data loss | ~1 hour | RDS automated backups with a 7-day retention window and 5-minute transaction log granularity |

RTO assumes Terraform state is intact and images are in ECR. Losing state adds
substantially to the timeline — see the state-loss scenario.

## What is backed up

| Asset | Mechanism | Retention | Restores in |
|-------|-----------|-----------|-------------|
| RDS data | Automated backups + PITR | 7 days | ~10–20 min |
| Terraform state | S3 bucket versioning | All versions | Minutes |
| Container images | ECR repositories | Last 10 tagged images per service | Immediate |
| Infrastructure definition | This Git repository | Full history | N/A — it *is* the backup |
| Application config | `helm-values/` in Git | Full history | N/A |
| Secret values | AWS Secrets Manager, 30-day recovery window after deletion | 30 days | Minutes |

The most important line is the third-from-last: the platform is defined in code, so
"restore" mostly means "apply the code again".

## What is not recoverable

Be honest about these before an incident, not during one.

- **RDS on destroy.** `skip_final_snapshot = true`, so `terraform destroy` deletes the
  instance *and* its automated backups with no final snapshot. Take a manual snapshot
  first if the data matters.
- **Prometheus, Grafana, and Loki data.** On EBS PVCs, deleted with the cluster. Metrics
  history and logs do not survive a rebuild. Export anything needed for an RCA before
  destroying.
- **Zipkin traces.** In-memory on an emptyDir; lost on pod restart, let alone a rebuild.
- **Anything applied by hand and never committed.** If it is not in Git, a rebuild does
  not bring it back. This is the strongest argument for the GitOps discipline.
- **The Grafana admin password** changes on rebuild — `random_password` generates a new
  one. Read it again with `terraform output`.

## Scenario: full environment rebuild

**When:** Cluster destroyed, environment corrupted beyond repair, or a deliberate
rebuild.
**Who:** Senior engineer with AWS credentials for the account.
**Time:** 60–90 minutes, most of it waiting on AWS.

**Prerequisites:** Terraform state intact (or recovered first), and the Git repository
available.

**Steps:**

1. Confirm what actually still exists before assuming:

   ```bash
   aws eks list-clusters --region us-east-1
   aws rds describe-db-instances --region us-east-1 \
     --query 'DBInstances[].DBInstanceIdentifier'
   aws ecr describe-repositories --region us-east-1 \
     --query 'repositories[].repositoryName'
   cd terraform/environments/{env} && terraform state list | wc -l
   ```

2. If the state bucket itself is gone, recreate the backend before anything else:

   ```bash
   ./scripts/bootstrap-state.sh --region us-east-1
   ```

3. Build the infrastructure. Install flags for cluster add-ons must be **false** on the
   first apply — a Helm release cannot be created in the same apply that creates the
   cluster it targets. In `terraform/environments/{env}/terraform.tfvars`:

   ```hcl
   install_eso           = false
   install_ebs_csi       = false
   install_lb_controller = false
   install_external_dns  = false
   install_observability = false
   ```

   Then:

   ```bash
   cd terraform/environments/{env}
   terraform init
   terraform plan -out plan.out
   terraform apply plan.out
   ```

4. Flip the flags to `true` and apply again. This installs the EKS add-ons, the gp3
   StorageClass, ESO, the Load Balancer Controller, ExternalDNS, the observability stack,
   and Zipkin:

   ```bash
   terraform plan -out plan.out
   terraform apply plan.out
   ```

5. Point kubectl at the new cluster — the API endpoint hostname changes on every
   rebuild:

   ```bash
   aws eks update-kubeconfig --name petclinic-{env} --region us-east-1
   kubectl get nodes
   ```

6. Apply namespaces and ExternalSecrets. The ClusterSecretStore is cluster-scoped.
   Dev ExternalSecret files target **`petclinic-dev`**. For prod use the `*-prod.yaml`
   files (or equivalent). Do **not** `kubectl apply -k k8s-reference/overlays/prod` —
   that reference overlay includes Spring Deployments, which fight ArgoCD.

   ```bash
   kubectl apply -f k8s/base/namespaces.yaml
   kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml

   # Dev
   kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml
   kubectl apply -f k8s/base/external-secrets/openai-api-key.yaml

   # Prod
   kubectl apply -f k8s/base/external-secrets/rds-credentials-prod.yaml
   kubectl apply -f k8s/base/external-secrets/openai-api-key-prod.yaml

   kubectl get secret -n petclinic-{env}
   ```

7. Install ArgoCD and register the applications:

   ```bash
   kubectl apply -k k8s/argocd/install/
   kubectl wait --for=condition=available --timeout=300s \
     deployment/argocd-server -n argocd

   kubectl apply -f k8s/argocd/projects/petclinic-{env}.yaml
   kubectl apply -f k8s/argocd/applications/{env}/applicationset.yaml
   ```

   Substitute the real GitHub org for the `GITHUB_ORG` placeholder in those files first.

8. Apply the security layer:

   ```bash
   kubectl apply -f k8s/security/{env}/
   ```

9. Restore data if the database was lost — see the PITR scenario below. A rebuilt RDS
   instance is empty; Spring initialises the schema on first start but not the data.

**Verify:**

```bash
kubectl get pods -n petclinic-{env}          # 8 services running
kubectl get applications -n argocd           # Synced / Healthy
kubectl get ingress -n petclinic-{env}       # ALB address populated
# The hostname is NOT petclinic-{env}: dev is prefixed, prod is not.
# dev:  petclinic-dev.{domain}      prod: petclinic.{domain}
dig +short petclinic-dev.{domain}            # prod: petclinic.{domain}
curl -sI https://petclinic-dev.{domain} | head -1
```

Then confirm observability: Prometheus targets `UP`, Grafana loads, logs arriving in
Loki.

**Rollback:** Not applicable — this *is* the recovery path. If it fails partway, the
apply is idempotent; fix the error and re-run.

## Scenario: RDS point-in-time recovery

**When:** Data corrupted or deleted, and the instance still exists.
**Who:** Senior engineer.
**Time:** 20–30 minutes.

**Steps:**

1. Find the recoverable window:

   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier petclinic-{env}-mysql --region us-east-1 \
     --query 'DBInstances[0].{earliest:EarliestRestorableTime,latest:LatestRestorableTime}'
   ```

2. Restore to a **new** instance — PITR never restores in place:

   ```bash
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier petclinic-{env}-mysql \
     --target-db-instance-identifier petclinic-{env}-mysql-restored \
     --restore-time {YYYY-MM-DDTHH:MM:SSZ} \
     --db-subnet-group-name petclinic-{env}-db-subnet-group \
     --vpc-security-group-ids {rds-sg-id} \
     --no-publicly-accessible \
     --region us-east-1

   aws rds wait db-instance-available \
     --db-instance-identifier petclinic-{env}-mysql-restored --region us-east-1
   ```

3. Verify the restored data from a debug pod before switching anything —
   [runbook](./runbook.md#procedure-connect-to-rds).

4. Cut over. Either point the services at the new endpoint by updating
   `SPRING_DATASOURCE_URL` in `helm-values/{service}.yaml` and letting ArgoCD sync, or
   rename the instances so the original endpoint resolves to the restored data.

5. Reconcile Terraform. The restored instance is not in state; adopt it with
   `terraform import`, or plan a migration back to a Terraform-managed instance. Do not
   leave the environment permanently drifted.

**Verify:** The application reads the expected data; no connection errors in the three
data services.

**Rollback:** The original instance is untouched by PITR. Point back at it if the
restore is wrong.

## Scenario: Terraform state loss

**When:** State file deleted, truncated, or corrupted.
**Who:** Senior engineer.
**Time:** Minutes if versioning has it; hours if not.

**Steps — recover a previous version:**

```bash
aws s3api list-object-versions \
  --bucket petclinic-terraform-state-{account} \
  --prefix petclinic/{env}/terraform.tfstate \
  --query 'Versions[0:10].[VersionId,LastModified,Size]' --output table

aws s3api get-object \
  --bucket petclinic-terraform-state-{account} \
  --key petclinic/{env}/terraform.tfstate \
  --version-id {version-id} \
  restored.tfstate

cd terraform/environments/{env}
terraform state push restored.tfstate
terraform plan       # must show no unexpected changes
```

**If no usable version exists**, the infrastructure still exists but Terraform no longer
knows about it. Options, worst to best:

1. Import every resource by hand — accurate but slow, dozens of `terraform import` calls.
2. Rebuild into a fresh state and migrate data, accepting an outage.
3. Adopt selectively: import the expensive, stateful resources (VPC, EKS, RDS) and let
   Terraform recreate the cheap ones.

**Verify:** `terraform plan` reports no changes against healthy infrastructure.

**Rollback:** Every `state push` creates a new S3 version, so the pre-push state is
itself recoverable.

## Scenario: accidental namespace or workload deletion

**When:** Someone deletes a Deployment, or a namespace, in a live cluster.
**Who:** On-call engineer.
**Time:** 5–15 minutes.

Because the eight services are GitOps-managed, this is usually self-healing:

- **Dev** has `selfHeal: true` — ArgoCD restores the deleted object within minutes,
  unaided.
- **Prod** requires a manual sync:

  ```bash
  kubectl port-forward svc/argocd-server -n argocd 8443:443
  argocd app sync {service}-prod
  ```

If the whole namespace went, recreate it first, then re-apply the ExternalSecret CRs and
the security layer, then sync. Use the **dev or prod apply** from the full rebuild
step 6 — the base ExternalSecret YAML is hardcoded to `petclinic-dev` / `petclinic/dev/*`.

```bash
kubectl apply -f k8s/base/namespaces.yaml
# then the matching ExternalSecret apply from step 6 (dev files, or prod sed)
kubectl apply -f k8s/security/{env}/
```

Cluster add-ons installed by Terraform (ESO, controllers, observability) are **not**
restored by ArgoCD — re-run `terraform apply` for those.

## Single-region risk

Everything lives in `us-east-1`: both clusters, both databases, ECR, Secrets Manager, and
the Terraform state bucket. A full regional outage takes the platform down and this plan
does not recover from it.

That is an accepted trade-off for a learning platform. Multi-region would mean
cross-region ECR replication, a global database or cross-region read replica, Route 53
health-check failover, and duplicated state — several times the cost and complexity of
the current stack.

Future enhancement, roughly in order of value per unit of effort:

1. Cross-region RDS snapshot copies (cheap; improves the worst case materially).
2. ECR cross-region replication.
3. A warm standby cluster in a second region.

## Communication

Roles, not names. See [incident-playbook.md](./incident-playbook.md) for severity and
escalation.

| Audience | Who informs them | When |
|----------|-----------------|------|
| Engineering team | On-call engineer | At declaration, then hourly |
| Team lead | On-call engineer | Immediately for anything touching prod data |
| Stakeholders | Team lead | At declaration and at restoration |

Use the status-update template in the incident playbook. If a status page exists, it is
at `{status-page-url}` — a placeholder, because this platform does not ship one.

## Testing this plan

A DR plan that has never been executed is a hypothesis.

**Recommended cadence: quarterly**, in dev only, during a low-traffic window.

A test run is: take a manual RDS snapshot, run the full rebuild procedure end to end,
time each phase, and record where the documented steps did not match reality. Update this
file with what you learned — especially the timings, which are estimates until someone
measures them.

**A live teardown and rebuild test (PETPLAT-90) is parked and has not been performed.**
Nothing in this document is derived from an executed test; the procedures come from the
Terraform, Helm, and Kubernetes definitions in this repository. Expect the first real run
to surface gaps, and budget more than the RTO target for it.

## Related documents

- [Runbook](./runbook.md)
- [Incident playbook](./incident-playbook.md)
- [Architecture](./architecture.md)
- [Compliance checklist](./compliance-checklist.md)
