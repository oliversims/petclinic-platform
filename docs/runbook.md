# Operations Runbook

**Last Updated:** 2026-09-02

Day-2 procedures for the Petclinic platform. Every procedure states when to use it, who
can run it, and how to undo it. For secret rotation see [secret-rotation.md](./secret-rotation.md);
for outages see [incident-playbook.md](./incident-playbook.md).

## Contents

- [Before you start](#before-you-start)
- [Deploy a service](#procedure-deploy-a-service)
- [Roll back a service](#procedure-roll-back-a-service)
- [Restart a service](#procedure-restart-a-service)
- [Scale a service](#procedure-scale-a-service)
- [Read logs](#procedure-read-logs)
- [Connect to RDS](#procedure-connect-to-rds)
- [Reach Grafana, Prometheus, Zipkin, ArgoCD](#procedure-reach-grafana-prometheus-zipkin-argocd)
- [Apply NetworkPolicies](#procedure-apply-networkpolicies)
- [Terraform plan and apply](#procedure-terraform-plan-and-apply)
- [Terraform state surgery](#procedure-terraform-state-surgery)
- [Upgrade EKS](#procedure-upgrade-eks)
- [Tear down an environment](#procedure-tear-down-an-environment)

## Before you start

```bash
# Point kubectl at the right cluster. Do this every time you switch environments.
aws eks update-kubeconfig --name petclinic-{env} --region us-east-1
kubectl config current-context
```

The EKS public endpoint is restricted to the operator's IP. If `kubectl` hangs or times
out, your public IP has probably changed — update `public_access_cidrs` in
`terraform/environments/{env}/terraform.tfvars` and apply.

Two rules that shape everything below:

- **Applications are deployed by ArgoCD from Git.** Never `helm upgrade --install` or
  `kubectl apply` a Spring Deployment. Those changes are reverted by self-heal in dev,
  and in prod they drift from Git silently.
- **Cluster add-ons are deployed by Terraform.** ESO, the Load Balancer Controller,
  ExternalDNS, the observability stack, and Zipkin change via `terraform apply`.

---

### Procedure: Deploy a service

**When:** A new image tag needs to reach an environment.
**Who:** Engineer with write access to this repo; prod also needs ArgoCD sync rights.
**Time:** 5 minutes dev, plus review time for prod.

**Steps:**

1. Confirm the image exists in ECR:

   ```bash
   aws ecr describe-images \
     --repository-name petclinic-{env}/{service} \
     --image-ids imageTag={sha} \
     --region us-east-1
   ```

2. For a CI-built commit the tag is already committed by `update-image-tags.yml`. To set
   one by hand, edit `helm-values/{service}.yaml`:

   ```yaml
   image:
     tag: {sha}   # 7-character commit SHA, never "latest"
   ```

3. Commit and push to `main`:

   ```bash
   git add helm-values/{service}.yaml
   git commit -m "deploy: {service} to {sha}"
   git push origin main
   ```

4. Dev syncs on its own within about three minutes. For prod, sync deliberately:

   ```bash
   argocd login argocd-{env}.{domain} --grpc-web
   # or port-forward: kubectl port-forward svc/argocd-server -n argocd 8443:443
   argocd app sync {service}-prod
   ```

**Verify:**

```bash
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service}
kubectl get deployment {service} -n petclinic-{env} \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

The reported image must end in the tag you committed, and pods must be `Running` with
readiness gates passed.

**Rollback:** See the next procedure. Do not fix a bad deploy with `kubectl set image` —
ArgoCD will revert it in dev and mask the drift in prod.

---

### Procedure: Roll back a service

**When:** A deployed tag is bad and the previous one was good.
**Who:** Same as deploy.
**Time:** 5 minutes.

**Steps:**

1. Find the previous tag from Git history:

   ```bash
   git log --oneline -5 -- helm-values/{service}.yaml
   git show {previous-commit}:helm-values/{service}.yaml | grep -A2 '^image:'
   ```

2. Put that tag back and push:

   ```bash
   git revert {bad-commit}          # or edit image.tag manually
   git push origin main
   ```

3. Prod: sync as in the deploy procedure. Dev: wait for auto-sync.

**Verify:** Same checks as deploy, expecting the older tag.

**Rollback:** Rolling forward to a known-good tag is always available; the images stay
in ECR until the lifecycle policy expires them (last 10 tagged images retained).

> For an emergency where Git is unavailable, `argocd app rollback {service}-{env}` moves
> the live release back one revision. This puts the cluster out of step with Git —
> reconcile by committing the correct tag as soon as possible.

---

### Procedure: Restart a service

**When:** A service needs a clean restart — stuck connection pool, refreshed config, or
newly synced secret.
**Who:** Anyone with cluster access.
**Time:** 2 minutes.

**Steps:**

```bash
kubectl rollout restart deployment/{service} -n petclinic-{env}
kubectl rollout status deployment/{service} -n petclinic-{env} --timeout=5m
```

**Verify:**

```bash
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service}
```

Pod age resets; the image tag does not change, so ArgoCD stays in sync.

**Rollback:** None needed — this creates no drift. If the new pods fail to start, treat
it as an incident and see [CrashLoopBackOff](./incident-playbook.md#crashloopbackoff).

---

### Procedure: Scale a service

**When:** Load requires more replicas, or you are reducing cost.
**Who:** Engineer with repo write access.
**Time:** 5 minutes.

**Steps:**

1. Edit the environment values file, not the cluster.

   For every service in an environment, `helm-values/{env}.yaml`:

   ```yaml
   replicaCount: 2
   ```

   For one service only, `helm-values/prod.yaml`:

   ```yaml
   replicaOverrides:
     genai-service: 1
     admin-server: 1
     {service}: 3
   ```

2. Commit, push, and let ArgoCD sync (prod: sync manually).

**Verify:**

```bash
kubectl get deployment {service} -n petclinic-{env}
```

**Rollback:** Revert the commit.

> **Autoscaled services.** api-gateway, customers, visits, vets, and genai have an HPA in
> prod. The HPA owns `spec.replicas` at runtime, so a static change there is overwritten
> shortly after each sync. To change the range, edit `autoscaling.minReplicas` /
> `maxReplicas` in `helm-values/{service}.yaml`. Note the HPA needs Metrics Server, which
> is not yet installed (PETPLAT-72) — until then it reports `<unknown>` and does not act.

---

### Procedure: Read logs

**When:** Diagnosing anything.
**Who:** Anyone with cluster access.
**Time:** Immediate.

**Steps — live tail:**

```bash
kubectl logs -f deployment/{service} -n petclinic-{env}
kubectl logs deployment/{service} -n petclinic-{env} --previous   # last crashed container
```

**Steps — historical, across pods (Loki):**

1. Open Grafana at `https://grafana-{env}.{domain}` (port-forward fallback:
   `kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80`).

2. Go to **Explore**, choose the **Loki** datasource, and
   query:

   ```logql
   {namespace="petclinic-{env}", pod=~"{service}.*"}
   {namespace="petclinic-{env}"} |= "ERROR"
   {namespace="petclinic-{env}"} |= "OutOfMemoryError"
   ```

Retention is 7 days in dev and 30 in prod. There are no CloudWatch log groups in this
stack — see [ADR-0013](./adr/0013-loki-over-cloudwatch.md).

**Verify:** Log lines appear for the expected namespace and pod.

**Rollback:** N/A — read-only.

---

### Procedure: Connect to RDS

**When:** Inspecting schema or data, or confirming credentials work.
**Who:** Engineer with cluster access. RDS is private; there is no bastion and no public
endpoint.
**Time:** 5 minutes.

**Steps:**

1. Start a throwaway MySQL client inside the app namespace, where the node security
   group already permits 3306:

   ```bash
   kubectl run -it --rm debug-mysql \
     --image=mysql:8 \
     --restart=Never \
     -n petclinic-{env} \
     -- bash
   ```

2. Read the credentials from the ESO-synced Secret (in another shell):

   ```bash
   kubectl get secret rds-credentials -n petclinic-{env} \
     -o jsonpath='{.data.username}' | base64 -d; echo
   kubectl get secret rds-credentials -n petclinic-{env} \
     -o jsonpath='{.data.password}' | base64 -d; echo
   ```

3. Connect from inside the debug pod:

   ```bash
   mysql -h {rds-endpoint} -u {username} -p petclinic
   ```

   The endpoint comes from `terraform output rds_endpoint`.

**Verify:**

```sql
SHOW TABLES;
SELECT COUNT(*) FROM owners;
```

**Rollback:** Exit the shell — `--rm` deletes the pod. Never leave a debug pod running,
and never paste credentials into a shared channel or a commit.

---

### Procedure: Reach Grafana, Prometheus, Zipkin, ArgoCD

**When:** You need any of the internal UIs.
**Who:** Anyone with cluster access.
**Time:** 1 minute.

**Steps:**

```bash
# Grafana — prefer the hostname; port-forward if your IP is not allowed
# https://grafana-{env}.{domain}
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
# Alertmanager
kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093
# Zipkin — prefer https://zipkin-{env}.{domain}
kubectl port-forward svc/zipkin -n tracing 9411:9411
# Argo CD — prefer https://argocd-{env}.{domain} (prod: https://argocd.{domain})
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

Credentials:

```bash
# Grafana admin password (sensitive output; do not paste it anywhere persistent)
cd terraform/environments/{env} && terraform output -raw grafana_admin_password

# ArgoCD initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

None of these have an Ingress and none should get one — they are reachable only through
port-forward.

**Verify:** The UI loads on `localhost`.

**Rollback:** Ctrl-C the port-forward.

---

### Procedure: Apply NetworkPolicies

**When:** After VPC CNI network policy is enabled on a cluster, or after editing
`k8s/security/`.
**Who:** Operator with cluster access.
**Time:** 5 minutes.

**Steps:**

1. Confirm the CNI enforces policy — without this, NetworkPolicies are inert:

   ```bash
   aws eks describe-addon --cluster-name petclinic-{env} --addon-name vpc-cni \
     --region us-east-1 --query 'addon.configurationValues'
   ```

   Expect `{"enableNetworkPolicy":"true"}`. It is set by Terraform when
   `install_ebs_csi` is true.

2. Dry-run, then apply:

   ```bash
   kubectl apply --dry-run=client -f k8s/security/{env}/
   kubectl apply -f k8s/security/{env}/
   ```

**Verify:**

```bash
kubectl get networkpolicy -n petclinic-{env}
kubectl get resourcequota,limitrange -n petclinic-{env}
```

Then confirm the platform still works end to end: the app answers over HTTPS, and
Prometheus targets are still `UP` (Prometheus scrapes from `monitoring`, which every
policy allows).

**Rollback:**

```bash
kubectl delete -f k8s/security/{env}/
```

Removing `default-deny-ingress` restores open in-namespace traffic immediately.

> These are applied by the operator, not ArgoCD. The ApplicationSets manage the eight
> app releases only.

---

### Procedure: Terraform plan and apply

**When:** Any infrastructure change.
**Who:** Engineer with AWS credentials for the account.
**Time:** 5 minutes to plan; applies vary — EKS ~15 minutes, RDS ~8.

**Steps:**

```bash
cd terraform/environments/{env}
terraform init
terraform plan -out plan.out
# Read the plan. Check the add/change/destroy counts and every destroy line.
terraform apply plan.out
```

**Verify:**

```bash
terraform output
terraform state list | wc -l
```

**Rollback:** Terraform has no undo. Revert the code change, re-plan, and re-apply. For
a resource that was destroyed, recreation is the only path — which is why every plan
with a destroy line needs reading before it is applied.

> Never `terraform apply` without a saved plan file. A repository hook warns on this.
> The plan is consumed by the apply; a second apply needs a fresh plan.

---

### Procedure: Terraform state surgery

**When:** State no longer matches reality — a resource was deleted outside Terraform, a
resource was renamed in code, or a lock is stuck after a crash.
**Who:** Senior engineer. These commands can make things much worse.
**Time:** 15–30 minutes.

**Steps — inspect first:**

```bash
cd terraform/environments/{env}
terraform state list
terraform state show module.vpc.aws_vpc.this
```

**Steps — adopt an existing resource:**

```bash
terraform import module.vpc.aws_vpc.this vpc-0123456789abcdef0
terraform plan   # must show no changes for that resource
```

**Steps — forget a resource without deleting it in AWS:**

```bash
terraform state rm module.rds.aws_db_instance.this
```

**Steps — follow a rename in code:**

```bash
terraform state mv module.old_name.aws_s3_bucket.this module.new_name.aws_s3_bucket.this
```

**Steps — release a stuck lock.** Only after confirming no apply is running anywhere:

```bash
terraform force-unlock {lock-id}
```

**Steps — restore a corrupted state file from S3 versioning:**

```bash
aws s3api list-object-versions \
  --bucket petclinic-terraform-state-{account} \
  --prefix petclinic/{env}/terraform.tfstate \
  --query 'Versions[0:5].[VersionId,LastModified]' --output table

aws s3api get-object \
  --bucket petclinic-terraform-state-{account} \
  --key petclinic/{env}/terraform.tfstate \
  --version-id {version-id} \
  restored.tfstate

terraform state push restored.tfstate
```

**Verify:** `terraform plan` shows only the changes you expect. If it proposes to
destroy and recreate infrastructure that is healthy, stop and re-examine.

**Rollback:** S3 versioning on the state bucket is the safety net — every one of these
commands writes a new state version, so the previous one can be restored with the
procedure above.

> **When not to use these.** Do not use `state rm` to "fix" a failed apply; find out why
> it failed. Do not use `import` to paper over drift that should be reverted in AWS. Do
> not `force-unlock` because an apply is slow — check whether one is genuinely running.

---

### Procedure: Upgrade EKS

**When:** The current Kubernetes version approaches end of support, or an add-on needs a
newer control plane.
**Who:** Senior engineer, scheduled in a maintenance window.
**Time:** 1–2 hours per environment.

**Pre-checks:**

1. Read the [EKS release notes](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
   for the target version and every version being skipped. Control-plane upgrades are
   one minor version at a time.
2. Check API deprecations against what this repo ships:

   ```bash
   grep -rn "apiVersion:" k8s/ helm/ | sort -u -t: -k3
   ```

3. Confirm the cluster is healthy first — no pods pending, no nodes `NotReady`:

   ```bash
   kubectl get nodes
   kubectl get pods -A --field-selector=status.phase!=Running
   ```

4. Upgrade dev first. Let it run for at least a day before touching prod.

**Steps:**

1. Bump the version in `terraform/environments/{env}/terraform.tfvars`:

   ```hcl
   cluster_version = "1.35"
   ```

2. Plan and read carefully. The control plane updates in place; the node group is
   replaced:

   ```bash
   cd terraform/environments/{env}
   terraform plan -out plan.out
   terraform apply plan.out
   ```

3. Add-on versions resolve from `data.aws_eks_addon_version` for the new cluster
   version, so CoreDNS, kube-proxy, VPC CNI, and EBS CSI move with the same apply.

4. Watch nodes roll. The managed node group replaces them one at a time with
   `max_unavailable = 1`:

   ```bash
   kubectl get nodes -w
   ```

**Verify:**

```bash
kubectl version
kubectl get nodes                      # all Ready, new version
kubectl get pods -A | grep -v Running  # should be empty
aws eks describe-addon --cluster-name petclinic-{env} --addon-name vpc-cni \
  --region us-east-1 --query 'addon.{v:addonVersion,s:status}'
```

Then confirm the app: pods healthy in `petclinic-{env}`, Prometheus targets `UP`, and
the app answering over HTTPS.

**Rollback:** **EKS control-plane upgrades cannot be reversed.** There is no downgrade.
If the new version breaks workloads, the options are to fix forward, or to build a new
cluster on the old version and move traffic — which is the [DR rebuild](./dr-plan.md)
procedure. This is why dev goes first and why the pre-checks matter.

Node groups *can* be rolled back by reverting the version and applying, as long as the
control plane still supports the older kubelet (n-2).

---

### Procedure: Tear down an environment

**When:** Deliberately decommissioning, or reducing cost between working sessions.
**Who:** Operator, with explicit approval. Never run in prod without sign-off.
**Time:** 20–30 minutes.

> **Repository hooks block `terraform destroy` and `kubectl delete` of prod namespaces.**
> That is intentional. If a hook stops you, that is the moment to confirm you are in the
> right environment rather than to work around it.

**Cheaper alternative first.** For an overnight pause, do not destroy:

```bash
./scripts/stop-env.sh {env}    # stops RDS, scales the node group to zero
./scripts/start-env.sh {env}   # brings both back
```

That leaves the EKS control plane (~$73/month) and NAT Gateways billing. Only a destroy
removes those.

**Steps:**

1. Remove Kubernetes-managed AWS resources first, so Terraform is not fighting live
   controllers. Delete the Ingress so the Load Balancer Controller removes its ALB:

   ```bash
   kubectl delete ingress api-gateway -n petclinic-{env}
   ```

2. Confirm the ALB is gone before continuing:

   ```bash
   aws elbv2 describe-load-balancers --region us-east-1 \
     --query "LoadBalancers[?LoadBalancerName=='petclinic-{env}'].State"
   ```

3. Destroy the Terraform stack:

   ```bash
   cd terraform/environments/{env}
   terraform plan -destroy -out destroy.out
   # Read it. Confirm the environment name in the resource addresses.
   terraform apply destroy.out
   ```

4. Secrets Manager keeps deleted secrets for a recovery window, which blocks recreating
   them under the same name. Either wait out the window, restore them, or force-delete:

   ```bash
   aws secretsmanager restore-secret --secret-id petclinic/{env}/rds-credentials --region us-east-1
   # or, if you are sure:
   aws secretsmanager delete-secret --secret-id petclinic/{env}/rds-credentials \
     --force-delete-without-recovery --region us-east-1
   ```

**Verify:**

```bash
terraform state list          # empty
aws eks list-clusters --region us-east-1
aws rds describe-db-instances --region us-east-1 \
  --query 'DBInstances[].DBInstanceIdentifier'
```

**Rollback:** Rebuild from Terraform — see [dr-plan.md](./dr-plan.md). Note that
`skip_final_snapshot = true`, so **destroying RDS discards the data permanently**. Take
a manual snapshot first if the data matters:

```bash
aws rds create-db-snapshot \
  --db-instance-identifier petclinic-{env}-mysql \
  --db-snapshot-identifier petclinic-{env}-manual-$(date +%Y%m%d) \
  --region us-east-1
```

## Related documents

- [Secret rotation](./secret-rotation.md)
- [Incident playbook](./incident-playbook.md)
- [Monitoring guide](./monitoring-guide.md)
- [DR plan](./dr-plan.md)
- [Architecture](./architecture.md)
