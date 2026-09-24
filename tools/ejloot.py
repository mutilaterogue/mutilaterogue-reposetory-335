#!/usr/bin/env python3
"""
Rebuilds the loot tables in EncounterJournalData.lua using the world database,
so that normal and heroic show different items.

Inputs (tab separated, dumped from the world DB):

    creatures.csv       entry, difficulty_entry_1, modelid1..4, name
    creature_loot.csv   Entry, Item, Reference, Chance, GroupId
    reference_loot.csv  Entry, Item, Reference, Chance

Journal creatures are matched to creature_template by display model. Where a
model maps to several entries, the one whose difficulty_entry_1 points at
another entry in the same set is taken as the normal version, and that pointer
gives the heroic version.

Raids have four difficulties: 10 normal (the entry), 25 normal
(difficulty_entry_1), 10 heroic and 25 heroic (difficulty_entry_2 / _3).
creatures.csv has no _2 / _3 columns, so they are found by the core's naming
convention: "<name> (2)" and "<name> (3)". If the dump gets two more columns
(entry, difficulty_entry_1, difficulty_entry_2, difficulty_entry_3, modelid1..4,
name) they are used instead.

Chests (optional, gameobject loot - gunship, Deathbringer, Dreamwalker, Faction
Champions, Ulduar keepers, ...): each chest spawn is given to the nearest boss of
its instance, and its spawnMask is the difficulty (same bits as below).

    gameobjects.csv       entry, name, Data1 (loot id), map, position_x, position_y,
                          position_z, spawnMask
    gameobject_loot.csv   Entry, Item, Reference, Chance, GroupId
    spawns.csv            id, map, position_x, position_y, position_z (boss positions)

Difficulty is written as a bitmask, bit = 2^(journal difficulty index - 1):
    dungeons: 1 normal, 2 heroic
    raids:    1 10 normal, 2 25 normal, 4 10 heroic, 8 25 heroic
A raid without heroic entries shows its 10 / 25 normal loot on the heroic
difficulties too; a raid with a single difficulty shows its loot everywhere.

Usage:
    py ejloot.py [EncounterJournalData.lua] [csv_dir] [output.lua]
"""
import collections
import os
import re
import sys


MAX_REFERENCE_DEPTH = 6


def read_csv(path, ncols):
    """Tab separated rows, or a quoted CSV export with a header (it fails the int parse)."""
    import csv
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as fh:
        first = fh.readline()
        if "\t" not in first:
            fh.seek(0)
            return [row for row in csv.reader(fh) if len(row) >= ncols]
    rows = []
    for encoding in ("utf-8", "cp1251"):
        try:
            rows = []
            with open(path, encoding=encoding) as fh:
                for line in fh:
                    parts = line.rstrip("\r\n").split("\t")
                    if len(parts) < ncols:
                        continue
                    rows.append(parts)
            return rows
        except UnicodeDecodeError:
            continue
    raise SystemExit("could not decode " + path)


def load_creatures(path):
    """Returns model -> set(entry), entry -> heroic entry, entry -> name,
    entry -> [difficulty_entry_2, difficulty_entry_3] (only with the long dump)."""
    model2entry = collections.defaultdict(set)
    heroic = {}
    names = {}
    extra = {}

    for p in read_csv(path, 7):
        try:
            entry = int(p[0])
            dif = int(p[1])
        except ValueError:
            continue
        if len(p) >= 9:
            try:
                extra[entry] = [int(p[2]), int(p[3])]
            except ValueError:
                pass
            p = p[:2] + p[4:]
        heroic[entry] = dif
        names[entry] = p[6]
        for m in p[2:6]:
            try:
                mid = int(m)
            except ValueError:
                continue
            if mid > 0:
                model2entry[mid].add(entry)

    return model2entry, heroic, names, extra


def raid_heroic_entries(entry, names, name2entry, extra):
    """Returns [10 heroic entry, 25 heroic entry] of a raid creature (None if missing)."""
    if entry in extra:
        return [e if e > 0 else None for e in extra[entry]]
    base = names.get(entry)
    out = []
    for n in (2, 3):
        found = name2entry.get("%s (%d)" % (base, n)) if base else None
        out.append(min(found) if found else None)
    return out


def load_loot(path, ncols):
    """Returns entry -> [(item, reference)]."""
    table = collections.defaultdict(list)
    for p in read_csv(path, ncols):
        try:
            entry = int(p[0])
            item = int(p[1])
            ref = int(p[2])
            chance = float(p[3])
        except ValueError:
            continue
        # chance 0 means the row is part of a group roll, it still drops
        table[entry].append((item, ref, chance))
    return table


def expand(entry, creature_loot, reference_loot, depth=0, seen=None):
    """Flattens a loot entry into a set of item ids, following references."""
    if depth > MAX_REFERENCE_DEPTH:
        return set()
    if seen is None:
        seen = set()

    key = (entry, depth > 0)
    if key in seen:
        return set()
    seen.add(key)

    table = reference_loot if depth > 0 else creature_loot
    rows = table.get(entry)
    if not rows:
        return set()

    items = set()
    for item, ref, _chance in rows:
        if ref and ref > 0:
            items |= expand(ref, creature_loot, reference_loot, depth + 1, seen)
        elif item > 0:
            items.add(item)
    return items


def resolve_entry(model, model2entry, heroic):
    """Returns (normal_entry, heroic_entry) or (None, None)."""
    s = model2entry.get(model)
    if not s:
        return None, None

    if len(s) == 1:
        e = next(iter(s))
        h = heroic.get(e, 0)
        return e, (h if h > 0 else None)

    # prefer the entry whose difficulty_entry_1 points at a sibling
    for e in sorted(s):
        h = heroic.get(e, 0)
        if h and h in s:
            return e, h

    # otherwise take the lowest entry that has any heroic pointer
    for e in sorted(s):
        h = heroic.get(e, 0)
        if h:
            return e, h

    return None, None


MAX_CHEST_DISTANCE = 150.0


def load_chests(csvdir, text, model2entry, reference_loot):
    """encounterID -> [set per difficulty index 0..3] of chest items; prints unmatched chests."""
    go_path = os.path.join(csvdir, "gameobjects.csv")
    loot_path = os.path.join(csvdir, "gameobject_loot.csv")
    spawn_path = os.path.join(csvdir, "spawns.csv")
    chests = collections.defaultdict(lambda: [set(), set(), set(), set()])
    if not (os.path.exists(go_path) and os.path.exists(loot_path) and os.path.exists(spawn_path)):
        print("chests: gameobjects.csv / gameobject_loot.csv / spawns.csv missing, skipped", file=sys.stderr)
        return chests

    go_loot = load_loot(loot_path, 5)

    inst_map = {int(i): int(m) for i, m in re.findall(
        r"EJ_DATA\.instances\[(\d+)\] = \{ mapID = (\d+)", text)}
    enc_inst = {int(e): int(i) for e, i in re.findall(
        r"EJ_DATA\.encounters\[(\d+)\] = \{ (?:floor = \d+, )?instanceID = (\d+)", text)}
    enc_models = collections.defaultdict(list)
    for e, m in re.findall(r"EJ_DATA\.creatures\[\d+\] = \{ encounterID = (\d+), modelID = (\d+)", text):
        enc_models[int(e)].append(int(m))

    spawns = collections.defaultdict(list)
    for p in read_csv(spawn_path, 5):
        try:
            spawns[int(p[0])].append((int(p[1]), float(p[2]), float(p[3]), float(p[4])))
        except ValueError:
            continue

    # boss position: average spawn of the boss creatures on the instance map
    boss_pos = collections.defaultdict(list)   # map -> [(encounterID, x, y, z)]
    for encid, models in enc_models.items():
        mapID = inst_map.get(enc_inst.get(encid))
        points = [(x, y, z) for model in models for entry in model2entry.get(model, ())
                  for smap, x, y, z in spawns.get(entry, ()) if smap == mapID]
        if points:
            n = float(len(points))
            boss_pos[mapID].append((encid, sum(p[0] for p in points) / n,
                                    sum(p[1] for p in points) / n, sum(p[2] for p in points) / n))

    matched = unmatched = 0
    for p in read_csv(go_path, 8):
        try:
            name = p[1]
            lootid, mapID = int(p[2]), int(p[3])
            x, y, z = float(p[4]), float(p[5]), float(p[6])
            mask = int(p[7]) or 1
        except ValueError:
            continue
        best = None
        for encid, bx, by, bz in boss_pos.get(mapID, ()):
            dist = ((x - bx) ** 2 + (y - by) ** 2 + (z - bz) ** 2) ** 0.5
            if best is None or dist < best[0]:
                best = (dist, encid)
        if not best or best[0] > MAX_CHEST_DISTANCE:
            unmatched += 1
            print("  chest without a boss nearby: %s (entry %s, map %d)" % (name, p[0], mapID), file=sys.stderr)
            continue
        items = expand(lootid, go_loot, reference_loot)
        for index in range(4):
            if mask & (1 << index):
                chests[best[1]][index] |= items
        matched += 1
    print("chests given to a boss      %d, without a boss %d" % (matched, unmatched), file=sys.stderr)
    return chests


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "EncounterJournalData.lua"
    csvdir = sys.argv[2] if len(sys.argv) > 2 else "."
    dst = sys.argv[3] if len(sys.argv) > 3 else "EncounterJournalData.lua"

    text = open(src, encoding="utf-8", errors="replace").read()

    model2entry, heroic, names, extra = load_creatures(os.path.join(csvdir, "creatures.csv"))
    name2entry = collections.defaultdict(set)
    for entry, name in names.items():
        name2entry[name].add(entry)

    # ---- which encounters belong to raids ----------------------------------
    raid_instances = set(int(i) for i in re.findall(
        r"EJ_DATA\.instances\[(\d+)\] = \{[^\n]*?isRaid = true", text))
    raid_encounters = set(int(e) for e, i in re.findall(
        r"EJ_DATA\.encounters\[(\d+)\] = \{[^\n]*?instanceID = (\d+)", text)
        if int(i) in raid_instances)
    creature_loot = load_loot(os.path.join(csvdir, "creature_loot.csv"), 5)
    reference_loot = load_loot(os.path.join(csvdir, "reference_loot.csv"), 4)

    print("creature_template rows   %d" % len(heroic), file=sys.stderr)
    print("creature_loot entries    %d" % len(creature_loot), file=sys.stderr)
    print("reference_loot entries   %d" % len(reference_loot), file=sys.stderr)

    # ---- journal creatures, grouped by encounter --------------------------
    creatures = re.findall(
        r"EJ_DATA\.creatures\[(\d+)\] = \{ encounterID = (\d+), modelID = (\d+)",
        text)

    by_encounter = collections.defaultdict(list)
    for _cid, encid, mid in creatures:
        by_encounter[int(encid)].append(int(mid))

    # ---- existing journal loot, so unmatched encounters keep theirs -------
    old_items = {}
    for m in re.finditer(
            r"EJ_DATA\.items\[(\d+)\] = \{ encounterID = (\d+), itemID = (\d+), "
            r"difficulty = (-?\d+) \};", text):
        old_items[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))

    old_by_encounter = collections.defaultdict(set)
    for _rid, (encid, itemid) in old_items.items():
        old_by_encounter[encid].add(itemid)

    chests = load_chests(csvdir, text, model2entry, reference_loot)

    matched = 0
    unmatched = 0
    raid_fallback = [0, 0]   # raid encounters without a 10 / 25 heroic entry
    lines = []
    by_enc_ids = collections.defaultdict(list)
    next_id = 1

    for encid in sorted(set(list(by_encounter) + list(old_by_encounter) + list(chests))):
        is_raid = encid in raid_encounters
        # per difficulty index (0-based): dungeon normal / heroic, raid 10N / 25N / 10H / 25H
        per_diff = [set(), set(), set(), set()]
        has_entry = [False, False, False, False]
        found = False

        for model in by_encounter.get(encid, []):
            n_entry, h_entry = resolve_entry(model, model2entry, heroic)
            if not n_entry:
                continue
            found = True
            entries = [n_entry, h_entry]
            if is_raid:
                entries += raid_heroic_entries(n_entry, names, name2entry, extra)
            for index, entry in enumerate(entries):
                if entry:
                    has_entry[index] = True
                    per_diff[index] |= expand(entry, creature_loot, reference_loot)

        # chest loot (spawnMask bits = difficulty index bits)
        for index, items in enumerate(chests.get(encid, ())):
            if items:
                found = True
                has_entry[index] = True
                per_diff[index] |= items

        if not found or not any(per_diff):
            unmatched += 1
            # keep whatever the journal export had, visible everywhere
            mask_all = 15 if is_raid else 3
            for itemid in sorted(old_by_encounter.get(encid, ())):
                lines.append("EJ_DATA.items[%d] = { encounterID = %d, itemID = %d, "
                             "difficulty = %d };" % (next_id, encid, itemid, mask_all))
                by_enc_ids[encid].append(next_id)
                next_id += 1
            continue

        matched += 1
        if is_raid:
            if not has_entry[1] and not per_diff[1]:
                # single difficulty raid (classic, TBC): its loot on every difficulty
                per_diff = [set(per_diff[0])] * 4
            else:
                if not has_entry[2]:
                    per_diff[2] = set(per_diff[0])
                    raid_fallback[0] += 1
                if not has_entry[3]:
                    per_diff[3] = set(per_diff[1])
                    raid_fallback[1] += 1
            num = 4
        else:
            if not per_diff[1]:
                per_diff[1] = set(per_diff[0])
            num = 2

        all_items = set()
        for index in range(num):
            all_items |= per_diff[index]
        for itemid in sorted(all_items):
            mask = 0
            for index in range(num):
                if itemid in per_diff[index]:
                    mask |= 1 << index
            lines.append("EJ_DATA.items[%d] = { encounterID = %d, itemID = %d, "
                         "difficulty = %d };" % (next_id, encid, itemid, mask))
            by_enc_ids[encid].append(next_id)
            next_id += 1

    print("", file=sys.stderr)
    print("encounters rebuilt from DB  %d" % matched, file=sys.stderr)
    print("encounters kept as exported %d" % unmatched, file=sys.stderr)
    print("raid bosses, 10H = 10N      %d" % raid_fallback[0], file=sys.stderr)
    print("raid bosses, 25H = 25N      %d" % raid_fallback[1], file=sys.stderr)
    print("loot rows written           %d" % len(lines), file=sys.stderr)

    # ---- splice the new loot into the file --------------------------------
    block = ["", "-- Loot rebuilt from the world database by ejloot.py.",
             "-- difficulty is a bitmask, bit = 2^(difficulty index - 1):",
             "--   dungeons 1 normal, 2 heroic; raids 1 10N, 2 25N, 4 10H, 8 25H.", ""]
    block += lines
    block.append("")
    for encid in sorted(by_enc_ids):
        block.append("EJ_DATA.itemsByEncounter[%d] = { %s };"
                     % (encid, ", ".join(str(i) for i in by_enc_ids[encid])))
    block.append("")

    # drop every old item line and index line
    text = re.sub(r"^EJ_DATA\.items\[\d+\] = \{[^\n]*\n", "", text, flags=re.M)
    text = re.sub(r"^EJ_DATA\.itemsByEncounter\[\d+\] = \{[^\n]*\n", "", text,
                  flags=re.M)
    text = text.replace("EJ_DATA.difficultyFiltering = false;",
                        "EJ_DATA.difficultyFiltering = true;")

    text = text.rstrip("\n") + "\n" + "\n".join(block)

    open(dst, "w", encoding="utf-8").write(text)
    print("", file=sys.stderr)
    print("wrote %s" % dst, file=sys.stderr)


if __name__ == "__main__":
    main()