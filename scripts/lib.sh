#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$PROJECT_ROOT/.tools/bin:$PATH"
# shellcheck source=versions.env
source "$PROJECT_ROOT/scripts/versions.env"

retry_command() {
  local description="$1"
  shift
  local attempt
  for attempt in 1 2 3 4 5; do
    if "$@"; then
      return 0
    fi
    if ((attempt < 5)); then
      printf '%s failed (attempt %d/5); retrying in 5s\n' "$description" "$attempt" >&2
      sleep 5
    fi
  done
  printf '%s failed after 5 attempts\n' "$description" >&2
  return 1
}

retry_capture() {
  local description="$1"
  shift
  local attempt output
  for attempt in 1 2 3 4 5; do
    if output="$("$@")"; then
      printf '%s\n' "$output"
      return 0
    fi
    if ((attempt < 5)); then
      printf '%s failed (attempt %d/5); retrying in 5s\n' "$description" "$attempt" >&2
      sleep 5
    fi
  done
  printf '%s failed after 5 attempts\n' "$description" >&2
  return 1
}

require_context() {
  local current
  current="$(kubectl config current-context)"
  if [[ "$current" != k3d-kube-deploy ]]; then
    printf 'Refusing to modify cluster: current context is %s, expected k3d-kube-deploy\n' "$current" >&2
    exit 1
  fi
}
