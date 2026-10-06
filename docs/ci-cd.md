# CI/CD

## CI

`.github/workflows/ci.yml` запускается для PR и push в `main`, `feature/**`, `fix/**`. Job имеют только `contents: read` и проверяют:

- Go format/vet/race tests и сборку backend;
- npm lint/typecheck/tests/build/audit frontend;
- Dockerfile build checks, запуск Caddy под `no-new-privileges` и Trivy;
- shellcheck, actionlint, yamllint, Kustomize/Helm/Score/kubeconform/gator;
- агрегирующий обязательный status `ci-success`.

## Release

`.github/workflows/release.yml` запускается только для push в `main`. После повторной верификации два matrix job получают минимальные дополнительные права `packages: write`, `id-token: write`, `attestations: write` и:

1. собирают amd64 candidate;
2. отклоняют исправимые HIGH/CRITICAL через Trivy;
3. публикуют multi-arch `linux/amd64,linux/arm64` image с тегом `sha-<full commit>`;
4. добавляют BuildKit provenance/SBOM;
5. создают GitHub attestation для опубликованного digest;
6. повторно проверяют remote digest и attestation.

## Локальный CD

GitHub-hosted runner не имеет маршрута к локальному k3d. Поэтому deploy выполняется с Mac, а kubeconfig никогда не загружается в GitHub:

```sh
make deploy IMAGE_TAG=sha-<full-main-commit>
```

Deploy fail-closed: требуется чистый текущий commit из `origin/main`, здоровый системный Argo layer, доступный immutable digest и attestation от конкретного release workflow. Применение не начнётся при любой ошибке этих проверок.

`make e2e` дополняет deploy admission- и self-heal-проверками, пишет обезличенный log и JUnit XML в `build/evidence/`.
