#!/usr/bin/env python3
"""DS5 Chord Combo Daemon

Monitors the DualSense PS button (BTN_MODE) via evdev and sends
Gamescope keyboard hotkeys when chord combos are detected.

Gamescope hotkeys:
  - Guide (Steam button): Tab + Shift_L
  - QAM: Tab + Control_L + Shift_L

Chord combos:
  - PS + Cross (A):  QAM (Tab + Control_L + Shift_L)
  - PS + Circle (B): Close app (Alt+F4)
  - PS + Square (X): Keyboard (Tab + Control_L + Shift_L + Alt_L) -- not standard
  - PS + Triangle (Y): Steam overlay (Tab + Shift_L)
  - PS alone (quick tap): Steam overlay (Tab + Shift_L)
"""

import evdev
from evdev import InputDevice, UInput, ecodes, categorize
import select
import sys
import os
import time
import signal
import logging

# Gamescope keyboard hotkeys
GUIDE_KEYS = [ecodes.KEY_TAB, ecodes.KEY_LEFTSHIFT]
QAM_KEYS = [ecodes.KEY_TAB, ecodes.KEY_LEFTCTRL, ecodes.KEY_LEFTSHIFT]

# Button codes
BTN_MODE = ecodes.BTN_MODE      # 316 - PS button
BTN_SOUTH = ecodes.BTN_SOUTH    # 304 - Cross (A)
BTN_EAST = ecodes.BTN_EAST      # 305 - Circle (B)
BTN_NORTH = ecodes.BTN_NORTH    # 307 - Triangle (Y)
BTN_WEST = ecodes.BTN_WEST      # 308 - Square (X)

# Chord timeout (ms) - how long after PS press to wait for chord button
CHORD_TIMEOUT = 0.3
# Tap timeout - if PS is released within this time without chord, send guide
TAP_TIMEOUT = 0.25

# Vendor/Product for DualSense
DUALSENSE_VID = 0x054c
DUALSENSE_PID = 0x0ce6

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [ds5-chord] %(message)s',
    stream=sys.stderr
)
log = logging.getLogger('ds5-chord')

running = True
ui = None


def signal_handler(signum, frame):
    global running
    running = False
    log.info("Received signal %d, shutting down", signum)


def find_dualsense_device():
    """Find the DualSense evdev device that has BTN_MODE capability."""
    devices = [InputDevice(path) for path in evdev.list_devices()]
    for dev in devices:
        if dev.info.vendor == DUALSENSE_VID and dev.info.product == DUALSENSE_PID:
            if ecodes.EV_KEY in dev.capabilities():
                keys = dev.capabilities()[ecodes.EV_KEY]
                if BTN_MODE in keys:
                    log.info("Found DualSense at %s: %s", dev.path, dev.name)
                    return dev
    return None


def send_hotkey(uinput_dev, keys, delay=0.02):
    """Send a keyboard hotkey combo via uinput."""
    # Press all keys
    for key in keys:
        uinput_dev.write(ecodes.EV_KEY, key, 1)
    uinput_dev.syn()
    time.sleep(delay)
    # Release all keys in reverse order
    for key in reversed(keys):
        uinput_dev.write(ecodes.EV_KEY, key, 0)
    uinput_dev.syn()


def main():
    global ui, running

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Create uinput virtual keyboard
    try:
        ui = UInput(
            name="DS5 Chord Combo Daemon",
            events={
                ecodes.EV_KEY: [
                    ecodes.KEY_TAB, ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT,
                    ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL,
                    ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT,
                    ecodes.KEY_F4, ecodes.KEY_ESC,
                ]
            }
        )
        log.info("Created uinput virtual keyboard device")
    except Exception as e:
        log.error("Failed to create uinput device: %s", e)
        sys.exit(1)

    # Find the DualSense device
    dev = find_dualsense_device()
    if dev is None:
        log.error("DualSense device not found. Make sure hid-playstation driver is loaded.")
        sys.exit(1)

    log.info("DS5 Chord Combo Daemon started. Listening for PS button combos...")

    # State tracking
    ps_pressed = False
    ps_press_time = 0
    chord_button_pressed = None
    chord_button_press_time = 0
    waiting_for_chord = False
    chord_action_sent = False

    # Track button states
    button_states = {
        BTN_SOUTH: False,
        BTN_EAST: False,
        BTN_NORTH: False,
        BTN_WEST: False,
    }

    while running:
        r, _, _ = select.select([dev], [], [], 0.1)

        if r:
            for event in dev.read():
                if event.type == ecodes.EV_KEY:
                    if event.code == BTN_MODE:
                        if event.value == 1:  # Pressed
                            ps_pressed = True
                            ps_press_time = time.monotonic()
                            waiting_for_chord = True
                            log.debug("PS button pressed")
                        elif event.value == 0:  # Released
                            ps_released_time = time.monotonic()
                            ps_duration = ps_released_time - ps_press_time
                            ps_pressed = False

                            if chord_button_pressed is not None:
                                log.debug("PS released after chord: %s", chord_button_pressed)
                                chord_button_pressed = None
                                chord_action_sent = False
                            # Don't send Guide on PS tap — Steam handles that
                            # via HIDAPI already. Only handle chord combos.
                            waiting_for_chord = False

                    elif event.code in button_states:
                        button_states[event.code] = (event.value == 1)

                        if event.value == 1 and ps_pressed and chord_button_pressed is None:
                            # Chord combo detected!
                            chord_button_pressed = event.code
                            chord_button_press_time = time.monotonic()

                            btn_name = {
                                BTN_SOUTH: "Cross(A)",
                                BTN_EAST: "Circle(B)",
                                BTN_NORTH: "Triangle(Y)",
                                BTN_WEST: "Square(X)",
                            }.get(event.code, f"btn_{event.code}")

                            chord_action_sent = True
                            if event.code == BTN_SOUTH:
                                log.info("Chord: PS + %s -> QAM", btn_name)
                                send_hotkey(ui, QAM_KEYS)
                            elif event.code == BTN_NORTH:
                                log.info("Chord: PS + %s -> Guide (Steam overlay)", btn_name)
                                send_hotkey(ui, GUIDE_KEYS)
                            elif event.code == BTN_EAST:
                                log.info("Chord: PS + %s -> Close app (Alt+F4)", btn_name)
                                send_hotkey(ui, [ecodes.KEY_LEFTALT, ecodes.KEY_F4])
                            elif event.code == BTN_WEST:
                                log.info("Chord: PS + %s -> QAM (alt)", btn_name)
                                send_hotkey(ui, QAM_KEYS)

        # Check for chord timeout
        if waiting_for_chord and ps_pressed and chord_button_pressed is None:
            if time.monotonic() - ps_press_time > CHORD_TIMEOUT:
                waiting_for_chord = False
                log.debug("Chord timeout - waiting for PS release")

    # Cleanup
    ui.close()
    log.info("DS5 Chord Combo Daemon stopped")


if __name__ == '__main__':
    main()
