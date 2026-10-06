# Архитектура

## Границы ответственности

| Слой | Источник истины | Инструмент применения | Ресурсы |
|---|---|---|---|
| Bootstrap | Git checkout на Mac | Kustomize + `kubectl apply --server-side` | Argo CD controller и root Application |
| Системный GitOps | `platform/clusters/local` | Argo CD | namespaces, AppProject, child Applications, Gateway, Gatekeeper policies |
| Готовые системные пакеты | закреплённые OCI/Helm charts | Helm через Argo CD | Gateway API CRD, Envoy Gateway, Gatekeeper |
| Пользовательские workload | `platform/score/*.yaml` | `score-k8s` + локальный CD | frontend/backend Deployment, Service и HTTPRoute |
| Stateful data | локальный chart `apps/postgres-chart` | Helm 4 с Mac | PostgreSQL StatefulSet, Service и PVC |

Gateway API CRD имеет одного владельца — отдельный Argo Application `kube-deploy-envoy-crds`; chart контроллера запускается с `crds.enabled=false`. Это устраняет гонку владельцев CRD.

## Поток доставки

1. Push/PR запускает CI: тесты, lint, рендер Score/Kustomize/Helm и policy validation.
2. Push в `main` запускает Release: повторную проверку, Trivy gate, multi-arch build, публикацию SHA-tag в GHCR, SBOM/provenance и GitHub attestation.
3. На Mac `make deploy IMAGE_TAG=sha-<40 hex>` связывает checkout, `origin/main`, image digest и attestation с одним commit.
4. Score state восстанавливается из Secret, манифесты генерируются во временном каталоге, проверяются kubeconform/gator и server-side dry-run, затем применяются SSA manager `kubedeploy-score`.
5. Envoy Gateway обслуживает `/` с frontend и более специфичный `/api` с backend на host `kube-deploy.local`.

## Состояние и секреты

- PostgreSQL data хранится на PVC `data-demo-postgres-0` с retention `Retain`.
- Пароль создаётся один раз локально и хранится только в Kubernetes Secret; Helm upgrade его не генерирует заново.
- `.score-k8s/state.yaml` переносится через Secret `score-k8s-state`, не попадает в Git или Actions artifacts.
- K3s secrets encryption включён при создании кластера.

## Почему нет Istio и Cilium

Для одного локального кластера не нужны service mesh, mTLS между сервисами, сложная traffic policy или замена CNI. Envoy Gateway закрывает north-south routing, а стандартный K3s networking достаточен. Добавление Istio/Cilium увеличило бы требования к RAM и область отказа, не закрывая обязательные требования темы.
