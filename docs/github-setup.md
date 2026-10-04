# Настройка GitHub перед этапом 4 и выпуском образов

Этот список нужен после появления remote; разработка этапов 0–3 от него не зависит.

- Согласовать owner и видимость репозитория. Текущий bootstrap поддерживает публичный HTTPS GitHub remote; для приватного потребуется отдельно настроить доступ Argo CD к Git и чтение GHCR на кластере.
- Создать репозиторий, настроить `origin`, зафиксировать URL в `platform/clusters/local/repository.yaml` и `platform/bootstrap/root-application.yaml`.
- Защитить `main`: запретить прямой push и force push, требовать PR и обязательный status `ci-success`.
- Ограничить права `GITHUB_TOKEN`; для release открыть `packages: write`, `id-token: write` и `attestations: write` только нужным job.
- Разрешить публикацию GHCR packages и проверить доступность public pull; иначе выбрать namespace-scoped `imagePullSecret`.
- Запретить deploy из PR/fork. Self-hosted runner в MVP отсутствует.
- Проверить, что release публикует образы по SHA и attestation; локальный deploy использует digest.

Проверить настройки GitHub фактически после создания remote: этот файл не заменяет просмотр текущих repository settings.
