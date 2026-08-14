#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${KUDORA_E2E_STATE_DIR:-/state}"
CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
DENOM="${KUDORA_DENOM:-akud}"
VALIDATOR_FUNDS="1000000000000000000000${DENOM}"
LOCAL_ACCOUNT_FUNDS="500000000000000000000${DENOM}"
ALICE_PRIVATE_KEY="ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
BOB_PRIVATE_KEY="59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
CAROL_PRIVATE_KEY="5de4111afa1c3b3acad9b40e0cb199eb39ccbd86caeea1eb07bdf2c834bbdca9"
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

for account in alice bob carol; do
  case "${account}" in
    alice) private_key="${ALICE_PRIVATE_KEY}" ;;
    bob) private_key="${BOB_PRIVATE_KEY}" ;;
    carol) private_key="${CAROL_PRIVATE_KEY}" ;;
  esac
  kudora-evm-smoke-helper create-account \
    --private-key "${private_key}" \
    --key-file "${STATE_DIR}/${account}.key" \
    --info-file "${STATE_DIR}/${account}.json" \
    >"${STATE_DIR}/logs/${account}-account.stdout" \
    2>"${STATE_DIR}/logs/${account}-account.stderr"
  printf 'localnet\n' | kudorad keys unsafe-import-eth-key "${account}" "${private_key}" \
    --keyring-backend test \
    --keyring-dir "${STATE_DIR}/validator0" \
    --home "${STATE_DIR}/validator0" \
    >"${STATE_DIR}/logs/key-${account}.stdout" \
    2>"${STATE_DIR}/logs/key-${account}.stderr"
done

alice_address="$(jq -r '.cosmos_address // empty' "${STATE_DIR}/alice.json")"
bob_address="$(jq -r '.cosmos_address // empty' "${STATE_DIR}/bob.json")"
carol_address="$(jq -r '.cosmos_address // empty' "${STATE_DIR}/carol.json")"
alice_eth_address="$(jq -r '.eth_address // empty' "${STATE_DIR}/alice.json")"
bob_eth_address="$(jq -r '.eth_address // empty' "${STATE_DIR}/bob.json")"
carol_eth_address="$(jq -r '.eth_address // empty' "${STATE_DIR}/carol.json")"
[[ -n "${alice_address}" && -n "${bob_address}" && -n "${carol_address}" ]] || fail "local account address is missing"

cp "${STATE_DIR}/alice.key" "${STATE_DIR}/evm-sender.key"
cp "${STATE_DIR}/alice.json" "${STATE_DIR}/evm-sender.json"

canonical_home="${STATE_DIR}/validator0"
for index in 0 1 2; do
  kudorad genesis add-genesis-account \
    "${validator_accounts[${index}]}" \
    "${VALIDATOR_FUNDS}" \
    --home "${canonical_home}" \
    >"${STATE_DIR}/logs/fund-validator-${index}.stdout" \
    2>"${STATE_DIR}/logs/fund-validator-${index}.stderr"
done

kudorad genesis add-genesis-account "${alice_address}" "${LOCAL_ACCOUNT_FUNDS}" \
  --home "${canonical_home}" \
  >"${STATE_DIR}/logs/fund-alice.stdout" 2>"${STATE_DIR}/logs/fund-alice.stderr"
kudorad genesis add-genesis-account "${bob_address}" "${LOCAL_ACCOUNT_FUNDS}" \
  --home "${canonical_home}" \
  >"${STATE_DIR}/logs/fund-bob.stdout" 2>"${STATE_DIR}/logs/fund-bob.stderr"
kudorad genesis add-genesis-account "${carol_address}" "${LOCAL_ACCOUNT_FUNDS}" \
  --home "${canonical_home}" \
  >"${STATE_DIR}/logs/fund-carol.stdout" 2>"${STATE_DIR}/logs/fund-carol.stderr"

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
    --fees "50000000000000${DENOM}" \
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
  --arg max_deposit_period "${KUDORA_MAX_DEPOSIT_PERIOD:-8s}" \
  --arg voting_period "${KUDORA_VOTING_PERIOD:-8s}" \
  '
    .app_state.gov.params.min_deposit = [{denom: $denom, amount: "1000000000000000000"}]
    | .app_state.gov.params.expedited_min_deposit = [{denom: $denom, amount: "2000000000000000000"}]
    | .app_state.gov.params.expedited_voting_period = "5s"
    | .app_state.gov.params.max_deposit_period = $max_deposit_period
    | .app_state.gov.params.voting_period = $voting_period
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
    -e 's|^timeout_propose = .*|timeout_propose = "500ms"|' \
    -e 's|^timeout_commit = .*|timeout_commit = "500ms"|' \
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
  --arg carol "${carol_address}" \
  --arg alice_eth "${alice_eth_address}" \
  --arg bob_eth "${bob_eth_address}" \
  --arg carol_eth "${carol_eth_address}" \
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
      alice: {key: "alice", cosmos_address: $alice, eth_address: $alice_eth, key_file: "/state/alice.key", home: "/state/validator0"},
      bob: {key: "bob", cosmos_address: $bob, eth_address: $bob_eth, key_file: "/state/bob.key", home: "/state/validator0"},
      carol: {key: "carol", cosmos_address: $carol, eth_address: $carol_eth, key_file: "/state/carol.key", home: "/state/validator0"},
      evm_sender: {cosmos_address: $alice, eth_address: $alice_eth, key_file: "/state/evm-sender.key"}
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
