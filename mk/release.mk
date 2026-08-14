.PHONY: cosmovisor-image-build cosmovisor-layout-verify cosmovisor-smoke-test mainnet-genesis-build mainnet-genesis-inspect-policy mainnet-genesis-inspect-supply mainnet-genesis-validate release-build-binaries release-docker-build release-docker-verify release-package release-verify

cosmovisor-image-build: release-docker-build
	@$(DEVTOOLS_SCRIPT) run ./scripts/release/build-cosmovisor-image.sh

cosmovisor-layout-verify: cosmovisor-image-build
	@$(DEVTOOLS_SCRIPT) run ./scripts/release/verify-cosmovisor-layout.sh

cosmovisor-smoke-test: cosmovisor-image-build
	@$(DEVTOOLS_SCRIPT) run env KUDORA_IN_DOCKER=1 ./deploy/cosmovisor/scripts/smoke-cosmovisor.sh

mainnet-genesis-build:
	@$(DEVTOOLS_SCRIPT) run bash -lc 'make build >/dev/null && ./scripts/with-wasmvm.sh ./scripts/mainnet/build-genesis.sh'

mainnet-genesis-inspect-policy: mainnet-genesis-build
	@$(DEVTOOLS_SCRIPT) run ./scripts/with-wasmvm.sh ./scripts/mainnet/inspect-genesis-policy.sh

mainnet-genesis-inspect-supply: mainnet-genesis-build
	@$(DEVTOOLS_SCRIPT) run ./scripts/with-wasmvm.sh ./scripts/mainnet/inspect-genesis-supply.sh

mainnet-genesis-validate: mainnet-genesis-build
	@$(DEVTOOLS_SCRIPT) run ./scripts/with-wasmvm.sh ./scripts/mainnet/validate-genesis.sh

release-build-binaries: mainnet-genesis-build
	@$(DEVTOOLS_SCRIPT) run env KUDORA_IN_DOCKER=1 ./scripts/release/build-binaries.sh

release-docker-build: release-build-binaries
	@$(DEVTOOLS_SCRIPT) run ./scripts/release/build-docker-image.sh

release-docker-verify: release-docker-build
	@$(DEVTOOLS_SCRIPT) run ./scripts/release/verify-docker-image.sh

release-package: release-build-binaries
	@$(DEVTOOLS_SCRIPT) run ./scripts/release/package-release.sh

release-verify: release-package
	@$(DEVTOOLS_SCRIPT) run ./scripts/release/verify-release.sh
