#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${FRONTEND_IMAGE:?FRONTEND_IMAGE must be an immutable image digest reference}"
: "${BACKEND_IMAGE:?BACKEND_IMAGE must be an immutable image digest reference}"
: "${REVISION:?REVISION must be the full release commit SHA}"

if [[ ! "$FRONTEND_IMAGE" =~ @sha256:[a-f0-9]{64}$ ]] || [[ ! "$BACKEND_IMAGE" =~ @sha256:[a-f0-9]{64}$ ]]; then
  printf '%s\n' 'Both images must use @sha256 digest references' >&2
  exit 1
fi
if [[ ! "$REVISION" =~ ^[a-f0-9]{40}$ ]]; then
  printf '%s\n' 'REVISION must be a 40-character lowercase Git commit SHA' >&2
  exit 1
fi

output="${SCORE_OUTPUT:-$PROJECT_ROOT/build/manifests.yaml}"
work_dir="$(mktemp -d)"
trap 'rm -r "$work_dir"' EXIT
cd "$work_dir"

if [[ -n "${SCORE_STATE_INPUT:-}" ]]; then
  mkdir -p .score-k8s
  cp "$SCORE_STATE_INPUT" .score-k8s/state.yaml
fi
score-k8s init --no-sample --no-default-provisioners \
  --provisioners "$PROJECT_ROOT/platform/score/provisioners/local.provisioners.yaml" \
  --patch-templates "$PROJECT_ROOT/platform/score/patches/unprivileged.tpl" >/dev/null

score-k8s generate "$PROJECT_ROOT/platform/score/score-frontend.yaml" \
  --image "$FRONTEND_IMAGE" --namespace kube-deploy-demo \
  --override-property "metadata.revision=$REVISION" --output manifests.yaml >/dev/null
score-k8s generate "$PROJECT_ROOT/platform/score/score-backend.yaml" \
  --image "$BACKEND_IMAGE" --namespace kube-deploy-demo \
  --override-property "metadata.revision=$REVISION" --output manifests.yaml >/dev/null

mkdir -p "$(dirname "$output")"
cp manifests.yaml "$output"
if [[ -n "${SCORE_STATE_OUTPUT:-}" ]]; then
  cp .score-k8s/state.yaml "$SCORE_STATE_OUTPUT"
fi
printf 'Rendered Score manifests to %s\n' "$output"
