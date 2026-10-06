#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
kubectl --context k3d-kube-deploy -n gatekeeper-system rollout status \
  deployment/gatekeeper-controller-manager --timeout=180s >/dev/null

fixtures=(privileged-deployment.yaml latest.yaml no-resources.yaml)
for fixture in "${fixtures[@]}"; do
  set +e
  output="$(kubectl --context k3d-kube-deploy apply --dry-run=server \
    -f "$PROJECT_ROOT/platform/policies/tests/$fixture" 2>&1)"
  exit_code=$?
  set -e

  if ((exit_code == 0)); then
    printf 'Gatekeeper unexpectedly accepted %s\n' "$fixture" >&2
    exit 1
  fi
  if [[ "$output" != *'admission webhook "validation.gatekeeper.sh" denied the request'* ]]; then
    printf 'Expected a Gatekeeper admission denial for %s, got:\n%s\n' "$fixture" "$output" >&2
    exit 1
  fi
  printf 'Admission rejected as expected: %s\n' "$fixture"
done

printf 'Gatekeeper admission demo passed: %s fixtures rejected\n' "${#fixtures[@]}"
