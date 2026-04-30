#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

command_mode=${1:-audit}

pretty_name=$(awk -F= '/^PRETTY_NAME=/ { gsub(/"/, "", $2); print $2 }' /etc/os-release 2>/dev/null || true)
product_name=$(read_first /sys/class/dmi/id/product_name)
product_family=$(read_first /sys/class/dmi/id/product_family)
cpu_vendor=$(awk -F: '/^vendor_id/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' /proc/cpuinfo 2>/dev/null || true)
cpu_model=$(cpu_model_id)
pkgbase=$(kernel_pkgbase)
bootloader=$(active_bootloader)

log "OS: ${pretty_name:-unknown}"
log "DMI product: ${product_name:-unknown}"
log "DMI family: ${product_family:-unknown}"
log "CPU: vendor=${cpu_vendor:-unknown} model=${cpu_model:-unknown}"
log "Kernel: $(uname -r) pkgbase=${pkgbase:-unknown}"
log "Bootloader: $bootloader"

if is_cachyos; then
  log "CachyOS detection: yes"
else
  warn "CachyOS detection: no"
fi

if is_dell_xps; then
  log "Dell XPS detection: yes"
else
  log "Dell XPS detection: no"
fi

if is_panther_lake; then
  log "Panther Lake detection: yes"
else
  log "Panther Lake detection: no"
fi

if has_wifi7_intel_be; then
  log "Intel BE Wi-Fi 7 detection: yes"
else
  log "Intel BE Wi-Fi 7 detection: no"
fi

if has_synaptics_xps_haptic_touchpad; then
  log "Synaptics XPS haptic touchpad detection: yes"
else
  log "Synaptics XPS haptic touchpad detection: no"
fi

if has_ipu7_camera; then
  log "IPU7/OV08X40 camera detection: yes"
else
  log "IPU7/OV08X40 camera detection: no"
fi

if [[ "$command_mode" != "audit" ]]; then
  require_cachyos
  require_cmd pacman
  require_cmd systemctl
fi

if [[ -f /etc/pacman.conf ]] && grep -q '\[cachyos-v4\]' /etc/pacman.conf 2>/dev/null; then
  warn "cachyos-v4 repo appears enabled. Intel hybrid laptops should usually stay on x86-64-v3 repos."
fi
