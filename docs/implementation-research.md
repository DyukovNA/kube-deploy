# Исследование практик для реализации KubeDeploy Platform

Дата проверки: 2026-10-01

Область: этапы 0–12 из `IMPLEMENTATION_PLAN.md`

Метод: использованы только официальные руководства проектов и upstream-документация. Версии всё равно фиксируются непосредственно перед реализацией в `docs/version-matrix.md`, потому что compatibility matrix и patch-релизы меняются.

Изменение решения 2026-10-04: для MVP выбран локальный `make deploy` на одном Mac без self-hosted runner. Упоминания runner ниже сохраняют исходные исследовательские выводы, но не являются текущим планом реализации. Текущий baseline — `IMPLEMENTATION_PLAN.md` §2.2 и §7.3.

## Как читать документ

- **Зафиксировано** — решение входит в основной план и должно быть реализовано.
- **Проверка** — отдельный автоматический критерий, добавленный по результатам исследования.
- **Отложено** — полезная возможность, которая сознательно не входит в MVP.

## Этап 0. Каркас и стандарты

Что найдено:

- GitHub рекомендует фиксировать сторонние Actions по полному commit SHA и выдавать `GITHUB_TOKEN` минимальные permissions. Workflow из fork/PR нельзя допускать к доверенному self-hosted runner; `pull_request_target` не должен выполнять недоверенный код из PR.
- Кэш Actions не является доверенным хранилищем и не должен содержать секреты. Низкодоверенные запуски могут читать подходящие cache entries, поэтому deploy/release не должны исполнять бинарники из PR-сформированного кэша без повторной проверки.
- Скрипты с `kubectl` должны запрашивать machine-readable output, указывать namespace/context явно и иметь конечный timeout.

Зафиксировано:

- Actions — только full SHA с комментарием версии; workflow-level `permissions: {}` либо `contents: read`, расширение только на конкретный job.
- `pull_request` выполняет только read-only CI на GitHub-hosted runner. Локальное применение release выполняет разработчик командой `make deploy` на Mac с k3d.
- `actionlint`, `shellcheck`, YAML lint и проверка всех закреплённых Actions входят в CI.
- `doctor.sh` сравнивает не только наличие CLI, но и совместимые версии из одного version file.

Проверка:

- CI-тест отвергает floating Action refs (`@main`, `@v4`) и workflow с неожиданными write permissions.

Источники:

- [GitHub Actions: Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub Actions workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [GitHub dependency caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
- [kubectl usage conventions](https://kubernetes.io/docs/reference/kubectl/conventions/)

## Этап 1. Backend

Что найдено:

- `http.Server.Shutdown` прекращает приём новых соединений и ждёт активные запросы; процесс не должен завершаться раньше возврата `Shutdown`.
- У HTTP-сервера должны быть конечные `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout`, `MaxHeaderBytes` и shutdown timeout.
- Контекст HTTP-запроса нужно передавать в запросы к БД, чтобы отмена клиента или timeout отменяли SQL-операцию.
- `pgxpool.New` не гарантирует немедленное соединение с БД; после создания пула нужен явный `Ping`. Транзакция требует явного `Commit` или `Rollback`.

Зафиксировано:

- Один root context через `signal.NotifyContext`, отдельный bounded context на shutdown, закрытие пула после остановки HTTP.
- Startup выполняет config validation, создание пула, `Ping`, idempotent migration; только после этого сервер считается ready.
- Liveness проверяет только жизнеспособность процесса. Readiness делает короткий DB ping и проверяет версию миграции.
- Request body ограничивается до декодирования, неизвестные JSON fields отклоняются, SQL выполняется только с request context.

Проверка:

- Тесты на SIGTERM с незавершённым запросом, cancellation DB query, повторную migration и отсутствие ready при недоступной БД.

Источники:

- [Go `net/http` package](https://pkg.go.dev/net/http)
- [Go: Canceling in-progress database operations](https://go.dev/doc/database/cancel-operations)
- [`pgxpool` package](https://pkg.go.dev/github.com/jackc/pgx/v5/pgxpool)

## Этап 2. Frontend

Исследование frontend уже встроено в основной план: React Router Framework Mode в SPA-режиме, Tailwind CSS 4, адаптированные shadcn/ui primitives, строгая доступность, responsive/e2e/performance gates. Важное ограничение — production остаётся статическим и не требует Node.js runtime.

Источники:

- [React Router SPA mode](https://reactrouter.com/how-to/spa)
- [Tailwind CSS with Vite](https://tailwindcss.com/docs/installation/using-vite)
- [shadcn/ui for Vite](https://ui.shadcn.com/docs/installation/vite)
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)

## Этап 3. Контейнеризация

Что найдено:

- BuildKit умеет отдельно проверять Dockerfile через `docker build --check`.
- Secrets нельзя передавать через `ARG`/`ENV`: они остаются в metadata/layers. Для приватных ресурсов допустимы только BuildKit secret/SSH mounts.
- Buildx может публиковать SBOM и provenance attestations вместе с образом.
- Distroless не содержит shell/package manager; для Go подходит `static-debian13:nonroot`. Debian generation и digest надо фиксировать явно, debug-вариант не использовать в release.

Зафиксировано:

- Backend runtime — pinned `gcr.io/distroless/static-debian13:nonroot@sha256:...`; frontend runtime — pinned Caddy image с non-root конфигурацией.
- `docker build --check` обязателен; `SecretsUsedInArgOrEnv` блокирует CI.
- Все base images фиксируются по digest; source/revision/version OCI labels обязательны.
- Release создаёт SBOM и provenance для multi-platform manifest digest.

Проверка:

- Runtime UID не равен 0, filesystem не требует записи вне выделенного temp, образ не содержит shell/компилятор/исходники, `/api/health/live` работает.

Источники:

- [Docker build checks](https://docs.docker.com/build/checks/)
- [Docker build secrets](https://docs.docker.com/build/building/secrets/)
- [Docker attestations in GitHub Actions](https://docs.docker.com/build/ci/github-actions/attestations/)
- [GoogleContainerTools/distroless](https://github.com/GoogleContainerTools/distroless)

## Этап 4. k3d и Argo CD bootstrap

Что найдено:

- K3s умеет шифровать Kubernetes Secrets в datastore, если сервер с первого запуска получает `--secrets-encryption`; доступен provider `secretbox`.
- App-of-apps остаётся допустимым bootstrap pattern, но parent repository фактически является admin-level: создавать child Applications должен только доверенный автор.
- Состояние parent Application не доказывает здоровье child Applications. В новых Argo CD health inheritance для `Application` не включён по умолчанию.
- Default AppProject слишком широк для безопасного baseline.

Зафиксировано:

- `cluster/k3d.yaml` включает `--secrets-encryption` и `--secrets-encryption-provider=secretbox` на K3s server с самого создания кластера.
- Root app и child app definitions изменяются только через protected `main`; отдельный AppProject ограничивает repositories, destinations и resource kinds.
- `wait-platform.sh` явно ждёт каждый child Application и его реальные Deployments/CRDs, а не полагается на health root app.
- Sync waves задают порядок CRD/controller/custom resources; `allowEmpty` выключен, prune выполняется последним.

Проверка:

- Clean bootstrap, повторный bootstrap, проверка AppProject deny и проверка включённого K3s secrets encryption.

Источники:

- [k3d configuration file](https://k3d.io/stable/usage/configfile/)
- [K3s secrets encryption](https://docs.k3s.io/security/secrets-encryption)
- [Argo CD cluster bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Argo CD Projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
- [Argo CD sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Argo CD resource health](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/)

## Этап 5. Системные приложения и входящий трафик

Что найдено:

- ingress-nginx завершил поддержку в марте 2026 года; новые releases и security fixes больше не выпускаются.
- Kubernetes рекомендует Gateway API вместо Ingress API.
- Envoy Gateway является conformant Gateway API implementation и имеет официальный пример установки через Argo CD с Server-Side Apply.
- Cross-namespace `HTTPRoute` может подключаться к shared Gateway только если listener явно разрешает namespace через `allowedRoutes`; selector по системной namespace-name label безопаснее произвольной изменяемой label.

Зафиксировано:

- ingress-nginx исключён. Используются pinned Envoy Gateway Helm chart и Gateway API `v1`.
- Совместимый baseline — latest patch K3s/Kubernetes 1.36 и Envoy Gateway 1.9.x: официальная matrix покрывает Kubernetes 1.33–1.36 и Gateway API v1.6.1.
- Один владелец CRD: отдельное Argo Application рендерит официальный `gateway-crds-helm` standard channel через Server-Side Apply; основной chart получает `crds.enabled=false`. K3s 1.37 со встроенными Gateway API CRD пока не берётся, чтобы не смешивать владельцев и только что выпущенную minor line.
- K3s Traefik отключён, чтобы был один gateway controller. ServiceLB остаётся и публикует Envoy `LoadBalancer` Service через k3d load balancer.
- Argo CD управляет `GatewayClass`/`Gateway`; Score provisioner создаёт только `HTTPRoute` в `kube-deploy-demo`.
- Shared Gateway разрешает route attachment только из namespace `kube-deploy-demo` через selector по `kubernetes.io/metadata.name`.
- E2E ждёт у `Gateway` condition `Programmed=True`, а у обоих `HTTPRoute` — `Accepted=True` и `ResolvedRefs=True`.

Проверка:

- `/api` идёт в backend, `/` — во frontend, неизвестный host/path не маршрутизируется; проверяются status conditions, а не только HTTP 200.

Источники:

- [ingress-nginx retirement notice](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Ingress documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Gateway API conformant implementations](https://gateway-api.sigs.k8s.io/docs/implementations/list/)
- [Envoy Gateway installation with Argo CD](https://gateway.envoyproxy.io/docs/install/install-argocd/)
- [Envoy Gateway compatibility matrix](https://gateway.envoyproxy.io/news/releases/matrix/)
- [Gateway API cross-namespace routing](https://gateway-api.sigs.k8s.io/guides/user-guides/multiple-ns/)

## Этап 6. Policy as Code

Что найдено:

- Официальная Gatekeeper Library уже содержит шаблоны privileged containers, required container resources и disallowed image tags. Собственные аналоги дают лишний риск ошибки в Rego.
- Gatekeeper chart по умолчанию использует `failurePolicy: Ignore`: это fail-open при недоступном webhook. `Fail` усиливает enforcement, но способен остановить cluster operations при проблеме Gatekeeper.
- Audit обнаруживает уже существующие нарушения, а admission блокирует новые. Лимит audit results в status ограничен, поэтому CI не должен использовать audit как единственный gate.
- ExpansionTemplate позволяет применять pod-level policy к workload controllers и должен быть покрыт отдельным тестом.

Зафиксировано:

- Три ConstraintTemplate vendored из Gatekeeper Library на конкретном commit SHA с сохранением лицензии и provenance; локально пишутся Constraints, namespace scope и tests.
- Для учебного single-cluster MVP остаётся документированный fail-open (`Ignore`), чтобы сбой webhook не ломал bootstrap. Строгий gate обеспечивают `gator` до apply и readiness Gatekeeper перед deploy/demo.
- Admission и audit проверяются раздельно. Enforcement включается только для `kube-deploy-demo`.

Проверка:

- Fixtures охватывают containers/initContainers/ephemeralContainers, no-tag/`latest`, каждый отсутствующий requests/limits field и expansion из Deployment.
- E2E подтверждает admission denial и появление intentional audit violation; после теста fixture удаляется.

Отложено:

- Fail-closed режим — только после namespace exemptions и проверки аварийного восстановления webhook.

Источники:

- [Gatekeeper Library: privileged containers](https://open-policy-agent.github.io/gatekeeper-library/website/validation/privileged-containers/)
- [Gatekeeper Library: required resources](https://open-policy-agent.github.io/gatekeeper-library/website/validation/containerresources/)
- [Gatekeeper Library: disallowed tags](https://open-policy-agent.github.io/gatekeeper-library/website/validation/disallowedtags/)
- [Gatekeeper audit](https://open-policy-agent.github.io/gatekeeper/website/docs/audit/)
- [Gatekeeper fail-closed discussion](https://open-policy-agent.github.io/gatekeeper/website/docs/v3.8.x/failing-closed/)

## Этап 7. PostgreSQL Helm chart

Что найдено:

- StatefulSet даёт stable identity/storage; `volumeClaimTemplates` создаёт PVC, который не следует неявно удалять вместе с workload.
- Kubernetes Secret — не шифрование: данные base64 и по умолчанию могут лежать в datastore открыто. Это усиливает необходимость K3s encryption at rest и минимального RBAC.
- `values.schema.json` проверяется при `lint`, `template`, `install` и `upgrade`.
- В Helm 4 `--atomic` заменён явным сочетанием `--rollback-on-failure`, `--cleanup-on-fail` и `--wait`. `--reuse-values` делает результат зависимым от старого release state.

Зафиксировано:

- Используется pinned Helm 4; deploy всегда передаёт полный tracked values file и не использует `--reuse-values`.
- Команда: `helm upgrade --install ... --wait --wait-for-jobs --rollback-on-failure --cleanup-on-fail --timeout 5m`.
- StatefulSet явно задаёт `persistentVolumeClaimRetentionPolicy.whenDeleted=Retain` и `whenScaled=Retain`.
- Secret создаётся вне chart и только referenced; `helm template`/debug output с секретами не сохраняется.
- Chart содержит JSON Schema и `helm test` Job, который проверяет auth/connection и удаляется после теста.

Проверка:

- Install/upgrade/rollback-on-failure, повторное использование того же Secret, сохранение записи после pod restart и chart uninstall/install с retained PVC по документированной процедуре.

Источники:

- [Kubernetes StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Kubernetes Secrets good practices](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [Helm charts and schema files](https://docs.helm.sh/docs/topics/charts/)
- [Helm 4 upgrade command](https://docs.helm.sh/docs/helm/helm_upgrade/)

## Этап 8. Score integration

Что найдено:

- `.score-k8s/state.yaml` содержит unique/random/non-hermetic state. Официальная рекомендация для CI — восстанавливать его перед generation, сохранять после deploy и сериализовать concurrent deployments.
- Официальный Score CI/CD example генерирует `gateway.networking.k8s.io/v1 HTTPRoute`, поэтому Gateway API является естественным target для route provisioner.
- Kubernetes Server-Side Apply отслеживает владельцев полей и сообщает конфликт вместо скрытого перетирания другого manager.

Зафиксировано:

- Score state хранится не в Git/artifacts, а в Kubernetes Secret `score-k8s-state` в namespace приложения; перед render восстанавливается во временную директорию и после успешного deploy обновляется.
- Deploy jobs сериализованы через `concurrency: local-cluster`; temp/state всегда удаляются trap-ом и не печатаются.
- Generated resources применяются через `kubectl apply --server-side --field-manager=kubedeploy-score`; `--force-conflicts` запрещён в штатном пути.
- Route provisioner генерирует `HTTPRoute`, не `Ingress`.

Проверка:

- Два последовательных deploy используют один resource identity; конфликт field manager приводит к явному failure; state Secret существует и не выводится в logs.

Источники:

- [Score CI/CD pipelines](https://docs.score.dev/docs/how-to/score-cicd-pipelines/)
- [Score local state](https://docs.score.dev/docs/score-implementation/local-state/)
- [Score specification reference](https://docs.score.dev/docs/score-specification/score-spec-reference/)
- [Kubernetes Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)

## Этап 9. Локальный deploy и smoke tests

Что найдено:

- Startup probe блокирует liveness/readiness до успешного старта. Readiness убирает Pod из Service endpoints; liveness предназначен для restart, поэтому зависимость от БД нельзя включать в liveness backend.
- `kubectl rollout status` и `kubectl wait` должны иметь явные timeouts. Для reusable scripts рекомендуются fully-qualified resources и JSON/JSONPath output.

Зафиксировано:

- Backend: startup проверяет завершение startup/migration, readiness зависит от DB, liveness — только process-local. Frontend использует простую HTTP readiness/liveness.
- Deploy порядок: exact context → state restore → Secret init → Helm PostgreSQL → render/validate → SSA → state persist → route/rollout waits → smoke.
- Все waits конечны; при failure выводятся `get/describe/events/logs` только по известным namespaces/labels без Secret values.

Проверка:

- Идемпотентный второй deploy, forced DB unavailability (NotReady без restart loop), update SHA с сохранением данных, отрицательный timeout path с diagnostics.

Источники:

- [Kubernetes probes](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes)
- [`kubectl rollout status`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/kubectl_rollout_status/)
- [`kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/)

## Этап 10. GitHub Actions, release и local CD

Что найдено:

- GitHub Environment может ограничить deployment branch и удерживать environment secrets до approval. В текущем MVP kubeconfig остаётся только на Mac и не передаётся в GitHub.
- Artifact attestations могут связать GHCR image digest с workflow identity; `gh attestation verify oci://...` позволяет проверить происхождение перед deploy.
- Buildx умеет прикреплять SBOM/provenance к multi-platform image. Подписывать mutable tag недостаточно — deploy должен разрешить tag в digest и работать с digest.

Зафиксировано:

- Release запускается только для защищённой `main`; локальный deploy проверяет SHA из `origin/main` и опубликованный release.
- Release permissions: `contents: read`, `packages: write`, `id-token: write`, `attestations: write`; остальные отсутствуют.
- Release публикует `sha-<full SHA>`, SBOM, provenance и GitHub artifact attestation для manifest digest.
- Перед локальным deploy команда на Mac выполняет `gh attestation verify` и применяет образы как `repository@sha256:...`; SHA-tag остаётся удобным указателем и доказательством версии.

Проверка:

- PR/fork не может вызвать deploy; неподтверждённый digest и digest не от текущего repository workflow отклоняются; cache не переносит credentials/state.

Источники:

- [GitHub deployment environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [GitHub artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

## Этап 11. Сквозной e2e и демонстрации

Что найдено:

- Проверять только существование Pod недостаточно: `kubectl wait` умеет ждать conditions/JSONPath, а Argo health определяется состоянием непосредственных ресурсов и не всегда наследует здоровье вложенных CR.
- Self-heal происходит только при `automated.selfHeal: true`; auto-prune и allow-empty — отдельные независимые решения.

Зафиксировано:

- Каждый сценарий имеет Arrange/Act/Assert/Cleanup, уникальный test message/id и trap для восстановления обратимого drift.
- Assertions проверяют: Argo child apps, controller readiness, Gateway/HTTPRoute conditions, Deployment rollout revision, `/api/version`, запись в БД, Gatekeeper denial и возвращённое Git-owned поле.
- `make e2e` пишет JUnit-compatible summary и компактный human-readable evidence log без секретов. При ошибке состояние сохраняется как diagnostics artifact, но не kubeconfig/Secrets.

Проверка:

- Все четыре сценария темы проходят дважды подряд на одном кластере; затем clean-cluster run подтверждает воспроизводимость.

Источники:

- [Argo CD automated sync and self-heal](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
- [Argo CD resource health](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/)
- [`kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/)

## Этап 12. Документация и защита

Что найдено:

- GitHub Markdown нативно отображает Mermaid, поэтому архитектурные схемы можно хранить как проверяемый текст рядом с кодом.
- Не все Mermaid diagrams полностью доступны screen readers; смысл схемы необходимо дублировать кратким текстовым описанием.

Зафиксировано:

- Architecture и delivery flow оформляются Mermaid плюс текстовое описание; исходник схемы живёт в Markdown, отдельные бинарные картинки не являются source of truth.
- Все команды quickstart вызывают Make targets, которые реально исполняются в clean-cluster e2e. Документация не содержит второго, непроверенного набора ручных команд.
- Version matrix содержит дату проверки, exact versions/digests, ссылки на compatibility matrix и команду обновления.
- ADR добавляются для двух delivery planes, k3d, Gateway API/Envoy Gateway, Score state и локального CD без runner.

Проверка:

- Markdown links/lint, Mermaid parse check и отдельный clean-machine walkthrough перед защитой.

Источники:

- [GitHub: Creating diagrams](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams)
- [GitHub: Working with non-code files](https://docs.github.com/en/repositories/working-with-files/using-files/working-with-non-code-files)

## Итоговые изменения baseline

Самые значимые изменения после исследования:

1. ingress-nginx заменён на Envoy Gateway + Gateway API из-за завершения поддержки ingress-nginx.
2. Score state теперь сохраняется в зашифрованном Kubernetes Secret и сериализуется между deploy jobs.
3. K3s создаётся с encryption at rest для Secrets.
4. Gatekeeper templates vendored из официальной библиотеки; fail-open trade-off фиксируется явно.
5. Generated manifests применяются через Server-Side Apply без принудительного захвата конфликтующих полей.
6. PostgreSQL chart использует Helm 4 rollback semantics и явную политику сохранения PVC.
7. Release выдаёт SBOM, provenance и проверяемую GitHub attestation; deploy использует image digest.
8. App-of-apps проверяется по каждому child Application и реальному resource status.

Отложенные улучшения не должны незаметно попасть в MVP: TLS/cert-manager, Gatekeeper fail-closed, image signing отдельным keyless cosign workflow, multi-cluster ApplicationSet и managed Score implementation.
