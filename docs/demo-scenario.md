# Сценарий проверки и демонстрации

Статус: deploy из чистого кластера, обновление без потери данных, Gatekeeper admission и Argo self-heal фактически пройдены 7 октября 2026 года. Результаты зафиксированы в [`docs/evidence/2026-10-07-e2e.md`](evidence/2026-10-07-e2e.md). Автоматизированный прогон выполняется командой `make e2e IMAGE_TAG=sha-<полный_SHA>` и сохраняет обезличенные log/JUnit в `build/evidence/`.

Перед началом:

```sh
make doctor
git status --short
kubectl config current-context
gh auth token | docker login ghcr.io -u DyukovNA --password-stdin
make cluster-up bootstrap
```

Ожидаются чистый Git status, context `k3d-kube-deploy` и все Argo Application в `Synced/Healthy`.

## 1. Первое развёртывание

```sh
SHA="$(git rev-parse HEAD)"
make deploy IMAGE_TAG="sha-$SHA"
```

Команда проверяет digest и attestation двух образов, поднимает PostgreSQL, восстанавливает Score state, генерирует и валидирует манифесты, выполняет server-side admission/apply и ждёт rollout/Gateway/HTTPRoute. Успех заканчивается `Smoke passed` и `Deployed sha-...`.

```sh
kubectl --context k3d-kube-deploy -n kube-deploy-demo get deployments,pods,httproutes,pvc
```

## 2. Обновление без потери данных

Записать текущее сообщение:

```sh
make smoke REVISION="$(git rev-parse HEAD)"
```

После следующего проверенного commit/release повторить deploy с новым SHA. `/api/version` должен показать новый commit, а прежний `id` остаться в `/api/messages`; PVC `data-demo-postgres-0` и Score-generated resource identities не меняются.

## 3. Блокировка запрещённой конфигурации

```sh
make test-policies
make demo-policy
```

Первая команда проверяет positive/negative fixtures через gator. Вторая выполняет `kubectl apply --dry-run=server` и принимает только явный denial от `validation.gatekeeper.sh` для privileged workload, `latest` и отсутствующих requests/limits. Ошибка соединения с webhook не считается успехом.

## 4. Самовосстановление системного слоя

```sh
make demo-drift
```

Команда проверяет исходный `Synced/Healthy`, временно масштабирует `envoy-gateway` с 1 до 2 replicas и ждёт, пока Argo CD вернёт значение 1. Такой drift относится к управляемому chart-полю и не прерывает маршрут. Лишняя произвольная annotation не используется: она может отсутствовать в desired manifest и потому не считаться drift.

## 5. Полный прогон

```sh
make e2e IMAGE_TAG="sha-$(git rev-parse HEAD)"
```

Последовательность: cluster start/create → Argo bootstrap → provenance-checked deploy + smoke → Gatekeeper admission demo → Argo self-heal. При любом сбое exit code ненулевой, а JUnit содержит failure. Evidence не включает Secret values, Score state, kubeconfig или токены.
