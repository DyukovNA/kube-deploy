# Матрица версий

Проверено 2026-10-04 по upstream release pages. Это зафиксированные версии; совместимость всего набора подтвердит только полный clean-cluster e2e. Источники истины для версий: `.tool-versions` для Go/Node и `scripts/versions.env` для платформы.

| Компонент | Версия | Основание |
|---|---|---|
| Go | 1.27.1 | [официальная история выпусков](https://go.dev/doc/devel/release); builder `golang:1.27.1-alpine@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414` |
| Node.js | 22.17.0 | установленный toolchain, `.tool-versions` |
| k3d | 5.9.0 | [upstream release](https://github.com/k3d-io/k3d/releases/tag/v5.9.0) |
| K3s | v1.36.5+k3s1 | [upstream release](https://github.com/k3s-io/k3s/releases/tag/v1.36.5%2Bk3s1); выбран Kubernetes 1.36, чтобы сохранить одного владельца Gateway API CRD |
| kubectl | 1.36.5 | client для выбранного Kubernetes 1.36 |
| Helm | 4.3.0 | [upstream release](https://github.com/helm/helm/releases/tag/v4.3.0) |
| Argo CD | v3.5.3 | [upstream release](https://github.com/argoproj/argo-cd/releases/tag/v3.5.3) |
| Envoy Gateway | v1.9.2 | [upstream release](https://github.com/envoyproxy/gateway/releases/tag/v1.9.2); OCI `gateway-helm` digest `sha256:be034275b55deeddd6b7bc1f4da6eeb02b8efc418a4a29e2b1977851b24b1e63` |
| Envoy Gateway CRD chart | v1.9.2 | OCI `gateway-crds-helm` digest `sha256:940b88fe361cb22fb651e3075f649e9be885f35b1c8a990658c1a2acc2d2a678` |
| Gateway API | v1.6.2 | [upstream release](https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.6.2) |
| Gatekeeper | v3.23.1; chart 3.23.1 | [upstream release](https://github.com/open-policy-agent/gatekeeper/releases/tag/v3.23.1) |
| score-k8s | 0.19.0 | [upstream release](https://github.com/score-spec/score-k8s/releases/tag/0.19.0) |
| Kustomize | 5.8.2 | [upstream release](https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize/v5.8.2) |
| kubeconform | 0.8.0 | [upstream release](https://github.com/yannh/kubeconform/releases/tag/v0.8.0) |
| Trivy | 0.75.0 | [upstream release](https://github.com/aquasecurity/trivy/releases/tag/v0.75.0) |
| Caddy runtime image | 2.11.6-alpine | `sha256:d44355d3c2149dc580ce2cac735955d1c08d3d00882c30489c241aa51a5c10d9`; локальный Trivy 2026-10-05: 0 исправимых HIGH/CRITICAL |
| PostgreSQL image | 17.11-alpine | [официальные release notes](https://www.postgresql.org/docs/17/release-17-11.html); `sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24` |

Рендер Envoy Gateway, Envoy CRD и Gatekeeper charts проходит локальную синтаксическую/schema-проверку; их совместная работа в кластере пока не подтверждена. Argo CD bootstrap зафиксирован на release commit `c9c369efcc5b2a0bd720803f8d14a1c3eaddf579` и уже запущен в локальном кластере. Обновление версии требует повторного e2e. Встроенный `kubectl kustomize` не считается отдельным Kustomize CLI.
