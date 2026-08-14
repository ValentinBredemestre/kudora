#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DOCKER_IMAGE="${KUDORA_DOCKER_IMAGE:-$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)}"
DOCKER_BUILD_TAGS="${KUDORA_DOCKER_BUILD_TAGS:-localnet,docker}"
DOCKER_APP_VERSION="${KUDORA_DOCKER_APP_VERSION:-dev}"
DOCKER_GIT_COMMIT="${KUDORA_DOCKER_GIT_COMMIT:-unknown}"
cleanup_dirs=()

cleanup() {
  local path

  for path in "${cleanup_dirs[@]}"; do
    [[ -n "${path}" ]] || continue
    rm -rf "${path}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return 0
  fi

  echo "docker-build: no sha256 command available" >&2
  exit 1
}

sha256_files() {
  if command -v sha256sum >/dev/null 2>&1; then
    xargs -0 sha256sum
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    xargs -0 shasum -a 256
    return 0
  fi

  echo "docker-build: no sha256 command available" >&2
  exit 1
}

compute_context_hash() {
  find . \
    \( -path './.git' -o -path './.kudora' -o -path './.testnets' -o -path './.localnet' -o -path './build' -o -path './dist' -o -path './tmp' -o -path './release/temp' -o -path './out' -o -path './deploy/localnet/state' \) -prune -o \
    \( -path './deploy/explorers/*/.env' -o -path './deploy/explorers/*/data/*' -o -path './deploy/explorers/*/db/*' -o -path './deploy/explorers/*/postgres/*' -o -path './deploy/explorers/*/redis/*' -o -path './deploy/monitoring/*/.env' -o -path './deploy/monitoring/*/data/*' -o -path './deploy/monitoring/*/prometheus-data/*' -o -path './deploy/monitoring/*/grafana-data/*' -o -path './deploy/cosmovisor/*/.env' \) -prune -o \
    \( -name '.DS_Store' -o -name '*.log' -o -name '.env' -o -name '.env.*' -o -name 'priv_validator_key.json' -o -name 'node_key.json' -o -name 'key_seed.json' -o -name '*.pem' -o -name '*.key' -o -name '*.seed' -o -name '*.mnemonic' -o -name '*.zip' \) -prune -o \
    -type f -print0 \
    | LC_ALL=C sort -z \
    | sha256_files \
    | sha256_text
}

prepare_prebuilt_runtime_context() {
  local prebuilt_dir=""
  local tmp_root="${ROOT_DIR}/tmp/docker-image-build"
  local gotmp_dir=""
  local tmp_dir=""
  local mod_cache=""
  local wasmvm_lib_aarch64=""
  local wasmvm_lib_x86_64=""

  mkdir -p "${tmp_root}"
  prebuilt_dir="$(mktemp -d "${ROOT_DIR}/tmp/docker-image-prebuilt.XXXXXX")"
  gotmp_dir="$(mktemp -d "${tmp_root}/gotmp.XXXXXX")"
  tmp_dir="$(mktemp -d "${tmp_root}/tmp.XXXXXX")"
  cleanup_dirs+=("${prebuilt_dir}" "${gotmp_dir}" "${tmp_dir}")

  GOFLAGS="-buildvcs=false -p=1" \
  GOTMPDIR="${gotmp_dir}" \
  TMPDIR="${tmp_dir}" \
  GOOS=linux \
  GOARCH="$(go env GOARCH)" \
  CGO_ENABLED=1 \
  go build -trimpath \
    -ldflags="-s -w \
      -X github.com/cosmos/cosmos-sdk/version.Name=kudora \
      -X github.com/cosmos/cosmos-sdk/version.AppName=kudorad \
      -X github.com/cosmos/cosmos-sdk/version.Version=${DOCKER_APP_VERSION} \
      -X github.com/cosmos/cosmos-sdk/version.Commit=${DOCKER_GIT_COMMIT} \
      -X github.com/cosmos/cosmos-sdk/version.BuildTags=${DOCKER_BUILD_TAGS}" \
    -o "${prebuilt_dir}/kudorad" \
    ./cmd/kudorad

  GOFLAGS="-buildvcs=false -p=1" \
  GOTMPDIR="${gotmp_dir}" \
  TMPDIR="${tmp_dir}" \
  GOOS=linux \
  GOARCH="$(go env GOARCH)" \
  CGO_ENABLED=1 \
  go build -trimpath \
    -ldflags="-s -w" \
    -o "${prebuilt_dir}/kudora-evm-smoke-helper" \
    ./testutil/evm-smoke

  mod_cache="$(go env GOMODCACHE)"
  wasmvm_lib_aarch64="$(find "${mod_cache}" -path '*/github.com/!cosm!wasm/wasmvm/v3@*/internal/api/libwasmvm.aarch64.so' | head -n 1)"
  wasmvm_lib_x86_64="$(find "${mod_cache}" -path '*/github.com/!cosm!wasm/wasmvm/v3@*/internal/api/libwasmvm.x86_64.so' | head -n 1)"

  test -n "${wasmvm_lib_aarch64}"
  test -n "${wasmvm_lib_x86_64}"

  cp "${wasmvm_lib_aarch64}" "${prebuilt_dir}/libwasmvm.aarch64.so"
  cp "${wasmvm_lib_x86_64}" "${prebuilt_dir}/libwasmvm.x86_64.so"
  chmod 0755 "${prebuilt_dir}/kudorad" "${prebuilt_dir}/kudora-evm-smoke-helper"

  printf '%s\n' "${prebuilt_dir}"
}

context_hash="$(compute_context_hash)"
current_hash="$(docker image inspect "${DOCKER_IMAGE}" --format '{{ index .Config.Labels "io.kudora.context_hash" }}' 2>/dev/null || true)"

if [[ -n "${current_hash}" && "${current_hash}" == "${context_hash}" ]]; then
  echo "docker-build: PASS (${DOCKER_IMAGE}; context unchanged: ${context_hash})"
  exit 0
fi

if [[ "${KUDORA_IN_DOCKER:-}" == "1" ]]; then
  prebuilt_dir="$(prepare_prebuilt_runtime_context)"

  DOCKER_BUILDKIT=1 docker buildx build \
    --load \
    --build-context "prebuilt=${prebuilt_dir}" \
    --build-arg "CONTEXT_HASH=${context_hash}" \
    --target runtime-prebuilt \
    --tag "${DOCKER_IMAGE}" \
    --file Dockerfile \
    .
else
  DOCKER_BUILDKIT=1 docker buildx build \
    --load \
    --build-arg "CONTEXT_HASH=${context_hash}" \
    --tag "${DOCKER_IMAGE}" \
    --file Dockerfile \
    .
fi
