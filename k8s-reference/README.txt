k8s-reference/
=============

Pre-Helm plain YAML kept for learning / history only.

Contents
--------
base/{8 services}/     Deployments, Services, ConfigMaps, ServiceAccounts
base/kustomization.yaml
overlays/{dev,prod}/   Old Kustomize overlays (replicas, HPA, PDB, ESO patch examples)

Do not use for the live path
----------------------------
Apps deploy via helm/petclinic-service + helm-values/ + Argo CD.
Namespaces and ExternalSecrets stay under k8s/base/ (live).

Optional dry build (not required)
---------------------------------
  kubectl kustomize k8s-reference/overlays/dev
