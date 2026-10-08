-- C_ActionBar и смежные API новых версий поверх 3.3.5a.
-- Нужен для порта ActionButton.lua / ActionBar.lua.

Enum = Enum or {};

Enum.PowerType = Enum.PowerType or {
	HealthCost = -2,
	None = -1,
	Mana = 0,
	Rage = 1,
	Focus = 2,
	Energy = 3,
	ComboPoints = 4,
	Runes = 5,
	RunicPower = 6,
};

Enum.GameMode = Enum.GameMode or { Standard = 0 };

C_ActionBar = C_ActionBar or {};

local NUM_SLOTS = 120;

---------------------------------------------------------------------------
-- прямые обёртки над функциями 3.3.5
---------------------------------------------------------------------------
function C_ActionBar.HasAction(slot) return HasAction(slot); end
function C_ActionBar.GetActionTexture(slot) return GetActionTexture(slot); end
function C_ActionBar.GetActionText(slot) return GetActionText(slot); end
function C_ActionBar.UsesActionText(slot) return GetActionText(slot) ~= nil; end
function C_ActionBar.IsUsableAction(slot) return IsUsableAction(slot); end
function C_ActionBar.IsCurrentAction(slot) return IsCurrentAction(slot); end
function C_ActionBar.IsAttackAction(slot) return IsAttackAction(slot); end
function C_ActionBar.IsAutoRepeatAction(slot) return IsAutoRepeatAction(slot); end
function C_ActionBar.IsConsumableAction(slot) return IsConsumableAction(slot); end
function C_ActionBar.IsStackableAction(slot) return IsStackableAction(slot); end
function C_ActionBar.IsItemAction(slot) return GetActionInfo(slot) == "item"; end
function C_ActionBar.IsEquippedAction(slot) return IsEquippedAction(slot); end
function C_ActionBar.IsHelpfulAction(slot) return IsHelpfulItem and IsHelpfulItem(slot) or false; end
function C_ActionBar.IsHarmfulAction(slot) return IsHarmfulItem and IsHarmfulItem(slot) or false; end
function C_ActionBar.ActionHasRange(slot) return ActionHasRange(slot); end
function C_ActionBar.IsActionInRange(slot, unit) return IsActionInRange(slot, unit); end
function C_ActionBar.PickupAction(slot) PickupAction(slot); end
function C_ActionBar.PlaceAction(slot) PlaceAction(slot); end
function C_ActionBar.PutActionInSlot(slot) PlaceAction(slot); end
function C_ActionBar.GetActionBarPage() return GetActionBarPage(); end
function C_ActionBar.SetActionBarPage(page) ChangeActionBarPage(page); end
function C_ActionBar.GetBonusBarIndex() return GetBonusBarOffset(); end

function C_ActionBar.GetActionCooldown(slot)
	local start, duration, enable = GetActionCooldown(slot);
	return { startTime = start or 0, duration = duration or 0, isEnabled = enable == 1, modRate = 1 };
end

function C_ActionBar.GetActionCharges(slot)
	-- зарядов в 3.3.5 нет
	return nil;
end

-- 3.3.5: GetSpellInfo не отдаёт spellID, он есть только в ссылке
local function SpellIDByName(name)
	if not name then
		return nil;
	end
	local link = GetSpellLink(name);
	return link and tonumber(link:match("spell:(%d+)"));
end

C_ActionBar.GetSpellIDByName = SpellIDByName;

---------------------------------------------------------------------------
-- питомец
---------------------------------------------------------------------------
function C_ActionBar.GetPetActionPetBarIndices(spellID)
	if not spellID then
		return nil;
	end

	local indices;
	for i = 1, NUM_PET_ACTION_SLOTS do
		local name, _, _, isToken = GetPetActionInfo(i);
		if name and not isToken then
			local id = SpellIDByName(name);
			if id == spellID then
				indices = indices or {};
				indices[#indices + 1] = i;
			end
		end
	end
	return indices;
end

function C_ActionBar.IsAutoCastPetAction(index)
	local autoCastAllowed, autoCastEnabled = select(6, GetPetActionInfo(index));
	return autoCastEnabled and true or false, autoCastAllowed and true or false;
end

function C_ActionBar.ToggleAutoCastPetAction(index)
	TogglePetAutocast(index);
end

C_PetInfo = C_PetInfo or {};

function C_PetInfo.IsPetActionPassive(index)
	return select(5, GetPetActionInfo(index)) and true or false;
end

---------------------------------------------------------------------------
-- поиск заклинаний на панелях
---------------------------------------------------------------------------
local function ActionSpellID(slot)
	local actionType, id = GetActionInfo(slot);
	if actionType == "spell" then
		if not id or id == 0 then
			return nil;
		end
		-- id здесь — номер в книге заклинаний
		local link = GetSpellLink(id, BOOKTYPE_SPELL);
		return link and tonumber(link:match("spell:(%d+)")) or nil;
	elseif actionType == "macro" then
		return SpellIDByName(GetMacroSpell(id));
	end
end

function C_ActionBar.FindSpellActionButtons(spellID)
	if not spellID then
		return nil;
	end

	-- быстрый путь: функция из DLL читает массив слотов клиента
	if FindSpellActionBarSlots then
		local results = { FindSpellActionBarSlots(spellID) };
		local slots;
		for _, slot in ipairs(results) do
			if type(slot) == "number" then
				slots = slots or {};
				slots[#slots + 1] = slot + 1; -- DLL отдаёт слоты с нуля
			end
		end
		return slots;
	end

	local slots;
	for slot = 1, NUM_SLOTS do
		if HasAction(slot) and ActionSpellID(slot) == spellID then
			slots = slots or {};
			slots[#slots + 1] = slot;
		end
	end
	return slots;
end

function C_ActionBar.FindPetActionButtons(spellID)
	return C_ActionBar.GetPetActionPetBarIndices(spellID);
end

function C_ActionBar.FindFlyoutActionButtons()
	return nil; -- флайаутов в 3.3.5 нет
end

function C_ActionBar.IsOnBarOrSpecialBar(spellID)
	return C_ActionBar.FindSpellActionButtons(spellID) ~= nil;
end

---------------------------------------------------------------------------
-- то, чего в 3.3.5 нет
---------------------------------------------------------------------------
function C_ActionBar.RegisterActionUIButton() end
function C_ActionBar.EnableActionRangeCheck() end
function C_ActionBar.GetProfessionQualityInfo() return nil; end
function C_ActionBar.IsAssistedCombatAction() return false; end
function C_ActionBar.IsEquippedGearOutfitAction() return false; end
function C_ActionBar.ShouldShowAssistedCombatRotationFrame() return false; end

C_LevelLink = C_LevelLink or {};
C_LevelLink.IsActionLocked = C_LevelLink.IsActionLocked or function() return false; end;
C_LevelLink.IsSpellLocked = C_LevelLink.IsSpellLocked or function() return false; end;

C_SpellActivationOverlay = C_SpellActivationOverlay or {};
C_SpellActivationOverlay.IsSpellOverlayed = C_SpellActivationOverlay.IsSpellOverlayed
	or function(spellID) return IsSpellOverlayed and IsSpellOverlayed(spellID) or false; end;

C_PetBattles = C_PetBattles or {};
C_PetBattles.IsInBattle = C_PetBattles.IsInBattle or function() return false; end;

C_GameRules = C_GameRules or {};
C_GameRules.GetActiveGameMode = C_GameRules.GetActiveGameMode or function() return Enum.GameMode.Standard; end;

C_TransmogOutfitInfo = C_TransmogOutfitInfo or {};
C_TransmogOutfitInfo.IsLockedOutfit = C_TransmogOutfitInfo.IsLockedOutfit or function() return false; end;
C_TransmogOutfitInfo.IsEquippedGearOutfitLocked = C_TransmogOutfitInfo.IsEquippedGearOutfitLocked or function() return false; end;

C_AssistedCombat = C_AssistedCombat or {};
C_AssistedCombat.GetActionSpell = C_AssistedCombat.GetActionSpell or function() return nil; end;
C_AssistedCombat.GetRotationSpells = C_AssistedCombat.GetRotationSpells or function() return {}; end;

---------------------------------------------------------------------------
-- C_Spell: то, что использует ActionButton.lua
---------------------------------------------------------------------------
C_Spell = C_Spell or {};

C_Spell.GetSpellCharges = C_Spell.GetSpellCharges or function() return nil; end;
C_Spell.IsPressHoldReleaseSpell = C_Spell.IsPressHoldReleaseSpell or function() return false; end;
C_Spell.GetSpellLossOfControlCooldownInfo = C_Spell.GetSpellLossOfControlCooldownInfo or function() return nil; end;

if not C_Spell.IsSpellPassive then
	function C_Spell.IsSpellPassive(spellID)
		local name = GetSpellInfo(spellID);
		return name ~= nil and IsPassiveSpell and IsPassiveSpell(name) or false;
	end
end

if not C_Spell.GetSpellPowerCost then
	function C_Spell.GetSpellPowerCost(spellID)
		local name, _, _, powerCost, _, powerType = GetSpellInfo(spellID);
		if not name then
			return nil;
		end
		return { { cost = powerCost or 0, type = powerType or Enum.PowerType.Mana, name = "SPELL_POWER_MANA" } };
	end
end

---------------------------------------------------------------------------
-- функции из WotLK-Extensions
---------------------------------------------------------------------------
function C_ActionBar.ReplaceSpell(oldSpellID, newSpellID)
	if ReplaceActionBarSpell then
		ReplaceActionBarSpell(oldSpellID, newSpellID);
	end
end

-- слот с единицы, как в Lua
function C_ActionBar.SetSpellInSlot(spellID, slot)
	if SetSpellInActionBarSlot and slot then
		SetSpellInActionBarSlot(spellID, slot - 1);
	end
end