# Безопасность

## Контроли workload

Gatekeeper применяется только к namespace с label `kubedeploy.io/policy=enabled` и запрещает:

- `securityContext.privileged: true`;
- отсутствие CPU/memory requests или limits;
- `:latest` и image без тега/digest.

Score patch дополнительно включает `runAsNonRoot`, `RuntimeDefault` seccomp, `allowPrivilegeEscalation: false`, `privileged: false`, drop `ALL` capabilities и отключает service-account token. CI проверяет те же policies до доступа к Kubernetes; `make demo-policy` доказывает enforcement admission webhook.

## Цепочка поставки

- base images и Actions закреплены digest/full commit SHA;
- release images имеют immutable SHA tag и развёртываются только по digest;
- Trivy отклоняет исправимые HIGH/CRITICAL приложения;
- BuildKit формирует SBOM/provenance, GitHub Actions — signed attestation;
- локальный deploy проверяет source SHA, branch, signer workflow и digest.

## Секреты

- kubeconfig остаётся на Mac;
- PostgreSQL password и Score state находятся в Kubernetes Secret и не выводятся скриптами;
- временный Score каталог удаляется trap после deploy;
- Secret values, tokens и kubeconfig запрещено сохранять в evidence.

## Остаточные риски

- кластер single-node/local и не является production HA;
- официальный PostgreSQL 17.11 image содержит известные исправимые HIGH в вспомогательном `gosu`; это документированный риск локальной БД, а не исключение для frontend/backend release gate;
- Gatekeeper webhook не переведён в отдельный production fail-closed hardening profile; CI/gator и readiness остаются обязательными дополнительными барьерами;
- Docker Desktop и локальная учётная запись входят в доверенную границу.
