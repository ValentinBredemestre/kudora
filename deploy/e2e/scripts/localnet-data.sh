#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${KUDORA_E2E_STATE_DIR:-/state}"
METADATA="${STATE_DIR}/metadata.json"
RESULT_DIR="${STATE_DIR}/results"
LOG_DIR="${STATE_DIR}/logs/localnet-data"
CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
DENOM="${KUDORA_DENOM:-akud}"
REST="${KUDORA_REST_URL:-http://validator-0:1317}"
RPC="${KUDORA_RPC_URL:-http://validator-0:26657}"
NODE="tcp://${RPC#http://}"
TX_FEES="1000000000000000${DENOM}"
MODE="${1:-}"

log() {
  printf '[localnet:%s] %s\n' "${MODE:-data}" "$*"
}

fail() {
  printf '[localnet:%s] ERROR: %s\n' "${MODE:-data}" "$*" >&2
  exit 1
}

[[ -f "${METADATA}" ]] || fail "localnet is not initialized; run make localnet"
mkdir -p "${RESULT_DIR}" "${LOG_DIR}"

for _ in $(seq 1 60); do
  if curl -sf "${RPC}/status" >/dev/null && curl -sf "${REST}/cosmos/base/tendermint/v1beta1/node_info" >/dev/null; then
    break
  fi
  sleep 1
done
curl -sf "${RPC}/status" >/dev/null || fail "localnet is not running; run make localnet"

to_akud() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+([.][0-9]{1,18})?$ ]] || fail "amount must be a positive KUD number with at most 18 decimals"
  local whole="${value%%.*}"
  local fraction=""
  if [[ "${value}" == *.* ]]; then
    fraction="${value#*.}"
  fi
  while [[ ${#fraction} -lt 18 ]]; do fraction="${fraction}0"; done
  local amount="${whole}${fraction}"
  amount="${amount#${amount%%[!0]*}}"
  printf '%s' "${amount:-0}"
}

LAST_TX_HASH=""
LAST_MESSAGE_ID=""

run_tx() {
  local label="$1"
  shift
  local sync_file="${LOG_DIR}/${label}-sync.json"
  local tx_file="${LOG_DIR}/${label}-committed.json"
  local stderr_file="${LOG_DIR}/${label}.stderr"

  if ! "$@" --output json >"${sync_file}" 2>"${stderr_file}"; then
    cat "${stderr_file}" >&2
    fail "${label} could not be broadcast"
  fi
  LAST_TX_HASH="$(jq -r '.txhash // empty' "${sync_file}")"
  [[ -n "${LAST_TX_HASH}" ]] || fail "${label} returned no transaction hash"

  for _ in $(seq 1 120); do
    if kudorad query tx "${LAST_TX_HASH}" --node "${NODE}" --output json >"${tx_file}" 2>"${tx_file}.stderr"; then
      jq -e '.code == 0' "${tx_file}" >/dev/null || {
        jq -r '.raw_log // .' "${tx_file}" >&2
        fail "${label} failed on-chain"
      }
      return 0
    fi
    sleep 0.2
  done
  fail "${label} was not committed"
}

tx_for() {
  local label="$1"
  local key="$2"
  local home="$3"
  shift 3
  run_tx "${label}" "$@" \
    --from "${key}" \
    --keyring-backend test \
    --keyring-dir "${home}" \
    --home "${home}" \
    --chain-id "${CHAIN_ID}" \
    --node "${NODE}" \
    --broadcast-mode sync \
    --yes \
    --fees "${TX_FEES}"
}

balance_kud() {
  local address="$1"
  local amount
  amount="$(curl -sf "${REST}/cosmos/bank/v1beta1/balances/${address}/by_denom?denom=${DENOM}" | jq -r '.balance.amount // "0"')"
  jq -nr --arg amount "${amount}" '$amount | if length <= 18 then "0." + ("0" * (18 - length)) + . else .[0:-18] + "." + .[-18:] end | sub("[.]?0+$"; "")'
}

fund_wallets() {
  local display_amount="${1:-100}"
  local amount
  amount="$(to_akud "${display_amount}")"
  [[ "${amount}" != "0" ]] || fail "amount must be greater than zero"

  for index in 0 1 2; do
    local account
    case "${index}" in
      0) account="alice" ;;
      1) account="bob" ;;
      2) account="carol" ;;
    esac
    local recipient source_key source_home
    recipient="$(jq -r ".users.${account}.cosmos_address" "${METADATA}")"
    source_key="$(jq -r ".validators[${index}].key" "${METADATA}")"
    source_home="$(jq -r ".validators[${index}].home" "${METADATA}")"
    tx_for "fund-${account}-$(date +%s)" "${source_key}" "${source_home}" \
      kudorad tx bank send "${source_key}" "${recipient}" "${amount}${DENOM}" --gas 300000 --note "Kudora localnet user fund"
    log "${account^}: +${display_amount} KUD, balance $(balance_kud "${recipient}") KUD"
  done
}

account_home="$(jq -r '.users.alice.home' "${METADATA}")"
alice_address="$(jq -r '.users.alice.cosmos_address' "${METADATA}")"
bob_address="$(jq -r '.users.bob.cosmos_address' "${METADATA}")"
carol_address="$(jq -r '.users.carol.cosmos_address' "${METADATA}")"

post_message() {
  local label="$1" proposal_id="$2" parent_id="$3" author="$4" payload="$5" home="${6:-${account_home}}" capture_id="${7:-yes}"
  local encoded
  encoded="$(printf '%s' "${payload}" | base64 -w 0)"
  tx_for "${label}" "${author}" "${home}" \
    kudorad tx discussion post "${proposal_id}" "${parent_id}" "${encoded}" --gas 350000
  if [[ "${capture_id}" == "yes" ]]; then
    LAST_MESSAGE_ID="$(curl -sf "${REST}/kudora/discussion/v1/messages/${proposal_id}?pagination.limit=200" | jq -r '[.messages[].message_id | tonumber] | max // 0')"
  fi
}

seed_account_activity() {
  local marker="${RESULT_DIR}/account-activity-seed-v1.json"
  if [[ -s "${marker}" ]]; then
    log "account activity already exists (3 rewards, 6 payments, 3 moves)"
    return
  fi

  local validator0_key validator0_home validator0_address
  local validator1_key validator1_home validator1_address
  local validator2_key validator2_home
  validator0_key="$(jq -r '.validators[0].key' "${METADATA}")"
  validator0_home="$(jq -r '.validators[0].home' "${METADATA}")"
  validator0_address="$(jq -r '.validators[0].account' "${METADATA}")"
  validator1_key="$(jq -r '.validators[1].key' "${METADATA}")"
  validator1_home="$(jq -r '.validators[1].home' "${METADATA}")"
  validator1_address="$(jq -r '.validators[1].account' "${METADATA}")"
  validator2_key="$(jq -r '.validators[2].key' "${METADATA}")"
  validator2_home="$(jq -r '.validators[2].home' "${METADATA}")"

  log "creating 3 real on-chain airdrop rewards"
  tx_for "activity-reward-alice" "${validator0_key}" "${validator0_home}" \
    kudorad tx bank send "${validator0_key}" "${alice_address}" "$(to_akud 125.5)${DENOM}" --gas 300000 --note "Kudora localnet airdrop reward"
  local reward_alice_hash="${LAST_TX_HASH}"
  tx_for "activity-reward-bob" "${validator1_key}" "${validator1_home}" \
    kudorad tx bank send "${validator1_key}" "${bob_address}" "$(to_akud 95.25)${DENOM}" --gas 300000 --note "Kudora localnet airdrop reward"
  local reward_bob_hash="${LAST_TX_HASH}"
  tx_for "activity-reward-carol" "${validator2_key}" "${validator2_home}" \
    kudorad tx bank send "${validator2_key}" "${carol_address}" "$(to_akud 70.75)${DENOM}" --gas 300000 --note "Kudora localnet airdrop reward"
  local reward_carol_hash="${LAST_TX_HASH}"

  log "creating 6 real payments between users and validators"
  tx_for "activity-alice-bob" alice "${account_home}" \
    kudorad tx bank send alice "${bob_address}" "$(to_akud 18.5)${DENOM}" --gas 300000 --note "Kudora demo payment"
  tx_for "activity-bob-carol" bob "${account_home}" \
    kudorad tx bank send bob "${carol_address}" "$(to_akud 7.25)${DENOM}" --gas 300000 --note "Kudora demo payment"
  tx_for "activity-carol-alice" carol "${account_home}" \
    kudorad tx bank send carol "${alice_address}" "$(to_akud 4.75)${DENOM}" --gas 300000 --note "Kudora demo payment"
  tx_for "activity-bob-alice" bob "${account_home}" \
    kudorad tx bank send bob "${alice_address}" "$(to_akud 2.5)${DENOM}" --gas 300000 --note "Kudora demo payment"
  tx_for "activity-alice-validator" alice "${account_home}" \
    kudorad tx bank send alice "${validator1_address}" "$(to_akud 3)${DENOM}" --gas 300000 --note "Kudora validator support payment"
  tx_for "activity-carol-validator" carol "${account_home}" \
    kudorad tx bank send carol "${validator0_address}" "$(to_akud 1.5)${DENOM}" --gas 300000 --note "Kudora validator support payment"

  log "creating 3 real KUD to MockUSDC moves"
  local deployment="${RESULT_DIR}/swap-deployment.json"
  [[ -s "${deployment}" ]] || fail "local swap is not deployed; run make localnet"
  local swap_alice="${RESULT_DIR}/account-activity-swap-alice.json"
  local swap_bob="${RESULT_DIR}/account-activity-swap-bob.json"
  local swap_carol="${RESULT_DIR}/account-activity-swap-carol.json"
  kudora-evm-smoke-helper swap-smoke --rpc-url "http://validator-0:8545" --chain-id 120001 \
    --sender-key-file "${STATE_DIR}/alice.key" --deployment-file "${deployment}" --result-file "${swap_alice}" --amount-wei "$(to_akud 2)"
  kudora-evm-smoke-helper swap-smoke --rpc-url "http://validator-0:8545" --chain-id 120001 \
    --sender-key-file "${STATE_DIR}/bob.key" --deployment-file "${deployment}" --result-file "${swap_bob}" --amount-wei "$(to_akud 1.25)"
  kudora-evm-smoke-helper swap-smoke --rpc-url "http://validator-0:8545" --chain-id 120001 \
    --sender-key-file "${STATE_DIR}/carol.key" --deployment-file "${deployment}" --result-file "${swap_carol}" --amount-wei "$(to_akud 0.75)"
  jq -e '.receipt_status == "0x1" and .kud_in == "2000000000000000000"' "${swap_alice}" >/dev/null
  jq -e '.receipt_status == "0x1" and .kud_in == "1250000000000000000"' "${swap_bob}" >/dev/null
  jq -e '.receipt_status == "0x1" and .kud_in == "750000000000000000"' "${swap_carol}" >/dev/null

  jq -n \
    --arg reward_alice "${reward_alice_hash}" \
    --arg reward_bob "${reward_bob_hash}" \
    --arg reward_carol "${reward_carol_hash}" \
    --slurpfile swap_alice "${swap_alice}" \
    --slurpfile swap_bob "${swap_bob}" \
    --slurpfile swap_carol "${swap_carol}" \
    '{version:1,rewards:[$reward_alice,$reward_bob,$reward_carol],payments:6,moves:[$swap_alice[0].transaction_hash,$swap_bob[0].transaction_hash,$swap_carol[0].transaction_hash]}' >"${marker}"
  log "account activity ready: 3 rewards, 6 payments, 3 moves"
}

seed_zap_activity() {
  local marker="${RESULT_DIR}/account-zap-seed-v1.json"
  if [[ -s "${marker}" ]]; then
    log "zap activity already exists (3 cross-account zaps)"
    return
  fi

  local -a proposal_ids=()
  mapfile -t proposal_ids < <(curl -sf "${REST}/cosmos/gov/v1/proposals?pagination.limit=3" | jq -r '.proposals[].id')
  [[ ${#proposal_ids[@]} -eq 3 ]] || fail "three seeded proposals are required for zap activity"
  local alice_proposal="${proposal_ids[0]}" bob_proposal="${proposal_ids[1]}" carol_proposal="${proposal_ids[2]}"
  local alice_message bob_message carol_message
  alice_message="$(curl -sf "${REST}/kudora/discussion/v1/messages/${alice_proposal}?pagination.limit=3" | jq -r '.messages[1].message_id // empty')"
  bob_message="$(curl -sf "${REST}/kudora/discussion/v1/messages/${bob_proposal}?pagination.limit=3" | jq -r '.messages[1].message_id // empty')"
  carol_message="$(curl -sf "${REST}/kudora/discussion/v1/messages/${carol_proposal}?pagination.limit=3" | jq -r '.messages[0].message_id // empty')"
  [[ -n "${alice_message}" && -n "${bob_message}" && -n "${carol_message}" ]] || fail "seeded discussion messages were not found for zap activity"

  log "creating 3 real cross-account zaps"
  tx_for "activity-zap-alice-bob" alice "${account_home}" \
    kudorad tx discussion zap "${alice_proposal}" "${alice_message}" "$(to_akud 0.4)" --gas 300000
  local alice_hash="${LAST_TX_HASH}"
  tx_for "activity-zap-bob-carol" bob "${account_home}" \
    kudorad tx discussion zap "${bob_proposal}" "${bob_message}" "$(to_akud 0.3)" --gas 300000
  local bob_hash="${LAST_TX_HASH}"
  tx_for "activity-zap-carol-alice" carol "${account_home}" \
    kudorad tx discussion zap "${carol_proposal}" "${carol_message}" "$(to_akud 0.2)" --gas 300000
  local carol_hash="${LAST_TX_HASH}"

  jq -n --arg alice "${alice_hash}" --arg bob "${bob_hash}" --arg carol "${carol_hash}" \
    '{version:1,zaps:{alice:$alice,bob:$bob,carol:$carol}}' >"${marker}"
  log "zap activity ready: Alice 0.40 KUD, Bob 0.30 KUD, Carol 0.20 KUD"
}

seed_demo() {
  local marker="${RESULT_DIR}/demo-seed.json"
  if [[ -s "${marker}" ]]; then
    seed_account_activity
    seed_zap_activity
    log "demo data already exists ($(jq -r '.proposals' "${marker}") proposals)"
    return
  fi

  local existing
  existing="$(curl -sf "${REST}/cosmos/gov/v1/proposals?pagination.limit=1" | jq -r '.pagination.total // (.proposals | length)')"
  [[ "${existing}" == "0" ]] || fail "the chain already has ${existing} proposal(s); run make localnet-reset, make localnet, then make seed"

  local gov_authority
  gov_authority="$(curl -sf "${REST}/cosmos/auth/v1beta1/module_accounts/gov" | jq -r '[.. | objects | .address? // empty][0] // empty')"
  [[ -n "${gov_authority}" ]] || fail "governance authority is not queryable"

  local titles=(
    "Explore a research partnership with Nova University"
    "Add a simple status page for community services"
    "Require a named owner for every accepted proposal"
    "Make mobile participation a top priority"
    "Renew the accessibility testing programme"
    "Join the Open Builders mentorship programme"
    "Create a shared calendar for releases and votes"
    "Add a seven-day review before major fee changes"
    "Support twelve local contributor meetups"
    "Pilot a shared identity standard with Aurora"
    "Publish a one-year product plan"
    "Fund a community explorer"
    "Add a simple proposal comparison view"
    "Limit emergency council terms to one year"
    "Require plain-language notes for every release"
    "Fund three beginner education pilots"
    "Create one public dashboard for grants"
    "Publish serious network incidents within 24 hours"
    "Limit one team to 12% of the community voice"
    "Rotate community grant reviewers every six months"
    "Publish a simple quarterly spending report"
    "Add an emergency pause for bridge transfers"
    "Reserve 5% of fees for local builders"
    "Make tokens available again after 14 days"
    "Let proposal authors correct small errors"
    "Release the final payment for the learning hub"
    "Choose the next three beginner guides"
    "Approve a joint safety exercise with Meridian"
    "Show a plain-language warning before risky actions"
    "Fund an independent budget review"
    "Add translated proposal summaries"
    "Move account recovery research into this quarter"
    "Create a shared grants showcase with Helio"
    "Sponsor three independent security reviews"
    "Add a cooling-off period for emergency appointments"
    "Build a simple representative comparison"
    "Start a public data collaboration with Open Atlas"
    "Prioritise tools for project partnerships"
    "Create a community roadmap board"
    "Require a public handover when a team changes"
    "Create a small rapid-response project budget"
    "Offer a shared launch programme for new projects"
    "Review the five-year vision in public"
    "Add milestone charts to project updates"
    "Publish reasons when a public request is declined"
    "Expand the public translation budget"
    "Invite Cedar to co-design a local grants pilot"
    "Set public goals for the next community season"
  )
  local proposal_ids=() proposal_groups=()
  local proposal_file="${RESULT_DIR}/demo-proposal.json"

  proposal_copy() {
    local index="$1" title="$2" action="${2,}"
    COPY_REQUESTED_AMOUNT="None"
    case "${index}" in
      0) COPY_REQUESTED_AMOUNT="120,000 KUD" ;;
      4) COPY_REQUESTED_AMOUNT="60,000 KUD" ;;
      5) COPY_REQUESTED_AMOUNT="45,000 KUD" ;;
      8) COPY_REQUESTED_AMOUNT="90,000 KUD" ;;
      11) COPY_REQUESTED_AMOUNT="250,000 KUD" ;;
      15) COPY_REQUESTED_AMOUNT="75,000 KUD" ;;
      16) COPY_REQUESTED_AMOUNT="110,000 KUD" ;;
      22) COPY_REQUESTED_AMOUNT="5% of future network fees" ;;
      25) COPY_REQUESTED_AMOUNT="180,000 KUD" ;;
      27) COPY_REQUESTED_AMOUNT="40,000 KUD" ;;
      29) COPY_REQUESTED_AMOUNT="35,000 KUD" ;;
      32) COPY_REQUESTED_AMOUNT="80,000 KUD" ;;
      33) COPY_REQUESTED_AMOUNT="210,000 KUD" ;;
      36) COPY_REQUESTED_AMOUNT="100,000 KUD" ;;
      40) COPY_REQUESTED_AMOUNT="50,000 KUD" ;;
      41) COPY_REQUESTED_AMOUNT="150,000 KUD" ;;
      43) COPY_REQUESTED_AMOUNT="65,000 KUD" ;;
      45) COPY_REQUESTED_AMOUNT="85,000 KUD" ;;
      46) COPY_REQUESTED_AMOUNT="120,000 KUD" ;;
    esac

    case $((index % 3)) in
      0) COPY_SUMMARY="This proposal would ${action}." ;;
      1) COPY_SUMMARY="The community is deciding whether Kudora should ${action}." ;;
      2) COPY_SUMMARY="This vote decides whether to ${action}." ;;
    esac

    if [[ "${COPY_REQUESTED_AMOUNT}" != "None" ]]; then
      COPY_CONTEXT="The community needs to confirm the business value, budget and owner before any KUD is committed."
      COPY_OUTCOME="Kudora will ${action}. Funding will follow verified milestones instead of being released all at once."
      COPY_CHANGES='["Publish the final scope, budget and accountable owner.","Release the first portion when work starts.","Verify delivery against public success measures.","Publish the final report before releasing the remaining KUD."]'
    elif [[ "${title}" =~ (partnership|programme|collaboration|exercise|co-design|meetups) ]]; then
      COPY_CONTEXT="This opportunity needs a clear partner, owner and success measure before Kudora commits."
      COPY_OUTCOME="Kudora will ${action}, beginning with a time-limited pilot and a public decision on whether to continue."
      COPY_CHANGES='["Confirm the partner, owner and scope in public.","Launch a time-limited pilot with clear success measures.","Publish the pilot results and community feedback.","Decide publicly whether to continue, change or stop the work."]'
    else
      COPY_CONTEXT="The current approach leaves an important rule or service unclear for members."
      COPY_OUTCOME="Kudora will ${action}. The new approach will be reviewed with public evidence after its first full cycle."
      COPY_CHANGES='["Publish the final rule or service scope in plain language.","Name the owner and the date the change starts.","Share a progress checkpoint with measurable evidence.","Review the result publicly and record any follow-up decision."]'
    fi
  }

  local validator0_key validator0_home validator1_key validator1_home validator2_key validator2_home
  validator0_key="$(jq -r '.validators[0].key' "${METADATA}")"
  validator0_home="$(jq -r '.validators[0].home' "${METADATA}")"
  validator1_key="$(jq -r '.validators[1].key' "${METADATA}")"
  validator1_home="$(jq -r '.validators[1].home' "${METADATA}")"
  validator2_key="$(jq -r '.validators[2].key' "${METADATA}")"
  validator2_home="$(jq -r '.validators[2].home' "${METADATA}")"

  log "creating 12 completed governance proposals"
  for index in $(seq 36 47); do
    local title="${titles[${index}]}" summary metadata proposal_id
    proposal_copy "${index}" "${title}"
    summary="${COPY_SUMMARY}"
    metadata="$(jq -nc --arg title "${title}" --arg summary "${summary}" --arg context "${COPY_CONTEXT}" --arg outcome "${COPY_OUTCOME}" --arg requestedAmount "${COPY_REQUESTED_AMOUNT}" --argjson changes "${COPY_CHANGES}" '{title:$title,summary:$summary,v:1,context:$context,changes:$changes,outcome:$outcome,requestedAmount:$requestedAmount}')"
    jq -n \
      --arg authority "${gov_authority}" \
      --arg metadata "${metadata}" \
      --arg title "${title}" \
      --arg summary "${summary}" \
      --arg deposit "2000000000000000000${DENOM}" \
      '{messages:[{"@type":"/kudora.discussion.v1.MsgUpdateParams",authority:$authority,params:{post_fee:{denom:"akud",amount:"1000000000000000"}}}],metadata:$metadata,deposit:$deposit,title:$title,summary:$summary,expedited:true}' >"${proposal_file}"
    tx_for "proposal-${index}" alice "${account_home}" \
      kudorad tx gov submit-proposal "${proposal_file}" --gas 1000000
    proposal_id="$(curl -sf "${REST}/cosmos/gov/v1/proposals?pagination.limit=1&pagination.reverse=true" | jq -r '.proposals[0].id')"
    proposal_ids[${index}]="${proposal_id}"
    proposal_groups[${index}]="past"
    local -a vote_pids=()
    if (( index % 2 == 0 )); then
      tx_for "proposal-${index}-vote-0" "${validator0_key}" "${validator0_home}" kudorad tx gov vote "${proposal_id}" yes --gas 300000 & vote_pids+=("$!")
      tx_for "proposal-${index}-vote-1" "${validator1_key}" "${validator1_home}" kudorad tx gov vote "${proposal_id}" yes --gas 300000 & vote_pids+=("$!")
      tx_for "proposal-${index}-vote-2" "${validator2_key}" "${validator2_home}" kudorad tx gov vote "${proposal_id}" no --gas 300000 & vote_pids+=("$!")
    else
      tx_for "proposal-${index}-vote-0" "${validator0_key}" "${validator0_home}" kudorad tx gov vote "${proposal_id}" yes --gas 300000 & vote_pids+=("$!")
      tx_for "proposal-${index}-vote-1" "${validator1_key}" "${validator1_home}" kudorad tx gov vote "${proposal_id}" abstain --gas 300000 & vote_pids+=("$!")
      tx_for "proposal-${index}-vote-2" "${validator2_key}" "${validator2_home}" kudorad tx gov vote "${proposal_id}" yes --gas 300000 & vote_pids+=("$!")
    fi
    for pid in "${vote_pids[@]}"; do wait "${pid}"; done
  done

  log "creating 36 open governance proposals"
  for index in $(seq 0 35); do
    local title="${titles[${index}]}" summary metadata proposal_id
    proposal_copy "${index}" "${title}"
    summary="${COPY_SUMMARY}"
    metadata="$(jq -nc --arg title "${title}" --arg summary "${summary}" --arg context "${COPY_CONTEXT}" --arg outcome "${COPY_OUTCOME}" --arg requestedAmount "${COPY_REQUESTED_AMOUNT}" --argjson changes "${COPY_CHANGES}" '{title:$title,summary:$summary,v:1,context:$context,changes:$changes,outcome:$outcome,requestedAmount:$requestedAmount}')"
    jq -n \
      --arg authority "${gov_authority}" \
      --arg metadata "${metadata}" \
      --arg title "${title}" \
      --arg summary "${summary}" \
      --arg deposit "1000000000000000000${DENOM}" \
      '{messages:[{"@type":"/kudora.discussion.v1.MsgUpdateParams",authority:$authority,params:{post_fee:{denom:"akud",amount:"1000000000000000"}}}],metadata:$metadata,deposit:$deposit,title:$title,summary:$summary,expedited:false}' >"${proposal_file}"
    tx_for "proposal-${index}" alice "${account_home}" \
      kudorad tx gov submit-proposal "${proposal_file}" --gas 1000000
    proposal_id="$(curl -sf "${REST}/cosmos/gov/v1/proposals?pagination.limit=1&pagination.reverse=true" | jq -r '.proposals[0].id')"
    proposal_ids[${index}]="${proposal_id}"
    proposal_groups[${index}]="open"
    local -a vote_pids=()
    case "${index}" in
      0) tx_for "proposal-${index}-alice-vote" alice "${account_home}" kudorad tx gov vote "${proposal_id}" yes --gas 300000 & vote_pids+=("$!") ;;
      1) tx_for "proposal-${index}-alice-vote" alice "${account_home}" kudorad tx gov vote "${proposal_id}" no --gas 300000 & vote_pids+=("$!") ;;
      2) tx_for "proposal-${index}-bob-vote" bob "${account_home}" kudorad tx gov vote "${proposal_id}" abstain --gas 300000 & vote_pids+=("$!") ;;
      3) tx_for "proposal-${index}-carol-vote" carol "${account_home}" kudorad tx gov vote "${proposal_id}" no_with_veto --gas 300000 & vote_pids+=("$!") ;;
    esac
    case $((index % 4)) in
      0)
        tx_for "proposal-${index}-vote-0" "${validator0_key}" "${validator0_home}" kudorad tx gov vote "${proposal_id}" yes --gas 300000 & vote_pids+=("$!")
        tx_for "proposal-${index}-vote-1" "${validator1_key}" "${validator1_home}" kudorad tx gov vote "${proposal_id}" no --gas 300000 & vote_pids+=("$!")
        tx_for "proposal-${index}-vote-2" "${validator2_key}" "${validator2_home}" kudorad tx gov vote "${proposal_id}" abstain --gas 300000 & vote_pids+=("$!")
        ;;
      1)
        tx_for "proposal-${index}-vote-0" "${validator0_key}" "${validator0_home}" kudorad tx gov vote "${proposal_id}" no --gas 300000 & vote_pids+=("$!")
        tx_for "proposal-${index}-vote-1" "${validator1_key}" "${validator1_home}" kudorad tx gov vote "${proposal_id}" yes --gas 300000 & vote_pids+=("$!")
        ;;
      2)
        tx_for "proposal-${index}-vote-1" "${validator1_key}" "${validator1_home}" kudorad tx gov vote "${proposal_id}" no --gas 300000 & vote_pids+=("$!")
        tx_for "proposal-${index}-vote-2" "${validator2_key}" "${validator2_home}" kudorad tx gov vote "${proposal_id}" yes --gas 300000 & vote_pids+=("$!")
        ;;
      3)
        tx_for "proposal-${index}-vote-0" "${validator0_key}" "${validator0_home}" kudorad tx gov vote "${proposal_id}" abstain --gas 300000 & vote_pids+=("$!")
        tx_for "proposal-${index}-vote-2" "${validator2_key}" "${validator2_home}" kudorad tx gov vote "${proposal_id}" no_with_veto --gas 300000 & vote_pids+=("$!")
        ;;
    esac
    for pid in "${vote_pids[@]}"; do wait "${pid}"; done
  done

  log "creating delegations"
  local delegates=(alice bob carol)
  for index in 0 1 2; do
    local operator
    operator="$(jq -r ".validators[${index}].operator" "${METADATA}")"
    tx_for "delegate-${delegates[${index}]}" "${delegates[${index}]}" "${account_home}" \
      kudorad tx staking delegate "${operator}" "10000000000000000000${DENOM}" --gas 400000
  done
  log "creating on-chain discussions, proposal reactions and zaps"
  for index in $(seq 0 47); do
    local proposal_id="${proposal_ids[${index}]}" group="${proposal_groups[${index}]}" root_id payload kind author reactor
    post_message "discussion-${index}-anchor" "${proposal_id}" 0 alice \
      "$(jq -nc '{v:1,t:"text",role:"proposal",text:"On-chain community signal for this proposal."}')"
    local anchor_id="${LAST_MESSAGE_ID}"
    case $((index % 5)) in
      0) kind="text"; payload="$(jq -nc --arg n "$((index + 1))" '{v:1,t:"text",text:("I support a clear owner and public checkpoint for decision " + $n + ".")}')" ;;
      1) kind="timeline"; payload="$(jq -nc '{v:1,t:"timeline",text:"A practical delivery sequence.",title:"Public delivery timeline",items:["Week 1 · confirm owner","Week 2 · publish first checkpoint","Week 4 · community review"]}')" ;;
      2) kind="budget"; payload="$(jq -nc '{v:1,t:"budget",text:"The budget should stay visible.",title:"Suggested allocation",items:[["Delivery","60%"],["Independent review","25%"],["Contingency","15%"]]}')" ;;
      3) kind="poll"; payload="$(jq -nc '{v:1,t:"poll",text:"Which checkpoint matters most?",title:"Community checkpoint",items:["Public owner","Weekly update","Independent review"]}')" ;;
      4) kind="carousel"; payload="$(jq -nc '{v:1,t:"carousel",text:"Three outcomes worth tracking.",title:"What success looks like",items:["Simple to understand","Publicly measurable","Owned by a named team"]}')" ;;
    esac
    if (( index % 2 == 0 )); then author="bob"; reactor="carol"; else author="carol"; reactor="bob"; fi
    post_message "discussion-${index}-root" "${proposal_id}" 0 "${author}" "${payload}"
    root_id="${LAST_MESSAGE_ID}"
    local representative_key representative_home representative_vote
    if (( index >= 36 || index % 4 != 2 )); then
      representative_key="${validator0_key}"
      representative_home="${validator0_home}"
      if (( index >= 36 && index % 2 == 0 )); then representative_vote="Yes";
      elif (( index >= 36 )); then representative_vote="Yes";
      elif (( index % 4 == 0 )); then representative_vote="Yes";
      elif (( index % 4 == 1 )); then representative_vote="No";
      else representative_vote="Abstain"; fi
    else
      representative_key="${validator1_key}"
      representative_home="${validator1_home}"
      representative_vote="No"
    fi
    local -a enrichment_pids=()
    post_message "discussion-${index}-representative" "${proposal_id}" 0 "${representative_key}" \
      "$(jq -nc --arg vote "${representative_vote}" '{v:1,t:"text",role:"validator-comment",vote:$vote,text:("I voted " + $vote + " because the proposal needs a clear owner, measurable milestones and a public review.")}')" \
      "${representative_home}" no & enrichment_pids+=("$!")
    local reaction="useful"
    if (( index % 4 == 3 )); then reaction="not-useful"; fi
    tx_for "discussion-${index}-proposal-reaction" "${reactor}" "${account_home}" \
      kudorad tx discussion react "${proposal_id}" "${anchor_id}" "${reaction}" --gas 300000 & enrichment_pids+=("$!")
    tx_for "discussion-${index}-comment-reaction" alice "${account_home}" \
      kudorad tx discussion react "${proposal_id}" "${root_id}" useful --gas 300000 & enrichment_pids+=("$!")
    for pid in "${enrichment_pids[@]}"; do wait "${pid}"; done

    if [[ "${group}" == "past" || $((index % 3)) == 0 ]]; then
      post_message "discussion-${index}-reply" "${proposal_id}" "${root_id}" alice \
        "$(jq -nc '{v:1,t:"text",text:"This is useful. I would also publish the evidence behind the checkpoint."}')"
    fi
    if [[ "${group}" == "past" ]]; then
      local -a extra_pids=()
      post_message "discussion-${index}-extra-1" "${proposal_id}" 0 bob \
        "$(jq -nc '{v:1,t:"poll",text:"A quick community pulse before the final checkpoint.",title:"Which proof should be public?",items:["Delivery receipt","Independent review","Community sign-off"]}')" "${account_home}" no & extra_pids+=("$!")
      post_message "discussion-${index}-extra-2" "${proposal_id}" 0 carol \
        "$(jq -nc '{v:1,t:"budget",text:"Keep every amount easy to audit.",title:"Transparent budget",items:[["Build","50%"],["Review","30%"],["Support","20%"]]}')" "${account_home}" no & extra_pids+=("$!")
      for pid in "${extra_pids[@]}"; do wait "${pid}"; done
    fi
    if (( index % 4 == 0 )); then
      tx_for "discussion-${index}-zap" bob "${account_home}" \
        kudorad tx discussion zap "${proposal_id}" "${anchor_id}" 10000000000000000 --gas 300000
    fi
    if (( (index + 1) % 6 == 0 )); then log "$((index + 1))/48 proposals enriched"; fi
  done

  seed_account_activity
  seed_zap_activity

  local passed rejected open messages
  passed="$(curl -sf "${REST}/cosmos/gov/v1/proposals?proposal_status=PROPOSAL_STATUS_PASSED&pagination.limit=100" | jq '.proposals | length')"
  rejected="$(curl -sf "${REST}/cosmos/gov/v1/proposals?proposal_status=PROPOSAL_STATUS_REJECTED&pagination.limit=100" | jq '.proposals | length')"
  open="$(curl -sf "${REST}/cosmos/gov/v1/proposals?proposal_status=PROPOSAL_STATUS_VOTING_PERIOD&pagination.limit=100" | jq '.proposals | length')"
  messages="$(for index in $(seq 0 47); do curl -sf "${REST}/kudora/discussion/v1/messages/${proposal_ids[${index}]}?pagination.limit=200"; done | jq -s '[.[].messages[]] | length')"
  jq -n --argjson proposals 48 --argjson passed "${passed}" --argjson rejected "${rejected}" --argjson open "${open}" --argjson messages "${messages}" \
    '{proposals:$proposals,passed:$passed,rejected:$rejected,open:$open,messages:$messages}' >"${marker}"
  log "ready: 48 proposals (${open} open, ${passed} passed, ${rejected} rejected), ${messages} discussion records"
}

case "${MODE}" in
  fund) fund_wallets "${2:-100}" ;;
  seed) seed_demo ;;
  *) fail "usage: localnet-data.sh fund [amount]|seed" ;;
esac
