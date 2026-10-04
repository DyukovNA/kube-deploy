#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
kubectl --context k3d-kube-deploy create namespace argocd --dry-run=client -o yaml | kubectl --context k3d-kube-deploy apply -f -
kubectl --context k3d-kube-deploy apply -k "$PROJECT_ROOT/platform/bootstrap/argocd" --server-side --field-manager=kubedeploy-bootstrap
for workload in argocd-redis argocd-repo-server argocd-server argocd-applicationset-controller argocd-notifications-controller; do
  kubectl --context k3d-kube-deploy -n argocd rollout status "deployment/$workload" --timeout=300s
done
kubectl --context k3d-kube-deploy -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
printf 'Argo CD controller installed; root Application requires a reachable Git remote\n'
