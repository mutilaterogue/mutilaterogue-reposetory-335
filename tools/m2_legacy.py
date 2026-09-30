#!/usr/bin/env python3
"""Convert a retail (chunked MD21, version 272+) M2 doodad to WotLK 3.3.5 (version 264).

    m2_legacy.py <model.m2> <out_dir> <client path of the model dir> [--manifest file.manifest.json]

What it does:
  * unwraps MD21 -> MD20, version 264;
  * texture file IDs (TXID) -> file names: textures are copied next to the model
    (name from the .manifest.json, else <model>_<fileid>.blp) and referenced by path;
  * drops particles / ribbons / lights / cameras (their retail layout differs);
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


if __name__ == '__main__':
    args = sys.argv[1:]
    manifest = None
    if '--manifest' in args:
        i = args.index('--manifest')
        manifest = args[i + 1]
        del args[i:i + 2]
    convert(args[0], args[1], args[2], manifest)
