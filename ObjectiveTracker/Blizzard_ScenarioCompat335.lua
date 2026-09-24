-- C_Scenario / C_ScenarioInfo for 3.3.5 (ScenarioInfoDocumentation), dungeon display only.
--
-- 3.3.5 has no scenarios. Inside a dungeon the retail tracker shows it as a scenario of the type
-- LE_SCENARIO_TYPE_USE_DUNGEON_DISPLAY: one stage, one criteria per boss ("<boss> побежден 0/1").
-- The bosses come from the encounter journal data (EJ_DATA, EncounterJournalData.lua); a boss
-- counts as killed when one of its creatures dies (combat log UNIT_DIED).
--
-- Events: 3.3.5 cannot fire SCENARIO_UPDATE / SCENARIO_CRITERIA_UPDATE, so listeners register with
-- ScenarioCompat_RegisterCallback(func) and get (event, ...) with the same names.

LE_SCENARIO_TYPE_SCENARIO = LE_SCENARIO_TYPE_SCENARIO or 0;
LE_SCENARIO_TYPE_CHALLENGE_MODE = LE_SCENARIO_TYPE_CHALLENGE_MODE or 1;
LE_SCENARIO_TYPE_PROVING_GROUNDS = LE_SCENARIO_TYPE_PROVING_GROUNDS or 2;
LE_SCENARIO_TYPE_USE_DUNGEON_DISPLAY = LE_SCENARIO_TYPE_USE_DUNGEON_DISPLAY or 3;
SCENARIO_FLAG_SUPRESS_STAGE_TEXT = SCENARIO_FLAG_SUPRESS_STAGE_TEXT or 0x00000002;

TRACKER_HEADER_DUNGEON = TRACKER_HEADER_DUNGEON or "Подземелье";
TRACKER_HEADER_RAID = TRACKER_HEADER_RAID or "Рейд";
DUNGEON_COMPLETED = DUNGEON_COMPLETED or "Подземелье пройдено!";
SCENARIO_BOSS_DEFEATED = SCENARIO_BOSS_DEFEATED or "%s: побежден";

-- retail shows the dungeon display in dungeons only; true adds raids
local SHOW_IN_RAIDS = false;

C_Scenario = C_Scenario or {};
C_ScenarioInfo = C_ScenarioInfo or {};

local callbacks = {};

-- strlower does not touch Cyrillic (UTF-8): "Алого Ордена" in the journal, "Алого ордена" in the game
local function ULower(text)
	text = strlower(text or "");
	text = text:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32); end);
	text = text:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32); end);
	text = text:gsub("\208\129", "\209\145");
	return text;
end

function ScenarioCompat_RegisterCallback(func)
	table.insert(callbacks, func);
end

local function Fire(event, ...)
	for _, func in ipairs(callbacks) do
		func(event, ...);
	end
end

---------------------------------------------------------------------------
-- current instance -> journal instance
---------------------------------------------------------------------------
local current;			-- { instanceID, name, isRaid, bosses = { {encounterID, name, names = {}} }, key }
local killedByRun = {};	-- [run key] = { [encounterID] = true }, kept for the session (re-entering the run)

local function FindJournalInstance(zoneName, isRaid)
	if not EJ_DATA then
		return nil;
	end
	local lowerName = ULower(zoneName);
	if lowerName == "" then
		return nil;
	end
	-- exact name first, then wings ("Монастырь Алого ордена - Кладбище"): the sub zone decides
	local prefixMatches = {};
	for _, instanceID in ipairs(EJ_DATA.instanceOrder) do
		local inst = EJ_DATA.instances[instanceID];
		if inst and (inst.isRaid and true or false) == isRaid then
			local name = ULower(inst.name);
			if name == lowerName then
				return instanceID;
			end
			if strfind(name, lowerName, 1, true) == 1 then
				table.insert(prefixMatches, instanceID);
			end
		end
	end
	if #prefixMatches > 0 then
		local subZone = ULower(GetSubZoneText());
		for _, instanceID in ipairs(prefixMatches) do
			if subZone ~= "" and strfind(ULower(EJ_DATA.instances[instanceID].name), subZone, 1, true) then
				return instanceID;
			end
		end
		return prefixMatches[1];
	end

	-- names differ between Map.dbc and the journal: the dungeon map of the zone
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then
		SetMapToCurrentZone();
		local texture = strlower(GetMapInfo() or "");
		if texture ~= "" then
			for _, instanceID in ipairs(EJ_DATA.instanceOrder) do
				local inst = EJ_DATA.instances[instanceID];
				if inst and inst.mapTexture and strlower(inst.mapTexture) == texture then
					return instanceID;
				end
			end
		end
	end
	return nil;
end

local function BuildBosses(instanceID)
	local bosses = {};
	for _, encounterID in ipairs(EJ_DATA.encountersByInstance[instanceID] or {}) do
		local enc = EJ_DATA.encounters[encounterID];
		if enc then
			local boss = { encounterID = encounterID, name = enc.name, names = {} };
			boss.names[ULower(enc.name)] = true;
			for _, creatureID in ipairs(EJ_DATA.creaturesByEncounter[encounterID] or {}) do
				local creature = EJ_DATA.creatures[creatureID];
				if creature and creature.name then
					boss.names[ULower(creature.name)] = true;
				end
			end
			table.insert(bosses, boss);
		end
	end
	return bosses;
end

local function UpdateCurrentInstance()
	local old = current;
	current = nil;

	local inInstance, instanceType = IsInInstance();
	if inInstance and (instanceType == "party" or (SHOW_IN_RAIDS and instanceType == "raid")) then
		local name, _, difficultyIndex = GetInstanceInfo();
		local isRaid = instanceType == "raid";
		local instanceID = FindJournalInstance(name, isRaid) or FindJournalInstance(GetRealZoneText(), isRaid);
		if instanceID then
			local key = instanceID .. ":" .. (difficultyIndex or 1);
			current = {
				instanceID = instanceID,
				name = EJ_DATA.instances[instanceID].name,
				description = EJ_DATA.instances[instanceID].desc,
				isRaid = isRaid,
				bosses = BuildBosses(instanceID),
				key = key,
			};
			killedByRun[key] = killedByRun[key] or {};
		end
	end

	local changed = (old and old.key) ~= (current and current.key);
	if changed then
		Fire("SCENARIO_UPDATE", true);
	end
end

local function NumKilled()
	if not current then
		return 0;
	end
	local killed, count = killedByRun[current.key], 0;
	for _, boss in ipairs(current.bosses) do
		if killed[boss.encounterID] then
			count = count + 1;
		end
	end
	return count;
end

local function OnUnitDied(destName)
	if not current or not destName then
		return;
	end
	local lowerName = ULower(destName);
	local killed = killedByRun[current.key];
	for index, boss in ipairs(current.bosses) do
		if not killed[boss.encounterID] and boss.names[lowerName] then
			killed[boss.encounterID] = true;
			Fire("SCENARIO_CRITERIA_UPDATE", boss.encounterID);
			if NumKilled() == #current.bosses then
				Fire("SCENARIO_UPDATE", true);
				Fire("SCENARIO_COMPLETED");
			end
			return;
		end
	end
end

local watcher = CreateFrame("Frame");
watcher:RegisterEvent("PLAYER_ENTERING_WORLD");
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA");
watcher:RegisterEvent("ZONE_CHANGED");
watcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
watcher:SetScript("OnEvent", function(self, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local _, subEvent, _, _, _, _, destName = ...;
		if subEvent == "UNIT_DIED" then
			OnUnitDied(destName);
		end
	else
		UpdateCurrentInstance();
	end
end);

---------------------------------------------------------------------------
-- C_Scenario (retail multiple returns)
---------------------------------------------------------------------------
-- scenarioName, currentStage, numStages, flags, hasBonusStep, isBonusStepComplete, completed,
-- xp, money, scenarioType, areaName, textureKit, scenarioID
function C_Scenario.GetInfo()
	if not current then
		return nil, 0, 0, 0, false, false, false, 0, 0, nil, nil, nil, nil;
	end
	local completed = NumKilled() == #current.bosses;
	local currentStage = completed and 2 or 1;
	return current.name, currentStage, 1, SCENARIO_FLAG_SUPRESS_STAGE_TEXT, false, false, completed,
		0, 0, LE_SCENARIO_TYPE_USE_DUNGEON_DISPLAY, current.name, "evergreen-scenario", current.instanceID;
end

-- stageName, stageDescription, numCriteria, stepFailed, isBonusStep, isForCurrentStepOnly,
-- shouldShowBonusObjective, numSpells, spellInfo, weightedProgress, rewardQuestID, widgetSetID
function C_Scenario.GetStepInfo()
	if not current then
		return nil, nil, 0;
	end
	return current.name, current.description or "", #current.bosses, false, false, false, false,
		0, nil, nil, 0, nil;
end

function C_Scenario.IsInScenario()
	return current ~= nil;
end

function C_Scenario.ShouldShowCriteria()
	return true;
end

function C_Scenario.IsRaid()
	return current and current.isRaid or false;
end

---------------------------------------------------------------------------
-- C_ScenarioInfo (tables)
---------------------------------------------------------------------------
function C_ScenarioInfo.GetScenarioInfo()
	if not current then
		return nil;
	end
	local name, currentStage, numStages, flags, _, _, completed, xp, money, scenarioType, area, textureKit, scenarioID = C_Scenario.GetInfo();
	return {
		name = name, currentStage = currentStage, numStages = numStages, flags = flags,
		isComplete = completed, xp = xp, money = money, type = scenarioType, area = area,
		uiTextureKit = textureKit, scenarioID = scenarioID,
	};
end

function C_ScenarioInfo.GetScenarioStepInfo()
	if not current then
		return nil;
	end
	return {
		title = current.name, description = current.description or "", numCriteria = #current.bosses,
		stepFailed = false, isBonusStep = false, isForCurrentStepOnly = false,
		shouldShowBonusObjective = false, spells = {}, weightedProgress = nil,
		rewardQuestID = 0, widgetSetID = nil, stepID = current.instanceID,
	};
end

function C_ScenarioInfo.GetCriteriaInfo(criteriaIndex)
	local boss = current and current.bosses[criteriaIndex];
	if not boss then
		return nil;
	end
	local completed = killedByRun[current.key][boss.encounterID] == true;
	return {
		description = SCENARIO_BOSS_DEFEATED:format(boss.name),
		criteriaType = 0,
		completed = completed,
		quantity = completed and 1 or 0,
		totalQuantity = 1,
		flags = 0,
		assetID = boss.encounterID,
		criteriaID = boss.encounterID,
		duration = 0,
		elapsed = 0,
		failed = false,
		isWeightedProgress = false,
		isFormatted = false,
		quantityString = completed and "1" or "0",
	};
end

function C_ScenarioInfo.GetDisplayInfo()
	return nil;
end

function C_ScenarioInfo.IsTieredEntranceScenario()
	return false;
end
