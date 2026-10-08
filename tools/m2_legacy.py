#!/usr/bin/env python3
"""Convert a retail (chunked MD21, version 272+) M2 doodad to WotLK 3.3.5 (version 264).

    m2_legacy.py <model.m2 | folder> [out_dir] [client path of the model dir] [--manifest file.manifest.json]
    e.g. m2_legacy.py C:\\wow.export\\item\\objectcomponents\\weapon  (all models, -> weapon_out, Item\\ObjectComponents\\Weapon)

What it does:
  * unwraps MD21 -> MD20, version 264;
  * texture file IDs (TXID) -> file names: textures are copied next to the model
    (name from the .manifest.json, else <model>_<fileid>.blp) and referenced by path;
  * particles -> 3.3.5 layout; drops ribbons / lights / cameras (their retail layout differs);
  * fills the empty texture unit lookup (3.3.5 crashes without it);
  * clamps materials (flags, blend mode 7 -> add) and skin batch shaders to 3.3.5 values;
  * writes <model>00.skin only (one skin profile); sequences must be inline (flag 0x20).
"""
import json
import os
import shutil
import struct
import sys

HEADER_FIELDS = ['name', 'flags', 'gloops', 'seqs', 'seqlookup', 'bones', 'keybone', 'verts', 'nskin',
                 'colors', 'textures', 'tweights', 'ttrans', 'texreplace', 'materials', 'bonelookup',
                 'texlookup', 'texunit', 'transplookup', 'uvlookup', 'bbox', 'bradius', 'cbox', 'cradius',
                 'colIdx', 'colPos', 'colNorm', 'attach', 'attachLookup', 'events', 'lights', 'cameras',
                 'camLookup', 'ribbons', 'particles']


def header_offsets():
    offsets, p = {}, 8
    for n in HEADER_FIELDS:
        offsets[n] = p
        p += 4 if n in ('flags', 'nskin', 'bradius', 'cradius') else 24 if n in ('bbox', 'cbox') else 8
    return offsets


PARTICLE_335 = 476      # M2ParticleOld (3.3.5)
PARTICLE_RETAIL = 492   # Cata+: + multiTextureParam0[2], multiTextureParam1[2]


def convert_particles(md, H):
    """retail emitters -> 3.3.5 layout (returns the new array, or b'' when there are none)."""
    count, off = struct.unpack_from('<II', md, H['particles'])
    out = bytearray()
    for i in range(count):
        p = bytearray(md[off + i * PARTICLE_RETAIL:off + i * PARTICLE_RETAIL + PARTICLE_335])
        flags = struct.unpack_from('<I', p, 4)[0]
        # multi texture: 3 texture ids packed by 5 bits -> the first one
        if flags & 0x10000000:
            struct.pack_into('<H', p, 22, struct.unpack_from('<H', p, 22)[0] & 0x1F)
        # compressed gravity (vector in 4 bytes) is unknown to 3.3.5: plain downward gravity from its z
        if flags & 0x800000:
            n, o = struct.unpack_from('<II', p, 132 + 12)
            for k in range(n):
                cnt, arr = struct.unpack_from('<II', md, o + k * 8)
                for j in range(cnt):
                    x, y, z = struct.unpack_from('<bbh', md, arr + j * 4)
                    struct.pack_into('<f', md, arr + j * 4, -z / 64.0)
        struct.pack_into('<I', p, 4, flags & 0x007FFFFF)
        # blend 0..4
        if p[40] > 4:
            p[40] = 4
        # 44/45: retail multiTextureParamX -> particleType / headOrTail (head, tail, both by the cell tracks)
        head = struct.unpack_from('<I', p, 308 + 8)[0]
        tail = struct.unpack_from('<I', p, 324 + 8)[0]
        p[44] = 0
        p[45] = 2 if head and tail else 1 if tail else 0
        out += p
    return bytes(out)


def read_chunks(data):
    chunks, o = {}, 0
    while o + 8 <= len(data):
        tag = data[o:o + 4]
        size = struct.unpack_from('<I', data, o + 4)[0]
        chunks[tag] = data[o + 8:o + 8 + size]
        o += 8 + size
    return chunks


def convert(src, out_dir, client_dir, manifest=None):
    data = open(src, 'rb').read()
    base = os.path.splitext(os.path.basename(src))[0]
    src_dir = os.path.dirname(os.path.abspath(src))
    chunks = read_chunks(data) if data[:4] == b'MD21' else {b'MD21': data}
    md = bytearray(chunks[b'MD21'])
    assert md[:4] == b'MD20', 'no MD20'
    H = header_offsets()

    struct.pack_into('<I', md, 4, 264)
    flags = struct.unpack_from('<I', md, H['flags'])[0]
    struct.pack_into('<I', md, H['flags'], flags & 0x7)
    particles = convert_particles(md, H)
    for n in ('lights', 'cameras', 'camLookup', 'ribbons', 'particles'):
        struct.pack_into('<II', md, H[n], 0, 0)
    struct.pack_into('<I', md, H['nskin'], 1)

    # sequences: 3.3.5 would look for .anim files without 0x20
    count, off = struct.unpack_from('<II', md, H['seqs'])
    for i in range(count):
        seq_flags = struct.unpack_from('<I', md, off + i * 64 + 12)[0]
        if not seq_flags & 0x20:
            print('warning: sequence %d is not inline (needs .anim)' % i)

    # materials: flags 0..0x1F, blend 0..6
    count, off = struct.unpack_from('<II', md, H['materials'])
    for i in range(count):
        mflags, blend = struct.unpack_from('<HH', md, off + i * 4)
        struct.pack_into('<HH', md, off + i * 4, mflags & 0x1F, 4 if blend > 6 else blend)

    # textures: file ids -> names
    names = {}
    if manifest:
        for t in json.load(open(manifest))['textures']:
            names[t['fileDataID']] = t['file']
    txid = chunks.get(b'TXID', b'')
    ids = struct.unpack_from('<%dI' % (len(txid) // 4), txid) if txid else ()
    count, off = struct.unpack_from('<II', md, H['textures'])
    os.makedirs(out_dir, exist_ok=True)
    tail = bytearray()
    for i in range(count):
        fid = ids[i] if i < len(ids) else 0
        if not fid:
            continue
        file = names.get(fid, '%s_%d.blp' % (base, fid)).replace('\\', '/')
        src_blp = os.path.normpath(os.path.join(src_dir, file))
        blp = os.path.basename(file)
        if os.path.exists(src_blp):
            shutil.copyfile(src_blp, os.path.join(out_dir, blp))
        else:
            print('warning: missing texture', file)
        path = (client_dir.rstrip('\\') + '\\' + blp).encode() + b'\0'
        struct.pack_into('<II', md, off + i * 16 + 8, len(path), len(md) + len(tail))
        tail += path
    # texture unit (coord) lookup: retail models leave it empty, 3.3.5 reads it for every batch -> crash
    count, off = struct.unpack_from('<II', md, H['texunit'])
    if count == 0:
        while (len(md) + len(tail)) % 4:
            tail += b'\0'
        struct.pack_into('<II', md, H['texunit'], 8, len(md) + len(tail))
        tail += struct.pack('<8h', *([0] * 8))
    # textures set from the DBC (item skins, type != 0) have no file id in the model: copy all of the manifest
    for file in names.values():
        src_blp = os.path.normpath(os.path.join(src_dir, file.replace('\\', '/')))
        dst_blp = os.path.join(out_dir, os.path.basename(src_blp))
        if os.path.exists(src_blp) and not os.path.exists(dst_blp):
            shutil.copyfile(src_blp, dst_blp)
    if particles:
        while (len(md) + len(tail)) % 16:
            tail += b'\0'
        struct.pack_into('<II', md, H['particles'], len(particles) // PARTICLE_335, len(md) + len(tail))
        tail += particles
    md += tail
    while len(md) % 16:
        md += b'\0'
    open(os.path.join(out_dir, base + '.m2'), 'wb').write(md)

    # skin 00: batch shaders -> 3.3.5 combiners
    skin = bytearray(open(os.path.join(src_dir, base + '00.skin'), 'rb').read())
    count, off = struct.unpack_from('<II', skin, 4 + 4 * 8)
    for i in range(count):
        o = off + i * 24
        shader = struct.unpack_from('<H', skin, o + 2)[0]
        tex_count = struct.unpack_from('<H', skin, o + 14)[0]
        if shader & 0x8000 or tex_count == 1:
            shader, tex_count = 0, 1
        else:
            shader &= 0xFF
            tex_count = min(tex_count, 2)
        struct.pack_into('<H', skin, o + 2, shader)
        struct.pack_into('<H', skin, o + 14, tex_count)
    open(os.path.join(out_dir, base + '00.skin'), 'wb').write(skin)
    print('ok:', os.path.join(out_dir, base + '.m2'))


def guess_client_dir(folder):
    """...\item\objectcomponents\weapon -> Item\ObjectComponents\Weapon (from the item/world/creature part)."""
    parts = os.path.normpath(folder).replace('/', '\\').split('\\')
    for i, part in enumerate(parts):
        if part.lower() in ('item', 'world', 'creature', 'character', 'spells', 'environments'):
            return '\\'.join(p[:1].upper() + p[1:] for p in parts[i:])
    return parts[-1]


def convert_one(src, out_dir=None, client_dir=None, manifest=None):
    folder = os.path.dirname(os.path.abspath(src))
    base = os.path.splitext(os.path.basename(src))[0]
    if manifest is None and os.path.exists(os.path.join(folder, base + '.manifest.json')):
        manifest = os.path.join(folder, base + '.manifest.json')
    convert(src, out_dir or folder + '_out', client_dir or guess_client_dir(folder), manifest)


if __name__ == '__main__':
    # m2_legacy.py <model.m2 | folder> [out_dir] [client dir] [--manifest file]
    # a folder converts every .m2 in it; out_dir defaults to <folder>_out, the client dir is taken from the path
    args = sys.argv[1:]
    manifest = None
    if '--manifest' in args:
        i = args.index('--manifest')
        manifest = args[i + 1]
        del args[i:i + 2]
    if not args:
        print(__doc__)
        sys.exit(1)
    src = args[0]
    out_dir = args[1] if len(args) > 1 else None
    client_dir = args[2] if len(args) > 2 else None
    if os.path.isdir(src):
        for name in sorted(os.listdir(src)):
            if name.lower().endswith('.m2'):
                try:
                    convert_one(os.path.join(src, name), out_dir or os.path.abspath(src) + '_out', client_dir or guess_client_dir(src))
                except Exception as e:
                    print('fail:', name, e)
    else:
        convert_one(src, out_dir, client_dir, manifest)
