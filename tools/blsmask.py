"""Builds the UI mask pixel shaders (.bls) for the 3.3.5 client.

BLS (GXSH) layout, taken from Shaders\\Pixel\\ps_3_0\\UI.bls and Desaturate.bls:
  0x00 'GXSH'  0x04 0x00010003  0x08 1  0x0C 0xA00  0x10 0x200  0x14 1
  0x18 bytecode size  0x1C D3D9 bytecode (ps_2_0, the client uses ps_2_0 code for every profile)

Shaders (all ps_2_0; the mask UV is the texture UV mapped by c1/c2: uv * c1 + c2, c1.zw = c2.zw = 0).
The D3D9 validator rejects the shader if a register component is read before it is written, and
ps_2_0 has no arbitrary swizzles (only .xyzw and the replicates .xxxx/.yyyy/.zzzz/.wwww).:
  UIMask            = UI.bls with the mask alpha
  UIMaskDesaturate  = Desaturate.bls with the mask alpha
Inputs: v0 vertex color, t0 texture UV, s0 texture, s1 mask, c1 mask UV scale, c2 mask UV offset.

Usage: python tools/blsmask.py Shaders/Pixel [ps_2_0 UI.bls to self-check the header]
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
DCL_MASKED = [
    0x0200001F, 0x80000000, 0x900F0000,	# dcl v0
    0x0200001F, 0x80000000, 0xB00F0000,	# dcl t0 (all: mad reads t0.xyzw, zw are 0)
    0x0200001F, 0x90000000, 0xA00F0800,	# dcl_2d s0
]
DCL_MASK = [
    0x0200001F, 0x90000000, 0xA00F0801,	# dcl_2d s1
]
SAMPLE_MASK = [
    0x03000005, 0x800F0001, 0xB0E40000, 0xA0E40001,	# mul r1, t0, c1 (all of r1: texld reads it whole)
    0x03000002, 0x800F0001, 0x80E40001, 0xA0E40002,	# add r1, r1, c2 (one constant per instruction)
    0x03000042, 0x800F0000, 0xB0E40000, 0xA0E40800,			# texld r0, t0, s0
    0x03000042, 0x800F0001, 0x80E40001, 0xA0E40801,			# texld r1, r1, s1
]

UI = [0xFFFF0200] + DCL + [
    0x03000042, 0x800F0000, 0xB0E40000, 0xA0E40800,	# texld r0, t0, s0
    0x03000005, 0x800F0000, 0x80E40000, 0x90E40000,	# mul r0, r0, v0
    0x02000001, 0x800F0800, 0x80E40000,			# mov oC0, r0
    0x0000FFFF,
]

UI_MASK = [0xFFFF0200] + DCL_MASKED + DCL_MASK + SAMPLE_MASK + [
    0x03000005, 0x800F0000, 0x80E40000, 0x90E40000,	# mul r0, r0, v0
    0x03000005, 0x80080000, 0x80FF0000, 0x80FF0001,	# mul r0.w, r0.w, r1.w
    0x02000001, 0x800F0800, 0x80E40000,			# mov oC0, r0
    0x0000FFFF,
]

UI_MASK_DESATURATE = [0xFFFF0200,
    0x05000051, 0xA00F0000, 0x3E991687, 0x3F1645A2, 0x3DE978D5, 0x00000000,	# def c0, 0.299, 0.587, 0.114, 0
] + DCL_MASKED + DCL_MASK + SAMPLE_MASK + [
    0x03000008, 0x80010002, 0x80E40000, 0xA0E40000,	# dp3 r2.x, r0, c0
    0x03000005, 0x80080002, 0x80FF0000, 0x90FF0000,	# mul r2.w, r0.w, v0.w
    0x03000005, 0x80080002, 0x80FF0002, 0x80FF0001,	# mul r2.w, r2.w, r1.w
    0x02000001, 0x80070002, 0x80000002,			# mov r2.xyz, r2.x
    0x02000001, 0x800F0800, 0x80E40002,			# mov oC0, r2
    0x0000FFFF,
]

# Debug shaders (TextureMaskDebugFlags 8 / 16):
#   UIMaskDebugC = the constants as a color: (c1.x / 8, c1.y / 8, -c2.x, 1) -> white for an 8x8 atlas icon
#                  and a full mask; black = the constants do not reach the shader
#   UIMaskDebugT = the stage 1 texture at t0, opaque: the mask image (wrong place) = s1 is bound
UI_MASK_DEBUG_C = [0xFFFF0200,
    0x05000051, 0xA00F0003, 0x3E000000, 0x3E000000, 0x00000000, 0x3F800000,	# def c3, 0.125, 0.125, 0, 1
    0x02000001, 0x800F0001, 0xA0E40001,			# mov r1, c1
    0x03000005, 0x800F0000, 0x80E40001, 0xA0E40003,	# mul r0, r1, c3
    0x02000001, 0x80040000, 0xA1000002,			# mov r0.z, -c2.x
    0x02000001, 0x80080000, 0xA0FF0003,			# mov r0.w, c3.w
    0x02000001, 0x800F0800, 0x80E40000,			# mov oC0, r0
    0x0000FFFF,
]

UI_MASK_DEBUG_T = [0xFFFF0200,
    0x05000051, 0xA00F0003, 0x00000000, 0x00000000, 0x00000000, 0x3F800000,	# def c3, 0, 0, 0, 1
    0x0200001F, 0x80000000, 0xB0030000,			# dcl t0.xy
    0x0200001F, 0x90000000, 0xA00F0801,			# dcl_2d s1
    0x03000042, 0x800F0000, 0xB0E40000, 0xA0E40801,	# texld r0, t0, s1
    0x02000001, 0x80080000, 0xA0FF0003,			# mov r0.w, c3.w
    0x02000001, 0x800F0800, 0x80E40000,			# mov oC0, r0
    0x0000FFFF,
]

# ---------------- ps_3_0 ----------------
# The client draws the UI with a vs_3_0 vertex shader on ps_3_0 hardware (gx.log vertexShaderTarget),
# D3D9 does not draw a vs_3_0 + ps_2_0 pair: Shaders\\Pixel\\ps_3_0 needs ps_3_0 code.
# Inputs are declared by semantic: v0 = COLOR0, v1 = TEXCOORD0 (the UI vertex shader outputs).
DCL3 = [
    0x0200001F, 0x8000000A, 0x900F0000,	# dcl_color0 v0
    0x0200001F, 0x80000005, 0x90030001,	# dcl_texcoord0 v1.xy
    0x0200001F, 0x90000000, 0xA00F0800,	# dcl_2d s0
]
DCL3_MASK = [
    0x0200001F, 0x90000000, 0xA00F0801,	# dcl_2d s1
]
SAMPLE3_MASK = [
    0x04000004, 0x800F0001, 0x90440001, 0xA0E40001, 0xA0E40002,	# mad r1, v1.xyxy, c1, c2 (c1.zw = c2.zw = 0)
    0x03000042, 0x800F0000, 0x90440001, 0xA0E40800,			# texld r0, v1.xyxy, s0
    0x03000042, 0x800F0001, 0x80E40001, 0xA0E40801,			# texld r1, r1, s1
]

UI_MASK_3 = [0xFFFF0300] + DCL3 + DCL3_MASK + SAMPLE3_MASK + [
    0x03000005, 0x800F0000, 0x80E40000, 0x90E40000,	# mul r0, r0, v0
    0x03000005, 0x80080000, 0x80FF0000, 0x80FF0001,	# mul r0.w, r0.w, r1.w
    0x02000001, 0x800F0800, 0x80E40000,			# mov oC0, r0
    0x0000FFFF,
]

UI_MASK_DESATURATE_3 = [0xFFFF0300,
    0x05000051, 0xA00F0000, 0x3E991687, 0x3F1645A2, 0x3DE978D5, 0x00000000,	# def c0, 0.299, 0.587, 0.114, 0
] + DCL3 + DCL3_MASK + SAMPLE3_MASK + [
    0x03000008, 0x80010002, 0x80E40000, 0xA0E40000,	# dp3 r2.x, r0, c0
    0x03000005, 0x80080002, 0x80FF0000, 0x90FF0000,	# mul r2.w, r0.w, v0.w
    0x03000005, 0x80080002, 0x80FF0002, 0x80FF0001,	# mul r2.w, r2.w, r1.w
    0x02000001, 0x80070002, 0x80000002,			# mov r2.xyz, r2.x
    0x02000001, 0x800F0800, 0x80E40002,			# mov oC0, r2
    0x0000FFFF,
]

UI_MASK_DEBUG_C_3 = [0xFFFF0300] + UI_MASK_DEBUG_C[1:]

UI_MASK_DEBUG_T_3 = [0xFFFF0300,
    0x05000051, 0xA00F0003, 0x00000000, 0x00000000, 0x00000000, 0x3F800000,	# def c3, 0, 0, 0, 1
    0x0200001F, 0x80000005, 0x90030001,			# dcl_texcoord0 v1.xy
    0x0200001F, 0x90000000, 0xA00F0801,			# dcl_2d s1
    0x03000042, 0x800F0000, 0x90440001, 0xA0E40801,	# texld r0, v1.xyxy, s1
    0x02000001, 0x80080000, 0xA0FF0003,			# mov r0.w, c3.w
    0x02000001, 0x800F0800, 0x80E40000,			# mov oC0, r0
    0x0000FFFF,
]

SHADERS = {
    "ps_2_0": (("UIMask", UI_MASK), ("UIMaskDesaturate", UI_MASK_DESATURATE),
               ("UIMaskDebugC", UI_MASK_DEBUG_C), ("UIMaskDebugT", UI_MASK_DEBUG_T)),
    "ps_3_0": (("UIMask", UI_MASK_3), ("UIMaskDesaturate", UI_MASK_DESATURATE_3),
               ("UIMaskDebugC", UI_MASK_DEBUG_C_3), ("UIMaskDebugT", UI_MASK_DEBUG_T_3)),
}

if __name__ == "__main__":
    # usage: blsmask.py <Shaders\\Pixel dir> [ps_2_0 UI.bls to self-check the header]
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    if len(sys.argv) > 2:
        with open(sys.argv[2], "rb") as f:
            assert f.read() == bls(UI), "header/UI mismatch"
        print("UI.bls rebuilt byte for byte")
    for profile, shaders in SHADERS.items():
        out = os.path.join(root, profile)
        os.makedirs(out, exist_ok=True)
        for name, tokens in shaders:
            with open(os.path.join(out, name + ".bls"), "wb") as f:
                f.write(bls(tokens))
            print(profile, name + ".bls", len(bls(tokens)))
