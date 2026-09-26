-- CharacterFrame (Cataclysm 4.3.4) -> 3.3.5a
-- Заглушки API и строк, которых нет в 3.3.5. Грузится первым из CharacterFrame.xml.

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

if not GetMeleeHaste then
	function GetMeleeHaste()
		return GetCombatRatingBonus(CR_HASTE_MELEE or 18) or 0;
	end
end

if not GetRangedHaste then
	function GetRangedHaste()
		return GetCombatRatingBonus(CR_HASTE_RANGED or 19) or 0;
	end
end

if not UnitSpellHaste then
	function UnitSpellHaste(unit)
		return GetCombatRatingBonus(CR_HASTE_SPELL or 20) or 0;
	end
end

if not IsDualWielding then
	function IsDualWielding()
		return OffhandHasWeapon() and true or false;
	end
end

if not GetExpertisePercent then
	-- 3.3.5: 1 ед. мастерства = 0.25% снижения уклонения/парирования
	function GetExpertisePercent()
		local mh, oh = GetExpertise();
		return (mh or 0) * 0.25, (oh or 0) * 0.25;
	end
end

if not GetPowerRegen then
	-- 3.3.5 не отдаёт реген энергии/фокуса; считаем от базы и скорости
	function GetPowerRegen()
		local _, token = UnitPowerType("player");
		local haste = 1 + (GetCombatRatingBonus(CR_HASTE_MELEE or 18) or 0) / 100;
		if token == "ENERGY" then
			return 10 * haste, 10 * haste;
		elseif token == "FOCUS" then
			return 5, 5;
		end
		return 0, 0;
	end
end

if not GetMastery then
	function GetMastery()
		if GetCustomCombatRatingBonus then
			return GetCustomCombatRatingBonus(CR_MASTERY or 26) or 0;
		end
		return 0;
	end
end

if not GetOverrideSpellPowerByAP then
	function GetOverrideSpellPowerByAP()
		return nil;
	end
end

if not UnitHPPerStamina then
	function UnitHPPerStamina()
		return HEALTH_PER_STAMINA or 10;
	end
end

if not IsTrialAccount then
	function IsTrialAccount()
		return false;
	end
end

if not GetRestrictedAccountData then
	function GetRestrictedAccountData()
		return 0, 0, 0;
	end
end

if not PlaySoundKitID then
	function PlaySoundKitID()
		PlaySound("igCharacterInfoTab");
	end
end

if not ResistancePercent then
	-- примерное снижение урона (среднее) для цели указанного уровня
	function ResistancePercent(resistance, level)
		resistance = resistance or 0;
		level = level or UnitLevel("player");
		local k = max(1, level * 5 + 110);
		return min(75, 100 * resistance / (resistance + k));
	end
end

if not GetAverageItemLevel then
	local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 };
	function GetAverageItemLevel()
		local total, count = 0, 0;
		local twoHander = false;
		for _, slot in ipairs(SLOTS) do
			local link = GetInventoryItemLink("player", slot);
			if link then
				local _, _, _, ilvl, _, _, _, _, equipLoc = GetItemInfo(link);
				if ilvl then
					total = total + ilvl;
					if slot == 16 and equipLoc == "INVTYPE_2HWEAPON" then
						twoHander = true;
					end
				end
			end
			if slot ~= 17 or not twoHander then
				count = count + 1;
			end
		end
		local avg = count > 0 and total / count or 0;
		return avg, avg;
	end
end

-- Катовские битовые CVar-ы (свёрнутые категории статов)
local function SafeRegisterCVar(name, default)
	if GetCVar(name) == nil and RegisterCVar then
		pcall(RegisterCVar, name, default);
	end
end

local fallbackCVars = {};
local function CVarExists(name)
	return GetCVar(name) ~= nil;
end

local cvarDefaults = {
	characterFrameCollapsed = "0",
	statCategoryOrder = "",
	statCategoryOrder_2 = "",
	statCategoriesCollapsed = "0",
	statCategoriesCollapsed_2 = "0",
	petStatCategoryOrder = "",
	petStatCategoriesCollapsed = "0",
};
for name, default in pairs(cvarDefaults) do
	SafeRegisterCVar(name, default);
	if not CVarExists(name) then
		fallbackCVars[name] = default;
	end
end

-- GetCVar/SetCVar для этих имён работают, даже если RegisterCVar не сработал
local origGetCVar, origSetCVar = GetCVar, SetCVar;
function PaperDoll_GetCVar(name)
	if fallbackCVars[name] ~= nil then
		return fallbackCVars[name];
	end
	return origGetCVar(name);
end

function PaperDoll_SetCVar(name, value)
	value = tostring(value);
	if fallbackCVars[name] ~= nil then
		fallbackCVars[name] = value;
		return;
	end
	origSetCVar(name, value);
end

if not GetCVarBitfield then
	function GetCVarBitfield(name, index)
		local value = tonumber(PaperDoll_GetCVar(name)) or 0;
		local bit = 2 ^ (index - 1);
		return (value % (bit * 2)) >= bit;
	end
end

if not SetCVarBitfield then
	function SetCVarBitfield(name, index, set)
		local value = tonumber(PaperDoll_GetCVar(name)) or 0;
		local bit = 2 ^ (index - 1);
		local has = (value % (bit * 2)) >= bit;
		if set and not has then
			value = value + bit;
		elseif not set and has then
			value = value - bit;
		end
		PaperDoll_SetCVar(name, value);
	end
end

-- надет ли сейчас комплект (в 3.3.5 GetEquipmentSetInfo этого не отдаёт)
function PaperDoll_IsEquipmentSetEquipped(name)
	if not name then
		return false;
	end
	local ids = GetEquipmentSetItemIDs(name);
	if not ids then
		return false;
	end
	local ignored = EQUIPMENT_SET_IGNORED_SLOT or 1;
	for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
		local id = ids[slot];
		if id and id ~= ignored then
			local equipped = GetInventoryItemID("player", slot) or 0;
			if id ~= equipped then
				return false;
			end
		end
	end
	return true;
end

---------------------------------------------------------------------------
-- Строки (в 3.3.5 их нет)
---------------------------------------------------------------------------

CHARACTERFRAME_PLAYER_LEVEL = "Уровень %d |c%s%s %s|r";
CHARACTERFRAME_PLAYER_LEVEL_NO_SPEC = "Уровень %d |c%s%s|r";

PAPERDOLL_SIDEBAR_STATS = PAPERDOLL_SIDEBAR_STATS or "Характеристики";
PAPERDOLL_SIDEBAR_TITLES = PAPERDOLL_SIDEBAR_TITLES or "Звания";
PAPERDOLL_EQUIPMENTMANAGER = PAPERDOLL_EQUIPMENTMANAGER or "Управление экипировкой";
PAPERDOLL_NEWEQUIPMENTSET = PAPERDOLL_NEWEQUIPMENTSET or "Новый комплект";
PLAYER_TITLE_NONE = PLAYER_TITLE_NONE or "Без звания";
EQUIPMENT_SET_EDIT = EQUIPMENT_SET_EDIT or "Изменить название/значок";
EQUIPMENT_SETS_CANT_RENAME = EQUIPMENT_SETS_CANT_RENAME or "Комплект с таким названием уже существует.";
EQUIPMENT_SET_ICON_NEEDS_EQUIP = "Значок комплекта можно сменить, только когда комплект надет.";
STATS_COLLAPSE_TOOLTIP = STATS_COLLAPSE_TOOLTIP or "Скрыть характеристики";
STATS_EXPAND_TOOLTIP = STATS_EXPAND_TOOLTIP or "Показать характеристики";
PET_STATS_COLLAPSE_TOOLTIP = PET_STATS_COLLAPSE_TOOLTIP or "Скрыть характеристики питомца";
PET_STATS_EXPAND_TOOLTIP = PET_STATS_EXPAND_TOOLTIP or "Показать характеристики питомца";
TRIAL_LEVEL_CAPPED = TRIAL_LEVEL_CAPPED or "";

STAT_CATEGORY_GENERAL = STAT_CATEGORY_GENERAL or "Общее";
STAT_CATEGORY_ATTRIBUTES = STAT_CATEGORY_ATTRIBUTES or "Характеристики";
STAT_CATEGORY_MELEE = STAT_CATEGORY_MELEE or "Ближний бой";
STAT_CATEGORY_RANGED = STAT_CATEGORY_RANGED or "Дальний бой";
STAT_CATEGORY_SPELL = STAT_CATEGORY_SPELL or "Заклинания";
STAT_CATEGORY_DEFENSE = STAT_CATEGORY_DEFENSE or "Защита";
STAT_CATEGORY_RESISTANCE = STAT_CATEGORY_RESISTANCE or "Сопротивления";

STAT_AVERAGE_ITEM_LEVEL = STAT_AVERAGE_ITEM_LEVEL or "Ур. предметов";
STAT_AVERAGE_ITEM_LEVEL_EQUIPPED = STAT_AVERAGE_ITEM_LEVEL_EQUIPPED or "(надето: %d)";
STAT_AVERAGE_ITEM_LEVEL_TOOLTIP = STAT_AVERAGE_ITEM_LEVEL_TOOLTIP or "Средний уровень надетых предметов.";
STAT_MOVEMENT_SPEED = STAT_MOVEMENT_SPEED or "Скорость";
STAT_MOVEMENT_GROUND_TOOLTIP = STAT_MOVEMENT_GROUND_TOOLTIP or "Скорость бега: %d%%";
STAT_MOVEMENT_FLIGHT_TOOLTIP = STAT_MOVEMENT_FLIGHT_TOOLTIP or "Скорость полёта: %d%%";
STAT_MOVEMENT_SWIM_TOOLTIP = STAT_MOVEMENT_SWIM_TOOLTIP or "Скорость плавания: %d%%";
STAT_HEALTH_TOOLTIP = STAT_HEALTH_TOOLTIP or "Максимальный запас здоровья. Если здоровье упадёт до нуля, вы погибнете.";
STAT_HEALTH_PET_TOOLTIP = STAT_HEALTH_PET_TOOLTIP or "Максимальный запас здоровья питомца.";
STAT_MANA_TOOLTIP = STAT_MANA_TOOLTIP or "Максимальный запас маны. Мана нужна для применения заклинаний.";
STAT_DPS_SHORT = STAT_DPS_SHORT or "УВС";
STAT_HASTE = STAT_HASTE or "Скорость";
STAT_HASTE_MELEE_TOOLTIP = STAT_HASTE_MELEE_TOOLTIP or "Повышает скорость атаки.";
STAT_HASTE_RANGED_TOOLTIP = STAT_HASTE_RANGED_TOOLTIP or "Повышает скорость атаки в дальнем бою.";
STAT_HASTE_SPELL_TOOLTIP = STAT_HASTE_SPELL_TOOLTIP or "Повышает скорость произнесения заклинаний.";
STAT_HASTE_BASE_TOOLTIP = STAT_HASTE_BASE_TOOLTIP or "\n\nРейтинг скорости: %d (+%.2f%% к скорости).";
STAT_HIT_CHANCE = STAT_HIT_CHANCE or "Меткость";
STAT_HIT_MELEE_TOOLTIP = STAT_HIT_MELEE_TOOLTIP or "Рейтинг меткости: %d (+%.2f%% к вероятности попадания)";
STAT_HIT_RANGED_TOOLTIP = STAT_HIT_RANGED_TOOLTIP or "Рейтинг меткости: %d (+%.2f%% к вероятности попадания)";
STAT_HIT_SPELL_TOOLTIP = STAT_HIT_SPELL_TOOLTIP or "Рейтинг меткости: %d (+%.2f%% к вероятности попадания заклинаниями)";
STAT_HIT_NORMAL_ATTACKS = STAT_HIT_NORMAL_ATTACKS or "Обычные атаки";
STAT_HIT_SPECIAL_ATTACKS = STAT_HIT_SPECIAL_ATTACKS or "Особые атаки";
STAT_TARGET_LEVEL = STAT_TARGET_LEVEL or "Уровень цели";
MISS_CHANCE = MISS_CHANCE or "Промах";
STAT_ENERGY_REGEN = STAT_ENERGY_REGEN or "Энергия";
STAT_ENERGY_REGEN_TOOLTIP = STAT_ENERGY_REGEN_TOOLTIP or "Скорость восполнения энергии в секунду.";
STAT_FOCUS_REGEN = STAT_FOCUS_REGEN or "Концентрация";
STAT_FOCUS_REGEN_TOOLTIP = STAT_FOCUS_REGEN_TOOLTIP or "Скорость восполнения концентрации в секунду.";
STAT_RUNE_REGEN = STAT_RUNE_REGEN or "Руны";
STAT_RUNE_REGEN_FORMAT = STAT_RUNE_REGEN_FORMAT or "%.2f сек.";
STAT_RUNE_REGEN_TOOLTIP = STAT_RUNE_REGEN_TOOLTIP or "Время восстановления руны.";
STAT_SPELLPOWER = STAT_SPELLPOWER or "Сила заклинаний";
STAT_SPELLPOWER_TOOLTIP = STAT_SPELLPOWER_TOOLTIP or "Увеличивает урон и лечение от заклинаний.";
STAT_SPELLDAMAGE = STAT_SPELLDAMAGE or "Урон";
STAT_SPELLDAMAGE_TOOLTIP = STAT_SPELLDAMAGE_TOOLTIP or "Увеличивает урон от заклинаний.";
STAT_SPELLHEALING = STAT_SPELLHEALING or "Лечение";
STAT_SPELLHEALING_TOOLTIP = STAT_SPELLHEALING_TOOLTIP or "Увеличивает лечение от заклинаний.";
STAT_TOOLTIP_BONUS_AP = STAT_TOOLTIP_BONUS_AP or "Увеличивает силу атаки на %d.|n";
STAT_USELESS_TOOLTIP = STAT_USELESS_TOOLTIP or "|cff808080Не даёт вашему классу никакой пользы.|r";
STAT4_NOSPELLPOWER_TOOLTIP = STAT4_NOSPELLPOWER_TOOLTIP or "Запас маны увеличен на %d.|nВероятность нанести критический удар заклинанием повышена на %.2f%%.";
MANA_REGEN_COMBAT = MANA_REGEN_COMBAT or "В бою";
MANA_COMBAT_REGEN_TOOLTIP = MANA_COMBAT_REGEN_TOOLTIP or "Восполнение %d ед. маны каждые 5 сек. в бою.";
MELEE_ATTACK_POWER_SPELL_POWER_TOOLTIP = MELEE_ATTACK_POWER_SPELL_POWER_TOOLTIP or "Увеличивает урон от оружия ближнего боя на %.1f ед. урона в секунду.|nСила заклинаний: %d.";
CR_CRIT_SPELL_TOOLTIP = CR_CRIT_SPELL_TOOLTIP or "Рейтинг критического удара: %d (вероятность нанесения +%.2f%%).";
PET_BONUS_TOOLTIP_WARLOCK_SPELLDMG = PET_BONUS_TOOLTIP_WARLOCK_SPELLDMG or "Увеличивает силу атаки питомца на %d и урон от его заклинаний на %d.";
DAMAGE_SCHOOL1 = DAMAGE_SCHOOL1 or "физический";
COMBAT_RATING_NAME1 = COMBAT_RATING_NAME1 or "Оружейный навык";
RESISTANCE_TOOLTIP_SUBTEXT_CATA = "Снижает урон от атак школы «%s» в среднем на %.1f%% (против цели %d-го уровня).";

-- Тексты подсказок характеристик в формате Каты (порядок аргументов другой, чем в 3.3.5)
PAPERDOLL_STAT_TOOLTIPS = {
	[1] = "Увеличивает силу атаки на %d.",
	[2] = "Вероятность нанести критический удар повышена на %.2f%%.",
	[3] = "Максимальный запас здоровья увеличен на %d.",
	[4] = "Запас маны увеличен на %d.|nСила заклинаний увеличена на %d.|nВероятность нанести критический удар заклинанием повышена на %.2f%%.",
	[5] = "Скорость восполнения здоровья увеличена.",
};
