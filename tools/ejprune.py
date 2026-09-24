#!/usr/bin/env python3
"""
Prunes the loot in EncounterJournalData.lua:

  * drops items that are not present in ItemCache.lua at all
  * drops grey and white items, which are vendor trash and crafting scraps
  * keeps quest items and recipes whatever their quality

Usage:
    py ejprune.py [EncounterJournalData.lua] [ItemCache.lua] [output.lua]
"""
import collections
import re
import sys


ITEM_CLASS_RECIPE = 9
ITEM_CLASS_QUEST = 12
MIN_QUALITY = 2          # uncommon and better


def main():
    src   = sys.argv[1] if len(sys.argv) > 1 else "EncounterJournalData.lua"
    cache = sys.argv[2] if len(sys.argv) > 2 else "ItemCache.lua"
    dst   = sys.argv[3] if len(sys.argv) > 3 else "EncounterJournalData.lua"

    # ---- item cache: id -> (quality, class) -------------------------------
    keep_item = {}
    known = set()

    for m in re.finditer(
            r'ITEM_CACHE\[(\d+)\] = \{ "(?:[^"\\]|\\.)*", (\d+), (\d+),', 
            open(cache, encoding="utf-8", errors="replace").read()):
        itemID = int(m.group(1))
        quality = int(m.group(2))
        cls = int(m.group(3))
        known.add(itemID)
        keep_item[itemID] = (quality >= MIN_QUALITY
                             or cls in (ITEM_CLASS_QUEST, ITEM_CLASS_RECIPE))

    print("items in cache          %d" % len(known), file=sys.stderr)
    print("  of those worth showing %d" % sum(1 for v in keep_item.values() if v),
          file=sys.stderr)

    # ---- walk the journal data -------------------------------------------
    text = open(src, encoding="utf-8", errors="replace").read()

    kept_rows = []
    by_encounter = collections.defaultdict(list)

    dropped_unknown = 0
    dropped_quality = 0
    kept = 0

    for m in re.finditer(
            r"EJ_DATA\.items\[(\d+)\] = \{ encounterID = (\d+), itemID = (\d+), "
            r"difficulty = (-?\d+) \};", text):
        rowID = int(m.group(1))
        encID = int(m.group(2))
        itemID = int(m.group(3))
        difficulty = int(m.group(4))

        if itemID not in known:
            dropped_unknown += 1
            continue
        if not keep_item[itemID]:
            dropped_quality += 1
            continue

        kept_rows.append((rowID, encID, itemID, difficulty))
        by_encounter[encID].append(rowID)
        kept += 1

    print("", file=sys.stderr)
    print("loot rows kept          %d" % kept, file=sys.stderr)
    print("dropped, not in cache   %d" % dropped_unknown, file=sys.stderr)
    print("dropped, grey or white  %d" % dropped_quality, file=sys.stderr)

    # ---- splice ------------------------------------------------------------
    block = ["", "-- Loot pruned by ejprune.py: nothing below uncommon except",
             "-- quest items and recipes, and nothing missing from ItemCache.", ""]
    for rowID, encID, itemID, difficulty in kept_rows:
        block.append("EJ_DATA.items[%d] = { encounterID = %d, itemID = %d, "
                     "difficulty = %d };" % (rowID, encID, itemID, difficulty))
    block.append("")
    for encID in sorted(by_encounter):
        block.append("EJ_DATA.itemsByEncounter[%d] = { %s };"
                     % (encID, ", ".join(str(i) for i in by_encounter[encID])))
    block.append("")

    text = re.sub(r"^EJ_DATA\.items\[\d+\] = \{[^\n]*\n", "", text, flags=re.M)
    text = re.sub(r"^EJ_DATA\.itemsByEncounter\[\d+\] = \{[^\n]*\n", "", text,
                  flags=re.M)
    text = text.rstrip("\n") + "\n" + "\n".join(block)

    open(dst, "w", encoding="utf-8").write(text)
    print("", file=sys.stderr)
    print("wrote %s" % dst, file=sys.stderr)


if __name__ == "__main__":
    main()