#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

if ! is_dell_xps; then
  log "Not a Dell XPS; skipping haptic touchpad module."
  exit 0
fi

if ! has_synaptics_xps_haptic_touchpad; then
  log "No Synaptics 06CB I2C haptic touchpad detected; skipping."
  exit 0
fi

install_packages python

if is_apply_mode; then
  as_root install -m 0755 "$SCRIPT_DIR/dell-xps-haptic-touchpad.py" /usr/local/bin/dell-xps-haptic-touchpad
  as_root install -m 0755 "$SCRIPT_DIR/dell-xps-restart-trackpad" /usr/local/bin/dell-xps-restart-trackpad
else
  log "Would install haptic daemon and restart helper to /usr/local/bin."
fi

write_root_file /etc/udev/rules.d/99-dell-xps-haptic-touchpad.rules 0644 <<'EOF'
# Keep I2C controller power on so the Synaptics haptic engine does not lose state.
ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:00:19.0", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="i2c_designware.0", ATTR{power/control}="on"
EOF

write_root_file /etc/systemd/system/dell-xps-haptic-touchpad.service 0644 <<'EOF'
[Unit]
Description=Dell XPS haptic touchpad feedback
After=systemd-udev-settle.service

[Service]
Type=simple
ExecStart=/usr/local/bin/dell-xps-haptic-touchpad
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

reload_udev
reload_systemd
enable_service dell-xps-haptic-touchpad.service
