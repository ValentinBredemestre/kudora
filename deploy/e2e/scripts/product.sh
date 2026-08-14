#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${KUDORA_E2E_STATE_DIR:-/state}"
RPC="${KUDORA_RPC_URL:-http://validator-0:26657}"
REST="${KUDORA_REST_URL:-http://validator-0:1317}"
EVM_RPC="${KUDORA_EVM_RPC_URL:-http://validator-0:8545}"
MODE="${1:-}"

wait_ready() {
  status_file="${STATE_DIR}/logs/product-status.json"
  for _ in $(seq 1 120); do
    if curl -sf "${RPC}/status" >"${status_file}" \
      && jq -e '(.result.sync_info.latest_block_height | tonumber) > 0' "${status_file}" >/dev/null \
      && curl -sf "${REST}/kudora/discussion/v1/params" >/dev/null \
      && curl -sf -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        "${EVM_RPC}" | jq -e '.result == "0x1d4c1"' >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "[localnet] chain endpoints did not become ready" >&2
  return 1
}

case "${MODE}" in
  wait)
    wait_ready
    ;;
  bootstrap)
    wait_ready
    mkdir -p "${STATE_DIR}/results"
    deployment="${STATE_DIR}/results/swap-deployment.json"
    if [[ ! -s "${deployment}" ]]; then
      kudora-evm-smoke-helper swap-deploy \
        --rpc-url "${EVM_RPC}" \
        --chain-id 120001 \
        --sender-key-file "${STATE_DIR}/alice.key" \
        --result-file "${deployment}"
    fi
    jq --slurpfile swap "${deployment}" '.swap = $swap[0]' \
      "${STATE_DIR}/metadata.json" >"${STATE_DIR}/metadata.json.tmp"
    mv "${STATE_DIR}/metadata.json.tmp" "${STATE_DIR}/metadata.json"
    ;;
  accounts)
    echo "LOCAL DEVELOPMENT ONLY — DISPOSABLE KEYS — DO NOT USE ON MAINNET"
    echo
    for account in alice bob carol; do
      title="${account^}"
      echo "${title}"
      echo "  EVM:        $(jq -r ".users.${account}.eth_address" "${STATE_DIR}/metadata.json")"
      echo "  Cosmos:     $(jq -r ".users.${account}.cosmos_address" "${STATE_DIR}/metadata.json")"
      echo "  Private key: $(tr -d '\n' <"${STATE_DIR}/${account}.key")"
      echo
    done
    ;;
  height)
    wait_ready
    curl -sf "${RPC}/status" | jq -r '.result.sync_info.latest_block_height'
    ;;
  public-config)
    wait_ready
    if ! gov_authority="$(curl -sf "${REST}/cosmos/auth/v1beta1/module_accounts/gov" | jq -r '[.. | objects | .address? // empty][0] // empty')" || [[ -z "${gov_authority}" ]]; then
      echo "[localnet] governance authority is not queryable" >&2
      exit 1
    fi
    jq --arg gov_authority "${gov_authority}" '{
      cosmosChainId: .chain_id,
      evmChainId: 120001,
      denom: "akud",
      displayDenom: "KUD",
      decimals: 18,
      cosmosRestUrl: "http://localhost:1317",
      cosmosRpcUrl: "http://localhost:26657",
      evmRpcUrl: "http://localhost:8545",
      evmWsUrl: "ws://localhost:8546",
      discussionPrecompileAddress: "0x0000000000000000000000000000000000000900",
      governancePrecompileAddress: "0x0000000000000000000000000000000000000805",
      governanceAuthority: $gov_authority,
      localWalletsUrl: "/kudora-local-wallets.json",
      accounts: {
        alice: {
          evmAddress: .users.alice.eth_address,
          cosmosAddress: .users.alice.cosmos_address
        },
        bob: {
          evmAddress: .users.bob.eth_address,
          cosmosAddress: .users.bob.cosmos_address
        },
        carol: {
          evmAddress: .users.carol.eth_address,
          cosmosAddress: .users.carol.cosmos_address
        }
      },
      swap: {
        localnetOnly: true,
        routerAddress: .swap.router_address,
        mockUsdcAddress: .swap.mock_usdc_address
      }
    }' "${STATE_DIR}/metadata.json"
    ;;
  wallets)
    wait_ready
    jq -n \
      --arg alice "$(tr -d '\n' <"${STATE_DIR}/alice.key")" \
      --arg bob "$(tr -d '\n' <"${STATE_DIR}/bob.key")" \
      --arg carol "$(tr -d '\n' <"${STATE_DIR}/carol.key")" \
      '{localDevelopmentOnly: true, accounts: {
        alice: {privateKey: ("0x" + $alice)},
        bob: {privateKey: ("0x" + $bob)},
        carol: {privateKey: ("0x" + $carol)}
      }}'
    ;;
  *)
    echo "usage: product.sh wait|bootstrap|accounts|height|public-config|wallets" >&2
    exit 1
    ;;
esac
