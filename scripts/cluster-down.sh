#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! k3d cluster list --no-headers | awk '$1 == "kube-deploy" { found = 1 } END { exit !found }'; then
  printf '%s\n' 'Cluster kube-deploy does not exist'
  exit 0
fi

require_context
k3d cluster delete kube-deploy
printf '%s\n' 'Deleted dedicated cluster kube-deploy'
