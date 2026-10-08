-- Retail EncounterJournal API on top of the 3.3.5 data (EncounterJournalData.lua) and its
-- 4.3.4-style API (EncounterJournalAPI.lua). Loads after both.
--
-- The data and EncounterJournalAPI.lua are not changed: this file keeps the original functions
-- in locals and replaces the globals with the retail signatures the retail journal UI expects.
--
--   tiers            = expansions present in the data (tier index = expansion + 1)
--   difficulties     = retail difficultyIDs (1 normal, 2 heroic, 3 10N, 4 25N, 5 10H, 6 25H)
--                      mapped to the 4.3.4 context indices of EncounterJournalAPI.lua
--   loot             = class filter (EJ_SetLootFilter) + retail slot filter (C_EncounterJournal.SetSlotFilter)
--   sections / loot  = C_EncounterJournal.* tables built from the multi-value returns
--   search           = the data search is instant: always "finished"

local band = bit.band;

local orig = {
	GetInstanceByIndex = EJ_GetInstanceByIndex,
	GetInstanceInfo = EJ_GetInstanceInfo,
	GetDifficulty = EJ_GetDifficulty,
	SetDifficulty = EJ_SetDifficulty,
	IsValidInstanceDifficulty = EJ_IsValidInstanceDifficulty,
	GetNumLoot = EJ_GetNumLoot,
	GetLootInfoByIndex = EJ_GetLootInfoByIndex,
	GetLootInfo = EJ_GetLootInfo,
	GetSectionInfo = EJ_GetSectionInfo,
	SetClassLootFilter = EJ_SetClassLootFilter,
	GetClassFilter = EJ_GetClassFilter,
	GetNumSearchResults = EJ_GetNumSearchResults,
	GetExpansion = EJ_GetExpansion,
	SetExpansion = EJ_SetExpansion,
};

EJ_Compat335 = orig;   -- for debugging

---------------------------------------------------------------------------
-- tiers = expansions
---------------------------------------------------------------------------
local tiers = {};   -- tier index -> expansion (0-based)

local function BuildTiers()
	local seen = {};
	for _, instanceID in ipairs(EJ_DATA.instanceOrder) do
		local inst = EJ_DATA.instances[instanceID];
		local expansion = inst and inst.expansion or 0;
		seen[expansion] = true;
	end
	for expansion = 0, 10 do
		if seen[expansion] then
			table.insert(tiers, expansion);
		end
	end
end
BuildTiers();

local function TierForExpansion(expansion)
	for index, value in ipairs(tiers) do
		if value == expansion then
			return index;
		end
	end
	return #tiers;
end

function EJ_GetNumTiers()
	return #tiers;
end

-- retail: name, link
function EJ_GetTierInfo(tierIndex)
	local expansion = tiers[tierIndex];
	if not expansion then
		return nil;
	end
	local name = _G["EXPANSION_NAME" .. expansion] or ("Tier " .. tierIndex);
	return name, ("|cff66bbff|Hjournal:4:%d:0|h[%s]|h|r"):format(tierIndex, name);
end

function EJ_GetCurrentTier()
	return TierForExpansion(orig.GetExpansion());
end

function EJ_SelectTier(tierIndex)
	local expansion = tiers[tierIndex];
	if expansion and expansion ~= orig.GetExpansion() then
		orig.SetExpansion(expansion);
	end
end

-- the journal opens on the newest tier, like retail
C_EncounterJournal = C_EncounterJournal or {};
function C_EncounterJournal.InitalizeSelectedTier()
	EJ_SelectTier(#tiers);
end

---------------------------------------------------------------------------
-- instances
---------------------------------------------------------------------------
-- retail: instanceID, name, description, bgImage, buttonImage1, loreImage, buttonImage2,
--         dungeonAreaMapID, link, shouldDisplayDifficulty, mapID
function EJ_GetInstanceByIndex(index, isRaid)
	local instanceID, name, description, bg, button, lore, mapID, link = orig.GetInstanceByIndex(index, isRaid);
	if not instanceID then
		return nil;
	end
	local inst = EJ_DATA.instances[instanceID];
	local shouldDisplayDifficulty = inst and inst.difficulties and #inst.difficulties > 1 or false;
	return instanceID, name, description, bg, button, lore, button, inst and inst.areaID or 0, link, shouldDisplayDifficulty, mapID;
end

-- retail: name, description, bgImage, buttonImage1, loreImage, buttonImage2, dungeonAreaMapID,
--         link, shouldDisplayDifficulty, mapID, covenantID, isRaid
function EJ_GetInstanceInfo(instanceID)
	instanceID = instanceID or EJ_GetCurrentInstance();
	local name, description, bg, button, lore, areaID = orig.GetInstanceInfo(instanceID);
	if not name then
		return nil;
	end
	local inst = EJ_DATA.instances[instanceID];
	local link = ("|cff66bbff|Hjournal:0:%d:%d|h[%s]|h|r"):format(instanceID, EJ_GetDifficulty() or 1, name);
	local shouldDisplayDifficulty = inst and inst.difficulties and #inst.difficulties > 1 or false;
	return name, description, bg, button, lore, button, areaID, link, shouldDisplayDifficulty, inst and inst.mapID, nil, inst and inst.isRaid or false;
end

function C_EncounterJournal.InstanceHasLoot(instanceID)
	return true;
end

function C_EncounterJournal.GetInstanceForGameMap(mapID)
	for instanceID, inst in pairs(EJ_DATA.instances) do
		if inst.mapID == mapID then
			return instanceID;
		end
	end
	return nil;
end

---------------------------------------------------------------------------
-- difficulties: retail difficultyID <-> 4.3.4 context index
---------------------------------------------------------------------------
local DUNGEON_TO_INDEX = { [1] = 1, [2] = 2 };
local RAID_TO_INDEX = { [3] = 1, [4] = 2, [5] = 3, [6] = 4 };
local INDEX_TO_DUNGEON = { [1] = 1, [2] = 2 };
local INDEX_TO_RAID = { [1] = 3, [2] = 4, [3] = 5, [4] = 6 };

local function ToIndex(difficultyID)
	if EJ_InstanceIsRaid() then
		return RAID_TO_INDEX[difficultyID];
	end
	return DUNGEON_TO_INDEX[difficultyID];
end

-- The difficulty is kept as the retail ID: EJ_GetDifficulty() must not guess it back from the
-- data index after switching between a raid and a dungeon.
local selectedDifficultyID;

function EJ_GetDifficulty()
	if selectedDifficultyID and ToIndex(selectedDifficultyID) then
		return selectedDifficultyID;
	end
	local index = orig.GetDifficulty();
	if EJ_InstanceIsRaid() then
		return INDEX_TO_RAID[index] or 3;
	end
	return INDEX_TO_DUNGEON[index] or 1;
end

function EJ_SetDifficulty(difficultyID)
	local index = ToIndex(difficultyID);
	if not index then
		return;
	end
	selectedDifficultyID = difficultyID;
	orig.SetDifficulty(index);
end

function EJ_IsValidInstanceDifficulty(difficultyID)
	local index = ToIndex(difficultyID);
	return index ~= nil and orig.IsValidInstanceDifficulty(index);
end

function C_EncounterJournal.GetBaseDifficultyID(difficultyID)
	return difficultyID;
end

function C_EncounterJournal.InstanceHasDifficultyID(difficultyID)
	return EJ_IsValidInstanceDifficulty(difficultyID);
end

---------------------------------------------------------------------------
-- sections
---------------------------------------------------------------------------
local sectionFlags = {};

function C_EncounterJournal.GetSectionInfo(sectionID)
	local title, description, headerType, abilityIcon, displayInfo, siblingID, firstChildID,
		filteredByDifficulty, link, startsOpen, f1, f2, f3, f4 = orig.GetSectionInfo(sectionID);
	if not title then
		return nil;
	end
	sectionFlags[sectionID] = { f1, f2, f3, f4 };
	return {
		spellID = 0,
		title = title,
		description = description,
		headerType = headerType or 0,
		abilityIcon = abilityIcon or 0,
		creatureDisplayID = displayInfo or 0,
		uiModelSceneID = 0,
		siblingSectionID = siblingID,
		firstChildSectionID = firstChildID,
		filteredByDifficulty = filteredByDifficulty or false,
		link = link or "",
		startsOpen = startsOpen or false,
	};
end

function C_EncounterJournal.GetSectionIconFlags(sectionID)
	if not sectionFlags[sectionID] then
		C_EncounterJournal.GetSectionInfo(sectionID);
	end
	local flags = sectionFlags[sectionID];
	if not flags or not flags[1] then
		return nil;
	end
	local result = {};
	for i = 1, 4 do
		if flags[i] then
			table.insert(result, flags[i]);
		end
	end
	return result;
end

---------------------------------------------------------------------------
-- loot: class filter + slot filter
---------------------------------------------------------------------------
-- retail class filter uses classIDs (druid = 11); EncounterJournalAPI.lua uses EJ_CLASS_TOKENS order (druid = 10)
local function ClassIDToFilterIndex(classID)
	if not classID or classID == 0 then
		return 0;
	end
	return classID == 11 and 10 or classID;
end

local function FilterIndexToClassID(index)
	if not index or index == 0 then
		return 0;
	end
	return index == 10 and 11 or index;
end

local lootClassID, lootSpecID = 0, 0;

function EJ_SetLootFilter(classID, specID)
	lootClassID, lootSpecID = classID or 0, specID or 0;
	orig.SetClassLootFilter(ClassIDToFilterIndex(lootClassID));
end

function EJ_GetLootFilter()
	return lootClassID, lootSpecID;
end

function EJ_ResetLootFilter()
	EJ_SetLootFilter(0, 0);
end

-- the retail journal keeps the 4.3.4 names too
EJ_SetClassLootFilter = function(index)
	EJ_SetLootFilter(FilterIndexToClassID(index), 0);
end

-- Enum.ItemSlotFilterType -> equip locations
local SLOT_FILTER_EQUIPLOCS = {
	[0] = { INVTYPE_HEAD = true },
	[1] = { INVTYPE_NECK = true },
	[2] = { INVTYPE_SHOULDER = true },
	[3] = { INVTYPE_CLOAK = true },
	[4] = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
	[5] = { INVTYPE_WRIST = true },
	[6] = { INVTYPE_HAND = true },
	[7] = { INVTYPE_WAIST = true },
	[8] = { INVTYPE_LEGS = true },
	[9] = { INVTYPE_FEET = true },
	[10] = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true },
	[11] = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
	[12] = { INVTYPE_FINGER = true },
	[13] = { INVTYPE_TRINKET = true },
};

local SLOT_FILTER_NO_FILTER = 15;
local SLOT_FILTER_OTHER = 14;
local slotFilter = SLOT_FILTER_NO_FILTER;

-- Item.dbc InventoryType -> Enum.ItemSlotFilterType; not listed = "other"
local INVTYPE_TO_SLOT_FILTER = {
	[1] = 0,                                  -- head
	[2] = 1,                                  -- neck
	[3] = 2,                                  -- shoulder
	[16] = 3,                                 -- back
	[5] = 4, [20] = 4,                        -- chest, robe
	[9] = 5,                                  -- wrist
	[10] = 6,                                 -- hand
	[6] = 7,                                  -- waist
	[7] = 8,                                  -- legs
	[8] = 9,                                  -- feet
	[13] = 10, [17] = 10, [21] = 10,          -- one-hand, two-hand, main hand
	[15] = 10, [25] = 10, [26] = 10,          -- ranged, thrown, wand / gun
	[14] = 11, [22] = 11, [23] = 11,          -- shield, off hand, held in off hand
	[11] = 12,                                -- finger
	[12] = 13,                                -- trinket
};

-- the slot comes from the local item cache (ItemCache.lua): GetItemInfo() only knows items
-- the client has already seen, so it let almost everything through
local function ItemSlotFilter(itemID)
	local _, _, _, _, invType = GetItemInfoCached(itemID);
	if invType then
		return INVTYPE_TO_SLOT_FILTER[invType] or SLOT_FILTER_OTHER;
	end
	local equipLoc = select(9, GetItemInfo(itemID));
	if not equipLoc then
		return nil;
	end
	for filter, locs in pairs(SLOT_FILTER_EQUIPLOCS) do
		if locs[equipLoc] then
			return filter;
		end
	end
	return SLOT_FILTER_OTHER;
end

local function MatchesSlotFilter(itemID)
	if slotFilter == SLOT_FILTER_NO_FILTER then
		return true;
	end
	local filter = ItemSlotFilter(itemID);
	if filter == nil then
		return true;   -- unknown item: show
	end
	return filter == slotFilter;
end

-- filtered index -> index in the class-filtered list of EncounterJournalAPI.lua
local lootIndexMap = {};

local function BuildLootIndexMap()
	wipe(lootIndexMap);
	for index = 1, orig.GetNumLoot() do
		local _, _, _, _, itemID = orig.GetLootInfoByIndex(index);
		if not itemID or MatchesSlotFilter(itemID) then
			table.insert(lootIndexMap, index);
		end
	end
end

function C_EncounterJournal.SetSlotFilter(filter)
	slotFilter = filter or SLOT_FILTER_NO_FILTER;
end

function C_EncounterJournal.GetSlotFilter()
	return slotFilter;
end

function C_EncounterJournal.ResetSlotFilter()
	slotFilter = SLOT_FILTER_NO_FILTER;
end

function EJ_GetNumLoot()
	BuildLootIndexMap();
	return #lootIndexMap;
end

-- retail (4.x-style global): name, icon, slot, armorType, itemID, link, encounterID
function EJ_GetLootInfoByIndex(index)
	local realIndex = lootIndexMap[index];
	if not realIndex then
		return nil;
	end
	return orig.GetLootInfoByIndex(realIndex);
end

local function LootTable(name, icon, slot, armorType, itemID, link, encounterID, quality)
	if not itemID then
		return nil;
	end
	return {
		itemID = itemID,
		encounterID = encounterID,
		name = name,
		itemQuality = quality and select(4, GetItemQualityColor(quality)) or nil,
		icon = icon,
		slot = slot,
		armorType = armorType,
		link = link,
	};
end

function C_EncounterJournal.GetLootInfoByIndex(index)
	return LootTable(EJ_GetLootInfoByIndex(index));
end

function C_EncounterJournal.GetLootInfo(itemID)
	return LootTable(orig.GetLootInfo(itemID));
end

function EJ_GetNumEncountersForLootByIndex()
	return 1;
end

function EJ_IsLootListOutOfDate()
	return false;
end

---------------------------------------------------------------------------
-- search: instant in the data
---------------------------------------------------------------------------
function EJ_IsSearchFinished()
	return true;
end

function EJ_GetSearchProgress()
	return 1;
end

function EJ_GetSearchSize()
	return orig.GetNumSearchResults();
end

function EJ_EndSearch()
end

---------------------------------------------------------------------------
-- the rest of C_EncounterJournal / EJ_* the retail journal calls
---------------------------------------------------------------------------
function C_EncounterJournal.OnOpen() end
function C_EncounterJournal.OnClose() end
function C_EncounterJournal.SetTab() end
function C_EncounterJournal.IsEncounterComplete() return false; end
function C_EncounterJournal.SetPreviewMythicPlusLevel() end
function C_EncounterJournal.SetPreviewPvpTier() end
function C_EncounterJournal.GetEncountersOnMap() return {}; end
function C_EncounterJournal.GetDungeonEntrancesForMap() return {}; end

function C_EncounterJournal.GetEncounterJournalLink(linkType, id, displayText, difficultyID)
	return ("|cff66bbff|Hjournal:%d:%d:%d|h[%s]|h|r"):format(linkType, id, difficultyID or 0, displayText or "");
end

function EJ_GetContentTuningID()
	return nil;
end

---------------------------------------------------------------------------
-- boss pins on dungeon maps: only the bosses of the shown floor
---------------------------------------------------------------------------
-- EncounterJournalAPI.lua returns every boss of the instance on every floor. The data knows
-- the floor of each boss (tools ejfloors.py: DungeonMap.dbc floorIndex = GetCurrentMapDungeonLevel()).
-- A boss without a floor in a multi-floor instance is skipped: its x / y are not on any of the
-- floor maps (gunship battle, bosses whose spawn was not found).
local mapPins, mapPinsKey = {}, nil;

local function InstanceForMapTexture(texture)
	texture = strlower(texture);
	for _, instanceID in ipairs(EJ_DATA.instanceOrder) do
		local inst = EJ_DATA.instances[instanceID];
		if inst and inst.mapTexture and inst.mapTexture ~= "" and strlower(inst.mapTexture) == texture then
			return instanceID;
		end
	end
	return nil;
end

local function BuildMapPins()
	local texture = GetMapInfo and GetMapInfo();
	local level = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0;
	local key = (texture or "") .. "#" .. level;
	if key == mapPinsKey then
		return;
	end
	mapPinsKey = key;
	wipe(mapPins);

	local instanceID = texture and texture ~= "" and InstanceForMapTexture(texture);
	local list = instanceID and EJ_DATA.encountersByInstance[instanceID];
	if not list then
		return;
	end

	local multiFloor = false;
	for _, encounterID in ipairs(list) do
		local enc = EJ_DATA.encounters[encounterID];
		if enc and (enc.floor or 0) > 0 then
			multiFloor = true;
			break;
		end
	end

	for _, encounterID in ipairs(list) do
		local enc = EJ_DATA.encounters[encounterID];
		local floor = enc and enc.floor or 0;
		local onFloor;
		if multiFloor then
			onFloor = floor > 0 and (floor == level or (level == 0 and floor == 1));
		else
			onFloor = true;
		end
		if enc and onFloor and enc.x and not (enc.x == 0 and enc.y == 0) then
			table.insert(mapPins, { id = encounterID, instanceID = instanceID, enc = enc });
		end
	end
end

-- x, y, instanceID, name, description, encounterID, rootSectionID, link
function EJ_GetMapEncounter(index)
	BuildMapPins();
	local pin = mapPins[index];
	if not pin then
		return nil;
	end
	local enc = pin.enc;
	return enc.x, enc.y, pin.instanceID, enc.name, enc.desc, pin.id, enc.sectionID,
		("|cff66bbff|Hjournal:1:%d:%d|h[%s]|h|r"):format(pin.id, EJ_GetDifficulty() or 1, enc.name);
end
