#!/usr/bin/env python3
"""Generate the two bundled grid samples without external packages or network access.
Exports: PNG resources in App/Preview/Resources. Dependencies: Python standard library.
"""

from pathlib import Path
import struct
import zlib


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def grid(cell: int) -> bytes:
    width, height = 320, 200
    colors = [(24, 57, 69), (61, 133, 145), (232, 185, 113), (242, 226, 200)]
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            color = colors[(x // cell + y // cell) % len(colors)]
            rows.extend((249, 246, 239) if x % cell < 2 or y % cell < 2 else color)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(
        b"IDAT", zlib.compress(rows, 9)
    ) + chunk(b"IEND", b"")


resources = Path(__file__).resolve().parents[1] / "App" / "Preview" / "Resources"
resources.mkdir(exist_ok=True)
for name, cell in [("coarse", 40), ("fine", 16)]:
    (resources / f"demo-{name}-grid.png").write_bytes(grid(cell))
