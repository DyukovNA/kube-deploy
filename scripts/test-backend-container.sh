#!/usr/bin/env bash
set -Eeuo pipefail

network="kubedeploy-backend-smoke-$$"
database_container="kubedeploy-db-smoke-$$"
backend_container="kubedeploy-api-smoke-$$"
cleanup() {
  docker stop "$backend_container" >/dev/null 2>&1 || true
  docker stop "$database_container" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker run --rm --detach --name "$database_container" --network "$network" --network-alias postgres \
  -e POSTGRES_PASSWORD=integration-only -e POSTGRES_DB=kubedeploy_test \
  postgres:17.6-alpine@sha256:ef257d85f76e48da1c64832459b59fcaba1a4dac97bf5d7450c77753542eee94 >/dev/null

for attempt in {1..30}; do
  if docker exec "$database_container" pg_isready -U postgres -d kubedeploy_test >/dev/null 2>&1; then
    break
  fi
  if (( attempt == 30 )); then
    printf '%s\n' 'PostgreSQL did not become ready' >&2
    exit 1
  fi
  sleep 1
done

docker run --rm --detach --name "$backend_container" --network "$network" -p 127.0.0.1::8080 \
  -e DATABASE_URL=postgres://postgres:integration-only@postgres:5432/kubedeploy_test?sslmode=disable \
  -e BUILD_VERSION=sha-smoke -e BUILD_COMMIT=smoke kubedeploy-backend:local >/dev/null
address="$(docker port "$backend_container" 8080/tcp)"
port="${address##*:}"
base_url="http://127.0.0.1:${port}"

for attempt in {1..30}; do
  if curl -fsS --max-time 1 "$base_url/api/health/ready" >/dev/null 2>&1; then
    break
  fi
  if (( attempt == 30 )); then
    docker logs "$backend_container" >&2
    printf '%s\n' 'Backend did not become ready' >&2
    exit 1
  fi
  sleep 1
done

curl -fsS "$base_url/api/health/live" | jq -e '.status == "ok"' >/dev/null
curl -fsS "$base_url/api/version" | jq -e '.version == "sha-smoke" and .commit == "smoke"' >/dev/null
curl -fsS -X POST -H 'Content-Type: application/json' --data '{"text":"container smoke"}' "$base_url/api/messages" | jq -e '.text == "container smoke"' >/dev/null
curl -fsS "$base_url/api/messages" | jq -e '.[0].text == "container smoke"' >/dev/null
printf '%s\n' 'Backend container smoke passed'
