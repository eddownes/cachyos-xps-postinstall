#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

install_asset() {
  local src=$1
  local dest=$2
  local mode=${3:-0644}
  if ! is_apply_mode; then
    log "Would install $dest from ${src#$SCRIPT_DIR/}"
    return 0
  fi

  backup_file "$dest"
  as_root mkdir -p "$(dirname "$dest")"
  as_root install -m "$mode" "$src" "$dest"
}

target_user() {
  local user=${SUDO_USER:-${USER:-}}
  if [[ -z "$user" || "$user" == "root" ]]; then
    user=$(logname 2>/dev/null || true)
  fi
  [[ -n "$user" && "$user" != "root" ]] && printf '%s\n' "$user"
}

add_pipewire_camera_flag() {
  local user=$1
  local conf=$2

  if ! is_apply_mode; then
    log "Would ensure PipeWireCamera in $conf"
    return 0
  fi

  as_root bash -c '
    set -e
    user=$1
    conf=$2
    mkdir -p "$(dirname "$conf")"
    touch "$conf"
    chown "$user:$user" "$conf"
    if grep -q "PipeWireCamera" "$conf"; then
      exit 0
    fi
    if grep -q -- "--enable-features=" "$conf"; then
      sed -i "s/--enable-features=\([^ ]*\)/--enable-features=\1,PipeWireCamera/" "$conf"
    else
      printf "%s\n" "--enable-features=PipeWireCamera" >>"$conf"
    fi
    chown "$user:$user" "$conf"
  ' _ "$user" "$conf"
}

apply_runtime_config() {
  local user uid
  user=$(target_user || true)
  if [[ -n "${user:-}" ]]; then
    uid=$(id -u "$user" 2>/dev/null || true)
  fi
  uid=${uid:-1000}

  install_asset "$SCRIPT_DIR/assets/camera-deps.conf" /usr/lib/modprobe.d/camera-deps.conf
  install_asset "$SCRIPT_DIR/assets/v4l2loopback-camera.conf" /usr/lib/modprobe.d/v4l2loopback-camera.conf
  install_asset "$SCRIPT_DIR/assets/camera-init.service" /usr/lib/systemd/system/camera-init.service
  install_asset "$SCRIPT_DIR/assets/intel-ipu7-camera.service" /usr/lib/systemd/system/intel-ipu7-camera.service
  install_asset "$SCRIPT_DIR/assets/hide-ipu7-v4l2.conf" /usr/share/wireplumber/wireplumber.conf.d/hide-ipu7-v4l2.conf
  install_asset "$SCRIPT_DIR/assets/disable-libcamera.conf" /usr/share/wireplumber/wireplumber.conf.d/disable-libcamera.conf
  install_asset "$SCRIPT_DIR/assets/71-ipu7-hide-isys.rules" /usr/lib/udev/rules.d/71-ipu7-hide-isys.rules
  install_asset "$SCRIPT_DIR/assets/90-ipu7-psys.rules" /usr/lib/udev/rules.d/90-ipu7-psys.rules
  install_asset "$SCRIPT_DIR/assets/v4l2-relayd-ipu7.conf" /etc/v4l2-relayd.d/ipu7.conf
  write_root_file /etc/systemd/system/v4l2-relayd@ipu7.service.d/override.conf 0644 <<EOF
[Unit]
After=camera-init.service

[Service]
Environment=GST_PLUGIN_PATH=/usr/lib/gstreamer-1.0
PrivateNetwork=no
InaccessibleDirectories=
ReadOnlyDirectories=
DevicePolicy=auto
DeviceAllow=char-intel-ipu7-psys
ExecStartPost=/bin/bash -c 'sleep 2 && systemctl --user -M ${uid}@ restart wireplumber.service 2>/dev/null || true'
EOF
  install_asset "$SCRIPT_DIR/assets/camera-tmpfiles.conf" /usr/lib/tmpfiles.d/camera.conf
  install_asset "$SCRIPT_DIR/assets/ov08x40.yaml" /usr/share/libcamera/ipa/simple/ov08x40.yaml
  install_asset "$SCRIPT_DIR/assets/camera-sleep-hook" /usr/lib/systemd/system-sleep/camera-sleep-hook 0755

  reload_udev
  reload_systemd

  if is_apply_mode; then
    as_root systemd-tmpfiles --create /usr/lib/tmpfiles.d/camera.conf || true
    as_root systemctl disable camera-init.service v4l2-relayd@ipu7.service 2>/dev/null || true
  fi
  enable_service intel-ipu7-camera.service

  if [[ -n "${user:-}" ]]; then
    if is_apply_mode; then
      as_root usermod -aG video "$user" || true
    else
      log "Would add $user to video group."
    fi
    add_pipewire_camera_flag "$user" "/home/$user/.config/chromium-flags.conf"
    add_pipewire_camera_flag "$user" "/home/$user/.config/brave-flags.conf"
    add_pipewire_camera_flag "$user" "/home/$user/.config/chrome-flags.conf"
  else
    warn "Could not determine target user for browser camera flags."
  fi
}

if ! has_ipu7_camera; then
  log "No IPU7/OV08X40 camera detected; skipping camera module."
  exit 0
fi

install_packages dkms v4l2loopback-dkms gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad jsoncpp libdrm

if pacman -Q intel-ipu7-camera >/dev/null 2>&1; then
  log "intel-ipu7-camera already installed."
elif [[ "${CACHY_XPS_BUILD_CAMERA:-0}" == "1" ]]; then
  if is_apply_mode && [[ "$CACHY_XPS_DRY_RUN" != "1" ]]; then
    bash "$SCRIPT_DIR/build.sh"
  else
    log "Would build intel-ipu7-camera from Omarchy package sources."
  fi
else
  warn "IPU7 camera detected but intel-ipu7-camera is not installed. Re-run with --build-camera or install the package first."
  exit 0
fi

apply_runtime_config
