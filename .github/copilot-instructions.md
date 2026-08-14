# Kudora repository instructions

Kudora is a business-focused Cosmos SDK chain with EVM and CosmWasm support.
Keep protocol dependencies on their official upstream repositories; do not add
Kudora-maintained forks or copy upstream protocol code into this repository.

## Current baseline

- Go: read the exact version from `go.mod` and `Dockerfile`.
- Cosmos SDK, Cosmos EVM, CometBFT, Wasmd, wasmvm and IBC-Go: read the exact
  compatible tuple from `go.mod` and `docs/release/dependency-baseline.md`.
- Binary: `kudorad`.
- Chain ID: `kudora_12000-1`.
- Base/display denom: `akud` / `KUD`, with 18 decimals.
- Bech32 prefix: `kudo`.
- Kudora-owned business code lives under `x/`; the active custom module is
  `x/integrity`.
- IBC packages are transitive integration dependencies; Kudora does not yet
  expose a production IBC transfer, relayer, packet-forward, rate-limit, ICA,
  or 08-wasm product flow.

## Development policy

- Prefer official Cosmos APIs and normal application wiring in `app/`.
- Never add a replace directive for Cosmos SDK, Cosmos EVM, CometBFT, Wasmd,
  or wasmvm. The narrowly pinned Cosmos-maintained `go-ethereum` replacement
  required by Cosmos EVM is checked by `scripts/verify-no-forks.sh`.
- Do not add custom precompiles or activate upstream stateful precompiles
  without a separate security review.
- Keep production defaults conservative; local E2E configuration may enable
  JSON-RPC and contract permissions explicitly.
- Do not revive milestone-specific `phase-*-validate` scripts. They were
  removed because they encoded obsolete branches and historical architecture.

## Validation

The contributor acceptance path is fully Dockerized:

```sh
make e2e
```

It creates three validators and validates native transfer, staking, EVM and
CosmWasm contracts, `x/integrity`, governance, quorum loss, and recovery. It
requires only Make, Docker, and Docker Compose on the host. Add new user-facing
business behavior to this suite instead of recreating the removed
Interchaintest scaffold.

Useful focused checks are listed in the root `README.md`. Generated release
manifests and checksums must come from `make release-package`; do not edit or
commit them by hand.
