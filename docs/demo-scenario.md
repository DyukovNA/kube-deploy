# Сценарий проверки и демонстрации

Статус: подготовлен, но сквозной прогон **не выполнен**. Нужны публичный GitHub remote, успешный release в GHCR и `Synced/Healthy` дочерние приложения Argo CD. Все команды запускаются с Mac из корня репозитория; kubeconfig и токены не публикуются.

Перед началом: `make doctor`, `git status --short` (пусто), `kubectl config current-context` (`k3d-kube-deploy`), `make bootstrap`. Дождаться завершения release workflow для текущего `main` и записать полный SHA: `git rev-parse HEAD`. Не подставлять произвольный тег или локально собранный образ вместо GHCR release.

## 1. Первое развёртывание

Запустить `make deploy IMAGE_TAG=sha-<полный_SHA>`. Команда проверяет digest и attestation двух образов, поднимает PostgreSQL, генерирует Score-манифесты, проверяет политики и применяет ресурсы. Ожидается `Deployed sha-...`, две готовые Deployment, Gateway с `Programmed=True`, два HTTPRoute с `Accepted=True` и `ResolvedRefs=True`. Дополнительно: `make smoke`; он проверяет страницу, API, версию и запись/чтение через PostgreSQL. Проверить `kubectl --context k3d-kube-deploy -n kube-deploy-demo get deployments,pods,httproutes,pvc`.

## 2. Обновление без потери данных

Зафиксировать ID и текст сообщения, созданного smoke-проверкой, либо создать своё через UI. Сделать отдельный контролируемый commit приложения, отправить его в `main` через обычный PR и дождаться нового release. Запустить `make deploy IMAGE_TAG=sha-<новый_полный_SHA>`. Ожидается новая версия в `/api/version`, успешный rollout и наличие старого сообщения в `/api/messages`; PVC и имя `data-demo-postgres-0` остаются прежними. Этот шаг специально требует второго выпуска и пока не может быть подтверждён локальными unit-тестами.

## 3. Блокировка запрещённой конфигурации

Локально запустить `make test-policies`: negative fixtures с `latest`, образом без тега, отсутствующими limits и privileged-контейнерами должны быть отклонены. После готовности Gatekeeper проверить admission без создания ресурса: `kubectl --context k3d-kube-deploy apply --dry-run=server -f platform/policies/tests/privileged-deployment.yaml` должен завершиться ошибкой policy webhook. Аналогично проверить `latest.yaml` и `no-resources.yaml`. Отрицательный exit code — ожидаемый результат; отсутствие webhook или ошибка соединения не считается подтверждением policy.

## 4. Самовосстановление системного слоя

Запомнить текущий образ Deployment контроллера Envoy: `kubectl --context k3d-kube-deploy -n envoy-gateway-system get deployment envoy-gateway -o jsonpath='{.spec.template.spec.containers[0].image}'`. Выполнить безопасный для демонстрации drift: `kubectl --context k3d-kube-deploy -n envoy-gateway-system annotate deployment/envoy-gateway kubedeploy.io/drift-probe=temporary --overwrite`. Argo CD должен вернуть Application `kube-deploy-envoy-gateway` в `Synced/Healthy` и удалить аннотацию из живого Deployment. Если chart определяет другой live-объект или аннотация не управляется Git, выбрать поле из рендеренного Helm-манифеста и сначала проверить, что восстановление не прервёт маршрутизацию; не удалять namespace, PVC или Secret ради демонстрации.

Для каждого шага сохранить время, SHA, команды, exit code и обезличенные выводы в отдельный evidence-файл после фактического прогона. Не сохранять kubeconfig, значения Secret, содержимое Score state и токены. Пока шаги 1–4 не пройдены, этот файл является инструкцией, а не свидетельством выполнения.
