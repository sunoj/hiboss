# HiBoss USB status lamp

A Waveshare RP2040-Zero with an RGB LED (red on GP29, green on GP28, blue on GP27, active
high) running MicroPython. HiBoss Island drives it over USB serial while the app runs:

| Lamp | Meaning |
|---|---|
| Blue, slow blink (1 s) | A decision is waiting for the boss |
| Red, fast blink (0.4 s) | A waiting decision expires within 5 minutes (wins over blue) |
| One green flash (0.8 s) | A new agent message arrived on the live feed |
| Off | Nothing is waiting, the app quit, or no command arrived for 90 seconds |

Messages and decisions that quiet hours hold back from alerting do not light the lamp,
matching the Island's presentation and notification rules. The app finds the lamp by its USB product string
`HiBoss Lamp`, which `boot.py` sets, so other serial devices are never written to.

## Install

1. Flash MicroPython for `WAVESHARE_RP2040_ZERO` (micropython.org/download): hold BOOT
   while plugging in, then copy the `.uf2` to the `RPI-RP2` volume.
2. Copy the lamp program and reset the board:

   ```bash
   python3 -I macos/lamp-firmware/install.py /dev/cu.usbmodemXXXX
   ```

   `ioreg -p IOUSB -l -w0 | grep '"USB Product Name" = "HiBoss Lamp"'` confirms the new identity.

## Protocol

One command per line at any baud rate; each line gets a reply of `ok`, `err` or the status.

- `show <r> <g> <b> <steady|blink|pulse> [period_ms]`: channels 0–100
- `flash <r> <g> <b> [ms]`: one overlay, then back to the shown state
- `off`, `status`

Any line refreshes the 90-second staleness timer. Ctrl-C on the serial console stops
the program and opens the MicroPython REPL; `import machine; machine.bootloader()` there
mounts `RPI-RP2` for a firmware update without the BOOT button. A 1200-baud touch does not
work once `boot.py` has set the lamp identity. Reflashing MicroPython keeps the installed
`boot.py` and `main.py`.
