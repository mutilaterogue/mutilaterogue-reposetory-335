"""Builds the UI mask pixel shaders (.bls) for the 3.3.5 client.

BLS (GXSH) layout, taken from Shaders\\Pixel\\ps_3_0\\UI.bls and Desaturate.bls:
  0x00 'GXSH'  0x04 0x00010003  0x08 1  0x0C 0xA00  0x10 0x200  0x14 1
  0x18 bytecode size  0x1C D3D9 bytecode (ps_2_0, the client uses ps_2_0 code for every profile)

Shaders (all ps_2_0; the mask UV is the texture UV mapped by c1: uv * c1.xy + c1.zw;
no register component may be read before it is written, the D3D9 validator rejects the shader):
  UIMask            = UI.bls with the mask alpha
  UIMaskDesaturate  = Desaturate.bls with the mask alpha
Inputs: v0 vertex color, t0 texture UV, s0 texture, s1 mask, c1 mask UV transform.

Usage: python tools/blsmask.py <out dir> [UI.bls to self-check the header]
"""
import os
import struct
import sys

HEADER = (0x47585348, 0x00010003, 1, 0xA00, 0x200, 1)


def bls(tokens):
    code = struct.pack("<%dI" % len(tokens), *tokens)
    return struct.pack("<7I", *HEADER, len(code)) + code


DCL = [
    0x0200001F, 0x80000000, 0x900F0000,	# dcl v0
    0x0200001F, 0x80000000, 0xB0030000,	# dcl t0.xy
    0x0200001F, 0x90000000, 0xA00F0800,	# dcl_2d s0
]
DCL_MASK = [
    0x0200001F, 0x90000000, 0xA00F0801,	# dcl_2d s1
]
SAMPLE_MASK = [
    0x04000004, 0x800F0001, 0xB0440000, 0xA0440001, 0xA0EE0001,	# mad r1, t0.xyxy, c1.xyxy, c1.zwzw (all of r1: texld reads it whole)
    0x03000042, 0x800F0000, 0xB0E40000, 0xA0E40800,			# texld r0, t0, s0
    0x03000042, 0x800F0001, 0x80E40001, 0xA0E40801,			# texld r1, r1, s1
]

UI = [0xFFFF0200] + DCL + [
    0x03000042, 0x800F0000, 0xB0E40000, 0xA0E40800,	# texld r0, t0, s0
    0x03000005, 0x800F0000, 0x80E40000, 0x90E40000,	# mul r0, r0, v0
    0x02000001, 0x800F0800, 0x80E40000,			# mov oC0, r0
    0x0000FFFF,
]

UI_MASK = [0xFFFF0200] + DCL + DCL_MASK + SAMPLE_MASK + [
    0x03000005, 0x800F0000, 0x80E40000, 0x90E40000,	# mul r0, r0, v0
    0x03000005, 0x80080000, 0x80FF0000, 0x80FF0001,	# mul r0.w, r0.w, r1.w
    0x02000001, 0x800F0800, 0x80E40000,			# mov oC0, r0
    0x0000FFFF,
]

UI_MASK_DESATURATE = [0xFFFF0200,
    0x05000051, 0xA00F0000, 0x3E991687, 0x3F1645A2, 0x3DE978D5, 0x00000000,	# def c0, 0.299, 0.587, 0.114, 0
] + DCL + DCL_MASK + SAMPLE_MASK + [
    0x03000008, 0x80010002, 0x80E40000, 0xA0E40000,	# dp3 r2.x, r0, c0
    0x03000005, 0x80080002, 0x80FF0000, 0x90FF0000,	# mul r2.w, r0.w, v0.w
    0x03000005, 0x80080002, 0x80FF0002, 0x80FF0001,	# mul r2.w, r2.w, r1.w
    0x02000001, 0x80070002, 0x80000002,			# mov r2.xyz, r2.x
    0x02000001, 0x800F0800, 0x80E40002,			# mov oC0, r2
    0x0000FFFF,
]

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    if len(sys.argv) > 2:
        with open(sys.argv[2], "rb") as f:
            assert f.read() == bls(UI), "header/UI mismatch"
        print("UI.bls rebuilt byte for byte")
    os.makedirs(out, exist_ok=True)
    for name, tokens in (("UIMask", UI_MASK), ("UIMaskDesaturate", UI_MASK_DESATURATE)):
        with open(os.path.join(out, name + ".bls"), "wb") as f:
            f.write(bls(tokens))
        print(name + ".bls", len(bls(tokens)))
