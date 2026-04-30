#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
source "$ROOT_DIR/lib/common.sh"

if ! is_dell_xps; then
  log "Not a Dell XPS; skipping mic mute LED helper."
  exit 0
fi

install_packages pipewire pipewire-pulse wireplumber alsa-utils jq

if is_apply_mode; then
  as_root install -m 0755 "$SCRIPT_DIR/xps-audio-input-mute" /usr/local/bin/xps-audio-input-mute
else
  log "Would install /usr/local/bin/xps-audio-input-mute."
fi

log "Bind /usr/local/bin/xps-audio-input-mute to the microphone mute key in the desktop hotkey layer."
