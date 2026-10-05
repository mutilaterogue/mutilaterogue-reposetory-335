-- QuestMapFrame.lua: Legion's QuestMapFrame (7.3.5 FrameXML\QuestMapFrame.lua) on the 3.3.5 world map.
-- The frames are in QuestAndMap.xml; the window around the map is WorldMapLegion.lua.
--
-- Like Legion: the whole quest log next to the map (zone headers that collapse, titles in difficulty colors,
-- numbered POIs matching the map, objectives, tags, party counts, watched check); hovering a quest draws its
-- blob, a click opens the details (text, rewards, Back / Abandon / Share / Track), shift-click tracks,
-- right click gives the options menu.
-- 3.3.5 API: GetQuestLogTitle 9 returns (questID 9th), QuestPOI_* by parent name, QUEST_TEMPLATE_MAP1/MAP2,
-- DrawQuestBlob, IsUnitOnQuest(index, unit), GetNumPartyMembers.


local function SetAtlasIf(texture, atlas, useSize)
	if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas, useSize);
		return true;
	end
	return false;
end

local function QuestIDOf(questLogIndex)
	local questID = select(9, GetQuestLogTitle(questLogIndex));
	if questID and questID ~= 0 then
		return questID;
	end
	local link = GetQuestLink(questLogIndex);
	return link and tonumber(link:match("quest:(%d+)"));
end

function QuestMapFrame_GetQuestLogIndexByID(questID)
	if not questID or questID == 0 then
		return 0;
	end
	if GetQuestLogIndexByID then
		local index = GetQuestLogIndexByID(questID);
		if index and index > 0 then
			return index;
		end
	end
	for i = 1, GetNumQuestLogEntries() do
		if QuestIDOf(i) == questID then
			return i;
		end
	end
	return 0;
end
local IndexByID = QuestMapFrame_GetQuestLogIndexByID;

local function NumGroupMembers()
	return GetNumPartyMembers and GetNumPartyMembers() or 0;
end

---------------------------------------------------------------------------
-- frames (QuestAndMap.xml)
---------------------------------------------------------------------------
local questsFrame, contents, detailsFrame, detailsScroll, detailsContents, textPart, rewardsPart, optionsDropDown;

-- sliced atlases (retail draws these with slice margins; 3.3.5 stretches a texture): up to 9 pieces,
-- the corners at their atlas size, the edges and the middle stretched between them
function QuestMap_SliceAtlas(frame, atlas, layer, left, top, right, bottom, pieces)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas);
	local file = info and (info.filename or info.file);
	if not (file and info.width and info.width > 0) then
		return pieces or {};
	end
	-- the margins: given, else the atlas' slice data (sliceData, or slice={l, t, r, b} in AtlasInfo)
	if not left then
		local slice = info.sliceData;
		if slice then
			left, top, right, bottom = slice.marginLeft, slice.marginTop, slice.marginRight, slice.marginBottom;
		else
			local raw = AtlasInfo and AtlasInfo[file] and AtlasInfo[file][atlas];
			slice = raw and raw.slice;
			if slice then
				left, top, right, bottom = slice[1], slice[2], slice[3], slice[4];
			end
		end
	end
	left, top, right, bottom = left or 0, top or 0, right or 0, bottom or 0;
	local u1, u2 = info.leftTexCoord or info.left, info.rightTexCoord or info.right;
	local v1, v2 = info.topTexCoord or info.top, info.bottomTexCoord or info.bottom;
	if not (u1 and u2 and v1 and v2) then
		return pieces or {};
	end
	local du, dv = (u2 - u1) / info.width, (v2 - v1) / info.height;
	-- columns / rows: { texcoord from, texcoord to, anchor from (side, offset), anchor to }
	local cols, rows = {}, {};
	if left > 0 then
		tinsert(cols, { u1, u1 + left * du, "LEFT", 0, "LEFT", left });
	end
	tinsert(cols, { u1 + left * du, u2 - right * du, "LEFT", left, "RIGHT", -right });
	if right > 0 then
		tinsert(cols, { u2 - right * du, u2, "RIGHT", -right, "RIGHT", 0 });
	end
	if top > 0 then
		tinsert(rows, { v1, v1 + top * dv, "TOP", 0, "TOP", -top });
	end
	tinsert(rows, { v1 + top * dv, v2 - bottom * dv, "TOP", -top, "BOTTOM", bottom });
	if bottom > 0 then
		tinsert(rows, { v2 - bottom * dv, v2, "BOTTOM", bottom, "BOTTOM", 0 });
	end
	pieces = pieces or {};
	local index = 0;
	for _, row in ipairs(rows) do
		for _, col in ipairs(cols) do
			index = index + 1;
			local piece = pieces[index] or frame:CreateTexture(nil, layer or "BACKGROUND");
			pieces[index] = piece;
			piece:SetTexture(file);
			piece:SetTexCoord(col[1], col[2], row[1], row[2]);
			piece:ClearAllPoints();
			-- left / right edges, top / bottom edges of the piece
			piece:SetPoint("TOPLEFT", frame, row[3] .. col[3], col[4], row[4]);
			piece:SetPoint("BOTTOMRIGHT", frame, row[5] .. col[5], col[6], row[6]);
			piece:Show();
		end
	end
	return pieces;
end

function QuestMap_ShowSlices(pieces, shown)
	for _, piece in ipairs(pieces or {}) do
		if shown then
			piece:Show();
		else
			piece:Hide();
		end
	end
end

-- the retail scroll bar (MinimalScrollBar) on a 3.3.5 UIPanelScrollFrameTemplate: thin track, thumb, arrows
function QuestMap_RetailScrollBar(scrollFrame)
	local name = scrollFrame:GetName();
	local bar = _G[name .. "ScrollBar"];
	if not bar or bar.retailStyled then
		return;
	end
	bar.retailStyled = true;
	bar:SetWidth(8);

	-- the track: top, stretched middle, bottom
	local trackTop = bar:CreateTexture(nil, "BACKGROUND");
	SetAtlasIf(trackTop, "minimal-scrollbar-track-top", true);
	trackTop:SetPoint("TOP", bar, "TOP", 0, 0);
	local trackBottom = bar:CreateTexture(nil, "BACKGROUND");
	SetAtlasIf(trackBottom, "minimal-scrollbar-track-bottom", true);
	trackBottom:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0);
	local trackMiddle = bar:CreateTexture(nil, "BACKGROUND");
	SetAtlasIf(trackMiddle, "!minimal-scrollbar-track-middle");
	trackMiddle:SetWidth(8);
	trackMiddle:SetPoint("TOP", trackTop, "BOTTOM");
	trackMiddle:SetPoint("BOTTOM", trackBottom, "TOP");

	-- the thumb: the slider's thumb is the middle, the caps hang on it
	local thumb = bar:GetThumbTexture();
	if thumb then
		SetAtlasIf(thumb, "minimal-scrollbar-thumb-middle");
		thumb:SetWidth(8);
		thumb:SetHeight(28);
		local capTop = bar:CreateTexture(nil, "OVERLAY");
		SetAtlasIf(capTop, "minimal-scrollbar-small-thumb-top", true);
		capTop:SetPoint("BOTTOM", thumb, "TOP");
		local capBottom = bar:CreateTexture(nil, "OVERLAY");
		SetAtlasIf(capBottom, "minimal-scrollbar-small-thumb-bottom", true);
		capBottom:SetPoint("TOP", thumb, "BOTTOM");
	end

	-- the arrows
	local function Arrow(button, atlas)
		if not button then
			return;
		end
		button:SetWidth(17);
		button:SetHeight(11);
		for _, key in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
			local texture = button["Get" .. key .. "Texture"] and button["Get" .. key .. "Texture"](button);
			if texture then
				local suffix = (key == "Pushed" and "-down") or (key == "Highlight" and "-over") or "";
				SetAtlasIf(texture, atlas .. suffix);
				texture:ClearAllPoints();
				texture:SetAllPoints(button);
				if key == "Disabled" then
					texture:SetDesaturated(true);
				elseif key == "Highlight" then
					texture:SetBlendMode("BLEND");
				end
			end
		end
	end
	local up, down = _G[name .. "ScrollBarScrollUpButton"], _G[name .. "ScrollBarScrollDownButton"];
	Arrow(up, "minimal-scrollbar-arrow-top");
	Arrow(down, "minimal-scrollbar-arrow-bottom");
	if up then
		up:ClearAllPoints();
		up:SetPoint("BOTTOM", bar, "TOP", 0, 2);
	end
	if down then
		down:ClearAllPoints();
		down:SetPoint("TOP", bar, "BOTTOM", 0, -2);
	end
end

local OBJECTIVE_FRAMES = {};
function QuestLog_GetObjectiveFrame(index)
	if not OBJECTIVE_FRAMES[index] then
		OBJECTIVE_FRAMES[index] = CreateFrame("Frame", "QLOF" .. index, contents, "QuestMapLogObjectiveTemplate");
	end
	return OBJECTIVE_FRAMES[index];
end

function QuestLogQuests_GetHeaderButton(index)
	local headers = contents.Headers;
	if not headers[index] then
		local header = CreateFrame("Button", nil, contents, "QuestMapLogHeaderTemplate");
		-- the retail header bar: a three slice, its highlight the same bar added
		header.BarSlices = QuestMap_SliceAtlas(header, "common-button-list-collapseexpand-2x", "BACKGROUND", 10, 0, 10, 0);
		header.HighlightSlices = QuestMap_SliceAtlas(header, "common-button-list-collapseexpand-2x", "HIGHLIGHT", 10, 0, 10, 0);
		for _, piece in ipairs(header.HighlightSlices) do
			piece:SetBlendMode("ADD");
			piece:SetAlpha(0.4);
		end
		headers[index] = header;
	end
	return headers[index];
end

function QuestLogQuests_GetTitleButton(index)
	local titles = contents.Titles;
	if not titles[index] then
		local title = CreateFrame("Button", nil, contents, "QuestMapLogTitleTemplate");
		-- the hover glow behind the title: sliced so its ends keep their shape
		title.GlowSlices = QuestMap_SliceAtlas(title, "QuestLog-quest-glow-yellow", "BORDER", 40, 0, 40, 0);
		QuestMap_ShowSlices(title.GlowSlices, false);
		titles[index] = title;
	end
	return titles[index];
end

function QuestMapFrame_OnLoad(self)
	-- the retail metal frame: nine slice by its atlas margins
	if self.BorderFrame then
		QuestMap_SliceAtlas(self.BorderFrame, "QuestLog-frame", "BORDER", 53, 53, 53, 53);
	end
	questsFrame = QuestScrollFrame;
	contents = QuestScrollFrameContents;
	contents.Headers, contents.Titles = {}, {};
	questsFrame.Contents = contents;
	questsFrame.Background = self.Background;
	self.QuestsFrame = questsFrame;

	detailsFrame = QuestMapDetailsFrame;
	self.DetailsFrame = detailsFrame;
	detailsScroll = QuestMapDetailsScrollFrame;
	detailsContents = QuestMapDetailsScrollChild;
	textPart = QuestMapDetailsTextFrame;
	rewardsPart = QuestMapDetailsRewardsFrame;
	detailsFrame.ScrollFrame = detailsScroll;
	detailsFrame.RewardsFrame = rewardsPart;

	-- retail: the buttons on a dark bar under the details
	local bar = detailsFrame:CreateTexture(nil, "BORDER");
	bar:SetPoint("BOTTOMLEFT", 0, 0);
	bar:SetPoint("BOTTOMRIGHT", 0, 0);
	bar:SetHeight(25);
	bar:SetTexture(0, 0, 0, 0.75);

	QuestMap_RetailScrollBar(QuestScrollFrame);
	QuestMap_RetailScrollBar(QuestMapDetailsScrollFrame);

	optionsDropDown = QuestMapQuestOptionsDropDown;
	optionsDropDown.questID = 0;
	UIDropDownMenu_Initialize(optionsDropDown, QuestMapQuestOptionsDropDown_Initialize, "MENU");

	self.open = true;	-- Legion's questLogOpen CVar (none in 3.3.5): open each session
	self:RegisterEvent("QUEST_LOG_UPDATE");
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED");
	self:RegisterEvent("PARTY_MEMBERS_CHANGED");
	self:RegisterEvent("QUEST_POI_UPDATE");
	self:RegisterEvent("WORLD_MAP_UPDATE");
end

---------------------------------------------------------------------------
-- open / close / layout
---------------------------------------------------------------------------

-- the stock list / detail boxes are replaced by the panel
function QuestMapFrame_HideStockParts()
	WorldMapQuestScrollFrame:Hide();
	WorldMapQuestDetailScrollFrame:Hide();
	WorldMapQuestRewardScrollFrame:Hide();
	WorldMapTrackQuest:Hide();
end
local HideStockQuestParts = QuestMapFrame_HideStockParts;

-- opened: the panel shows with the windowed map (WorldMapLegion_Layout places it)
function QuestMapFrame_Open(userAction)
	if userAction then
		QuestMapFrame.open = true;
	end
	WorldMapLegion_Layout();
end

function QuestMapFrame_Close(userAction)
	if userAction then
		QuestMapFrame.open = false;
	end
	WorldMapLegion_Layout();
end

function QuestMapFrame_Show()
	if not QuestMapFrame:IsShown() then
		QuestMapFrame:Show();
	end
	QuestMapFrame_UpdateAll();
end

function QuestMapFrame_Hide()
	if QuestMapFrame:IsShown() then
		QuestMapFrame:Hide();
	end
end

---------------------------------------------------------------------------
-- update
---------------------------------------------------------------------------
-- the map's POI numbers (the stock WorldMapFrame_UpdateQuests order): questID -> { number, complete }
local function GetQuestPOIs()
	local pois = {};
	if not (WorldMapFrame:IsShown() and WatchFrame and WatchFrame.showObjectives) then
		return pois;
	end
	local numEntries = QuestMapUpdateAllQuests();
	local count, completed = 0, 0;
	local playerMoney = GetMoney();
	for i = 1, numEntries do
		local questID, questLogIndex = QuestPOIGetQuestIDByVisibleIndex(i);
		if questLogIndex and questLogIndex > 0 then
			count = count + 1;
			local isComplete = select(7, GetQuestLogTitle(questLogIndex));
			if isComplete and isComplete < 0 then
				isComplete = false;
			elseif GetNumQuestLeaderBoards(questLogIndex) == 0 and playerMoney >= GetQuestLogRequiredMoney(questLogIndex) then
				isComplete = true;
			end
			if isComplete then
				completed = completed + 1;
				pois[questID] = { number = completed, complete = true };
			else
				pois[questID] = { number = count - completed };
			end
		end
	end
	return pois;
end

function QuestMapFrame_UpdateAll()
	if not QuestMapFrame:IsShown() then
		return;
	end
	local questDetailID = detailsFrame.questID;
	if questDetailID then
		if IndexByID(questDetailID) == 0 then
			QuestMapFrame_CloseQuestDetails();
		else
			QuestMapFrame_UpdateQuestDetailsButtons();
		end
		return;
	end
	QuestLogQuests_Update(GetQuestPOIs());
end

-- the quest's tag icon (3.3.5 tags are localized strings)
local function TagAtlas(questTag, isComplete, isDaily)
	if isComplete and isComplete < 0 then
		return "questlog-questtypeicon-questfailed";
	elseif isComplete and isComplete > 0 then
		return "QuestLog-icon-checkmark-yellow";
	elseif isDaily then
		return "questlog-questtypeicon-daily";
	elseif questTag then
		if questTag == (PVP or "PvP") then
			return "questlog-questtypeicon-pvp";
		elseif questTag == RAID then
			return "questlog-questtypeicon-raid";
		elseif questTag == (LFG_TYPE_DUNGEON or DUNGEONS) or questTag == "Dungeon" then
			return "questlog-questtypeicon-dungeon";
		elseif questTag == (PLAYER_DIFFICULTY2 or "Heroic") then
			return "questlog-questtypeicon-heroic";
		elseif questTag == GROUP or questTag == ELITE then
			return "questlog-questtypeicon-group";
		end
	end
	return nil;
end

function QuestLogQuests_Update(poiTable)
	local playerMoney = GetMoney();
	local numEntries = GetNumQuestLogEntries();
	local button, prevButton;
	local totalContentsHeight = 6;

	QuestPOI_HideAllButtons("QuestScrollFrameContents");
	local numPOINumeric, numPOIComplete = 0, 0;

	local headerIndex, titleIndex, objectiveIndex = 0, 0, 0;
	local headerCollapsed = false;
	local headerTitle, headerShown, headerLogIndex;
	local noHeaders = true;
	for questLogIndex = 1, numEntries do
		local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID = GetQuestLogTitle(questLogIndex);
		questID = questID or QuestIDOf(questLogIndex);
		local difficultyColor = GetQuestDifficultyColor(level);
		if isHeader then
			headerTitle = title;
			headerShown = false;
			headerLogIndex = questLogIndex;
			headerCollapsed = isCollapsed;
			-- a collapsed header has no quests under it in 3.3.5: show it now
			if isCollapsed then
				headerShown = true;
				noHeaders = false;
				headerIndex = headerIndex + 1;
				button = QuestLogQuests_GetHeaderButton(headerIndex);
				SetAtlasIf(button.CollapseIcon, "common-button-list-plus-2x", true);	-- its own size: plus 13x13, minus 13x4
				button.ButtonText:SetText(headerTitle or "");
				button:ClearAllPoints();
				if prevButton then
					button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0);
				else
					button:SetPoint("TOPLEFT", 4, -6);
				end
				button.questLogIndex = headerLogIndex;
				button:Show();
				prevButton = button;
				totalContentsHeight = totalContentsHeight + button:GetHeight();
			end
		else
			if not headerShown then
				headerShown = true;
				noHeaders = false;
				headerIndex = headerIndex + 1;
				button = QuestLogQuests_GetHeaderButton(headerIndex);
				SetAtlasIf(button.CollapseIcon, "common-button-list-minus-2x", true);
				button.ButtonText:SetText(headerTitle or "");
				button:ClearAllPoints();
				if prevButton then
					button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0);
				else
					button:SetPoint("TOPLEFT", 4, -6);
				end
				button.questLogIndex = headerLogIndex;
				button:Show();
				prevButton = button;
				totalContentsHeight = totalContentsHeight + button:GetHeight();
			end

			local totalHeight = 8;
			titleIndex = titleIndex + 1;
			button = QuestLogQuests_GetTitleButton(titleIndex);
			button.questID = questID;

			if ENABLE_COLORBLIND_MODE == "1" then
				title = "[" .. level .. "] " .. title;
			end
			-- party members on this quest
			local partyMembersOnQuest = 0;
			for j = 1, NumGroupMembers() do
				if IsUnitOnQuest(questLogIndex, "party" .. j) then
					partyMembersOnQuest = partyMembersOnQuest + 1;
				end
			end
			if partyMembersOnQuest > 0 then
				title = "[" .. partyMembersOnQuest .. "] " .. title;
			end

			button.Text:SetText(title);
			button.Text:SetTextColor(difficultyColor.r, difficultyColor.g, difficultyColor.b);
			button.difficultyColor = difficultyColor;
			totalHeight = totalHeight + button.Text:GetHeight();
			-- retail: the tracking box at the right, checked when watched
			if IsQuestWatched(questLogIndex) then
				button.Checkbox.CheckMark:Show();
			else
				button.Checkbox.CheckMark:Hide();
			end

			local tagAtlas = TagAtlas(questTag, isComplete, isDaily);
			if tagAtlas and SetAtlasIf(button.TagTexture, tagAtlas) then
				button.TagTexture:Show();
			else
				button.TagTexture:Hide();
			end

			-- objectives
			local requiredMoney = GetQuestLogRequiredMoney(questLogIndex);
			local numObjectives = GetNumQuestLeaderBoards(questLogIndex);
			if isComplete and isComplete < 0 then
				isComplete = false;
			elseif numObjectives == 0 and playerMoney >= requiredMoney then
				isComplete = true;
			end
			if isComplete then
				objectiveIndex = objectiveIndex + 1;
				local objectiveFrame = QuestLog_GetObjectiveFrame(objectiveIndex);
				objectiveFrame.questID = questID;
				objectiveFrame:Show();
				objectiveFrame.Text:SetText(GetQuestLogCompletionText(questLogIndex) or QUEST_WATCH_QUEST_READY or COMPLETE);
				local height = objectiveFrame.Text:GetHeight();
				objectiveFrame:SetHeight(height);
				objectiveFrame:ClearAllPoints();
				objectiveFrame:SetPoint("TOPLEFT", button.Text, "BOTTOMLEFT", 0, -3);
				totalHeight = totalHeight + height + 3;
			else
				local prevObjective;
				for i = 1, numObjectives do
					local text, _, finished = GetQuestLogLeaderBoard(i, questLogIndex);
					if text and not finished then
						objectiveIndex = objectiveIndex + 1;
						local objectiveFrame = QuestLog_GetObjectiveFrame(objectiveIndex);
						objectiveFrame.questID = questID;
						objectiveFrame:Show();
						objectiveFrame.Text:SetText(text);
						local height = objectiveFrame.Text:GetHeight();
						objectiveFrame:SetHeight(height);
						objectiveFrame:ClearAllPoints();
						if prevObjective then
							objectiveFrame:SetPoint("TOPLEFT", prevObjective, "BOTTOMLEFT", 0, -2);
							height = height + 2;
						else
							objectiveFrame:SetPoint("TOPLEFT", button.Text, "BOTTOMLEFT", 0, -3);
							height = height + 3;
						end
						totalHeight = totalHeight + height;
						prevObjective = objectiveFrame;
					end
				end
				if requiredMoney > playerMoney then
					objectiveIndex = objectiveIndex + 1;
					local objectiveFrame = QuestLog_GetObjectiveFrame(objectiveIndex);
					objectiveFrame.questID = questID;
					objectiveFrame:Show();
					objectiveFrame.Text:SetText(GetMoneyString(playerMoney) .. " / " .. GetMoneyString(requiredMoney));
					local height = objectiveFrame.Text:GetHeight();
					objectiveFrame:SetHeight(height);
					objectiveFrame:ClearAllPoints();
					if prevObjective then
						objectiveFrame:SetPoint("TOPLEFT", prevObjective, "BOTTOMLEFT", 0, -2);
						height = height + 2;
					else
						objectiveFrame:SetPoint("TOPLEFT", button.Text, "BOTTOMLEFT", 0, -3);
						height = height + 3;
					end
					totalHeight = totalHeight + height;
				end
			end

			-- POI: the number the map shows for it
			local poi = poiTable[questID];
			if poi then
				local poiButton;
				if poi.complete then
					numPOIComplete = numPOIComplete + 1;
					poiButton = QuestPOI_DisplayButton("QuestScrollFrameContents", QUEST_POI_COMPLETE_IN, numPOIComplete, questID);
				else
					numPOINumeric = numPOINumeric + 1;
					poiButton = QuestPOI_DisplayButton("QuestScrollFrameContents", QUEST_POI_NUMERIC, poi.number, questID);
				end
				if poiButton then
					poiButton:ClearAllPoints();
					poiButton:SetPoint("TOPLEFT", button, 6, -4);
					poiButton:SetFrameLevel(button:GetFrameLevel() + 2);
					poiButton.parent = button;
					poiButton:SetScript("OnClick", function(self)
						QuestMapLogTitleButton_OnClick(self.parent, "LeftButton");
					end);
				end
				totalHeight = totalHeight + 6;
				button.Text:SetPoint("TOPLEFT", 31, -8);
			else
				button.Text:SetPoint("TOPLEFT", 31, -4);
			end

			button:SetHeight(totalHeight);
			button.questLogIndex = questLogIndex;
			button:ClearAllPoints();
			if prevButton then
				button:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 0);
			else
				button:SetPoint("TOPLEFT", 4, -6);
			end
			button:Show();
			prevButton = button;
			totalContentsHeight = totalContentsHeight + totalHeight;
		end
	end

	-- background
	if titleIndex == 0 and noHeaders then
		SetAtlasIf(questsFrame.Background, "QuestLog-main-background");
	else
		SetAtlasIf(questsFrame.Background, "QuestLog-main-background");
	end

	if WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.selectedQuestId then
		QuestPOI_SelectButtonByQuestId("QuestScrollFrameContents", WORLDMAP_SETTINGS.selectedQuestId, true);
	end

	-- clean up
	for i = headerIndex + 1, #contents.Headers do
		contents.Headers[i]:Hide();
	end
	for i = titleIndex + 1, #contents.Titles do
		contents.Titles[i]:Hide();
	end
	for i = objectiveIndex + 1, #OBJECTIVE_FRAMES do
		OBJECTIVE_FRAMES[i]:Hide();
	end
	contents:SetHeight(math.max(10, totalContentsHeight));
	ScrollFrame_OnScrollRangeChanged(questsFrame);
end

---------------------------------------------------------------------------
-- details
---------------------------------------------------------------------------
-- the parts' heights: down to the lowest shown QuestInfo region (laid out a frame later)
local function LowestBottom(frame)
	local top = frame:GetTop();
	if not top then
		return 10;
	end
	local bottom = top;
	for _, region in ipairs({ frame:GetChildren() }) do
		if region:IsShown() and region:GetBottom() then
			bottom = math.min(bottom, region:GetBottom());
		end
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsShown() and region:GetBottom() then
			bottom = math.min(bottom, region:GetBottom());
		end
	end
	return math.max(10, top - bottom + 8);
end

local fitter = CreateFrame("Frame");
fitter:Hide();
fitter:SetScript("OnUpdate", function(self)
	self:Hide();
	textPart:SetHeight(LowestBottom(textPart));
	rewardsPart:SetHeight(LowestBottom(rewardsPart));
	detailsContents:SetHeight(textPart:GetHeight() + rewardsPart:GetHeight());
	ScrollFrame_OnScrollRangeChanged(detailsScroll);
end);

local function DisplayDetails()
	QuestInfo_Display(QUEST_TEMPLATE_MAP1, textPart);
	QuestInfo_Display(QUEST_TEMPLATE_MAP2, rewardsPart);
	fitter:Show();
end

function QuestMapFrame_ShowQuestDetails(questID)
	local questLogIndex = IndexByID(questID);
	if questLogIndex == 0 then
		return;
	end
	detailsFrame.questID = questID;
	-- the map's selection (POI + blob) first: it shows the quest in the stock boxes, then into the panel
	if WorldMapFrame:IsShown() and WatchFrame and WatchFrame.showObjectives and GetQuestPOIs()[questID] then
		WorldMapFrame_SelectQuestById(questID);
	end
	SelectQuestLogEntry(questLogIndex);
	DisplayDetails();
	detailsScroll:SetVerticalScroll(0);
	HideStockQuestParts();

	questsFrame:Hide();
	detailsFrame:Show();
	QuestMapFrame_UpdateQuestDetailsButtons();

	StaticPopup_Hide("ABANDON_QUEST");
	StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS");
end

function QuestMapFrame_CloseQuestDetails()
	questsFrame:Show();
	detailsFrame:Hide();
	detailsFrame.questID = nil;
	QuestMapFrame_UpdateAll();
	StaticPopup_Hide("ABANDON_QUEST");
	StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS");
end

function QuestMapFrame_ReturnFromQuestDetails()
	QuestMapFrame_CloseQuestDetails();
end

function QuestMapFrame_OpenToQuestDetails(questID)
	if not WorldMapFrame:IsShown() then
		ShowUIPanel(WorldMapFrame);
	end
	QuestMapFrame_Open(true);
	QuestMapFrame_ShowQuestDetails(questID);
end

function QuestMapFrame_GetDetailQuestID()
	return detailsFrame.questID;
end

function QuestMapFrame_UpdateQuestDetailsButtons()
	local questLogIndex = IndexByID(detailsFrame.questID);
	if questLogIndex == 0 then
		return;
	end
	SelectQuestLogEntry(questLogIndex);
	detailsFrame.AbandonButton:Enable();
	if IsQuestWatched(questLogIndex) then
		detailsFrame.TrackButton:SetText(UNTRACK_QUEST_ABBREV or UNTRACK_QUEST or "Не отслеживать");
	else
		detailsFrame.TrackButton:SetText(TRACK_QUEST_ABBREV or TRACK_QUEST);
	end
	if GetQuestLogPushable() and (NumGroupMembers() > 0 or (GetNumRaidMembers and GetNumRaidMembers() > 0)) then
		detailsFrame.ShareButton:Enable();
	else
		detailsFrame.ShareButton:Disable();
	end
end

---------------------------------------------------------------------------
-- options (track / share / abandon)
---------------------------------------------------------------------------
function QuestMapQuestOptions_TrackQuest(questID)
	local questLogIndex = IndexByID(questID);
	if questLogIndex == 0 then
		return;
	end
	if IsQuestWatched(questLogIndex) then
		RemoveQuestWatch(questLogIndex);
	elseif GetNumQuestWatches() >= MAX_WATCHABLE_QUESTS then
		UIErrorsFrame:AddMessage(format(QUEST_WATCH_TOO_MANY, MAX_WATCHABLE_QUESTS), 1.0, 0.1, 0.1, 1.0);
		return;
	else
		AddQuestWatch(questLogIndex);
	end
	if WatchFrame_Update then
		WatchFrame_Update();
	end
	QuestMapFrame_UpdateQuestDetailsButtons();
	QuestMapFrame_UpdateAll();
end

function QuestMapQuestOptions_ShareQuest(questID)
	local questLogIndex = IndexByID(questID);
	if questLogIndex == 0 then
		return;
	end
	SelectQuestLogEntry(questLogIndex);
	QuestLogPushQuest();
	PlaySound("igQuestLogOpen");
end

function QuestMapQuestOptions_AbandonQuest(questID)
	local questLogIndex = IndexByID(questID);
	if questLogIndex == 0 then
		return;
	end
	local lastQuestIndex = GetQuestLogSelection();
	SelectQuestLogEntry(questLogIndex);
	SetAbandonQuest();
	local items = GetAbandonQuestItems();
	if items then
		StaticPopup_Hide("ABANDON_QUEST");
		StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", GetAbandonQuestName(), items);
	else
		StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS");
		StaticPopup_Show("ABANDON_QUEST", GetAbandonQuestName());
	end
	SelectQuestLogEntry(lastQuestIndex);
end

function QuestMapQuestOptionsDropDown_Initialize(self)
	local questLogIndex = IndexByID(self.questID);
	if questLogIndex == 0 then
		return;
	end
	local info = UIDropDownMenu_CreateInfo();
	info.notCheckable = true;

	info.text = IsQuestWatched(questLogIndex) and (UNTRACK_QUEST or "Не отслеживать") or TRACK_QUEST;
	info.func = function(_, questID) QuestMapQuestOptions_TrackQuest(questID); end;
	info.arg1 = self.questID;
	UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL);

	info.text = SHARE_QUEST;
	info.func = function(_, questID) QuestMapQuestOptions_ShareQuest(questID); end;
	info.arg1 = self.questID;
	SelectQuestLogEntry(questLogIndex);
	if not GetQuestLogPushable() or NumGroupMembers() == 0 then
		info.disabled = 1;
	end
	UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL);

	info.text = ABANDON_QUEST;
	info.func = function(_, questID) QuestMapQuestOptions_AbandonQuest(questID); end;
	info.arg1 = self.questID;
	info.disabled = nil;
	UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL);
end

---------------------------------------------------------------------------
-- list buttons
---------------------------------------------------------------------------
function QuestMapLogHeaderButton_OnClick(self, button)
	PlaySound("igMainMenuOptionCheckBoxOn");
	if button == "LeftButton" then
		local _, _, _, _, _, isCollapsed = GetQuestLogTitle(self.questLogIndex);
		if isCollapsed then
			ExpandQuestHeader(self.questLogIndex);
		else
			CollapseQuestHeader(self.questLogIndex);
		end
	elseif WorldMapZoomOutButton_OnClick then
		WorldMapZoomOutButton_OnClick();
	end
end

local tooltipButton;
function QuestMapLogTitleButton_OnEnter(self)
	local title, level, questTag, _, _, _, isComplete, isDaily = GetQuestLogTitle(self.questLogIndex);
	self.Text:SetTextColor(1, 1, 1);
	for _, line in pairs(OBJECTIVE_FRAMES) do
		if line.questID == self.questID then
			line.Text:SetTextColor(1, 1, 1);
		end
	end
	if not isComplete or isComplete <= 0 then
		WorldMapBlobFrame:DrawQuestBlob(self.questID, true);
	end

	local tooltip = WorldMapTooltip or GameTooltip;
	tooltip:SetOwner(self, "ANCHOR_NONE");
	tooltip:ClearAllPoints();
	tooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 34, 0);
	tooltip:SetText(title);
	if (UIParent:GetRight() - QuestMapFrame:GetRight()) < 260 then
		tooltip:ClearAllPoints();
		tooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -5, 0);
	end
	if questTag then
		tooltip:AddLine(questTag, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);
	end
	if isDaily then
		tooltip:AddLine(DAILY, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);
	end
	if isComplete and isComplete < 0 then
		tooltip:AddLine(FAILED, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b);
	end
	tooltip:AddLine(" ");

	if isComplete and isComplete > 0 then
		tooltip:AddLine(GetQuestLogCompletionText(self.questLogIndex) or QUEST_WATCH_QUEST_READY or COMPLETE, 1, 1, 1, true);
		tooltip:AddLine(" ");
	else
		local selection = GetQuestLogSelection();
		SelectQuestLogEntry(self.questLogIndex);
		local _, objectiveText = GetQuestLogQuestText();
		SelectQuestLogEntry(selection);
		if objectiveText and objectiveText ~= "" then
			tooltip:AddLine(objectiveText, 1, 1, 1, true);
			tooltip:AddLine(" ");
		end
		local needsSeparator = false;
		for i = 1, GetNumQuestLeaderBoards(self.questLogIndex) do
			local text, _, finished = GetQuestLogLeaderBoard(i, self.questLogIndex);
			if text then
				local color = finished and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
				tooltip:AddLine(QUEST_DASH .. text, color.r, color.g, color.b, true);
				needsSeparator = true;
			end
		end
		local requiredMoney = GetQuestLogRequiredMoney(self.questLogIndex);
		if requiredMoney > 0 then
			local playerMoney = GetMoney();
			local color = HIGHLIGHT_FONT_COLOR;
			if requiredMoney <= playerMoney then
				playerMoney = requiredMoney;
				color = GRAY_FONT_COLOR;
			end
			tooltip:AddLine(QUEST_DASH .. GetMoneyString(playerMoney) .. " / " .. GetMoneyString(requiredMoney), color.r, color.g, color.b);
			needsSeparator = true;
		end
		if needsSeparator then
			tooltip:AddLine(" ");
		end
	end
	tooltip:AddLine(CLICK_QUEST_DETAILS or "Щелкните, чтобы просмотреть подробности", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b);

	local partyMembersOnQuest = 0;
	for i = 1, NumGroupMembers() do
		if IsUnitOnQuest(self.questLogIndex, "party" .. i) then
			if partyMembersOnQuest == 0 then
				tooltip:AddLine(" ");
				tooltip:AddLine(PARTY_QUEST_STATUS_ON or PARTY);
			end
			partyMembersOnQuest = partyMembersOnQuest + 1;
			tooltip:AddLine(LIGHTYELLOW_FONT_COLOR_CODE .. UnitName("party" .. i) .. FONT_COLOR_CODE_CLOSE);
		end
	end
	tooltip:Show();
	tooltipButton = self;
end

function QuestMapLogTitleButton_OnLeave(self)
	local color = self.difficultyColor or NORMAL_FONT_COLOR;
	self.Text:SetTextColor(color.r, color.g, color.b);
	for _, line in pairs(OBJECTIVE_FRAMES) do
		if line.questID == self.questID then
			line.Text:SetTextColor(0.8, 0.8, 0.8);
		end
	end
	if not (WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.selectedQuestId == self.questID) then
		WorldMapBlobFrame:DrawQuestBlob(self.questID, false);
	end
	(WorldMapTooltip or GameTooltip):Hide();
	tooltipButton = nil;
end

function QuestMapLogTitleButton_OnClick(self, button)
	if IsModifiedClick("CHATLINK") and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
		local link = GetQuestLink(self.questLogIndex);
		if link then
			ChatEdit_InsertLink(link);
			return;
		end
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	if IsShiftKeyDown() then
		QuestMapQuestOptions_TrackQuest(self.questID);
	elseif button == "RightButton" then
		if self.questID ~= optionsDropDown.questID then
			CloseDropDownMenus();
		end
		optionsDropDown.questID = self.questID;
		ToggleDropDownMenu(1, nil, optionsDropDown, "cursor", 6, -6);
	else
		QuestMapFrame_ShowQuestDetails(self.questID);
	end
end

---------------------------------------------------------------------------
-- events and the stock map
---------------------------------------------------------------------------
-- Legion's QuestMapFrame_ResetFilters: the headers of the zones on the shown map open (the others are left as they are)
-- (3.3.5 headers are zone names: the zone itself, or the zones of the shown continent; the world: all open)
local lastMap;
function QuestMapFrame_ResetFilters()
	local continent, zone = GetCurrentMapContinent(), GetCurrentMapZone();
	local mapKey = tostring(continent) .. ":" .. tostring(zone);
	if mapKey == lastMap then
		return;
	end
	lastMap = mapKey;
	local onMap;
	if continent and continent > 0 then
		onMap = {};
		if zone and zone > 0 then
			onMap[(select(zone, GetMapZones(continent)))] = true;
		else
			for _, name in ipairs({ GetMapZones(continent) }) do
				onMap[name] = true;
			end
		end
	end
	QuestMapFrame.ignoreQuestLogUpdate = true;
	-- from the end: collapsing a header moves the entries after it
	for questLogIndex = GetNumQuestLogEntries(), 1, -1 do
		local title, _, _, _, isHeader, isCollapsed = GetQuestLogTitle(questLogIndex);
		if isHeader then
			-- only opened: closing the other zones hid the rest of the log (a zone with no quests closed it all)
			if isCollapsed and (not onMap or onMap[title]) then
				ExpandQuestHeader(questLogIndex);
			end
		end
	end
	QuestMapFrame.ignoreQuestLogUpdate = nil;
end

function QuestMapFrame_OnEvent(self, event, arg1)
	if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then
		return;
	end
	if not self:IsShown() or self.ignoreQuestLogUpdate then
		return;
	end
	if event == "WORLD_MAP_UPDATE" and not detailsFrame.questID then
		QuestMapFrame_ResetFilters();
	end
	QuestMapFrame_UpdateAll();
	if tooltipButton and tooltipButton:IsShown() then
		QuestMapLogTitleButton_OnEnter(tooltipButton);
	end
end

-- the stock selection puts the QuestInfo parts into its boxes: back into the panel; the list follows the map
hooksecurefunc("WorldMapFrame_SelectQuestFrame", function()
	HideStockQuestParts();
	if QuestMapFrame:IsShown() and detailsFrame:IsShown() and detailsFrame.questID then
		local questLogIndex = IndexByID(detailsFrame.questID);
		if questLogIndex > 0 then
			SelectQuestLogEntry(questLogIndex);
			DisplayDetails();
		end
	end
end);
hooksecurefunc("WorldMapFrame_UpdateQuests", function()
	HideStockQuestParts();
	if QuestMapFrame:IsShown() and not detailsFrame.questID then
		QuestLogQuests_Update(GetQuestPOIs());
	end
end);

-- a click on a quest POI on the map opens its details (Legion)
hooksecurefunc("WorldMapQuestPOI_OnClick", function(self)
	if self.quest and self.quest.questId and not IsShiftKeyDown() and QuestMapFrame:IsShown() then
		QuestMapFrame_ShowQuestDetails(self.quest.questId);
	end
end);

-- retail: hovering a quest on the map lights its line in the list
function QuestMapFrame_HighlightQuest(questID)
	for _, title in ipairs(contents and contents.Titles or {}) do
		if title:IsShown() then
			QuestMap_ShowSlices(title.GlowSlices, questID and title.questID == questID);
		end
	end
end
hooksecurefunc("WorldMapQuestPOI_OnEnter", function(self)
	if self.quest and self.quest.questId then
		QuestMapFrame_HighlightQuest(self.quest.questId);
	end
end);
hooksecurefunc("WorldMapQuestPOI_OnLeave", function()
	QuestMapFrame_HighlightQuest(nil);
end);
