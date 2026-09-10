# IPU7/OV08X40 camera on Pop!_OS Cosmic 24.04 (experimental, unverified)

**Status: not yet verified on real hardware.** This is a port of the two
IPU7 camera root-cause fixes worked out and confirmed working on CachyOS (see
[`../fixes/70-ipu7-camera`](../fixes/70-ipu7-camera) and the main
[README](../README.md#panther-lake-ipu7-fixes-module-load-order--psys-permissions))
to Ubuntu/apt for Pop!_OS Cosmic 24.04 on Panther Lake laptops. Nobody has run
it end-to-end on a real Pop!_OS Panther Lake machine yet. If you try it,
please report back what worked and what package names needed fixing.

## Why this might work, and where it's shaky

The two actual bugs are pure kernel-module and systemd configuration, not
Arch-specific, so they should carry over unchanged:

1. `intel_ipu7` auto-loads via PCI hotplug before `ov08x40` registers its
   sensor, so it scans for sensors once and finds none. Fixed by blacklisting
   `intel_ipu7` and having `camera-init.service` modprobe it explicitly,
   after `ov08x40`: `intel_cvs → ov08x40 → intel_ipu7 → v4l2loopback`.
2. `v4l2-relayd`'s cgroup device allowlist has `DeviceAllow=char-psys`, but
   `/dev/ipu7-psys0`'s real udev subsystem is `intel-ipu7-psys`, so the
   kernel silently rejects the `open()` with `EPERM` even with correct file
   permissions. Fixed by adding `DeviceAllow=char-intel-ipu7-psys`.

What's genuinely unverified is the **package availability**. Unlike
CachyOS/Arch (where a single AUR-adjacent `omarchy-pkgs` PKGBUILD builds the
whole IPU7 stack from source), Ubuntu splits it across several debs in
Intel's own `ppa:oem-solutions-group/intel-ipu7` PPA, and Panther Lake support
in that PPA is very recent (as of this writing, Ubuntu's own
[MIPI camera wiki page](https://wiki.ubuntu.com/IntelMIPICamera) doesn't
mention Panther Lake at all yet). Specifically:

- `intel-ipu7-dkms` exists in Ubuntu's universe archive as a real DKMS
  source package (not locked to a specific kernel ABI), which is why this
  should work on Pop!_OS's own kernel rather than requiring Ubuntu's OEM
  kernel flavor.
- The camera HAL package is `libcamhal-ipu7x` **or** `libcamhal-ipu75xa`
  depending on the exact IPU7 stepping — the script tries both.
- The GStreamer plugin package is named `gstreamer1.0-icamera` on some
  Ubuntu series and `gst-plugins-icamera` on others — the script tries both.
- **`intel_cvs` (the ACPI camera-ownership driver from
  `intel/vision-drivers`) has no confirmed apt package name.** The script
  prints a search command and a pointer to build it from source via DKMS if
  nothing turns up — this was also true on CachyOS until very recently, so
  don't be surprised if you have to do this by hand.

## Usage

```bash
cd popos-cosmic-24.04
./install-ipu7-camera.sh
```

Run as your normal user (it uses `sudo` only where needed), then reboot.

## Verifying it worked

Check `journalctl -u v4l2-relayd@ipu7.service` for
`PSysDevice: Failed to open psys device Operation not permitted` — if you
still see that, `DeviceAllow=` in
`/etc/systemd/system/v4l2-relayd@ipu7.service.d/override.conf` doesn't match
your device's real udev subsystem; check it with:

```bash
udevadm info -q all -n /dev/ipu7-psys0 | grep SUBSYSTEM
```

**Don't trust a quick single-frame test.** `v4l2-relayd` only starts the
real camera pipeline once a client holds the loopback device open for a
sustained period; until then it silently serves an internal placeholder
image, which looks identical to a genuinely broken black/frozen feed. Test
with an actual app (Cheese, a browser) or a longer capture:

```bash
timeout 8 v4l2-ctl -d /dev/video50 --stream-mmap --stream-count=60 --stream-to=/tmp/frame.raw
```

## What this does not cover

Anything outside camera bring-up specifically — `fred=on`, Wi-Fi 7 EHT,
haptic touchpad, mic-mute LED, etc. from the main CachyOS toolkit are
CachyOS/pacman-specific and not ported here.

## Fedora

Not attempted. Fedora's own MIPI camera enablement effort
([`Changes/X86_MIPI_CameraHwEnablement`](https://fedoraproject.org/wiki/Changes/X86_MIPI_CameraHwEnablement))
is IPU6-only as of Fedora 42 and explicitly lists IPU7/Panther Lake as
future work, and there's no COPR equivalent to
[`jwrdegoede/ipu6-softisp`](https://copr.fedorainfracloud.org/coprs/jwrdegoede/ipu6-softisp/)
for IPU7 yet. Porting there means building the whole stack
(`intel/ipu7-drivers`, `intel/vision-drivers`, the camera HAL, `icamerasrc`,
`v4l2-relayd`) from source and packaging it as RPM/COPR yourself.
