# Incident Playbook

**Last Updated:** 2026-09-02

What to do when the platform misbehaves: severity, first commands, common failures, and
the record you write afterwards. Routine procedures live in [runbook.md](./runbook.md).

## Contents

- [Severity levels](#severity-levels)
- [Escalation](#escalation)
- [First five minutes](#first-five-minutes)
- [Scenarios](#scenarios)
  - [CrashLoopBackOff](#crashloopbackoff)
  - [Service missing from Eureka](#service-missing-from-eureka)
  - [RDS connection failures](#rds-connection-failures)
  - [ECR image pull failure](#ecr-image-pull-failure)
  - [Node NotReady](#node-notready)
  - [High latency or timeouts](#high-latency-or-timeouts)
- [Status update template](#status-update-template)
- [RCA template](#rca-template)

> Alertmanager posts to Slack when `slack_webhook_url` is set in gitignored
> `terraform.tfvars`. If that URL is empty, alerts go to a blackhole and nothing
> is delivered. Treat the alert rules as diagnostic aids; confirm Slack after
> the observability apply.

## Severity levels

| Severity | Meaning | Examples | Response target |
|----------|---------|----------|-----------------|
| **SEV1** | Platform down or data at risk | App unreachable over HTTPS; RDS unavailable; all nodes `NotReady`; suspected credential compromise | Begin within **15 minutes** |
| **SEV2** | Degraded but usable | One domain service down; high error rate or latency; ArgoCD cannot sync; one node lost | Begin within **1 hour** |
| **SEV3** | Minor or cosmetic | Single pod restart that recovered; a dashboard panel broken; non-blocking warning alert | **Next business day** |

Judgement calls: if prod customer-facing traffic is failing, it is SEV1. If only dev is
affected, drop one level — dev has no external users.

## Escalation

Roles, not individuals. Fill in the on-call rota wherever the team keeps it.

| Level | Role | Engage when |
|-------|------|-------------|
| **L1** | On-call engineer | First responder for everything |
| **L2** | Senior platform engineer | No progress after 30 minutes (SEV1) or 2 hours (SEV2); any change to prod Terraform or state |
| **L3** | Platform architect / AWS support | Suspected AWS-side fault, control-plane failure, data loss, or anything needing an architectural decision |

Escalate early rather than late. Escalating is not an admission of failure; a silent
stalled incident is.

## First five minutes

Establish scope before changing anything.

```bash
aws eks update-kubeconfig --name petclinic-{env} --region us-east-1

# 1. What is not running?
kubectl get pods -n petclinic-{env}
kubectl get pods -A --field-selector=status.phase!=Running

# 2. Is the cluster itself healthy?
kubectl get nodes
kubectl top nodes 2>/dev/null || echo "metrics-server not installed (expected)"

# 3. What changed recently?
kubectl get events -n petclinic-{env} --sort-by=.lastTimestamp | tail -30
git log --oneline -10 -- helm-values/

# 4. Is ArgoCD in sync?
kubectl get applications -n argocd
```

Then decide severity, and say so out loud in whatever channel the team uses before you
start digging.

---

## Scenarios

### CrashLoopBackOff

**Symptoms:** Pod restarts repeatedly; `RESTARTS` climbing; `PodRestartLoop` alert
firing in Alertmanager.

**Diagnose:**

```bash
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service}
kubectl describe pod {pod} -n petclinic-{env}
kubectl logs {pod} -n petclinic-{env} --previous     # the crashed container
kubectl logs {pod} -n petclinic-{env} -c wait-for-config-server   # init container
```

**Common causes, in the order worth checking:**

1. **Init container never finishes** — config-server or discovery-server is not up.
   The pod sits in `Init:0/2`, not `CrashLoopBackOff`. Fix the dependency first;
   start-up order is config → discovery → everything else.
2. **Missing secret** — the Kubernetes Secret has not synced. Check
   `kubectl get externalsecret -n petclinic-{env}`; `STATUS` must be `SecretSynced`.
3. **Bad image tag** — see [ECR image pull failure](#ecr-image-pull-failure).
4. **OOMKilled** — `kubectl describe pod` shows `Reason: OOMKilled`. The container hit
   its 512Mi limit. Raise `resources.limits.memory` in `helm-values/{service}.yaml` and
   deploy through Git; do not patch the Deployment.
5. **Datasource failure at startup** — for customers, visits, or vets, see
   [RDS connection failures](#rds-connection-failures).

**Resolve:** Fix the cause, then let ArgoCD re-sync, or
`kubectl rollout restart deployment/{service} -n petclinic-{env}` if the fix was outside
the manifest. Roll back the image tag through Git if the new build is the problem —
[runbook](./runbook.md#procedure-roll-back-a-service).

---

### Service missing from Eureka

**Symptoms:** api-gateway returns 503 for one route; the service's pods are `Running`;
the Eureka dashboard does not list it.

**Diagnose:**

```bash
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name=discovery-server
kubectl logs deployment/{service} -n petclinic-{env} | grep -i -E "eureka|registration"

# Reach the Eureka UI
kubectl port-forward svc/discovery-server -n petclinic-{env} 8761:8761
# then open http://localhost:8761

# Can the service resolve and reach discovery?
kubectl run -it --rm netcheck --image=busybox:1.36 --restart=Never \
  -n petclinic-{env} -- sh -c \
  "wget -qO- http://discovery-server:8761/actuator/health; echo; nslookup discovery-server"
```

**Common causes:**

1. **Discovery restarted** — registrations rebuild over roughly 30 seconds. Wait before
   acting.
2. **NetworkPolicy** — `allow-discovery-server` permits 8761 from pods in the same
   namespace. If policies were edited, confirm with
   `kubectl get networkpolicy -n petclinic-{env}`; deleting `default-deny-ingress` is
   the fastest way to confirm or exclude policy as the cause.
3. **Service still starting** — Spring registers after the context is up; readiness may
   pass slightly earlier.

**Resolve:** Restart the affected service after discovery is confirmed healthy. If the
policy is at fault, correct `k8s/security/{env}/` and re-apply — that YAML is applied by
the operator, not ArgoCD.

---

### RDS connection failures

**Symptoms:** `Communications link failure` or `Access denied` in customers, visits, or
vets logs; those three services unhealthy while the other five are fine.

**Diagnose:**

```bash
# Is the instance up?
aws rds describe-db-instances \
  --db-instance-identifier petclinic-{env}-mysql --region us-east-1 \
  --query 'DBInstances[0].{status:DBInstanceStatus,endpoint:Endpoint.Address}'

# Did the credentials sync?
kubectl get externalsecret rds-credentials -n petclinic-{env}
kubectl get secret rds-credentials -n petclinic-{env}

# Can a pod reach 3306?
kubectl run -it --rm debug-mysql --image=mysql:8 --restart=Never \
  -n petclinic-{env} -- \
  mysql -h {rds-endpoint} -u {username} -p petclinic
```

**Common causes:**

1. **Instance stopped** — `scripts/stop-env.sh` stops RDS to save cost. `start-env.sh`
   brings it back; startup takes several minutes.
2. **Password rotated without restarting pods** — the Secret updated but the JVM holds
   the old value. Restart the three services. See
   [secret-rotation.md](./secret-rotation.md).
3. **Secret never synced** — ESO cannot read Secrets Manager. Check the operator:
   `kubectl logs -n external-secrets deployment/external-secrets`. Confirm the
   ServiceAccount annotation matches `terraform output eso_role_arn`.
4. **Security group** — RDS accepts 3306 from the node security group only. If SGs were
   changed, compare against `terraform/modules/vpc/security-groups.tf`.
5. **Storage full** — check `FreeStorageSpace` in the RDS console. Storage autoscaling
   is deliberately disabled (`max_allocated_storage` equals `allocated_storage`).

**Resolve:** Address the cause; restart the three data services once the database is
reachable.

---

### ECR image pull failure

**Symptoms:** `ImagePullBackOff` or `ErrImagePull`; `kubectl describe pod` shows
`manifest for ... not found` or an authorization error.

**Diagnose:**

```bash
kubectl describe pod {pod} -n petclinic-{env} | grep -A5 Events

# Does the tag exist?
aws ecr describe-images \
  --repository-name petclinic-{env}/{service} \
  --image-ids imageTag={sha} --region us-east-1

# What tag does Git ask for?
grep -A3 '^image:' helm-values/{service}.yaml
```

**Common causes:**

1. **Tag does not exist** — CI failed or was never run for that commit, or the tag was
   hand-edited. Check the app repo's `build-push.yml` run.
2. **Wrong registry for the environment** — `image.registry` in `helm-values/{env}.yaml`
   still holds the `ACCOUNT` placeholder, or points at the other environment's prefix.
3. **Node cannot reach ECR** — outbound goes through NAT. If NAT or the route table is
   broken, every pull fails at once, not just one service.
4. **Node role lost ECR read** — the node role carries
   `AmazonEC2ContainerRegistryReadOnly`; if it was detached, all pulls fail.

**Resolve:** Point Git at a tag that exists and let ArgoCD sync. If the registry host is
wrong, fix `helm-values/{env}.yaml` — never `kubectl set image`.

---

### Node NotReady

**Symptoms:** `kubectl get nodes` shows `NotReady`; pods `Pending` or being evicted;
capacity roughly halved (there are only two nodes).

**Diagnose:**

```bash
kubectl get nodes -o wide
kubectl describe node {node} | grep -A10 Conditions
kubectl get events -A --sort-by=.lastTimestamp | grep -i -E "node|evict" | tail -20

aws ec2 describe-instance-status --region us-east-1 \
  --filters "Name=instance-state-name,Values=running" \
  --query 'InstanceStatuses[].{id:InstanceId,sys:SystemStatus.Status,inst:InstanceStatus.Status}'
```

**Common causes:**

1. **Disk pressure** — 20Gi root volumes fill with images and logs. `DiskPressure` shows
   in the node conditions.
2. **Memory pressure** — two `t4g.small` nodes are 2 GiB each. The observability stack
   plus eight services is a tight fit; that is why the resource quotas exist.
3. **EC2 instance degraded** — replace it; the managed node group will recreate.
4. **Scaled to zero deliberately** — `stop-env.sh` does this. `start-env.sh` reverses it.

**Resolve:**

```bash
# Drain and let the node group replace the node
kubectl drain {node} --ignore-daemonsets --delete-emptydir-data
kubectl delete node {node}
```

The managed node group launches a replacement automatically. Do not drain both nodes at
once — with `minAvailable: 1` PDBs on six services in prod, the drain will block, which
is the intended protection.

---

### High latency or timeouts

**Symptoms:** `HighLatency` or `HighErrorRate` alerts; slow page loads; ALB 5xx.

**Diagnose:**

Open Grafana at `https://grafana-{env}.{domain}` (or port-forward if that host is
unreachable). In Grafana, open **Petclinic / Service Overview** for the error-rate
and RPS split, then the per-service dashboard for p95/p99. Then find where the
time goes:

```bash
kubectl port-forward svc/zipkin -n tracing 9411:9411
# fallback: http://localhost:9411 — or https://zipkin-{env}.{domain}
```

Only api-gateway, customers-service, visits-service, vets-service, and genai-service
emit traces. config-server, discovery-server, and admin-server do not.

**Common causes:**

1. **Database slow** — check the RDS console for CPU and connections;
   `db.t4g.micro` is small. Zipkin shows the JDBC span dominating.
2. **JVM garbage collection** — the JVM dashboard shows heap near the limit and GC pause
   time climbing. Usually precedes an OOMKill.
3. **Under-replicated** — dev runs one replica of everything. A single restarting pod is
   a total outage for that service.
4. **genai-service waiting on OpenAI** — an external dependency; latency there is not a
   platform fault.

**Resolve:** Short term, scale the affected service via `helm-values/` and Git. Longer
term, take the finding to an RCA action item rather than leaving replicas permanently
raised without a reason recorded.

---

## Status update template

Post at declaration, at meaningful change, and at resolution. Keep it factual.

```
[SEV{1,2,3}] {short description} — {INVESTIGATING | IDENTIFIED | MONITORING | RESOLVED}

Environment: {dev|prod}
Started:     {UTC timestamp}
Impact:      {what users cannot do right now}
Current:     {what is known, what is being tried}
Next update: {UTC timestamp}
Owner:       {role, e.g. on-call engineer}
```

Do not name individuals, and do not speculate about cause in a status update. Say what
is known.

---

## RCA template

Write one for every SEV1 and any SEV2 that recurs. Within five business days, blameless.

```markdown
# RCA: {short title}

**Date of incident:** {YYYY-MM-DD}
**Severity:** SEV{1,2,3}
**Duration:** {start UTC} to {end UTC} ({total})
**Environment:** {dev|prod}
**Author:** {role}

## Impact
{Who or what was affected, and how. Quantify: requests failed, services down, data lost.}

## Timeline
| Time (UTC) | Event |
|------------|-------|
| {hh:mm} | {what happened or what was observed} |
| {hh:mm} | {action taken, by which role} |
| {hh:mm} | Service restored |

## Root cause
{The technical cause. Not "someone made a mistake" — what made the mistake possible or
undetected.}

## Contributing factors
- {What made it worse, slower to detect, or harder to fix}

## What went well
- {Detection, tooling, or procedure that helped}

## Action items
| Action | Type | Owner (role) | Target |
|--------|------|--------------|--------|
| {change} | prevent / detect / mitigate | {role} | {date} |

## Prevention
{The change that stops this class of failure, not just this instance.}
```

File the RCA in the team's tracker and raise the action items as tickets. An RCA with no
tracked action items has not finished.

## Related documents

- [Runbook](./runbook.md)
- [Monitoring guide](./monitoring-guide.md)
- [DR plan](./dr-plan.md)
- [Architecture](./architecture.md)
