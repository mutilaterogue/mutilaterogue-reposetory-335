-- Археология: полоса места раскопок, «Исследование» и места раскопок на карте мира (server/archaeology.cpp)
--   «Исследовать» (80451) на сервере                -> телескоп / находка, "ARCH_DIGSITE" : site : finds : max
--   "ARCH_ENTER" : site : finds : max, "ARCH_LEAVE" - вход и выход из места раскопок
--   "ARCH_SITES_GET" -> "ARCH_SITE" : site : zoneName : x : y : finds (x, y - 0..10000 на карте зоны), "ARCH_SITES_END"

local digSites = {};    -- { site, zone, x, y, finds }
local incoming;
local pins = {};

-- «Исследовать» (80451): кнопка на полосе - защищённая кнопка заклинания (вне боя)
ARCHAEOLOGY_SURVEY_SPELL = 80451;
local surveyInit = CreateFrame("Frame");
surveyInit:RegisterEvent("PLAYER_LOGIN");
surveyInit:SetScript("OnEvent", function()
	local button = ArchaeologyDigsiteFrame.SurveyButton;
	local name = GetSpellInfo(ARCHAEOLOGY_SURVEY_SPELL);
	if name and not InCombatLockdown() then
		button:SetAttribute("type", "spell");
		button:SetAttribute("spell", name);
	end
end);

local function SiteName(siteId)
	local site = ARCHAEOLOGY_SITES and ARCHAEOLOGY_SITES[tonumber(siteId)];
	return site and site.name or ARCHAEOLOGY_DIG_HELP;
end

local function ShowDigsite(siteId, finds, max)
	local frame = ArchaeologyDigsiteFrame;
	frame.Title:SetText(SiteName(siteId));
	frame.Bar:SetMinMaxValues(0, tonumber(max) or 3);
	frame.Bar:SetValue(tonumber(finds) or 0);
	frame.Bar.Text:SetFormattedText("%d/%d", tonumber(finds) or 0, tonumber(max) or 3);
	ArchaeologyDigsite_SetShown(true);
end

-- в полосе защищённая кнопка: в бою показывать/прятать нельзя - после боя
local pendingShown;
function ArchaeologyDigsite_SetShown(shown)
	if InCombatLockdown() then
		pendingShown = shown;
		return;
	end
	pendingShown = nil;
	if shown then
		ArchaeologyDigsiteFrame:Show();
	else
		ArchaeologyDigsiteFrame:Hide();
	end
end

local combatWatcher = CreateFrame("Frame");
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED");
combatWatcher:SetScript("OnEvent", function()
	if pendingShown ~= nil then
		ArchaeologyDigsite_SetShown(pendingShown);
	end
end);

---------------------------------------------------------------------------
-- карта мира: лопата на месте раскопок текущей зоны
---------------------------------------------------------------------------
local function CurrentZoneName()
	local continent, zone = GetCurrentMapContinent(), GetCurrentMapZone();
	if not continent or continent < 1 or not zone or zone < 1 then
		return nil;
	end
	return (select(zone, GetMapZones(continent)));
end

local function GetPin(index)
	local pin = pins[index];
	if not pin then
		pin = CreateFrame("Frame", nil, WorldMapButton);
		pin:SetSize(20, 20);
		pin:EnableMouse(true);
		pin.icon = pin:CreateTexture(nil, "OVERLAY");
		pin.icon:SetAllPoints();
		pin.icon:SetTexture("Interface\\Icons\\INV_Misc_Shovel_01");
		pin:SetScript("OnEnter", function(self)
			WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT");
			WorldMapTooltip:SetText(SiteName(self.site));
			WorldMapTooltip:AddLine(("Находки: %d/3"):format(self.finds or 0), 1, 1, 1);
			WorldMapTooltip:Show();
		end);
		pin:SetScript("OnLeave", function() WorldMapTooltip:Hide(); end);
		pins[index] = pin;
	end
	return pin;
end

function ArchaeologyMap_Update()
	for _, pin in ipairs(pins) do
		pin:Hide();
	end
	if not WorldMapButton or not WorldMapButton:IsVisible() then
		return;
	end
	local zoneName = CurrentZoneName();
	if not zoneName then
		return;
	end
	local width, height = WorldMapButton:GetWidth(), WorldMapButton:GetHeight();
	local index = 0;
	for _, site in ipairs(digSites) do
		if site.zone == zoneName then
			index = index + 1;
			local pin = GetPin(index);
			pin.site, pin.finds = site.site, site.finds;
			pin:ClearAllPoints();
			pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", site.x / 10000 * width, -site.y / 10000 * height);
			pin:SetFrameLevel(WorldMapButton:GetFrameLevel() + 5);
			pin:Show();
		end
	end
end

local mapWatcher = CreateFrame("Frame");
mapWatcher:RegisterEvent("WORLD_MAP_UPDATE");
mapWatcher:SetScript("OnEvent", ArchaeologyMap_Update);

---------------------------------------------------------------------------
-- сервер
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register("ARCH_ENTER", function(siteId, finds, max)
		ShowDigsite(siteId, finds, max);
	end);

	Comm_Register("ARCH_LEAVE", function()
		ArchaeologyDigsite_SetShown(false);
	end);

	Comm_Register("ARCH_DIGSITE", function(siteId, finds, max)
		ShowDigsite(siteId, finds, max);
	end);

	Comm_Register("ARCH_SITE", function(siteId, zone, x, y, finds)
		incoming = incoming or {};
		table.insert(incoming, { site = tonumber(siteId), zone = zone, x = tonumber(x) or 0, y = tonumber(y) or 0, finds = tonumber(finds) or 0 });
	end);

	Comm_Register("ARCH_SITES_END", function()
		digSites = incoming or {};
		incoming = nil;
		ArchaeologyMap_Update();
	end);
end
