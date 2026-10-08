# KubeDeploy Platform

Локальная учебная платформа декларативного развёртывания в Kubernetes. Git и Argo CD управляют системным слоем, Score генерирует ресурсы frontend/backend, Helm развёртывает PostgreSQL, а Gatekeeper блокирует небезопасные workload.

Рабочий контур проверен 7 октября 2026 года, в том числе полным прогоном с созданием чистого кластера: CI и Release завершены успешно, образы опубликованы в GHCR с SBOM/provenance/attestations, все Argo CD Application находятся в `Synced/Healthy`, приложение доступно через Envoy Gateway, smoke пишет и читает данные PostgreSQL, Gatekeeper отклоняет три класса нарушений, а Argo CD устраняет контролируемый drift.

## Архитектура

```text
GitHub repository
├── platform/ ── Argo CD ── Kustomize/Helm ── Envoy Gateway + Gatekeeper
└── apps/ + Score ── GitHub Actions ── GHCR ── local make deploy ── k3d
                                                       ├── frontend
                                                       ├── backend
                                                       └── PostgreSQL (Helm/PVC)
```

Argo CD синхронизирует только системные компоненты. Пользовательские workload генерируются `score-k8s`, проходят schema/policy/admission-проверки и применяются локальным CD. Kubeconfig и секреты не передаются в GitHub.

Подробности: [архитектура](docs/architecture.md), [CI/CD](docs/ci-cd.md), [безопасность](docs/security.md), [матрица версий](docs/version-matrix.md).

## Быстрый запуск

Нужны Docker Desktop и авторизованный GitHub CLI. Закреплённые CLI уже устанавливаются в `.tools/bin`; проверить окружение:

```sh
make doctor
gh auth status
gh auth token | docker login ghcr.io -u DyukovNA --password-stdin
```

Поднять или возобновить локальный контур и развернуть текущий опубликованный SHA:

```sh
make cluster-up
make bootstrap
SHA="$(git rev-parse HEAD)"
make deploy IMAGE_TAG="sha-$SHA"
```

`make deploy` допускает только чистый checkout текущего commit из `origin/main`, проверяет digest и GitHub attestation обоих образов, восстанавливает Score state, обновляет PostgreSQL, валидирует/применяет манифесты и выполняет smoke.

Полный повторяемый прогон с локальным evidence log и JUnit XML:

```sh
make e2e IMAGE_TAG="sha-$(git rev-parse HEAD)"
```

Артефакты прогона записываются в игнорируемый каталог `build/evidence/`; значения Secret, kubeconfig и токены туда не попадают.

## Проверки

```sh
make test lint
make test-backend-integration
make test-backend-container
make demo-policy
make demo-drift
make smoke REVISION="$(git rev-parse HEAD)"
```

- `demo-policy` доказывает server-side admission denial для privileged-контейнера, `latest` и отсутствующих requests/limits.
- `demo-drift` безопасно меняет replica count Envoy Gateway с 1 на 2 и ждёт, пока Argo CD вернёт Git-state.
- `cluster-down` удаляет только кластер `kube-deploy` и отказывается работать при другом current context.

Пошаговый сценарий защиты находится в [docs/demo-scenario.md](docs/demo-scenario.md), фактический прогон — в [evidence за 2026-10-07](docs/evidence/2026-10-07-e2e.md), устранение типовых сбоев — в [docs/troubleshooting.md](docs/troubleshooting.md).

## Статус требований

- [x] k3d/K3s и воспроизводимый lifecycle
- [x] Kustomize + Argo CD для системного слоя
- [x] Envoy Gateway и Gateway API
- [x] Score-generated frontend/backend без ручных Deployment/Service
- [x] PostgreSQL через Helm с сохраняемым PVC
- [x] Gatekeeper: privileged, resources, image tags
- [x] GitHub Actions CI, Trivy, GHCR, SBOM/provenance/attestations
- [x] Локальный CD с проверкой SHA, digest и provenance
- [x] Smoke, admission denial и Argo self-heal
- [x] Автоматизированный e2e и evidence/JUnit output

Осознанно не входят в MVP: cloud/Terraform, production HA, service mesh, Cilium, observability stack, secrets operator и автоматический доступ GitHub runner к локальному kubeconfig.
