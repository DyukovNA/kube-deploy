# ADR 0003: Gateway API и Envoy Gateway

Статус: принято, 2026-10-04.

Envoy Gateway управляет GatewayClass и общим Gateway. Gateway API CRD устанавливаются отдельным системным Argo CD Application с одним владельцем. Score provisioner генерирует HTTPRoute в namespace приложения; `/api` направляется в backend, `/` — во frontend.

Готовность определяется conditions `Programmed`, `Accepted` и `ResolvedRefs` плюс HTTP smoke test. Совместимость закреплённых версий проверяется на чистом кластере до принятия этого этапа.
