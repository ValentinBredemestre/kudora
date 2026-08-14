#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${KUDORA_DEVTOOLS_IMAGE:-kudora/devtools:local}"
CACHE_VOLUME="${KUDORA_DEVTOOLS_CACHE:-kudora-devtools-cache}"
ACTION="${1:-run}"

build_image() {
  local force="${1:-0}"
  if [[ "${force}" == "1" ]] || ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    DOCKER_BUILDKIT=1 docker buildx build \
      --load \
      --tag "${IMAGE}" \
      --file "${ROOT_DIR}/docker/devtools/Dockerfile" \
      "${ROOT_DIR}"
  fi
}

case "${ACTION}" in
  build)
    build_image 1
    ;;
  run)
    shift
    [[ $# -gt 0 ]] || {
      echo "usage: $0 run <command> [args...]" >&2
      exit 1
    }

    build_image 0
    socket_gid="$(docker run --rm \
      --entrypoint stat \
      --volume /var/run/docker.sock:/var/run/docker.sock \
      "${IMAGE}" -c '%g' /var/run/docker.sock)"

    exec docker run --rm \
      --add-host host.docker.internal:host-gateway \
      --env DOCKER_SOCKET_GID="${socket_gid}" \
      --env LOCAL_GID="$(id -g)" \
      --env LOCAL_UID="$(id -u)" \
      --volume /var/run/docker.sock:/var/run/docker.sock \
      --volume "${CACHE_VOLUME}:/cache" \
      --volume "${ROOT_DIR}:${ROOT_DIR}" \
      --workdir "${ROOT_DIR}" \
      "${IMAGE}" "$@"
    ;;
  *)
    echo "usage: $0 build|run <command> [args...]" >&2
    exit 1
    ;;
esac
