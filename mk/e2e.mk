E2E_BUILD_CACHE_FROM ?=
E2E_BUILD_CACHE_TO ?=
E2E_COMPOSE := docker compose --project-name kudora-e2e --file deploy/e2e/docker-compose.yml

.PHONY: e2e e2e-build e2e-business e2e-down e2e-fault-tolerance e2e-init e2e-logs e2e-report e2e-reset e2e-status e2e-up

e2e:
	@$(MAKE) --no-print-directory e2e-reset
	@$(MAKE) --no-print-directory e2e-build
	@$(MAKE) --no-print-directory e2e-init
	@$(MAKE) --no-print-directory e2e-up
	@$(MAKE) --no-print-directory e2e-business
	@$(MAKE) --no-print-directory e2e-fault-tolerance
	@$(MAKE) --no-print-directory e2e-report

e2e-build:
	@DOCKER_BUILDKIT=1 docker buildx build --load $(E2E_BUILD_CACHE_FROM) $(E2E_BUILD_CACHE_TO) --tag kudora/kudorad:e2e --file Dockerfile .
	@DOCKER_BUILDKIT=1 docker buildx build --load $(E2E_BUILD_CACHE_FROM) $(E2E_BUILD_CACHE_TO) --target e2e-runner --tag kudora/e2e-runner:local --file Dockerfile .

e2e-business:
	@$(E2E_COMPOSE) run --rm e2e-business

e2e-down:
	@$(E2E_COMPOSE) down --remove-orphans

e2e-fault-tolerance:
	@$(E2E_COMPOSE) stop validator-2
	@$(E2E_COMPOSE) run --rm e2e-fault continues
	@$(E2E_COMPOSE) stop validator-1
	@$(E2E_COMPOSE) run --rm e2e-fault halts
	@$(E2E_COMPOSE) start validator-1 validator-2
	@$(E2E_COMPOSE) run --rm e2e-fault recovers

e2e-init:
	@$(E2E_COMPOSE) run --rm e2e-init

e2e-logs:
	@$(E2E_COMPOSE) logs --follow validator-0 validator-1 validator-2

e2e-report:
	@$(E2E_COMPOSE) run --rm e2e-report

e2e-reset:
	@$(E2E_COMPOSE) down --volumes --remove-orphans

e2e-status:
	@$(E2E_COMPOSE) ps

e2e-up:
	@$(E2E_COMPOSE) up --detach validator-0 validator-1 validator-2
