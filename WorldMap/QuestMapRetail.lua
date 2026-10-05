-- QuestMapRetail.lua: the Legion quest panel (QuestMapFrame) on the 3.3.5 world map.
-- In FrameXML.toc after WorldMapFrame.xml: ..\..\WorldMap\QuestMapRetail.lua (or the path you keep it at).
--
-- The big map in the quest list mode (WORLDMAP_QUESTLIST_SIZE) keeps the stock 3.3.5 parts: the quest POIs,
-- the blobs, the numbered quest list (WorldMapQuestScrollFrame) and the selection. What changes, like Legion:
--   * the list and the details live in one panel to the right of the map (QuestLogBackground);
--   * a click on a quest (list or map POI) opens its details in that panel (the whole quest log text and
--     the rewards), with Back, Abandon, Share and Track; the stock detail / reward boxes under the map are off.

local QM = CreateFrame("Frame", "QuestMapRetailFrame", WorldMapFrame);
QM:Hide();

local PANEL_WIDTH = 318;
local CONTENT_WIDTH = 285;	-- QUEST_TEMPLATE_LOG's

local function SetAtlasIf(texture, atlas)
	if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas);
		return true;
	end
	return false;
end

-- the quest log index of a quest id (indices move when quests are added / removed)
local function QuestLogIndexByID(questID)
	if not questID or questID == 0 then
		return nil;
	end
	if GetQuestLogIndexByID then
		local index = GetQuestLogIndexByID(questID);
		if index and index > 0 then
			return index;
		end
	end
	for i = 1, GetNumQuestLogEntries() do
		local link = GetQuestLink(i);
		if link and tonumber(link:match("quest:(%d+)")) == questID then
			return i;
		end
	end
	return nil;
end

---------------------------------------------------------------------------
-- the panel
---------------------------------------------------------------------------
QM.Background = QM:CreateTexture(nil, "BACKGROUND");
QM.Background:SetAllPoints(QM);
if not SetAtlasIf(QM.Background, "QuestLogBackground") then
	QM.Background:SetTexture("Interface\\QuestFrame\\QuestBG");
end

QM.Divider = QM:CreateTexture(nil, "ARTWORK");
QM.Divider:SetPoint("TOPRIGHT", QM, "TOPLEFT", 4, 0);
QM.Divider:SetPoint("BOTTOMRIGHT", QM, "BOTTOMLEFT", 4, 0);
QM.Divider:SetWidth(8);
if not SetAtlasIf(QM.Divider, "QuestLog-frame-devider") then
	QM.Divider:Hide();
end

-- list view: a header over the stock numbered list
QM.ListHeader = QM:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
QM.ListHeader:SetPoint("TOPLEFT", 14, -10);
QM.ListHeader:SetPoint("RIGHT", -14, 0);
QM.ListHeader:SetJustifyH("LEFT");
QM.ListHeader:SetText(QUEST_LOG or "Задания");

-- details view
local details = CreateFrame("Frame", nil, QM);
details:SetAllPoints(QM);
details:Hide();
QM.Details = details;

details.Back = CreateFrame("Button", nil, details, "UIPanelButtonTemplate");
details.Back:SetWidth(90);
details.Back:SetHeight(22);
details.Back:SetPoint("TOPLEFT", 8, -8);
details.Back:SetText(BACK or "Назад");
details.Back:SetScript("OnClick", function()
	PlaySound("igMainMenuOptionCheckBoxOn");
	QM.ShowList();
end);

local scroll = CreateFrame("ScrollFrame", "QuestMapRetailDetailScrollFrame", details, "UIPanelScrollFrameTemplate");
scroll:SetPoint("TOPLEFT", 8, -38);
scroll:SetPoint("BOTTOMRIGHT", -28, 40);
local child = CreateFrame("Frame", "QuestMapRetailDetailScrollChildFrame", scroll);
child:SetWidth(CONTENT_WIDTH);
child:SetHeight(10);
scroll:SetScrollChild(child);
details.Scroll, details.Child = scroll, child;

local function BottomButton(text, width)
	local button = CreateFrame("Button", nil, details, "UIPanelButtonTemplate");
	button:SetWidth(width);
	button:SetHeight(22);
	button:SetText(text);
	return button;
end
details.Abandon = BottomButton(ABANDON_QUEST_ABBREV or ABANDON_QUEST or "Отказаться", 96);
details.Abandon:SetPoint("BOTTOMLEFT", 8, 10);
details.Share = BottomButton(SHARE_QUEST_ABBREV or SHARE_QUEST or "Поделиться", 96);
details.Share:SetPoint("LEFT", details.Abandon, "RIGHT", 2, 0);
details.Track = BottomButton(TRACK_QUEST_ABBREV or TRACK_QUEST or "Отслеживать", 96);
details.Track:SetPoint("LEFT", details.Share, "RIGHT", 2, 0);

---------------------------------------------------------------------------
-- views
---------------------------------------------------------------------------
-- the details' height: down to the lowest shown QuestInfo part (laid out a frame later)
local function FitChild()
	local top = child:GetTop();
	if not top then
		return;
	end
	local bottom = top;
	for _, region in ipairs({ child:GetChildren() }) do
		if region:IsShown() and region:GetBottom() then
			bottom = math.min(bottom, region:GetBottom());
		end
	end
	for _, region in ipairs({ child:GetRegions() }) do
		if region:IsShown() and region:GetBottom() then
			bottom = math.min(bottom, region:GetBottom());
		end
	end
	child:SetHeight(math.max(10, top - bottom + 12));
	ScrollFrame_OnScrollRangeChanged(scroll);
end

local fitter = CreateFrame("Frame");
fitter:Hide();
fitter:SetScript("OnUpdate", function(self)
	self:Hide();
	FitChild();
end);

function QM.UpdateButtons()
	local index = QuestLogIndexByID(QM.questID);
	if not index then
		return;
	end
	if IsQuestWatched(index) then
		details.Track:SetText(UNTRACK_QUEST_ABBREV or UNTRACK_QUEST or "Не отслеживать");
	else
		details.Track:SetText(TRACK_QUEST_ABBREV or TRACK_QUEST or "Отслеживать");
	end
	SelectQuestLogEntry(index);
	if GetQuestLogPushable() and (GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0) then
		details.Share:Enable();
	else
		details.Share:Disable();
	end
end

-- the quest's whole log text and rewards in the panel (3.3.5 QuestInfo, the quest log template)
function QM.ShowDetails(questID)
	local index = QuestLogIndexByID(questID);
	if not index then
		QM.ShowList();
		return;
	end
	QM.questID = questID;
	SelectQuestLogEntry(index);
	QuestInfo_Display(QUEST_TEMPLATE_LOG, child);
	scroll:SetVerticalScroll(0);
	fitter:Show();
	QM.UpdateButtons();
	WorldMapQuestScrollFrame:Hide();
	QM.ListHeader:Hide();
	details:Show();
end

function QM.ShowList()
	QM.questID = nil;
	details:Hide();
	QM.ListHeader:Show();
	WorldMapQuestScrollFrame:Show();
end

details.Abandon:SetScript("OnClick", function()
	local index = QuestLogIndexByID(QM.questID);
	if not index then
		return;
	end
	SelectQuestLogEntry(index);
	SetAbandonQuest();
	local items = GetAbandonQuestItems();
	if items then
		StaticPopup_Hide("ABANDON_QUEST");
		StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", GetAbandonQuestName(), items);
	else
		StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS");
		StaticPopup_Show("ABANDON_QUEST", GetAbandonQuestName());
	end
end);

details.Share:SetScript("OnClick", function()
	local index = QuestLogIndexByID(QM.questID);
	if index then
		SelectQuestLogEntry(index);
		QuestLogPushQuest();
		PlaySound("igQuestLogOpen");
	end
end);

details.Track:SetScript("OnClick", function()
	local index = QuestLogIndexByID(QM.questID);
	if not index then
		return;
	end
	if IsQuestWatched(index) then
		RemoveQuestWatch(index);
	elseif GetNumQuestWatches() >= MAX_WATCHABLE_QUESTS then
		UIErrorsFrame:AddMessage(format(QUEST_WATCH_TOO_MANY, MAX_WATCHABLE_QUESTS), 1.0, 0.1, 0.1, 1.0);
		return;
	else
		AddQuestWatch(index);
	end
	WatchFrame_Update();
	if WatchFrame.showObjectives then
		WorldMapFrame_DisplayQuests(QM.questID);
	end
	QM.UpdateButtons();
end);

---------------------------------------------------------------------------
-- on the stock map
---------------------------------------------------------------------------
-- the panel where the stock list was, the list moved into it; the stock boxes under the map off
function QM.Layout()
	QM:ClearAllPoints();
	QM:SetPoint("TOPLEFT", WorldMapDetailFrame, "TOPRIGHT", 6, 0);
	QM:SetWidth(PANEL_WIDTH);
	QM:SetHeight(WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale());
	QM:SetFrameLevel(WorldMapDetailFrame:GetFrameLevel() + 20);

	WorldMapQuestScrollFrame:SetParent(QM);
	WorldMapQuestScrollFrame:ClearAllPoints();
	WorldMapQuestScrollFrame:SetPoint("TOPLEFT", QM, "TOPLEFT", 4, -36);
	WorldMapQuestScrollFrame:SetPoint("BOTTOMRIGHT", QM, "BOTTOMRIGHT", -28, 8);

	WorldMapQuestDetailScrollFrame:Hide();
	WorldMapQuestRewardScrollFrame:Hide();
	WorldMapTrackQuest:Hide();
end

local function OnQuestView()
	QM.Layout();
	QM:Show();
	if QM.questID then
		QM.ShowDetails(QM.questID);
	else
		QM.ShowList();
	end
end

local function OffQuestView()
	QM:Hide();
end

hooksecurefunc("WorldMapFrame_SetQuestMapView", OnQuestView);
hooksecurefunc("WorldMap_ToggleSizeUp", function()
	if WORLDMAP_SETTINGS.size == WORLDMAP_QUESTLIST_SIZE then
		OnQuestView();
	end
end);
hooksecurefunc("WorldMapFrame_SetFullMapView", OffQuestView);
hooksecurefunc("WorldMap_ToggleSizeDown", OffQuestView);

-- the stock selection puts the QuestInfo parts into its own boxes: back into the panel while the details show
hooksecurefunc("WorldMapFrame_SelectQuestFrame", function()
	WorldMapQuestDetailScrollFrame:Hide();
	WorldMapQuestRewardScrollFrame:Hide();
	WorldMapTrackQuest:Hide();
	if QM:IsShown() and details:IsShown() and QM.questID then
		QM.ShowDetails(QM.questID);
	end
end);

-- a click on a quest in the list or on its map POI opens the details
hooksecurefunc("WorldMapFrame_GetQuestFrame", function(index)
	local frame = _G["WorldMapQuestFrame" .. index];
	if frame and not frame.qmHooked then
		frame.qmHooked = true;
		frame:HookScript("OnMouseUp", function(self)
			if self:IsMouseOver() and not IsShiftKeyDown() and self.questId and self.questId ~= 0 then
				QM.ShowDetails(self.questId);
			end
		end);
	end
end);
hooksecurefunc("WorldMapQuestPOI_OnClick", function(self)
	if self.quest and self.quest.questId and not IsShiftKeyDown() then
		QM.ShowDetails(self.quest.questId);
	end
end);

-- a quest gone (abandoned / turned in): back to the list; the buttons follow the group and tracking
QM:RegisterEvent("QUEST_LOG_UPDATE");
QM:RegisterEvent("PARTY_MEMBERS_CHANGED");
QM:SetScript("OnEvent", function(self)
	if not (self:IsShown() and details:IsShown() and self.questID) then
		return;
	end
	if QuestLogIndexByID(self.questID) then
		self.UpdateButtons();
	else
		self.ShowList();
	end
end);
