#!/usr/bin/env python3
"""
Builds EncounterJournalItemSets.lua (the journal's "Item sets" tab).

    item_template    which items belong to a set (itemset column), item level, class,
                     required level, bonding, stats - the source of the set contents
    ItemSet.dbc      only the set name and its bonus spells / thresholds
    Spell.dbc        bonus descriptions ($s1 / ${...} tokens are resolved here)
    ItemCache.lua    quality and icon check (items missing from the client are dropped)

Only raid and dungeon sets are kept (see the filters below): bind on pickup, no
resilience (PvP), with stats, item level >= MIN_ITEM_LEVEL, required level >= MIN_REQUIRED_LEVEL.
A set is split into one row per item level (tier 10 normal / heroic / sanctified share
one ItemSet), and a row needs at least MIN_PIECES items.

item_template export (CSV with header, as exported, or tab separated with header):

    SELECT entry, Quality, ItemLevel, RequiredLevel, AllowableClass, itemset, bonding, StatsCount,
           (stat_type1 = 35 OR stat_type2 = 35 OR stat_type3 = 35 OR stat_type4 = 35 OR
            stat_type5 = 35 OR stat_type6 = 35 OR stat_type7 = 35 OR stat_type8 = 35 OR
            stat_type9 = 35 OR stat_type10 = 35) AS resilience
    FROM item_template WHERE itemset > 0;

Usage:
    py ejsets.py [ItemSet.dbc] [Spell.dbc] [ItemCache.lua] [output.lua] [items_ext.csv]
"""
import os
import re
import struct
import sys

LOCALE = 8   # ruRU slot of the localized strings

MIN_ITEM_LEVEL = 115
MIN_REQUIRED_LEVEL = 55
MIN_PIECES = 4
BIND_ON_PICKUP = 1


def load_dbc(path):
    data = open(path, "rb").read()
    if data[:4] != b"WDBC":
        raise SystemExit(path + ": not a WDBC file")
    count, fields, size, strsize = struct.unpack("<4I", data[4:20])
    records = data[20:20 + count * size]
    strings = data[20 + count * size:]
    rows = [struct.unpack("<%dI" % fields, records[i * size:(i + 1) * size]) for i in range(count)]

    def string(offset):
        end = strings.index(b"\0", offset)
        return strings[offset:end].decode("utf-8", "replace")

    return rows, string


def signed(value):
    return value - 2 ** 32 if value >= 2 ** 31 else value


def as_float(value):
    return struct.unpack("<f", struct.pack("<I", value))[0]


# Spell.dbc 3.3.5 (12340) layout: name -> (first field, count)
SPELL_FIELDS = [
    ("ID", 1), ("Category", 1), ("DispelType", 1), ("Mechanic", 1), ("Attributes", 8),
    ("ShapeshiftMask", 2), ("ShapeshiftExclude", 2), ("Targets", 1), ("TargetCreatureType", 1),
    ("RequiresSpellFocus", 1), ("FacingCasterFlags", 1), ("AuraStates", 4), ("AuraSpells", 4),
    ("CastingTimeIndex", 1), ("RecoveryTime", 1), ("CategoryRecoveryTime", 1), ("InterruptFlags", 3),
    ("ProcTypeMask", 1), ("ProcChance", 1), ("ProcCharges", 1), ("MaxLevel", 1), ("BaseLevel", 1),
    ("SpellLevel", 1), ("DurationIndex", 1), ("PowerType", 1), ("ManaCost", 4), ("RangeIndex", 1),
    ("Speed", 1), ("ModalNextSpell", 1), ("CumulativeAura", 1), ("Totem", 2), ("Reagent", 8),
    ("ReagentCount", 8), ("EquippedItem", 3), ("Effect", 3), ("EffectDieSides", 3),
    ("EffectRealPointsPerLevel", 3), ("EffectBasePoints", 3), ("EffectMechanic", 3),
    ("ImplicitTargetA", 3), ("ImplicitTargetB", 3), ("EffectRadiusIndex", 3), ("EffectAura", 3),
    ("EffectAuraPeriod", 3), ("EffectMultipleValue", 3), ("EffectChainTargets", 3),
    ("EffectItemType", 3), ("EffectMiscValue", 3), ("EffectMiscValueB", 3),
    ("EffectTriggerSpell", 3), ("EffectPointsPerCombo", 3), ("EffectSpellClassMask", 9),
    ("SpellVisualID", 2), ("SpellIconID", 1), ("ActiveIconID", 1), ("SpellPriority", 1),
    ("Name", 17), ("NameSubtext", 17), ("Description", 17), ("AuraDescription", 17),
]
SPELL = {}
_offset = 0
for _name, _count in SPELL_FIELDS:
    SPELL[_name] = _offset
    _offset += _count


class Spells:
    def __init__(self, path):
        rows, self.string = load_dbc(path)
        self.rows = {row[0]: row for row in rows}

    def field(self, spell_id, name, index=0):
        row = self.rows.get(spell_id)
        return row[SPELL[name] + index] if row else 0

    def text(self, spell_id, name):
        row = self.rows.get(spell_id)
        if not row:
            return ""
        return self.string(row[SPELL[name] + LOCALE])

    # $m / $s: base points + 1 (die sides 1 in all set bonuses)
    def value(self, spell_id, letter, effect):
        i = effect - 1
        base = signed(self.field(spell_id, "EffectBasePoints", i))
        dice = signed(self.field(spell_id, "EffectDieSides", i))
        if letter in "msMS":
            low = base + 1
            high = base + max(dice, 1)
            return abs(low) if low == high else "%d - %d" % (abs(low), abs(high))
        if letter in "oO":
            return abs(base + 1)
        if letter in "tT":
            return self.field(spell_id, "EffectAuraPeriod", i) / 1000.0
        if letter in "aA":
            return self.field(spell_id, "EffectRadiusIndex", i)
        if letter in "xX":
            return self.field(spell_id, "EffectChainTargets", i)
        if letter in "eE":
            return round(as_float(self.field(spell_id, "EffectMultipleValue", i)), 2)
        if letter in "bB":
            return round(as_float(self.field(spell_id, "EffectPointsPerCombo", i)), 2)
        if letter in "qQ":
            return signed(self.field(spell_id, "EffectMiscValue", i))
        return None

    def single(self, spell_id, letter):
        if letter in "hH":
            return self.field(spell_id, "ProcChance")
        if letter in "uU":
            return self.field(spell_id, "CumulativeAura")
        if letter in "nN":
            return self.field(spell_id, "ProcCharges")
        return None


def number(value, decimals=None):
    if isinstance(value, str):
        return value
    if decimals is not None:
        return ("%." + str(decimals) + "f") % value
    if abs(value - round(value)) < 1e-6:
        return str(int(round(value)))
    return ("%.1f" % value).rstrip("0").rstrip(".")


TOKEN = re.compile(r"\$(\d+)?([a-zA-Z])(\d)?")


def resolve(spells, spell_id, text):
    """Resolves the description tokens of a set bonus spell."""

    def token_value(ref, letter, effect):
        target = int(ref) if ref else spell_id
        if effect:
            return spells.value(target, letter, int(effect))
        return spells.single(target, letter)

    # ${expression}.decimals
    def expression(match):
        expr = match.group(1)
        decimals = match.group(2)

        def sub(m):
            value = token_value(m.group(1), m.group(2), m.group(3))
            return str(value if isinstance(value, (int, float)) else 0)

        try:
            value = eval(TOKEN.sub(sub, expr), {"__builtins__": {}}, {})
        except Exception:
            return "?"
        return number(abs(value), int(decimals) if decimals else None)

    text = re.sub(r"\$\{([^}]*)\}(?:\.(\d))?", expression, text)

    # $/1000;S1 and $*2;s1
    def scaled(match):
        op, factor, ref, letter, effect = match.groups()
        value = token_value(ref, letter, effect)
        if not isinstance(value, (int, float)):
            return "?"
        value = value / float(factor) if op == "/" else value * float(factor)
        return number(value)

    text = re.sub(r"\$([/*])(\d+);(\d+)?([a-zA-Z])(\d)?", scaled, text)

    # $lsingular:plural; and $gmale:female; - take the first form
    text = re.sub(r"\$[lLgG]([^:;]*):[^;]*;", r"\1", text)

    def simple(match):
        value = token_value(match.group(1), match.group(2), match.group(3))
        if value is None:
            return ""
        return number(value)

    text = TOKEN.sub(simple, text)
    return text.replace("\r", "").strip()


def load_item_cache(path):
    items = {}
    pattern = re.compile(r'ITEM_CACHE\[(\d+)\] = \{ "((?:[^"\\]|\\.)*)", (\d+), (\d+), (\d+), (\d+), "([^"]*)"')
    for m in pattern.finditer(open(path, encoding="utf-8", errors="replace").read()):
        items[int(m.group(1))] = {"quality": int(m.group(3)), "class": int(m.group(4)),
                                  "subclass": int(m.group(5)), "invType": int(m.group(6))}
    return items


def load_items_ext(path):
    """entry -> {column: int} from the item_template export (header row required)."""
    import csv
    items = {}
    if not path or not os.path.exists(path):
        raise SystemExit("items_ext.csv (item_template export) is required, see the header of this script")
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as fh:
        sample = fh.readline()
        fh.seek(0)
        reader = csv.reader(fh, delimiter="\t" if "\t" in sample else ",")
        header = [h.strip().lower() for h in next(reader)]
        for parts in reader:
            if len(parts) < len(header):
                continue
            row = {}
            for key, value in zip(header, parts):
                try:
                    row[key] = int(float(value))
                except ValueError:
                    row[key] = 0
            items[row["entry"]] = row
    for column in ("itemlevel", "allowableclass", "itemset", "requiredlevel", "bonding", "statscount"):
        if items and column not in next(iter(items.values())):
            raise SystemExit("items_ext.csv has no column " + column + ", see the header of this script")
    return items


# classID (EJ class filter, druid = 11) from the AllowableClass bitmask (bit = classID - 1)
ALL_CLASSES_MASK = 0x5FF


def class_bits(*class_ids):
    mask = 0
    for class_id in class_ids:
        mask |= 1 << (class_id - 1)
    return mask


# items with AllowableClass -1: the classes whose primary armor it is (like retail's filter)
ITEM_CLASS_ARMOR = 4
ARMOR_CLASSES = {
    1: class_bits(5, 8, 9),       # cloth: priest, mage, warlock
    2: class_bits(4, 11),         # leather: rogue, druid
    3: class_bits(3, 7),          # mail: hunter, shaman
    4: class_bits(1, 2, 6),       # plate: warrior, paladin, death knight
}


def armor_class_mask(items, cache):
    """Class mask from the armor type most of the set's armor pieces have (0 = unknown)."""
    counts = {}
    for i in items:
        item = cache[i]
        if item["class"] == ITEM_CLASS_ARMOR and item["subclass"] in ARMOR_CLASSES:
            counts[item["subclass"]] = counts.get(item["subclass"], 0) + 1
    if not counts:
        return 0
    return ARMOR_CLASSES[max(counts, key=counts.get)]


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def set_expansion(set_id):
    if set_id < 552:
        return 0
    if set_id < 753:
        return 1
    return 2


def main():
    itemset_path = sys.argv[1] if len(sys.argv) > 1 else "ItemSet.dbc"
    spell_path = sys.argv[2] if len(sys.argv) > 2 else "Spell.dbc"
    cache_path = sys.argv[3] if len(sys.argv) > 3 else "ItemCache.lua"
    out_path = sys.argv[4] if len(sys.argv) > 4 else "EncounterJournalItemSets.lua"
    ext_path = sys.argv[5] if len(sys.argv) > 5 else "items_ext.csv"

    rows, string = load_dbc(itemset_path)
    spells = Spells(spell_path)
    cache = load_item_cache(cache_path)
    ext = load_items_ext(ext_path)

    members = {}
    for entry, item in ext.items():
        if item["itemset"] > 0:
            members.setdefault(item["itemset"], []).append(entry)

    sets = []
    stats = {"no items": 0, "not raid/dungeon": 0, "level": 0, "pieces": 0}
    for row in rows:
        set_id = row[0]
        name = string(row[1 + LOCALE])
        items = [i for i in members.get(set_id, []) if i in cache]
        if not name or not items:
            stats["no items"] += 1
            continue

        # raid / dungeon: bind on pickup, not PvP (resilience), with stats
        if any(ext[i]["bonding"] != BIND_ON_PICKUP or ext[i].get("resilience", 0) for i in items) \
                or not any(ext[i]["statscount"] > 0 for i in items):
            stats["not raid/dungeon"] += 1
            continue

        bonuses = []
        for spell_id, threshold in zip(row[35:43], row[43:51]):
            if spell_id and threshold:
                text = resolve(spells, spell_id, spells.text(spell_id, "Description"))
                if not text:
                    text = spells.text(spell_id, "Name")
                bonuses.append((threshold, text))
        bonuses.sort(key=lambda b: b[0])

        # one row per item level
        by_level = {}
        for i in items:
            by_level.setdefault(ext[i]["itemlevel"], []).append(i)
        for item_level, level_items in sorted(by_level.items(), reverse=True):
            if item_level < MIN_ITEM_LEVEL or max(ext[i]["requiredlevel"] for i in level_items) < MIN_REQUIRED_LEVEL:
                stats["level"] += 1
                continue
            if len(level_items) < MIN_PIECES:
                stats["pieces"] += 1
                continue
            level_items.sort(key=lambda i: (cache[i]["invType"], i))
            class_mask = 0
            for i in level_items:
                mask = ext[i]["allowableclass"]
                if mask > 0 and (mask & ALL_CLASSES_MASK) != ALL_CLASSES_MASK:
                    class_mask |= mask
            if class_mask == 0:
                class_mask = armor_class_mask(level_items, cache)
            sets.append({"id": set_id, "name": name, "items": level_items, "bonuses": bonuses,
                         "quality": max(cache[i]["quality"] for i in level_items),
                         "itemLevel": item_level, "classMask": class_mask,
                         "expansion": set_expansion(set_id)})

    # newest first inside an expansion: item level, then item IDs
    sets.sort(key=lambda s: (s["expansion"], -s["itemLevel"], -max(s["items"])))

    out = ["-- Generated by tools/ejsets.py from item_template + ItemSet.dbc + Spell.dbc. Do not edit by hand.",
           "-- EJ_ITEMSETS[i] = { id, name, expansion, quality, itemLevel (0 = unknown),",
           "--                    classMask (AllowableClass bits, 0 = every class), items, bonuses = { { count, text } } }",
           "", "EJ_ITEMSETS = {"]
    for s in sets:
        bonuses = ", ".join("{ %d, %s }" % (count, lua_string(text)) for count, text in s["bonuses"])
        out.append("\t{ id = %d, name = %s, expansion = %d, quality = %d, itemLevel = %d, classMask = %d, "
                   "items = { %s }, bonuses = { %s } },"
                   % (s["id"], lua_string(s["name"]), s["expansion"], s["quality"], s["itemLevel"],
                      s["classMask"], ", ".join(str(i) for i in s["items"]), bonuses))
    out.append("};")
    out.append("")
    open(out_path, "w", encoding="utf-8").write("\n".join(out))

    per_expansion = [sum(1 for s in sets if s["expansion"] == e) for e in range(3)]
    print("rows written %d (classic %d, tbc %d, wotlk %d)"
          % (len(sets), per_expansion[0], per_expansion[1], per_expansion[2]), file=sys.stderr)
    print("dropped: %s" % ", ".join("%s %d" % kv for kv in stats.items()), file=sys.stderr)


if __name__ == "__main__":
    main()
