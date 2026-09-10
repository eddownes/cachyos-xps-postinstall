#!/usr/bin/env bash
# IPU7/OV08X40 camera bring-up for Pop!_OS Cosmic 24.04 (Ubuntu 24.04-based) on
# Panther Lake hardware. Ports the two fixes worked out on CachyOS in
# ../fixes/70-ipu7-camera to apt/DKMS. See README.md in this directory for
# status: this has NOT been verified end-to-end on real Pop!_OS hardware.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"
BACKUP_DIR=/var/backups/popos-ipu7-camera

log()  { printf '[ipu7-camera] %s\n' "$*"; }
warn() { printf '[ipu7-camera] warning: %s\n' "$*" >&2; }
die()  { printf '[ipu7-camera] error: %s\n' "$*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] && die "Run as your normal user, not root. sudo is invoked only where needed."

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

as_root() { sudo "$@"; }

backup_file() {
  local path=$1
  [[ -e "$path" ]] || return 0
  local dest="$BACKUP_DIR${path}.$(date +%Y%m%d%H%M%S)"
  as_root mkdir -p "$(dirname "$dest")"
  as_root cp -a "$path" "$dest"
}

install_asset() {
  local src=$1 dest=$2 mode=${3:-0644}
  backup_file "$dest"
  as_root mkdir -p "$(dirname "$dest")"
  as_root install -m "$mode" "$src" "$dest"
  log "Installed $dest"
}

target_user() {
  local user=${SUDO_USER:-${USER:-}}
  [[ -n "$user" && "$user" != "root" ]] && printf '%s\n' "$user" || logname 2>/dev/null || true
}

has_ipu7_camera() {
  grep -q 'OVTI08F4' /sys/bus/acpi/devices/*/hid 2>/dev/null
}

is_panther_lake() {
  command -v lspci >/dev/null 2>&1 && lspci | grep -iE 'vga|3d|display' | grep -qi 'panther lake'
}

# --- Preflight -------------------------------------------------------------

if ! grep -qiE '^ID=(pop|ubuntu)' /etc/os-release 2>/dev/null; then
  warn "This does not look like Pop!_OS or Ubuntu (/etc/os-release ID). Continuing anyway, but package names below are apt/deb-specific."
fi

if ! has_ipu7_camera; then
  die "No OVTI08F4 (IPU7/OV08X40) ACPI device found. Nothing to do."
fi

if ! is_panther_lake; then
  warn "Could not confirm Panther Lake GPU via lspci; continuing since the OV08X40 ACPI device is present."
fi

require_cmd apt-get
require_cmd dpkg

log "Detected IPU7/OV08X40 camera. Proceeding."

# --- Packages ----------------------------------------------------------

log "Adding ppa:oem-solutions-group/intel-ipu7 (Intel's own development PPA for this stack)."
as_root apt-get install -y software-properties-common
as_root add-apt-repository -y ppa:oem-solutions-group/intel-ipu7
as_root apt-get update

as_root apt-get install -y build-essential dkms "linux-headers-$(uname -r)" git v4l2loopback-dkms

# Package names for the IPU7 userspace stack are new (Panther Lake support
# only landed in the Intel PPA recently) and vary by naming generation. Try
# known candidates one at a time instead of a single apt-get install so one
# missing/renamed package doesn't abort the whole run.
declare -a wanted=(
  intel-ipu7-dkms
  v4l2-relayd
  gstreamer1.0-icamera
  gst-plugins-icamera
  libcamhal-ipu7x
  libcamhal-ipu75xa
)
declare -a installed=()
declare -a missing=()

for pkg in "${wanted[@]}"; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    if as_root apt-get install -y "$pkg"; then
      installed+=("$pkg")
    else
      missing+=("$pkg (found in apt-cache, install failed)")
    fi
  else
    missing+=("$pkg (not found in enabled repos)")
  fi
done

log "Installed: ${installed[*]:-none}"
if ((${#missing[@]})); then
  warn "Not installed: ${missing[*]}"
  warn "This is expected for the *x/*75xa HAL alternatives (only one applies to your exact IPU7 stepping) and for whichever of gstreamer1.0-icamera/gst-plugins-icamera your Ubuntu series doesn't use."
fi

log "Intel's intel_cvs (ACPI camera-ownership) driver has no confirmed apt package name yet as of this writing. Search for it yourself:"
log "  apt-cache search icvs cvs ivsc | grep -i -E 'icvs|ivsc|cvs'"
log "If nothing turns up, you likely need to build github.com/intel/vision-drivers from source via dkms, the same way CachyOS users had to before it was packaged there."

# --- Module load order fix --------------------------------------------------

install_asset "$ASSETS_DIR/camera-deps.conf" /etc/modprobe.d/ipu7-camera-deps.conf
install_asset "$ASSETS_DIR/v4l2loopback-camera.conf" /etc/modprobe.d/v4l2loopback-camera.conf

# --- systemd units -----------------------------------------------------

install_asset "$ASSETS_DIR/camera-init.service" /etc/systemd/system/camera-init.service
install_asset "$ASSETS_DIR/camera-sleep-hook" /usr/lib/systemd/system-sleep/camera-sleep-hook 0755

user=$(target_user || true)
uid=1000
[[ -n "${user:-}" ]] && uid=$(id -u "$user" 2>/dev/null || echo 1000)

install_asset "$ASSETS_DIR/v4l2-relayd-ipu7.conf" /etc/v4l2-relayd.d/ipu7.conf

backup_file /etc/systemd/system/v4l2-relayd@ipu7.service.d/override.conf
as_root mkdir -p /etc/systemd/system/v4l2-relayd@ipu7.service.d
as_root tee /etc/systemd/system/v4l2-relayd@ipu7.service.d/override.conf >/dev/null <<EOF
[Unit]
After=camera-init.service

[Service]
Environment=GST_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/gstreamer-1.0
PrivateNetwork=no
InaccessibleDirectories=
ReadOnlyDirectories=
DevicePolicy=auto
DeviceAllow=char-intel-ipu7-psys
ExecStartPost=/bin/bash -c 'sleep 2 && systemctl --user -M ${uid}@ restart wireplumber.service 2>/dev/null || true'
EOF
log "Installed /etc/systemd/system/v4l2-relayd@ipu7.service.d/override.conf"
log "NOTE: verify /dev/ipu7-psys0's real udev SUBSYSTEM on your machine with:"
log "  udevadm info -q all -n /dev/ipu7-psys0 | grep SUBSYSTEM"
log "If it isn't exactly 'intel-ipu7-psys', edit DeviceAllow= above to match, or the psys open will still fail with EPERM."

# --- udev / wireplumber / tmpfiles (only if applicable) -------------------

udev_dir=/usr/lib/udev/rules.d
[[ -d /lib/udev/rules.d && ! -d "$udev_dir" ]] && udev_dir=/lib/udev/rules.d
install_asset "$ASSETS_DIR/71-ipu7-hide-isys.rules" "$udev_dir/71-ipu7-hide-isys.rules"
install_asset "$ASSETS_DIR/90-ipu7-psys.rules" "$udev_dir/90-ipu7-psys.rules"

if [[ -d /usr/share/wireplumber ]]; then
  install_asset "$ASSETS_DIR/hide-ipu7-v4l2.conf" /usr/share/wireplumber/wireplumber.conf.d/hide-ipu7-v4l2.conf
  install_asset "$ASSETS_DIR/disable-libcamera.conf" /usr/share/wireplumber/wireplumber.conf.d/disable-libcamera.conf
else
  warn "No /usr/share/wireplumber found; skipping wireplumber config (install pipewire-wireplumber if COSMIC's camera portal needs it)."
fi

install_asset "$ASSETS_DIR/camera-tmpfiles.conf" /usr/lib/tmpfiles.d/camera.conf
as_root systemd-tmpfiles --create /usr/lib/tmpfiles.d/camera.conf || true

# --- enable everything -------------------------------------------------

as_root udevadm control --reload-rules
as_root systemctl daemon-reload
as_root systemctl enable camera-init.service
as_root systemctl enable v4l2-relayd@ipu7.service 2>/dev/null || warn "v4l2-relayd@ipu7.service not found yet; enable it once the v4l2-relayd package installs its unit."

if [[ -n "${user:-}" ]]; then
  as_root usermod -aG video "$user"
else
  warn "Could not determine target user; add yourself to the 'video' group manually."
fi

log "Done. Reboot, then test with a REAL app (Cheese, a browser) or a sustained capture:"
log "  timeout 8 v4l2-ctl -d /dev/video50 --stream-mmap --stream-count=60 --stream-to=/tmp/frame.raw"
log "A single-frame test (--stream-count=1) can look black even when everything works — v4l2-relayd only switches from its placeholder image to the real feed once a client holds the device open for a sustained period."
