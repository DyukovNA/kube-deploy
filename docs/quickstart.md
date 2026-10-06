# Быстрый старт

## 1. Подготовка

```sh
make doctor
gh auth status
gh auth token | docker login ghcr.io -u DyukovNA --password-stdin
git status --short
```

Ожидается `0 missing/unavailable`, `0 version mismatches` и пустой Git status. Docker Desktop должен выделять около 8 ГиБ RAM. Порты `6445`, `8080` и `8443` должны быть свободны при первом создании кластера.

## 2. Системный слой

```sh
make cluster-up
make bootstrap
kubectl --context k3d-kube-deploy -n argocd get applications
```

`cluster-up` создаёт отсутствующий кластер, запускает остановленный или проверяет работающий. `bootstrap` требует публичный HTTPS `origin`, чистый checkout и текущий commit в `origin/main`.

## 3. Выпуск и deploy

Дождаться успешных CI и Release для текущего `main`, затем:

```sh
SHA="$(git rev-parse HEAD)"
make deploy IMAGE_TAG="sha-$SHA"
```

Успех заканчивается строками `Smoke passed` и `Deployed sha-...`.

## 4. Демонстрация

```sh
make demo-policy
make demo-drift
make smoke REVISION="$(git rev-parse HEAD)"
```

Либо выполнить всё одним запуском:

```sh
make e2e IMAGE_TAG="sha-$(git rev-parse HEAD)"
```

## 5. Остановка

Остановить без удаления данных:

```sh
k3d cluster stop kube-deploy
```

Удалить только учебный кластер и его local-path PVC:

```sh
make cluster-down
```

Удаление необратимо для данных внутри кластера; исходники, GHCR images и GitHub evidence не затрагиваются.
