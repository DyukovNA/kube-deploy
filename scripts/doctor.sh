#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$root_dir/.tools/bin:$PATH"
# shellcheck source=versions.env
source "$root_dir/scripts/versions.env"

mode="${1:-local}"
if [[ "$mode" != local && "$mode" != --ci ]]; then
  printf 'Usage: %s [--ci]\n' "$0" >&2
  exit 2
fi

missing=0
mismatched=0

check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    printf 'OK       %-14s %s\n' "$name" "$(command -v "$name")"
  else
    printf 'MISSING  %-14s\n' "$name"
    ((missing += 1))
  fi
}

check_version() {
  local name="$1" expected="$2" actual="$3"
  if [[ -z "$actual" ]]; then
    return
  fi
  if [[ "$actual" == "$expected" ]]; then
    printf 'VERSION  %-14s %s\n' "$name" "$actual"
  else
    printf 'MISMATCH %-14s expected %s, found %s\n' "$name" "$expected" "$actual"
    ((mismatched += 1))
  fi
}

printf 'KubeDeploy prerequisite report (%s)\n' "$mode"
for tool in git go node npm docker k3d kubectl helm kustomize score-k8s gator kubeconform trivy jq curl gh shellcheck actionlint yamllint; do
  check_command "$tool"
done

if command -v go >/dev/null 2>&1; then
  module_go_version="$(cd "$root_dir/apps/backend" && go version | awk '{ print $3 }' | sed 's/^go//')"
  check_version go "$(awk '$1 == "golang" { print $2 }' "$root_dir/.tool-versions")" "$module_go_version"
fi
if command -v node >/dev/null 2>&1; then
  check_version node "$(awk '$1 == "nodejs" { print $2 }' "$root_dir/.tool-versions")" "$(node --version | sed 's/^v//')"
fi
if command -v k3d >/dev/null 2>&1; then
  check_version k3d "$K3D_VERSION" "$(k3d version | awk 'NR == 1 { sub(/^v/, "", $3); print $3 }')"
fi
if command -v helm >/dev/null 2>&1; then
  check_version helm "$HELM_VERSION" "$(helm version --short | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
fi
if command -v kubectl >/dev/null 2>&1; then
  check_version kubectl "$KUBECTL_VERSION" "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion' | sed 's/^v//')"
fi
if command -v docker >/dev/null 2>&1; then
  if docker info --format '{{.ServerVersion}} {{.MemTotal}}' >/dev/null 2>&1; then
    read -r docker_version docker_memory < <(docker info --format '{{.ServerVersion}} {{.MemTotal}}')
    printf 'DAEMON   docker         %s, %s bytes RAM\n' "$docker_version" "$docker_memory"
  else
    printf 'UNAVAILABLE docker daemon\n'
    ((missing += 1))
  fi
fi

printf 'Summary: %d missing/unavailable, %d version mismatches\n' "$missing" "$mismatched"
if (( missing > 0 || mismatched > 0 )); then
  exit 1
fi
