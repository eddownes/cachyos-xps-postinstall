#!/usr/bin/env python3

"""Haptic feedback daemon for Synaptics touchpads with Manual Trigger."""

import fcntl
import glob
import os
import struct
import sys

VENDOR = "06CB"
REPORT_ID = 0x37
INTENSITY = 40

EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_KEY = 0x01
BTN_LEFT = 272
BTN_RIGHT = 273
BTN_MIDDLE = 274


def hid_iocs_feature(length):
    return 0xC0000000 | (length << 16) | (ord("H") << 8) | 0x06


def find_hidraw():
    for path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = os.path.join(path, "device", "uevent")
        try:
            with open(uevent, encoding="utf-8") as handle:
                content = handle.read().upper()
            if f"0000{VENDOR}" in content:
                return os.path.join("/dev", os.path.basename(path))
        except OSError:
            continue
    return None


def find_touchpad_event():
    for path in sorted(glob.glob("/sys/class/input/event*/device/name")):
        try:
            with open(path, encoding="utf-8") as handle:
                name = handle.read().strip().upper()
            if VENDOR in name and "TOUCHPAD" in name:
                event = path.split("/")[-3]
                return os.path.join("/dev/input", event)
        except OSError:
            continue
    return None


def main():
    hidraw = find_hidraw()
    if not hidraw:
        print("No Synaptics haptic touchpad hidraw device found", file=sys.stderr)
        sys.exit(1)

    event = find_touchpad_event()
    if not event:
        print("No Synaptics haptic touchpad input device found", file=sys.stderr)
        sys.exit(1)

    print(f"Haptic touchpad: hidraw={hidraw} input={event} intensity={INTENSITY}", flush=True)

    haptic_report = struct.pack("BB", REPORT_ID, INTENSITY)
    ioctl_req = hid_iocs_feature(len(haptic_report))

    hidraw_fd = os.open(hidraw, os.O_RDWR)
    event_fd = os.open(event, os.O_RDONLY)

    try:
        while True:
            data = os.read(event_fd, EVENT_SIZE)
            if len(data) < EVENT_SIZE:
                continue
            _, _, ev_type, code, value = struct.unpack(EVENT_FORMAT, data)
            if ev_type == EV_KEY and code in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE) and value == 1:
                try:
                    fcntl.ioctl(hidraw_fd, ioctl_req, haptic_report)
                except OSError:
                    pass
    except KeyboardInterrupt:
        pass
    finally:
        os.close(event_fd)
        os.close(hidraw_fd)


if __name__ == "__main__":
    main()
