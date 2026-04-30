#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

if have_cmd lspci && lspci | grep -iE 'vga|3d|display' | grep -qi 'intel'; then
  install_packages intel-media-driver libvpl vpl-gpu-rt vulkan-intel
else
  log "No Intel GPU detected; skipping Intel media packages."
fi

if is_intel_cpu && has_battery; then
  install_packages thermald power-profiles-daemon
  enable_service thermald.service
  enable_service power-profiles-daemon.service
else
  log "Not an Intel laptop with battery; skipping thermald/power-profiles-daemon enablement."
fi

if is_intel_cpu && has_battery; then
  cpu_model=$(cpu_model_id)
  if [[ "$cpu_model" =~ ^(151|154|170|172|183|186|189|191|204)$ ]]; then
    install_optional_package intel-lpmd
    if is_apply_mode && systemctl list-unit-files intel_lpmd.service >/dev/null 2>&1; then
      enable_service intel_lpmd.service
    elif ! is_apply_mode; then
      log "Would enable intel_lpmd.service if intel-lpmd is available."
    else
      warn "intel_lpmd.service was not found after package check."
    fi
  else
    log "Intel CPU model $cpu_model is not in the intel-lpmd target set."
  fi
fi
