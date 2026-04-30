#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

install_packages fwupd

if ! is_apply_mode; then
  log "Would run fwupdmgr refresh and fwupdmgr get-updates."
  if [[ "${CACHY_XPS_FIRMWARE_UPDATE:-0}" == "1" ]]; then
    log "Would run fwupdmgr update after refresh."
  fi
  exit 0
fi

if ! have_cmd fwupdmgr; then
  warn "fwupdmgr not found after package step."
  exit 0
fi

as_root fwupdmgr refresh --force || true
as_root fwupdmgr get-devices || true
as_root fwupdmgr get-updates || true

if [[ "${CACHY_XPS_FIRMWARE_UPDATE:-0}" == "1" ]]; then
  if [[ -r /sys/class/power_supply/AC/online ]] && [[ "$(cat /sys/class/power_supply/AC/online)" != "1" ]]; then
    warn "AC power is not detected; skipping firmware update."
    exit 0
  fi
  confirm "Run fwupdmgr update now? This can stage BIOS/UEFI updates and require a reboot."
  as_root fwupdmgr update
else
  log "Firmware updates were listed only. Re-run with --firmware-update to apply them."
fi
