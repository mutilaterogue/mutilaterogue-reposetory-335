-- Retail style talents: the class tree (left column) and the hero tree (middle column, one of 2-3) next to
-- one 3.3.5 spec tree (right). Server: server/talent_custom.cpp (CTAL_*). The points are the 3.3.5 talent points.

PlayerSpellsCustomTalents = { trees = {}, nodes = {}, ranks = {}, hero = 0, loaded = false };
local CT = PlayerSpellsCustomTalents;

-- retail node scale (ClassTalentsFrame): ~40 px nodes, ~56 px apart
local NODE_SPACING = 58;
local NODE_SIZE = 40;
local ICON_SIZE = 34;
local LINE_THICKNESS = 6;
local NODE_RADIUS = 20;
local HEADER_HEIGHT = 80;

local ATLAS = {
	circle = { yellow = "talents-node-circle-yellow", green = "talents-node-circle-green", gray = "talents-node-circle-gray" },
	square = { yellow = "talents-node-square-yellow", green = "talents-node-square-green", gray = "talents-node-square-gray" },
	lineActive = "talents-arrow-line-yellow",
	lineLocked = "talents-arrow-line-gray",
};

local function Send(...)
	if Comm_Send then
		Comm_Send(...);
	end
end

local function SplitNumbers(text, separator)
	local list = {};
	for value in string.gmatch(text or "", "[^" .. separator .. "]+") do
		local n = tonumber(value);
		if n then
			table.insert(list, n);
		end
	end
	return list;
end

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------
local function TreesOfKind(kind)
	local list = {};
	for _, tree in pairs(CT.trees) do
		if tree.kind == kind then
			table.insert(list, tree);
		end
	end
	table.sort(list, function(a, b) return a.id < b.id; end);
	return list;
end

local function SpentInTree(treeId)
	local spent = 0;
	for nodeId, rank in pairs(CT.ranks) do
		local node = CT.nodes[nodeId];
		if node and node.tree == treeId then
			spent = spent + rank;
		end
	end
	return spent;
end

local function FreePoints()
	local group = GetActiveTalentGroup(false, false) or 1;
	return (GetUnspentTalentPoints(false, false, group) or 0) - (GetGroupPreviewTalentPointsSpent(false, group) or 0);
end

-- "yellow" learned (max or partial), "green" can take a point, "gray" closed
local function NodeState(node)
	local rank = CT.ranks[node.id] or 0;
	if rank >= node.maxRank then
		return "yellow", rank;
	end
	local tree = CT.trees[node.tree];
	local open = UnitLevel("player") >= 10 and SpentInTree(node.tree) >= node.minPoints;
	if tree and tree.kind == 1 then
		open = open and CT.hero == tree.id and UnitLevel("player") >= tree.minLevel;
	end
	if open and #node.requires > 0 then
		local any = false;
		for _, required in ipairs(node.requires) do
			local req = CT.nodes[required];
			if req and (CT.ranks[required] or 0) >= req.maxRank then
				any = true;
			end
		end
		open = any;
	end
	if open and FreePoints() > 0 then
		return "green", rank;
	end
	return rank > 0 and "yellow" or "gray", rank;
end

---------------------------------------------------------------------------
-- columns
---------------------------------------------------------------------------
local function CreateColumn(parent, name)
	-- retail: no panels, the spec art of the frame shows through; centered name and points
	local column = CreateFrame("Frame", name, parent);
	column.Name = column:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge");
	column.Name:SetPoint("TOP", 0, -12);
	column.Points = column:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge");
	column.Points:SetPoint("TOP", column.Name, "BOTTOM", 0, -6);
	column.Points:SetTextColor(0.6, 0.6, 0.6);
	column.Content = CreateFrame("Frame", nil, column);
	column.Content:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT);
	column.Content:SetPoint("BOTTOMRIGHT");
	column.buttons = {};
	column.lines = {};
	return column;
end

local function AcquireLine(column)
	column.lineCount = column.lineCount + 1;
	local line = column.lines[column.lineCount];
	if not line then
		line = column.Content:CreateTexture(nil, "ARTWORK");
		column.lines[column.lineCount] = line;
	end
	line:Show();
	return line;
end

local function AtlasFile(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas);
	if not info then
		return nil;
	end
	return info.file or info.filename, info.left or info.leftTexCoord, info.right or info.rightTexCoord, info.top or info.topTexCoord, info.bottom or info.bottomTexCoord;
end

-- a line between two node centers (content coordinates, y down), turned by its angle (texcoords)
local function DrawLine(column, x1, y1, x2, y2, atlas)
	local dx, dy = x2 - x1, y2 - y1;
	local length = math.sqrt(dx * dx + dy * dy) - 2 * NODE_RADIUS;
	if length <= 1 then
		return;
	end
	local line = AcquireLine(column);
	local file, l, r, t, b = AtlasFile(atlas);
	if file then
		line:SetTexture(file);
	else
		line:SetTexture(1, 0.82, 0, 0.8);
		l, r, t, b = 0, 1, 0, 1;
	end
	-- a square box around the middle, the line drawn turned inside it
	local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2;
	local angle = math.atan2(-dy, dx);
	local size = length;
	line:ClearAllPoints();
	line:SetPoint("CENTER", column.Content, "TOPLEFT", cx, -cy);
	line:SetWidth(size);
	line:SetHeight(size);
	-- the atlas strip (length x thickness) in the middle of the square, turned: corners of the square in texture space
	local c, s = math.cos(angle), math.sin(angle);
	local half = 0.5;
	local thick = LINE_THICKNESS / size / 2;
	local function Corner(x, y)
		-- square corner (x, y in -0.5..0.5, y up) -> along / across the line
		local along = x * c + y * s;
		local across = -x * s + y * c;
		local u = l + (along + half) * (r - l);
		local v = t + (0.5 - across / (thick * 2) * 0.5) * (b - t);
		return u, v;
	end
	local ulx, uly = Corner(-0.5, 0.5);
	local llx, lly = Corner(-0.5, -0.5);
	local urx, ury = Corner(0.5, 0.5);
	local lrx, lry = Corner(0.5, -0.5);
	line:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry);
	-- only the strip is visible: the rest of the square samples outside the line thickness (clamped edge)
	line:SetHeight(size);
end

local function NodeButton(column, index)
	local button = column.buttons[index];
	if button then
		return button;
	end
	button = CreateFrame("Button", nil, column.Content);
	button:SetWidth(NODE_SIZE);
	button:SetHeight(NODE_SIZE);
	button:RegisterForClicks("LeftButtonUp");
	button.Icon = button:CreateTexture(nil, "ARTWORK");
	button.Icon:SetPoint("CENTER");
	button.Icon:SetWidth(ICON_SIZE);
	button.Icon:SetHeight(ICON_SIZE);
	button.Ring = button:CreateTexture(nil, "OVERLAY");
	button.Ring:SetPoint("CENTER");
	button.Ring:SetWidth(NODE_SIZE);
	button.Ring:SetHeight(NODE_SIZE);
	button.Rank = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline");
	button.Rank:SetPoint("CENTER", button, "BOTTOMRIGHT", -2, 4);
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	button:SetScript("OnClick", function(self)
		if self.state == "green" then
			Send("CTAL_LEARN", self.node.id);
		end
	end);
	button:SetScript("OnEnter", function(self)
		local node = self.node;
		local rank = CT.ranks[node.id] or 0;
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("spell:" .. node.spells[math.max(1, rank)]);
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine(string.format(TOOLTIP_TALENT_RANK or "Rank %d/%d", rank, node.maxRank), 1, 1, 1);
		if rank > 0 and rank < node.maxRank then
			local nextName = GetSpellInfo(node.spells[rank + 1]);
			if nextName then
				GameTooltip:AddLine(TOOLTIP_TALENT_NEXT_RANK or "Next rank:", 1, 1, 1);
				GameTooltip:AddLine(nextName, 1, 0.82, 0);
			end
		end
		if self.state == "green" then
			GameTooltip:AddLine(TOOLTIP_TALENT_LEARN or "Click to learn", 0.1, 1, 0.1);
		elseif node.minPoints > 0 and SpentInTree(node.tree) < node.minPoints then
			GameTooltip:AddLine(string.format(TOOLTIP_TALENT_TIER_POINTS or "Requires %d points in %s", node.minPoints, CT.trees[node.tree].name), 1, 0.1, 0.1, true);
		end
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", GameTooltip_Hide);
	column.buttons[index] = button;
	return button;
end

-- the nodes of a tree in a column: centered by the widest row
local function LayoutTree(column, treeId)
	column.lineCount = 0;
	local list = {};
	local maxCol = 0;
	for _, node in pairs(CT.nodes) do
		if node.tree == treeId then
			table.insert(list, node);
			maxCol = math.max(maxCol, node.col);
		end
	end
	table.sort(list, function(a, b) return a.id < b.id; end);
	local spacing = column.spacing or NODE_SPACING;
	local width = column.Content:GetWidth();
	local offsetX = (width - maxCol * spacing) / 2;
	local centers = {};
	for i, node in ipairs(list) do
		local button = NodeButton(column, i);
		button.node = node;
		local x = offsetX + node.col * spacing;
		local y = (column.top or 40) + node.row * spacing;
		centers[node.id] = { x = x, y = y };
		button:ClearAllPoints();
		button:SetPoint("CENTER", column.Content, "TOPLEFT", x, -y);
		local state, rank = NodeState(node);
		button.state = state;
		local _, _, icon = GetSpellInfo(node.spells[math.max(1, rank)]);
		local shape = node.maxRank == 1 and "square" or "circle";
		if shape == "circle" and icon then
			SetPortraitToTexture(button.Icon, icon);
			button.Icon:SetTexCoord(0, 1, 0, 1);
		else
			button.Icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark");
			button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
		end
		button.Icon:SetDesaturated(state == "gray");
		button.Ring:SetAtlas(ATLAS[shape][state]);
		button.Rank:SetText(rank .. "/" .. node.maxRank);
		if state == "green" then
			button.Rank:SetTextColor(0.1, 1, 0.1);
		elseif state == "yellow" then
			button.Rank:SetTextColor(1, 0.82, 0);
		else
			button.Rank:SetTextColor(0.6, 0.6, 0.6);
		end
		button:Show();
	end
	for i = #list + 1, #column.buttons do
		column.buttons[i]:Hide();
	end
	-- edges: from each required node
	for _, node in ipairs(list) do
		for _, required in ipairs(node.requires) do
			local from, to = centers[required], centers[node.id];
			local req = CT.nodes[required];
			if from and to and req then
				local active = (CT.ranks[required] or 0) >= req.maxRank;
				DrawLine(column, from.x, from.y, to.x, to.y, active and ATLAS.lineActive or ATLAS.lineLocked);
			end
		end
	end
	for i = column.lineCount + 1, #column.lines do
		column.lines[i]:Hide();
	end
end

---------------------------------------------------------------------------
-- hero choice (retail: HeroTalentsSelectionDialog) - one card per hero tree
---------------------------------------------------------------------------
local function SetAtlasIfExists(texture, atlas)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas);
		return true;
	end
	return false;
end

local function RoundIcon(texture, icon)
	icon = icon ~= "" and icon or "Interface\\Icons\\INV_Misc_QuestionMark";
	SetPortraitToTexture(texture, icon);
end

local function CreateChoiceDialog(frame)
	local dialog = CreateFrame("Frame", nil, frame);
	dialog:SetAllPoints(frame);
	dialog:SetFrameLevel(frame:GetFrameLevel() + 50);
	dialog:EnableMouse(true);
	local shade = dialog:CreateTexture(nil, "BACKGROUND");
	shade:SetAllPoints();
	shade:SetTexture(0, 0, 0, 0.8);
	dialog.Title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge");
	dialog.Title:SetPoint("TOP", 0, -60);
	dialog.Title:SetTextColor(0.12, 1, 0);
	dialog.Close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton");
	dialog.Close:SetPoint("TOPRIGHT", -10, -10);
	dialog.Close:SetScript("OnClick", function() dialog:Hide(); end);
	dialog.cards = {};
	dialog:Hide();
	return dialog;
end

local function ShowChoiceDialog(frame)
	local dialog = frame.HeroChoiceDialog;
	local trees = TreesOfKind(1);
	dialog.Title:SetText(HERO_TALENTS_CHOOSE or "Выберите геройские таланты");
	local cardWidth, gap = 320, 40;
	local total = #trees * cardWidth + (#trees - 1) * gap;
	for i, tree in ipairs(trees) do
		local card = dialog.cards[i];
		if not card then
			card = CreateFrame("Frame", nil, dialog);
			card:SetWidth(cardWidth);
			card:SetHeight(520);
			card.Background = card:CreateTexture(nil, "BACKGROUND");
			card.Background:SetPoint("TOP", 0, -150);
			card.Background:SetWidth(284);
			card.Background:SetHeight(362);
			if not SetAtlasIfExists(card.Background, "talents-heroclass-backplate-full-expanded") then
				card.Background:SetTexture(0, 0, 0, 0.5);
			end
			card.Icon = card:CreateTexture(nil, "ARTWORK");
			card.Icon:SetPoint("TOP", 0, -40);
			card.Icon:SetWidth(108);
			card.Icon:SetHeight(108);
			card.Border = card:CreateTexture(nil, "OVERLAY");
			card.Border:SetPoint("CENTER", card.Icon, "CENTER", 0, -2);
			card.Border:SetWidth(192);
			card.Border:SetHeight(192);
			SetAtlasIfExists(card.Border, "talents-heroclass-ring-mainpane");
			card.Name = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
			card.Name:SetPoint("TOP", 0, -6);
			card.Description = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
			card.Description:SetPoint("TOPLEFT", card.Background, "TOPLEFT", 24, -40);
			card.Description:SetPoint("TOPRIGHT", card.Background, "TOPRIGHT", -24, -40);
			card.Description:SetJustifyH("CENTER");
			card.Button = CreateFrame("Button", nil, card, "UIPanelButtonTemplate");
			card.Button:SetWidth(164);
			card.Button:SetHeight(22);
			card.Button:SetPoint("BOTTOM", card.Background, "BOTTOM", 0, 24);
			dialog.cards[i] = card;
		end
		card:ClearAllPoints();
		card:SetPoint("TOPLEFT", dialog, "TOP", -total / 2 + (i - 1) * (cardWidth + gap), -120);
		RoundIcon(card.Icon, tree.icon);
		card.Name:SetText(string.upper(tree.name));
		card.Description:SetText(tree.description);
		if UnitLevel("player") < tree.minLevel then
			card.Button:SetText(string.format(UNIT_LEVEL_TEMPLATE or "Level %d", tree.minLevel));
			card.Button:Disable();
		else
			card.Button:SetText(tree.id == CT.hero and ACTIVE_PETS or ACCEPT);
			card.Button:SetEnabled(tree.id ~= CT.hero);
		end
		card.Button:SetScript("OnClick", function()
			if CT.hero ~= 0 then
				StaticPopup_Show("CTAL_CHANGE_HERO", nil, nil, tree.id);
			else
				Send("CTAL_HERO", tree.id);
			end
			dialog:Hide();
		end);
		card:Show();
	end
	for i = #trees + 1, #dialog.cards do
		dialog.cards[i]:Hide();
	end
	dialog:Show();
end

StaticPopupDialogs["CTAL_CHANGE_HERO"] = {
	text = "Сменить геройскую ветку? Вложенные в неё очки вернутся.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		Send("CTAL_HERO", data);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

---------------------------------------------------------------------------
-- layout in the talents frame (retail ClassTalentsFrame / HeroTalentsContainer)
---------------------------------------------------------------------------
-- retail currency display: "NAME  0" centered on a point
function CT.CreateCurrencyDisplay(parent)
	local display = CreateFrame("Frame", nil, parent);
	display:SetWidth(1);
	display:SetHeight(1);
	display.Label = display:CreateFontString(nil, "ARTWORK", _G.SystemFont_Shadow_Large2 and "SystemFont_Shadow_Large2" or "GameFontHighlightLarge");
	display.Amount = display:CreateFontString(nil, "ARTWORK", _G.Game32Font_Shadow2 and "Game32Font_Shadow2" or "GameFontNormalHuge");
	display.Amount:SetTextColor(0.5, 0.5, 0.5);
	display.Set = function(self, label, amount)
		self.Label:SetText(label);
		self.Amount:SetText(amount);
		self.Amount:SetTextColor(tonumber(amount) and tonumber(amount) > 0 and 1 or 0.5, tonumber(amount) and tonumber(amount) > 0 and 0.82 or 0.5, tonumber(amount) and tonumber(amount) > 0 and 0 or 0.5);
		local width = self.Label:GetStringWidth() + 12 + self.Amount:GetStringWidth();
		self.Label:ClearAllPoints();
		self.Label:SetPoint("LEFT", self, "CENTER", -width / 2, 0);
		self.Amount:ClearAllPoints();
		self.Amount:SetPoint("LEFT", self.Label, "RIGHT", 12, 0);
	end;
	return display;
end

function CT.Setup(frame)
	if frame.ClassColumn then
		return;
	end
	local class = CreateColumn(frame, "PlayerSpellsClassTalents");
	class:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, -14);
	class:SetWidth(664);
	class:SetHeight(757);
	class.Name:Hide();
	class.Points:Hide();
	frame.ClassColumn = class;
	frame.ClassCurrencyDisplay = CT.CreateCurrencyDisplay(frame);
	frame.ClassCurrencyDisplay:SetPoint("CENTER", frame, "TOPLEFT", 372, -45);

	-- hero: name, ring with the icon, points badge, backplate with the nodes
	local hero = CreateFrame("Frame", "PlayerSpellsHeroTalents", frame);
	hero:SetPoint("TOP", frame, "TOP", -10, -14);
	hero:SetWidth(300);
	hero:SetHeight(757);
	hero.buttons = {};
	hero.lines = {};
	hero.spacing = 52;
	hero.top = 46;
	hero.Name = hero:CreateFontString(nil, "ARTWORK", _G.GameFontNormalHuge2 and "GameFontNormalHuge2" or "GameFontNormalLarge");
	hero.Name:SetPoint("TOP", 0, -30);
	hero.SubName = hero:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	hero.SubName:SetPoint("BOTTOM", hero.Name, "TOP", 0, 2);
	hero.SubName:SetTextColor(0.12, 1, 0);

	local ring = CreateFrame("Button", nil, hero);
	ring:SetWidth(108);
	ring:SetHeight(108);
	ring:SetPoint("TOP", 0, -64);
	ring:SetFrameLevel(hero:GetFrameLevel() + 10);
	ring.Icon = ring:CreateTexture(nil, "ARTWORK");
	ring.Icon:SetAllPoints();
	ring.Border = ring:CreateTexture(nil, "OVERLAY");
	ring.Border:SetPoint("CENTER", 0, -2);
	ring.Border:SetWidth(192);
	ring.Border:SetHeight(192);
	ring.Highlight = ring:CreateTexture(nil, "HIGHLIGHT");
	ring.Highlight:SetAllPoints(ring.Border);
	ring.Highlight:SetBlendMode("ADD");
	ring.Highlight:SetAlpha(0.4);
	ring:SetScript("OnClick", function() ShowChoiceDialog(frame); end);
	ring:SetScript("OnEnter", function(self)
		local tree = CT.trees[CT.hero];
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(tree and tree.name or (HERO_TALENTS_CHOOSE or "Выберите геройские таланты"));
		if tree and tree.description ~= "" then
			GameTooltip:AddLine(tree.description, 1, 1, 1, true);
		end
		GameTooltip:Show();
	end);
	ring:SetScript("OnLeave", GameTooltip_Hide);
	hero.Ring = ring;

	local badge = CreateFrame("Frame", nil, ring);
	badge:SetWidth(30);
	badge:SetHeight(30);
	badge:SetPoint("CENTER", ring, "BOTTOM", 0, -3);
	badge.Background = badge:CreateTexture(nil, "ARTWORK");
	badge.Background:SetPoint("CENTER");
	badge.Background:SetWidth(56);
	badge.Background:SetHeight(56);
	SetAtlasIfExists(badge.Background, "talents-heroclass-ring-pointsavailable");
	badge.Text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	badge.Text:SetPoint("CENTER");
	badge.Text:SetTextColor(0.12, 1, 0);
	hero.Badge = badge;

	hero.Content = CreateFrame("Frame", nil, hero);
	hero.Content:SetWidth(284);
	hero.Content:SetHeight(362);
	hero.Content:SetPoint("TOP", ring, "BOTTOM", 0, 34);
	hero.Backplate = hero.Content:CreateTexture(nil, "BACKGROUND");
	hero.Backplate:SetAllPoints();
	if not SetAtlasIfExists(hero.Backplate, "talents-heroclass-backplate-full-expanded") then
		hero.Backplate:SetTexture(0, 0, 0, 0.5);
	end
	hero.BlankNodes = hero.Content:CreateTexture(nil, "BORDER");
	hero.BlankNodes:SetPoint("CENTER", 0, -6);
	if SetAtlasIfExists(hero.BlankNodes, "talents-heroclass-backplate-intro-expanded") then
		local info = C_Texture.GetAtlasInfo("talents-heroclass-backplate-intro-expanded");
		hero.BlankNodes:SetWidth(info.width or 200);
		hero.BlankNodes:SetHeight(info.height or 300);
	end
	frame.HeroColumn = hero;
	frame.HeroChoiceDialog = CreateChoiceDialog(frame);
	Send("CTAL_GET");
end

function CT.Refresh(frame)
	if not frame.ClassColumn then
		return;
	end
	-- class tree
	local classTree = TreesOfKind(0)[1];
	local class = frame.ClassColumn;
	local className = string.upper(classTree and classTree.name ~= "" and classTree.name or (UnitClass("player")));
	if classTree then
		frame.ClassCurrencyDisplay:Set(className, SpentInTree(classTree.id));
		LayoutTree(class, classTree.id);
	else
		frame.ClassCurrencyDisplay:Set(className, 0);
		class.lineCount = 0;
		for _, button in ipairs(class.buttons) do button:Hide(); end
		for _, line in ipairs(class.lines) do line:Hide(); end
	end

	-- hero tree: the chosen one, or the "choose" ring with blank nodes
	local hero = frame.HeroColumn;
	local heroTree = CT.trees[CT.hero];
	local hasChoice = #TreesOfKind(1) > 0;
	hero:SetShown(hasChoice or heroTree ~= nil);
	if heroTree then
		hero.SubName:SetText("");
		hero.Name:SetText(heroTree.name);
		RoundIcon(hero.Ring.Icon, heroTree.icon);
		SetAtlasIfExists(hero.Ring.Border, "talents-heroclass-ring-mainpane");
		SetAtlasIfExists(hero.Ring.Highlight, "talents-heroclass-ring-mainpane");
		hero.BlankNodes:Hide();
		hero.Badge:Hide();
		LayoutTree(hero, heroTree.id);
	else
		hero.SubName:SetText(string.upper(CHOOSE or "Выберите"));
		hero.Name:SetText("|cff1eff00" .. string.upper(HERO_TALENTS or "Геройские таланты") .. "|r");
		RoundIcon(hero.Ring.Icon, "Interface\\Icons\\INV_Misc_QuestionMark");
		SetAtlasIfExists(hero.Ring.Border, "talents-heroclass-ring-intro");
		SetAtlasIfExists(hero.Ring.Highlight, "talents-heroclass-ring-intro");
		hero.BlankNodes:Show();
		hero.Badge:Hide();
		hero.lineCount = 0;
		for _, button in ipairs(hero.buttons) do button:Hide(); end
		for _, line in ipairs(hero.lines) do line:Hide(); end
	end
	if frame.HeroChoiceDialog:IsShown() then
		ShowChoiceDialog(frame);
	end
end

---------------------------------------------------------------------------
-- comm (Server.lua may load after this file - then on login)
---------------------------------------------------------------------------
local function OnUpdate()
	if PlayerSpellsTalentsFrame and PlayerSpellsTalentsFrame:IsShown() then
		CT.Refresh(PlayerSpellsTalentsFrame);
	end
end

local function RegisterComm()
	if not Comm_Register or CT.commRegistered then
		return;
	end
	CT.commRegistered = true;
	-- the definitions follow (login / .reload custom_talents): drop the old ones
	Comm_Register("CTAL_RESET", function()
		wipe(CT.trees);
		wipe(CT.nodes);
		CT.loaded = false;
	end);
	Comm_Register("CTAL_TREE", function(id, kind, name, icon, minLevel, description)
		id = tonumber(id);
		if id then
			CT.trees[id] = { id = id, kind = tonumber(kind) or 0, name = name or "", icon = icon or "", minLevel = tonumber(minLevel) or 10, description = description or "" };
		end
	end);
	Comm_Register("CTAL_NODE", function(id, tree, row, col, maxRank, spells, requires, minPoints)
		id = tonumber(id);
		if id then
			CT.nodes[id] = {
				id = id, tree = tonumber(tree) or 0, row = tonumber(row) or 0, col = tonumber(col) or 0,
				maxRank = tonumber(maxRank) or 1, spells = SplitNumbers(spells, "/"), requires = SplitNumbers(requires, "/"),
				minPoints = tonumber(minPoints) or 0,
			};
		end
	end);
	Comm_Register("CTAL_DONE", function()
		CT.loaded = true;
		OnUpdate();
	end);
	Comm_Register("CTAL_STATE", function(spec, hero, list)
		CT.hero = tonumber(hero) or 0;
		wipe(CT.ranks);
		for entry in string.gmatch(list or "", "[^,]+") do
			local node, rank = strsplit("/", entry);
			node, rank = tonumber(node), tonumber(rank);
			if node and rank then
				CT.ranks[node] = rank;
			end
		end
		OnUpdate();
	end);
end

RegisterComm();
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_LOGIN");
loader:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
loader:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		RegisterComm();
	else
		-- the spells of the custom talents of the new spec
		Send("CTAL_SPEC");
	end
end);
