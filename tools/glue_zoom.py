"""Builds the zoomed character create backgrounds UI_<Name>_ZOOM from the client's UI_<Name> (3.3.5, M2 v264).

The zoomed copy is the same scene with its camera closer to the character's face; CharacterCreateRetail.lua
loads it with SetBackgroundModel(CharacterCreate, "<Name>_ZOOM") for the face options.
Only the .m2 and its .skin files are copied: the textures are referenced by full path and stay where they are.

Camera (WotLK, 100 bytes, M2 header cameras at 0x110): type, fov, far, near, positions track,
position_base (+36), target track, target_base (+68), roll track. The glue backgrounds keep static
cameras in the base vectors (the tracks hold zeros), so only the bases are moved:
  target' = target + (0, 0, LIFT)                         raised from the chest to the face
  camera' = target' + (camera - target) * DISTANCE        same direction, closer

Usage: python tools/glue_zoom.py <...\\Interface\\Glues\\Models> <out dir> [Name ...]
"""
import os
import shutil
import struct
import sys

CAMERAS = 0x110
CAMERA_SIZE = 100
POSITION_BASE = 36
TARGET_BASE = 68

DISTANCE = 0.6      # of the camera's distance to its target
LIFT = 0.3          # the target up to the face (scene units)
# per background (smaller races, other scales); missing names use the defaults above
TUNING = {
    "Dwarf": (0.65, 0.12),       # also the gnomes
    "Tauren": (0.6, 0.4),
}

DEFAULT_NAMES = ["Human", "Dwarf", "NightElf", "Draenei", "Orc", "Scourge", "Tauren", "BloodElf", "DeathKnight"]


def find_dir(models, name):
    for entry in os.listdir(models):
        if entry.lower() == ("ui_" + name).lower():
            return os.path.join(models, entry)
    return None


def zoom_camera(data, name):
    distance, lift = TUNING.get(name, (DISTANCE, LIFT))
    count, offset = struct.unpack_from("<II", data, CAMERAS)
    for i in range(count):
        base = offset + i * CAMERA_SIZE
        pos = struct.unpack_from("<3f", data, base + POSITION_BASE)
        tgt = struct.unpack_from("<3f", data, base + TARGET_BASE)
        new_tgt = (tgt[0], tgt[1], tgt[2] + lift)
        new_pos = tuple(new_tgt[k] + (pos[k] - tgt[k]) * distance for k in range(3))
        struct.pack_into("<3f", data, base + TARGET_BASE, *new_tgt)
        struct.pack_into("<3f", data, base + POSITION_BASE, *new_pos)
        print(f"  camera {i}: {fmt(pos)} -> {fmt(new_pos)}, target {fmt(tgt)} -> {fmt(new_tgt)}")
    return count


def fmt(v):
    return "(" + ", ".join(f"{x:.3f}" for x in v) + ")"


def build(models, out, name):
    source = find_dir(models, name)
    if not source:
        print(f"{name}: UI_{name} not found, skipped")
        return
    m2 = next((f for f in os.listdir(source) if f.lower() == f"ui_{name}.m2".lower()), None)
    if not m2:
        print(f"{name}: no UI_{name}.m2, skipped")
        return
    target = os.path.join(out, f"UI_{name}_ZOOM")
    os.makedirs(target, exist_ok=True)
    print(f"{name}:")
    data = bytearray(open(os.path.join(source, m2), "rb").read())
    if struct.unpack_from("<I", data, 4)[0] != 264:
        print("  not a 3.3.5 M2 (version 264), skipped")
        return
    if not zoom_camera(data, name):
        print("  no camera, skipped")
        return
    open(os.path.join(target, f"UI_{name}_ZOOM.m2"), "wb").write(data)
    stem = os.path.splitext(m2)[0].lower()
    for f in os.listdir(source):
        low = f.lower()
        if low.startswith(stem) and low.endswith(".skin"):
            shutil.copyfile(os.path.join(source, f), os.path.join(target, f"UI_{name}_ZOOM{low[len(stem):]}"))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    models, out = sys.argv[1], sys.argv[2]
    for name in sys.argv[3:] or DEFAULT_NAMES:
        build(models, out, name)


if __name__ == "__main__":
    main()
