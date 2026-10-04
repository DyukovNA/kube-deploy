#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

manifest="${1:-$PROJECT_ROOT/build/manifests.yaml}"
test -s "$manifest" || { printf 'Missing generated manifest: %s\n' "$manifest" >&2; exit 1; }

# Kubernetes built-ins are schema-checked here. Gateway API CRDs are validated
# by the cluster API server during the local deploy; kubeconform skips them.
kubeconform -strict -summary -ignore-missing-schemas "$manifest"
gator test \
  -f "$PROJECT_ROOT/platform/clusters/local/namespaces.yaml" \
  -f "$PROJECT_ROOT/platform/policies/templates" \
  -f "$PROJECT_ROOT/platform/policies/constraints" \
  -f "$PROJECT_ROOT/platform/policies/expansion.yaml" \
  -f "$manifest"
printf 'Generated manifest passes schema and policy checks\n'
