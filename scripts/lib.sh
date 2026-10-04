#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$PROJECT_ROOT/.tools/bin:$PATH"
# shellcheck source=versions.env
source "$PROJECT_ROOT/scripts/versions.env"

require_context() {
  local current
  current="$(kubectl config current-context)"
  if [[ "$current" != k3d-kube-deploy ]]; then
    printf 'Refusing to modify cluster: current context is %s, expected k3d-kube-deploy\n' "$current" >&2
    exit 1
  fi
}
