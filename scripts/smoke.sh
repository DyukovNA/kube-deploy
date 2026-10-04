#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
base=http://kube-deploy.local:8080
curl_args=(--noproxy '*' --resolve kube-deploy.local:8080:127.0.0.1 --fail-with-body --silent --show-error --max-time 10)

page="$(curl "${curl_args[@]}" "$base/")"
if [[ "$page" != *'KubeDeploy'* ]]; then
  printf 'Frontend page did not contain the expected title\n' >&2
  exit 1
fi
curl "${curl_args[@]}" "$base/api/health/ready" | jq -e '.status == "ok"' >/dev/null
version="$(curl "${curl_args[@]}" "$base/api/version")"
if [[ -n "${REVISION:-}" ]]; then
  jq -e --arg commit "$REVISION" '.commit == $commit' <<<"$version" >/dev/null
fi

probe="smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$"
created="$(curl "${curl_args[@]}" -X POST -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg text "$probe" '{text:$text}')" "$base/api/messages")"
message_id="$(jq -er --arg text "$probe" 'select(.text == $text) | .id' <<<"$created")"
curl "${curl_args[@]}" "$base/api/messages" |
  jq -e --argjson id "$message_id" --arg text "$probe" \
    'any(.[]; .id == $id and .text == $text)' >/dev/null
printf 'Smoke passed: frontend, readiness, version %s, message id %s\n' \
  "$(jq -r .version <<<"$version")" "$message_id"
