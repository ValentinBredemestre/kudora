#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_docker
release_require_candidate_genesis

platform="$(release_linux_amd64_platform)"
docker_platform="$(release_runtime_docker_platform)"
binary_path="$(release_binary_path "${platform}")"
helper_path="$(release_evm_helper_path "${platform}")"
lib_name="$(release_required_wasmvm_library "${platform}")"
lib_path="$(release_wasmvm_lib_path "${platform}" "${lib_name}")"
prebuilt_dir="${RELEASE_DOCKER_TMP_DIR}/prebuilt-runtime"
git_commit="$(release_git_commit)"
image_created="$(release_now_utc)"
primary_tag="$(release_docker_image_tag)"
alias_tag="$(release_docker_image_latest_rc_tag)"
result_path="${RELEASE_OUT_DIR}/docker-image.json"

if [[ ! -f "${binary_path}" || ! -f "${helper_path}" || ! -f "${lib_path}" ]]; then
  "${ROOT_DIR}/scripts/release/build-binaries.sh" >/dev/null
fi

rm -rf "${prebuilt_dir}"
mkdir -p "${prebuilt_dir}/usr/local/bin" "${prebuilt_dir}/usr/lib"
cp "${binary_path}" "${prebuilt_dir}/usr/local/bin/kudorad"
cp "${helper_path}" "${prebuilt_dir}/usr/local/bin/kudora-evm-smoke-helper"
cp "${lib_path}" "${prebuilt_dir}/usr/lib/${lib_name}"

docker buildx build \
  --load \
  --platform "${docker_platform}" \
  --target runtime-prebuilt \
  --build-context "prebuilt=${prebuilt_dir}" \
  --tag "${primary_tag}" \
  --tag "${alias_tag}" \
  --build-arg APP_VERSION="$(release_version_tag)" \
  --build-arg GIT_COMMIT="${git_commit}" \
  --build-arg BUILD_TAGS="release,candidate,docker" \
  --build-arg IMAGE_CREATED="${image_created}" \
  --build-arg RELEASE_TRACK="${RELEASE_TRACK}" \
  --build-arg MAINNET_LAUNCH_READY="false" \
  --file "${ROOT_DIR}/Dockerfile" \
  "${ROOT_DIR}" >/dev/null

jq -n \
  --arg built_at_utc "${image_created}" \
  --arg primary_tag "${primary_tag}" \
  --arg alias_tag "${alias_tag}" \
  --arg docker_platform "${docker_platform}" \
  --arg image_id "$(docker image inspect "${primary_tag}" --format '{{.Id}}')" \
  --arg image_size_bytes "$(docker image inspect "${primary_tag}" --format '{{.Size}}')" \
  '{
    built_at_utc: $built_at_utc,
    primary_tag: $primary_tag,
    alias_tag: $alias_tag,
    docker_platform: $docker_platform,
    image_id: $image_id,
    image_size_bytes: ($image_size_bytes | tonumber)
  }' >"${result_path}"

echo "release-docker-build: PASS (${primary_tag})"
