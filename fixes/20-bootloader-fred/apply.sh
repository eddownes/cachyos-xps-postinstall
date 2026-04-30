#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

if [[ "${CACHY_XPS_ENABLE_FRED:-1}" != "1" ]]; then
  log "FRED boot arg module disabled."
  exit 0
fi

if ! is_panther_lake; then
  log "Not Panther Lake; skipping fred=on."
  exit 0
fi

log "Panther Lake detected; ensuring fred=on is present through the active bootloader."
add_kernel_arg "fred=on"
