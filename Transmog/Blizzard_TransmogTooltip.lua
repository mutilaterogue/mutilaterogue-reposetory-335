-- Трансмогрификация: строка «Предмет трансмогрифицирован в: ...» в подсказке предмета (всегда, не только в окне).
-- Сервер (transmog.cpp) присылает облики предметов персонажа по ячейкам:
--   "TMOG_ITEMS_GET" -> "TMOG_ITEMS" : "bag/slot/fakeEntry,..."   bag 255 - экипировка, 0 - рюкзак, 1..4 - сумки

local looks = {};          -- [bag][slot] = fakeEntry
local requestDelay;

local function AddLine(tooltip, fakeEntry)
	if not fakeEntry then
		return;
	end
	local name, _, quality = GetItemInfo(fakeEntry);
	if not name then
		TransmogUI.RequestItem(fakeEntry);
		name = "item:" .. fakeEntry;
	end
	-- ретейл: TRANSMOGRIFIED = "Предмет трансмогрифицирован в:\n%s", цвет TRANSMOGRIFY_FONT_COLOR (1, 0.5, 1)
	for line in TRANSMOGRIFIED:format(name):gmatch("[^\n]+") do
		tooltip:AddLine(line, 1, 0.5, 1, true);
	end
	tooltip:Show();
end

hooksecurefunc(GameTooltip, "SetInventoryItem", function(self, unit, slot)
	if unit == "player" and looks[255] then
		AddLine(self, looks[255][slot]);
	end
end);

hooksecurefunc(GameTooltip, "SetBagItem", function(self, bag, slot)
	if looks[bag] then
		AddLine(self, looks[bag][slot]);
	end
end);

-- после перекладывания предметов ячейки меняются - спросить заново (с задержкой, BAG_UPDATE приходит пачкой)
local watcher = CreateFrame("Frame");
watcher:RegisterEvent("BAG_UPDATE");
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
watcher:RegisterEvent("PLAYER_ENTERING_WORLD");
watcher:SetScript("OnEvent", function()
	requestDelay = 0.5;
end);
watcher:SetScript("OnUpdate", function(self, elapsed)
	if requestDelay then
		requestDelay = requestDelay - elapsed;
		if requestDelay <= 0 then
			requestDelay = nil;
			if Comm_Send then
				Comm_Send("TMOG_ITEMS_GET");
			end
		end
	end
end);

if Comm_Register then
	Comm_Register("TMOG_ITEMS", function(text)
		wipe(looks);
		for bag, slot, fake in (text or ""):gmatch("(%d+)/(%d+)/(%d+)") do
			bag = tonumber(bag);
			looks[bag] = looks[bag] or {};
			looks[bag][tonumber(slot)] = tonumber(fake);
		end
	end);
end
