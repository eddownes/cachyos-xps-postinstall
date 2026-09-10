# CachyOS XPS Post-Install Fixes

This is a CachyOS-first post-install toolkit for Dell XPS Panther Lake systems.
It ports the useful Omarchy hardware enablement work without running Omarchy's
full installer or replacing CachyOS system ownership.

> This is [eddownes](https://github.com/eddownes)'s fork of
> [spencerbull/cachyos-xps-postinstall](https://github.com/spencerbull/cachyos-xps-postinstall),
> carrying additional Panther Lake IPU7 camera fixes (see
> [Panther Lake IPU7 fixes](#panther-lake-ipu7-fixes-module-load-order--psys-permissions)
> below) not yet in upstream.

## Fresh install

```bash
git clone https://github.com/eddownes/cachyos-xps-postinstall.git
cd cachyos-xps-postinstall
./install.sh --yes --build-camera
```

`--build-camera` is required to get a working IPU7 camera (see
[Camera Build](#camera-build) below); everything else in `install.sh --yes`
applies without extra flags.

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

### Panther Lake IPU7 fixes (module load order + psys permissions)

On XPS 16 (Panther Lake) systems the camera can build and install cleanly but
still not work, in two ways that are fixed by this module:

1. **Black/frozen frames, `intel-ipu7 0000:00:05.0: no subdev found in graph`
   in `dmesg`.** `intel_ipu7` (the PCI driver) auto-loads via ordinary PCI
   hotplug early in boot, before `ov08x40` (loaded later by
   `camera-init.service`, after `intel_cvs` hands over ACPI camera ownership)
   registers its async v4l2 subdev. `intel_ipu7`'s one-shot sensor scan
   completes with zero sensors matched and never retries. Fixed by
   blacklisting `intel_ipu7` (`assets/camera-deps.conf`) and having
   `camera-init.service` modprobe it explicitly, after `ov08x40`:
   `intel_cvs → ov08x40 → intel_ipu7 → v4l2loopback`.

2. **Sensor registers fine, but frames from `v4l2-relayd@ipu7` are solid
   black.** `journalctl -u v4l2-relayd@ipu7.service` shows
   `PSysDevice: Failed to open psys device Operation not permitted`. The
   `v4l2-relayd@.service` unit's cgroup device allowlist has
   `DeviceAllow=char-psys`, but the real udev subsystem for
   `/dev/ipu7-psys0` on IPU7 is `intel-ipu7-psys`, not `psys` — so the
   kernel's device-cgroup filter silently rejects the `open()` even though
   the device node itself is world-writable. Fixed by adding
   `DeviceAllow=char-intel-ipu7-psys` to the `v4l2-relayd@ipu7.service.d`
   override this module installs.

**If frames still look black/frozen right after applying this fix**, don't
trust a quick single-frame test (`v4l2-ctl --stream-count=1`) —
`v4l2-relayd` lazily starts the real camera pipeline only once a client
holds the loopback device open for a sustained period, and silently serves
an internal placeholder image (visible as `dataurisrc`/`imagefreeze` threads
under `ps -T <pid>`) until then. Test with a real app (Cheese, a browser) or
a longer capture (`v4l2-ctl --stream-count=60 ...`) before concluding the
pipeline is broken.

## Safety

- The toolkit refuses `apply` and `install` on non-CachyOS systems.
- Existing files are backed up under `/var/backups/cachyos-xps-fixes`.
- Firmware updates are listed by default, not applied.
- Bootloader changes go through systemd-boot, GRUB, or Limine regeneration paths.
