#!/usr/bin/env bash
set -Eeuo pipefail

export CACHY_XPS_COMMAND=${CACHY_XPS_COMMAND:-apply}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

require_cachyos
require_cmd git
require_cmd makepkg

if [[ "${CACHY_XPS_DRY_RUN:-0}" == "1" ]]; then
  log "Would clone Omarchy package sources and build v4l2-relayd/intel-ipu7-camera."
  exit 0
fi

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "Do not run the camera build as root. Run run.sh as your user; it will use sudo only where needed."
fi

pkgbase=$(kernel_pkgbase)
[[ -n "$pkgbase" ]] || die "Could not determine active kernel package."
header_pkg="${pkgbase}-headers"

build_root=${CACHY_XPS_CAMERA_BUILD_ROOT:-/var/tmp/cachyos-xps-camera-build}
repo_url=${CACHY_XPS_OMARCHY_PKGS_URL:-https://github.com/omacom-io/omarchy-pkgs.git}
repo_ref=${CACHY_XPS_OMARCHY_PKGS_REF:-main}
repo_dir="$build_root/omarchy-pkgs"

install_packages git base-devel dkms "$header_pkg" cmake autoconf automake libtool pkgconf jsoncpp libdrm \
  v4l2loopback-dkms gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad

mkdir -p "$build_root"

if [[ -d "$repo_dir/.git" ]]; then
  git -C "$repo_dir" fetch --depth 1 origin "$repo_ref"
  git -C "$repo_dir" checkout FETCH_HEAD
else
  git clone --depth 1 --branch "$repo_ref" "$repo_url" "$repo_dir"
fi

build_pkg() {
  local name=$1
  local source_dir=$2
  local work_dir="$build_root/$name"

  rm -rf "$work_dir"
  cp -a "$source_dir" "$work_dir"

  if [[ "$name" == "intel-ipu7-camera" ]]; then
    sed -i "s/'linux-headers'/'$header_pkg'/" "$work_dir/PKGBUILD"
  fi

  log "Building $name from $work_dir"
  (cd "$work_dir" && makepkg -si --noconfirm)
}

if [[ -d "$repo_dir/pkgbuilds/edge/v4l2-relayd" ]] && ! pacman -Q v4l2-relayd >/dev/null 2>&1; then
  build_pkg v4l2-relayd "$repo_dir/pkgbuilds/edge/v4l2-relayd"
fi

build_pkg intel-ipu7-camera "$repo_dir/pkgbuilds/edge/intel-ipu7-camera"
