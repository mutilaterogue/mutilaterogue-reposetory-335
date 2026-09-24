--
-- EncounterJournalAPI.lua
--
-- Reimplements the 24 native EJ_* functions of the 4.3.4 client on top of the
-- exported EJ_DATA tables. Must load AFTER EncounterJournalData.lua.
--
-- Difficulty indices are context dependent, exactly as in the 4.3.4 FrameXML:
--   dungeons : 1 = normal, 2 = heroic
--   raids    : 1 = 10N, 2 = 25N, 3 = 10H, 4 = 25H, 5 = LFR
-- JournalEncounterItem.Difficulty is a bitmask, so the bit for a given index
-- is 2^(index-1) in both cases.
--

local band = bit.band;

local state = {
	instanceID = nil,
	encounterID = nil,
	difficulty = 1,
	classFilter = 0,
	search = nil,
	searchResults = {},
	lootCache = nil,     -- invalidated whenever encounter/difficulty/filter changes
	expansion = 2,       -- Wrath by default, matching the old hardcoded title
};

-- Raid vs dungeon and the artwork paths both come straight from the export now.
local isRaidInstance = {};
local raidOrder, dungeonOrder = {}, {};

local function BuildIndexes()
	for _, instanceID in ipairs(EJ_DATA.instanceOrder) do
		local inst = EJ_DATA.instances[instanceID];
		if ( inst and (inst.expansion or 0) == (state.expansion or 2) ) then
			isRaidInstance[instanceID] = inst.isRaid and true or false;
			if ( inst.isRaid ) then
				tinsert(raidOrder, instanceID);
			else
				tinsert(dungeonOrder, instanceID);
			end
		end
	end
end

BuildIndexes();

local function InstanceArt(inst)
	if ( not inst ) then
		return nil, nil, nil;
	end
	return inst.bg, inst.button, inst.lore;
end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function DifficultyMask()
	return 2 ^ (state.difficulty - 1);
end

local function LootMatchesDifficulty(entryDifficulty)
	if ( EJ_DATA.difficultyFiltering == false ) then
		return true;
	end
	if ( entryDifficulty == -1 or entryDifficulty == 0 ) then
		return true;
	end
	if ( entryDifficulty < 0 ) then
		entryDifficulty = band(entryDifficulty, 0xF);
		if ( entryDifficulty == 0 ) then
			return true;
		end
	end
	return band(entryDifficulty, DifficultyMask()) ~= 0;
end

local EJ_STYPE_ITEM      = 0;
local EJ_STYPE_ENCOUNTER = 1;
local EJ_STYPE_CREATURE  = 2;
local EJ_STYPE_SECTION   = 3;
local EJ_STYPE_INSTANCE  = 4;

local ITEM_CLASS_ARMOR = 4;
local ITEM_CLASS_WEAPON = 2;

-- Item.dbc InventoryType -> localized slot name
local INVENTORY_TYPE_NAMES = {
	[1]  = INVTYPE_HEAD,            [2]  = INVTYPE_NECK,
	[3]  = INVTYPE_SHOULDER,        [4]  = INVTYPE_BODY,
	[5]  = INVTYPE_CHEST,           [6]  = INVTYPE_WAIST,
	[7]  = INVTYPE_LEGS,            [8]  = INVTYPE_FEET,
	[9]  = INVTYPE_WRIST,           [10] = INVTYPE_HAND,
	[11] = INVTYPE_FINGER,          [12] = INVTYPE_TRINKET,
	[13] = INVTYPE_WEAPON,          [14] = INVTYPE_SHIELD,
	[15] = INVTYPE_RANGED,          [16] = INVTYPE_CLOAK,
	[17] = INVTYPE_2HWEAPON,        [18] = INVTYPE_BAG,
	[19] = INVTYPE_TABARD,          [20] = INVTYPE_ROBE,
	[21] = INVTYPE_WEAPONMAINHAND,  [22] = INVTYPE_WEAPONOFFHAND,
	[23] = INVTYPE_HOLDABLE,        [24] = INVTYPE_AMMO,
	[25] = INVTYPE_THROWN,          [26] = INVTYPE_RANGEDRIGHT,
	[28] = INVTYPE_RELIC,
};

local EJ_CLASS_TOKENS = {
	"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
	"DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
};

local ITEM_CLASS_RECIPE = 9;
local ITEM_CLASS_QUEST = 12;
local ITEM_QUALITY_UNCOMMON = 2;

-- Grey and white drops are vendor trash and crafting scraps. Quest items and
-- recipes are kept whatever their quality, since they are a reason to come here.
local function LootIsWorthShowing(itemID)
	local _, quality, class = GetItemInfoCached(itemID);

	-- unknown items are shown rather than hidden
	if ( not quality ) then
		return true;
	end

	if ( class == ITEM_CLASS_QUEST or class == ITEM_CLASS_RECIPE ) then
		return true;
	end

	return quality >= ITEM_QUALITY_UNCOMMON;
end

-- Who can use an item by its armor / weapon type - the same rules as the heirloom journal
-- (server heirloom_collection.cpp, GetClassMaskByType). Filter index = EJ_CLASS_TOKENS order.
local WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, DEATHKNIGHT, SHAMAN, MAGE, WARLOCK, DRUID = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

local function Classes(...)
	local set = {};
	for i = 1, select("#", ...) do
		set[select(i, ...)] = true;
	end
	return set;
end

local INVTYPE_CLOAK_ID = 16;

-- Item.dbc armor subclasses
local ARMOR_CLASSES = {
	[1] = Classes(PRIEST, MAGE, WARLOCK),                                   -- cloth
	[2] = Classes(HUNTER, ROGUE, SHAMAN, DRUID),                            -- leather
	[3] = Classes(WARRIOR, PALADIN, DEATHKNIGHT, HUNTER, SHAMAN),           -- mail
	[4] = Classes(WARRIOR, PALADIN, DEATHKNIGHT),                           -- plate
	[6] = Classes(WARRIOR, PALADIN, SHAMAN),                                -- shield
};

-- Item.dbc weapon subclasses
local WEAPON_CLASSES = {
	[15] = Classes(WARRIOR, ROGUE, HUNTER, SHAMAN, PRIEST, MAGE, WARLOCK, DRUID),        -- dagger
	[7]  = Classes(WARRIOR, PALADIN, ROGUE, HUNTER, MAGE, WARLOCK, DEATHKNIGHT),         -- 1h sword
	[8]  = Classes(WARRIOR, PALADIN, HUNTER, DEATHKNIGHT),                               -- 2h sword
	[0]  = Classes(WARRIOR, PALADIN, ROGUE, HUNTER, SHAMAN, DEATHKNIGHT),                -- 1h axe
	[1]  = Classes(WARRIOR, PALADIN, HUNTER, SHAMAN, DEATHKNIGHT),                       -- 2h axe
	[4]  = Classes(WARRIOR, PALADIN, ROGUE, SHAMAN, PRIEST, DRUID, DEATHKNIGHT),         -- 1h mace
	[5]  = Classes(WARRIOR, PALADIN, HUNTER, SHAMAN, DRUID, DEATHKNIGHT),                -- 2h mace
	[6]  = Classes(WARRIOR, PALADIN, HUNTER, DRUID, DEATHKNIGHT),                        -- polearm
	[13] = Classes(WARRIOR, ROGUE, HUNTER, SHAMAN),                                      -- fist
	[10] = Classes(SHAMAN, PRIEST, MAGE, WARLOCK, DRUID),                                -- staff
	[19] = Classes(PRIEST, MAGE, WARLOCK),                                               -- wand
	[2]  = Classes(WARRIOR, ROGUE, HUNTER),                                              -- bow
	[3]  = Classes(WARRIOR, ROGUE, HUNTER),                                              -- gun
	[18] = Classes(WARRIOR, ROGUE, HUNTER),                                              -- crossbow
	[16] = Classes(WARRIOR, ROGUE, HUNTER),                                              -- thrown
};

local function LootMatchesClass(itemID)
	if ( state.classFilter == 0 ) then
		return true;
	end

	local _, _, class, subclass, invType = GetItemInfoCached(itemID);

	-- items missing from the cache are shown rather than hidden
	if ( not class ) then
		return true;
	end

	local allowed;
	if ( class == ITEM_CLASS_ARMOR ) then
		-- cloaks, rings, necks, trinkets (misc armor) are for everyone
		if ( invType ~= INVTYPE_CLOAK_ID ) then
			allowed = ARMOR_CLASSES[subclass];
		end
	elseif ( class == ITEM_CLASS_WEAPON ) then
		allowed = WEAPON_CLASSES[subclass];
	end

	return not allowed or allowed[state.classFilter] == true;
end

function EJ_GetAvailableClasses()
	local out = {};
	for i, token in ipairs(EJ_CLASS_TOKENS) do
		tinsert(out, LOCALIZED_CLASS_NAMES_MALE[token] or token);
		tinsert(out, token);
	end
	return unpack(out);
end

local function InvalidateLoot()
	state.lootCache = nil;
end

-- Flattened, filtered loot list for the current encounter/difficulty/filter.
local function BuildLoot()
	if ( state.lootCache ) then
		return state.lootCache;
	end

	local list = {};

	local function collect(encounterID)
		local ids = EJ_DATA.itemsByEncounter[encounterID];
		if ( not ids ) then return; end
		for _, id in ipairs(ids) do
			local entry = EJ_DATA.items[id];
			if ( LootMatchesDifficulty(entry.difficulty)
			     and LootMatchesClass(entry.itemID)
			     and LootIsWorthShowing(entry.itemID) ) then
				tinsert(list, entry);
			end
		end
	end

	if ( state.encounterID ) then
		collect(state.encounterID);
	elseif ( state.instanceID ) then
		local encounters = EJ_DATA.encountersByInstance[state.instanceID];
		if ( encounters ) then
			for _, encID in ipairs(encounters) do
				collect(encID);
			end
		end
	end

	state.lootCache = list;
	return list;
end

--------------------------------------------------------------------------------
-- state setters
--------------------------------------------------------------------------------

function EJ_SelectInstance(instanceID)
	state.instanceID = instanceID;
	state.encounterID = nil;
	InvalidateLoot();
end

function EJ_SelectEncounter(encounterID)
	state.encounterID = encounterID;
	InvalidateLoot();
end

function EJ_SetDifficulty(difficulty)
	if ( state.difficulty == difficulty ) then
		return;
	end
	state.difficulty = difficulty;
	InvalidateLoot();
	if ( EncounterJournal and EncounterJournal:IsShown() ) then
		EncounterJournal:GetScript("OnEvent")(EncounterJournal, "EJ_DIFFICULTY_UPDATE", difficulty);
	end
end

function EJ_SetClassLootFilter(classID)
	state.classFilter = classID or 0;
	InvalidateLoot();
end

--------------------------------------------------------------------------------
-- state getters
--------------------------------------------------------------------------------

function EJ_GetCurrentInstance()
	return state.instanceID;
end

function EJ_GetDifficulty()
	return state.difficulty;
end

function EJ_GetClassFilter()
	if ( state.classFilter == 0 ) then
		return 0, nil;
	end

	local token = EJ_CLASS_TOKENS[state.classFilter];
	local name = token and (LOCALIZED_CLASS_NAMES_MALE[token] or token) or nil;

	return state.classFilter, name;
end

function EJ_InstanceIsRaid()
	if ( not state.instanceID ) then
		return false;
	end
	return isRaidInstance[state.instanceID] == true;
end

function EJ_IsValidInstanceDifficulty(difficulty)
	local inst = state.instanceID and EJ_DATA.instances[state.instanceID];
	if ( not inst ) then
		return false;
	end

	-- the list comes from MapDifficulty.dbc, so it matches what the map
	-- actually offers instead of being guessed from the loot
	local list = inst.difficulties;
	if ( list ) then
		for _, d in ipairs(list) do
			if ( d == difficulty ) then
				return true;
			end
		end
		return false;
	end

	if ( inst.isRaid ) then
		return difficulty >= 1 and difficulty <= 4;
	end
	return difficulty == 1 or difficulty == 2;
end

--------------------------------------------------------------------------------
-- instances
--------------------------------------------------------------------------------

-- EJ_GetInstanceInfo([instanceID])
--   -> name, description, bgImage, buttonImage, loreImage
function EJ_GetInstanceInfo(instanceID)
	instanceID = instanceID or state.instanceID;
	local inst = instanceID and EJ_DATA.instances[instanceID];
	if ( not inst ) then
		return nil;
	end
	local bg, button, lore = InstanceArt(inst);
	-- the sixth return is what the Show Map button reads; SetMapByID wants a
	-- WorldMapArea id, so an instance without one simply has no map
	return inst.name, inst.desc, bg, button, lore, inst.areaID or 0;
end

function EJ_GetInstanceByIndex(index, isRaid)
	local order = isRaid and raidOrder or dungeonOrder;
	local instanceID = order[index];
	if ( not instanceID ) then
		return nil;
	end
	local inst = EJ_DATA.instances[instanceID];
	local bg, button, lore = InstanceArt(inst);
	return instanceID, inst.name, inst.desc, bg, button, lore, inst.mapID,
	       format("|cff66bbff|Hjournal:0:%d:%d|h[%s]|h|r", instanceID, state.difficulty, inst.name);
end

--------------------------------------------------------------------------------
-- encounters
--------------------------------------------------------------------------------

-- EJ_GetEncounterInfo(encounterID)
--   -> name, description, journalEncounterID, rootSectionID, link
function EJ_GetEncounterInfo(encounterID)
	local enc = encounterID and EJ_DATA.encounters[encounterID];
	if ( not enc ) then
		return nil;
	end
	return enc.name, enc.desc, encounterID, enc.sectionID,
	       format("|cff66bbff|Hjournal:1:%d:%d|h[%s]|h|r", encounterID, state.difficulty, enc.name);
end

-- EJ_GetEncounterInfoByIndex(index [, instanceID])
--   -> name, description, encounterID, rootSectionID, link
function EJ_GetEncounterInfoByIndex(index, instanceID)
	instanceID = instanceID or state.instanceID;
	local list = instanceID and EJ_DATA.encountersByInstance[instanceID];
	local encounterID = list and list[index];
	if ( not encounterID ) then
		return nil;
	end
	local enc = EJ_DATA.encounters[encounterID];
	return enc.name, enc.desc, encounterID, enc.sectionID,
	       format("|cff66bbff|Hjournal:1:%d:%d|h[%s]|h|r", encounterID, state.difficulty, enc.name);
end

--------------------------------------------------------------------------------
-- creatures
--------------------------------------------------------------------------------

-- EJ_GetCreatureInfo(index [, encounterID])
--   -> id, name, description, displayInfo, iconImage
function EJ_GetCreatureInfo(index, encounterID)
	encounterID = encounterID or state.encounterID;
	local list = encounterID and EJ_DATA.creaturesByEncounter[encounterID];
	local id = list and list[index];
	if ( not id ) then
		return nil;
	end
	local cre = EJ_DATA.creatures[id];
	local icon = cre.icon;
	if ( icon == "" ) then
		icon = nil;
	end
	return id, cre.name, nil, cre.modelID, icon;
end

--------------------------------------------------------------------------------
-- sections
--------------------------------------------------------------------------------

-- EJ_GetSectionInfo(sectionID)
--   -> title, description, headerType, abilityIcon, displayInfo, siblingID,
--      nextSectionID, filteredByDifficulty, link, startsOpen,
--      flag1, flag2, flag3, flag4
function EJ_GetSectionInfo(sectionID)
	local sec = sectionID and EJ_DATA.sections[sectionID];
	if ( not sec ) then
		return nil;
	end

	local flags = sec.flags;
	local startsOpen = band(flags, 1) ~= 0;

	-- flag1..flag4 are the indices of the set bits, not booleans:
	-- EncounterJournal.lua builds ENCOUNTER_JOURNAL_SECTION_FLAG<n> from them
	local f = {};
	for bitIndex = 0, 15 do
		if ( band(flags, 2 ^ bitIndex) ~= 0 ) then
			tinsert(f, bitIndex);
			if ( #f == 4 ) then
				break;
			end
		end
	end

	return sec.name,                      -- title
	       sec.desc,                      -- description
	       sec.type,                      -- headerType
	       (sec.icon ~= "") and sec.icon or nil,   -- abilityIcon, from SpellIcon.dbc
	       (sec.modelID ~= 0) and sec.modelID or nil,
	       (sec.sibling ~= 0) and sec.sibling or nil,
	       (sec.sub ~= 0) and sec.sub or nil,
	       false,                         -- filteredByDifficulty
	       format("|cff66bbff|Hjournal:3:%d:%d|h[%s]|h|r", sectionID, state.difficulty, sec.name or ""),
	       startsOpen,
	       f[1], f[2], f[3], f[4];
end

-- EJ_GetSectionPath(sectionID) -> varargs, root first
function EJ_GetSectionPath(sectionID)
	local path = {};
	local id = sectionID;
	local guard = 0;

	while ( id and id ~= 0 and guard < 64 ) do
		tinsert(path, 1, id);
		local sec = EJ_DATA.sections[id];
		id = sec and sec.parent;
		guard = guard + 1;
	end

	return unpack(path);
end

--------------------------------------------------------------------------------
-- loot
--------------------------------------------------------------------------------

local ARMOR_SUBCLASS_NAMES = {
	[0] = "Разные", [1] = "Тканевые", [2] = "Кожаные",
	[3] = "Кольчужные", [4] = "Латные", [6] = "Щиты",
};

local function LootReturn(entry)
	if ( not entry ) then
		return nil;
	end

	local name, quality, class, subclass, invType, icon = GetItemInfoCached(entry.itemID);
	if ( not name ) then
		return nil;
	end

	local slot = INVENTORY_TYPE_NAMES[invType] or "";
	local armorType = "";
	if ( class == ITEM_CLASS_ARMOR or class == ITEM_CLASS_WEAPON ) then
		armorType = GetItemSubClassName(class, subclass, true);
	end

	return name, icon, slot, armorType,
	       entry.itemID, "item:"..entry.itemID, entry.encounterID, quality;
end

function EJ_GetNumLoot()
	return #BuildLoot();
end

-- EJ_GetLootInfoByIndex(index)
--   -> name, icon, slot, armorType, itemID, link, encounterID
function EJ_GetLootInfoByIndex(index)
	return LootReturn(BuildLoot()[index]);
end

-- EJ_GetLootInfo(itemID) -> same shape, looked up by item
function EJ_GetLootInfo(itemID)
	for _, entry in ipairs(BuildLoot()) do
		if ( entry.itemID == itemID ) then
			return LootReturn(entry);
		end
	end
	return nil;
end

--------------------------------------------------------------------------------
-- search
--------------------------------------------------------------------------------

function EJ_SetSearch(text)
	state.search = text;
	wipe(state.searchResults);

	if ( not text or strlen(text) < 1 ) then
		return;
	end

	local needle = strlower(text);

	local function matches(s)
		return s and strfind(strlower(s), needle, 1, true) ~= nil;
	end

	for _, instanceID in ipairs(EJ_DATA.instanceOrder) do
		local inst = EJ_DATA.instances[instanceID];
		if ( matches(inst.name) ) then
			tinsert(state.searchResults,
				{ id = instanceID, stype = EJ_STYPE_INSTANCE, difficulty = 0,
				  instanceID = instanceID, encounterID = nil });
		end
	end

	for encounterID, enc in pairs(EJ_DATA.encounters) do
		if ( matches(enc.name) ) then
			tinsert(state.searchResults,
				{ id = encounterID, stype = EJ_STYPE_ENCOUNTER, difficulty = 0,
				  instanceID = enc.instanceID, encounterID = encounterID });
		end
	end

	for sectionID, sec in pairs(EJ_DATA.sections) do
		if ( matches(sec.name) ) then
			local enc = EJ_DATA.encounters[sec.encounterID];
			tinsert(state.searchResults,
				{ id = sectionID, stype = EJ_STYPE_SECTION, difficulty = 0,
				  instanceID = enc and enc.instanceID or 0,
				  encounterID = sec.encounterID });
		end
	end

	for creatureID, cre in pairs(EJ_DATA.creatures) do
		if ( matches(cre.name) ) then
			local enc = EJ_DATA.encounters[cre.encounterID];
			tinsert(state.searchResults,
				{ id = creatureID, stype = EJ_STYPE_CREATURE, difficulty = 0,
				  instanceID = enc and enc.instanceID or 0,
				  encounterID = cre.encounterID });
		end
	end

	-- items; names come from the local cache, so this costs no server round trips
	local seenItem = {};
	for _, entry in pairs(EJ_DATA.items) do
		if ( not seenItem[entry.itemID] ) then
			seenItem[entry.itemID] = true;
			local iname = GetItemInfoCached(entry.itemID);
			if ( iname and matches(iname) ) then
				local enc = EJ_DATA.encounters[entry.encounterID];
				tinsert(state.searchResults,
					{ id = entry.itemID, stype = EJ_STYPE_ITEM, difficulty = 0,
					  instanceID = enc and enc.instanceID or 0,
					  encounterID = entry.encounterID });
			end
		end
	end
end

function EJ_ClearSearch()
	state.search = nil;
	wipe(state.searchResults);
end

function EJ_GetNumSearchResults()
	return #state.searchResults;
end

-- EJ_GetSearchResult(index) -> id, stype, difficulty, instanceID, encounterID
function EJ_GetSearchResult(index)
	local r = state.searchResults[index];
	if ( not r ) then
		return nil;
	end
	return r.id, r.stype, r.difficulty, r.instanceID, r.encounterID;
end

--------------------------------------------------------------------------------
-- links
--------------------------------------------------------------------------------

-- EJ_HandleLinkPath(jtype, id) -> instanceID, encounterID, sectionID
function EJ_HandleLinkPath(jtype, id)
	id = tonumber(id);
	if ( not id ) then
		return nil;
	end

	if ( jtype == 0 ) then               -- EJ_LINK_INSTANCE
		return id, nil, nil;
	elseif ( jtype == 1 ) then           -- EJ_LINK_ENCOUNTER
		local enc = EJ_DATA.encounters[id];
		if ( not enc ) then return nil; end
		return enc.instanceID, id, nil;
	elseif ( jtype == 3 ) then           -- EJ_LINK_SECTION
		local sec = EJ_DATA.sections[id];
		if ( not sec ) then return nil; end
		local enc = EJ_DATA.encounters[sec.encounterID];
		return enc and enc.instanceID or nil, sec.encounterID, id;
	end

	return nil;
end

--------------------------------------------------------------------------------
-- boss pins on the world map
--------------------------------------------------------------------------------

-- Resolves the instance whose dungeon map is currently open, by matching the
-- WorldMapArea id the client reports against the one stored per instance.
local function InstanceForCurrentMap()
	-- GetCurrentMapAreaID() is an index into the client's own map list and does
	-- not line up with WorldMapArea.ID, so match on the texture folder name
	-- that GetMapInfo() reports instead. Case differs between the two.
	local texture = GetMapInfo and GetMapInfo();
	if ( not texture or texture == "" ) then
		return nil;
	end

	texture = strlower(texture);

	for _, instanceID in ipairs(EJ_DATA.instanceOrder) do
		local inst = EJ_DATA.instances[instanceID];
		if ( inst and inst.mapTexture and inst.mapTexture ~= ""
		     and strlower(inst.mapTexture) == texture ) then
			return instanceID;
		end
	end

	return nil;
end

-- EJ_GetMapEncounter(index)
--   -> x, y, instanceID, name, description, encounterID, rootSectionID, link
--
-- The caller walks index upwards until this returns nil, so the floor filter
-- has to produce a dense list rather than skipping entries in place.
local mapPins = {};
local mapPinsKey = nil;

local function BuildMapPins()
	local texture = GetMapInfo and GetMapInfo();
	local level = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0;
	local key = (texture or "").."#"..level;

	if ( key == mapPinsKey ) then
		return;
	end

	mapPinsKey = key;
	wipe(mapPins);

	local instanceID = InstanceForCurrentMap();
	if ( not instanceID ) then
		return;
	end

	local list = EJ_DATA.encountersByInstance[instanceID];
	if ( not list ) then
		return;
	end

	for _, encounterID in ipairs(list) do
		local enc = EJ_DATA.encounters[encounterID];
		if ( enc and enc.x and not (enc.x == 0 and enc.y == 0) ) then
			tinsert(mapPins, { id = encounterID, instanceID = instanceID, enc = enc });
		end
	end
end

function EJ_GetMapEncounter(index)
	BuildMapPins();

	local pin = mapPins[index];
	if ( not pin ) then
		return nil;
	end

	local enc = pin.enc;
	return enc.x, enc.y, pin.instanceID, enc.name, enc.desc, pin.id, enc.sectionID,
	       format("|cff66bbff|Hjournal:1:%d:%d|h[%s]|h|r", pin.id, state.difficulty, enc.name);
end

--------------------------------------------------------------------------------
-- expansion filter
--------------------------------------------------------------------------------

function EJ_GetExpansion()
	return state.expansion or 2;
end

function EJ_SetExpansion(expansion)
	state.expansion = expansion;

	wipe(raidOrder);
	wipe(dungeonOrder);
	wipe(isRaidInstance);

	state.instanceID = nil;
	state.encounterID = nil;
	InvalidateLoot();

	BuildIndexes();
end