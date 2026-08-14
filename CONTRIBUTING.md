# Contributing to Kudora

Kudora follows official Cosmos protocol implementations and concentrates its
own code on business features. Contributions should extend Kudora at the
application or module layer without creating local forks of Cosmos SDK, Cosmos
EVM, CometBFT, Wasmd, wasmvm, or IBC-Go.

## Prerequisites

- Git
- Make
- Docker with Docker Compose
- Go only for host-side development; use the exact version declared in
  `go.mod`

## Setup

```sh
git clone https://github.com/Kudora-Labs/kudora.git
cd kudora
make e2e
```

`make e2e` is the portable contributor acceptance test. It builds the chain in
Docker, starts three validators, and exercises native transfers, staking, EVM
and CosmWasm contracts, governance, the Kudora integrity module, consensus
halt, and recovery. No host Go installation is needed for this path.

## Development rules

- Put Kudora business modules under `x/` and wire them through the standard
  Cosmos SDK application APIs in `app/`.
- Do not copy or patch upstream protocol code locally.
- Keep the dependency tuple documented in
  `docs/release/dependency-baseline.md`; upgrades must stay on a combination
  supported by the official upstream projects.
- Do not activate IBC product flows or stateful EVM precompiles implicitly.
  These surfaces require an explicit design and security review.
- Never commit mnemonics, validator keys, node keys, private keys, `.env`
  files, local chain state, or generated release artifacts.
- Add end-to-end coverage for user-visible behavior. Unit tests may protect
  implementation details but do not replace the business acceptance suite.

## Checks

Run the complete user-facing acceptance suite:

```sh
make e2e
```

Useful focused checks include:

```sh
make verify-no-forks
make verify-no-secrets
make dependency-audit
make docker-build
make docker-smoke-test
```

For host-side Go changes, also run `make test` and `make lint` when Go is
installed. Pull requests should describe the behavior changed, the dependency
impact, and the exact commands used for validation.

## Pull requests

Use a clear conventional title such as `feat: add settlement policy` or
`fix: reject invalid integrity ownership transfer`. Keep changes scoped,
document security-sensitive decisions, and link the issue or business need
that motivated the change.
