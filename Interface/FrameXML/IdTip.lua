-- IdTip для FrameXML (3.3.5): ID заклинаний, предметов, NPC, заданий, достижений и символов в подсказках.
-- В отличие от аддона IdTip строки с ID всегда в самом низу подсказки - после строки трансмогрификации
-- и всего, что дописывают другие хуки: ID собираются и дописываются, когда подсказка уже заполнена.
-- Подключение: в FrameXML.toc после GameTooltip.lua / ItemRef.lua - IdTip.lua

local select, tonumber, UnitAura, UnitExists, UnitIsUnit, UnitClass, UnitName, UnitGUID =
      select, tonumber, UnitAura, UnitExists, UnitIsUnit, UnitClass, UnitName, UnitGUID

local TYPES = {
	spell       = "Spell ID:",
	item        = "Item ID:",
	unit        = "NPC ID:",
	quest       = "Quest ID:",
	talent      = "Talent ID:",
	achievement = "Achievement ID:",
	criteria    = "Criteria ID:",
	glyph       = "Glyph Spell ID:",
};

---------------------------------------------------------------------------
-- отложенные строки: [tooltip] = { { left, right, r, g, b, r2, g2, b2 }, ... }
---------------------------------------------------------------------------
local pending = {};
local flusher = CreateFrame("Frame");
flusher:Hide();

local function Flush()
	for tooltip, lines in pairs(pending) do
		if tooltip:IsShown() then
			for _, line in ipairs(lines) do
				tooltip:AddDoubleLine(line[1], line[2], line[3], line[4], line[5], line[6], line[7], line[8]);
			end
			tooltip:Show();
		end
		pending[tooltip] = nil;
	end
	flusher:Hide();
end
flusher:SetScript("OnUpdate", Flush);

local function Queue(tooltip, left, right, r, g, b, r2, g2, b2)
	local lines = pending[tooltip];
	if not lines then
		lines = {};
		pending[tooltip] = lines;
	end
	for _, line in ipairs(lines) do
		if line[1] == left then
			return;   -- уже есть (подсказки талантов обновляются несколько раз)
		end
	end
	table.insert(lines, { left, right, r or 1, g or 0.82, b or 0, r2 or 1, g2 or 1, b2 or 1 });
	flusher:Show();   -- дописать в следующем кадре, когда все хуки уже отработали
end

local function AddId(tooltip, id, kind)
	if id then
		Queue(tooltip, kind, "|cffffffff" .. id .. "|r");
	end
end

-- новая подсказка - старые отложенные строки не нужны
local function Cleared(tooltip)
	pending[tooltip] = nil;
end

-- FrameXML грузится раньше, чем создаются GameTooltip/ItemRefTooltip/ShoppingTooltip (они в XML ниже по .toc),
-- поэтому хуки ставятся на PLAYER_LOGIN, когда все подсказки уже существуют
local function Init()
local tooltips = { GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2, ShoppingTooltip3,
	ItemRefShoppingTooltip1, ItemRefShoppingTooltip2, ItemRefShoppingTooltip3 };
for _, tooltip in ipairs(tooltips) do
	if tooltip then
		tooltip:HookScript("OnTooltipCleared", Cleared);
		tooltip:HookScript("OnHide", Cleared);
	end
end

---------------------------------------------------------------------------
-- ссылки (чат, отдельная подсказка)
---------------------------------------------------------------------------
local function OnSetHyperlink(self, link)
	local kind, id = string.match(link or "", "^(%a+):(%d+)");
	if not kind then
		kind, id = string.match(link or "", "|H(%a+):(%d+)");
	end
	if not kind or not id then
		return;
	end
	if kind == "spell" or kind == "enchant" or kind == "trade" then
		AddId(self, id, TYPES.spell);
	elseif kind == "talent" then
		AddId(self, id, TYPES.talent);
	elseif kind == "quest" then
		AddId(self, id, TYPES.quest);
	elseif kind == "achievement" then
		AddId(self, id, TYPES.achievement);
	end
	-- item - через OnTooltipSetItem ниже
end
hooksecurefunc(ItemRefTooltip, "SetHyperlink", OnSetHyperlink);
hooksecurefunc(GameTooltip, "SetHyperlink", OnSetHyperlink);

---------------------------------------------------------------------------
-- ауры: ID и кто наложил
---------------------------------------------------------------------------
local function HandleAura(self, ...)
	local _, rank, _, _, _, _, _, source, _, _, id = UnitAura(...);
	if not id then
		return;
	end
	local left = "ID: |cffffffff" .. id .. "|r" .. ((rank and rank:match("%d+")) and " |cffaaaaaa(" .. rank .. ")|r" or "");
	local right = "";
	local r, g, b = 1, 0.82, 0;
	if source then
		local owner = UnitIsUnit(source, "pet") and "player" or source:gsub("[pP][eE][tT]", "");
		if UnitExists(owner) then
			local classColor = RAID_CLASS_COLORS[(select(2, UnitClass(owner)))];
			if classColor then
				r, g, b = classColor.r, classColor.g, classColor.b;
			end
			right = (owner == source and "%s" or "%s (%s)"):format(UnitName(owner), UnitName(source));
		end
	end
	Queue(self, left, right, 1, 0.82, 0, r, g, b);
end
hooksecurefunc(GameTooltip, "SetUnitBuff", HandleAura);
hooksecurefunc(GameTooltip, "SetUnitDebuff", HandleAura);
hooksecurefunc(GameTooltip, "SetUnitAura", HandleAura);

hooksecurefunc("SetItemRef", function(link)
	local id = tonumber((link or ""):match("spell:(%d+)"));
	if id then
		AddId(ItemRefTooltip, id, TYPES.spell);
	end
end);

GameTooltip:HookScript("OnTooltipSetSpell", function(self)
	local id = select(3, self:GetSpell());
	AddId(self, id, TYPES.spell);
end);

---------------------------------------------------------------------------
-- NPC
---------------------------------------------------------------------------
GameTooltip:HookScript("OnTooltipSetUnit", function(self)
	local unit = select(2, self:GetUnit());
	local guid = unit and UnitGUID(unit);
	if guid then
		local id = tonumber(guid:sub(-10, -7), 16);
		if id and id > 0 then
			AddId(self, id, TYPES.unit);
		end
	end
end);

---------------------------------------------------------------------------
-- предметы (сумки, персонаж, ссылки, сравнение)
---------------------------------------------------------------------------
local function OnTooltipSetItem(self)
	local link = select(2, self:GetItem());
	local id = link and link:match("item:(%d+)");
	if id and id ~= "0" then
		AddId(self, id, TYPES.item);
	end
end
for _, tooltip in ipairs(tooltips) do
	if tooltip then
		tooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem);
	end
end

---------------------------------------------------------------------------
-- символы
---------------------------------------------------------------------------
hooksecurefunc(GameTooltip, "SetGlyph", function(self, glyphIndex)
	local _, _, spellID = GetGlyphSocketInfo(glyphIndex, 1);
	if spellID and _G[self:GetName() .. "TextLeft1"]:GetText() ~= GetSpellInfo(spellID) then
		_, _, spellID = GetGlyphSocketInfo(glyphIndex, 2);   -- символ второй специализации
	end
	AddId(self, spellID, TYPES.glyph);
end);

---------------------------------------------------------------------------
-- задания (журнал)
---------------------------------------------------------------------------
hooksecurefunc("SelectQuestLogEntry", function()
	if not (QuestLogFrame:IsVisible() and QuestLogHighlightFrame and QuestLogHighlightFrame:IsMouseOver()) then
		return;
	end
	local index = GetQuestLogSelection();
	local link = index and GetQuestLink(index);
	local id = link and tonumber(link:match(":(%d+):"));
	if id then
		GameTooltip:SetOwner(QuestLogScrollFrame, "ANCHOR_NONE");
		GameTooltip:SetPoint("TOPLEFT", QuestLogScrollFrame, "TOPRIGHT", 0, 0);
		GameTooltip:Show();
		AddId(GameTooltip, id, TYPES.quest);
	end
end);

end

local initFrame = CreateFrame("Frame");
initFrame:RegisterEvent("PLAYER_LOGIN");
initFrame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN");
	Init();
end);

---------------------------------------------------------------------------
-- достижения (Blizzard_AchievementUI загружается по требованию)
---------------------------------------------------------------------------
local achievementLoader = CreateFrame("Frame");
achievementLoader:RegisterEvent("ADDON_LOADED");
achievementLoader:SetScript("OnEvent", function(self, _, addon)
	if addon ~= "Blizzard_AchievementUI" then
		return;
	end
	self:UnregisterEvent("ADDON_LOADED");

	for _, button in ipairs(AchievementFrameAchievementsContainer.buttons) do
		button:HookScript("OnEnter", function()
			GameTooltip:SetOwner(button, "ANCHOR_NONE");
			GameTooltip:SetPoint("TOPLEFT", button, "TOPRIGHT", 0, 0);
			GameTooltip:Show();
			AddId(GameTooltip, button.id, TYPES.achievement);
		end);
		button:HookScript("OnLeave", function()
			GameTooltip:Hide();
		end);
	end

	local hooked = {};
	hooksecurefunc("AchievementButton_GetCriteria", function(index, renderOffScreen)
		local frame = _G["AchievementFrameCriteria" .. (renderOffScreen and "OffScreen" or "") .. index];
		if not frame or hooked[frame] then
			return;
		end
		hooked[frame] = true;
		frame:HookScript("OnEnter", function(criteria)
			local button = criteria:GetParent() and criteria:GetParent():GetParent();
			if not button or not button.id then
				return;
			end
			local criteriaId = select(10, GetAchievementCriteriaInfo(button.id, index));
			if criteriaId then
				GameTooltip:SetOwner(button:GetParent(), "ANCHOR_NONE");
				GameTooltip:SetPoint("TOPLEFT", button, "TOPRIGHT", 0, 0);
				GameTooltip:Show();
				AddId(GameTooltip, button.id, TYPES.achievement);
				AddId(GameTooltip, criteriaId, TYPES.criteria);
			end
		end);
		frame:HookScript("OnLeave", function()
			GameTooltip:Hide();
		end);
	end);
end);
