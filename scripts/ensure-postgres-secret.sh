#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
namespace=kube-deploy-demo
secret=demo-postgres-credentials

if kubectl --context k3d-kube-deploy -n "$namespace" get secret "$secret" -o name >/dev/null 2>&1; then
  printf '%s\n' 'PostgreSQL credentials already exist; preserving them'
  exit 0
fi

openssl rand -hex 32 | tr -d '\n' | kubectl --context k3d-kube-deploy -n "$namespace" create secret generic "$secret" --from-file=password=/dev/stdin >/dev/null
printf '%s\n' 'Created PostgreSQL credentials in Kubernetes Secret'
