# USB identity for the HiBoss status lamp, applied before the first enumeration.
# The Island app finds the lamp by the product string "HiBoss Lamp".
# Any failure keeps MicroPython's default descriptors, so the REPL stays reachable.

import machine

try:
    usb = machine.USBDevice()
    cdc = usb.BUILTIN_CDC
    usb.builtin_driver = cdc
    usb.config(cdc.desc_dev, cdc.desc_cfg,
               desc_strs={1: "HiBoss", 2: "HiBoss Lamp", 3: machine.unique_id().hex()})
    usb.active(True)
except Exception as error:
    print("lamp boot: default USB identity kept:", error)
