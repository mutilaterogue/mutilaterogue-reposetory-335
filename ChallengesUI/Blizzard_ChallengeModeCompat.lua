-- Mythic+ data for 3.3.5 (server/mythic_plus.cpp over AddonComm) and the retail API on top of it:
-- C_ChallengeMode / C_MythicPlus (subset), keystone tooltip, start countdown.
-- Listeners: MythicPlus_RegisterCallback(func) -> func(event, ...), events:
--   "AFFIXES", "KEY", "RATING", "RUN", "BOSSES", "COMPLETE", "FONT_OPEN", "FONT_CLOSE", "SLOTTED", "RESULT"

KEYSTONE_ITEM_ID = 138019;

MythicPlus = {
	affixes = {},		-- [id] = { name, icon, description }
	week = {},			-- this week's affix ids
	key = nil,			-- { mapID, level, name }
	rating = 0,
	best = {},			-- [mapID] = { level, timeMs, timed, score }
	run = nil,			-- see ParseRun
	bosses = {},		-- server boss names of the current instance
	forcesName = "",
};

local callbacks = {};

function MythicPlus_RegisterCallback(func)
	table.insert(callbacks, func);
end

local function Fire(event, ...)
	for _, func in ipairs(callbacks) do
		func(event, ...);
	end
end

local function Send(...)
	if Comm_Send then
		Comm_Send(...);
	end
end

function MythicPlus_Send(...)
	Send(...);
end

local function SplitIds(text)
	local ids = {};
	for id in string.gmatch(text or "", "%d+") do
		local n = tonumber(id);
		if n and n > 0 then
			table.insert(ids, n);
		end
	end
	return ids;
end

-- affixes of a keystone level: 1 from +2, 2 from +4, 3 from +7 (same thresholds as the server)
function MythicPlus_GetAffixesForLevel(level)
	local result = {};
	local thresholds = { 2, 4, 7 };
	for i, id in ipairs(MythicPlus.week) do
		if level >= thresholds[i] then
			table.insert(result, id);
		end
	end
	-- seasonal affix (MPLUS_SEASON)
	local season = MythicPlus.season;
	if season and season.affix > 0 and level >= season.affixLevel and not tContains(result, season.affix) then
		table.insert(result, season.affix);
	end
	return result;
end

function MythicPlus_FormatTime(seconds, withHours)
	seconds = math.max(0, math.floor(seconds or 0));
	local h = math.floor(seconds / 3600);
	local m = math.floor(seconds % 3600 / 60);
	local s = seconds % 60;
	if h > 0 or withHours then
		return string.format("%d:%02d:%02d", h, m, s);
	end
	return string.format("%d:%02d", m, s);
end

---------------------------------------------------------------------------
-- run state
---------------------------------------------------------------------------
MYTHIC_RUN_NONE = 0;
MYTHIC_RUN_COUNTDOWN = 1;
MYTHIC_RUN_ACTIVE = 2;
MYTHIC_RUN_DONE_TIMED = 3;
MYTHIC_RUN_DONE_LATE = 4;

-- elapsed ms of the timer (ticks locally between server syncs)
function MythicPlus_GetElapsedMs()
	local run = MythicPlus.run;
	if not run then
		return 0;
	end
	if run.state == MYTHIC_RUN_ACTIVE then
		return run.timeMs + (GetTime() - run.receivedAt) * 1000;
	end
	if run.state == MYTHIC_RUN_COUNTDOWN then
		return 0;
	end
	return run.timeMs;
end

function MythicPlus_GetCountdownMs()
	local run = MythicPlus.run;
	if not run or run.state ~= MYTHIC_RUN_COUNTDOWN then
		return 0;
	end
	return math.max(0, run.timeMs - (GetTime() - run.receivedAt) * 1000);
end

function MythicPlus_IsKeystoneRun()
	local run = MythicPlus.run;
	return run ~= nil and run.mapID ~= 0 and run.level > 0 and run.state ~= MYTHIC_RUN_NONE;
end

function MythicPlus_IsInMythicInstance()
	return MythicPlus.run ~= nil and MythicPlus.run.mapID ~= 0;
end

---------------------------------------------------------------------------
-- comm
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register("MPLUS_AFFIX", function(id, name, icon, description)
		id = tonumber(id);
		if id then
			MythicPlus.affixes[id] = { name = name or "", icon = icon or "", description = description or "" };
			Fire("AFFIXES");
		end
	end);

	Comm_Register("MPLUS_SEASON", function(id, name, affix, affixLevel)
		MythicPlus.season = { id = tonumber(id) or 0, name = name or "", affix = tonumber(affix) or 0, affixLevel = tonumber(affixLevel) or 0 };
		Fire("SEASON");
	end);

	Comm_Register("MPLUS_WEEK", function(list)
		MythicPlus.week = SplitIds(list);
		Fire("AFFIXES");
	end);

	Comm_Register("MPLUS_KEY", function(mapID, level, name, timeLimit)
		mapID = tonumber(mapID) or 0;
		if mapID == 0 then
			MythicPlus.key = nil;
		else
			MythicPlus.key = { mapID = mapID, level = tonumber(level) or 0, name = name or "", timeLimit = tonumber(timeLimit) or 0 };
		end
		Fire("KEY");
	end);

	Comm_Register("MPLUS_RATING", function(rating, list)
		MythicPlus.rating = tonumber(rating) or 0;
		wipe(MythicPlus.best);
		for entry in string.gmatch(list or "", "[^,]+") do
			local mapID, level, timeMs, timed, score = strsplit(";", entry);
			mapID = tonumber(mapID);
			if mapID then
				MythicPlus.best[mapID] = { level = tonumber(level) or 0, timeMs = tonumber(timeMs) or 0, timed = timed == "1", score = tonumber(score) or 0 };
			end
		end
		Fire("RATING");
	end);

	Comm_Register("MPLUS_RUN", function(state, mapID, level, affixes, timeLimit, timeMs, deaths, penalty, forces, forcesMax, bossMask, bossCount)
		local old = MythicPlus.run;
		local run = {
			state = tonumber(state) or 0,
			mapID = tonumber(mapID) or 0,
			level = tonumber(level) or 0,
			affixes = SplitIds(affixes),
			timeLimit = tonumber(timeLimit) or 0,
			timeMs = tonumber(timeMs) or 0,
			deaths = tonumber(deaths) or 0,
			penalty = tonumber(penalty) or 5,
			forces = tonumber(forces) or 0,
			forcesMax = tonumber(forcesMax) or 0,
			bossMask = tonumber(bossMask) or 0,
			bossCount = tonumber(bossCount) or 0,
			receivedAt = GetTime(),
		};
		if run.mapID == 0 then
			MythicPlus.run = nil;
			wipe(MythicPlus.bosses);
		else
			MythicPlus.run = run;
		end
		local newStage = not old or (old.state ~= run.state) or (old.mapID ~= run.mapID);
		Fire("RUN", newStage, old);
	end);

	Comm_Register("MPLUS_BOSSES", function(list)
		wipe(MythicPlus.bosses);
		if list and list ~= "-" then
			for name in string.gmatch(list, "[^#]+") do
				table.insert(MythicPlus.bosses, name);
			end
		end
		Fire("BOSSES");
	end);

	Comm_Register("MPLUS_FORCES_NAME", function(name)
		MythicPlus.forcesName = name or "";
	end);

	-- retail C_ChallengeMode.GetChallengeCompletionInfo
	Comm_Register("MPLUS_COMPLETE", function(timed, upgrade, timeMs, level, newLevel, score, oldRating, newRating, mapID, name)
		MythicPlus.completion = {
			onTime = timed == "1", keystoneUpgradeLevels = tonumber(upgrade) or 0, time = tonumber(timeMs) or 0,
			level = tonumber(level) or 0, newLevel = tonumber(newLevel) or 0, score = tonumber(score) or 0,
			oldOverallDungeonScore = tonumber(oldRating) or 0, newOverallDungeonScore = tonumber(newRating) or 0,
			mapChallengeModeID = tonumber(mapID) or 0, name = name or "",
		};
		Fire("COMPLETE", MythicPlus.completion);
	end);

	-- dungeons of the season: id;name;timeLimit,...
	Comm_Register("MPLUS_MAPS", function(list)
		MythicPlus.maps = {};
		MythicPlus.mapInfo = {};
		for entry in string.gmatch(list or "", "[^,]+") do
			local id, name, limit = strsplit(";", entry);
			id = tonumber(id);
			if id then
				table.insert(MythicPlus.maps, id);
				MythicPlus.mapInfo[id] = { name = name or "", timeLimit = tonumber(limit) or 0 };
			end
		end
		Fire("MAPS");
	end);

	-- Great Vault: runs this week, their levels, last week's options slot;item;level;claimed
	-- + raid difficulties of this week's bosses, world levels; option slots 1..3 dungeons, 4..6 raid, 7..9 world
	Comm_Register("MPLUS_VAULT", function(runs, levels, options, raid, world)
		local vault = { runs = tonumber(runs) or 0, levels = SplitIds(levels), options = {}, claimed = false,
			raid = SplitIds(raid), world = SplitIds(world) };
		for entry in string.gmatch(options or "", "[^,]+") do
			local slot, item, level, claimed = strsplit(";", entry);
			slot = tonumber(slot);
			if slot then
				vault.options[slot] = { itemID = tonumber(item) or 0, level = tonumber(level) or 0, claimed = claimed == "1" };
				if claimed == "1" then
					vault.claimed = true;
				end
			end
		end
		MythicPlus.vault = vault;
		Fire("VAULT");
	end);

	Comm_Register("MPLUS_VAULT_OPEN", function()
		Fire("VAULT_OPEN");
	end);

	Comm_Register("MPLUS_FONT_OPEN", function(mapID)
		Fire("FONT_OPEN", tonumber(mapID) or 0);
	end);

	Comm_Register("MPLUS_FONT_CLOSE", function()
		Fire("FONT_CLOSE");
	end);

	Comm_Register("MPLUS_SLOTTED", function(slotted)
		Fire("SLOTTED", slotted == "1");
	end);

	Comm_Register("MPLUS_RESULT", function(message)
		if message and message ~= "" then
			UIErrorsFrame:AddMessage(message, 1, 0.1, 0.1);
		end
		Fire("RESULT", message);
	end);
end

local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD");
	Send("MPLUS_GET");
end);

---------------------------------------------------------------------------
-- C_ChallengeMode / C_MythicPlus (retail names, subset)
---------------------------------------------------------------------------
C_ChallengeMode = C_ChallengeMode or {};
C_MythicPlus = C_MythicPlus or {};

-- name, description, filedataid (icon path here)
function C_ChallengeMode.GetAffixInfo(affixID)
	local affix = MythicPlus.affixes[affixID];
	if not affix then
		return nil;
	end
	return affix.name, affix.description, affix.icon;
end

-- activeKeystoneLevel, activeAffixIDs, wasActiveKeystoneCharged
function C_ChallengeMode.GetActiveKeystoneInfo()
	if not MythicPlus_IsKeystoneRun() then
		return 0, {}, false;
	end
	local run = MythicPlus.run;
	return run.level, run.affixes, run.state ~= MYTHIC_RUN_DONE_LATE;
end

function C_ChallengeMode.GetActiveChallengeMapID()
	return MythicPlus_IsKeystoneRun() and MythicPlus.run.mapID or nil;
end

function C_ChallengeMode.IsChallengeModeActive()
	return MythicPlus_IsKeystoneRun() and MythicPlus.run.state == MYTHIC_RUN_ACTIVE;
end

-- numDeaths, timeLost
function C_ChallengeMode.GetDeathCount()
	local run = MythicPlus.run;
	if not run then
		return 0, 0;
	end
	return run.deaths, run.deaths * run.penalty;
end

-- name, id, timeLimit
function C_ChallengeMode.GetMapUIInfo(mapID)
	local info = MythicPlus.mapInfo and MythicPlus.mapInfo[mapID];
	if info then
		return info.name, mapID, info.timeLimit;
	end
	if MythicPlus.key and MythicPlus.key.mapID == mapID then
		return MythicPlus.key.name, mapID, MythicPlus.key.timeLimit;
	end
	return nil, mapID, nil;
end

function C_ChallengeMode.GetMapTable()
	return MythicPlus.maps or {};
end

function C_ChallengeMode.GetChallengeCompletionInfo()
	return MythicPlus.completion;
end

function C_ChallengeMode.GetOverallDungeonScore()
	return MythicPlus.rating;
end

function C_MythicPlus.GetOwnedKeystoneChallengeMapID()
	return MythicPlus.key and MythicPlus.key.mapID or nil;
end

function C_MythicPlus.GetOwnedKeystoneLevel()
	return MythicPlus.key and MythicPlus.key.level or nil;
end

function C_MythicPlus.GetCurrentAffixes()
	local result = {};
	for i, id in ipairs(MythicPlus.week) do
		table.insert(result, { id = id, seasonID = 0 });
	end
	return result;
end

function C_MythicPlus.GetSeasonBestForMap(mapID)
	local best = MythicPlus.best[mapID];
	if not best then
		return nil;
	end
	return { level = best.level, durationSec = math.floor(best.timeMs / 1000), completionDate = nil }, nil;
end

---------------------------------------------------------------------------
-- keystone tooltip: "Эпохальный ключ: <dungeon>", level, affixes
---------------------------------------------------------------------------
local function ItemIDFromLink(link)
	return link and tonumber(string.match(link, "item:(%d+)"));
end

-- the key travels inside the link: uniqueId (the 8th number after the item id) = mapID * 100000 + level.
-- item:itemId:enchant:gem1:gem2:gem3:gem4:suffix:uniqueId:linkLevel
local KEY_LINK_FACTOR = 100000;

local function KeyFromLink(link)
	local fields = link and string.match(link, "item:([%-%d:]+)");
	if not fields then
		return nil;
	end
	local list = { strsplit(":", fields) };
	local packed = tonumber(list[9]);
	if not packed or packed < KEY_LINK_FACTOR then
		return nil;
	end
	local mapID, level = math.floor(packed / KEY_LINK_FACTOR), packed % KEY_LINK_FACTOR;
	local name = C_ChallengeMode.GetMapUIInfo(mapID);
	return { mapID = mapID, level = level, name = name or "" };
end

local function AddKeyToLink(text)
	local key = MythicPlus.key;
	if not key or type(text) ~= "string" or ItemIDFromLink(text) ~= KEYSTONE_ITEM_ID then
		return text;
	end
	local packed = key.mapID * KEY_LINK_FACTOR + math.min(key.level, KEY_LINK_FACTOR - 1);
	return (string.gsub(text, "item:([%-%d:]+)", function(fields)
		local list = { strsplit(":", fields) };
		for i = #list + 1, 10 do
			list[i] = "0";
		end
		list[9] = tostring(packed);
		return "item:" .. table.concat(list, ":");
	end, 1));
end

-- shift-click of the own keystone: the link carries its dungeon and level
local insertLink = ChatEdit_InsertLink;
ChatEdit_InsertLink = function(text, ...)
	return insertLink(AddKeyToLink(text), ...);
end

local function ReadLines(tooltip)
	local name, lines = tooltip:GetName(), {};
	for i = 1, tooltip:NumLines() do
		local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i];
		local entry = { text = left and left:GetText() or "" };
		if left then
			entry.r, entry.g, entry.b = left:GetTextColor();
		end
		if right and right:IsShown() and right:GetText() then
			entry.right = right:GetText();
			entry.rr, entry.rg, entry.rb = right:GetTextColor();
		end
		lines[i] = entry;
	end
	return lines;
end

local function WriteLines(tooltip, lines)
	local name, count = tooltip:GetName(), tooltip:NumLines();
	for i, entry in ipairs(lines) do
		if i > count then
			if entry.right then
				tooltip:AddDoubleLine(entry.text, entry.right, entry.r, entry.g, entry.b, entry.rr, entry.rg, entry.rb);
			else
				tooltip:AddLine(entry.text, entry.r, entry.g, entry.b, entry.wrap);
			end
		else
			local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i];
			left:SetText(entry.text);
			left:SetTextColor(entry.r or 1, entry.g or 1, entry.b or 1);
			if right then
				if entry.right then
					right:SetText(entry.right);
					right:SetTextColor(entry.rr or 1, entry.rg or 1, entry.rb or 1);
					right:Show();
				else
					right:SetText("");
					right:Hide();
				end
			end
		end
	end
end

-- retail order: name, Mythic Level, the item lines, Dungeon Modifiers + affixes, the description
local function DecorateKeystone(tooltip)
	local _, link = tooltip:GetItem();
	if ItemIDFromLink(link) ~= KEYSTONE_ITEM_ID then
		return;
	end
	-- a linked key: its own data; a hovered item (bags, character): the player's key
	local key = KeyFromLink(link);
	if not key and tooltip ~= ItemRefTooltip then
		key = MythicPlus.key;
	end
	if not key then
		return;
	end

	local lines = ReadLines(tooltip);
	local result, description = {}, {};
	for i, entry in ipairs(lines) do
		if i == 1 then
			entry.text = CHALLENGE_MODE_KEYSTONE_NAME:format(key.name);
			table.insert(result, entry);
			table.insert(result, { text = CHALLENGE_MODE_ITEM_POWER_LEVEL:format(key.level), r = 1, g = 0.82, b = 0 });
		elseif string.sub(entry.text, 1, 1) == "\"" then
			entry.wrap = true;
			table.insert(description, entry);
		else
			table.insert(result, entry);
		end
	end
	local affixes = MythicPlus_GetAffixesForLevel(key.level);
	if #affixes > 0 then
		table.insert(result, { text = DUNGEON_MODIFIERS or "Модификаторы подземелья:", r = 1, g = 1, b = 1 });
		for _, affixID in ipairs(affixes) do
			local name = C_ChallengeMode.GetAffixInfo(affixID);
			if name then
				table.insert(result, { text = "  " .. name, r = 0.12, g = 1, b = 0 });
			end
		end
	end
	for _, entry in ipairs(description) do
		table.insert(result, entry);
	end
	WriteLines(tooltip, result);
	tooltip:Show();
end

for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
	if tooltip then
		tooltip:HookScript("OnTooltipSetItem", DecorateKeystone);
	end
end

---------------------------------------------------------------------------
-- start countdown (10 .. 1) in the middle of the screen
---------------------------------------------------------------------------
local countdown = CreateFrame("Frame", "MythicPlusCountdownFrame", UIParent);
countdown:SetWidth(200);
countdown:SetHeight(120);
countdown:SetPoint("CENTER", 0, 180);
countdown:Hide();
countdown.Text = countdown:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge");
countdown.Text:SetPoint("CENTER");
countdown.Text:SetTextColor(1, 0.82, 0);
countdown.last = nil;

countdown:SetScript("OnUpdate", function(self)
	local left = MythicPlus_GetCountdownMs();
	if left <= 0 then
		self:Hide();
		return;
	end
	local seconds = math.ceil(left / 1000);
	if seconds ~= self.last then
		self.last = seconds;
		self.Text:SetText(seconds);
		PlaySound("RaidWarning");
	end
	local frac = (left / 1000) % 1;
	self.Text:SetAlpha(0.3 + 0.7 * frac);
end);

MythicPlus_RegisterCallback(function(event)
	if event == "RUN" then
		local run = MythicPlus.run;
		if run and run.state == MYTHIC_RUN_COUNTDOWN then
			countdown.last = nil;
			countdown:Show();
		else
			countdown:Hide();
		end
	elseif event == "COMPLETE" then
		PlaySound("LevelUp");
	end
end);

---------------------------------------------------------------------------
-- release spirit in a mythic dungeon (retail): back alive at the entrance or the last killed boss
---------------------------------------------------------------------------
local deathDialog = StaticPopupDialogs and StaticPopupDialogs["DEATH"];
if deathDialog then
	local repop = deathDialog.OnAccept;
	deathDialog.OnAccept = function(self, ...)
		if MythicPlus_IsInMythicInstance() then
			Send("MPLUS_RELEASE");
			return;
		end
		if repop then
			return repop(self, ...);
		end
	end
end

---------------------------------------------------------------------------
-- items from the Mythic+ chest: "Эпохальный +N" instead of the "Героический" line
-- (the server sends "bag/slot/level,...": bag 255 - equipment and bank, 0 - backpack, 1..4, 5..11 - bank bags)
---------------------------------------------------------------------------
local mythicItems = {};

if Comm_Register then
	Comm_Register("MPLUS_ITEMS", function(list)
		wipe(mythicItems);
		for entry in string.gmatch(list or "", "[^,]+") do
			local bag, slot, level = strsplit("/", entry);
			bag, slot, level = tonumber(bag), tonumber(slot), tonumber(level);
			if bag and slot and level then
				mythicItems[bag] = mythicItems[bag] or {};
				mythicItems[bag][slot] = level;
			end
		end
	end);
end

local function MythicLine(tooltip, bag, slot)
	local level = mythicItems[bag] and mythicItems[bag][slot];
	if not level then
		return;
	end
	-- retail ITEM_MYTHIC may be a format ("...: %d")
	local text = ITEM_MYTHIC:find("%%d") and ITEM_MYTHIC:format(level) or (ITEM_MYTHIC .. " +" .. level);
	local name = tooltip:GetName();
	for i = 2, tooltip:NumLines() do
		local line = _G[name .. "TextLeft" .. i];
		if line and line:GetText() == ITEM_HEROIC then
			line:SetText(text);
			tooltip:Show();
			return;
		end
	end
	-- no heroic line: under the name
	local line = _G[name .. "TextLeft1"];
	local current = line and line:GetText();
	if current and not current:find("\n", 1, true) then
		line:SetText(current .. "\n|cff1eff00" .. text .. "|r");
		tooltip:Show();
	end
end

local mythicTooltips = CreateFrame("Frame");
mythicTooltips:RegisterEvent("PLAYER_LOGIN");
mythicTooltips:RegisterEvent("BAG_UPDATE");
mythicTooltips:RegisterEvent("PLAYERBANKSLOTS_CHANGED");
mythicTooltips:RegisterEvent("UNIT_INVENTORY_CHANGED");
mythicTooltips:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		hooksecurefunc(GameTooltip, "SetInventoryItem", function(tooltip, unit, slot)
			if unit == "player" then
				MythicLine(tooltip, 255, slot);
			end
		end);
		hooksecurefunc(GameTooltip, "SetBagItem", function(tooltip, bag, slot)
			MythicLine(tooltip, bag, slot);
		end);
		return;
	end
	-- items moved: ask again once the burst of events is over
	self.pending = 0.5;
end);
mythicTooltips:SetScript("OnUpdate", function(self, elapsed)
	if self.pending then
		self.pending = self.pending - elapsed;
		if self.pending <= 0 then
			self.pending = nil;
			Send("MPLUS_ITEMS_GET");
		end
	end
end);
