# Устранение неполадок

## Кластер существует, но API недоступен

`make cluster-up` распознаёт остановленный `kube-deploy` и запускает его. Проверка:

```sh
k3d cluster list
kubectl --context k3d-kube-deploy get nodes
```

## GHCR возвращает 403

Локальный Docker credential может отсутствовать или устареть:

```sh
gh auth status
gh auth token | docker login ghcr.io -u DyukovNA --password-stdin
```

Для другого пользователя private package требует classic PAT с `read:packages`; public GHCR image должен скачиваться анонимно.

## `exec /usr/bin/caddy: operation not permitted`

Причина — `cap_net_bind_service` в upstream Caddy image при Kubernetes `no_new_privs`. Dockerfile проекта снимает ненужную file capability, потому что Caddy слушает 8080. CI запускает image с `--security-opt no-new-privileges --cap-drop ALL`, чтобы ошибка не вернулась.

## HTTP 503 или route не готов

```sh
kubectl --context k3d-kube-deploy -n kube-deploy-system get gateway
kubectl --context k3d-kube-deploy -n kube-deploy-demo get httproutes
kubectl --context k3d-kube-deploy -n kube-deploy-demo get pods
```

Gateway должен иметь `Programmed=True`, оба HTTPRoute — `Accepted=True` и `ResolvedRefs=True`, frontend/backend/PostgreSQL — Ready.

## Policy demo не подтверждён

Ошибка соединения с webhook не является доказательством denial. Запустить `make demo-policy`; команда принимает только ответ `admission webhook "validation.gatekeeper.sh" denied the request` для всех трёх fixtures.

## Argo не устраняет annotation drift

Лишняя annotation может не входить в desired Helm manifest, поэтому Argo считает её неуправляемой. `make demo-drift` использует управляемое и безопасное поле replicas (1 → 2 → 1), не удаляет Deployment и не прерывает маршрут.

## Недостаточно ресурсов

Проверить Docker Desktop memory через `make doctor`. Для полного стека рекомендуется около 8 ГиБ; при нехватке памяти pods получают `Pending`, eviction или долгие rollout timeout.
