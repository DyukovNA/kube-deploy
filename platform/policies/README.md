# Политики demo namespace

Три локальных ConstraintTemplate опираются на семантику официальной
[Gatekeeper Library](https://github.com/open-policy-agent/gatekeeper-library/tree/d2b86f87b0c98922d0765f6829bdabd75b3348e5)
(commit `d2b86f87b0c98922d0765f6829bdabd75b3348e5`):
`pod-security-policy/privileged-containers`, `general/containerresources`,
`general/disallowedtags`. Здесь они намеренно упрощены для учебного MVP:
без exemptImages, с поддержкой `@sha256:` в правиле тегов. Это не копии
исходных шаблонов; авторитетная проверка поведения — `make test-policies`.

Constraints распространяются только на Pod в namespace с меткой
`policy.kubedeploy.io/enforced=true`. ExpansionTemplate позволяет тем же
правилам проверять Pod template в Deployment/StatefulSet/DaemonSet.
`make validate-generated` проверяет Score output до применения. При ошибке
политики или недоступности gator deploy обязан остановиться; Gatekeeper
webhook с fail-open не является единственной защитой.
