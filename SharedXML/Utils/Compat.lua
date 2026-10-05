-- Compat.lua: недостающие в 3.3.5a функции и методы, которые ждёт код из 7.3.5+
-- Грузить после XMLExt.lua и C_Timer.lua, до Util.lua

LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2

---------------------------------------------------------------------------
-- глобальные функции
---------------------------------------------------------------------------
nop = nop or function() end

if not GetPhysicalScreenSize then
	function GetPhysicalScreenSize()
		local res = GetCVar("gxResolution") or "";
		local w, h = res:match("(%d+)x(%d+)");
		return tonumber(w) or 1024, tonumber(h) or 768;
	end
end

if not IsTrialAccount then IsTrialAccount = function() return false end end
if not IsVeteranTrialAccount then IsVeteranTrialAccount = function() return false end end

LARGE_NUMBER_SEPERATOR = LARGE_NUMBER_SEPERATOR or ",";
TIME_UNIT_DELIMITER = TIME_UNIT_DELIMITER or " ";
PERCENTAGE_STRING = PERCENTAGE_STRING or "%d%%";

Enum = Enum or {};

Enum.LFGRole = {
	Tank = 0,
	Healer = 1,
	Damage = 2,
};

---------------------------------------------------------------------------
-- методы виджетов
---------------------------------------------------------------------------
local function AddMethods(meta, methods)
	for name, fn in pairs(methods) do
		if not meta[name] then
			meta[name] = fn;
		end
	end
end

local function SetShown(self, shown)
	if shown then self:Show() else self:Hide() end
end

local function SetEnabled(self, enabled)
	if enabled then self:Enable() else self:Disable() end
end

local function SetSize(self, w, h)
	self:SetWidth(w);
	self:SetHeight(h or w);
end

local function GetSize(self)
	return self:GetWidth(), self:GetHeight();
end

local function GetScaledRect(self)
	local l, b, w, h = self:GetRect();
	if not l then return end
	local s;
	if self.GetEffectiveScale then
		s = self:GetEffectiveScale();
	else
		-- у регионов (FontString/Texture) масштаб берётся от родителя
		local parent = self:GetParent();
		s = parent and parent:GetEffectiveScale() or UIParent:GetEffectiveScale();
	end
	return l * s, b * s, w * s, h * s;
end

local function ClearPointsAndSetPoint(self, ...)
	self:ClearAllPoints();
	self:SetPoint(...);
end

local common = {
	SetShown = SetShown,
	SetSize = SetSize,
	GetSize = GetSize,
	GetScaledRect = GetScaledRect,
	ClearPointsOffset = nop,
	ClearAndSetPoint = ClearPointsAndSetPoint,
};

local holder = CreateFrame("Frame");

-- фреймы (у всех типов, начиная с Frame, общий __index в 3.3.5 нет — патчим каждый)
local frameTypes = {
	"Frame", "Button", "CheckButton", "EditBox", "Slider", "StatusBar",
	"ScrollFrame", "MessageFrame", "ScrollingMessageFrame", "SimpleHTML",
	"Cooldown", "Model", "PlayerModel", "DressUpModel", "TabardModel",
	"ColorSelect", "GameTooltip", "Minimap", "MovieFrame",
};

for _, t in ipairs(frameTypes) do
	local ok, f = pcall(CreateFrame, t, nil, holder);
	if ok and f then
		local meta = getmetatable(f).__index;
		AddMethods(meta, common);
		if meta.Enable and meta.Disable then
			AddMethods(meta, { SetEnabled = SetEnabled });
		end
		f:Hide();
	end
end

-- текстуры
local tex = holder:CreateTexture();
local texMeta = getmetatable(tex).__index;
AddMethods(texMeta, common);
local textureMeta = getmetatable(CreateFrame("Frame"):CreateTexture()).__index
AddMethods(textureMeta, {
	SetColorTexture = function(self, r, g, b, a)
		self:SetTexture(r, g, b, a);
	end,
	SetDrawLayer = texMeta.SetDrawLayer or nop,
});

-- фонтстринги
local fs = holder:CreateFontString();
local fsMeta = getmetatable(fs).__index;
AddMethods(fsMeta, common);
AddMethods(fsMeta, {
	IsTruncated = function(self)
		return self:GetStringWidth() > self:GetWidth() + 0.5;
	end,
});

-- анимации
local ag = holder:CreateAnimationGroup();
AddMethods(getmetatable(ag).__index, {
	SetPlaying = function(self, playing)
		if playing then self:Play() else self:Stop() end
	end,
});

function GetDisplayedAllyFrames()
	local UseCompact = GetCVarBool("useCompactPartyFrames")
	local _, InstanceType = GetInstanceInfo()

	if ( not UseCompact and InstanceType == "arena" ) then
		return "party"
	end

	if ( IsInGroup() ) then
		if ( UseCompact or IsInRaid() ) then
			return "raid"
		end
		return "party"
	end

	return nil
end

function IsInGroup(LE_CATEGORY)
	if ( LE_CATEGORY and LE_CATEGORY == LE_PARTY_CATEGORY_INSTANCE ) then
		return false
	end
	return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

function IsInRaid(LE_CATEGORY)
	if ( LE_CATEGORY and LE_CATEGORY == LE_PARTY_CATEGORY_INSTANCE ) then
		return false
	end
	return GetNumRaidMembers() > 0
end

function GetNumSubgroupMembers()
	return GetNumPartyMembers()
end

function GetNumGroupMembers()
	local Total = GetNumRaidMembers()

	-- If in a raid, GetNumRaidMembers() is always the total count.
	if ( Total > 0 ) then
		return Total
	end

	-- If not in a raid, check the party.
	-- GetNumPartyMembers() returns 1-4 (excluding player).
	-- If it's 0, we are solo (return 0).
	-- If it's > 0, we add 1 for the player.
	local Total = GetNumPartyMembers()
	return (Total > 0) and (Total + 1) or 0
end

function UnitIsGroupLeader(Unit)
	local NumRaid = GetNumRaidMembers()
	local NumParty = GetNumPartyMembers()

	if ( Unit == "player" ) then
		if ( NumRaid > 0 ) then
			return IsRaidLeader()
		elseif ( NumParty > 0 ) then
			return IsPartyLeader()
		end
		return false
	end

	if ( NumRaid > 0 ) then
		for i = 1, NumRaid do
			local _, Rank = GetRaidRosterInfo(i)
			if ( Rank == 2 and UnitIsUnit(Unit, "raid"..i) ) then
				return true
			end
		end
	elseif ( NumParty > 0 ) then
		return UnitIsPartyLeader(Unit)
	end

	return false
end

function UnitIsGroupAssistant(Unit)
	local NumRaid = GetNumRaidMembers()

	if ( NumRaid == 0 ) then
		return false
	end

	for i = 1, NumRaid do
		local _, Rank = GetRaidRosterInfo(i)
		if ( Rank == 1 and UnitIsUnit(Unit, "raid"..i) ) then
			return true
		end
	end

	return false
end

local IsAllAssistant, AssistantTicker
function SetEveryoneIsAssistant(Enable)
	local NumMembers = GetNumRaidMembers()

	if ( NumMembers <= 0 ) then return end

	if ( AssistantTicker ) then
		AssistantTicker:Cancel()
		AssistantTicker = nil
	end

	IsAllAssistant = Enable

	AssistantTicker = C_Timer.NewTicker(0.2, function(Self)
		local Unit = "raid"..Self.Index

		-- Skip checking the player (you cannot demote yourself)
		if ( not UnitIsUnit(Unit, "player") ) then
			if ( IsAllAssistant ) then
				-- Only promote if they aren't already an assistant/leader
				local _, Rank = GetRaidRosterInfo(Self.Index)
				if ( Rank == 0 ) then
					PromoteToAssistant(Unit)
				end
			else
				-- Only demote if they are currently an assistant
				local _, Rank = GetRaidRosterInfo(Self.Index)
				if ( Rank == 1 ) then
					DemoteAssistant(Unit)
				end
			end
		end

		Self.Index = Self.Index + 1
	end, NumMembers)

	AssistantTicker.Index = 1
end

function IsEveryoneAssistant()
	return IsAllAssistant
end

function CanBeRaidTarget(Unit)
	if ( not Unit or not UnitExists(Unit) or not UnitIsConnected(Unit) ) then
		return false
	end

	if ( UnitIsPlayer(Unit) and UnitIsEnemy("player", Unit) ) then
		return false
	end

	return true
end

ALTERNATE_POWER_INDEX = ALTERNATE_POWER_INDEX or 10

function UnitAlternatePowerInfo(unit)
	return nil
end

function UnitHasIncomingResurrection(unit)
	return false
end

function GetTexCoordsForRoleSmallCircle(role)
	if role == "TANK" then
		return 0, 19/64, 22/64, 41/64
	elseif role == "HEALER" then
		return 20/64, 39/64, 1/64, 20/64
	elseif role == "DAMAGER" then
		return 20/64, 39/64, 22/64, 41/64
	end
	return 0, 1, 0, 1
end

---------------------------------------------------------------------------
-- UIPanelSpellButtonFrame / PagedContent
---------------------------------------------------------------------------
if not CooldownFrame_Set then
	function CooldownFrame_Set(cooldown, start, duration, enable, forceShowDrawEdge, modRate)
		if enable and enable ~= 0 and start and start > 0 and duration and duration > 0 then
			cooldown:SetCooldown(start, duration)
			cooldown:Show()
		else
			cooldown:Hide()
		end
	end
end

if not CooldownFrame_Clear then
	function CooldownFrame_Clear(cooldown)
		cooldown:Hide()
	end
end

do
	-- the login screen (GlueXML) has no GameTooltip frame type: skip there, the rest of this file must run
	local ok, tooltip = pcall(CreateFrame, "GameTooltip", nil, holder)
	local tooltipMeta = ok and tooltip and getmetatable(tooltip).__index or {}
	if not tooltipMeta.SetSpellByID then
		tooltipMeta.SetSpellByID = function(self, spellID)
			if spellID then
				self:SetHyperlink("spell:" .. spellID)
			end
		end
	end
end

if not CastSpellByID then
	function CastSpellByID(spellID)
		local name = GetSpellInfo(spellID)
		if name then
			CastSpellByName(name)
		end
	end
end

DrawLayerUtil = {}

local layerHolder = CreateFrame("Frame")
local layerMeta = getmetatable(layerHolder:CreateTexture()).__index
local OriginalSetDrawLayer = layerMeta.SetDrawLayer

local pending, scheduled = {}, false

local function ApplyPending()
	scheduled = false

	for parent in pairs(pending) do
		pending[parent] = nil

		if parent.GetRegions then
			local byLayer = {}

			for _, region in ipairs({ parent:GetRegions() }) do
				-- textures only: OriginalSetDrawLayer is the Texture method (a FontString errors with it)
				if region.GetDrawLayer and region:IsObjectType("Texture") then
					local layer = region:GetDrawLayer()
					byLayer[layer] = byLayer[layer] or {}
					local list = byLayer[layer]
					list[#list + 1] = { region = region, subLevel = region.subLevel or 0, order = #list }
				end
			end

			for layer, list in pairs(byLayer) do
				table.sort(list, function(a, b)
					if a.subLevel ~= b.subLevel then
						return a.subLevel < b.subLevel
					end
					return a.order < b.order
				end)

				local shuffleLayer = (layer == "BACKGROUND") and "OVERLAY" or "BACKGROUND"

				for _, entry in ipairs(list) do
					OriginalSetDrawLayer(entry.region, shuffleLayer)
					OriginalSetDrawLayer(entry.region, layer)
				end
			end
		end
	end
end

function DrawLayerUtil.SetSubLevel(texture, subLevel)
	texture.subLevel = subLevel
	pending[texture:GetParent() or UIParent] = true

	if not scheduled then
		scheduled = true
		C_Timer.After(0, ApplyPending)
	end
end

function DrawLayerUtil.GetSubLevel(texture)
	return texture.subLevel or 0
end

layerMeta.SetDrawLayer = function(self, layer, subLevel)
	OriginalSetDrawLayer(self, layer)
	if subLevel and subLevel ~= 0 then
		DrawLayerUtil.SetSubLevel(self, subLevel)
	end
end

Constants = Constants or {};
Constants.LFG_ROLEConstants = Constants.LFG_ROLEConstants or {
	LFG_ROLE_NO_ROLE = -1,
	LFG_ROLE_ANY = 3,
};

-- используется в GetIconForRoleEnum
assertsafe = assertsafe or function(cond, msg)
	if not cond then
		geterrorhandler()(msg or "assertion failed");
	end
	return cond;
end

-- Флайауты (Cata API) поверх функций DLL: GetSpellFlyoutRawInfo / GetSpellFlyoutSlotSpell
function GetFlyoutInfo(flyoutID)
	local name, description, numSlots, matchesPlayer = GetSpellFlyoutRawInfo(flyoutID);
	if ( not name ) then
		return;
	end
	local isKnown = false;
	if ( matchesPlayer ) then
		for i = 1, numSlots do
			local spellID = GetSpellFlyoutSlotSpell(flyoutID, i);
			if ( spellID and IsSpellKnown(spellID) ) then
				isKnown = true;
				break;
			end
		end
	end
	return name, description, numSlots, isKnown;
end

function GetFlyoutSlotInfo(flyoutID, slot)
	local spellID = GetSpellFlyoutSlotSpell(flyoutID, slot);
	return spellID, spellID and IsSpellKnown(spellID) or false;
end

function FlyoutHasSpell(flyoutID, spellID)
	local _, _, numSlots = GetSpellFlyoutRawInfo(flyoutID);
	for i = 1, numSlots or 0 do
		if ( GetSpellFlyoutSlotSpell(flyoutID, i) == spellID ) then
			return true;
		end
	end
	return false;
end

GetCallPetSpellInfo = GetCallPetSpellInfo or function() return nil; end

-- Заклинания, которые открываются из флайаутов, известных игроку (для скрытия в книге)
function SpellFlyout_GetContainedSpells()
	local hidden = {};
	if ( not GetFlyoutIDBySpell or not C_SpellBook ) then
		return hidden;
	end

	local bank = Enum.SpellBookSpellBank.Player;
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line);
		if ( lineInfo ) then
			for slot = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, bank);
				local flyoutID = item and item.spellID and GetFlyoutIDBySpell(item.spellID);
				if ( flyoutID ) then
					local _, _, numSlots = GetSpellFlyoutRawInfo(flyoutID);
					for i = 1, numSlots or 0 do
						local spellID = GetSpellFlyoutSlotSpell(flyoutID, i);
						if ( spellID ) then
							hidden[spellID] = true;
						end
					end
				end
			end
		end
	end

	return hidden;
end