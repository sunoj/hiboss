# HiBoss status lamp: an RGB LED on GP29 (red), GP28 (green) and GP27 (blue), driven over USB serial.
# Lines: "show <r> <g> <b> <steady|blink|pulse> [period_ms]" (channels 0-100), "flash <r> <g> <b>
# [ms]" (one overlay, then back to the shown state), "off", "status"; replies ok/err/status.
# The lamp goes dark when no line arrives for STALE_MS, so a dead host leaves no stale signal.

import math
import select
import sys
import time

import machine

STALE_MS = 90_000
PINS = (29, 28, 27)
channels = [machine.PWM(machine.Pin(pin)) for pin in PINS]
for channel in channels:
    channel.freq(1000)
state = {"rgb": (0, 0, 0), "mode": "steady", "period": 1000, "seen": time.ticks_ms(),
         "flash": None, "until": 0}


def write(rgb, scale=1.0):
    for channel, level in zip(channels, rgb):
        channel.duty_u16(int(65535 * level * scale / 100))


def handle(parts):
    if parts[0] == "status":
        print(state)
        return
    if parts[0] == "off":
        state.update(rgb=(0, 0, 0), mode="steady")
    elif parts[0] == "show" and len(parts) in (5, 6) and parts[4] in ("steady", "blink", "pulse"):
        rgb = tuple(max(0, min(100, int(value))) for value in parts[1:4])
        period = max(100, int(parts[5])) if len(parts) == 6 else 1000
        state.update(rgb=rgb, mode=parts[4], period=period)
    elif parts[0] == "flash" and len(parts) in (4, 5):
        rgb = tuple(max(0, min(100, int(value))) for value in parts[1:4])
        ms = max(50, min(5000, int(parts[4]))) if len(parts) == 5 else 600
        state.update(flash=rgb, until=time.ticks_add(time.ticks_ms(), ms))
    else:
        raise ValueError(parts[0])
    print("ok")


def render(now):
    if time.ticks_diff(now, state["seen"]) > STALE_MS:
        write((0, 0, 0))
        return
    if state["flash"] is not None:
        if time.ticks_diff(state["until"], now) > 0:
            write(state["flash"])
            return
        state["flash"] = None
    mode, period = state["mode"], state["period"]
    if mode == "blink":
        write(state["rgb"], 1.0 if (now // (period // 2)) % 2 == 0 else 0.0)
    elif mode == "pulse":
        write(state["rgb"], 0.5 - 0.5 * math.cos(2 * math.pi * (now % period) / period))
    else:
        write(state["rgb"])


def run():
    poll = select.poll()
    poll.register(sys.stdin, select.POLLIN)
    line = ""
    while True:
        if poll.poll(10):
            char = sys.stdin.read(1)
            if char not in "\r\n":
                line += char
            elif line.strip():
                state["seen"] = time.ticks_ms()
                try:
                    handle(line.split())
                except Exception:
                    print("err")
                line = ""
        render(time.ticks_ms())


try:
    run()
finally:
    write((0, 0, 0))
