KUDORA_MAX_DEPOSIT_PERIOD ?= 24h
KUDORA_VOTING_PERIOD ?= 24h

PRODUCT_COMPOSE := env KUDORA_E2E_CONTAINER_PREFIX=kudora-localnet KUDORA_E2E_NETWORK=kudora-localnet-chain KUDORA_E2E_STATE_VOLUME=kudora-localnet-state KUDORA_ETH_CHAIN_ID=0x1d4c1 KUDORA_EVM_CHAIN_ID=120001 KUDORA_EVM_RPC_PORT=8545 KUDORA_EVM_WS_PORT=8546 KUDORA_GRPC_PORT=9090 KUDORA_MAX_DEPOSIT_PERIOD=$(KUDORA_MAX_DEPOSIT_PERIOD) KUDORA_MINIMUM_GAS_PRICES=100000000akud KUDORA_REST_PORT=1317 KUDORA_RPC_PORT=26657 KUDORA_VOTING_PERIOD=$(KUDORA_VOTING_PERIOD) docker compose --project-name kudora-localnet --file deploy/e2e/docker-compose.yml

.PHONY: product-accounts product-bootstrap product-build product-config product-down product-fund product-height product-init product-logs product-reset product-seed product-up product-wallets

product-accounts:
	@$(PRODUCT_COMPOSE) run --rm --entrypoint /opt/kudora/e2e/product.sh e2e-business accounts

product-bootstrap:
	@$(PRODUCT_COMPOSE) run --rm --entrypoint /opt/kudora/e2e/product.sh e2e-business bootstrap

product-build:
	@$(MAKE) --no-print-directory e2e-build

product-config:
	@$(PRODUCT_COMPOSE) run --rm --entrypoint /opt/kudora/e2e/product.sh e2e-business public-config

product-down:
	@$(PRODUCT_COMPOSE) down --remove-orphans

product-fund:
	@$(PRODUCT_COMPOSE) run --rm --entrypoint /opt/kudora/e2e/localnet-data.sh e2e-business fund "$(KUDORA_FUND_AMOUNT)"

product-height:
	@$(PRODUCT_COMPOSE) run --rm --entrypoint /opt/kudora/e2e/product.sh e2e-business height

product-init:
	@if ! $(PRODUCT_COMPOSE) run --rm --entrypoint test e2e-init -s /state/metadata.json >/dev/null 2>&1; then \
		$(PRODUCT_COMPOSE) run --rm e2e-init; \
	fi

product-logs:
	@$(PRODUCT_COMPOSE) logs --follow validator-0 validator-1 validator-2

product-reset:
	@$(PRODUCT_COMPOSE) down --volumes --remove-orphans

product-seed:
	@$(PRODUCT_COMPOSE) run --rm --entrypoint /opt/kudora/e2e/localnet-data.sh e2e-business seed

product-up: product-init
	@$(PRODUCT_COMPOSE) up --detach validator-0 validator-1 validator-2
	@$(PRODUCT_COMPOSE) run --rm --entrypoint /opt/kudora/e2e/product.sh e2e-business wait

product-wallets:
	@$(PRODUCT_COMPOSE) run --rm --entrypoint /opt/kudora/e2e/product.sh e2e-business wallets
