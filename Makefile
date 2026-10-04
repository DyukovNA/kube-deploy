SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help doctor doctor-ci cluster-up argocd-up bootstrap database-up render validate-generated deploy smoke test test-policies test-backend-integration test-backend-container lint

help:
	@printf '%s\n' 'Targets:' '  doctor     Report local prerequisites and pinned version mismatches' '  doctor-ci  Check tools needed for CI validation' '  cluster-up Create or inspect the dedicated k3d cluster' '  argocd-up  Install the pinned Argo CD controller only' '  database-up Install/upgrade PostgreSQL in kube-deploy-demo' '  render     Generate Score manifests from immutable image refs' '  validate-generated  Check generated YAML schemas and policies' '  deploy IMAGE_TAG=sha-...  Verify and deploy a published release' '  smoke      Check routed UI, API, and PostgreSQL persistence' '  test       Run application and policy tests' '  test-policies  Check negative policy fixtures' '  test-backend-integration  Test backend against disposable PostgreSQL' '  test-backend-container  Smoke test backend image with PostgreSQL' '  lint       Run available source checks'

doctor:
	@bash scripts/doctor.sh

doctor-ci:
	@bash scripts/doctor.sh --ci

cluster-up:
	@bash scripts/cluster-up.sh

argocd-up:
	@bash scripts/argocd-up.sh

bootstrap:
	@bash scripts/bootstrap.sh

database-up:
	@bash scripts/database-up.sh

render:
	@FRONTEND_IMAGE='$(FRONTEND_IMAGE)' BACKEND_IMAGE='$(BACKEND_IMAGE)' REVISION='$(REVISION)' bash scripts/render-score.sh

validate-generated:
	@bash scripts/validate-generated.sh

deploy:
	@IMAGE_TAG='$(IMAGE_TAG)' bash scripts/deploy.sh

smoke:
	@REVISION='$(REVISION)' bash scripts/smoke.sh

test:
	@if test -f apps/backend/go.mod; then cd apps/backend && go test ./...; else printf '%s\n' 'Backend not implemented yet'; fi
	@if test -f apps/frontend/package.json; then cd apps/frontend && npm test -- --run; else printf '%s\n' 'Frontend not implemented yet'; fi
	@bash scripts/test-policies.sh

test-policies:
	@bash scripts/test-policies.sh

test-backend-integration:
	@bash scripts/test-backend-integration.sh

test-backend-container:
	@bash scripts/test-backend-container.sh

lint:
	@if test -f apps/backend/go.mod; then cd apps/backend && go vet ./...; else printf '%s\n' 'Backend not implemented yet'; fi
	@if test -f apps/frontend/package.json; then cd apps/frontend && npm run lint; else printf '%s\n' 'Frontend not implemented yet'; fi
	@PATH='$(CURDIR)/.tools/bin:$(PATH)' shellcheck -x -S warning scripts/*.sh
	@yamllint platform cluster apps/postgres-chart/values.yaml apps/postgres-chart/Chart.yaml
	@PATH='$(CURDIR)/.tools/bin:$(PATH)' kustomize build platform/policies >/dev/null
	@PATH='$(CURDIR)/.tools/bin:$(PATH)' kustomize build platform/gateway >/dev/null
	@PATH='$(CURDIR)/.tools/bin:$(PATH)' helm lint apps/postgres-chart
