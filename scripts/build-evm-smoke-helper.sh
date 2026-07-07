#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <output-path>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$1"
TMP_ROOT="${ROOT_DIR}/tmp/go-build"
GOTMP_DIR=""
TMP_DIR=""

cleanup() {
  [[ -n "${GOTMP_DIR}" ]] && rm -rf "${GOTMP_DIR}" >/dev/null 2>&1 || true
  [[ -n "${TMP_DIR}" ]] && rm -rf "${TMP_DIR}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${TMP_ROOT}" "$(dirname "${OUTPUT_PATH}")"
GOTMP_DIR="$(mktemp -d "${TMP_ROOT}/gotmp.XXXXXX")"
TMP_DIR="$(mktemp -d "${TMP_ROOT}/tmp.XXXXXX")"

GOFLAGS="-buildvcs=false -p=1" \
GOTMPDIR="${GOTMP_DIR}" \
TMPDIR="${TMP_DIR}" \
go build -o "${OUTPUT_PATH}" ./testutil/evm-smoke
