#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if k3d cluster list --no-headers | awk '$1 == "kube-deploy" { found = 1 } END { exit !found }'; then
  if ! kubectl --context k3d-kube-deploy get nodes >/dev/null 2>&1; then
    printf '%s\n' 'Cluster kube-deploy exists but is stopped; starting it'
    docker info >/dev/null
    k3d cluster start kube-deploy
  else
    printf '%s\n' 'Cluster kube-deploy already exists and is running'
  fi
  kubectl --context k3d-kube-deploy wait --for=condition=Ready nodes --all --timeout=180s
  kubectl --context k3d-kube-deploy get nodes -o name
  exit 0
fi

docker info >/dev/null
expected_image_version="${K3S_VERSION/+/-}"
if ! rg -q "rancher/k3s:${expected_image_version}@sha256:" "$PROJECT_ROOT/cluster/k3d.yaml"; then
  printf 'cluster/k3d.yaml image does not match K3S_VERSION=%s\n' "$K3S_VERSION" >&2
  exit 1
fi

for port in 6445 8080 8443; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    printf 'Host TCP port %s is already in use\n' "$port" >&2
    exit 1
  fi
done

k3d cluster create --config "$PROJECT_ROOT/cluster/k3d.yaml"
require_context
kubectl --context k3d-kube-deploy wait --for=condition=Ready nodes --all --timeout=180s
kubectl --context k3d-kube-deploy get nodes -o wide
