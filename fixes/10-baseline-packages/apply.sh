#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

packages=(
  base-devel
  git
  pciutils
  usbutils
  linux-firmware
  linux-firmware-intel
  intel-ucode
  sof-firmware
  alsa-ucm-conf
  alsa-utils
  pipewire
  wireplumber
  pipewire-alsa
  pipewire-jack
  pipewire-pulse
  bluez
  bluez-utils
  fwupd
  dkms
  v4l2loopback-dkms
  gst-plugin-pipewire
  gstreamer
  gst-plugins-base
  gst-plugins-good
  gst-plugins-bad
  jq
)

pkgbase=$(kernel_pkgbase)
if [[ -n "$pkgbase" ]]; then
  packages+=("${pkgbase}-headers")
else
  warn "Could not determine active kernel package; install matching CachyOS kernel headers manually if DKMS is needed."
fi

install_packages "${packages[@]}"

if have_cmd systemctl; then
  enable_service bluetooth.service
fi
