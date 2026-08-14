#!/usr/bin/env bash

set -euo pipefail

SUMMARY="${KUDORA_E2E_STATE_DIR:-/state}/results/summary.json"

[[ -f "${SUMMARY}" ]] || {
  echo "[e2e:report] FAIL: no summary found; run make e2e" >&2
  exit 1
}

jq -e '
  .network.status == "PASS"
  and .cosmos_transfer.status == "PASS"
  and .staking.status == "PASS"
  and .evm.status == "PASS"
  and .cosmwasm.status == "PASS"
  and .integrity.status == "PASS"
  and .governance.status == "PASS"
  and .fault_tolerance.one_validator_down.status == "PASS"
  and .fault_tolerance.two_validators_down.status == "PASS"
  and .fault_tolerance.recovery.status == "PASS"
' "${SUMMARY}" >/dev/null

echo ""
echo "Kudora business E2E report"
echo "=========================="
jq -r '
  "Chain: \(.chain_id)",
  "Network: PASS (\(.network.validators) validators, power \(.network.voting_power_percent | join("/")))",
  "Cosmos transfer: \(.cosmos_transfer.status) (\(.cosmos_transfer.tx_hash))",
  "Staking delegation: \(.staking.status) (\(.staking.tx_hash))",
  "EVM transfer + contract: \(.evm.status) (\(.evm.contract_address))",
  "CosmWasm lifecycle: \(.cosmwasm.status) (\(.cosmwasm.contract_address))",
  "Kudora integrity ownership: \(.integrity.status)",
  "Governance: \(.governance.status) (proposal \(.governance.proposal_id), 2 YES / 1 NO, rule enacted)",
  "One validator down: \(.fault_tolerance.one_validator_down.status) (chain continued)",
  "Two validators down: \(.fault_tolerance.two_validators_down.status) (chain halted)",
  "Recovery: \(.fault_tolerance.recovery.status) (chain resumed)"
' "${SUMMARY}"
echo "=========================="
echo "Kudora E2E: PASS"
