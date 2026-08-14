#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${KUDORA_E2E_STATE_DIR:-/state}"
CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
DENOM="${KUDORA_DENOM:-akud}"
VALIDATOR_FUNDS="1000000000000000000000${DENOM}"
ALICE_FUNDS="100000000000000000000${DENOM}"
BOB_FUNDS="100000000000000000000${DENOM}"
EVM_FUNDS="500000000000000000000${DENOM}"
VALIDATOR_STAKES=(
  "400000000000000000000${DENOM}"
  "300000000000000000000${DENOM}"
  "300000000000000000000${DENOM}"
)
RUNTIME_UID="${KUDORA_E2E_RUNTIME_UID:-65532}"
RUNTIME_GID="${KUDORA_E2E_RUNTIME_GID:-65532}"

log() {
  printf '[e2e:init] %s\n' "$*"
}

fail() {
  printf '[e2e:init] FAIL: %s\n' "$*" >&2
  exit 1
}

[[ "${STATE_DIR}" == "/state" ]] || fail "state directory must be /state"
find "${STATE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
mkdir -p "${STATE_DIR}/logs" "${STATE_DIR}/results"

declare -a validator_accounts
declare -a validator_operators

for index in 0 1 2; do
  home="${STATE_DIR}/validator${index}"
  key_name="validator${index}"
  mkdir -p "${home}"

  log "Initializing validator ${index}"
  kudorad init "kudora-e2e-validator-${index}" \
    --chain-id "${CHAIN_ID}" \
    --default-denom "${DENOM}" \
    --home "${home}" \
    >"${STATE_DIR}/logs/init-validator-${index}.stdout" \
    2>"${STATE_DIR}/logs/init-validator-${index}.stderr"

  key_json="$(kudorad keys add "${key_name}" \
    --keyring-backend test \
    --keyring-dir "${home}" \
    --home "${home}" \
    --output json \
    2>"${STATE_DIR}/logs/key-validator-${index}.stderr")"
  validator_accounts[${index}]="$(jq -r '.address // empty' <<<"${key_json}")"
  unset key_json

  [[ -n "${validator_accounts[${index}]}" ]] || fail "validator ${index} account address is missing"
  validator_operators[${index}]="$(kudorad keys show "${key_name}" \
    --address \
    --bech val \
    --keyring-backend test \
    --keyring-dir "${home}" \
    --home "${home}" \
    2>"${STATE_DIR}/logs/operator-validator-${index}.stderr")"
  [[ -n "${validator_operators[${index}]}" ]] || fail "validator ${index} operator address is missing"
done

alice_json="$(kudorad keys add alice \
  --keyring-backend test \
  --keyring-dir "${STATE_DIR}/validator0" \
  --home "${STATE_DIR}/validator0" \
  --output json \
  2>"${STATE_DIR}/logs/key-alice.stderr")"
alice_address="$(jq -r '.address // empty' <<<"${alice_json}")"
unset alice_json

bob_json="$(kudorad keys add bob \
  --keyring-backend test \
  --keyring-dir "${STATE_DIR}/validator0" \
  --home "${STATE_DIR}/validator0" \
  --output json \
  2>"${STATE_DIR}/logs/key-bob.stderr")"
bob_address="$(jq -r '.address // empty' <<<"${bob_json}")"
unset bob_json

[[ -n "${alice_address}" ]] || fail "Alice address is missing"
[[ -n "${bob_address}" ]] || fail "Bob address is missing"

kudora-evm-smoke-helper create-account \
  --key-file "${STATE_DIR}/evm-sender.key" \
  --info-file "${STATE_DIR}/evm-sender.json" \
  >"${STATE_DIR}/logs/evm-sender.stdout" \
  2>"${STATE_DIR}/logs/evm-sender.stderr"
evm_cosmos_address="$(jq -r '.cosmos_address // empty' "${STATE_DIR}/evm-sender.json")"
evm_eth_address="$(jq -r '.eth_address // empty' "${STATE_DIR}/evm-sender.json")"
[[ -n "${evm_cosmos_address}" && -n "${evm_eth_address}" ]] || fail "EVM sender address is missing"

canonical_home="${STATE_DIR}/validator0"
for index in 0 1 2; do
  kudorad genesis add-genesis-account \
    "${validator_accounts[${index}]}" \
    "${VALIDATOR_FUNDS}" \
    --home "${canonical_home}" \
    >"${STATE_DIR}/logs/fund-validator-${index}.stdout" \
    2>"${STATE_DIR}/logs/fund-validator-${index}.stderr"
done

kudorad genesis add-genesis-account "${alice_address}" "${ALICE_FUNDS}" \
  --home "${canonical_home}" \
  >"${STATE_DIR}/logs/fund-alice.stdout" 2>"${STATE_DIR}/logs/fund-alice.stderr"
kudorad genesis add-genesis-account "${bob_address}" "${BOB_FUNDS}" \
  --home "${canonical_home}" \
  >"${STATE_DIR}/logs/fund-bob.stdout" 2>"${STATE_DIR}/logs/fund-bob.stderr"
kudorad genesis add-genesis-account "${evm_cosmos_address}" "${EVM_FUNDS}" \
  --home "${canonical_home}" \
  >"${STATE_DIR}/logs/fund-evm.stdout" 2>"${STATE_DIR}/logs/fund-evm.stderr"

for index in 1 2; do
  cp "${canonical_home}/config/genesis.json" "${STATE_DIR}/validator${index}/config/genesis.json"
done

for index in 0 1 2; do
  home="${STATE_DIR}/validator${index}"
  kudorad genesis gentx "validator${index}" "${VALIDATOR_STAKES[${index}]}" \
    --chain-id "${CHAIN_ID}" \
    --home "${home}" \
    --keyring-backend test \
    --keyring-dir "${home}" \
    >"${STATE_DIR}/logs/gentx-validator-${index}.stdout" \
    2>"${STATE_DIR}/logs/gentx-validator-${index}.stderr"
done

for index in 1 2; do
  cp "${STATE_DIR}/validator${index}/config/gentx/"*.json "${canonical_home}/config/gentx/"
done
kudorad genesis collect-gentxs \
  --home "${canonical_home}" \
  >"${STATE_DIR}/logs/collect-gentxs.stdout" \
  2>"${STATE_DIR}/logs/collect-gentxs.stderr"

genesis="${canonical_home}/config/genesis.json"
jq \
  --arg denom "${DENOM}" \
  --arg alice "${alice_address}" \
  '
    .app_state.gov.params.min_deposit = [{denom: $denom, amount: "1000000000000000000"}]
    | .app_state.gov.params.expedited_min_deposit = [{denom: $denom, amount: "2000000000000000000"}]
    | .app_state.gov.params.expedited_voting_period = "10s"
    | .app_state.gov.params.max_deposit_period = "15s"
    | .app_state.gov.params.voting_period = "15s"
    | .app_state.gov.params.quorum = "0.334000000000000000"
    | .app_state.gov.params.threshold = "0.500000000000000000"
    | .app_state.gov.params.veto_threshold = "0.334000000000000000"
    | .app_state.slashing.params.signed_blocks_window = "1000"
    | .app_state.slashing.params.min_signed_per_window = "0.100000000000000000"
    | .app_state.wasm.params.code_upload_access = {permission: "AnyOfAddresses", addresses: [$alice]}
    | .app_state.wasm.params.instantiate_default_permission = "AnyOfAddresses"
  ' "${genesis}" >"${genesis}.tmp"
mv "${genesis}.tmp" "${genesis}"

for index in 1 2; do
  cp "${genesis}" "${STATE_DIR}/validator${index}/config/genesis.json"
done

declare -a node_ids
for index in 0 1 2; do
  node_ids[${index}]="$(kudorad comet show-node-id --home "${STATE_DIR}/validator${index}" 2>"${STATE_DIR}/logs/node-id-${index}.stderr")"
  [[ -n "${node_ids[${index}]}" ]] || fail "validator ${index} node ID is missing"
done

for index in 0 1 2; do
  home="${STATE_DIR}/validator${index}"
  peers=""
  for peer_index in 0 1 2; do
    if [[ "${peer_index}" != "${index}" ]]; then
      peer="${node_ids[${peer_index}]}@validator-${peer_index}:26656"
      if [[ -z "${peers}" ]]; then
        peers="${peer}"
      else
        peers="${peers},${peer}"
      fi
    fi
  done

  sed -i \
    -e "s|^persistent_peers = .*|persistent_peers = \"${peers}\"|" \
    -e 's|^addr_book_strict = true|addr_book_strict = false|' \
    -e 's|^allow_duplicate_ip = false|allow_duplicate_ip = true|' \
    -e 's|^timeout_propose = .*|timeout_propose = "1s"|' \
    -e 's|^timeout_commit = .*|timeout_commit = "1s"|' \
    "${home}/config/config.toml"

  if [[ "${index}" == "0" ]]; then
    kudorad config set app api.address tcp://0.0.0.0:1317 \
      --home "${home}" \
      >"${STATE_DIR}/logs/config-api.stdout" \
      2>"${STATE_DIR}/logs/config-api.stderr"
  fi
done

kudorad genesis validate \
  --home "${canonical_home}" \
  >"${STATE_DIR}/logs/validate-genesis.stdout" \
  2>"${STATE_DIR}/logs/validate-genesis.stderr"

jq -n \
  --arg chain_id "${CHAIN_ID}" \
  --arg denom "${DENOM}" \
  --arg alice "${alice_address}" \
  --arg bob "${bob_address}" \
  --arg evm_cosmos "${evm_cosmos_address}" \
  --arg evm_eth "${evm_eth_address}" \
  --arg validator0_account "${validator_accounts[0]}" \
  --arg validator1_account "${validator_accounts[1]}" \
  --arg validator2_account "${validator_accounts[2]}" \
  --arg validator0_operator "${validator_operators[0]}" \
  --arg validator1_operator "${validator_operators[1]}" \
  --arg validator2_operator "${validator_operators[2]}" \
  '{
    chain_id: $chain_id,
    denom: $denom,
    users: {
      alice: {key: "alice", address: $alice, home: "/state/validator0"},
      bob: {key: "bob", address: $bob, home: "/state/validator0"},
      evm_sender: {cosmos_address: $evm_cosmos, eth_address: $evm_eth, key_file: "/state/evm-sender.key"}
    },
    validators: [
      {index: 0, key: "validator0", account: $validator0_account, operator: $validator0_operator, home: "/state/validator0", power_percent: 40},
      {index: 1, key: "validator1", account: $validator1_account, operator: $validator1_operator, home: "/state/validator1", power_percent: 30},
      {index: 2, key: "validator2", account: $validator2_account, operator: $validator2_operator, home: "/state/validator2", power_percent: 30}
    ]
  }' >"${STATE_DIR}/metadata.json"

chown -R "${RUNTIME_UID}:${RUNTIME_GID}" \
  "${STATE_DIR}/validator0" \
  "${STATE_DIR}/validator1" \
  "${STATE_DIR}/validator2"

log "PASS: three validators initialized with voting power 40/30/30"
