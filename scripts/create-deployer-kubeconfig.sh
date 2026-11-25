#!/usr/bin/env bash
# Build a kubeconfig for the namespace-scoped ci-deployer ServiceAccount.
# Run with cluster-admin credentials. Output goes to artifacts/ (git-ignored).
#
#   ./scripts/create-deployer-kubeconfig.sh
#   base64 -w0 artifacts/ci-deployer.kubeconfig   # -> GitHub secret KUBECONFIG_B64
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-notes}"
SA="${SA:-ci-deployer}"
SECRET="${SECRET:-ci-deployer-token}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-${REPO_ROOT}/artifacts/ci-deployer.kubeconfig}"

mkdir -p "$(dirname "${OUT}")"

# Wait for the token controller to populate the Secret.
for _ in $(seq 1 30); do
  token="$(kubectl -n "${NAMESPACE}" get secret "${SECRET}" -o jsonpath='{.data.token}' 2>/dev/null || true)"
  [[ -n "${token}" ]] && break
  sleep 1
done
[[ -n "${token:-}" ]] || { echo "Token not populated in secret ${NAMESPACE}/${SECRET}" >&2; exit 1; }

server="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')"
ca="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"

umask 077
cat > "${OUT}" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: k8s-platform
    cluster:
      server: ${server}
      certificate-authority-data: ${ca}
users:
  - name: ${SA}
    user:
      token: $(printf '%s' "${token}" | base64 -d)
contexts:
  - name: ${SA}@k8s-platform
    context:
      cluster: k8s-platform
      user: ${SA}
      namespace: ${NAMESPACE}
current-context: ${SA}@k8s-platform
EOF

echo "Wrote ${OUT}"
echo "Check its permissions are namespace-scoped:"
echo "  KUBECONFIG=${OUT} kubectl auth can-i --list -n ${NAMESPACE}"
echo "  KUBECONFIG=${OUT} kubectl auth can-i get nodes   # expect: no"