#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
kubectl --context k3d-kube-deploy apply -f "$PROJECT_ROOT/platform/clusters/local/namespaces.yaml"
bash "$PROJECT_ROOT/scripts/ensure-postgres-secret.sh"
helm --kube-context k3d-kube-deploy upgrade --install demo-postgres "$PROJECT_ROOT/apps/postgres-chart" \
  --namespace kube-deploy-demo --values "$PROJECT_ROOT/apps/postgres-chart/values.yaml" \
  --wait --wait-for-jobs --rollback-on-failure --cleanup-on-fail --timeout 5m
helm --kube-context k3d-kube-deploy test demo-postgres --namespace kube-deploy-demo --timeout 2m
