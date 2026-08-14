.PHONY: monitoring-down monitoring-logs monitoring-reset monitoring-smoke-test monitoring-up

monitoring-down:
	@./deploy/monitoring/scripts/stop-monitoring.sh

monitoring-logs:
	@bash -lc 'source deploy/monitoring/common.sh; monitoring_compose logs -f'

monitoring-reset:
	@./deploy/monitoring/scripts/reset-monitoring.sh

monitoring-smoke-test:
	@$(DEVTOOLS_SCRIPT) run env KUDORA_IN_DOCKER=1 ./deploy/monitoring/scripts/smoke-monitoring.sh

monitoring-up:
	@./deploy/monitoring/scripts/start-monitoring.sh
