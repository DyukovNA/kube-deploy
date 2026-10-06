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
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_dir="$PROJECT_ROOT/build/evidence"
evidence_file="$evidence_dir/e2e-$timestamp-$revision.log"
junit_file="$evidence_dir/e2e-$timestamp-$revision.xml"
mkdir -p "$evidence_dir"
started_at="$SECONDS"

exec > >(tee "$evidence_file") 2>&1

finalize() {
  local exit_code=$?
  local elapsed=$((SECONDS - started_at))
  trap - EXIT
  if ((exit_code == 0)); then
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="kubedeploy-e2e" tests="1" failures="0" time="%s"><testcase name="bootstrap-deploy-policy-self-heal" time="%s"/></testsuite>\n' \
      "$elapsed" "$elapsed" >"$junit_file"
    printf 'E2E passed in %ss\nEvidence: %s\nJUnit: %s\n' "$elapsed" "$evidence_file" "$junit_file"
  else
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="kubedeploy-e2e" tests="1" failures="1" time="%s"><testcase name="bootstrap-deploy-policy-self-heal" time="%s"><failure message="e2e command failed with exit code %s"/></testcase></testsuite>\n' \
      "$elapsed" "$elapsed" "$exit_code" >"$junit_file"
    printf 'E2E failed in %ss with exit code %s\nEvidence: %s\nJUnit: %s\n' \
      "$elapsed" "$exit_code" "$evidence_file" "$junit_file" >&2
  fi
  exit "$exit_code"
}
trap finalize EXIT

printf 'KubeDeploy e2e start: timestamp=%s revision=%s\n' "$timestamp" "$revision"
bash "$PROJECT_ROOT/scripts/cluster-up.sh"
bash "$PROJECT_ROOT/scripts/bootstrap.sh"
IMAGE_TAG="$image_tag" bash "$PROJECT_ROOT/scripts/deploy.sh"
bash "$PROJECT_ROOT/scripts/demo-policy-denial.sh"
bash "$PROJECT_ROOT/scripts/demo-self-heal.sh"
