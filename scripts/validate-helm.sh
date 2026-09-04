#!/usr/bin/env bash
set -euo pipefail

#
# validate-helm.sh — Lint, render, and dry-run every Helm release
#
# Covers 8 services x 2 environments. Renders only: it never installs or
# upgrades anything on a cluster.
#
# Usage:
#   ./scripts/validate-helm.sh
#   ./scripts/validate-helm.sh --env dev
#   ./scripts/validate-helm.sh --service api-gateway
#   ./scripts/validate-helm.sh --env prod --service vets-service
#
# kubectl dry-run needs a reachable cluster for API discovery. Without one the
# script still lints and renders, and reports the dry-run as skipped.
#

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${REPO_ROOT}/helm/petclinic-service"
VALUES_DIR="${REPO_ROOT}/helm-values"

ALL_SERVICES=(
  config-server
  discovery-server
  api-gateway
  customers-service
  visits-service
  vets-service
  genai-service
  admin-server
)
ALL_ENVS=(dev prod)

FILTER_ENV=""
FILTER_SERVICE=""

usage() {
  echo "Usage: $0 [--env dev|prod] [--service <name>]"
  echo ""
  echo "Options:"
  echo "  --env       Only this environment (default: both)"
  echo "  --service   Only this service (default: all 8)"
  echo "  -h, --help  Show this help"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { echo "Error: --env requires a value"; usage; }
      FILTER_ENV="$2"; shift 2 ;;
    --service)
      [[ $# -ge 2 ]] || { echo "Error: --service requires a value"; usage; }
      FILTER_SERVICE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Error: unknown argument '$1'"; usage ;;
  esac
done

command -v helm >/dev/null 2>&1 || { echo "Error: helm not found on PATH"; exit 1; }

if [[ -n "${FILTER_ENV}" ]]; then
  [[ "${FILTER_ENV}" == "dev" || "${FILTER_ENV}" == "prod" ]] || {
    echo "Error: --env must be 'dev' or 'prod'"; exit 1; }
  ENVS=("${FILTER_ENV}")
else
  ENVS=("${ALL_ENVS[@]}")
fi

if [[ -n "${FILTER_SERVICE}" ]]; then
  [[ -f "${VALUES_DIR}/${FILTER_SERVICE}.yaml" ]] || {
    echo "Error: no values file at helm-values/${FILTER_SERVICE}.yaml"; exit 1; }
  SERVICES=("${FILTER_SERVICE}")
else
  SERVICES=("${ALL_SERVICES[@]}")
fi

# kubectl dry-run needs cluster discovery; skip it cleanly when unreachable.
DRY_RUN=true
if ! command -v kubectl >/dev/null 2>&1; then
  DRY_RUN=false
  echo "[!] kubectl not found — skipping dry-run, lint and template still run"
elif ! kubectl api-versions >/dev/null 2>&1; then
  DRY_RUN=false
  echo "[!] No reachable cluster — skipping dry-run, lint and template still run"
fi

FAILED=0

echo "[=] helm lint ${CHART#"${REPO_ROOT}/"}"
helm lint "${CHART}" >/dev/null || { echo "[x] lint failed"; FAILED=1; }

for env in "${ENVS[@]}"; do
  for svc in "${SERVICES[@]}"; do
    printf '[=] %-18s %-4s ' "${svc}" "${env}"

    if ! rendered="$(helm template "${svc}" "${CHART}" \
        -f "${VALUES_DIR}/${svc}.yaml" \
        -f "${VALUES_DIR}/${env}.yaml" 2>&1)"; then
      echo "template FAILED"
      echo "${rendered}" | sed 's/^/      /'
      FAILED=1
      continue
    fi

    if [[ "${DRY_RUN}" == true ]]; then
      if ! out="$(printf '%s\n' "${rendered}" | kubectl apply --dry-run=client -f - 2>&1)"; then
        echo "dry-run FAILED"
        echo "${out}" | sed 's/^/      /'
        FAILED=1
        continue
      fi
      echo "template OK, dry-run OK"
    else
      echo "template OK, dry-run skipped"
    fi
  done
done

echo ""
if [[ "${FAILED}" -eq 0 ]]; then
  echo "All checks passed."
else
  echo "One or more checks failed."
  exit 1
fi
