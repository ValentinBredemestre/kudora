#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_command file
release_require_docker
release_require_candidate_genesis

platform="$(release_linux_amd64_platform)"
platform_dir="$(release_binary_dir "${platform}")"
binary_path="$(release_binary_path "${platform}")"
helper_path="$(release_evm_helper_path "${platform}")"
lib_name="$(release_required_wasmvm_library "${platform}")"
lib_path="$(release_wasmvm_lib_path "${platform}" "${lib_name}")"
metadata_path="$(release_build_metadata_path)"
platforms_file="$(release_supported_platforms_file)"
git_commit="$(release_git_commit)"
build_created="$(release_now_utc)"
host_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/kudora-phase17-release-cache.XXXXXX")"
release_tmp_root="${ROOT_DIR}/tmp/phase-17-release-build"
release_gotmp_dir=""
release_tmp_dir=""

cleanup() {
  [[ -n "${release_gotmp_dir}" ]] && rm -rf "${release_gotmp_dir}" >/dev/null 2>&1 || true
  [[ -n "${release_tmp_dir}" ]] && rm -rf "${release_tmp_dir}" >/dev/null 2>&1 || true
  rm -rf "${host_cache_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -rf "${platform_dir}"
mkdir -p "${platform_dir}" "$(release_wasmvm_lib_dir "${platform}")" "$(dirname "${metadata_path}")"
mkdir -p "${release_tmp_root}"

build_linux_amd64() {
  local out_dir="$1"
  local cc_bin="cc"
  local native_arch

  native_arch="$(dpkg --print-architecture)"
  if [[ "${native_arch}" != "amd64" ]]; then
    command -v x86_64-linux-gnu-gcc >/dev/null 2>&1 \
      || release_die "phase-17: x86_64-linux-gnu-gcc is required for linux/amd64 release builds"
    cc_bin="x86_64-linux-gnu-gcc"
  fi

  release_gotmp_dir="$(mktemp -d "${release_tmp_root}/gotmp.XXXXXX")"
  release_tmp_dir="$(mktemp -d "${release_tmp_root}/tmp.XXXXXX")"

  export GOFLAGS="-buildvcs=false -p=1"
  export GOCACHE="${GOCACHE:-${host_cache_dir}/gocache}"
  export GOMODCACHE="${GOMODCACHE:-${host_cache_dir}/gomod}"
  export GOTMPDIR="${release_gotmp_dir}"
  export TMPDIR="${release_tmp_dir}"
  export GOOS=linux
  export GOARCH=amd64
  export GOAMD64=v1
  export CGO_ENABLED=1
  export CC="${cc_bin}"

  mkdir -p "${GOCACHE}" "${GOMODCACHE}" "${GOTMPDIR}" "${TMPDIR}" "${out_dir}/lib"

  go build -trimpath \
    -ldflags="-s -w \
      -X github.com/cosmos/cosmos-sdk/version.Name=kudora \
      -X github.com/cosmos/cosmos-sdk/version.AppName=kudorad \
      -X github.com/cosmos/cosmos-sdk/version.Version=$(release_version_tag) \
      -X github.com/cosmos/cosmos-sdk/version.Commit=${git_commit} \
      -X github.com/cosmos/cosmos-sdk/version.BuildTags=release,candidate,linux,amd64" \
    -o "${out_dir}/${RELEASE_BINARY_NAME}" ./cmd/${RELEASE_BINARY_NAME}

  go build -trimpath \
    -ldflags="-s -w" \
    -o "${out_dir}/kudora-evm-smoke-helper" ./testutil/evm-smoke

  mod_cache="$(go env GOMODCACHE)"
  wasmvm_lib="$(find "${mod_cache}" -path '*/github.com/!cosm!wasm/wasmvm/v3@*/internal/api/libwasmvm.x86_64.so' | head -n 1)"
  test -n "${wasmvm_lib}"
  cp "${wasmvm_lib}" "${out_dir}/lib/${lib_name}"
}

if [[ "${KUDORA_IN_DOCKER:-}" == "1" ]]; then
  build_linux_amd64 "${platform_dir}"
else
  docker run --rm \
    -v "${ROOT_DIR}:/workspace:ro" \
    -v "${platform_dir}:/out" \
    -v "${host_cache_dir}:/cache" \
    -w /workspace \
    "golang:1.26.4-bookworm" \
    bash -c '
      set -euo pipefail

      native_arch="$(dpkg --print-architecture)"
      cc_bin="cc"

      if [[ "${native_arch}" != "amd64" ]]; then
        apt-get update >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc-x86-64-linux-gnu libc6-dev-amd64-cross >/dev/null
        rm -rf /var/lib/apt/lists/*
        cc_bin="x86_64-linux-gnu-gcc"
      fi

      export GOFLAGS="-buildvcs=false -p=1"
      export GOCACHE=/cache/gocache
      export GOMODCACHE=/cache/gomod
      export GOTMPDIR=/cache/gotmp
      export TMPDIR=/cache/tmp
      export GOOS=linux
      export GOARCH=amd64
      export GOAMD64=v1
      export CGO_ENABLED=1
      export CC="${cc_bin}"

      mkdir -p "${GOCACHE}" "${GOMODCACHE}" "${GOTMPDIR}" "${TMPDIR}" /out/lib

      go build -trimpath \
        -ldflags="-s -w \
          -X github.com/cosmos/cosmos-sdk/version.Name=kudora \
          -X github.com/cosmos/cosmos-sdk/version.AppName=kudorad \
          -X github.com/cosmos/cosmos-sdk/version.Version='"$(release_version_tag)"' \
          -X github.com/cosmos/cosmos-sdk/version.Commit='"${git_commit}"' \
          -X github.com/cosmos/cosmos-sdk/version.BuildTags=release,candidate,linux,amd64" \
        -o /out/'"${RELEASE_BINARY_NAME}"' ./cmd/'"${RELEASE_BINARY_NAME}"'

      go build -trimpath \
        -ldflags="-s -w" \
        -o /out/kudora-evm-smoke-helper ./testutil/evm-smoke

      mod_cache="$(go env GOMODCACHE)"
      wasmvm_lib="$(find "${mod_cache}" -path '"'"'*/github.com/!cosm!wasm/wasmvm/v3@*/internal/api/libwasmvm.x86_64.so'"'"' | head -n 1)"
      test -n "${wasmvm_lib}"
      cp "${wasmvm_lib}" /out/lib/'"${lib_name}"'
    '
fi

chmod 0755 "${binary_path}"
chmod 0755 "${helper_path}"
chmod 0644 "${lib_path}"

printf '%s\n' "${platform}" >"${platforms_file}"

jq -n \
  --arg generated_at_utc "${build_created}" \
  --arg release_version "$(release_version_tag)" \
  --arg git_commit "${git_commit}" \
  --arg platform "${platform}" \
  --arg binary_path "$(release_repo_relpath "${binary_path}")" \
  --arg binary_sha256 "$(release_sha256_file "${binary_path}")" \
  --arg binary_file_type "$(file "${binary_path}")" \
  --arg helper_path "$(release_repo_relpath "${helper_path}")" \
  --arg helper_sha256 "$(release_sha256_file "${helper_path}")" \
  --arg wasmvm_library_path "$(release_repo_relpath "${lib_path}")" \
  --arg wasmvm_library_sha256 "$(release_sha256_file "${lib_path}")" \
  --arg wasmvm_library_name "${lib_name}" \
  '{
    generated_at_utc: $generated_at_utc,
    release_version: $release_version,
    git_commit: $git_commit,
    supported_platforms: [$platform],
    artifacts: [
      {
        platform: $platform,
        binary_path: $binary_path,
        binary_sha256: $binary_sha256,
        binary_file_type: $binary_file_type,
        helper_path: $helper_path,
        helper_sha256: $helper_sha256,
        wasmvm_library_path: $wasmvm_library_path,
        wasmvm_library_sha256: $wasmvm_library_sha256,
        wasmvm_library_name: $wasmvm_library_name
      }
    ]
  }' >"${metadata_path}"

echo "release-build-binaries: PASS (${binary_path})"
