k8s/ — live manifests only
==========================

Used by this project
--------------------
k8s/base/namespaces.yaml
k8s/base/external-secrets/
  cluster-secret-store.yaml
  rds-credentials.yaml / openai-api-key.yaml          (dev)
  rds-credentials-prod.yaml / openai-api-key-prod.yaml (prod)
  sample-external-secret.yaml                         (optional smoke test)
  how-to.txt

k8s/karpenter/{dev,prod}/
  NodePool + EC2NodeClass (kubectl apply)

k8s/argocd/
  install/, ingress/{env}.yaml, projects/, applications/

k8s/observability/
  grafana-dashboards/, prometheus-rules/, loki-rules/
  (loaded by Terraform observability module)

k8s/security/{dev,prod}/
  network-policies.yaml, resource-quota.yaml
  (operator apply later; not Argo CD)


Reference (moved out)
---------------------
Pre-Helm service YAML and Kustomize overlays live in:

  k8s-reference/

See k8s-reference/README.txt.
