# Kudora business end-to-end tests

This environment validates Kudora from a user's point of view. It does not run
unit tests and does not require Go, `jq`, `curl`, or `kudorad` on the host.
Only Docker with Docker Compose and `make` are required.
The Make targets invoke Docker directly and are suitable for GNU Make on
Linux, macOS, and Windows with Docker Desktop. Bash and every other test tool
run inside the test-runner image, not on the host.

Run the complete suite from the repository root:

```sh
make e2e
```

The command builds the images, creates a fresh three-validator network, runs
all business scenarios, tests consensus failures, prints a report, and leaves
the recovered network running for inspection.

## Business scenarios

1. A native Cosmos `akud` transfer from Alice to Bob is committed and the
   recipient balance changes.
2. Alice delegates stake to a validator and the delegation is queryable.
3. An EVM value transfer succeeds, then a Solidity-compatible storage contract
   is deployed, called, and queried.
4. A CosmWasm contract is stored, instantiated, executed, and queried after a
   persisted owner change.
5. A Kudora integrity tenant is registered by Alice and ownership is
   transferred to and accepted by Bob.
6. A governance proposal disables native bank transfers. Validators 0 and 1
   vote YES, validator 2 votes NO, the proposal passes, and a subsequent bank
   transfer is rejected by the enacted rule.
7. Validator 2 (30% power) is stopped and the chain continues. Validator 1 is
   then stopped too (60% total offline) and consensus halts. Both restart and
   the chain resumes.

Validator voting power is intentionally `40/30/30`, allowing the remaining 70%
to keep consensus while proving that the remaining 40% cannot.

## Operational commands

```sh
make e2e-build             # Build the node and test-runner images
make e2e-init              # Create fresh validator state in a Docker volume
make e2e-up                # Start the three validators
make e2e-business          # Run user-facing business scenarios
make e2e-fault-tolerance   # Run one-node/two-node/recovery scenarios
make e2e-report            # Print the persisted result report
make e2e-status            # Show container status
make e2e-logs              # Follow validator logs
make e2e-down              # Stop containers and keep test state
make e2e-reset             # Stop containers and remove test state
```

Node 0 exposes local inspection endpoints:

- CometBFT RPC: `http://localhost:27657`
- Cosmos REST: `http://localhost:27717`
- gRPC: `localhost:29090`
- EVM JSON-RPC: `http://localhost:28545`
- EVM WebSocket: `ws://localhost:28546`

All keys and chain data are generated in the Docker volume
`kudora-e2e-state`. They are disposable local test credentials and are never
written into the repository.
