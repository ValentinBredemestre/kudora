# Kudora

Cosmos SDK blockchain with EVM, CosmWasm, and the Kudora `x/integrity` and
`x/discussion` business modules.

Requirements: Docker, Docker Compose, and Make.

## Business E2E

```sh
make e2e
```

This starts three validators and validates Cosmos transfers, staking,
governance, EVM, CosmWasm, integrity ownership, consensus halt, and recovery.

The parent Kudora workspace adds the real frontend and browser business E2E on
top of this suite. Run `make localnet` or `make e2e` from that workspace root.

```sh
make e2e-status
make e2e-down
```

## Local stack

```sh
make localnet-up
make explorers-up
make monitoring-up
```

## Candidate release

```sh
make mainnet-genesis-build
make mainnet-genesis-validate
make release-package
make release-verify
```

Run `make help` for the other lifecycle commands. Go `1.26.4` is only
required for native development; the E2E suite is fully Dockerized.
