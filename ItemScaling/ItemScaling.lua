-- Скейлинг предметов: подсказки (server/item_scaling.cpp).
-- Характеристики экземпляра с бонусом к уровню сервер присылает кэшем предмета (как Reforger), родная
-- подсказка показывает их сама. Кэш клиента - по номеру предмета, поэтому при наведении на экземпляр
-- с другим бонусом, чем уже в кэше, просим сервер прислать кэш для него и перерисовываем подсказку.
-- Плюс строка «Уровень предмета» (в 3.3.5 её нет).
-- Подключение: FrameXML.toc - ItemScaling\ItemScaling.lua (после GameTooltip.lua)
--   "ISCALE_CONFIG" : statStep : armorStep : damageStep (x1000000)
--   "ISCALE_ITEMS_GET" -> "ISCALE_ITEMS" : "bag/slot/bonus,..."   (bag 255 - экипировка и банк, 0 - рюкзак, 1..4, 5..11 - банк)
--   "ISCALE_SHOW" : bag : slot

ITEM_LEVEL = ITEM_LEVEL or "Уровень предмета %d";

ItemScaling = { bonuses = {}, cached = {}, config = nil };
local bonuses, cached = ItemScaling.bonuses, ItemScaling.cached;   -- [bag][slot] = бонус; [itemId] = бонус в кэше клиента

function ItemScaling.GetBonus(bag, slot)
	return bonuses[bag] and bonuses[bag][slot] or 0;
end

local function ItemIdFromLink(link)
	return link and tonumber(link:match("item:(%d+)"));
end

-- перерисовать подсказку, когда придёт кэш
local refresh = CreateFrame("Frame");
refresh:Hide();
refresh:SetScript("OnUpdate", function(self, elapsed)
	self.delay = self.delay - elapsed;
	if self.delay > 0 then
		return;
	end
	self:Hide();
	local tooltip, redo = self.tooltip, self.redo;
	self.tooltip, self.redo = nil, nil;
	if tooltip and redo and tooltip:IsShown() and tooltip:GetOwner() == self.owner then
		redo();
	end
end);

local function Refresh(tooltip, redo)
	refresh.tooltip, refresh.redo, refresh.owner = tooltip, redo, tooltip:GetOwner();
	refresh.delay = 0.25;
	refresh:Show();
end

-- кэш этого номера предмета не для этого экземпляра - попросить нужный
local function EnsureCache(tooltip, itemId, bag, slot, redo)
	if not itemId or not Comm_Send then
		return;
	end
	local bonus = ItemScaling.GetBonus(bag, slot);
	if (cached[itemId] or 0) ~= bonus then
		cached[itemId] = bonus;
		Comm_Send("ISCALE_SHOW", bag, slot);
		Refresh(tooltip, redo);
	end
end

local function AddItemLevel(tooltip, link)
	if not link then
		return;
	end
	local _, _, _, itemLevel, _, _, _, _, equipLoc = GetItemInfo(link);
	if itemLevel and itemLevel > 1 and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
		-- the tooltip may already show the item level (client patch / other addon) - no duplicate
		local prefix = ITEM_LEVEL:match("^(.-)%%d") or ITEM_LEVEL;
		local name = tooltip:GetName();
		for i = 2, tooltip:NumLines() do
			local line = _G[name .. "TextLeft" .. i];
			local text = line and line:GetText();
			if text and text:find(prefix, 1, true) then
				return;
			end
		end
		tooltip:AddLine(ITEM_LEVEL:format(itemLevel), 1, 0.82, 0);
		tooltip:Show();
	end
end

local function OnInventoryItem(self, unit, slot)
	if unit ~= "player" then
		return;
	end
	local link = GetInventoryItemLink("player", slot);
	EnsureCache(self, ItemIdFromLink(link), 255, slot, function() self:SetInventoryItem("player", slot); end);
	AddItemLevel(self, link);
end

local function OnBagItem(self, bag, slot)
	local link = GetContainerItemLink(bag, slot);
	EnsureCache(self, ItemIdFromLink(link), bag, slot, function() self:SetBagItem(bag, slot); end);
	AddItemLevel(self, link);
end

-- окно сравнения: надетый предмет находим по ссылке
local function OnCompareItem(self)
	local _, link = self:GetItem();
	if not link then
		return;
	end
	for slot = 1, 19 do
		if GetInventoryItemLink("player", slot) == link then
			AddItemLevel(self, link);
			return;
		end
	end
end

local init = CreateFrame("Frame");
init:RegisterEvent("PLAYER_LOGIN");
init:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN");
	hooksecurefunc(GameTooltip, "SetInventoryItem", OnInventoryItem);
	hooksecurefunc(GameTooltip, "SetBagItem", OnBagItem);
	for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3" }) do
		if _G[name] then
			_G[name]:HookScript("OnTooltipSetItem", OnCompareItem);
		end
	end
end);

-- перекладывание предметов меняет ячейки - спросить заново (BAG_UPDATE приходит пачкой)
local watcher = CreateFrame("Frame");
watcher:RegisterEvent("BAG_UPDATE");
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
watcher:RegisterEvent("PLAYERBANKSLOTS_CHANGED");
watcher:RegisterEvent("BANKFRAME_OPENED");
watcher:SetScript("OnEvent", function(self)
	self.delay = 0.5;
	self:Show();
end);
watcher:Hide();
watcher:SetScript("OnUpdate", function(self, elapsed)
	self.delay = self.delay - elapsed;
	if self.delay <= 0 then
		self:Hide();
		if Comm_Send then
			Comm_Send("ISCALE_ITEMS_GET");
		end
	end
end);

if Comm_Register then
	Comm_Register("ISCALE_CONFIG", function(stat, armor, damage)
		ItemScaling.config = {
			stat = (tonumber(stat) or 1000000) / 1000000,
			armor = (tonumber(armor) or 1000000) / 1000000,
			damage = (tonumber(damage) or 1000000) / 1000000,
		};
	end);

	Comm_Register("ISCALE_ITEMS", function(text)
		wipe(bonuses);
		for bag, slot, bonus in (text or ""):gmatch("(%d+)/(%d+)/(%-?%d+)") do
			bag = tonumber(bag);
			bonuses[bag] = bonuses[bag] or {};
			bonuses[bag][tonumber(slot)] = tonumber(bonus);
		end
	end);
end
