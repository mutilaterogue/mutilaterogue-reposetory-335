"""Writes a solid (fully opaque white) BLP2 texture with mipmaps, raw BGRA (compression 3).

Used for Interface\\CharacterFrame\\TempPortraitAlphaMask.blp: the 3.3.5 client cuts SetPortraitTexture
portraits with that alpha (a circle); opaque, the portrait stays square and a MaskTexture shapes it
(retail: UI-HUD-UnitFrame-Player-Portrait-Mask).

Usage: python tools/blpsolid.py <out.blp> [size=128]
"""
import struct
import sys


def blp_solid(size, bgra=(255, 255, 255, 255)):
    mips = []
    s = size
    while s >= 1 and len(mips) < 16:
        mips.append(bytes(bgra) * (s * s))
        s //= 2
    header_size = 4 + 4 + 4 + 4 + 4 + 16 * 4 + 16 * 4 + 256 * 4
    offsets, sizes, pos = [], [], header_size
    for data in mips:
        offsets.append(pos)
        sizes.append(len(data))
        pos += len(data)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    header = b"BLP2" + struct.pack("<I", 1)			# type 1: not JPEG
    header += struct.pack("<BBBB", 3, 8, 8, 1)		# compression 3 (raw BGRA), alpha depth 8, alpha type, has mips
    header += struct.pack("<II", size, size)
    header += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    header += bytes(256 * 4)						# palette (unused)
    assert len(header) == header_size
    return header + b"".join(mips)


if __name__ == "__main__":
    out = sys.argv[1]
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 128
    with open(out, "wb") as f:
        f.write(blp_solid(size))
    print(out, size)
