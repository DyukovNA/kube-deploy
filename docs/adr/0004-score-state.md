# ADR 0004: состояние Score между deploy

Статус: принято, 2026-10-04.

`.score-k8s/state.yaml` переносится между запусками через Kubernetes Secret `score-k8s-state` в namespace `kube-deploy-demo`. Локальная команда deploy восстанавливает state во временную директорию, после успешного применения сохраняет его обратно и удаляет временные файлы. K3s шифрует Secrets в datastore.

State не сохраняется в Git, artifacts и логах. Параллельные deploy отклоняются локальным lock. Повторный deploy обязан сохранять identity ресурсов.
