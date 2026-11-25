#!/usr/bin/env bash
# The lab has no registry: build the app image locally and import it into
# containerd on every lab node, under the name the chart will request.
#
#   ./lab/load-image.sh                 # builds lab.local/notes-api:lab
#   TAG=v2 ./lab/load-image.sh          # a second version, to try a rollout
set -Eeuo pipefail

IMAGE="${IMAGE:-lab.local/notes-api}"
TAG="${TAG:-lab}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tarball="$(mktemp)"
trap 'rm -f "${tarball}"' EXIT

docker build -t "${IMAGE}:${TAG}" "${REPO_ROOT}/app"
docker save "${IMAGE}:${TAG}" -o "${tarball}"

for vm in $(multipass list --format json | jq -r '.list[] | select(.name | startswith("k8s-")) | .name'); do
  echo "Loading into ${vm}..."
  multipass transfer "${tarball}" "${vm}:/tmp/notes-api.tar"
  multipass exec "${vm}" -- sudo ctr -n k8s.io images import /tmp/notes-api.tar
  multipass exec "${vm}" -- rm -f /tmp/notes-api.tar
done

echo
echo "Deploy with:"
echo "  IMAGE_REPOSITORY=${IMAGE} IMAGE_TAG=${TAG} KUBECONFIG=artifacts/admin.conf make deploy"