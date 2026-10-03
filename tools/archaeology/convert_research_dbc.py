#!/usr/bin/env python3
"""
Археология: Research*.dbc (Cata 4.3.4, build 12340) -> SQL для сервера и Lua-данные для клиента.

  ResearchBranch  : ID, Name, ResearchFieldID, CurrencyID, Texture, KeystoneItemID
  ResearchProject : ID, Name, Description, Rarity(1 = редкий), BranchID, SpellID, NumSockets, Texture, RequiredFragments
  ResearchSite    : ID, MapID, QuestPOIBlobID, Name, AreaPOIIconEnum
  QuestPOIBlob    : ID, NumPoints, MapID, WorldMapAreaID                (если положить рядом)
  QuestPOIPoint   : ID, X, Y, QuestPOIBlobID                            (если положить рядом)

Запуск (в папке с .dbc): python3 convert_research_dbc.py
Результат: world_archaeology.sql (в world), ArchaeologyData.lua (в Interface\\FrameXML\\Archaeology).
Проекты с названием "Test:" и без ветки пропускаются.
"""
import os, struct

HERE = os.path.dirname(os.path.abspath(__file__))

def read_dbc(name, fmt):
    path = os.path.join(HERE, name + '.dbc')
    if not os.path.exists(path):
        return None
    data = open(path, 'rb').read()
    magic, nrec, nfields, recsize, strsize = struct.unpack('<4s4I', data[:20])
    strings = data[20 + nrec * recsize:]
    def string(offset):
        end = strings.index(b'\0', offset)
        return strings[offset:end].decode('utf-8', 'replace')
    rows = []
    for i in range(nrec):
        raw = data[20 + i * recsize:20 + (i + 1) * recsize]
        ints = struct.unpack('<%di' % nfields, raw[:nfields * 4])
        floats = struct.unpack('<%df' % nfields, raw[:nfields * 4])
        row = []
        for j, kind in enumerate(fmt):
            row.append(string(ints[j]) if kind == 's' else floats[j] if kind == 'f' else ints[j])
        rows.append(row)
    return rows

def sql(value):
    if isinstance(value, str):
        return "'" + value.replace('\\', '\\\\').replace("'", "\\'") + "'"
    if isinstance(value, float):
        return '%.3f' % value
    return str(value)

def lua(value):
    if isinstance(value, str):
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    return str(value)

branches = read_dbc('ResearchBranch', 'isiisi')
projects = read_dbc('ResearchProject', 'issiiiisi')
sites = read_dbc('ResearchSite', 'iiisi')
# ResearchSiteEntry::IsValid(): шаблоны и Вайш'ир
INVALID_SITES = {140, 142, 161, 471, 473, 475}
sites = [s for s in sites if s[0] not in INVALID_SITES]
blobs = read_dbc('QuestPOIBlob', 'iiii')
points = read_dbc('QuestPOIPoint', 'iiii')

branch_ids = {b[0] for b in branches}
# ветка 29 («Другие») - только тестовые проекты
branches = [b for b in branches if b[0] != 29]
branch_ids = {b[0] for b in branches}
projects = [p for p in projects if p[4] in branch_ids and not p[1].startswith('Test') and p[8] > 0]

out = ['-- world DB: археология, сгенерировано tools/archaeology/convert_research_dbc.py из Research*.dbc (4.3.4)']
out.append('''CREATE TABLE IF NOT EXISTS `archaeology_branch` (
  `id` INT UNSIGNED NOT NULL, `name` VARCHAR(100) NOT NULL DEFAULT '', `currency` INT UNSIGNED NOT NULL DEFAULT 0,
  `texture` VARCHAR(200) NOT NULL DEFAULT '', `keystone_item` INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `archaeology_project` (
  `id` INT UNSIGNED NOT NULL, `branch` INT UNSIGNED NOT NULL, `name` VARCHAR(200) NOT NULL DEFAULT '',
  `rare` TINYINT UNSIGNED NOT NULL DEFAULT 0, `fragments` INT UNSIGNED NOT NULL DEFAULT 0, `sockets` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `spell` INT UNSIGNED NOT NULL DEFAULT 0, `reward_item` INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `archaeology_site` (
  `id` INT UNSIGNED NOT NULL, `map` INT UNSIGNED NOT NULL, `name` VARCHAR(200) NOT NULL DEFAULT '',
  `branch` INT UNSIGNED NOT NULL DEFAULT 0, `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1, PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `archaeology_site_point` (
  `site` INT UNSIGNED NOT NULL, `idx` INT UNSIGNED NOT NULL, `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, PRIMARY KEY (`site`, `idx`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;''')
out.append('DELETE FROM `archaeology_branch`;')
for b in branches:
    out.append('INSERT INTO `archaeology_branch` VALUES (%s);' % ', '.join(sql(v) for v in (b[0], b[1], b[3], b[4], b[5])))
out.append('-- reward_item: предмет-артефакт (в 3.3.5 нет заклинаний Cata из поля spell) - заполнить после переноса предметов')
out.append('DELETE FROM `archaeology_project`;')
for p in projects:
    out.append('INSERT INTO `archaeology_project` VALUES (%s);' % ', '.join(sql(v) for v in (p[0], p[4], p[1], 1 if p[3] else 0, p[8], p[6], p[5], 0)))

# ветка места раскопок: окаменелости по названию, остальное - по континенту (сервер выбирает случайную ветку континента)
FOSSIL = 3
out.append('-- branch 0: случайная раса континента (archaeology.cpp), 3: окаменелости')
out.append('DELETE FROM `archaeology_site`;')
for s in sites:
    branch = FOSSIL if 'окаменел' in s[3].lower() or 'fossil' in s[3].lower() else 0
    enabled = 1 if s[1] in (0, 1, 530, 571) else 0   # континенты, которые есть в 3.3.5
    out.append('INSERT INTO `archaeology_site` VALUES (%s);' % ', '.join(sql(v) for v in (s[0], s[1], s[3], branch, enabled)))

if points is not None:
    by_blob = {}
    for p in points:
        by_blob.setdefault(p[3], []).append(p)
    out.append('DELETE FROM `archaeology_site_point`;')
    for s in sites:
        for idx, p in enumerate(by_blob.get(s[2], [])):
            out.append('INSERT INTO `archaeology_site_point` VALUES (%d, %d, %s, %s);' % (s[0], idx, p[1], p[2]))
else:
    out.append('-- QuestPOIPoint.dbc не найден: контуры мест раскопок (archaeology_site_point) не заполнены')

open(os.path.join(HERE, 'world_archaeology.sql'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')

# клиент: названия, описания, значки (в 3.3.5 клиент не читает Research*.dbc)
L = ['-- Археология: данные Research*.dbc (4.3.4), сгенерировано tools/archaeology/convert_research_dbc.py', 'ARCHAEOLOGY_BRANCHES = {']
for b in branches:
    L.append('\t[%d] = { name = %s, texture = %s, keystone = %d },' % (b[0], lua(b[1]), lua(b[4]), b[5]))
L.append('};')
L.append('ARCHAEOLOGY_PROJECTS = {')
for p in projects:
    L.append('\t[%d] = { branch = %d, name = %s, description = %s, rare = %s, fragments = %d, sockets = %d, texture = %s },' % (
        p[0], p[4], lua(p[1]), lua(p[2]), 'true' if p[3] else 'false', p[8], p[6], lua(p[7])))
L.append('};')
L.append('ARCHAEOLOGY_SITES = {')
for s in sites:
    L.append('\t[%d] = { map = %d, name = %s },' % (s[0], s[1], lua(s[3])))
L.append('};')
open(os.path.join(HERE, 'ArchaeologyData.lua'), 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print('branches %d, projects %d, sites %d, points %s' % (len(branches), len(projects), len(sites), 'yes' if points else 'no'))
