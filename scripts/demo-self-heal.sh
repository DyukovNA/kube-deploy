#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
application=kube-deploy-envoy-gateway
namespace=envoy-gateway-system
deployment=envoy-gateway

kubectl --context k3d-kube-deploy -n argocd get "application/$application" -o json |
  jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null

original_replicas="$(kubectl --context k3d-kube-deploy -n "$namespace" \
  get "deployment/$deployment" -o jsonpath='{.spec.replicas}')"
[[ "$original_replicas" =~ ^[0-9]+$ ]] || {
  printf 'Unexpected replica count: %s\n' "$original_replicas" >&2
  exit 1
}
drifted_replicas=$((original_replicas + 1))

cleanup() {
  local current
  current="$(kubectl --context k3d-kube-deploy -n "$namespace" \
    get "deployment/$deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  if [[ -n "$current" && "$current" != "$original_replicas" ]]; then
    kubectl --context k3d-kube-deploy -n "$namespace" scale \
      "deployment/$deployment" --replicas="$original_replicas" >/dev/null || true
  fi
}
trap cleanup EXIT

kubectl --context k3d-kube-deploy -n "$namespace" scale \
  "deployment/$deployment" --replicas="$drifted_replicas" >/dev/null
printf 'Introduced safe drift: %s replicas %s -> %s\n' \
  "$deployment" "$original_replicas" "$drifted_replicas"

healed=false
for _ in {1..90}; do
  current="$(kubectl --context k3d-kube-deploy -n "$namespace" \
    get "deployment/$deployment" -o jsonpath='{.spec.replicas}')"
  if [[ "$current" == "$original_replicas" ]]; then
    healed=true
    break
  fi
  sleep 2
done
[[ "$healed" == true ]] || {
  printf 'Argo CD did not restore %s replicas to %s\n' "$deployment" "$original_replicas" >&2
  exit 1
}

kubectl --context k3d-kube-deploy -n argocd get "application/$application" -o json |
  jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null
kubectl --context k3d-kube-deploy -n "$namespace" rollout status \
  "deployment/$deployment" --timeout=180s >/dev/null
printf 'Argo CD self-heal passed: %s replicas restored to %s and application is Synced/Healthy\n' \
  "$deployment" "$original_replicas"
