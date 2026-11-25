#!/usr/bin/env bash
# Delete every lab VM created by multipass-up.sh.
set -Eeuo pipefail

vms="$(multipass list --format json | jq -r '.list[] | select(.name | startswith("k8s-")) | .name')"
[[ -z "${vms}" ]] && { echo "No lab VMs found."; exit 0; }

echo "Deleting: ${vms//$'\n'/ }"
# shellcheck disable=SC2086
multipass delete ${vms}
multipass purge
rm -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lab-vars.yml"
echo "Lab removed."