-- Константы счётчика (из ретейлового DamageMeterConstants.lua).
DAMAGE_METER_DEFAULT_BAR_HEIGHT = 20;
DAMAGE_METER_DEFAULT_BAR_SPACING = 2;
DAMAGE_METER_TEXT_SIZE_TO_SCALE_MULTIPLIER = 0.01;
DAMAGE_METER_TRANSPARENCY_TO_ALPHA_MULTIPLIER = 0.01;

-- Категории и типы: подписи берутся из GlobalStrings (DAMAGE_METER_*)
DamageMeterCategories = {
	{
		label = DAMAGE_METER_CATEGORY_DAMAGE,
		types = {
			{ type = Enum.DamageMeterType.DamageDone, label = DAMAGE_METER_TYPE_DAMAGE_DONE },
			{ type = Enum.DamageMeterType.Dps, label = DAMAGE_METER_TYPE_DPS },
			{ type = Enum.DamageMeterType.DamageTaken, label = DAMAGE_METER_TYPE_DAMAGE_TAKEN },
			{ type = Enum.DamageMeterType.EnemyDamageTaken, label = DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN },
		},
	},
	{
		label = DAMAGE_METER_CATEGORY_HEALING,
		types = {
			{ type = Enum.DamageMeterType.HealingDone, label = DAMAGE_METER_TYPE_HEALING_DONE },
			{ type = Enum.DamageMeterType.Hps, label = DAMAGE_METER_TYPE_HPS },
			{ type = Enum.DamageMeterType.Absorbs, label = DAMAGE_METER_TYPE_ABSORBS },
		},
	},
	{
		label = DAMAGE_METER_CATEGORY_ACTIONS,
		types = {
			{ type = Enum.DamageMeterType.Interrupts, label = DAMAGE_METER_TYPE_INTERRUPTS },
			{ type = Enum.DamageMeterType.Dispels, label = DAMAGE_METER_TYPE_DISPELS },
			{ type = Enum.DamageMeterType.Deaths, label = DAMAGE_METER_TYPE_DEATHS },
		},
	},
};

-- плоский список: тип -> подпись
DamageMeterTypes = {};
for _, category in ipairs(DamageMeterCategories) do
	for _, entry in ipairs(category.types) do
		table.insert(DamageMeterTypes, entry);
	end
end

function DamageMeter_GetTypeLabel(damageMeterType)
	for _, entry in ipairs(DamageMeterTypes) do
		if entry.type == damageMeterType then
			return entry.label;
		end
	end
	return "";
end

function DamageMeter_GetSessionLabel(sessionType)
	if sessionType == Enum.DamageMeterSessionType.Overall then
		return DAMAGE_METER_OVERALL_SESSION, DAMAGE_METER_OVERALL_SESSION_SHORT;
	end
	return DAMAGE_METER_CURRENT_SESSION, DAMAGE_METER_CURRENT_SESSION_SHORT;
end

function DamageMeter_FormatAmount(amount)
	amount = amount or 0;
	if amount >= 1000000 then
		return format("%.1fМ", amount / 1000000);
	elseif amount >= 1000 then
		return format("%.1fК", amount / 1000);
	end
	return tostring(math.floor(amount + 0.5));
end
