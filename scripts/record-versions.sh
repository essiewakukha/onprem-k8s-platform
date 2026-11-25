#!/usr/bin/env bash
# Capture the exact versions running in the cluster (including patch levels
# that apt globs resolved to) so a rebuild can match them exactly.
#
#   ./scripts/record-versions.sh > VERSIONS.lock.md
set -Eeuo pipefail

echo "# Resolved versions ($(date -u +%Y-%m-%dT%H:%MZ))"
echo
echo "## Nodes"
echo
echo "| Node | kubelet | Container runtime | OS | Kernel |"
echo "|---|---|---|---|---|"
kubectl get nodes -o json | jq -r '.items[] |
  "| \(.metadata.name) | \(.status.nodeInfo.kubeletVersion) | \(.status.nodeInfo.containerRuntimeVersion) | \(.status.nodeInfo.osImage) | \(.status.nodeInfo.kernelVersion) |"'
echo
echo "## Control plane images"
echo
kubectl -n kube-system get pods -l tier=control-plane -o json \
  | jq -r '[.items[].spec.containers[].image] | unique[] | "- `\(.)`"'
echo
echo "## Helm releases"
echo
echo "| Release | Namespace | Chart | App version |"
echo "|---|---|---|---|"
helm list -A -o json | jq -r '.[] | "| \(.name) | \(.namespace) | \(.chart) | \(.app_version) |"'
echo
echo "## Tooling on this machine"
echo
echo "- kubectl: $(kubectl version --client -o json | jq -r .clientVersion.gitVersion)"
echo "- helm: $(helm version --short)"
command -v ansible >/dev/null && echo "- ansible-core: $(ansible --version | head -1 | sed 's/.*core //; s/]//')"