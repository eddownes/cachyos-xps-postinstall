#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export CACHY_XPS_ROOT="$ROOT_DIR"

source "$ROOT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh audit [--build-camera]
  ./run.sh install [--yes] [--build-camera] [--firmware-update]
  ./run.sh apply [--yes] [--build-camera]

Commands:
  audit        Detect hardware and print what would change.
  install      Full post-install pass. Runs system update first, then modules.
  apply        Apply modules without the initial full system update.

Options:
  --yes             Skip interactive confirmations.
  --dry-run         Print commands and file writes without applying them.
  --build-camera    Build/install the IPU7 camera packages when matching hardware is present.
  --firmware-update Run fwupdmgr update after listing firmware updates.
  --no-fred         Skip the Panther Lake fred=on bootloader module.
EOF
}

COMMAND=${1:-audit}
shift || true

case "$COMMAND" in
  audit|install|apply) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    die "Unknown command: $COMMAND"
    ;;
esac

export CACHY_XPS_COMMAND="$COMMAND"
export CACHY_XPS_YES=0
export CACHY_XPS_DRY_RUN=0
export CACHY_XPS_BUILD_CAMERA=0
export CACHY_XPS_FIRMWARE_UPDATE=0
export CACHY_XPS_ENABLE_FRED=1

while (($#)); do
  case "$1" in
    --yes|-y) CACHY_XPS_YES=1 ;;
    --dry-run) CACHY_XPS_DRY_RUN=1 ;;
    --build-camera) CACHY_XPS_BUILD_CAMERA=1 ;;
    --firmware-update) CACHY_XPS_FIRMWARE_UPDATE=1 ;;
    --no-fred) CACHY_XPS_ENABLE_FRED=0 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

if [[ "$COMMAND" == "install" ]]; then
  CACHY_XPS_BUILD_CAMERA=1
fi

export CACHY_XPS_YES CACHY_XPS_DRY_RUN CACHY_XPS_BUILD_CAMERA
export CACHY_XPS_FIRMWARE_UPDATE CACHY_XPS_ENABLE_FRED

log "CachyOS XPS post-install toolkit"
log "Command: $COMMAND"

if [[ "$COMMAND" == "install" ]]; then
  require_cachyos
  confirm "Run full system update with pacman -Syu before applying fixes?"
  as_root pacman -Syu --noconfirm
fi

modules=(
  "$ROOT_DIR/fixes/00-preflight/apply.sh"
  "$ROOT_DIR/fixes/10-baseline-packages/apply.sh"
  "$ROOT_DIR/fixes/20-bootloader-fred/apply.sh"
  "$ROOT_DIR/fixes/30-intel-power-media/apply.sh"
  "$ROOT_DIR/fixes/40-wifi7-eht/apply.sh"
  "$ROOT_DIR/fixes/50-haptic-touchpad/apply.sh"
  "$ROOT_DIR/fixes/60-mic-mute-led/apply.sh"
  "$ROOT_DIR/fixes/70-ipu7-camera/apply.sh"
  "$ROOT_DIR/fixes/80-firmware/apply.sh"
)

for module in "${modules[@]}"; do
  module_name=${module#"$ROOT_DIR/fixes/"}
  module_name=${module_name%/apply.sh}
  log "Running module: $module_name"
  bash "$module" "$COMMAND"
done

log "Complete."
if [[ "$COMMAND" != "audit" ]]; then
  warn "Reboot after kernel, DKMS, firmware, or bootloader changes."
fi
