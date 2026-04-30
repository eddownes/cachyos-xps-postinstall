# CachyOS XPS Post-Install Fixes

This is a CachyOS-first post-install toolkit for Dell XPS Panther Lake systems.
It ports the useful Omarchy hardware enablement work without running Omarchy's
full installer or replacing CachyOS system ownership.

## Usage

Audit only:

```bash
cd ~/cacheOS-xps-fixes/cachyos-xps-postinstall
./run.sh audit
```

Full post-install pass on CachyOS:

```bash
./install.sh --yes
```

Apply without the initial `pacman -Syu`:

```bash
./run.sh apply --yes
```

Preview writes and commands:

```bash
./run.sh install --dry-run
```

## Modules

- `00-preflight`: CachyOS, Dell XPS, Panther Lake, bootloader, kernel, Wi-Fi, touchpad, and camera detection.
- `10-baseline-packages`: firmware, audio, PipeWire, DKMS, GStreamer, fwupd, Bluetooth, and matching kernel headers.
- `20-bootloader-fred`: adds `fred=on` for Panther Lake through the detected bootloader.
- `30-intel-power-media`: Intel media packages, `thermald`, `power-profiles-daemon`, optional `intel-lpmd`.
- `40-wifi7-eht`: disables Intel BE200/BE211 Wi-Fi 7 EHT on Dell XPS Panther Lake.
- `50-haptic-touchpad`: Synaptics XPS haptic touchpad daemon, service, udev rule, and reset helper.
- `60-mic-mute-led`: Dell XPS mic mute helper that syncs PipeWire mute with ALSA capture state.
- `70-ipu7-camera`: builds Omarchy IPU7 camera packages when requested, then installs runtime camera glue.
- `80-firmware`: lists LVFS/fwupd updates; only applies firmware with `--firmware-update`.

## Camera Build

`install` mode automatically enables camera build when IPU7/OV08X40 hardware is
detected. For `apply` mode, pass:

```bash
./run.sh apply --yes --build-camera
```

The camera build must run as a normal user, not root. The script uses `sudo` only
for package installation and system file writes.

## Safety

- The toolkit refuses `apply` and `install` on non-CachyOS systems.
- Existing files are backed up under `/var/backups/cachyos-xps-fixes`.
- Firmware updates are listed by default, not applied.
- Bootloader changes go through systemd-boot, GRUB, or Limine regeneration paths.
