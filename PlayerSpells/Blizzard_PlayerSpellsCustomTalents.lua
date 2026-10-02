-- Retail style talents: the class tree (left column) and the hero tree (middle column, one of 2-3) next to
-- one 3.3.5 spec tree (right). Server: server/talent_custom.cpp (CTAL_*). The points are the 3.3.5 talent points.

PlayerSpellsCustomTalents = { trees = {}, nodes = {}, ranks = {}, hero = 0, loaded = false };
local CT = PlayerSpellsCustomTalents;

local NODE_SPACING = 64;
local NODE_SIZE = 50;
local ICON_SIZE = 44;
local LINE_THICKNESS = 6;
local NODE_RADIUS = 20;
local HEADER_HEIGHT = 44;

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
	local column = CreateFrame("Frame", name, parent);
	local bg = column:CreateTexture(nil, "BACKGROUND");
	bg:SetAllPoints();
	bg:SetTexture(0, 0, 0, 0.35);
	local header = column:CreateTexture(nil, "BORDER");
	header:SetPoint("TOPLEFT");
	header:SetPoint("TOPRIGHT");
	header:SetHeight(HEADER_HEIGHT);
	header:SetTexture(0, 0, 0, 0.6);
	column.Name = column:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	column.Name:SetPoint("TOPLEFT", 12, -13);
	column.Points = column:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge");
	column.Points:SetPoint("TOPRIGHT", -10, -13);
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
	local width = column:GetWidth();
	local offsetX = (width - maxCol * NODE_SPACING) / 2;
	local centers = {};
	for i, node in ipairs(list) do
		local button = NodeButton(column, i);
		button.node = node;
		local x = offsetX + node.col * NODE_SPACING;
		local y = 40 + node.row * NODE_SPACING;
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
-- hero choice
---------------------------------------------------------------------------
local function HeroChoice(column, show)
	column.choices = column.choices or {};
	local trees = TreesOfKind(1);
	for i, tree in ipairs(trees) do
		local card = column.choices[i];
		if not card then
			card = CreateFrame("Frame", nil, column.Content);
			card:SetHeight(150);
			card.Icon = card:CreateTexture(nil, "ARTWORK");
			card.Icon:SetWidth(56);
			card.Icon:SetHeight(56);
			card.Icon:SetPoint("TOPLEFT", 10, -10);
			card.Name = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
			card.Name:SetPoint("TOPLEFT", card.Icon, "TOPRIGHT", 10, -4);
			card.Description = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
			card.Description:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -6);
			card.Description:SetPoint("RIGHT", card, "RIGHT", -10, 0);
			card.Description:SetJustifyH("LEFT");
			card.Button = CreateFrame("Button", nil, card, "UIPanelButtonTemplate");
			card.Button:SetWidth(140);
			card.Button:SetHeight(22);
			card.Button:SetPoint("BOTTOMRIGHT", -10, 10);
			local bg = card:CreateTexture(nil, "BACKGROUND");
			bg:SetAllPoints();
			bg:SetTexture(1, 1, 1, 0.05);
			column.choices[i] = card;
		end
		card:ClearAllPoints();
		card:SetPoint("TOPLEFT", column.Content, "TOPLEFT", 10, -10 - (i - 1) * 160);
		card:SetPoint("RIGHT", column.Content, "RIGHT", -10, 0);
		card.Icon:SetTexture(tree.icon ~= "" and tree.icon or "Interface\\Icons\\INV_Misc_QuestionMark");
		card.Name:SetText(tree.name);
		card.Description:SetText(tree.description);
		local level = UnitLevel("player");
		if level < tree.minLevel then
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
			column.choosing = nil;
		end);
		card:SetShown(show);
	end
	for i = #trees + 1, #column.choices do
		column.choices[i]:Hide();
	end
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
-- layout in the talents frame
---------------------------------------------------------------------------
function CT.Setup(frame)
	if frame.ClassColumn then
		return;
	end
	frame.ClassColumn = CreateColumn(frame, "PlayerSpellsClassTalents");
	frame.ClassColumn:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -14);
	frame.ClassColumn:SetWidth(680);
	frame.ClassColumn:SetHeight(757);

	frame.HeroColumn = CreateColumn(frame, "PlayerSpellsHeroTalents");
	frame.HeroColumn:SetPoint("TOPLEFT", frame.ClassColumn, "TOPRIGHT", 20, 0);
	frame.HeroColumn:SetWidth(400);
	frame.HeroColumn:SetHeight(757);
	local change = CreateFrame("Button", nil, frame.HeroColumn, "UIPanelButtonTemplate");
	change:SetWidth(110);
	change:SetHeight(22);
	change:SetPoint("TOPRIGHT", frame.HeroColumn, "TOPRIGHT", -50, -11);
	change:SetText(CHANGE or "Сменить");
	change:SetScript("OnClick", function()
		frame.HeroColumn.choosing = not frame.HeroColumn.choosing;
		CT.Refresh(frame);
	end);
	frame.HeroColumn.ChangeButton = change;
	Send("CTAL_GET");
end

function CT.Refresh(frame)
	if not frame.ClassColumn then
		return;
	end
	-- class tree
	local classTree = TreesOfKind(0)[1];
	local class = frame.ClassColumn;
	if classTree then
		class.Name:SetText(classTree.name ~= "" and classTree.name or (UnitClass("player")));
		class.Points:SetText(SpentInTree(classTree.id));
		LayoutTree(class, classTree.id);
	else
		class.Name:SetText((UnitClass("player")));
		class.Points:SetText("");
		class.lineCount = 0;
		for _, button in ipairs(class.buttons) do button:Hide(); end
		for _, line in ipairs(class.lines) do line:Hide(); end
	end

	-- hero tree: the choice, or the chosen one
	local hero = frame.HeroColumn;
	local heroTree = CT.trees[CT.hero];
	local choosing = hero.choosing or not heroTree;
	hero.ChangeButton:SetShown(heroTree ~= nil and #TreesOfKind(1) > 1);
	hero.ChangeButton:SetText(choosing and CANCEL or (CHANGE or "Сменить"));
	if choosing then
		hero.Name:SetText(heroTree and heroTree.name or "");
		hero.Points:SetText("");
		hero.lineCount = 0;
		for _, button in ipairs(hero.buttons) do button:Hide(); end
		for _, line in ipairs(hero.lines) do line:Hide(); end
		HeroChoice(hero, true);
	else
		HeroChoice(hero, false);
		hero.Name:SetText(heroTree.name);
		hero.Points:SetText(SpentInTree(heroTree.id));
		LayoutTree(hero, heroTree.id);
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
