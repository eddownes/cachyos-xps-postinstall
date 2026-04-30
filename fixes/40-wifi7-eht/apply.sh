#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

if ! has_wifi7_intel_be; then
  log "No Intel BE200/BE211 Wi-Fi detected; skipping EHT workaround."
  exit 0
fi

if ! is_dell_xps || ! is_panther_lake; then
  warn "Intel BE Wi-Fi detected, but this is not a Dell XPS Panther Lake match. Skipping automatic EHT disable."
  exit 0
fi

write_root_file /etc/modprobe.d/iwlwifi-disable-eht.conf 0644 <<'EOF'
# Temporary Dell XPS Panther Lake workaround.
# Disable Wi-Fi 7 EHT/802.11be on Intel BE200/BE211 while firmware/driver RX
# rate adaptation is unreliable. Remove this file once the iwlwifi EHT path is fixed.
options iwlwifi disable_11be=Y
EOF

warn "Wi-Fi 7 EHT disable takes effect after reloading iwlwifi or rebooting."
