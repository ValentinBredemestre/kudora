.PHONY: blockscout-down blockscout-reset blockscout-smoke-test blockscout-up explorers-down explorers-logs explorers-reset explorers-smoke-test explorers-up ping-dashboard-down ping-dashboard-reset ping-dashboard-smoke-test ping-dashboard-up

blockscout-down:
	@./deploy/explorers/blockscout/scripts/stop-blockscout.sh

blockscout-reset:
	@./deploy/explorers/blockscout/scripts/reset-blockscout.sh

blockscout-smoke-test:
	@$(DEVTOOLS_SCRIPT) run env KUDORA_IN_DOCKER=1 ./deploy/explorers/blockscout/scripts/smoke-blockscout.sh

blockscout-up:
	@./deploy/explorers/blockscout/scripts/start-blockscout.sh

explorers-down:
	@./deploy/explorers/ping-dashboard/scripts/stop-ping-dashboard.sh
	@./deploy/explorers/blockscout/scripts/stop-blockscout.sh

explorers-logs:
	@bash -lc 'source deploy/explorers/common.sh; require_compose; COMPOSE_PROJECT_NAME="kudora-explorers" LOCALNET_DOCKER_NETWORK="$$LOCALNET_DOCKER_NETWORK" BLOCKSCOUT_BACKEND_IMAGE="$$BLOCKSCOUT_BACKEND_IMAGE" BLOCKSCOUT_FRONTEND_IMAGE="$$BLOCKSCOUT_FRONTEND_IMAGE" PING_DASHBOARD_IMAGE="$$PING_DASHBOARD_IMAGE" PING_DASHBOARD_UPSTREAM_COMMIT="$$PING_DASHBOARD_UPSTREAM_COMMIT" "$${COMPOSE_CMD[@]}" -f "$$BLOCKSCOUT_COMPOSE_FILE" -f "$$PING_DASHBOARD_COMPOSE_FILE" logs -f'

explorers-reset:
	@./deploy/explorers/ping-dashboard/scripts/reset-ping-dashboard.sh
	@./deploy/explorers/blockscout/scripts/reset-blockscout.sh

explorers-smoke-test:
	@$(MAKE) --no-print-directory blockscout-smoke-test
	@$(MAKE) --no-print-directory ping-dashboard-smoke-test

explorers-up:
	@./deploy/explorers/blockscout/scripts/start-blockscout.sh
	@./deploy/explorers/ping-dashboard/scripts/start-ping-dashboard.sh

ping-dashboard-down:
	@./deploy/explorers/ping-dashboard/scripts/stop-ping-dashboard.sh

ping-dashboard-reset:
	@./deploy/explorers/ping-dashboard/scripts/reset-ping-dashboard.sh

ping-dashboard-smoke-test:
	@$(DEVTOOLS_SCRIPT) run env KUDORA_IN_DOCKER=1 ./deploy/explorers/ping-dashboard/scripts/smoke-ping-dashboard.sh

ping-dashboard-up:
	@./deploy/explorers/ping-dashboard/scripts/start-ping-dashboard.sh
