"""Builds the UI mask pixel shaders (.bls) for the 3.3.5 client (MaskTexture patch).

BLS (GXSH) layout, taken from the client's Shaders\\Pixel\\<profile>\\UI.bls and Desaturate.bls:
  0x00 'GXSH'  0x04 0x00010003  0x08 1  0x0C 0xA00  0x10 0x200  0x14 1
  0x18 bytecode size  0x1C D3D9 bytecode

The client draws the UI with a vs_3_0 vertex shader on ps_3_0 hardware (gx.log vertexShaderTarget);
D3D9 does not draw a vs_3_0 + ps_2_0 pair, so the ps_3_0 folder needs ps_3_0 code. Inputs:
  ps_3_0: v0 = COLOR0, v1 = TEXCOORD0      ps_2_0: v0 = color, t0 = texcoord

Shaders UIMask<n> / UIMaskDesaturate<n>, n = 1..3 masks:
  color = tex(s0, uv) * vertex color (Desaturate: luminance, like the client's Desaturate)
  alpha *= mask_k(s_k, uv_k) for k = 1..n, uv_k = uv.x * c[3k-2] + uv.y * c[3k-1] + c[3k] (.xy)
  (an affine map: texcoord rotation, flips, atlases and crops all stay linear)
c0 is the luminance constant of the Desaturate variants.

Rules the D3D9 validator enforces (all broke an earlier version): no register component read before
it is written; ps_2_0 has no arbitrary swizzles (only .xyzw and the replicates); one constant
register per instruction here to stay safe.

Usage: python tools/blsmask.py Shaders/Pixel [ps_2_0 UI.bls [ps_3_0 UI.bls]] (self-checks)
"""
import os
import struct
import sys

HEADER = (0x47585348, 0x00010003, 1, 0xA00, 0x200, 1)
MAX_MASKS = 3

# register types
TEMP, INPUT, CONST, TEXTURE, COLOROUT, SAMPLER = 0, 1, 2, 3, 8, 10
# opcodes
MOV, ADD, MAD, MUL, DP3, TEXLD, DCL, DEF, END = 1, 2, 4, 5, 8, 0x42, 0x1F, 0x51, 0xFFFF
# swizzles
XYZW, XXXX, YYYY, WWWW = 0xE4, 0x00, 0x55, 0xFF
NEG = 1


def reg(rtype, index):
    return 0x80000000 | ((rtype & 7) << 28) | ((rtype >> 3) << 11) | index


def dst(rtype, index, mask=0xF):
    return reg(rtype, index) | (mask << 16)


def src(rtype, index, swizzle=XYZW, modifier=0):
    return reg(rtype, index) | (swizzle << 16) | (modifier << 24)


def ins(opcode, *args):
    return [(len(args) << 24) | opcode, *args]


def fbits(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


def bls(tokens):
    code = struct.pack("<%dI" % len(tokens), *tokens)
    return struct.pack("<7I", *HEADER, len(code)) + code


class Profile:
    def __init__(self, version, color_usage, uv_type, uv_usage):
        self.version = version
        self.color_usage = color_usage
        self.uv_type = uv_type
        self.uv_usage = uv_usage

    def uv(self, swizzle=XYZW):
        return src(self.uv_type, 1 if self.uv_type == INPUT else 0, swizzle)

    def declarations(self, samplers, color_mask=0xF):
        uv_index = 1 if self.uv_type == INPUT else 0
        tokens = ins(DCL, self.color_usage, dst(INPUT, 0, color_mask))
        tokens += ins(DCL, self.uv_usage, dst(self.uv_type, uv_index, 0x3))
        for s in range(samplers):
            tokens += ins(DCL, 0x90000000, dst(SAMPLER, s))	# dcl_2d
        return tokens


PS_2_0 = Profile(0xFFFF0200, 0x80000000, TEXTURE, 0x80000000)
PS_3_0 = Profile(0xFFFF0300, 0x8000000A, INPUT, 0x80000005)	# dcl_color0 / dcl_texcoord0

LUMINANCE = (0.299, 0.587, 0.114, 0.0)


def ui(profile):
    """The client's UI.bls (self-check)."""
    tokens = [profile.version] + profile.declarations(1)
    tokens += ins(TEXLD, dst(TEMP, 0), profile.uv(), src(SAMPLER, 0))
    if profile is PS_3_0:
        tokens += ins(MUL, dst(COLOROUT, 0), src(TEMP, 0), src(INPUT, 0))
    else:
        tokens += ins(MUL, dst(TEMP, 0), src(TEMP, 0), src(INPUT, 0))
        tokens += ins(MOV, dst(COLOROUT, 0), src(TEMP, 0))
    return tokens + [END]


def ui_mask(profile, masks, desaturate):
    tokens = [profile.version]
    if desaturate:
        tokens += ins(DEF, dst(CONST, 0), *map(fbits, LUMINANCE))
    tokens += profile.declarations(1 + masks)
    tokens += ins(TEXLD, dst(TEMP, 0), profile.uv(), src(SAMPLER, 0))
    for k in range(1, masks + 1):
        c = 3 * k - 2
        tokens += ins(MUL, dst(TEMP, 1), profile.uv(XXXX), src(CONST, c))
        tokens += ins(MAD, dst(TEMP, 1), profile.uv(YYYY), src(CONST, c + 1), src(TEMP, 1))
        tokens += ins(ADD, dst(TEMP, 1), src(TEMP, 1), src(CONST, c + 2))
        tokens += ins(TEXLD, dst(TEMP, 1), src(TEMP, 1), src(SAMPLER, k))
        tokens += ins(MUL, dst(TEMP, 0, 0x8), src(TEMP, 0, WWWW), src(TEMP, 1, WWWW))
    if desaturate:
        tokens += ins(DP3, dst(TEMP, 2, 0x1), src(TEMP, 0), src(CONST, 0))
        tokens += ins(MUL, dst(TEMP, 2, 0x8), src(TEMP, 0, WWWW), src(INPUT, 0, WWWW))
        tokens += ins(MOV, dst(TEMP, 2, 0x7), src(TEMP, 2, XXXX))
        tokens += ins(MOV, dst(COLOROUT, 0), src(TEMP, 2))
    else:
        tokens += ins(MUL, dst(TEMP, 0), src(TEMP, 0), src(INPUT, 0))
        tokens += ins(MOV, dst(COLOROUT, 0), src(TEMP, 0))
    return tokens + [END]


PROFILES = {"ps_2_0": PS_2_0, "ps_3_0": PS_3_0}


def shaders(profile):
    for masks in range(1, MAX_MASKS + 1):
        yield "UIMask%d" % masks, ui_mask(profile, masks, False)
        yield "UIMaskDesaturate%d" % masks, ui_mask(profile, masks, True)


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    for path, profile in zip(sys.argv[2:4], (PS_2_0, PS_3_0)):
        with open(path, "rb") as f:
            assert f.read() == bls(ui(profile)), path + ": header/UI mismatch"
        print(path, "rebuilt byte for byte")
    for name, profile in PROFILES.items():
        out = os.path.join(root, name)
        os.makedirs(out, exist_ok=True)
        for old in os.listdir(out):
            if old.startswith("UIMask") and old.endswith(".bls"):
                os.remove(os.path.join(out, old))
        for shader, tokens in shaders(profile):
            with open(os.path.join(out, shader + ".bls"), "wb") as f:
                f.write(bls(tokens))
            print(name, shader + ".bls", len(bls(tokens)))
