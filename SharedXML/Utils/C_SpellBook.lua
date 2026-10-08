-- C_SpellBook для 3.3.5a поверх родного API (GetSpellTabInfo / GetSpellName / BOOKTYPE_*)
-- Вкладки 3.3.5: 1 = Общее, 2..4 = ветки талантов класса.

Enum = Enum or {};

Enum.SpellBookSpellBank = Enum.SpellBookSpellBank or {
	Player = 0,
	Pet = 1,
};

Enum.SpellBookItemType = Enum.SpellBookItemType or {
	None = 0,
	Spell = 1,
	FutureSpell = 2,
	PetAction = 3,
	Flyout = 4,
};

Enum.SpellBookSkillLineIndex = Enum.SpellBookSkillLineIndex or {
	General = 1,
	Class = 2,
	MainSpec = 3,
};

Enum.ClickBindingType = Enum.ClickBindingType or { Spell = 1, PetAction = 4 };
Enum.TooltipTextureAnchor = Enum.TooltipTextureAnchor or { LeftCenter = 1 };
Enum.FrameTutorialAccount = Enum.FrameTutorialAccount or { AssistedCombatRotationDragSpell = 0 };

C_SpellBook = C_SpellBook or {};

local BANK_TO_BOOKTYPE = {
	[Enum.SpellBookSpellBank.Player] = BOOKTYPE_SPELL or "spell",
	[Enum.SpellBookSpellBank.Pet] = BOOKTYPE_PET or "pet",
};

local function BookType(spellBank)
	return BANK_TO_BOOKTYPE[spellBank or Enum.SpellBookSpellBank.Player] or "spell";
end

-- «Отображать все уровни заклинаний» (CVar ShowAllSpellRanks, как в 3.3.5).
-- Когда выключено, книга работает в индексах «старших рангов», а к API
-- обращаемся через реальный слот (GetKnownSlotFromHighestRankSlot).
function C_SpellBook.IsShowingAllRanks()
	return GetCVarBool("ShowAllSpellRanks");
end

function C_SpellBook.SetShowAllRanks(show)
	SetCVar("ShowAllSpellRanks", show and "1" or "0");
end

local function RealSlot(slotIndex, spellBank)
	if spellBank == Enum.SpellBookSpellBank.Pet or C_SpellBook.IsShowingAllRanks() then
		return slotIndex;
	end
	-- 0 / nil - такого номера нет в таблице старших рангов (0 в Lua - не false, «or» его не ловит)
	local real = GetKnownSlotFromHighestRankSlot(slotIndex);
	if not real or real <= 0 then
		return nil;
	end
	return real;
end
C_SpellBook.GetRealSlot = RealSlot;

local function TabInfo(tab)
	local name, texture, offset, numSpells, highestOffset, highestNum = GetSpellTabInfo(tab);
	if name and not C_SpellBook.IsShowingAllRanks() and highestOffset then
		offset, numSpells = highestOffset, highestNum;
	end
	return name, texture, offset, numSpells;
end

local function SpellIDFromLink(link)
	return link and tonumber(link:match("spell:(%d+)"));
end

function C_SpellBook.GetNumSpellBookSkillLines()
	return GetNumSpellTabs();
end

function C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
	local name, texture, offset, numSpells = TabInfo(skillLineIndex);
	if not name then
		return nil;
	end
	return {
		name = name,
		iconID = texture,
		itemIndexOffset = offset or 0,
		numSpellBookItems = numSpells or 0,
		isGuild = false,
		shouldHide = (numSpells or 0) == 0,
		specID = nil,
		offSpecID = nil,
	};
end

function C_SpellBook.HasPetSpells()
	local numSpells, petToken = HasPetSpells();
	return numSpells, petToken;
end

function C_SpellBook.GetSpellBookItemType(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return Enum.SpellBookItemType.None;
	end
	local bookType = BookType(spellBank);
	local name = GetSpellName(slotIndex, bookType);
	if not name then
		return Enum.SpellBookItemType.None;
	end

	if spellBank == Enum.SpellBookSpellBank.Pet then
		local link = GetSpellLink(slotIndex, bookType);
		if not link then
			return Enum.SpellBookItemType.PetAction, nil;
		end
		return Enum.SpellBookItemType.Spell, SpellIDFromLink(link);
	end

	return Enum.SpellBookItemType.Spell, SpellIDFromLink(GetSpellLink(slotIndex, bookType));
end

local function FindSkillLineForSlot(slotIndex)
	for i = 1, GetNumSpellTabs() do
		local _, _, offset, numSpells = TabInfo(i);
		if slotIndex > offset and slotIndex <= offset + numSpells then
			return i;
		end
	end
end

function C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	local bookType = BookType(spellBank);
	local name, subName = GetSpellName(slotIndex, bookType);
	if not name then
		return nil;
	end

	local itemType, spellID = C_SpellBook.GetSpellBookItemType(displaySlot, spellBank);

	return {
		actionID = spellID or slotIndex,
		spellID = spellID,
		itemType = itemType,
		name = name,
		subName = subName ~= "" and subName or nil,
		iconID = GetSpellTexture(slotIndex, bookType),
		isPassive = IsPassiveSpell(slotIndex, bookType) and true or false,
		isOffSpec = false,
		skillLineIndex = spellBank == Enum.SpellBookSpellBank.Pet and nil or FindSkillLineForSlot(displaySlot),
	};
end

function C_SpellBook.GetSpellBookItemName(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	return GetSpellName(slotIndex, BookType(spellBank));
end

function C_SpellBook.GetSpellBookItemTexture(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	return GetSpellTexture(slotIndex, BookType(spellBank));
end

function C_SpellBook.IsSpellBookItemPassive(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	return IsPassiveSpell(slotIndex, BookType(spellBank)) and true or false;
end

function C_SpellBook.GetSpellBookItemLink(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	return GetSpellLink(slotIndex, BookType(spellBank));
end

function C_SpellBook.GetSpellBookItemTradeSkillLink(slotIndex, spellBank)
	return nil;
end

function C_SpellBook.GetSpellBookItemCooldown(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	local start, duration, enabled = GetSpellCooldown(slotIndex, BookType(spellBank));
	return {
		startTime = start or 0,
		duration = duration or 0,
		isEnabled = enabled == 1 or enabled == true,
		modRate = 1,
	};
end

function C_SpellBook.GetSpellBookItemAutoCast(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	local autoCastAllowed, autoCastEnabled = GetSpellAutocast(slotIndex, BookType(spellBank));
	return autoCastAllowed and true or false, autoCastEnabled and true or false;
end

function C_SpellBook.ToggleSpellBookItemAutoCast(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	ToggleSpellAutocast(slotIndex, BookType(spellBank));
end

function C_SpellBook.GetSpellBookItemLevelLearned(slotIndex, spellBank)
	return 0;
end

function C_SpellBook.PickupSpellBookItem(slotIndex, spellBank)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	PickupSpell(slotIndex, BookType(spellBank));
end

function C_SpellBook.CastSpellBookItem(slotIndex, spellBank, targetSelf)
	local displaySlot = slotIndex;
	slotIndex = RealSlot(slotIndex, spellBank);
	if not slotIndex then
		return nil;
	end
	CastSpell(slotIndex, BookType(spellBank));
end

function C_SpellBook.FindSpellBookSlotForSpell(spellID, includeHidden, includeFlyouts, includeFutureSpells, includeOffSpec)
	if not GetSpellInfo(spellID) then
		return nil;
	end
	local _, _, offset, numSpells = TabInfo(GetNumSpellTabs());
	local total = (offset or 0) + (numSpells or 0);
	for slot = 1, total do
		local realSlot = RealSlot(slot, Enum.SpellBookSpellBank.Player);
		local link = realSlot and GetSpellLink(realSlot, BOOKTYPE_SPELL);
		if SpellIDFromLink(link) == spellID then
			return slot, Enum.SpellBookSpellBank.Player;
		end
	end
	return nil;
end

function C_SpellBook.IsSpellInSpellBook(spellID, spellBank, includeOverrides)
	return C_SpellBook.FindSpellBookSlotForSpell(spellID) ~= nil;
end

-- C_Spell
C_Spell = C_Spell or {};

function C_Spell.GetSpellInfo(spellID)
	local name, rank, icon, powerCost, isFunnel, powerType, castingTime, minRange, maxRange = GetSpellInfo(spellID);
	if not name then
		return nil;
	end
	return {
		name = name,
		iconID = icon,
		originalIconID = icon,
		castTime = castingTime or 0,
		minRange = minRange or 0,
		maxRange = maxRange or 0,
		spellID = spellID,
		rank = rank,
	};
end

function C_Spell.GetOverrideSpell(spellID)
	return spellID;
end

-- заглушки систем, которых в 3.3.5 нет
C_LevelLink = C_LevelLink or { IsSpellLocked = function() return false; end };
C_ClickBindings = C_ClickBindings or { CanSpellBeClickBound = function() return false; end };
C_AssistedCombat = C_AssistedCombat or { GetRotationSpells = function() return {}; end, GetActionSpell = function() return nil; end };
C_ActionBar = C_ActionBar or {};
C_ActionBar.HasAssistedCombatActionButtons = C_ActionBar.HasAssistedCombatActionButtons or function() return false; end;

-- специализации 3.3.5 = ветки талантов
if not GetNumSpecializations then
	function GetNumSpecializations()
		return GetNumTalentTabs and GetNumTalentTabs() or 3;
	end
end

PlayerUtil = PlayerUtil or {};
function PlayerUtil.GetClassName()
	return (UnitClass("player"));
end

PlayerSpellsUtil = PlayerSpellsUtil or {};
PlayerSpellsUtil.SpellBookCategories = PlayerSpellsUtil.SpellBookCategories or {
	Class = 1,
	General = 2,
	Pet = 3,
};

FrameUtil = FrameUtil or {};
function FrameUtil.RegisterFrameForEvents(frame, events)
	for _, event in ipairs(events) do
		pcall(frame.RegisterEvent, frame, event);
	end
end
function FrameUtil.UnregisterFrameForEvents(frame, events)
	for _, event in ipairs(events) do
		pcall(frame.UnregisterEvent, frame, event);
	end
end
function FrameUtil.RegisterFrameForUnitEvents(frame, events, ...)
	FrameUtil.RegisterFrameForEvents(frame, events);
end

ChatFrameUtil = ChatFrameUtil or {};
function ChatFrameUtil.InsertLink(link)
	return ChatEdit_InsertLink(link);
end

-- tCompare нужен категориям спеллбука
if not tCompare then
	function tCompare(lhs, rhs, depth)
		depth = depth or 1;
		for key, value in pairs(lhs) do
			if type(value) == "table" and type(rhs[key]) == "table" then
				if depth > 1 and not tCompare(value, rhs[key], depth - 1) then
					return false;
				end
			elseif value ~= rhs[key] then
				return false;
			end
		end
		for key in pairs(rhs) do
			if lhs[key] == nil then
				return false;
			end
		end
		return true;
	end
end

function C_Spell.PickupSpell(spellID)
	local name = GetSpellInfo(spellID);
	if name then
		PickupSpell(name);
	end
end

function C_Spell.GetSpellCooldown(spellID)
	local name = GetSpellInfo(spellID);
	if not name then
		return nil;
	end
	local start, duration, enabled = GetSpellCooldown(name);
	if not start then
		return nil;
	end
	return { startTime = start, duration = duration, isEnabled = enabled == 1, modRate = 1 };
end