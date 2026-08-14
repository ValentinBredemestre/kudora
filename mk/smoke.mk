.PHONY: evm-contract-smoke-test evm-smoke-test evm-transaction-smoke-test integrity-smoke-test wasm-smoke-test

evm-contract-smoke-test:
	@$(DEVTOOLS_SCRIPT) run bash -lc 'make build >/dev/null && ./scripts/evm-contract-smoke-test.sh'

evm-smoke-test:
	@$(DEVTOOLS_SCRIPT) run bash -lc 'make build >/dev/null && ./scripts/evm-smoke-test.sh'

evm-transaction-smoke-test:
	@$(DEVTOOLS_SCRIPT) run bash -lc 'make build >/dev/null && ./scripts/evm-transaction-smoke-test.sh'

integrity-smoke-test:
	@$(DEVTOOLS_SCRIPT) run bash -lc 'make build >/dev/null && ./scripts/with-wasmvm.sh env KUDORA_IN_DOCKER=1 ./scripts/integrity-smoke-test.sh'

wasm-smoke-test:
	@$(DEVTOOLS_SCRIPT) run bash -lc 'make build >/dev/null && ./scripts/with-wasmvm.sh ./scripts/wasm-smoke-test.sh'
