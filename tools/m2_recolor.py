#!/usr/bin/env python3
"""
Recolor a WotLK (3.3.5, M2 version 264) model: particle colors and the model color tracks.

Colors whose hue is inside the source range are moved to the target hue (saturation and brightness
are kept); white / grey and colors outside the range stay as they are. Textures are not touched:
a texture that is itself colored (T_VFX_PSY_PURPLE.BLP...) needs a recolored BLP copy.

Usage:
  python m2_recolor.py <in.M2> <out.M2> [--target 0] [--from 180 --to 342] [--spread 0.15]

  --target   target hue in degrees: 0 red, 30 orange, 60 yellow, 120 green, 200 light blue, 240 blue, 280 purple
  --from/--to  source hue range in degrees (default 180..342: blue, purple, pink)
  --spread   how much of the original hue variation is kept (0 - all one hue, 1 - keep it all)

The .skin files do not change: copy <in>00.skin to <out>00.skin (the client finds the skin by the file name).
Example (purple portal -> red):
  python m2_recolor.py InstanceNewPortal_Purple.M2 InstanceNewPortal_Red.M2 --target 0
  copy InstanceNewPortal_Purple00.skin InstanceNewPortal_Red00.skin
"""
import argparse
import colorsys
import struct
import sys

PARTICLE_SIZE = 476          # M2Particle (WotLK)
PARTICLE_COLOR_VALUES = 268  # colorTrack (M2PartTrack): timestamps at +260, values at +268
COLOR_SIZE = 40              # M2Color: color M2Track<C3Vector> + alpha M2Track
OFS_COLORS = 0x48
OFS_PARTICLES = 0x128


def make_shift(target, hue_from, hue_to, spread):
    center = (hue_from + hue_to) / 2.0

    def in_range(h):
        if hue_from <= hue_to:
            return hue_from <= h <= hue_to
        return h >= hue_from or h <= hue_to

    def shift(r, g, b, scale):
        h, s, v = colorsys.rgb_to_hsv(r / scale, g / scale, b / scale)
        if s < 0.12 or not in_range(h * 360.0):
            return r, g, b
        h = ((target + (h * 360.0 - center) * spread) % 360.0) / 360.0
        nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
        return nr * scale, ng * scale, nb * scale

    return shift


def recolor(data, shift):
    changed = 0
    count, offset = struct.unpack_from('<II', data, OFS_PARTICLES)
    for i in range(count):
        n, o = struct.unpack_from('<II', data, offset + i * PARTICLE_SIZE + PARTICLE_COLOR_VALUES)
        for k in range(n):
            r, g, b = struct.unpack_from('<fff', data, o + k * 12)
            nr, ng, nb = shift(r, g, b, 255.0)
            struct.pack_into('<fff', data, o + k * 12, nr, ng, nb)
            if (nr, ng, nb) != (r, g, b):
                changed += 1
                print('particle %d: (%d, %d, %d) -> (%d, %d, %d)' % (i, r, g, b, nr, ng, nb))

    count, offset = struct.unpack_from('<II', data, OFS_COLORS)
    for i in range(count):
        anims, values = struct.unpack_from('<II', data, offset + i * COLOR_SIZE + 12)
        for a in range(anims):
            n, o = struct.unpack_from('<II', data, values + a * 8)
            for k in range(n):
                r, g, b = struct.unpack_from('<fff', data, o + k * 12)
                nr, ng, nb = shift(r, g, b, 1.0)
                struct.pack_into('<fff', data, o + k * 12, nr, ng, nb)
                if (nr, ng, nb) != (r, g, b):
                    changed += 1
                    print('color %d: (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)' % (i, r, g, b, nr, ng, nb))
    return changed


def main():
    parser = argparse.ArgumentParser(description='Recolor a 3.3.5 M2 (particles and color tracks).')
    parser.add_argument('input')
    parser.add_argument('output')
    parser.add_argument('--target', type=float, default=0.0)
    parser.add_argument('--from', dest='hue_from', type=float, default=180.0)
    parser.add_argument('--to', dest='hue_to', type=float, default=342.0)
    parser.add_argument('--spread', type=float, default=0.15)
    args = parser.parse_args()

    data = bytearray(open(args.input, 'rb').read())
    if data[:4] != b'MD20' or struct.unpack_from('<I', data, 4)[0] != 264:
        sys.exit('not a WotLK M2 (MD20, version 264)')

    changed = recolor(data, make_shift(args.target, args.hue_from, args.hue_to, args.spread))
    open(args.output, 'wb').write(data)
    print('%s: %d colors changed' % (args.output, changed))

    count, offset = struct.unpack_from('<II', data, 0x50)
    for i in range(count):
        _, _, length, name = struct.unpack_from('<IIII', data, offset + i * 16)
        if length:
            print('texture %d: %s' % (i, data[name:name + length - 1].decode('latin-1')))


if __name__ == '__main__':
    main()
