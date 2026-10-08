#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_context
base=http://kube-deploy.local:8080
curl_args=(--noproxy '*' --resolve kube-deploy.local:8080:127.0.0.1 --fail-with-body --silent --show-error --max-time 10)
# Deployment readiness can precede Envoy receiving the new EndpointSlice by a
# few seconds. Retry only idempotent reads; the message POST must run once.
read_retry_args=(--retry 12 --retry-all-errors --retry-delay 1 --retry-max-time 30)

page="$(curl "${curl_args[@]}" "${read_retry_args[@]}" "$base/")"
if [[ "$page" != *'class="initial-shell"'* || "$page" != *'window.__reactRouterContext'* ]]; then
  printf 'Frontend page did not contain the expected React Router SPA shell\n' >&2
  exit 1
fi
curl "${curl_args[@]}" "${read_retry_args[@]}" "$base/api/health/ready" | jq -e '.status == "ok"' >/dev/null
version="$(curl "${curl_args[@]}" "${read_retry_args[@]}" "$base/api/version")"
if [[ -n "${REVISION:-}" ]]; then
  jq -e --arg commit "$REVISION" '.commit == $commit' <<<"$version" >/dev/null
fi

probe="smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$"
created="$(curl "${curl_args[@]}" -X POST -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg text "$probe" '{text:$text}')" "$base/api/messages")"
message_id="$(jq -er --arg text "$probe" 'select(.text == $text) | .id' <<<"$created")"
curl "${curl_args[@]}" "${read_retry_args[@]}" "$base/api/messages" |
  jq -e --argjson id "$message_id" --arg text "$probe" \
    'any(.[]; .id == $id and .text == $text)' >/dev/null
printf 'Smoke passed: frontend, readiness, version %s, message id %s\n' \
  "$(jq -r .version <<<"$version")" "$message_id"
