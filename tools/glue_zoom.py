"""Builds the zoomed character create backgrounds UI_<Name>_ZOOM from the client's UI_<Name> (3.3.5, M2 v264).

The zoomed copy is the same scene with its camera closer to the character's face; CharacterCreateRetail.lua
loads it with SetBackgroundModel(CharacterCreate, "<Name>_ZOOM") for the face options.
Only the .m2 and its .skin files are copied: the textures are referenced by full path and stay where they are.

Camera (WotLK, 100 bytes, M2 header cameras at 0x110): type, fov, far, near, positions track,
position_base (+36), target track, target_base (+68), roll track. The glue backgrounds keep static
cameras in the base vectors (the tracks hold zeros), so only the bases are moved. The character stands at
the background's attachment 0 (attachments at 0xF0, 40 bytes, position at +8):
  target' = the face: attachment 0 + the face height of the race / sex (ZOOMS) up
  camera' = level with it, on the scene camera's side, at the distance the head view needs (fov, VIEW)

Usage: python tools/glue_zoom.py <...\\Interface\\Glues\\Models> <out dir> [Human_Male ...]
Out: UI_<Race>_<Male|Female>_ZOOM (UI_DeathKnight_ZOOM for every death knight).
"""
import math
import os
import shutil
import struct
import sys

CAMERAS = 0x110
CAMERA_SIZE = 100
POSITION_BASE = 36
TARGET_BASE = 68

ATTACHMENTS = 0xF0     # attachment 0 of a glue background: where the character stands (feet)
ATTACHMENT_SIZE = 40
VIEW = 0.5              # the view this tall (scene units): head and shoulders
# one zoomed copy per race and sex: (out name, background, face height above the feet)
# the client puts gnomes on the Dwarf background, trolls on Orc, every death knight on DeathKnight
ZOOMS = [
    ("Human_Male", "Human", 1.75), ("Human_Female", "Human", 1.6),
    ("Dwarf_Male", "Dwarf", 1.25), ("Dwarf_Female", "Dwarf", 1.2),
    ("Gnome_Male", "Dwarf", 0.85), ("Gnome_Female", "Dwarf", 0.8),
    ("NightElf_Male", "NightElf", 2.1), ("NightElf_Female", "NightElf", 1.95),
    ("Draenei_Male", "Draenei", 2.15), ("Draenei_Female", "Draenei", 1.95),
    ("Orc_Male", "Orc", 1.6), ("Orc_Female", "Orc", 1.55),
    ("Troll_Male", "Orc", 1.7), ("Troll_Female", "Orc", 1.85),
    ("Scourge_Male", "Scourge", 1.5), ("Scourge_Female", "Scourge", 1.45),
    ("Tauren_Male", "Tauren", 2.0), ("Tauren_Female", "Tauren", 1.9),
    ("BloodElf_Male", "BloodElf", 1.75), ("BloodElf_Female", "BloodElf", 1.65),
    ("DeathKnight", "DeathKnight", 1.65),
]



def find_dir(models, name):
    for entry in os.listdir(models):
        if entry.lower() == ("ui_" + name).lower():
            return os.path.join(models, entry)
    return None


def zoom_camera(data, face_height):
    count, offset = struct.unpack_from("<II", data, CAMERAS)
    natt, oatt = struct.unpack_from("<II", data, ATTACHMENTS)
    if not natt:
        print("  no attachment 0 (the character's place)")
        return 0
    feet = struct.unpack_from("<3f", data, oatt + 8)
    face = (feet[0], feet[1], feet[2] + face_height)
    for i in range(count):
        base = offset + i * CAMERA_SIZE
        fov = struct.unpack_from("<f", data, base + 4)[0]
        pos = struct.unpack_from("<3f", data, base + POSITION_BASE)
        tgt = struct.unpack_from("<3f", data, base + TARGET_BASE)
        # the same side as the scene's camera, level with the face, as far as the head view needs
        dx, dy = pos[0] - feet[0], pos[1] - feet[1]
        length = math.hypot(dx, dy) or 1.0
        distance = (VIEW / 2) / math.tan(fov / 2)
        new_pos = (face[0] + dx / length * distance, face[1] + dy / length * distance, face[2])
        struct.pack_into("<3f", data, base + TARGET_BASE, *face)
        struct.pack_into("<3f", data, base + POSITION_BASE, *new_pos)
        print(f"  camera {i}: {fmt(pos)} -> {fmt(new_pos)}, target {fmt(tgt)} -> {fmt(face)} (feet {fmt(feet)})")
    return count


def fmt(v):
    return "(" + ", ".join(f"{x:.3f}" for x in v) + ")"


def build(models, out, name, background, face_height):
    source = find_dir(models, background)
    if not source:
        print(f"{name}: UI_{background} not found, skipped")
        return
    m2 = next((f for f in os.listdir(source) if f.lower() == f"ui_{background}.m2".lower()), None)
    if not m2:
        print(f"{name}: no UI_{background}.m2, skipped")
        return
    print(f"{name} (UI_{background}):")
    data = bytearray(open(os.path.join(source, m2), "rb").read())
    if struct.unpack_from("<I", data, 4)[0] != 264:
        print("  not a 3.3.5 M2 (version 264), skipped")
        return
    if not zoom_camera(data, face_height):
        print("  no camera, skipped")
        return
    target = os.path.join(out, f"UI_{name}_ZOOM")
    os.makedirs(target, exist_ok=True)
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
    only = {n.lower() for n in sys.argv[3:]}
    for name, background, face_height in ZOOMS:
        if not only or name.lower() in only:
            build(models, out, name, background, face_height)


if __name__ == "__main__":
    main()
