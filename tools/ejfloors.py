#!/usr/bin/env python3
"""
Works out which dungeon floor each journal boss stands on, and its position on
that floor's map, by matching creature spawns against DungeonMap boundaries.

Inputs (all in the same directory as the data file unless said otherwise):

    DungeonMap.dbc       floor rectangles in world coordinates
    DungeonMapChunk.dbc  optional: lowest height (MinZ) of each floor piece
    creatures.csv        entry, difficulty_entry_1, modelid1..4, name
    spawns.csv           entry, map, position_x, position_y [, position_z]

Floors of one map overlap (ICC, Ulduar: floors stacked above each other). With
DungeonMapChunk.dbc and position_z the floor is chosen the way the client does it:
of the floors whose rectangle holds the point, the one with the highest MinZ that is
still below the boss. Without them the lowest floor is taken, which puts upper
floor bosses on the ground floor.

    SELECT id, map, position_x, position_y, position_z FROM creature;

The journal stores a display id per boss; creatures.csv maps that to a
creature_template entry, and spawns.csv gives the world position.

World coordinates are rotated relative to map coordinates: the map x axis runs
along the world y axis and vice versa, which is why MinX/MaxX are compared
against position_y.

Usage:
    py ejfloors.py [EncounterJournalData.lua] [csv_dbc_dir] [output.lua]
"""
import collections
import os
import re
import struct
import sys


def read_dungeon_map(path):
    """[(id, mapID, floorIndex, minX, maxX, minY, maxY)]"""
    data = open(path, "rb").read()
    magic, rows, fields, rowsize, strsize = struct.unpack_from("<4siiii", data, 0)
    if magic != b"WDBC" or fields != 8:
        raise SystemExit("%s: expected 8 fields, got %d" % (path, fields))

    out = []
    for r in range(rows):
        b = 20 + r * rowsize
        rid, mapID, floor = struct.unpack_from("<iii", data, b)
        minX, maxX, minY, maxY = struct.unpack_from("<ffff", data, b + 12)
        out.append((rid, mapID, floor, minX, maxX, minY, maxY))
    return out


def read_dungeon_map_chunks(path):
    """DungeonMap ID -> highest MinZ of its chunks (ID, MapID, WMOGroupID, DungeonMapID, MinZ)."""
    if not os.path.exists(path):
        return {}
    data = open(path, "rb").read()
    magic, rows, fields, rowsize, strsize = struct.unpack_from("<4siiii", data, 0)
    if magic != b"WDBC" or fields != 5:
        raise SystemExit("%s: expected 5 fields, got %d" % (path, fields))
    out = {}
    for r in range(rows):
        b = 20 + r * rowsize
        _rid, _mapID, _group, dungeonMapID = struct.unpack_from("<iiii", data, b)
        (minZ,) = struct.unpack_from("<f", data, b + 16)
        out.setdefault(dungeonMapID, []).append(minZ)
    return out


def read_csv(path, ncols):
    rows = []
    for encoding in ("utf-8", "cp1251"):
        try:
            rows = []
            with open(path, encoding=encoding) as fh:
                for line in fh:
                    parts = line.rstrip("\r\n").split("\t")
                    if len(parts) >= ncols:
                        rows.append(parts)
            return rows
        except UnicodeDecodeError:
            continue
    raise SystemExit("could not decode " + path)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "EncounterJournalData.lua"
    datadir = sys.argv[2] if len(sys.argv) > 2 else "."
    dst = sys.argv[3] if len(sys.argv) > 3 else "EncounterJournalData.lua"

    floors = read_dungeon_map(os.path.join(datadir, "DungeonMap.dbc"))
    by_map = collections.defaultdict(list)
    chunks = read_dungeon_map_chunks(os.path.join(datadir, "DungeonMapChunk.dbc"))
    for rid, mapID, floor, minX, maxX, minY, maxY in floors:
        by_map[mapID].append((floor, minX, maxX, minY, maxY, chunks.get(rid, [])))
    print("DungeonMapChunk.dbc %s" % ("%d floors with heights" % len(chunks) if chunks else "missing: lowest floor rule"),
          file=sys.stderr)
    print("DungeonMap.dbc      %d floors over %d maps"
          % (len(floors), len(by_map)), file=sys.stderr)

    # display model -> creature entries
    model2entry = collections.defaultdict(set)
    for p in read_csv(os.path.join(datadir, "creatures.csv"), 7):
        try:
            entry = int(p[0])
        except ValueError:
            continue
        for m in p[2:6]:
            try:
                mid = int(m)
            except ValueError:
                continue
            if mid > 0:
                model2entry[mid].add(entry)
    print("creatures.csv       %d models" % len(model2entry), file=sys.stderr)

    # creature entry -> spawn points per map
    spawns = collections.defaultdict(list)
    for p in read_csv(os.path.join(datadir, "spawns.csv"), 4):
        try:
            entry = int(p[0])
            mapID = int(p[1])
            x = float(p[2])
            y = float(p[3])
            z = float(p[4]) if len(p) > 4 and p[4] != "" else None
        except ValueError:
            continue
        spawns[entry].append((mapID, x, y, z))
    print("spawns.csv          %d creatures" % len(spawns), file=sys.stderr)

    text = open(src, encoding="utf-8", errors="replace").read()

    instances = {}
    for m in re.finditer(r"EJ_DATA\.instances\[(\d+)\] = \{ mapID = (\d+)", text):
        instances[int(m.group(1))] = int(m.group(2))

    encounters = {}
    for m in re.finditer(
            r"EJ_DATA\.encounters\[(\d+)\] = \{ (?:floor = \d+, )?instanceID = (\d+)", text):
        encounters[int(m.group(1))] = int(m.group(2))

    creatures = collections.defaultdict(list)
    for m in re.finditer(
            r"EJ_DATA\.creatures\[\d+\] = \{ encounterID = (\d+), modelID = (\d+)",
            text):
        creatures[int(m.group(1))].append(int(m.group(2)))

    placed = 0
    missing_spawn = 0
    outside = 0
    updates = {}

    for encounterID, models in creatures.items():
        instanceID = encounters.get(encounterID)
        mapID = instances.get(instanceID)
        if not mapID or mapID not in by_map:
            continue

        # average the spawn points of every model this boss uses
        points = []
        for model in models:
            for entry in model2entry.get(model, ()):
                for smap, sx, sy, sz in spawns.get(entry, ()):
                    if smap == mapID:
                        points.append((sx, sy, sz))

        if not points:
            missing_spawn += 1
            continue

        wx = sum(p[0] for p in points) / len(points)
        wy = sum(p[1] for p in points) / len(points)
        heights = [p[2] for p in points if p[2] is not None]
        wz = sum(heights) / len(heights) if heights else None

        # floors whose rectangle holds the point (map x runs along world y, map y along world x)
        candidates = [f for f in sorted(by_map[mapID])
                      if f[1] <= wy <= f[2] and f[3] <= wx <= f[4]]
        hit = None
        if wz is not None and any(f[5] for f in candidates):
            # like the client: the highest floor that starts below the boss
            below = [(max(z for z in f[5] if z <= wz + 1.0), f) for f in candidates
                     if f[5] and any(z <= wz + 1.0 for z in f[5])]
            if below:
                hit = max(below, key=lambda b: b[0])[1]
        if not hit and candidates:
            # rectangles overlap: the lowest floor (the old rule, no heights known)
            hit = candidates[0]

        if not hit:
            outside += 1
            continue

        floor, minX, maxX, minY, maxY = hit[:5]
        nx = (wy - minX) / (maxX - minX)
        ny = 1.0 - (wx - minY) / (maxY - minY)

        updates[encounterID] = (floor, nx, ny)
        placed += 1

    print("", file=sys.stderr)
    print("bosses placed on a floor  %d" % placed, file=sys.stderr)
    print("bosses without a spawn    %d" % missing_spawn, file=sys.stderr)
    print("spawns outside any floor  %d" % outside, file=sys.stderr)

    def patch(m):
        encounterID = int(m.group(1))
        upd = updates.get(encounterID)
        body = m.group(0)
        body = re.sub(r"\{ floor = \d+, instanceID", "{ instanceID", body, count=1)
        if not upd:
            return body.replace("{ instanceID", "{ floor = 0, instanceID", 1)
        floor, nx, ny = upd
        body = re.sub(r"x = [\d.\-]+, y = [\d.\-]+",
                      "x = %.6f, y = %.6f" % (nx, ny), body)
        return body.replace("{ instanceID", "{ floor = %d, instanceID" % floor, 1)

    text = re.sub(r"EJ_DATA\.encounters\[(\d+)\] = \{[^\n]*\};", patch, text)

    open(dst, "w", encoding="utf-8").write(text)
    print("", file=sys.stderr)
    print("wrote %s" % dst, file=sys.stderr)


if __name__ == "__main__":
    main()