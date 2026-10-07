# Настройки GitHub

Репозиторий: публичный [`DyukovNA/kube-deploy`](https://github.com/DyukovNA/kube-deploy). GitOps URL в root/child Applications совпадает с HTTPS `origin`.

## Защита `main`

Фактически включено 7 октября 2026 года через GitHub Branch Protection API:

- изменения только через pull request;
- branch должна быть актуальна перед merge (`strict=true`);
- обязательный status check `ci-success`;
- правило применяется к administrator;
- linear history;
- запрет force push и удаления branch;
- обязательное разрешение review conversations;
- для solo-owner не требуется approving review (`required_approving_review_count=0`).

Проверка:

```sh
gh api repos/DyukovNA/kube-deploy/branches/main/protection
```

## Actions и Packages

- Глобальные workflow permissions: `contents: read`.
- Только Release publish job получает `packages: write`, `id-token: write`, `attestations: write`.
- PR/fork не получает deploy-доступ или локальный kubeconfig.
- GHCR images публикуются с полным SHA tag, multi-arch manifest, SBOM/provenance и attestation.
- Локальный deploy выполняется только после успешного Release и проверяет digest/attestation.

Dependabot еженедельно проверяет GitHub Actions и npm frontend. Actions остаются закреплены на полном commit SHA; human-readable tag находится в комментарии рядом.
