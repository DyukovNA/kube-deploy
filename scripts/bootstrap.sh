#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
remote="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"
if [[ ! "$remote" =~ ^https://github\.com/[^/]+/[^/]+\.git$ ]]; then
  printf 'Bootstrap requires a public HTTPS GitHub origin ending in .git\n' >&2
  exit 1
fi
github_repo="${remote#https://github.com/}"
github_repo="${github_repo%.git}"
visibility="$(retry_capture 'GitHub repository visibility lookup' \
  gh repo view "$github_repo" --json visibility --jq .visibility)"
if [[ "$visibility" != PUBLIC ]]; then
  printf 'Private Git remotes need explicit Argo CD repository credentials; bootstrap stopped\n' >&2
  exit 1
fi
repo_url="$(sed -n 's/^  url: //p' "$PROJECT_ROOT/platform/clusters/local/repository.yaml")"
root_url="$(sed -n 's/^    repoURL: //p' "$PROJECT_ROOT/platform/bootstrap/root-application.yaml")"
if [[ "$repo_url" != "$remote" || "$root_url" != "$remote" ]]; then
  printf 'Repository URLs in platform configuration must match origin: %s\n' "$remote" >&2
  exit 1
fi
test -z "$(git -C "$PROJECT_ROOT" status --porcelain)" || {
  printf 'Commit local changes before bootstrap\n' >&2; exit 1;
}
remote_ref="$(retry_capture 'origin/main lookup' git ls-remote "$remote" refs/heads/main)"
remote_head="$(awk '{print $1}' <<<"$remote_ref")"
test -n "$remote_head" && test "$remote_head" = "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" || {
  printf 'Push the current commit to origin/main before bootstrap\n' >&2; exit 1;
}

bash "$PROJECT_ROOT/scripts/argocd-up.sh"
kubectl --context k3d-kube-deploy apply --server-side --field-manager=kubedeploy-bootstrap \
  -f "$PROJECT_ROOT/platform/bootstrap/root-application.yaml"
for app in kube-deploy-root kube-deploy-envoy-crds kube-deploy-envoy-gateway kube-deploy-gatekeeper kube-deploy-gateway kube-deploy-policies; do
  ready=false
  for _ in {1..180}; do
    if kubectl --context k3d-kube-deploy -n argocd get "application/$app" -o json 2>/dev/null |
      jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 5
  done
  test "$ready" = true || { printf 'Argo application %s did not become Synced/Healthy\n' "$app" >&2; exit 1; }
  printf 'Synced/Healthy: %s\n' "$app"
done
kubectl --context k3d-kube-deploy -n gatekeeper-system rollout status deployment/gatekeeper-controller-manager --timeout=300s
kubectl --context k3d-kube-deploy -n envoy-gateway-system rollout status deployment/envoy-gateway --timeout=300s
printf 'System layer is ready\n'
