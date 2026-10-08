-- ============================================================
--  Guild progression (server/guild_progression.cpp), stage 1: guild level, experience, perks.
--  The 3.3.5a client has none of it: the values come from the server by AddonComm and are given to the UI
--  through Cataclysm's / retail's API (GetGuildLevel, UnitGetGuildXP, GetNumGuildPerks, GetGuildPerkInfo).
--  The UI listens with GuildProgression_RegisterCallback(func): func("GUILD_XP_UPDATE") / ("GUILD_PERK_UPDATE").
-- ============================================================

GUILD_MAX_LEVEL = 25;

local progress = { level = 0, experience = 0, toNext = 0, today = 0, dailyCap = 0 };
local perks = {};			-- { level = , spellID = }, by level
local callbacks = {};

function GuildProgression_RegisterCallback(func)
	tinsert(callbacks, func);
end

local function Fire(event)
	for _, func in ipairs(callbacks) do
		func(event);
	end
end

-- level, max level (0 without a guild)
function GetGuildLevel()
	return progress.level, GUILD_MAX_LEVEL;
end

-- Cataclysm's: current experience, to the next level, today's, today's cap (0: no cap)
function UnitGetGuildXP(unit)
	if ( unit and not UnitIsUnit(unit, "player") ) then
		return 0, 0, 0, 0;
	end
	return progress.experience, progress.toNext, progress.today, progress.dailyCap;
end

function GetNumGuildPerks()
	return #perks;
end

-- name, spellID, icon, description, guild level (Cataclysm's / retail's order)
function GetGuildPerkInfo(index)
	local perk = perks[index];
	if ( not perk ) then
		return;
	end
	local name, _, icon = GetSpellInfo(perk.spellID);
	local description = GetSpellDescription and GetSpellDescription(perk.spellID) or "";
	return name or ("Перк "..perk.spellID), perk.spellID, icon or "Interface\\Icons\\INV_Misc_QuestionMark", description, perk.level;
end

-- the perk is the guild's already
function IsGuildPerkActive(index)
	local perk = perks[index];
	return perk and progress.level >= perk.level;
end

local function OnProgress(level, experience, toNext, today, dailyCap)
	local oldLevel = progress.level;
	progress.level = tonumber(level) or 0;
	progress.experience = tonumber(experience) or 0;
	progress.toNext = tonumber(toNext) or 0;
	progress.today = tonumber(today) or 0;
	progress.dailyCap = tonumber(dailyCap) or 0;
	Fire("GUILD_XP_UPDATE");
	if ( oldLevel ~= progress.level ) then
		Fire("GUILD_PERK_UPDATE");
	end
end

-- level : spell : level : spell ...
local function OnPerks(...)
	perks = {};
	for i = 1, select("#", ...), 2 do
		local level, spellID = tonumber((select(i, ...))), tonumber((select(i + 1, ...)));
		if ( level and spellID ) then
			tinsert(perks, { level = level, spellID = spellID });
		end
	end
	sort(perks, function(a, b) return a.level < b.level; end);
	Fire("GUILD_PERK_UPDATE");
end

-- Server.lua may load after this file: registered at login, whatever the .toc order
local registered = false;
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:RegisterEvent("PLAYER_GUILD_UPDATE");
loader:SetScript("OnEvent", function(self, event)
	if ( not Comm_Register or not Comm_Send ) then
		return;
	end
	if ( not registered ) then
		Comm_Register("GUILD_PROG", OnProgress);
		Comm_Register("GUILD_PERKS", OnPerks);
		registered = true;
		Comm_Send("GUILD_PERKS_GET");
	end
	Comm_Send("GUILD_PROG_GET");
end);
