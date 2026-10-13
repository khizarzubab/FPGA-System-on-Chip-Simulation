#!/usr/bin/env python3
"""Convert the text PPM picture written by the full-system testbench into a PNG.

Usage:
    python scripts/ppm_to_png.py soc_frame.ppm soc_frame.png

Standard library only (no Pillow needed). Reads an ASCII "P3" PPM, writes an 8-bit RGB PNG.
"""

import struct
import sys
import zlib


def read_ppm(path):
    with open(path, "r", encoding="ascii") as f:
        tokens = f.read().split()
    if not tokens or tokens[0] != "P3":
        raise ValueError("not an ASCII PPM (P3) file")
    width, height, maxval = int(tokens[1]), int(tokens[2]), int(tokens[3])
    values = [int(t) for t in tokens[4:]]
    if len(values) < width * height * 3:
        raise ValueError(f"picture is incomplete: {len(values)} values, expected {width * height * 3}")
    if maxval != 255:
        values = [v * 255 // maxval for v in values]
    return width, height, values


def write_png(path, width, height, values):
    raw = bytearray()
    row_len = width * 3
    for y in range(height):
        raw.append(0)                                   # filter type 0: none
        raw.extend(values[y * row_len:(y + 1) * row_len])

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    if len(sys.argv) != 3:
        print("usage: python scripts/ppm_to_png.py input.ppm output.png", file=sys.stderr)
        return 1
    width, height, values = read_ppm(sys.argv[1])
    write_png(sys.argv[2], width, height, values)
    print(f"wrote {sys.argv[2]} ({width} x {height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
