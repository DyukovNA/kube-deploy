#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for fixture in "$PROJECT_ROOT"/platform/policies/tests/*.yaml; do
  case "$(basename "$fixture")" in
    privileged.yaml|privileged-deployment.yaml) expected=demo-no-privileged ;;
    no-resources.yaml) expected=demo-required-resources ;;
    latest.yaml|no-tag.yaml) expected=demo-image-tags ;;
    *) printf 'Unknown fixture: %s\n' "$fixture" >&2; exit 1 ;;
  esac
  if output="$(gator test \
    -f "$PROJECT_ROOT/platform/clusters/local/namespaces.yaml" \
    -f "$PROJECT_ROOT/platform/policies/templates" \
    -f "$PROJECT_ROOT/platform/policies/constraints" \
    -f "$PROJECT_ROOT/platform/policies/expansion.yaml" \
    -f "$fixture" 2>&1)"; then
    printf 'Expected policy rejection: %s\n' "$fixture" >&2
    exit 1
  fi
  if [[ "$output" != *"[\"$expected\"]"* ]]; then
    printf 'Fixture failed for the wrong reason: %s\n%s\n' "$fixture" "$output" >&2
    exit 1
  fi
  printf 'Rejected: %s\n' "$(basename "$fixture")"
done
