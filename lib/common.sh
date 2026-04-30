#!/usr/bin/env bash

: "${CACHY_XPS_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${CACHY_XPS_COMMAND:=audit}"
: "${CACHY_XPS_YES:=0}"
: "${CACHY_XPS_DRY_RUN:=0}"

STATE_DIR=/var/lib/cachyos-xps-fixes
BACKUP_DIR=/var/backups/cachyos-xps-fixes

log() {
  printf '[cachyos-xps] %s\n' "$*"
}

warn() {
  printf '[cachyos-xps] warning: %s\n' "$*" >&2
}

die() {
  printf '[cachyos-xps] error: %s\n' "$*" >&2
  exit 1
}

is_apply_mode() {
  [[ "$CACHY_XPS_COMMAND" == "apply" || "$CACHY_XPS_COMMAND" == "install" ]]
}

confirm() {
  local prompt=$1
  if [[ "$CACHY_XPS_YES" == "1" || "$CACHY_XPS_DRY_RUN" == "1" ]]; then
    log "$prompt"
    return 0
  fi
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

as_root() {
  if [[ "$CACHY_XPS_DRY_RUN" == "1" ]]; then
    printf '[dry-run root]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_cmd() {
  if [[ "$CACHY_XPS_DRY_RUN" == "1" ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  have_cmd "$1" || die "Required command not found: $1"
}

read_first() {
  local path=$1
  [[ -r "$path" ]] && head -n 1 "$path" || true
}

is_cachyos() {
  grep -qi '^ID=.*cachyos' /etc/os-release 2>/dev/null ||
    pacman -Q cachyos-keyring >/dev/null 2>&1
}

require_cachyos() {
  is_cachyos || die "This toolkit is gated to CachyOS. Run audit for detection, but install/apply requires CachyOS."
}

is_dell_xps() {
  grep -qi 'XPS' /sys/class/dmi/id/product_name 2>/dev/null ||
    grep -qi 'XPS' /sys/class/dmi/id/product_family 2>/dev/null
}

is_intel_cpu() {
  grep -qm1 '^vendor_id[[:space:]]*: GenuineIntel' /proc/cpuinfo 2>/dev/null
}

has_battery() {
  local bat
  for bat in /sys/class/power_supply/BAT*; do
    [[ -r "$bat/present" && -r "$bat/type" ]] || continue
    [[ "$(cat "$bat/present")" == "1" && "$(cat "$bat/type")" == "Battery" ]] && return 0
  done
  return 1
}

cpu_model_id() {
  awk -F: '/^model[[:space:]]*:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' /proc/cpuinfo 2>/dev/null
}

is_panther_lake() {
  if have_cmd lspci && lspci | grep -iE 'vga|3d|display' | grep -qi 'panther lake'; then
    return 0
  fi

  [[ "$(cpu_model_id)" == "204" ]]
}

has_wifi7_intel_be() {
  have_cmd lspci || return 1
  lspci -nn | grep -qE '\[8086:(e440|272b)\]'
}

has_synaptics_xps_haptic_touchpad() {
  compgen -G '/sys/bus/i2c/devices/i2c-VEN_06CB:00' >/dev/null
}

has_ipu7_camera() {
  grep -q 'OVTI08F4' /sys/bus/acpi/devices/*/hid 2>/dev/null
}

kernel_pkgbase() {
  local pkgbase_file="/usr/lib/modules/$(uname -r)/pkgbase"
  if [[ -r "$pkgbase_file" ]]; then
    cat "$pkgbase_file"
    return 0
  fi

  pacman -Qoq "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -n 1 || true
}

install_packages() {
  local packages=("$@")
  ((${#packages[@]})) || return 0

  if ! is_apply_mode; then
    log "Would install packages: ${packages[*]}"
    return 0
  fi

  require_cachyos
  as_root pacman -S --needed --noconfirm "${packages[@]}"
}

package_available() {
  local pkg=$1
  pacman -Si "$pkg" >/dev/null 2>&1
}

install_optional_package() {
  local pkg=$1
  if ! package_available "$pkg"; then
    warn "Package not found in enabled repos: $pkg"
    return 0
  fi
  install_packages "$pkg"
}

enable_service() {
  local service=$1
  if ! is_apply_mode; then
    log "Would enable service: $service"
    return 0
  fi
  as_root systemctl enable "$service"
}

enable_now_service() {
  local service=$1
  if ! is_apply_mode; then
    log "Would enable and start service: $service"
    return 0
  fi
  as_root systemctl enable --now "$service"
}

backup_file() {
  local path=$1
  [[ -e "$path" ]] || return 0

  local stamp dest
  stamp=$(date +%Y%m%d%H%M%S)
  dest="$BACKUP_DIR${path}.$stamp"

  if [[ "$CACHY_XPS_DRY_RUN" == "1" ]] || ! is_apply_mode; then
    log "Would back up $path to $dest"
    return 0
  fi

  as_root mkdir -p "$(dirname "$dest")"
  as_root cp -a "$path" "$dest"
}

write_root_file() {
  local path=$1
  local mode=${2:-0644}
  local tmp
  tmp=$(mktemp)
  cat >"$tmp"

  if [[ "$CACHY_XPS_DRY_RUN" == "1" ]] || ! is_apply_mode; then
    log "Would write $path"
    sed 's/^/  | /' "$tmp"
    rm -f "$tmp"
    return 0
  fi

  backup_file "$path"
  as_root mkdir -p "$(dirname "$path")"
  as_root install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

append_once_root_file() {
  local path=$1
  local marker=$2
  local mode=${3:-0644}
  local tmp

  if [[ -f "$path" ]] && grep -qF "$marker" "$path"; then
    log "Already present in $path: $marker"
    cat >/dev/null
    return 0
  fi

  tmp=$(mktemp)
  cat >"$tmp"

  if [[ "$CACHY_XPS_DRY_RUN" == "1" ]] || ! is_apply_mode; then
    log "Would append to $path"
    sed 's/^/  | /' "$tmp"
    rm -f "$tmp"
    return 0
  fi

  backup_file "$path"
  as_root mkdir -p "$(dirname "$path")"
  [[ -f "$path" ]] || as_root install -m "$mode" /dev/null "$path"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    cat "$tmp" >>"$path"
  else
    sudo tee -a "$path" <"$tmp" >/dev/null
  fi
  rm -f "$tmp"
}

active_bootloader() {
  if [[ -f /etc/sdboot-manage.conf ]]; then
    echo systemd-boot
  elif [[ -f /etc/default/grub ]]; then
    echo grub
  elif [[ -f /etc/default/limine ]]; then
    echo limine
  else
    echo unknown
  fi
}

regenerate_bootloader() {
  local bootloader=${1:-$(active_bootloader)}
  case "$bootloader" in
    systemd-boot)
      if have_cmd sdboot-manage; then
        as_root sdboot-manage gen
      else
        warn "sdboot-manage not found; regenerate systemd-boot entries manually."
      fi
      ;;
    grub)
      if have_cmd grub-mkconfig; then
        as_root grub-mkconfig -o /boot/grub/grub.cfg
      else
        warn "grub-mkconfig not found; regenerate GRUB manually."
      fi
      ;;
    limine)
      if have_cmd limine-mkinitcpio; then
        as_root limine-mkinitcpio
      elif have_cmd limine-update; then
        as_root limine-update
      else
        warn "No Limine regeneration command found."
      fi
      ;;
    *)
      warn "Unknown bootloader; no regeneration performed."
      ;;
  esac
}

add_kernel_arg() {
  local arg=$1
  local bootloader path
  bootloader=$(active_bootloader)

  case "$bootloader" in
    systemd-boot)
      path=/etc/sdboot-manage.conf
      if grep -qF "$arg" "$path" 2>/dev/null; then
        log "Kernel arg already present in $path: $arg"
        return 0
      fi
      if ! is_apply_mode; then
        log "Would add kernel arg to $path: $arg"
        return 0
      fi
      backup_file "$path"
      as_root bash -c '
        set -e
        path=$1
        arg=$2
        if grep -q "^LINUX_OPTIONS=" "$path"; then
          sed -i -E "s|^(LINUX_OPTIONS=[\"'"'"']?)([^\"'"'"']*)([\"'"'"']?)$|\1\2 '"$arg"'\3|" "$path"
        else
          printf "\nLINUX_OPTIONS=\"%s\"\n" "$arg" >>"$path"
        fi
      ' _ "$path" "$arg"
      regenerate_bootloader "$bootloader"
      ;;
    grub)
      path=/etc/default/grub
      if grep -qF "$arg" "$path" 2>/dev/null; then
        log "Kernel arg already present in $path: $arg"
        return 0
      fi
      if ! is_apply_mode; then
        log "Would add kernel arg to $path: $arg"
        return 0
      fi
      backup_file "$path"
      as_root bash -c '
        set -e
        path=$1
        arg=$2
        if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$path"; then
          sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 '"$arg"'\"|" "$path"
        else
          printf "\nGRUB_CMDLINE_LINUX_DEFAULT=\"%s\"\n" "$arg" >>"$path"
        fi
      ' _ "$path" "$arg"
      regenerate_bootloader "$bootloader"
      ;;
    limine)
      path=/etc/default/limine
      if grep -qF "$arg" "$path" 2>/dev/null; then
        log "Kernel arg already present in $path: $arg"
        return 0
      fi
      if ! is_apply_mode; then
        log "Would add kernel arg to $path: $arg"
        return 0
      fi
      append_once_root_file "$path" "$arg" 0644 <<EOF

# CachyOS XPS fixes
KERNEL_CMDLINE[default]+=" $arg"
EOF
      regenerate_bootloader "$bootloader"
      ;;
    *)
      warn "Could not detect bootloader; skipping kernel arg: $arg"
      ;;
  esac
}

reload_systemd() {
  if is_apply_mode; then
    as_root systemctl daemon-reload
  else
    log "Would reload systemd"
  fi
}

reload_udev() {
  if is_apply_mode; then
    as_root udevadm control --reload-rules
  else
    log "Would reload udev rules"
  fi
}
