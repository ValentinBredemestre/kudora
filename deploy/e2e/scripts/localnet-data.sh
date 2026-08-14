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
      kudorad tx bank send "${source_key}" "${recipient}" "${amount}${DENOM}" --gas 300000
    log "${account^}: +${display_amount} KUD, balance $(balance_kud "${recipient}") KUD"
  done
}

account_home="$(jq -r '.users.alice.home' "${METADATA}")"
alice_address="$(jq -r '.users.alice.cosmos_address' "${METADATA}")"
bob_address="$(jq -r '.users.bob.cosmos_address' "${METADATA}")"
carol_address="$(jq -r '.users.carol.cosmos_address' "${METADATA}")"

post_message() {
  local label="$1" proposal_id="$2" parent_id="$3" author="$4" payload="$5"
  local encoded
  encoded="$(printf '%s' "${payload}" | base64 -w 0)"
  tx_for "${label}" "${author}" "${account_home}" \
    kudorad tx discussion post "${proposal_id}" "${parent_id}" "${encoded}" --gas 350000
  LAST_MESSAGE_ID="$(curl -sf "${REST}/kudora/discussion/v1/messages/${proposal_id}?pagination.limit=200" | jq -r '[.messages[].message_id | tonumber] | max // 0')"
}

seed_demo() {
  local marker="${RESULT_DIR}/demo-seed.json"
  if [[ -s "${marker}" ]]; then
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

  local validator0_key validator0_home validator1_key validator1_home
  validator0_key="$(jq -r '.validators[0].key' "${METADATA}")"
  validator0_home="$(jq -r '.validators[0].home' "${METADATA}")"
  validator1_key="$(jq -r '.validators[1].key' "${METADATA}")"
  validator1_home="$(jq -r '.validators[1].home' "${METADATA}")"

  log "creating 12 completed governance proposals"
  for index in $(seq 36 47); do
    local title="${titles[${index}]}" summary metadata proposal_id vote
    summary="A public decision with measurable outcomes, clear ownership and community checkpoints."
    metadata="$(jq -nc --arg title "${title}" --arg summary "${summary}" '{title:$title,summary:$summary,v:1,group:"most-discussed",context:"The community needs a transparent decision backed by public evidence.",changes:["Publish the decision, owner and milestones on-chain.","Review progress with the community."],outcome:"Anyone can verify the result and follow delivery."}')"
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
    proposal_groups[${index}]="most-discussed"
    if (( index % 2 == 0 )); then vote="yes"; else vote="no"; fi
    tx_for "proposal-${index}-vote-0" "${validator0_key}" "${validator0_home}" \
      kudorad tx gov vote "${proposal_id}" "${vote}" --gas 300000
    tx_for "proposal-${index}-vote-1" "${validator1_key}" "${validator1_home}" \
      kudorad tx gov vote "${proposal_id}" "${vote}" --gas 300000
  done

  log "creating 36 open governance proposals"
  for index in $(seq 0 35); do
    local title="${titles[${index}]}" group summary metadata proposal_id
    if (( index < 12 )); then group="active"; elif (( index < 24 )); then group="representatives"; else group="closing"; fi
    summary="A focused proposal written in plain language with a public delivery checkpoint."
    metadata="$(jq -nc --arg title "${title}" --arg summary "${summary}" --arg group "${group}" '{title:$title,summary:$summary,v:1,group:$group,context:"This proposal turns a community need into one verifiable decision.",changes:["Record the commitment and responsible owner on-chain.","Publish a progress checkpoint for everyone."],outcome:"The community can inspect both the decision and its follow-up."}')"
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
    proposal_groups[${index}]="${group}"
    if [[ "${group}" == "active" ]]; then
      local choice="yes"
      case $((index % 4)) in 1) choice="no" ;; 2) choice="abstain" ;; 3) choice="no_with_veto" ;; esac
      tx_for "proposal-${index}-alice-vote" alice "${account_home}" \
        kudorad tx gov vote "${proposal_id}" "${choice}" --gas 300000
    elif [[ "${group}" == "representatives" ]]; then
      tx_for "proposal-${index}-representative-vote" "${validator0_key}" "${validator0_home}" \
        kudorad tx gov vote "${proposal_id}" yes --gas 300000
    fi
  done

  log "creating delegations and account history"
  local delegates=(alice bob carol)
  for index in 0 1 2; do
    local operator
    operator="$(jq -r ".validators[${index}].operator" "${METADATA}")"
    tx_for "delegate-${delegates[${index}]}" "${delegates[${index}]}" "${account_home}" \
      kudorad tx staking delegate "${operator}" "10000000000000000000${DENOM}" --gas 400000
  done
  for index in $(seq 1 9); do
    case $((index % 3)) in
      0) tx_for "history-${index}" alice "${account_home}" kudorad tx bank send alice "${bob_address}" "250000000000000000${DENOM}" --gas 300000 ;;
      1) tx_for "history-${index}" bob "${account_home}" kudorad tx bank send bob "${carol_address}" "250000000000000000${DENOM}" --gas 300000 ;;
      2) tx_for "history-${index}" carol "${account_home}" kudorad tx bank send carol "${alice_address}" "250000000000000000${DENOM}" --gas 300000 ;;
    esac
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
    local reaction="useful"
    if (( index % 4 == 3 )); then reaction="not-useful"; fi
    tx_for "discussion-${index}-proposal-reaction" "${reactor}" "${account_home}" \
      kudorad tx discussion react "${proposal_id}" "${anchor_id}" "${reaction}" --gas 300000
    tx_for "discussion-${index}-comment-reaction" alice "${account_home}" \
      kudorad tx discussion react "${proposal_id}" "${root_id}" useful --gas 300000

    if [[ "${group}" == "most-discussed" || $((index % 3)) == 0 ]]; then
      post_message "discussion-${index}-reply" "${proposal_id}" "${root_id}" alice \
        "$(jq -nc '{v:1,t:"text",text:"This is useful. I would also publish the evidence behind the checkpoint."}')"
    fi
    if [[ "${group}" == "most-discussed" ]]; then
      post_message "discussion-${index}-extra-1" "${proposal_id}" 0 bob \
        "$(jq -nc '{v:1,t:"poll",text:"A quick community pulse before the final checkpoint.",title:"Which proof should be public?",items:["Delivery receipt","Independent review","Community sign-off"]}')"
      post_message "discussion-${index}-extra-2" "${proposal_id}" 0 carol \
        "$(jq -nc '{v:1,t:"budget",text:"Keep every amount easy to audit.",title:"Transparent budget",items:[["Build","50%"],["Review","30%"],["Support","20%"]]}')"
    fi
    if (( index % 4 == 0 )); then
      tx_for "discussion-${index}-zap" bob "${account_home}" \
        kudorad tx discussion zap "${proposal_id}" "${anchor_id}" 10000000000000000 --gas 300000
    fi
    if (( (index + 1) % 6 == 0 )); then log "$((index + 1))/48 proposals enriched"; fi
  done

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
