# Tiny D3D9 shader model 3 assembler: emits the DWORD tokens of a few instructions.
import struct, math
SW = {'x':0,'y':1,'z':2,'w':3}
def swz(s):
    s = (s + s[-1]*4)[:4]
    return SW[s[0]] | SW[s[1]]<<2 | SW[s[2]]<<4 | SW[s[3]]<<6
TYPES = {'r':0,'v':1,'c':2,'s':10,'o':11,'oC':8,'oPos':4}
def regbits(t, n):
    return ((t & 7) << 28) | ((t >> 3) << 11) | n
def dst(reg, mask='xyzw', sat=False):
    t, n = reg
    m = sum(1 << SW[c] for c in mask)
    return 0x80000000 | regbits(TYPES[t], n) | (m << 16) | (0x00100000 if sat else 0)
def src(reg, sw='xyzw', neg=False):
    t, n = reg
    return 0x80000000 | regbits(TYPES[t], n) | (swz(sw) << 16) | (0x01000000 if neg else 0)
def ins(op, *toks):
    return [op | (len(toks) << 24)] + list(toks)
OP = dict(mov=1, add=2, mad=4, mul=5, rcp=6, min=10, max=11, dcl=31, texld=66, defc=81)
def f(x): return struct.unpack('<I', struct.pack('<f', x))[0]
def defc(n, a, b, c, d): return ins(OP['defc'], 0x80000000 | regbits(2, n) | 0x000F0000, f(a), f(b), f(c), f(d))
def dcl_usage(usage, reg, mask='xyzw', index=0):
    return ins(OP['dcl'], 0x80000000 | usage | (index << 16), dst(reg, mask))
def dcl_2d(sampler):
    return ins(OP['dcl'], 0x80000000 | (2 << 27), dst(('s', sampler)))
END = [0x0000FFFF]

def vs_quad():
    t = [0xFFFE0300]
    t += dcl_usage(0, ('v', 0)); t += dcl_usage(5, ('v', 1))
    t += dcl_usage(0, ('o', 0)); t += dcl_usage(5, ('o', 1))
    t += ins(OP['mov'], dst(('o', 0)), src(('v', 0)))
    t += ins(OP['mov'], dst(('o', 1)), src(('v', 1)))
    return t + END

def ps_flat():
    return [0xFFFF0300] + ins(OP['mov'], dst(('oC', 0)), src(('c', 0))) + END

def ps_outline(rings=((1.5, 8), (3.0, 8)), rotate=True):
    # c0.xy: one texel (1/width, 1/height); c1.x: alpha gain, c1.y: strength
    taps = []
    for k, (radius, count) in enumerate(rings):
        for i in range(count):
            a = 2 * math.pi * (i + (0.5 * k if rotate else 0)) / count
            taps.append((radius * math.cos(a), radius * math.sin(a)))
    t = [0xFFFF0300]
    base = 10
    consts = []
    for i in range(0, len(taps), 2):
        a = taps[i]; b = taps[i + 1]
        consts.append((a[0], a[1], b[0], b[1]))
    for i, c in enumerate(consts):
        t += defc(base + i, *c)
    t += defc(9, 0.0001, 1.0, 0, 0)
    t += dcl_usage(5, ('v', 0), 'xy')
    t += dcl_2d(0)
    # r3 = 0 (the sum); r1 = 0 (texld reads all of it, only .xy is set below: an unwritten
    # component makes the shader invalid)
    t += ins(OP['mov'], dst(('r', 3)), src(('c', 9), 'zzzz'))
    t += ins(OP['mov'], dst(('r', 1)), src(('c', 9), 'zzzz'))
    for i in range(len(taps)):
        c = ('c', base + i // 2)
        sw = 'xyxy' if i % 2 == 0 else 'zwzw'
        t += ins(OP['mad'], dst(('r', 1), 'xy'), src(c, sw), src(('c', 0), 'xyxy'), src(('v', 0), 'xyxy'))
        t += ins(OP['texld'], dst(('r', 2)), src(('r', 1)), src(('s', 0)))
        t += ins(OP['add'], dst(('r', 3)), src(('r', 3)), src(('r', 2)))
    # center
    t += ins(OP['texld'], dst(('r', 4)), src(('v', 0), 'xyxy'), src(('s', 0)))
    # rgb = sum.rgb / max(sum.a, eps)
    t += ins(OP['max'], dst(('r', 5), 'x'), src(('r', 3), 'wwww'), src(('c', 9), 'xxxx'))
    t += ins(OP['rcp'], dst(('r', 5), 'x'), src(('r', 5), 'xxxx'))
    t += ins(OP['mul'], dst(('r', 0), 'xyz'), src(('r', 3)), src(('r', 5), 'xxxx'))
    # a = saturate(sum.a * gain) * (1 - center.a) * strength
    t += ins(OP['mul'], dst(('r', 6), 'x', sat=True), src(('r', 3), 'wwww'), src(('c', 1), 'xxxx'))
    t += ins(OP['add'], dst(('r', 7), 'x'), src(('c', 9), 'yyyy'), src(('r', 4), 'wwww', neg=True))
    t += ins(OP['mul'], dst(('r', 6), 'x'), src(('r', 6), 'xxxx'), src(('r', 7), 'xxxx'))
    t += ins(OP['mul'], dst(('r', 0), 'w'), src(('r', 6), 'xxxx'), src(('c', 1), 'yyyy'))
    t += ins(OP['mov'], dst(('oC', 0)), src(('r', 0)))
    return t + END

def carray(name, toks):
    body = ', '.join('0x%08X' % x for x in toks)
    lines = []
    parts = body.split(', ')
    for i in range(0, len(parts), 8):
        lines.append('        ' + ', '.join(parts[i:i+8]) + ',')
    return '    const DWORD %s[] = {\n%s\n    };\n' % (name, '\n'.join(lines))

if __name__ == '__main__':
    print(carray('SHADER_FLAT_PS', ps_flat()))
    print(carray('SHADER_QUAD_VS', vs_quad()))
    print(carray('SHADER_OUTLINE_PS', ps_outline()))
    print(carray('SHADER_OUTLINE_LOW_PS', ps_outline(rings=((2.0, 8),), rotate=False)))
