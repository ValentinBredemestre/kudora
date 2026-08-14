.PHONY: localnet-down localnet-init localnet-logs localnet-reset localnet-smoke-test localnet-up localnet-wait

localnet-down:
	@./deploy/localnet/scripts/reset-localnet.sh --keep-state

localnet-init:
	@$(DEVTOOLS_SCRIPT) run env KUDORA_IN_DOCKER=1 ./deploy/localnet/scripts/init-localnet.sh

localnet-logs:
	@./deploy/localnet/scripts/start-localnet.sh --logs

localnet-reset:
	@./deploy/localnet/scripts/reset-localnet.sh

localnet-smoke-test:
	@$(DEVTOOLS_SCRIPT) run bash -lc 'make build >/dev/null && ./scripts/with-wasmvm.sh env KUDORA_IN_DOCKER=1 ./deploy/localnet/scripts/smoke-localnet.sh'

localnet-up:
	@./deploy/localnet/scripts/start-localnet.sh

localnet-wait:
	@$(DEVTOOLS_SCRIPT) run env KUDORA_IN_DOCKER=1 ./deploy/localnet/scripts/wait-localnet.sh
