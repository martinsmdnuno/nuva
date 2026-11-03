#!/usr/bin/env python3
"""Packs PNGs into a Windows .ico (PNG-compressed entries, Windows Vista and later).
Usage: make-ico.py out.ico 16.png 32.png ... (each square, 256 at most)."""
import struct, sys

def size(png):
    return struct.unpack(">II", png[16:24])

out, files = sys.argv[1], sys.argv[2:]
images = [open(f, "rb").read() for f in files]
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, data = b"", b""
for png in images:
    w, h = size(png)
    entries += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(png), offset + len(data))
    data += png
open(out, "wb").write(header + entries + data)
