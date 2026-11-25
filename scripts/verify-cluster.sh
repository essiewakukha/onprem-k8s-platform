#!/usr/bin/env bash
# Deploy (or upgrade) notes-api with Helm and prove it works.
#
#   IMAGE_TAG=3f9c2ab1d4e0 ./scripts/deploy.sh
#
# Steps: helm upgrade (waits for every pod to be Ready, rolls back
# automatically on failure) -> rollout status -> helm test -> on test
# failure, roll back to the previous revision.
set -Eeuo pipefail

: "${IMAGE_TAG:?set IMAGE_TAG to the immutable image tag to deploy}"
RELEASE="${RELEASE:-notes-api}"
NAMESPACE="${NAMESPACE:-notes}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${CHART:-${REPO_ROOT}/charts/notes-api}"
VALUES_FILE="${VALUES_FILE:-${CHART}/values-production.yaml}"
TIMEOUT="${TIMEOUT:-10m}"

log() { printf '\n==> %s\n' "$*"; }

if [[ "${IMAGE_TAG}" == "latest" ]]; then
  echo "Refusing to deploy ':latest' (not reproducible). Use a git SHA tag." >&2
  exit 1
fi

extra_args=()
if [[ -n "${IMAGE_REPOSITORY:-}" ]]; then
  extra_args+=(--set "image.repository=${IMAGE_REPOSITORY}")
fi

previous_revision="$(helm history "${RELEASE}" -n "${NAMESPACE}" --max 1 -o json 2>/dev/null \
  | jq -r '.[0].revision // empty' || true)"

log "Deploying ${RELEASE} image tag ${IMAGE_TAG} to namespace ${NAMESPACE}"
helm upgrade --install "${RELEASE}" "${CHART}" \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --set "image.tag=${IMAGE_TAG}" \
  "${extra_args[@]}" \
  --wait \
  --rollback-on-failure \
  --timeout "${TIMEOUT}" \
  --history-max 10

log "Confirming the Deployment rollout completed"
kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE}" --timeout=120s

log "Running smoke test"
if ! helm test "${RELEASE}" -n "${NAMESPACE}" --logs --timeout 3m; then
  echo "Smoke test failed." >&2
  if [[ -n "${previous_revision}" ]]; then
    log "Rolling back to revision ${previous_revision}"
    helm rollback "${RELEASE}" "${previous_revision}" -n "${NAMESPACE}" --wait --timeout "${TIMEOUT}"
  fi
  exit 1
fi

log "Deployed. Current pods:"
kubectl -n "${NAMESPACE}" get pods -l "app.kubernetes.io/instance=${RELEASE}" -o wide