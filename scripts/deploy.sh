#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

image_tag="${IMAGE_TAG:-}"
if [[ ! "$image_tag" =~ ^sha-([a-f0-9]{40})$ ]]; then
  printf 'IMAGE_TAG must be sha- followed by the full lowercase commit SHA\n' >&2
  exit 2
fi
revision="${BASH_REMATCH[1]}"

remote="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"
if [[ "$remote" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo_name="${BASH_REMATCH[2]%.git}"
elif [[ "$remote" =~ ^git@github\.com:([^/]+)/([^/]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo_name="${BASH_REMATCH[2]%.git}"
else
  printf 'Configure a GitHub origin remote before release deployment\n' >&2
  exit 1
fi
repository="$owner/$repo_name"
gh repo view "$repository" --json nameWithOwner --jq .nameWithOwner >/dev/null
test "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" = "$revision" || {
  printf 'Checked-out HEAD must match IMAGE_TAG commit\n' >&2; exit 1;
}
test -z "$(git -C "$PROJECT_ROOT" status --porcelain)" || {
  printf 'Working tree must be clean for a reproducible deploy\n' >&2; exit 1;
}
git -C "$PROJECT_ROOT" fetch --quiet origin main
git -C "$PROJECT_ROOT" merge-base --is-ancestor "$revision" origin/main || {
  printf 'Release commit is not in origin/main\n' >&2; exit 1;
}
require_context

lock_dir="$PROJECT_ROOT/.deploy-lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  printf 'Another deploy is active, or %s is stale\n' "$lock_dir" >&2
  exit 1
fi
work_dir="$(mktemp -d)"
trap 'rmdir "$lock_dir"; rm -r "$work_dir"' EXIT

for app in kube-deploy-envoy-crds kube-deploy-envoy-gateway kube-deploy-gatekeeper kube-deploy-gateway kube-deploy-policies; do
  kubectl --context k3d-kube-deploy -n argocd get "application/$app" -o json |
    jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null || {
      printf 'Argo CD application %s is not Synced/Healthy\n' "$app" >&2; exit 1;
    }
done

inspect_digest_with_retry() {
  local tag_ref="$1"
  local attempt digest
  for attempt in 1 2 3 4 5; do
    if digest="$(docker buildx imagetools inspect "$tag_ref" --format '{{json .}}' |
      jq -er '.manifest.digest')" && [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
      printf '%s\n' "$digest"
      return 0
    fi
    if ((attempt < 5)); then
      printf 'Digest lookup for %s failed (attempt %d/5); retrying in 5s\n' \
        "$tag_ref" "$attempt" >&2
      sleep 5
    fi
  done
  printf 'Failed to resolve a valid manifest digest for %s after 5 attempts\n' "$tag_ref" >&2
  return 1
}

verify_attestation_with_retry() {
  local digest_ref="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    if gh attestation verify "oci://$digest_ref" --repo "$repository" \
      --source-digest "$revision" --source-ref refs/heads/main \
      --signer-workflow "$repository/.github/workflows/release.yml" >/dev/null; then
      return 0
    fi
    if ((attempt < 5)); then
      printf 'Attestation verification for %s failed (attempt %d/5); retrying in 5s\n' \
        "$digest_ref" "$attempt" >&2
      sleep 5
    fi
  done
  printf 'Attestation verification failed for %s after 5 attempts\n' "$digest_ref" >&2
  return 1
}

image_base="ghcr.io/${repository,,}"
frontend_image=''
backend_image=''
for component in frontend backend; do
  tag_ref="$image_base-$component:$image_tag"
  digest="$(inspect_digest_with_retry "$tag_ref")"
  digest_ref="$image_base-$component@$digest"
  verify_attestation_with_retry "$digest_ref"
  case "$component" in
    frontend) frontend_image="$digest_ref" ;;
    backend) backend_image="$digest_ref" ;;
  esac
  printf 'Verified %s image: %s\n' "$component" "$digest_ref"
done

bash "$PROJECT_ROOT/scripts/score-state.sh" restore "$work_dir/old-state.yaml"
bash "$PROJECT_ROOT/scripts/database-up.sh"
state_input=()
if [[ -s "$work_dir/old-state.yaml" ]]; then
  state_input=(SCORE_STATE_INPUT="$work_dir/old-state.yaml")
fi
env FRONTEND_IMAGE="$frontend_image" BACKEND_IMAGE="$backend_image" REVISION="$revision" \
  SCORE_OUTPUT="$work_dir/manifests.yaml" SCORE_STATE_OUTPUT="$work_dir/new-state.yaml" \
  "${state_input[@]}" bash "$PROJECT_ROOT/scripts/render-score.sh"
bash "$PROJECT_ROOT/scripts/validate-generated.sh" "$work_dir/manifests.yaml"
kubectl --context k3d-kube-deploy apply --dry-run=server -f "$work_dir/manifests.yaml" >/dev/null
kubectl --context k3d-kube-deploy apply --server-side --field-manager=kubedeploy-score \
  -f "$work_dir/manifests.yaml"
bash "$PROJECT_ROOT/scripts/score-state.sh" persist "$work_dir/new-state.yaml"

for workload in frontend backend; do
  kubectl --context k3d-kube-deploy -n kube-deploy-demo rollout status \
    "deployment/$workload" --timeout=300s
done
kubectl --context k3d-kube-deploy -n kube-deploy-system wait --for=condition=Programmed \
  gateway/kube-deploy --timeout=180s
routes_ready=false
for _ in {1..60}; do
  if kubectl --context k3d-kube-deploy -n kube-deploy-demo get httproutes -o json |
    jq -e '(.items | length) == 2 and all(.items[];
      any(.status.parents[]?.conditions[]?; .type == "Accepted" and .status == "True") and
      any(.status.parents[]?.conditions[]?; .type == "ResolvedRefs" and .status == "True"))' >/dev/null; then
    routes_ready=true
    break
  fi
  sleep 2
done
test "$routes_ready" = true || { printf 'HTTPRoutes did not become Accepted/ResolvedRefs\n' >&2; exit 1; }
REVISION="$revision" bash "$PROJECT_ROOT/scripts/smoke.sh"
printf 'Deployed %s at http://kube-deploy.local:8080/\n' "$image_tag"
