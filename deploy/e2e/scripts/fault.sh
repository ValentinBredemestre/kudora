#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${KUDORA_E2E_STATE_DIR:-/state}"
SUMMARY="${STATE_DIR}/results/summary.json"
COMET_RPC="${KUDORA_RPC_URL:-http://validator-0:26657}"
MODE="${1:-}"

log() {
  printf '[e2e:fault] %s\n' "$*"
}

fail() {
  printf '[e2e:fault] FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "${SUMMARY}" ]] || fail "business summary is missing; run make e2e-business"

height() {
  curl -sf "${COMET_RPC}/status" | jq -er '.result.sync_info.latest_block_height | tonumber'
}

update_summary() {
  local filter="$1"
  shift
  jq "$@" "${filter}" "${SUMMARY}" >"${SUMMARY}.tmp"
  mv "${SUMMARY}.tmp" "${SUMMARY}"
}

case "${MODE}" in
  continues)
    before="$(height)"
    after="${before}"
    for _ in $(seq 1 30); do
      sleep 1
      after="$(height)"
      if (( after > before )); then
        break
      fi
    done
    (( after > before )) || fail "the chain stopped after one 30% validator went down"
    update_summary \
      '.fault_tolerance.one_validator_down = {status: "PASS", stopped_power_percent: 30, height_before: $before, height_after: $after}' \
      --argjson before "${before}" --argjson after "${after}"
    log "PASS: one validator down, chain advanced ${before}->${after}"
    ;;

  halts)
    sleep 2
    before="$(height)"
    sleep 4
    after="$(height)"
    [[ "${after}" == "${before}" ]] || fail "the chain still produced blocks with 60% of voting power offline (${before}->${after})"
    update_summary \
      '.fault_tolerance.two_validators_down = {status: "PASS", stopped_power_percent: 60, stable_height: $height}' \
      --argjson height "${after}"
    log "PASS: two validators down, consensus halted at height ${after}"
    ;;

  recovers)
    before="$(height)"
    after="${before}"
    for _ in $(seq 1 45); do
      sleep 1
      after="$(height)"
      if (( after > before )); then
        break
      fi
    done
    (( after > before )) || fail "the chain did not recover after validators restarted"
    update_summary \
      '.fault_tolerance.recovery = {status: "PASS", height_before: $before, height_after: $after}' \
      --argjson before "${before}" --argjson after "${after}"
    log "PASS: validators restarted, chain recovered ${before}->${after}"
    ;;

  *)
    fail "usage: fault.sh continues|halts|recovers"
    ;;
esac
