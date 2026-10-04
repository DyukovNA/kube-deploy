#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
container_id=""
cleanup() {
  if [[ -n "$container_id" ]]; then
    docker stop "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

container_id="$(docker run --rm --detach --name "kubedeploy-postgres-test-$$" -e POSTGRES_PASSWORD=integration-only -e POSTGRES_DB=kubedeploy_test -p 127.0.0.1::5432 postgres:17.6-alpine@sha256:ef257d85f76e48da1c64832459b59fcaba1a4dac97bf5d7450c77753542eee94)"
address="$(docker port "$container_id" 5432/tcp)"
port="${address##*:}"
database_url="postgres://postgres:integration-only@127.0.0.1:${port}/kubedeploy_test?sslmode=disable"

for attempt in {1..30}; do
  if docker exec "$container_id" pg_isready -U postgres -d kubedeploy_test >/dev/null 2>&1; then
    break
  fi
  if (( attempt == 30 )); then
    printf '%s\n' 'PostgreSQL did not become ready in 30 seconds' >&2
    exit 1
  fi
  sleep 1
done

cd "$root_dir/apps/backend"
TEST_DATABASE_URL="$database_url" go test -race ./internal/store -run '^TestPostgresIntegration$' -count=1
