#!/usr/bin/env bash

set -euo pipefail

[[ $# -gt 0 ]] || {
  echo "usage: $0 <command> [args...]" >&2
  exit 1
}

case "$(uname -m)" in
  aarch64|arm64)
    library_name="libwasmvm.aarch64.so"
    ;;
  x86_64)
    library_name="libwasmvm.x86_64.so"
    ;;
  *)
    echo "with-wasmvm: unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

module_cache="$(go env GOMODCACHE)"
library_path="$(find "${module_cache}" -path "*/github.com/!cosm!wasm/wasmvm/v3@*/internal/api/${library_name}" | head -n 1)"
[[ -n "${library_path}" ]] || {
  echo "with-wasmvm: ${library_name} is missing from the Go module cache" >&2
  exit 1
}

export LD_LIBRARY_PATH="$(dirname "${library_path}")${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "$@"
