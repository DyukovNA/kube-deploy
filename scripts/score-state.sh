#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
operation="${1:-}"
target="${2:-}"
test -n "$target" || { printf 'Usage: score-state.sh restore|persist FILE\n' >&2; exit 2; }
namespace=kube-deploy-demo
secret=score-k8s-state

case "$operation" in
  restore)
    if kubectl --context k3d-kube-deploy -n "$namespace" get secret "$secret" -o name >/dev/null 2>&1; then
      umask 077
      kubectl --context k3d-kube-deploy -n "$namespace" get secret "$secret" -o jsonpath='{.data.state\.yaml}' | base64 -D > "$target"
      test -s "$target" || { printf 'Stored Score state is empty\n' >&2; exit 1; }
      printf 'Restored Score state to %s\n' "$target"
    else
      printf 'No prior Score state; first deployment\n'
    fi
    ;;
  persist)
    test -s "$target" || { printf 'Refusing to persist empty Score state\n' >&2; exit 1; }
    kubectl --context k3d-kube-deploy -n "$namespace" create secret generic "$secret" \
      --from-file="state.yaml=$target" --dry-run=client -o yaml |
      kubectl --context k3d-kube-deploy -n "$namespace" apply --server-side \
        --field-manager=kubedeploy-score-state -f - >/dev/null
    printf 'Persisted Score state in %s/%s\n' "$namespace" "$secret"
    ;;
  *) printf 'Usage: score-state.sh restore|persist FILE\n' >&2; exit 2 ;;
esac
