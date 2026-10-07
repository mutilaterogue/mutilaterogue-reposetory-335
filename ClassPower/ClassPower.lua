-- ============================================================
--  Class powers of Cataclysm on 3.3.5a: Soul Shards (7), Eclipse (8), Holy Power (9)
--  The values come from the server (server/class_powers.cpp, "CLASS_POWER": type, value, max, direction):
--  the 3.3.5a unit has no field for them. UnitPower / UnitPowerMax answer them for the player, and the bars
--  (ShardBar, EclipseBarFrame, PaladinPowerBar) are updated as their events would.
-- ============================================================

SPELL_POWER_SOUL_SHARDS = 7;
SPELL_POWER_ECLIPSE = 8;
SPELL_POWER_HOLY_POWER = 9;

HOLY_POWER = HOLY_POWER or "Сила Света";
SOUL_SHARDS_POWER = SOUL_SHARDS_POWER or "Осколки души";
ECLIPSE = ECLIPSE or "Затмение";

local CLASS_POWER_TOKENS = { [7] = "SOUL_SHARDS", [8] = "ECLIPSE", [9] = "HOLY_POWER" };
local values = {};
local maxima = {};
local eclipseDirection = "none";

local ClientUnitPower = UnitPower;
local ClientUnitPowerMax = UnitPowerMax;

local function IsPlayer(unit)
	return unit and UnitIsUnit(unit, "player");
end

function UnitPower(unit, powerType, ...)
	if ( powerType and CLASS_POWER_TOKENS[powerType] ) then
		return IsPlayer(unit) and values[powerType] or 0;
	end
	return ClientUnitPower(unit, powerType, ...);
end

function UnitPowerMax(unit, powerType, ...)
	if ( powerType and CLASS_POWER_TOKENS[powerType] ) then
		return IsPlayer(unit) and maxima[powerType] or 0;
	end
	return ClientUnitPowerMax(unit, powerType, ...);
end

-- "sun", "moon" or "none"
function GetEclipseDirection()
	return eclipseDirection;
end

-- the spec's name (EclipseBar_UpdateShown compares it with DRUID_SPEC_BALANCE_TITLE): the primary talent tree,
-- else the tree with the most points
if ( not GetSpecName ) then
	function GetSpecName()
		local tree = GetPrimaryTalentTree and GetPrimaryTalentTree();
		if ( tree ) then
			return (GetTalentTabInfo(tree));
		end
		local best, bestPoints;
		for i = 1, GetNumTalentTabs() do
			local name, _, points = GetTalentTabInfo(i);
			if ( not bestPoints or points > bestPoints ) then
				best, bestPoints = name, points;
			end
		end
		return best;
	end
end

local function RefreshBars(powerType, directionChanged)
	if ( powerType == SPELL_POWER_SOUL_SHARDS and ShardBarFrame and ShardBar_OnEvent ) then
		ShardBar_OnEvent(ShardBarFrame, "UNIT_POWER_FREQUENT", ShardBarFrame:GetParent().unit, "SOUL_SHARDS");
	elseif ( powerType == SPELL_POWER_ECLIPSE and EclipseBarFrame and EclipseBar_Update ) then
		EclipseBar_Update(EclipseBarFrame);
		if ( directionChanged and EclipseBarFrame:IsShown() ) then
			EclipseBar_OnShow(EclipseBarFrame);
		end
	elseif ( powerType == SPELL_POWER_HOLY_POWER and PaladinPowerBar and PaladinPowerBar_Update ) then
		PaladinPowerBar_Update(PaladinPowerBar);
	end
end

Comm_Register("CLASS_POWER", function(powerType, value, maximum, direction)
	powerType = tonumber(powerType);
	if ( not powerType or not CLASS_POWER_TOKENS[powerType] ) then
		return;
	end
	values[powerType] = tonumber(value) or 0;
	maxima[powerType] = tonumber(maximum) or 0;
	local directionChanged = false;
	if ( powerType == SPELL_POWER_ECLIPSE and direction and direction ~= eclipseDirection ) then
		eclipseDirection = direction;
		directionChanged = true;
	end
	RefreshBars(powerType, directionChanged);
end);

Comm_OnLogin(function()
	Comm_Send("CLASS_POWER_GET");
end);
