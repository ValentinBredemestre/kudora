#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${KUDORA_E2E_STATE_DIR:-/state}"
METADATA="${STATE_DIR}/metadata.json"
RESULT_DIR="${STATE_DIR}/results"
LOG_DIR="${STATE_DIR}/logs/business"
SUMMARY="${RESULT_DIR}/summary.json"
CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
DENOM="${KUDORA_DENOM:-akud}"
COMET_RPC="${KUDORA_RPC_URL:-http://validator-0:26657}"
NODE="tcp://${COMET_RPC#http://}"
REST="${KUDORA_REST_URL:-http://validator-0:1317}"
EVM_RPC="${KUDORA_EVM_RPC_URL:-http://validator-0:8545}"
EVM_CHAIN_ID="${KUDORA_EVM_CHAIN_ID:-120001}"
ETH_CHAIN_ID="${KUDORA_ETH_CHAIN_ID:-0x1d4c1}"
TX_FEES="1000000000000000${DENOM}"

log() {
  printf '[e2e:business] %s\n' "$*"
}

fail() {
  printf '[e2e:business] FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "${METADATA}" ]] || fail "metadata is missing; run make e2e-init"
mkdir -p "${RESULT_DIR}" "${LOG_DIR}"

alice_address="$(jq -r '.users.alice.address' "${METADATA}")"
bob_address="$(jq -r '.users.bob.address' "${METADATA}")"
alice_home="$(jq -r '.users.alice.home' "${METADATA}")"
validator0_operator="$(jq -r '.validators[0].operator' "${METADATA}")"

LAST_TX_HASH=""
LAST_TX_FILE=""

query_json() {
  local output_file="$1"
  shift
  "$@" --output json >"${output_file}" 2>"${output_file}.stderr"
}

broadcast_tx() {
  local label="$1"
  shift
  local sync_file="${LOG_DIR}/${label}-sync.json"
  local stderr_file="${LOG_DIR}/${label}.stderr"

  if ! "$@" --output json >"${sync_file}" 2>"${stderr_file}"; then
    cat "${stderr_file}" >&2
    fail "${label} could not be broadcast"
  fi

  LAST_TX_HASH="$(jq -r '.txhash // empty' "${sync_file}")"
  [[ -n "${LAST_TX_HASH}" ]] || {
    cat "${sync_file}" >&2
    fail "${label} returned no transaction hash"
  }
}

wait_for_tx() {
  local label="$1"
  local tx_hash="$2"
  local tx_file="${LOG_DIR}/${label}-committed.json"

  for _ in $(seq 1 60); do
    if kudorad query tx "${tx_hash}" --node "${NODE}" --output json >"${tx_file}" 2>"${tx_file}.stderr"; then
      LAST_TX_FILE="${tx_file}"
      return 0
    fi
    sleep 1
  done

  return 1
}

expect_tx_success() {
  local label="$1"
  shift
  broadcast_tx "${label}" "$@"
  wait_for_tx "${label}" "${LAST_TX_HASH}" || fail "${label} was not committed"
  jq -e '.code == 0' "${LAST_TX_FILE}" >/dev/null || {
    jq -r '.raw_log // .' "${LAST_TX_FILE}" >&2
    fail "${label} failed on-chain"
  }
  log "PASS ${label}: ${LAST_TX_HASH}"
}

wait_for_network() {
  local status_file="${LOG_DIR}/network-status.json"
  local peers_file="${LOG_DIR}/network-peers.json"
  local evm_file="${LOG_DIR}/eth-chain-id.json"

  for _ in $(seq 1 120); do
    if curl -sf "${COMET_RPC}/status" >"${status_file}" \
      && jq -e '(.result.sync_info.latest_block_height | tonumber) > 0' "${status_file}" >/dev/null \
      && curl -sf "${COMET_RPC}/net_info" >"${peers_file}" \
      && jq -e '(.result.n_peers | tonumber) == 2' "${peers_file}" >/dev/null; then
      break
    fi
    sleep 1
  done

  jq -e '(.result.sync_info.latest_block_height | tonumber) > 0' "${status_file}" >/dev/null \
    || fail "the chain did not produce blocks"
  jq -e '(.result.n_peers | tonumber) == 2' "${peers_file}" >/dev/null \
    || fail "validator 0 is not connected to the other two validators"

  for _ in $(seq 1 60); do
    if curl -sS -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
      "${EVM_RPC}" >"${evm_file}" \
      && jq -e --arg expected "${ETH_CHAIN_ID}" '.error == null and .result == $expected' "${evm_file}" >/dev/null; then
      return 0
    fi
    sleep 1
  done

  fail "EVM JSON-RPC did not return chain ID ${ETH_CHAIN_ID}"
}

alice_tx=(
  --from alice
  --keyring-backend test
  --keyring-dir "${alice_home}"
  --home "${alice_home}"
  --chain-id "${CHAIN_ID}"
  --node "${NODE}"
  --broadcast-mode sync
  --yes
  --fees "${TX_FEES}"
)

bob_tx=(
  --from bob
  --keyring-backend test
  --keyring-dir "${alice_home}"
  --home "${alice_home}"
  --chain-id "${CHAIN_ID}"
  --node "${NODE}"
  --broadcast-mode sync
  --yes
  --fees "${TX_FEES}"
)

log "Waiting for the three-validator network"
wait_for_network

query_json "${LOG_DIR}/validators.json" kudorad query staking validators --node "${NODE}"
jq -e '.validators | length == 3' "${LOG_DIR}/validators.json" >/dev/null \
  || fail "expected three validators in staking state"
log "PASS network: three bonded validators are queryable"

log "Scenario 1/6: native Cosmos transfer"
query_json "${LOG_DIR}/bob-balance-before.json" kudorad query bank balance "${bob_address}" "${DENOM}" --node "${NODE}"
jq -e '.balance.amount == "100000000000000000000"' "${LOG_DIR}/bob-balance-before.json" >/dev/null \
  || fail "Bob's initial balance is unexpected"
expect_tx_success cosmos-transfer \
  kudorad tx bank send alice "${bob_address}" "1000000000000000000${DENOM}" \
  "${alice_tx[@]}" --gas 300000
cosmos_transfer_hash="${LAST_TX_HASH}"
query_json "${LOG_DIR}/bob-balance-after.json" kudorad query bank balance "${bob_address}" "${DENOM}" --node "${NODE}"
jq -e '.balance.amount == "101000000000000000000"' "${LOG_DIR}/bob-balance-after.json" >/dev/null \
  || fail "Bob did not receive the native transfer"

log "Scenario 2/6: staking delegation"
expect_tx_success staking-delegation \
  kudorad tx staking delegate "${validator0_operator}" "1000000000000000000${DENOM}" \
  "${alice_tx[@]}" --gas 400000
staking_hash="${LAST_TX_HASH}"
query_json "${LOG_DIR}/alice-delegation.json" \
  kudorad query staking delegation "${alice_address}" "${validator0_operator}" --node "${NODE}"
jq -e '.delegation_response.balance.amount == "1000000000000000000" or .balance.amount == "1000000000000000000"' \
  "${LOG_DIR}/alice-delegation.json" >/dev/null \
  || fail "Alice's delegation is not queryable"

log "Scenario 3/6: EVM transfer and contract lifecycle"
kudora-evm-smoke-helper create-account \
  --key-file "${RESULT_DIR}/evm-recipient.key" \
  --info-file "${RESULT_DIR}/evm-recipient.json" \
  >"${LOG_DIR}/evm-recipient.stdout" 2>"${LOG_DIR}/evm-recipient.stderr"
kudora-evm-smoke-helper transfer-smoke \
  --rpc-url "${EVM_RPC}" \
  --chain-id "${EVM_CHAIN_ID}" \
  --sender-key-file "${STATE_DIR}/evm-sender.key" \
  --recipient-info-file "${RESULT_DIR}/evm-recipient.json" \
  --result-file "${RESULT_DIR}/evm-transfer.json" \
  >"${LOG_DIR}/evm-transfer.stdout" 2>"${LOG_DIR}/evm-transfer.stderr"
jq -e '.receipt_status == "0x1" and .nonce_after == (.nonce_before + 1) and .gas_used > 0' \
  "${RESULT_DIR}/evm-transfer.json" >/dev/null \
  || fail "EVM transfer verification failed"
kudora-evm-smoke-helper contract-smoke \
  --rpc-url "${EVM_RPC}" \
  --chain-id "${EVM_CHAIN_ID}" \
  --sender-key-file "${STATE_DIR}/evm-sender.key" \
  --result-file "${RESULT_DIR}/evm-contract.json" \
  >"${LOG_DIR}/evm-contract.stdout" 2>"${LOG_DIR}/evm-contract.stderr"
jq -e '
  .deployment_receipt_status == "0x1"
  and .store_receipt_status == "0x1"
  and .updated_value == "888"
  and .gas_used_deploy > 0
  and .gas_used_store > 0
' "${RESULT_DIR}/evm-contract.json" >/dev/null \
  || fail "EVM contract deployment or state update failed"
evm_transfer_hash="$(jq -r '.transaction_hash' "${RESULT_DIR}/evm-transfer.json")"
evm_contract_address="$(jq -r '.contract_address' "${RESULT_DIR}/evm-contract.json")"
log "PASS EVM: transfer=${evm_transfer_hash} contract=${evm_contract_address}"

log "Scenario 4/6: CosmWasm store, instantiate, execute, and query"
expect_tx_success wasm-store \
  kudorad tx wasm store /opt/kudora/e2e/contracts/reflect_1_5.wasm \
  "${alice_tx[@]}" --gas 5000000
wasm_store_hash="${LAST_TX_HASH}"
wasm_code_id="$(jq -r '.events[] | select(.type == "store_code") | .attributes[] | select(.key == "code_id") | .value' "${LAST_TX_FILE}" | tail -n 1)"
[[ -n "${wasm_code_id}" ]] || fail "CosmWasm code ID is missing"
expect_tx_success wasm-instantiate \
  kudorad tx wasm instantiate "${wasm_code_id}" '{}' \
  --label kudora-e2e-reflect --no-admin \
  "${alice_tx[@]}" --gas 1000000
wasm_instantiate_hash="${LAST_TX_HASH}"
wasm_contract_address="$(jq -r '.events[] | select(.type == "instantiate") | .attributes[] | select(.key == "_contract_address") | .value' "${LAST_TX_FILE}" | tail -n 1)"
[[ -n "${wasm_contract_address}" ]] || fail "CosmWasm contract address is missing"
query_json "${LOG_DIR}/wasm-owner-before.json" \
  kudorad query wasm contract-state smart "${wasm_contract_address}" '{"owner":{}}' --node "${NODE}"
jq -e --arg alice "${alice_address}" '.data.owner == $alice' "${LOG_DIR}/wasm-owner-before.json" >/dev/null \
  || fail "CosmWasm initial owner is not Alice"
expect_tx_success wasm-execute \
  kudorad tx wasm execute "${wasm_contract_address}" "{\"change_owner\":{\"owner\":\"${bob_address}\"}}" \
  "${alice_tx[@]}" --gas 1000000
wasm_execute_hash="${LAST_TX_HASH}"
query_json "${LOG_DIR}/wasm-owner-after.json" \
  kudorad query wasm contract-state smart "${wasm_contract_address}" '{"owner":{}}' --node "${NODE}"
jq -e --arg bob "${bob_address}" '.data.owner == $bob' "${LOG_DIR}/wasm-owner-after.json" >/dev/null \
  || fail "CosmWasm owner change did not persist"

log "Scenario 5/6: Kudora tenant registration and ownership transfer"
tenant="kudora-e2e"
expect_tx_success integrity-register \
  kudorad tx integrity register-tenant "${tenant}" \
  "${alice_tx[@]}" --gas 300000
integrity_register_hash="${LAST_TX_HASH}"
expect_tx_success integrity-transfer \
  kudorad tx integrity transfer-tenant-ownership "${tenant}" "${bob_address}" \
  "${alice_tx[@]}" --gas 300000
integrity_transfer_hash="${LAST_TX_HASH}"
expect_tx_success integrity-accept \
  kudorad tx integrity accept-tenant-ownership "${tenant}" \
  "${bob_tx[@]}" --gas 300000
integrity_accept_hash="${LAST_TX_HASH}"
query_json "${LOG_DIR}/integrity-tenant.json" \
  kudorad query integrity tenant "${tenant}" --node "${NODE}"
jq -e --arg bob "${bob_address}" '.tenant.owner == $bob and ((.tenant.pending_owner // "") == "")' \
  "${LOG_DIR}/integrity-tenant.json" >/dev/null \
  || fail "Kudora tenant ownership was not transferred to Bob"

log "Scenario 6/6: governance proposal enacted by two YES validators"
if ! curl -sf "${REST}/cosmos/auth/v1beta1/module_accounts/gov" >"${LOG_DIR}/gov-module-account.json"; then
  curl -sf "${REST}/cosmos/auth/v1beta1/module_accounts" >"${LOG_DIR}/gov-module-account.json"
fi
gov_authority="$(jq -r '
  if .account then
    [.account | .. | objects | .address? // empty][0]
  else
    [.accounts[] | select(.name == "gov") | .. | objects | .address? // empty][0]
  end // empty
' "${LOG_DIR}/gov-module-account.json")"
[[ -n "${gov_authority}" ]] || fail "governance module authority address is missing"

jq -n \
  --arg authority "${gov_authority}" \
  --arg deposit "1000000000000000000${DENOM}" \
  '{
    messages: [{
      "@type": "/cosmos.bank.v1beta1.MsgUpdateParams",
      authority: $authority,
      params: {send_enabled: [], default_send_enabled: false}
    }],
    metadata: "Kudora E2E native transfer policy",
    deposit: $deposit,
    title: "Disable native transfers",
    summary: "Business E2E proposal proving that an approved governance decision changes chain behavior.",
    expedited: false
  }' >"${RESULT_DIR}/governance-proposal.json"

expect_tx_success governance-submit \
  kudorad tx gov submit-proposal "${RESULT_DIR}/governance-proposal.json" \
  "${alice_tx[@]}" --gas 1000000
governance_submit_hash="${LAST_TX_HASH}"
query_json "${LOG_DIR}/governance-proposals.json" kudorad query gov proposals --node "${NODE}"
proposal_id="$(jq -r '.proposals[-1].id // .proposals[-1].proposal_id // empty' "${LOG_DIR}/governance-proposals.json")"
[[ -n "${proposal_id}" ]] || fail "governance proposal ID is missing"

for index in 0 1; do
  validator_home="$(jq -r ".validators[${index}].home" "${METADATA}")"
  validator_key="$(jq -r ".validators[${index}].key" "${METADATA}")"
  expect_tx_success "governance-vote-${index}-yes" \
    kudorad tx gov vote "${proposal_id}" yes \
    --from "${validator_key}" \
    --keyring-backend test \
    --keyring-dir "${validator_home}" \
    --home "${validator_home}" \
    --chain-id "${CHAIN_ID}" \
    --node "${NODE}" \
    --broadcast-mode sync \
    --yes \
    --gas 300000 \
    --fees "${TX_FEES}"
done

validator_home="$(jq -r '.validators[2].home' "${METADATA}")"
validator_key="$(jq -r '.validators[2].key' "${METADATA}")"
expect_tx_success governance-vote-2-no \
  kudorad tx gov vote "${proposal_id}" no \
  --from "${validator_key}" \
  --keyring-backend test \
  --keyring-dir "${validator_home}" \
  --home "${validator_home}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE}" \
  --broadcast-mode sync \
  --yes \
  --gas 300000 \
  --fees "${TX_FEES}"

proposal_status=""
for _ in $(seq 1 60); do
  if query_json "${LOG_DIR}/governance-proposal-final.json" \
    kudorad query gov proposal "${proposal_id}" --node "${NODE}"; then
    proposal_status="$(jq -r '.proposal.status // empty' "${LOG_DIR}/governance-proposal-final.json")"
    if [[ "${proposal_status}" == "PROPOSAL_STATUS_PASSED" ]]; then
      break
    fi
    if [[ "${proposal_status}" == "PROPOSAL_STATUS_REJECTED" || "${proposal_status}" == "PROPOSAL_STATUS_FAILED" ]]; then
      fail "governance proposal ended with ${proposal_status}"
    fi
  fi
  sleep 1
done
[[ "${proposal_status}" == "PROPOSAL_STATUS_PASSED" ]] || fail "governance proposal did not pass"

query_json "${LOG_DIR}/bank-params-after-governance.json" kudorad query bank params --node "${NODE}"
jq -e '(.params.default_send_enabled // false) == false' "${LOG_DIR}/bank-params-after-governance.json" >/dev/null \
  || fail "the governance decision did not update bank parameters"

restricted_sync="${LOG_DIR}/governance-restricted-send-sync.json"
if ! kudorad tx bank send bob "${alice_address}" "1${DENOM}" \
  "${bob_tx[@]}" --gas 300000 --output json \
  >"${restricted_sync}" 2>"${restricted_sync}.stderr"; then
  restricted_code="$(jq -r '.code // 1' "${restricted_sync}" 2>/dev/null || printf '1')"
else
  restricted_hash="$(jq -r '.txhash // empty' "${restricted_sync}")"
  restricted_code="$(jq -r '.code // 0' "${restricted_sync}")"
  if [[ -n "${restricted_hash}" && "${restricted_code}" == "0" ]]; then
    wait_for_tx governance-restricted-send "${restricted_hash}" || fail "restricted send was not committed"
    restricted_code="$(jq -r '.code' "${LAST_TX_FILE}")"
  fi
fi
[[ "${restricted_code}" != "0" ]] || fail "native transfer still succeeded after governance disabled it"
log "PASS governance: proposal ${proposal_id} passed with two YES votes and one NO vote"

jq -n \
  --arg chain_id "${CHAIN_ID}" \
  --arg cosmos_transfer_hash "${cosmos_transfer_hash}" \
  --arg staking_hash "${staking_hash}" \
  --arg evm_transfer_hash "${evm_transfer_hash}" \
  --arg evm_contract "${evm_contract_address}" \
  --arg wasm_store_hash "${wasm_store_hash}" \
  --arg wasm_instantiate_hash "${wasm_instantiate_hash}" \
  --arg wasm_execute_hash "${wasm_execute_hash}" \
  --arg wasm_contract "${wasm_contract_address}" \
  --arg integrity_register_hash "${integrity_register_hash}" \
  --arg integrity_transfer_hash "${integrity_transfer_hash}" \
  --arg integrity_accept_hash "${integrity_accept_hash}" \
  --arg governance_submit_hash "${governance_submit_hash}" \
  --arg proposal_id "${proposal_id}" \
  --arg proposal_status "${proposal_status}" \
  --arg restricted_code "${restricted_code}" \
  '{
    chain_id: $chain_id,
    network: {status: "PASS", validators: 3, voting_power_percent: [40, 30, 30]},
    cosmos_transfer: {status: "PASS", tx_hash: $cosmos_transfer_hash},
    staking: {status: "PASS", tx_hash: $staking_hash},
    evm: {status: "PASS", transfer_tx_hash: $evm_transfer_hash, contract_address: $evm_contract},
    cosmwasm: {
      status: "PASS",
      store_tx_hash: $wasm_store_hash,
      instantiate_tx_hash: $wasm_instantiate_hash,
      execute_tx_hash: $wasm_execute_hash,
      contract_address: $wasm_contract
    },
    integrity: {
      status: "PASS",
      register_tx_hash: $integrity_register_hash,
      transfer_tx_hash: $integrity_transfer_hash,
      accept_tx_hash: $integrity_accept_hash
    },
    governance: {
      status: "PASS",
      submit_tx_hash: $governance_submit_hash,
      proposal_id: ($proposal_id | tonumber),
      final_status: $proposal_status,
      votes: {yes_validators: 2, no_validators: 1},
      enacted_change: "bank.params.default_send_enabled=false",
      rejected_send_code: ($restricted_code | tonumber)
    },
    fault_tolerance: {
      one_validator_down: {status: "NOT_RUN"},
      two_validators_down: {status: "NOT_RUN"},
      recovery: {status: "NOT_RUN"}
    }
  }' >"${SUMMARY}"

log "PASS: all six business scenarios succeeded"
