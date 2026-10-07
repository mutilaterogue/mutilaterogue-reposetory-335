-- ============================================================
--  Class powers of Cataclysm on 3.3.5a: Soul Shards (7), Eclipse (8), Holy Power (9)
--  The values come from the server (server/class_powers.cpp, "CLASS_POWER": type, value, max, direction):
--  the 3.3.5a unit has no field for them. UnitPower / UnitPowerMax answer them for the player, and the bars
--  (ShardBar, EclipseBarFrame, PaladinPowerBar) are updated as their events would.
-- ============================================================

SPELL_POWER_SOUL_SHARDS = 7;
SPELL_POWER_ECLIPSE = 8;
SPELL_POWER_HOLY_POWER = 9;
HOLY_POWER_SPELL_READY = 3;		-- what the spenders take (retail's); up to 5 banked

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
	if ( powerType == SPELL_POWER_SOUL_SHARDS ) then
		if ( ShardBarFrame and ShardBar_OnEvent ) then
			ShardBar_OnEvent(ShardBarFrame, "UNIT_POWER_FREQUENT", ShardBarFrame:GetParent().unit, "SOUL_SHARDS");
		end
		ClassNameplateBarWarlock_Update();
	elseif ( powerType == SPELL_POWER_ECLIPSE and EclipseBarFrame and EclipseBar_Update ) then
		EclipseBar_Update(EclipseBarFrame);
		if ( directionChanged and EclipseBarFrame:IsShown() ) then
			EclipseBar_OnShow(EclipseBarFrame);
		end
	elseif ( powerType == SPELL_POWER_HOLY_POWER ) then
		if ( PaladinPowerBar and PaladinPowerBar_Update ) then
			PaladinPowerBar_Update(PaladinPowerBar);
		end
		ClassNameplateBarPaladin_Update();
	end
end

-- ------------------------------------------------------------
--  Holy Power under the personal resource bar (ClassNameplateBar), retail's look: the ClassOverlay atlases
-- ------------------------------------------------------------
local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil;
end

-- the art the client has: retail 12.x (UF-HolyPower: a 150 x 43 holder, five sockets), Legion's ClassOverlay, else
-- Cataclysm's PaladinPowerTextures file (the player frame's own)
local PALADIN_ART = {
	{
		-- retail 12.1.5 PaladinPowerBarFrameTemplate: the runes' LEFT anchors + half their size (their centers)
		check = "UF-HolyPower-RuneHolder", width = 150, height = 43, left = true,
		bg = { atlas = "UF-HolyPower-RuneHolder" },
		active = "UF-HolyPower-RuneHolder-Active",
		ready = "UF-HolyPower-RuneHolder-ThinGlow",
		runes = {
			{ atlas = "UF-HolyPower-Rune1-Active", glow = "UF-HolyPower-Rune1-Glow", x = 27, y = -1 },
			{ atlas = "UF-HolyPower-Rune2-Active", glow = "UF-HolyPower-Rune2-Glow", x = 51.6, y = 0 },
			{ atlas = "UF-HolyPower-Rune3-Active", glow = "UF-HolyPower-Rune3-Glow", x = 76.5, y = 0.5 },
			{ atlas = "UF-HolyPower-Rune4-Active", glow = "UF-HolyPower-Rune4-Glow", x = 99.5, y = 0 },
			{ atlas = "UF-HolyPower-Rune5-Active", glow = "UF-HolyPower-Rune5-Glow", x = 121.2, y = -1 },
		},
	},
	{
		check = "ClassOverlay-HolyPowerBG", width = 136, height = 39,
		bg = { atlas = "ClassOverlay-HolyPowerBG" },
		runes = {
			{ atlas = "ClassOverlay-HolyPower1on", x = 37, y = -22 },
			{ atlas = "ClassOverlay-HolyPower2on", x = 70, y = -21 },
			{ atlas = "ClassOverlay-HolyPower3on", x = 101, y = -21 },
		},
	},
	{
		width = 136, height = 39,
		bg = { file = "Interface\\PlayerFrame\\PaladinPowerTextures", coords = { 0.00390625, 0.53515625, 0.00781250, 0.31250000 } },
		runes = {
			{ file = "Interface\\PlayerFrame\\PaladinPowerTextures", coords = { 0.00390625, 0.14453125, 0.78906250, 0.96093750 }, width = 36, height = 22, x = 39, y = -22 },
			{ file = "Interface\\PlayerFrame\\PaladinPowerTextures", coords = { 0.15234375, 0.27343750, 0.78906250, 0.92187500 }, width = 31, height = 17, x = 72, y = -20 },
			{ file = "Interface\\PlayerFrame\\PaladinPowerTextures", coords = { 0.28125000, 0.38671875, 0.64843750, 0.81250000 }, width = 27, height = 21, x = 103, y = -22 },
		},
	},
};

local function SetArt(texture, art, keepSize)
	if ( art.atlas ) then
		texture:SetAtlas(art.atlas, keepSize);
	else
		texture:SetTexture(art.file);
		texture:SetTexCoord(unpack(art.coords));
		if ( art.width ) then
			texture:SetSize(art.width, art.height);
		end
	end
end

local function CreatePaladinNameplateFrame()
	local art = PALADIN_ART[#PALADIN_ART];
	for _, candidate in ipairs(PALADIN_ART) do
		if ( candidate.check and HasAtlas(candidate.check) ) then
			art = candidate;
			break;
		end
	end

	local frame = CreateFrame("Frame", "ClassNameplateBarPaladinFrame", UIParent);
	frame:SetSize(art.width, art.height);
	frame:SetPoint("CENTER");
	frame.hideWhenDetached = true;	-- only under the personal bar (ClassNameplateBar)
	frame:Hide();

	frame.bg = frame:CreateTexture(nil, "BACKGROUND");
	SetArt(frame.bg, art.bg, false);
	frame.bg:SetAllPoints(frame);

	-- the holder lit (some power) and its thin glow (enough for a spell), as retail's
	if ( art.active ) then
		frame.active = frame:CreateTexture(nil, "BORDER");
		frame.active:SetAtlas(art.active);
		frame.active:SetAllPoints(frame);
		frame.active:SetAlpha(0);
		frame.ready = frame:CreateTexture(nil, "BORDER");
		frame.ready:SetAtlas(art.ready);
		frame.ready:SetAllPoints(frame);
		frame.ready:SetBlendMode("ADD");
		frame.ready:SetAlpha(0);
	end

	local anchor = art.left and "LEFT" or "TOPLEFT";
	frame.runes = {};
	for i, place in ipairs(art.runes) do
		local rune = frame:CreateTexture(nil, "ARTWORK");
		SetArt(rune, place, true);
		rune:SetPoint("CENTER", frame, anchor, place.x, place.y);
		rune:SetAlpha(0);
		if ( place.glow ) then
			rune.glow = frame:CreateTexture(nil, "OVERLAY");
			rune.glow:SetAtlas(place.glow, true);
			rune.glow:SetPoint("CENTER", rune, "CENTER");
			rune.glow:SetBlendMode("ADD");
			rune.glow:SetAlpha(0);
		end
		frame.runes[i] = rune;
	end
	return frame;
end

local paladinNameplateFrame;

function ClassNameplateBarPaladin_GetFrame()
	local _, class = UnitClass("player");
	if ( class ~= "PALADIN" ) then
		return nil;
	end
	if ( not paladinNameplateFrame ) then
		paladinNameplateFrame = CreatePaladinNameplateFrame();
	end
	return paladinNameplateFrame;		-- shown by ClassNameplateBar when it attaches it
end

-- a rune lit or out: a short fade
local function SetRune(rune, lit)
	local target = lit and 1 or 0;
	if ( rune.target == target ) then
		return;
	end
	rune.target = target;
	if ( lit ) then
		UIFrameFadeIn(rune, 0.2, rune:GetAlpha(), 1);
	else
		UIFrameFadeOut(rune, 0.3, rune:GetAlpha(), 0);
	end
end

function ClassNameplateBarPaladin_Update()
	if ( not paladinNameplateFrame ) then
		return;
	end
	local frame = paladinNameplateFrame;
	local power = UnitPower("player", SPELL_POWER_HOLY_POWER);
	local ready = power >= HOLY_POWER_SPELL_READY;
	for i, rune in ipairs(frame.runes) do
		SetRune(rune, i <= power);
		if ( rune.glow ) then
			rune.glow:SetAlpha((ready and i <= power) and 0.6 or 0);
		end
	end
	if ( frame.active ) then
		frame.active:SetAlpha(power > 0 and 1 or 0);
		frame.ready:SetAlpha(ready and 1 or 0);
	end
end

-- ------------------------------------------------------------
--  Soul Shards under the personal resource bar, retail's look (12.1.5 ShardBar.xml): a 23 x 30 slot a shard,
--  1 apart; the holder UF-SoulShard-Holder, the shard UF-SoulShard-Icon (+ IconGlow as it fills)
-- ------------------------------------------------------------
local SHARD_WIDTH, SHARD_HEIGHT, SHARD_SPACING = 23, 30, 1;
local warlockNameplateFrame;

local function CreateWarlockNameplateFrame()
	local count = 3;
	local frame = CreateFrame("Frame", "ClassNameplateBarWarlockFrame", UIParent);
	frame:SetSize(count * SHARD_WIDTH + (count - 1) * SHARD_SPACING, SHARD_HEIGHT);
	frame:SetPoint("CENTER");
	frame.hideWhenDetached = true;	-- only under the personal bar (ClassNameplateBar)
	frame:Hide();

	local retail = HasAtlas("UF-SoulShard-Holder");
	frame.shards = {};
	for i = 1, count do
		local slot = CreateFrame("Frame", nil, frame);
		slot:SetSize(SHARD_WIDTH, SHARD_HEIGHT);
		slot:SetPoint("LEFT", frame, "LEFT", (i - 1) * (SHARD_WIDTH + SHARD_SPACING), 0);

		slot.holder = slot:CreateTexture(nil, "BACKGROUND");
		slot.icon = slot:CreateTexture(nil, "ARTWORK");
		slot.glow = slot:CreateTexture(nil, "OVERLAY");
		if ( retail ) then
			slot.holder:SetAtlas("UF-SoulShard-Holder", true);
			slot.holder:SetPoint("CENTER", 0, -4.5);
			slot.icon:SetAtlas("UF-SoulShard-Icon", true);
			slot.icon:SetPoint("CENTER", 0, -3);
			slot.glow:SetAtlas("UF-SoulShard-IconGlow", true);
			slot.glow:SetPoint("CENTER", 0, -3);
		else
			-- Cataclysm's UI-WarlockShard (the player frame's ShardBar)
			slot.holder:SetTexture("Interface\\PlayerFrame\\UI-WarlockShard");
			slot.holder:SetTexCoord(0.01562500, 0.82812500, 0.60937500, 0.83593750);
			slot.holder:SetSize(SHARD_WIDTH, 13);
			slot.holder:SetPoint("CENTER");
			slot.icon:SetTexture("Interface\\PlayerFrame\\UI-WarlockShard");
			slot.icon:SetTexCoord(0.01562500, 0.28125000, 0.00781250, 0.13281250);
			slot.icon:SetSize(17, 16);
			slot.icon:SetPoint("CENTER");
			slot.glow:SetTexture("Interface\\PlayerFrame\\UI-WarlockShard");
			slot.glow:SetTexCoord(0.01562500, 0.42187500, 0.14843750, 0.32812500);
			slot.glow:SetSize(26, 23);
			slot.glow:SetPoint("CENTER");
		end
		slot.glow:SetBlendMode("ADD");
		slot.icon:SetAlpha(0);
		slot.glow:SetAlpha(0);
		frame.shards[i] = slot;
	end
	return frame;
end

function ClassNameplateBarWarlock_GetFrame()
	local _, class = UnitClass("player");
	if ( class ~= "WARLOCK" ) then
		return nil;
	end
	if ( not warlockNameplateFrame ) then
		warlockNameplateFrame = CreateWarlockNameplateFrame();
	end
	return warlockNameplateFrame;		-- shown by ClassNameplateBar when it attaches it
end

function ClassNameplateBarWarlock_Update()
	if ( not warlockNameplateFrame ) then
		return;
	end
	local power = UnitPower("player", SPELL_POWER_SOUL_SHARDS);
	for i, slot in ipairs(warlockNameplateFrame.shards) do
		local lit = i <= power;
		if ( slot.lit ~= lit ) then
			slot.lit = lit;
			SetRune(slot.icon, lit);
			if ( lit ) then
				-- a short flash as it fills (retail's IconGlow)
				slot.glow:SetAlpha(1);
				UIFrameFadeOut(slot.glow, 0.6, 1, 0);
			end
		end
	end
end

-- the bar of the player's class under the personal resource bar (ClassNameplateBar), refreshed as it is attached
function ClassNameplateBarClassPower_Update()
	ClassNameplateBarPaladin_Update();
	ClassNameplateBarWarlock_Update();
end

local function OnClassPower(powerType, value, maximum, direction)
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
end

-- Server.lua (Comm_Register / Comm_Send) may load after this file: registered at login, whatever the .toc order
local registered = false;
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_LOGIN");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:SetScript("OnEvent", function(self, event)
	if ( not Comm_Register or not Comm_Send ) then
		return;
	end
	if ( not registered ) then
		Comm_Register("CLASS_POWER", OnClassPower);
		registered = true;
	end
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		Comm_Send("CLASS_POWER_GET");
	end
end);
