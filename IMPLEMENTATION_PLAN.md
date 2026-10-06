# KubeDeploy Platform — план реализации

Статус: MVP реализован; фактические проверки и оставшиеся ограничения отражены в README и `docs/demo-scenario.md`

Исходное задание: `тема.pdf`

Цель: локальная платформа декларативного развёртывания приложений в Kubernetes с Git как источником конфигурации, GitOps для системного слоя и Score-based CD для пользовательского слоя.

## 1. Границы проекта

### 1.1. Что должно войти в итоговый MVP

- Локальный Kubernetes-кластер k3d (K3s в Docker).
- Воспроизводимое создание и удаление кластера одной командой.
- Argo CD, установленный bootstrap-скриптом и далее управляющий системным слоем.
- Kustomize-структура системной конфигурации.
- Envoy Gateway и OPA Gatekeeper как системные приложения Argo CD; маршрутизация описывается через Kubernetes Gateway API.
- Три Gatekeeper-политики:
  - запрет privileged-контейнеров;
  - обязательные CPU/memory requests и limits;
  - запрет изменяемого тега `latest` и образов без тега/digest.
- Демонстрационное приложение:
  - frontend на React 19 + TypeScript, React Router Framework Mode, Tailwind CSS 4 и shadcn/ui;
  - backend на Go;
  - PostgreSQL как StatefulSet, развёрнутый локальным Helm-чартом.
- Два Score workload-файла: frontend и backend.
- Кастомные `score-k8s` provisioners для локального DNS, Gateway API route и уже установленного PostgreSQL.
- Автоматическая генерация Kubernetes-ресурсов из Score без ручных Deployment/Service/Ingress для frontend и backend.
- CI в GitHub Actions: тесты, линтеры, сборка, проверка манифестов и политик.
- Release pipeline: сборка контейнеров, Trivy, публикация в GHCR по неизменяемому SHA-тегу.
- Локальный CD командой `make deploy` на Mac с k3d; отдельный self-hosted runner не требуется.
- Сквозные проверки: первоначальный deploy, обновление версии, блокировка плохой конфигурации, сохранение данных PostgreSQL и self-heal системного компонента через Argo CD.
- Документация и воспроизводимый демонстрационный сценарий для защиты.

### 1.2. Что сознательно не входит

- Облачный Kubernetes и Terraform.
- Несколько кластеров, production HA и disaster recovery.
- Собственная UI-панель управления платформой.
- Service mesh, Prometheus/Grafana, Vault, External Secrets, cert-manager.
- Автоматическое продвижение между dev/stage/prod.
- Полноценный multi-tenant RBAC.
- Argo CD для пользовательских workload. По теме Argo CD синхронизирует только системную часть.
- Database operator. Для курсовой Helm-чарта и StatefulSet достаточно.

Эти ограничения необходимо сохранить, чтобы проект был завершённым, а не широким, но недоделанным прототипом.

### 1.3. Трассировка требований темы

| Требование из темы | Реализация | Доказательство |
|---|---|---|
| Docker | multi-stage non-root images frontend/backend | CI build, runtime UID, Trivy report |
| Kubernetes | локальный k3d/K3s и namespace приложения | `make e2e`, состояние pods |
| Kustomize | bootstrap и системные overlays | `kustomize build`, Argo source path |
| Argo CD | системный GitOps-контур | Synced/Healthy и self-heal demo |
| Score / score-k8s | декларации frontend/backend | сгенерированный manifest, отсутствие ручных workload manifests |
| Helm | PostgreSQL и готовые системные charts | Helm release/status/lint/test |
| Gateway API | современная маршрутизация без устаревающего ingress-контроллера | Gateway/HTTPRoute conditions и HTTP e2e |
| OPA Gatekeeper | три обязательные политики | gator suites и admission denial |
| GitHub Actions | CI, release и публикация проверенных образов | успешные workflow runs |
| Локальный CD | `make deploy` применяет проверенный SHA release в k3d | повторяемый deploy и smoke test |
| GHCR | immutable frontend/backend images | package refs и digests |
| Trivy | vulnerability gate перед release | report и намеренно блокирующий threshold |
| Развёртывание | полный clean-cluster e2e | smoke test |
| Обновление версии | rollout на новый commit SHA | `/api/version` и сохранённые данные |
| Блокировка ошибки | shift-left + admission | три отрицательных fixtures |
| Восстановление системного состояния | Argo CD self-heal | обратимый drift demo |

## 2. Зафиксированные архитектурные решения

### 2.1. Два независимых контура доставки

```text
                         GitHub repository
                        /                 \
               platform config          application source + Score
                      |                            |
                 Argo CD poll                  GitHub Actions
                      |                    test -> build -> scan
                      |                            |
              Kustomize / Helm                    GHCR
                      |                            |
          Envoy Gateway, Gatekeeper       GHCR + attestations
                      |                            |
                      +-------- k3d <--- Mac: make deploy
                                     score-k8s -> gator -> apply
```

Системный контур:

1. В Git хранятся root Application, дочерние Argo CD Applications, Kustomize overlays и Gatekeeper policies.
2. Argo CD синхронизирует только системные namespaces и компоненты.
3. Для child Applications включаются `automated.prune=true` и `automated.selfHeal=true`; `allowEmpty` остаётся выключен.
4. Изменение живого системного ресурса вручную должно автоматически откатываться к состоянию из Git.

Пользовательский контур:

1. Разработчик меняет код и/или `score-*.yaml`.
2. CI тестирует код и декларации.
3. Release workflow создаёт образы с тегом `sha-<full commit sha>`, проверяет Trivy и публикует в GHCR.
4. На Mac после успешного release разработчик запускает `make deploy IMAGE_TAG=sha-...`; команда генерирует манифесты через `score-k8s`.
5. До применения выполняются schema validation и локальная проверка Gatekeeper-политик через `gator`.
6. Только прошедшие проверки ресурсы применяются в namespace `kube-deploy-demo`.

### 2.2. Локальный CD без отдельного runner

GitHub-hosted runner по умолчанию не имеет маршрута к Kubernetes API локального k3d-кластера. Для учебного single-machine MVP выбран локальный deploy:

- CI, Trivy, release и публикация GHCR выполняются на GitHub-hosted runner;
- `make deploy` запускается вручную на том же Mac, где работает k3d, после успешного release из защищённой ветки `main`;
- команда проверяет точный SHA, digest образов и GitHub attestations до применения ресурсов;
- kubeconfig остаётся только на Mac и никогда не передаётся в GitHub Secrets;
- `make deploy` сериализует локальные запуски, а временное состояние Score удаляет после завершения.

Автоматический deploy непосредственно по событию GitHub в MVP не входит. Это явное ограничение; при необходимости позже можно добавить runner как отдельное расширение, не меняя локальный deploy-скрипт.

### 2.3. Источник истины и генерируемые файлы

В Git хранятся:

- исходный код;
- Dockerfile;
- Score workload-файлы;
- Score provisioners и patch templates;
- Helm chart PostgreSQL;
- Kustomize overlays;
- Argo CD Applications;
- ConstraintTemplates, Constraints и их тесты;
- scripts, Makefile, workflows и документация.

В Git не хранятся:

- `.score-k8s/state.yaml`;
- сгенерированный `manifests.yaml`;
- kubeconfig;
- пароли PostgreSQL;
- GitHub tokens;
- Trivy cache и отчёты сборок.

`score-k8s` запускается во временной рабочей директории, но его state переносится между deploy-запусками: `.score-k8s/state.yaml` восстанавливается из Kubernetes Secret `score-k8s-state` в namespace приложения и после успешного deploy сохраняется обратно. Он не попадает в Git, artifacts или logs. Deploy jobs сериализованы, а K3s datastore шифрует Secrets at rest.

### 2.4. Работа с версиями

- Никаких `latest`, `main`, `master` и плавающих chart versions в исполняемой конфигурации.
- CLI-версии фиксируются в `.tool-versions` и `scripts/versions.env`.
- Container base images фиксируются как `version@sha256:digest`, где это поддерживается.
- GitHub Actions фиксируются по полному commit SHA; рядом в комментарии указывается человекочитаемый release tag.
- Helm repository URL и chart version фиксируются в Argo CD Application.
- Версии выбираются в начале реализации по совместимой матрице K3s/k3d/Argo CD/Envoy Gateway/Gateway API/Gatekeeper/Helm и записываются в `docs/version-matrix.md`.
- Dependabot обновляет GitHub Actions и npm; остальные обновления выполняются отдельными PR с повторным e2e.

### 2.5. Единственные входные параметры, которые нужно определить перед кодом

В начале этапа 0 один раз фиксируются:

- `GITHUB_OWNER` и итоговый публичный URL репозитория;
- доступность public GHCR packages либо необходимость `imagePullSecret`;
- архитектура машины с k3d (`amd64` или `arm64`);
- объём RAM, выделенный Docker (целевой минимум документируется после первого e2e).

`bootstrap.sh` берёт repository URL из уже настроенного `origin`, проверяет, что remote доступен Argo CD, и не принимает произвольный URL молча. Значения owner/repository используются для финальных Argo CD Applications и GHCR image names и коммитятся как обычная конфигурация. До появления Git remote можно реализовывать и тестировать этапы 0–3; для этапа 4 remote уже обязателен.

## 3. Целевая структура репозитория

```text
.
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       ├── ci.yml
│       └── release.yml
├── apps/
│   ├── backend/
│   │   ├── cmd/server/main.go
│   │   ├── internal/api/
│   │   ├── internal/config/
│   │   ├── internal/store/
│   │   ├── go.mod
│   │   ├── go.sum
│   │   └── Dockerfile
│   ├── frontend/
│   │   ├── app/
│   │   │   ├── components/ui/
│   │   │   ├── features/messages/
│   │   │   ├── lib/api/
│   │   │   ├── routes/home.tsx
│   │   │   ├── root.tsx
│   │   │   ├── routes.ts
│   │   │   └── styles.css
│   │   ├── public/
│   │   ├── tests/
│   │   ├── components.json
│   │   ├── package.json
│   │   ├── package-lock.json
│   │   ├── react-router.config.ts
│   │   ├── vite.config.ts
│   │   ├── vitest.config.ts
│   │   ├── playwright.config.ts
│   │   ├── Caddyfile
│   │   └── Dockerfile
│   └── postgres-chart/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values.schema.json
│       ├── templates/
│       │   ├── service.yaml
│       │   ├── statefulset.yaml
│       │   └── serviceaccount.yaml
│       └── tests/
├── platform/
│   ├── bootstrap/
│   │   └── argocd/
│   │       ├── kustomization.yaml
│   │       └── patches/
│   ├── clusters/local/
│   │   ├── kustomization.yaml
│   │   ├── namespaces.yaml
│   │   ├── root-application.yaml
│   │   └── applications/
│   │       ├── envoy-gateway-crds.yaml
│   │       ├── envoy-gateway.yaml
│   │       ├── gatekeeper.yaml
│   │       ├── gateway.yaml
│   │       └── policies.yaml
│   ├── policies/
│   │   ├── kustomization.yaml
│   │   ├── templates/
│   │   ├── constraints/
│   │   ├── expansion/
│   │   └── tests/
│   └── score/
│       ├── score-frontend.yaml
│       ├── score-backend.yaml
│       ├── provisioners/local.provisioners.yaml
│       └── patches/unprivileged.tpl
├── cluster/
│   └── k3d.yaml
├── scripts/
│   ├── lib.sh
│   ├── doctor.sh
│   ├── cluster-up.sh
│   ├── bootstrap.sh
│   ├── wait-platform.sh
│   ├── render-app.sh
│   ├── validate-app.sh
│   ├── deploy-app.sh
│   ├── smoke-test.sh
│   ├── demo-policy-denial.sh
│   ├── demo-self-heal.sh
│   └── cluster-down.sh
├── tests/
│   ├── fixtures/
│   └── e2e/
├── docs/
│   ├── architecture.md
│   ├── quickstart.md
│   ├── ci-cd.md
│   ├── security.md
│   ├── demo-scenario.md
│   ├── troubleshooting.md
│   ├── implementation-research.md
│   ├── version-matrix.md
│   └── adr/
│       ├── 0001-two-delivery-planes.md
│       ├── 0002-k3d.md
│       ├── 0003-gateway-api.md
│       ├── 0004-score-state.md
│       └── 0005-local-cd.md
├── .dockerignore
├── .editorconfig
├── .gitignore
├── .tool-versions
├── Makefile
├── README.md
└── тема.pdf
```

Точные имена внутренних Go/React-файлов можно менять без изменения архитектуры. Верхнеуровневые каталоги и ответственность слоёв менять не следует.

## 4. Контракты демонстрационного приложения

### 4.1. Предметная область

Приложение — минимальная «доска сообщений». Оно специально простое: оценивается платформа, а не сложность бизнес-логики.

Backend API:

| Метод | Путь | Назначение | Ответ |
|---|---|---|---|
| `GET` | `/api/health/live` | процесс жив | `200 {"status":"ok"}` |
| `GET` | `/api/health/ready` | доступна БД и выполнена миграция | `200`, иначе `503` |
| `GET` | `/api/version` | commit/build metadata | `200 {"version":"...","commit":"..."}` |
| `GET` | `/api/messages` | получить последние сообщения | `200` + JSON array |
| `POST` | `/api/messages` | создать сообщение | `201` + созданный объект |

Модель сообщения:

```json
{
  "id": 1,
  "text": "deployed by KubeDeploy",
  "createdAt": "2026-10-01T18:00:00Z"
}
```

Ограничения:

- `text`: после trim от 1 до 280 UTF-8 символов;
- request body не более 4 KiB;
- список ограничен последними 100 записями;
- SQL только через параметры;
- корректные timeouts для HTTP server и PostgreSQL pool;
- graceful shutdown по SIGTERM;
- структурированные JSON logs в stdout;
- schema `messages` создаётся idempotent migration при старте.

Frontend stack:

- React 19 stable и строгий TypeScript без `any` в application code;
- React Router в Framework Mode с `ssr: false`: на build получается статический SPA, Node.js в production не нужен;
- Tailwind CSS 4 через first-party Vite plugin;
- shadcn/ui с Base UI как доступные примитивы, исходники выбранных компонентов хранятся и адаптируются в репозитории;
- TanStack Query для server state, cache invalidation и retry policy;
- React Hook Form + Zod для формы и runtime-проверки API responses; Go backend валидирует независимо, а contract tests не дают правилам разойтись;
- без Redux и самодельного глобального store: локальное UI-state остаётся в компонентах;
- production build обслуживается Caddy от непривилегированного пользователя на порту `8080`.

Frontend behavior:

- показывает текущую backend version и состояние API/database;
- выводит список сообщений и позволяет добавить сообщение без полной перезагрузки;
- использует optimistic или immediate feedback, но подтверждает данные ответом API;
- имеет отдельные initial loading, background refresh, empty, validation, offline/network error и retry states;
- route-level error boundary не оставляет пользователя с пустым экраном;
- обращается к относительному пути `/api`, поэтому не требует runtime CORS/config;
- новая запись объявляется screen reader через `aria-live`, focus после submit остаётся предсказуемым.

Визуальное направление — «операционный пульт развёртывания», а не типовой SaaS-dashboard:

- графитовый фон, тёплая светлая поверхность, signal-green для healthy и safety-amber для действий/предупреждений;
- асимметричная status rail, тонкая техническая сетка и компактные deployment badges;
- выразительный локально поставляемый variable display font в паре с моноширинным шрифтом для SHA/status;
- собственные design tokens через CSS variables; shadcn defaults не используются без адаптации;
- одна содержательная entrance sequence и аккуратные state transitions; `prefers-reduced-motion` полностью отключает необязательное движение;
- mobile-first layout от 360 px, затем tablet/desktop без горизонтального scroll.

Frontend quality gates:

- semantic HTML, полная keyboard navigation, видимый focus и WCAG 2.2 AA contrast;
- zero critical axe violations в component/e2e tests;
- initial JS budget до 250 KiB gzip, изображения не нужны для основного сценария;
- цели Lighthouse на production build: Accessibility >= 95, Best Practices >= 90, Performance >= 90;
- `eslint`, TypeScript strict, Vitest, Testing Library и MSW в CI;
- Playwright проверяет загрузку, создание сообщения, error recovery и responsive viewport 360 px;
- никакой зависимости от CDN, внешних fonts или runtime Node server.

### 4.2. PostgreSQL

- Helm release: `demo-postgres`.
- Namespace: `kube-deploy-demo`.
- Service: `demo-postgres` на `5432`.
- Database/user: `kubedeploy`.
- Secret: `demo-postgres-credentials`, ключ `password`.
- Secret создаётся deploy-скриптом только при отсутствии; пароль генерируется локально и не печатается.
- StatefulSet: одна replica, PVC, `Recreate`/ordered semantics по умолчанию.
- `persistentVolumeClaimRetentionPolicy` явно задаёт `Retain` для delete и scale.
- Resource requests/limits обязательны.
- Image version/digest фиксируется.
- Helm 4 получает полный tracked values file; `--reuse-values` не используется.
- В учебном локальном кластере backup не реализуется; это явно указывается как ограничение.

### 4.3. Score workloads

`score-frontend.yaml` описывает:

- container image `.`;
- container port `8080`;
- CPU/memory requests и limits;
- readiness/liveness endpoints или TCP/HTTP probe;
- service port;
- `dns` resource с id `local`;
- `route` resource с host из DNS, path `/` и service port.

`score-backend.yaml` описывает:

- container image `.`;
- `PORT=8080`;
- DB host/port/name/user/password через `${resources.db.*}`;
- health probes;
- requests/limits;
- service port;
- `postgres` resource class `helm`, id `demo-postgres`;
- тот же DNS;
- route `/api` с более специфичным Gateway API `PathPrefix`.

`local.provisioners.yaml` содержит:

- `dns/default/local`: возвращает `kube-deploy.local`;
- `postgres/helm/demo-postgres`: возвращает фиксированные host/port/name/user, а password через `encodeSecretRef "demo-postgres-credentials" "password"`;
- собственный route provisioner для `gateway.networking.k8s.io/v1 HTTPRoute`; он подключает route из `kube-deploy-demo` к shared Gateway и является платформенным шаблоном, а не пользовательским Kubernetes-манифестом.

`unprivileged.tpl` добавляет к Score-генерируемым Deployments:

- `automountServiceAccountToken: false`;
- pod `runAsNonRoot: true` и `seccompProfile: RuntimeDefault`;
- container `allowPrivilegeEscalation: false`, `privileged: false`, drop `ALL` capabilities;
- общие labels `app.kubernetes.io/managed-by: score-k8s` и `kubedeploy.io/part-of: demo`;
- annotation `kubedeploy.io/source-revision` и label `app.kubernetes.io/version`, полученные из deploy SHA.

## 5. Системный слой

### 5.1. k3d

`cluster/k3d.yaml` использует `k3d.io/v1alpha5` SimpleConfig:

- cluster name `kube-deploy`;
- один K3s server и один agent;
- фиксированный patch image из поддерживаемой линии K3s/Kubernetes 1.36, без плавающего tag; Envoy Gateway 1.9 официально тестируется с Kubernetes 1.36;
- встроенный k3d load balancer;
- host ports `127.0.0.1:8080 -> 80` и `127.0.0.1:8443 -> 443` на load balancer;
- фиксированный localhost API port, выбранный после проверки конфликта;
- встроенный Traefik отключён через K3s extra arg, потому что Envoy Gateway устанавливает Argo CD;
- K3s server с первого запуска получает `--secrets-encryption` и `--secrets-encryption-provider=secretbox`;
- стандартный K3s `local-path` StorageClass используется для учебного PVC PostgreSQL;
- kubeconfig context `k3d-kube-deploy`.

K3s `ServiceLB` остаётся включённым: он публикует созданный Envoy Gateway `LoadBalancer` Service через `hostPort` на узлах, до которых доставляет трафик k3d load balancer. Встроенный k3d registry не является каноническим registry проекта: release/deploy использует GHCR. При необходимости его можно добавить позже только для ускорения локального dev loop, не меняя CI/CD-контракт.

Порты 8080/8443 выбраны вместо 80/443, чтобы bootstrap не требовал root и реже конфликтовал с локальными сервисами. В `/etc/hosts` достаточно добавить `127.0.0.1 kube-deploy.local`; quickstart также содержит вариант `curl -H 'Host: kube-deploy.local' http://localhost:8080` без изменения hosts.

### 5.2. Bootstrap Argo CD

Bootstrap — единственное императивное исключение GitOps:

1. Проверить текущий kubectl context и точное имя кластера.
2. Создать namespace `argocd`.
3. `kubectl apply -k platform/bootstrap/argocd`.
4. Дождаться rollout основных deployments/statefulsets.
5. Применить ровно один `root-application.yaml`.
6. Дождаться `Synced/Healthy` каждого дочернего приложения и readiness его controller/CRD; health одного root Application недостаточно.

Argo CD пишет в пользовательский namespace только заранее определённые platform resources, если это требуется shared Gateway/policy scope; пользовательские Deployments и Services остаются вне его управления. Child Applications ограничиваются `AppProject` с явными source repositories, destinations и допустимыми resource kinds. App-of-apps repository считается admin-level и изменяется только через protected `main`.

### 5.3. App-of-apps

Root Application смотрит в `platform/clusters/local` текущего репозитория. Он создаёт:

- `envoy-gateway-crds`: отдельный официальный CRD OCI chart Envoy Gateway 1.9.x с Gateway API v1.6.2 standard channel, pinned version и Server-Side Apply;
- `envoy-gateway`: официальный OCI Helm chart той же pinned версии с `crds.enabled=false` и Server-Side Apply;
- `gatekeeper`: официальный Helm chart, pinned version;
- `gateway`: Kustomize source с shared `GatewayClass`/`Gateway`, допускающим `HTTPRoute` только из `kube-deploy-demo`;
- `policies`: Kustomize source из `platform/policies`.

Порядок через sync waves:

1. namespaces и AppProject;
2. Envoy/Gateway API CRDs и Gatekeeper CRDs;
3. Envoy Gateway и Gatekeeper controllers;
4. shared Gateway и Gatekeeper ConstraintTemplates;
5. Constraints и ExpansionTemplate.

Для child Applications:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - PruneLast=true
```

`allowEmpty` не включается. Namespace deletion не автоматизируется.

Маршрутизация использует Gateway API `v1`, а не `Ingress`: Kubernetes рекомендует Gateway API, а ingress-nginx завершил поддержку в марте 2026 года. E2E ожидает `Programmed=True` у Gateway и `Accepted=True`/`ResolvedRefs=True` у обоих HTTPRoute, после чего проверяет `/api` и `/` через один host.

## 6. Policy as Code

### 6.1. Область применения

- Политики применяются только к namespace с label `policy.kubedeploy.io/enforced=true`.
- Системные namespaces (`kube-system`, `argocd`, `gatekeeper-system`, `envoy-gateway-system`) исключены.
- ConstraintTemplates локальные и адаптированы по семантике официальной Gatekeeper Library на конкретном commit SHA. Изменения (особенно разрешение digest refs для image policy) и provenance документируются отдельно; совместимость проверяется `gator` и admission.
- Constraints работают в `enforcementAction: deny`.
- Validation webhook оставляет chart default `failurePolicy: Ignore`: это явно документированный fail-open trade-off для доступности учебного кластера. Строгую pre-deploy границу дают `gator` и обязательная readiness Gatekeeper.

### 6.2. Политики

1. `K8sNoPrivileged`
   - проверяет containers, initContainers и ephemeralContainers;
   - нарушение, если `securityContext.privileged == true`.

2. `K8sRequiredResources`
   - каждый container и initContainer обязан иметь requests.cpu, requests.memory, limits.cpu, limits.memory;
   - пустое значение считается нарушением.

3. `K8sDisallowedImageTags`
   - запрещает `:latest`;
   - запрещает image без tag и без digest;
   - разрешает SHA-tag и digest.

### 6.3. Двойная проверка

Shift-left:

- `gator verify platform/policies/tests/...` тестирует каждую политику на allowed/disallowed fixtures;
- `gator test` проверяет итоговый Score manifest до `kubectl apply`;
- ExpansionTemplate преобразует Deployment/StatefulSet/DaemonSet в Pod-подобный объект для проверки container policy.

Admission:

- те же ConstraintTemplates и Constraints работают внутри Gatekeeper;
- отдельный demo fixture применяется напрямую в namespace и должен быть отвергнут webhook;
- проверяется понятный текст нарушения.

Критерий: плохая Score-конфигурация не доходит до Kubernetes; попытка обойти pipeline через `kubectl` блокируется Gatekeeper.

Gatekeeper audit проверяется отдельно от admission: он обнаруживает уже существующие нарушения, но не заменяет `gator` и admission gate.

## 7. CI/CD

### 7.1. `ci.yml`

Triggers: `pull_request`, push в feature branches и `main`.

Jobs:

1. `changes`
   - определяет изменённые области, но общие platform validation выполняются всегда.

2. `backend`
   - `go fmt` check;
   - `go vet ./...`;
   - `go test -race -cover ./...`;
   - сборка бинарника.

3. `frontend`
   - `npm ci`;
   - ESLint и `tsc --noEmit` в strict mode;
   - Vitest/Testing Library/MSW unit и component tests;
   - axe accessibility assertions;
   - `npm run build` и bundle-size budget;
   - Playwright smoke на production build в desktop и 360 px viewport.

4. `containers`
   - `docker build --check` для обоих Dockerfile;
   - BuildKit build обоих образов без push;
   - OCI labels source/revision/version;
   - Trivy image scan с failure на исправимых HIGH/CRITICAL;
   - JSON/SARIF report загружается как artifact даже при failure.

5. `platform-validate`
   - YAML lint;
   - `kustomize build` всех overlays;
   - `helm lint` PostgreSQL chart и проверка `values.schema.json`;
   - `helm template` с test values;
   - schema validation через `kubeconform`;
   - `score-k8s init/generate` с фиктивными SHA image refs;
   - validation сгенерированного manifest;
   - `gator verify` policy suites;
   - `gator test` generated manifest against enforced policies;
   - отрицательная fixture обязана завершиться non-zero.

6. `ci-success`
   - единая required status check для branch protection.

Permissions по умолчанию отсутствуют либо `contents: read`; повышаются только конкретному job. Сторонние Actions фиксируются полным commit SHA. Workflows имеют `concurrency` с отменой устаревших PR-запусков. Кэши не содержат secrets, Score state или credentials и не считаются доверенным источником release artifacts.

### 7.2. `release.yml`

Trigger: успешный merge/push в защищённую `main`.

1. Повторить быстрые обязательные тесты или зависеть от required CI commit status.
2. Войти в GHCR через `GITHUB_TOKEN` с job-scoped `packages: write`; для attestation также выдать только `id-token: write` и `attestations: write`.
3. Собрать локальный `linux/amd64` candidate каждого image и передать его в Trivy.
4. Теги:
   - `sha-<full commit sha>` — обязательный deploy tag;
   - `main` можно публиковать только как удобный указатель, но никогда не использовать в Kubernetes.
5. Прервать release при исправимых HIGH/CRITICAL; только после успешного scan собрать и опубликовать multi-platform images `linux/amd64,linux/arm64`.
6. Повторно проверить опубликованные GHCR refs и не запускать CD при post-push failure.
7. Создать SBOM, BuildKit provenance и GitHub artifact attestation для multi-platform manifest digest.
8. Сохранить platform digests и ссылки на attestation в Job Summary; deployable identity — `repository@sha256:...`, а SHA-tag остаётся удобным указателем.
9. Keyless cosign оставить optional enhancement, не блокирующий MVP.

GHCR packages делаются public для простой учебной установки. Если это невозможно, quickstart описывает создание namespace-scoped `imagePullSecret`; token в Git не попадает.

### 7.3. Локальный `make deploy`

Команда принимает обязательный `IMAGE_TAG=sha-<full commit sha>` и запускается разработчиком на Mac после успешного release. Она:

1. Проверяет Git remote, что SHA входит в `origin/main`, и точный context `k3d-kube-deploy`.
2. Разрешает SHA-tags в manifest digests, проверяет их происхождение через `gh attestation verify oci://...` и далее использует только digest refs.
3. Восстанавливает `.score-k8s/state.yaml` из namespace-scoped Secret во временную директорию либо инициализирует state при первом deploy.
4. Создаёт или повторно использует PostgreSQL Secret и выполняет Helm upgrade с полным tracked values file, `--wait --wait-for-jobs --rollback-on-failure --cleanup-on-fail --timeout 5m`.
5. Генерирует Score manifests, проверяет schema и Gatekeeper policies, применяет через Server-Side Apply без `--force-conflicts`.
6. После успешного apply сохраняет Score state в Secret; ждёт Gateway/HTTPRoute conditions и rollout с конечными timeout.
7. Запускает `make smoke` и печатает URL, digest и результаты без секретов.

Одновременный локальный deploy отклоняется через lock; повторный запуск с тем же SHA идемпотентен.

## 8. Скрипты и Makefile

Публичный интерфейс проекта — Makefile. Скрипты должны использовать `set -Eeuo pipefail`, единый `scripts/lib.sh`, понятные ошибки и cleanup traps.

| Команда | Эффект |
|---|---|
| `make doctor` | проверяет Docker, k3d, kubectl, helm, kustomize, score-k8s, gator, kubeconform, jq, curl |
| `make cluster-up` | создаёт только k3d/K3s-кластер, idempotent |
| `make bootstrap` | устанавливает Argo CD и root Application |
| `make platform-status` | показывает Argo Applications, pods и policy CRDs |
| `make test` | unit tests frontend/backend и policy suites |
| `make lint` | исходники, shell, YAML, Helm, Kustomize |
| `make render IMAGE_TAG=...` | создаёт `build/manifests.yaml` из Score |
| `make validate-generated` | kubeconform + gator для generated manifest |
| `make deploy IMAGE_TAG=...` | attestation/state/secret/Helm/Score/SSA/rollout |
| `make smoke` | API/UI/database smoke tests |
| `make demo-policy` | безопасно демонстрирует отклонение трёх плохих fixtures |
| `make demo-drift` | вносит обратимый drift в системный Deployment и ждёт self-heal |
| `make e2e` | cluster-up → bootstrap → deploy → проверки |
| `make cluster-down` | удаляет только cluster `kube-deploy` после явной команды |

Все изменяющие cluster scripts обязаны:

- сравнить текущий context с `k3d-kube-deploy`;
- работать только с известными namespaces/releases;
- не использовать wildcard deletion;
- не выводить Secret values;
- использовать fully-qualified resources, machine-readable output и конечные timeout;
- поддерживать повторный запуск.

## 9. План реализации по этапам

### Этап 0. Каркас и стандарты

Создать:

- Git repository и базовый `.gitignore`;
- README с состоянием проекта;
- `.editorconfig`, tool/version files;
- Makefile и `doctor.sh`;
- ADR для двух контуров доставки и k3d;
- ADR для Gateway API/Envoy Gateway и Score state;
- GitHub labels/branch protection checklist в docs.

Проверка:

- `make doctor` сообщает полный список найденных/отсутствующих инструментов;
- `.gitignore` исключает secrets, `.score-k8s`, build и kubeconfig;
- все версии имеют одно место определения;
- Actions не используют floating refs, а workflow permissions проходят автоматическую проверку.

### Этап 1. Backend

Реализовать API, конфигурацию из env, PostgreSQL store, migrations, health checks и tests.

HTTP server получает конечные read/header/write/idle timeouts и `MaxHeaderBytes`; shutdown использует bounded context. `pgxpool` после создания проходит явный `Ping`, а request context передаётся во все DB operations.

Тесты:

- config validation;
- handler validation/status codes;
- store integration test через disposable PostgreSQL container либо testcontainers;
- graceful shutdown;
- cancellation SQL-запроса и корректное различие liveness/readiness;
- migration повторно применяется без ошибки.

Готово, когда `go test -race ./...` проходит и локальный binary возвращает ожидаемые health responses.

### Этап 2. Frontend

Создать React Router Framework Mode SPA и собственную visual system поверх Tailwind 4/shadcn Base UI. Реализовать typed API client, Query hooks, форму, полный набор состояний и production serving.

Тесты:

- route/root error boundary и рендер shell;
- loading, background refresh, empty и populated states;
- успешное добавление и cache invalidation;
- client validation, `400/422`, `500`, network failure и retry;
- keyboard-only flow и axe assertions;
- Playwright happy path и 360 px layout;
- production build, bundle budget и Lighthouse thresholds.

Готово, когда `npm ci`, lint/typecheck/tests/build/e2e проходят, UI сохраняет дизайн и функциональность от 360 px, а Caddy обслуживает только статические artifacts.

### Этап 3. Контейнеризация

- Multi-stage Dockerfiles.
- Non-root runtime.
- Backend runtime на pinned distroless `static-debian13:nonroot` digest.
- `.dockerignore` на каждый build context.
- OCI source/revision labels.
- Backend image без компилятора/package manager.
- Frontend static assets + Caddy port 8080.

Проверка:

- containers стартуют локально;
- processes не root;
- health endpoints работают;
- image scan соответствует установленному порогу;
- `docker build --check` проходит, в build args/env нет secrets, SBOM/provenance генерируются для release image.

### Этап 4. k3d и Argo CD bootstrap

- k3d SimpleConfig и lifecycle scripts.
- K3s secrets encryption at rest с provider `secretbox`.
- Pinned Argo CD Kustomize bootstrap.
- Root Application и AppProject.
- wait/status diagnostics.

Проверка:

- чистый `make cluster-up bootstrap` заканчивается без ручных kubectl-команд;
- root Application `Synced/Healthy`;
- каждый child Application и его controller/CRD готовы независимо от root health;
- повторный bootstrap не ломает кластер.

### Этап 5. Системные приложения и Gateway API

- Envoy Gateway Application + pinned OCI chart/values;
- Gateway API CRDs совместимой версии и shared Gateway;
- Gatekeeper Application + values;
- namespaces и sync waves;
- доступ по `localhost:8080` с Host header.

Проверка:

- Envoy controller ready, Gateway `Programmed=True`, HTTPRoute `Accepted=True`/`ResolvedRefs=True`;
- Gatekeeper webhook ready;
- Argo child apps Healthy;
- безопасный drift управляемого replica count системного Deployment (1 → 2 → 1) исправляется Argo CD без изменения image и без прерывания маршрутизации.

### Этап 6. Политики

- Три локальных ConstraintTemplates, адаптированных на основе pinned Gatekeeper Library commit, и локальные Constraints.
- Namespace selector.
- ExpansionTemplate.
- Gator suites и fixtures.

Проверка:

- allowed fixtures проходят;
- каждая disallowed fixture падает по своей причине;
- admission webhook отклоняет прямой `kubectl apply`;
- audit отдельно показывает существующее intentional violation;
- системные namespaces не затронуты.

### Этап 7. PostgreSQL Helm chart

- StatefulSet, headless/normal Service, ServiceAccount, PVC.
- Явная PVC retention policy `Retain` для delete и scale.
- External Secret contract.
- Values schema, probes, resources, securityContext.
- NOTES и chart tests.

Проверка:

- `helm lint` и template schema validation;
- install/upgrade Helm 4 с `--wait --wait-for-jobs --rollback-on-failure --cleanup-on-fail`, без `--reuse-values`;
- `helm test` проверяет DB auth/connection;
- пароль не появляется в rendered chart и logs;
- запись переживает перезапуск PostgreSQL pod.

### Этап 8. Score integration

- Score specs frontend/backend.
- Local provisioners.
- Security patch template.
- Restore/persist `.score-k8s/state.yaml` через Kubernetes Secret.
- Render/validate scripts.

Проверка:

- generated manifest содержит только ожидаемые Deployment, Service и HTTPRoute; namespace/Gateway создаются системным Kustomize-слоем, а PostgreSQL — Helm;
- frontend/backend Kubernetes manifests не написаны вручную;
- image refs immutable;
- password представлен как `secretKeyRef`, а не plaintext;
- два последовательных generation с восстановленным state сохраняют resource identities; deploy сериализован;
- Server-Side Apply с field manager `kubedeploy-score` выявляет конфликт и не захватывает его принудительно;
- generated manifest проходит policies.

### Этап 9. Локальный deploy и smoke tests

- Secret initialization.
- Helm database deploy.
- Score render/apply.
- rollout waits.
- HTTP and persistence tests.

Проверка:

- UI открывается;
- POST затем GET возвращают запись;
- backend version соответствует image SHA;
- второй deploy идемпотентен;
- краткая недоступность БД делает backend NotReady, но не запускает liveness restart loop;
- данные остаются после обновления backend.

### Этап 10. GitHub Actions

- CI workflow.
- Release/GHCR workflow.
- Проверенная передача SHA release в локальный `make deploy`.
- Dependabot и permissions hardening.
- SBOM, provenance и GitHub artifact attestations.

Проверка:

- PR не имеет доступа к packages write или локальному kubeconfig;
- плохой test/policy/Trivy scan блокирует merge/release;
- успешный main build публикует два SHA image;
- локальный deploy проверяет attestation и применяет ровно digest образа из этого SHA release;
- workflow YAML проходит actionlint.

### Этап 11. Сквозной e2e и демонстрации

Автоматизировать четыре обязательных сценария темы:

1. Развёртывание: чистый кластер → работающий frontend/backend/PostgreSQL.
2. Обновление: новый commit → новые SHA images → rollout → новая `/api/version`, данные сохранены.
3. Блокировка: manifests с privileged, без limits и с latest отклоняются сначала gator, а прямой apply — Gatekeeper.
4. Самовосстановление: вручную изменённый системный Deployment возвращается Argo CD в Git-state.

Каждый сценарий имеет Arrange/Act/Assert/Cleanup и конечные timeout. Собирать доказательства в stdout, JUnit-compatible summary и GitHub Job Summary, не сохранять secrets/kubeconfig.

### Этап 12. Документация и защита

- README: ценность, архитектура, quickstart, команды.
- Architecture: границы системного/пользовательского слоёв и data flow.
- CI/CD: events, permissions, artifacts, failure modes.
- Security: threat model, secrets, локальный доступ к кластеру, policies, Trivy threshold.
- Demo scenario: команды и ожидаемые результаты на 7–10 минут.
- Troubleshooting: Docker resources, ports, DNS, webhook readiness, GHCR auth, локальный deploy.
- Version matrix и список ограничений.
- Исследовательский журнал `docs/implementation-research.md` с принятыми и отложенными решениями.
- Mermaid-схемы плюс эквивалентное текстовое описание для доступности.

Готово, когда новый разработчик по README проходит setup без устных подсказок.

## 10. Тестовая матрица

| Уровень | Что проверяется | Где |
|---|---|---|
| Unit | backend handlers/config, frontend components/API client | CI |
| Integration | backend + PostgreSQL, Helm render | CI/local |
| Static | Go vet, ESLint, TypeScript, shellcheck, yamllint, actionlint | CI |
| Supply chain | vulnerabilities, build checks, SBOM, provenance, attestation | CI/release/deploy |
| Config | Score generation/state continuity, Kustomize build, Helm lint/schema, kubeconform | CI/local CD |
| Policy unit | good/bad fixtures per policy | gator verify |
| Policy integration | generated manifests vs all policies | gator test |
| Admission | прямой bad manifest блокируется webhook | k3d e2e |
| Platform | child Argo Applications, controllers, Gateway/HTTPRoute conditions | k3d e2e |
| Application | HTTP, DB write/read, probes, rollout | k3d e2e |
| Resilience | DB persistence and Argo self-heal | demo/e2e |

## 11. Критерии готовности проекта

Проект завершён только если одновременно выполнено следующее:

- С нуля выполняются `make cluster-up`, `make bootstrap`, `make deploy`, `make smoke`.
- Системные компоненты видны в Argo CD и находятся в `Synced/Healthy`.
- В Git нет секретов и `.score-k8s/state.yaml`.
- Frontend/backend не имеют вручную написанных Kubernetes Deployment/Service.
- Score generation использует проверенные реальные GHCR digest refs, соответствующие SHA release.
- Score state переживает повторный deploy и не хранится в Git/artifacts.
- PostgreSQL развёрнут Helm и хранит данные на PVC.
- Все три policies имеют положительные и отрицательные тесты.
- Плохая конфигурация блокируется до apply и на admission.
- Trivy HIGH/CRITICAL policy реально ломает release.
- Ручной drift системного ресурса автоматически устраняется.
- Обновление приложения не уничтожает сохранённые данные.
- CI workflows используют минимальные permissions и pinned actions.
- Release публикует SBOM/provenance/attestation, а deploy проверяет attestation до apply.
- README воспроизводим на чистом окружении.
- Все обязательные сценарии записаны в `docs/demo-scenario.md` с ожидаемыми результатами.

## 12. Риски и меры

| Риск | Последствие | Мера |
|---|---|---|
| Недостаточно RAM для k3d + Argo + Gatekeeper | нестабильные pods | один agent, requests, preflight Docker memory check, troubleshooting |
| Встроенные Traefik/ServiceLB K3s конфликтуют с Envoy Gateway | порт недоступен или занят | Traefik отключён, ServiceLB оставлен осознанно, Gateway/HTTPRoute и routing покрыты e2e |
| Отличия K3s от upstream Kubernetes | скрытая непереносимость | использовать стандартные API, фиксировать отличия в ADR/version matrix |
| Gatekeeper блокирует системные компоненты | кластер не bootstrap-ится | namespace label opt-in, system exclusions, policies ставятся после controller |
| Argo CD root app удаляет критичный namespace | потеря среды | namespace prune protection, `allowEmpty=false`, PruneLast |
| Локальный deploy запускает непроверенный release | компрометация кластера | exact SHA из `origin/main`, attestation и digest verification до apply |
| Score state содержит non-hermetic/secret material | утечка или смена resource identities | temp directory, encrypted namespace Secret, serialized deploy, `.gitignore`, secret scan, запрет artifacts/logging |
| GHCR package private | ImagePullBackOff | public package для demo или документированный imagePullSecret |
| Trivy database/network недоступны | flaky CI | cache с контролем свежести, retry только download, fail closed для release |
| В официальном PostgreSQL 17.11 image остаются исправимые HIGH/CRITICAL находки во вспомогательном `gosu` | остаточный риск для локальной учебной БД | зафиксировать результат сканирования и отслеживать обновление upstream image; не ослаблять fail-closed gate для frontend/backend |
| Floating upstream manifests | невоспроизводимость | pin tag/version/SHA/digest, version matrix |
| Helm-generated secret меняется на upgrade | потеря DB доступа | secret создаётся отдельно один раз, chart использует existing Secret |
| SSA не удаляет исчезнувший Score resource | orphan resources | стабильный фиксированный MVP; cleanup command по точному label, limitation documented |
| HTTPRoute precedence `/api` vs `/` | запросы идут во frontend | один host, `PathPrefix`, accepted/resolved status и e2e для `/api/version` и `/` |
| Gatekeeper webhook fail-open недоступен | плохой manifest может пройти admission | обязательные gator checks, readiness перед deploy/demo, audit; fail-closed оставлен отдельным hardening этапом |
| Envoy/Gateway API CRD version mismatch | controller не принимает routes | единая compatibility matrix, pinned chart/CRDs, clean-cluster e2e |

## 13. Предлагаемая последовательность коммитов

1. `chore: initialize repository and toolchain`
2. `feat(backend): add message API and postgres store`
3. `feat(frontend): add message board UI`
4. `build: add reproducible non-root container images`
5. `feat(cluster): add k3d and argocd bootstrap`
6. `feat(platform): manage gateway api and gatekeeper with argocd`
7. `feat(policy): enforce and test workload security policies`
8. `feat(database): add postgres helm chart`
9. `feat(score): generate demo workloads from score specs`
10. `feat(deploy): add local deployment and smoke tests`
11. `ci: add validation build scan and ghcr release`
12. `feat(deploy): verify published release and deploy locally`
13. `test: add end-to-end platform scenarios`
14. `docs: add architecture operations and defense runbook`

Каждый коммит должен быть зелёным на доступном ему наборе проверок. Не следует откладывать все tests/workflows на последний коммит.

## 14. Порядок следующего рабочего сеанса

1. Проверить prerequisites и выбрать совместимые pinned versions.
2. Инициализировать Git и каркас из этапа 0.
3. Реализовать этапы строго по порядку 1–12.
4. После каждого этапа запускать его локальный критерий готовности.
5. После появления k3d запускать e2e после каждого изменения platform/policy/Score.
6. Не переходить к документации защиты, пока четыре обязательных сценария не проходят автоматически.

Этот файл является рабочим baseline. Архитектурное изменение оформляется ADR и одновременно обновляет план, tests и диаграмму.

## 15. Официальные технические опоры

- Полный журнал решений по всем этапам: [`docs/implementation-research.md`](docs/implementation-research.md).
- [Score specification](https://docs.score.dev/docs/score-specification/score-spec-reference/)
- [score-k8s CLI](https://docs.score.dev/docs/score-implementation/score-k8s/cli/)
- [score-k8s provisioners](https://docs.score.dev/docs/score-implementation/score-k8s/resources-provisioners/)
- [score-k8s patch templates](https://docs.score.dev/docs/score-implementation/score-k8s/patch-templates/)
- [Score in CI/CD and state handling](https://docs.score.dev/docs/how-to/score-cicd-pipelines/)
- [Argo CD automated sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
- [Argo CD cluster bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Argo CD projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
- [Envoy Gateway with Argo CD](https://gateway.envoyproxy.io/docs/install/install-argocd/)
- [Gateway API implementations](https://gateway-api.sigs.k8s.io/docs/implementations/list/)
- [Gateway API cross-namespace routing](https://gateway-api.sigs.k8s.io/guides/user-guides/multiple-ns/)
- [Gatekeeper ConstraintTemplates](https://open-policy-agent.github.io/gatekeeper/website/docs/constrainttemplates/)
- [Gatekeeper gator CLI](https://open-policy-agent.github.io/gatekeeper/website/docs/gator/)
- [Gatekeeper Library](https://open-policy-agent.github.io/gatekeeper-library/website/)
- [k3d configuration](https://k3d.io/stable/usage/configfile/)
- [k3d registries](https://k3d.io/stable/usage/registries/)
- [K3s secrets encryption](https://docs.k3s.io/security/secrets-encryption)
- [Kubernetes Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)
- [Kubernetes probes](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes)
- [Helm 4 upgrade](https://docs.helm.sh/docs/helm/helm_upgrade/)
- [Docker build checks](https://docs.docker.com/build/checks/)
- [Docker build attestations](https://docs.docker.com/build/ci/github-actions/attestations/)
- [React Router SPA mode](https://reactrouter.com/how-to/spa)
- [shadcn/ui for Vite](https://ui.shadcn.com/docs/installation/vite)
- [Tailwind CSS with Vite](https://tailwindcss.com/docs/installation/using-vite)
- [GitHub secure use of Actions](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Trivy GitHub Action](https://github.com/aquasecurity/trivy-action)
