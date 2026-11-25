#!/usr/bin/env python3
# Copies boot.py and main.py to a MicroPython lamp over its raw REPL, then resets the board.
# Usage: python3 -I install.py /dev/cu.usbmodemXXXX   (standard library only, macOS/Linux)

import os
import pathlib
import sys
import termios
import time

HERE = pathlib.Path(__file__).resolve().parent


def open_port(path):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    attrs[0] = attrs[1] = attrs[3] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[4] = attrs[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    return fd


def read_until(fd, token, seconds):
    deadline, data = time.time() + seconds, b""
    while time.time() < deadline and token not in data:
        try:
            data += os.read(fd, 4096)
        except BlockingIOError:
            time.sleep(0.02)
    if token not in data:
        sys.exit(f"install: no {token!r} from the board; got {data[-200:]!r}")
    return data


def run_raw(fd, code):
    data = code.encode()
    for start in range(0, len(data), 256):
        os.write(fd, data[start:start + 256])
        time.sleep(0.01)
    os.write(fd, b"\x04")
    reply = read_until(fd, b"\x04>", 10)
    if b"Traceback" in reply:
        sys.exit(f"install: board error: {reply.decode(errors='replace')}")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: install.py <serial-port>")
    fd = open_port(sys.argv[1])
    os.write(fd, b"\r\x03\x03")
    time.sleep(0.2)
    os.write(fd, b"\x01")
    read_until(fd, b"raw REPL; CTRL-B to exit\r\n>", 5)
    for name in ("boot.py", "main.py"):
        source = (HERE / name).read_text()
        run_raw(fd, f"f=open({name!r},'w')\nf.write({source!r})\nf.close()\n")
        print(f"install: wrote {name} ({len(source)} bytes)")
    os.write(fd, b"import machine\nmachine.reset()\n\x04")
    time.sleep(0.3)
    try:
        os.close(fd)
    except OSError:
        pass
    print("install: board reset; it re-enumerates as \"HiBoss Lamp\"")


if __name__ == "__main__":
    main()
