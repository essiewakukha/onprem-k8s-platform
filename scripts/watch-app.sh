#!/usr/bin/env bash
# Hit the app through the ingress every 200ms and print status + which pod
# and node answered. Run it during a rollout or a node-failure drill to see
# (or prove) that no request fails.
#
#   ./scripts/watch-app.sh http://notes.apps.lab.internal
set -Euo pipefail

URL="${1:-http://notes.apps.lab.internal}"
ok=0
failed=0

trap 'printf "\n%d ok, %d failed\n" "${ok}" "${failed}"; exit 0' INT

while true; do
  body="$(curl -s -m 2 -w '\n%{http_code}' "${URL}/" || printf '\n000')"
  code="$(tail -n1 <<<"${body}")"
  json="$(head -n -1 <<<"${body}")"
  if [[ "${code}" == "200" ]]; then
    ok=$((ok + 1))
    printf '%s 200 %s\n' "$(date +%T)" "$(jq -r '"\(.version) pod=\(.pod) node=\(.node)"' <<<"${json}" 2>/dev/null)"
  else
    failed=$((failed + 1))
    printf '%s \033[31m%s\033[0m\n' "$(date +%T)" "${code}"
  fi
  sleep 0.2
done