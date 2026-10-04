-- Retail style talents: the class tree (left column) and the hero tree (middle column, one of 2-3) next to
-- one 3.3.5 spec tree (right). Server: server/talent_custom.cpp (CTAL_*). The points are the 3.3.5 talent points.

PlayerSpellsCustomTalents = { trees = {}, nodes = {}, ranks = {}, choices = {}, hero = 0, loaded = false };
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
	choice = { yellow = "talents-node-choice-yellow", green = "talents-node-choice-green", gray = "talents-node-choice-gray" },
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
-- hero trees of the primary talent tree (specialization tab); specMask 0 = any
local function SpecAllowed(tree)
	if tree.kind ~= 1 or tree.specMask == 0 then
		return true;
	end
	local primary = PlayerSpellsSpecializations and PlayerSpellsSpecializations.GetPrimaryTree() or 0;
	return primary > 0 and bit.band(tree.specMask, bit.lshift(1, primary - 1)) ~= 0;
end

local function TreesOfKind(kind)
	local list = {};
	for _, tree in pairs(CT.trees) do
		if tree.kind == kind and SpecAllowed(tree) then
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

-- hero tree root (row 0): granted with the chosen tree, free, can't be unlearned (server: IsRoot)
local function IsRoot(node)
	local tree = CT.trees[node.tree];
	return tree and tree.kind == 1 and node.row == 0;
end

local function RankOf(node)
	if IsRoot(node) then
		return CT.hero == node.tree and node.maxRank or 0;
	end
	return CT.ranks[node.id] or 0;
end
CT.RankOf = RankOf;

-- choice node (retail octagon): one of two options
local function IsChoice(node)
	return node.choice and #node.choice > 0;
end

-- the option of a learned choice node (1 / 2), nil - not chosen yet
local function ChosenOption(node)
	if not IsChoice(node) or RankOf(node) == 0 then
		return nil;
	end
	return CT.choices[node.id] or 1;
end

local function OptionSpell(node, option, rank)
	local list = option == 2 and node.choice or node.spells;
	return list[math.max(1, math.min(rank, #list))] or list[1];
end

-- the icon of a node: a choice node not chosen yet - both options halved side by side
local function SetNodeIcon(button, node, rank, shape)
	local chosen = ChosenOption(node);
	button.Icon:ClearAllPoints();
	button.Icon:SetPoint("CENTER");
	button.Icon:SetWidth(button.iconSize or ICON_SIZE);
	if IsChoice(node) and not chosen then
		local _, _, left = GetSpellInfo(node.spells[1] or 0);
		local _, _, right = GetSpellInfo(node.choice[1] or 0);
		button.Icon:ClearAllPoints();
		button.Icon:SetPoint("RIGHT", button, "CENTER");
		button.Icon:SetWidth((button.iconSize or ICON_SIZE) / 2);
		button.Icon:SetTexture(left or "Interface\\Icons\\INV_Misc_QuestionMark");
		button.Icon:SetTexCoord(0.08, 0.5, 0.08, 0.92);
		button.Icon2:SetTexture(right or "Interface\\Icons\\INV_Misc_QuestionMark");
		button.Icon2:SetTexCoord(0.5, 0.92, 0.08, 0.92);
		button.Icon2:Show();
		return;
	end
	button.Icon2:Hide();
	local _, _, icon = GetSpellInfo(OptionSpell(node, chosen or 1, rank) or 0);
	if shape == "circle" and icon then
		SetPortraitToTexture(button.Icon, icon);
		button.Icon:SetTexCoord(0, 1, 0, 1);
	else
		button.Icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark");
		button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
	end
end

local function NodeShape(node)
	if IsChoice(node) then
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS.choice.gray) and "choice" or "square";
	end
	return node.maxRank == 1 and "square" or "circle";
end
CT.IsChoice, CT.SetNodeIcon, CT.NodeShape = IsChoice, SetNodeIcon, NodeShape;

-- "yellow" learned (max or partial), "green" can take a point, "gray" closed
local function NodeState(node)
	local rank = RankOf(node);
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
			if req and RankOf(req) >= req.maxRank then
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
-- diagonal edges: the 3.3.5 TaxiFrame line technique (a square line texture turned by tex coords), tinted
local LINE_TEXTURE = "Interface\\TaxiFrame\\UI-Taxi-Line";
local LINE_WIDTH = 32;
local LINE_FACTOR_2 = (128 / 126) / 2;
local LINE_COLOR = { active = { 1, 0.82, 0, 1 }, locked = { 0.45, 0.45, 0.45, 0.9 } };

local function DrawLine(column, x1, y1, x2, y2, atlas)
	local dx, dy = x2 - x1, y2 - y1;
	local full = math.sqrt(dx * dx + dy * dy);
	if full <= 2 * NODE_RADIUS + 1 then
		return;
	end
	-- from edge to edge of the nodes; y up for the math
	local ux, uy = dx / full, dy / full;
	local sx, sy = x1 + ux * NODE_RADIUS, -(y1 + uy * NODE_RADIUS);
	local ex, ey = x2 - ux * NODE_RADIUS, -(y2 - uy * NODE_RADIUS);

	local line = AcquireLine(column);
	line:SetTexture(LINE_TEXTURE);
	local color = atlas == ATLAS.lineActive and LINE_COLOR.active or LINE_COLOR.locked;
	line:SetVertexColor(color[1], color[2], color[3], color[4]);
	line:ClearAllPoints();

	local w = LINE_WIDTH;
	dx, dy = ex - sx, ey - sy;
	local cx, cy = (sx + ex) / 2, (sy + ey) / 2;
	if dx < 0 then
		dx, dy = -dx, -dy;
	end
	local l = math.sqrt(dx * dx + dy * dy);
	local sn, cs = -dy / l, dx / l;
	local sc = sn * cs;
	local bwid, bhgt, BLx, BLy, TLx, TLy, TRx, TRy, BRx, BRy;
	if dy >= 0 then
		bwid = ((l * cs) - (w * sn)) * LINE_FACTOR_2;
		bhgt = ((w * cs) - (l * sn)) * LINE_FACTOR_2;
		BLx, BLy, BRy = (w / l) * sc, sn * sn, (l / w) * sc;
		BRx, TLx, TLy, TRx = 1 - BLy, BLy, 1 - BRy, 1 - BLx;
		TRy = BRx;
	else
		bwid = ((l * cs) + (w * sn)) * LINE_FACTOR_2;
		bhgt = ((w * cs) + (l * sn)) * LINE_FACTOR_2;
		BLx, BLy, BRx = sn * sn, -(l / w) * sc, 1 + (w / l) * sc;
		BRy, TLx, TLy, TRy = BLx, 1 - BRx, 1 - BLx, 1 - BLy;
		TRx = TLy;
	end
	line:SetTexCoord(TLx, TLy, BLx, BLy, TRx, TRy, BRx, BRy);
	line:SetPoint("BOTTOMLEFT", column.Content, "TOPLEFT", cx - bwid, cy - bhgt);
	line:SetPoint("TOPRIGHT", column.Content, "TOPLEFT", cx + bwid, cy + bhgt);
end

-- the two options of a choice node over it (retail flyout)
local flyout;
function CT.ShowChoiceFlyout(owner)
	local node = owner.node;
	if not flyout then
		flyout = CreateFrame("Frame", nil, UIParent);
		flyout:SetFrameStrata("DIALOG");
		flyout:SetWidth(104);
		flyout:SetHeight(56);
		flyout:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } });
		flyout:SetBackdropColor(0, 0, 0, 0.9);
		flyout:EnableMouse(true);
		flyout.buttons = {};
		for option = 1, 2 do
			local button = CreateFrame("Button", nil, flyout);
			button:SetWidth(40);
			button:SetHeight(40);
			button:SetPoint("LEFT", 8 + (option - 1) * 48, 0);
			button.Icon = button:CreateTexture(nil, "ARTWORK");
			button.Icon:SetAllPoints();
			button.Ring = button:CreateTexture(nil, "OVERLAY");
			button.Ring:SetPoint("CENTER");
			button.Ring:SetWidth(48);
			button.Ring:SetHeight(48);
			button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetHyperlink("spell:" .. self.spellID);
				GameTooltip:Show();
			end);
			button:SetScript("OnLeave", GameTooltip_Hide);
			button:SetScript("OnClick", function(self)
				Send("CTAL_LEARN", flyout.node.id, self.option);
				flyout:Hide();
				GameTooltip:Hide();
			end);
			button.option = option;
			flyout.buttons[option] = button;
		end
		-- closes when the mouse leaves it and its node
		flyout:SetScript("OnUpdate", function(self)
			if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
				self:Hide();
			end
		end);
	end
	flyout.node = node;
	flyout.owner = owner;
	local chosen = ChosenOption(node);
	for option = 1, 2 do
		local button = flyout.buttons[option];
		button.spellID = OptionSpell(node, option, math.max(1, RankOf(node))) or 0;
		local _, _, icon = GetSpellInfo(button.spellID);
		button.Icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark");
		button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
		local state = chosen == option and "yellow" or (chosen and "gray" or "green");
		button.Ring:SetAtlas(ATLAS.square[state]);
		button.Icon:SetDesaturated(chosen ~= nil and chosen ~= option);
	end
	flyout:ClearAllPoints();
	flyout:SetPoint("BOTTOM", owner, "TOP", 0, 2);
	flyout:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale());
	flyout:Show();
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
	button.Icon2 = button:CreateTexture(nil, "ARTWORK");
	button.Icon2:SetPoint("LEFT", button, "CENTER");
	button.Icon2:SetWidth(ICON_SIZE / 2);
	button.Icon2:SetHeight(ICON_SIZE);
	button.Icon2:Hide();
	button.Ring = button:CreateTexture(nil, "OVERLAY");
	button.Ring:SetPoint("CENTER");
	button.Ring:SetWidth(NODE_SIZE);
	button.Ring:SetHeight(NODE_SIZE);
	button.Rank = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline");
	button.Rank:SetPoint("CENTER", button, "BOTTOMRIGHT", -2, 4);
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	button:SetScript("OnClick", function(self)
		local node = self.node;
		-- a choice node: the two options; a learned one can switch
		if IsChoice(node) and (self.state == "green" or RankOf(node) > 0) then
			CT.ShowChoiceFlyout(self);
		elseif self.state == "green" then
			Send("CTAL_LEARN", node.id);
		end
	end);
	button:SetScript("OnEnter", function(self)
		local node = self.node;
		local rank = RankOf(node);
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		if IsChoice(node) and not ChosenOption(node) then
			-- not chosen yet: both options
			GameTooltip:AddLine("Выбор таланта", 1, 0.82, 0);
			for option = 1, 2 do
				local name = GetSpellInfo(OptionSpell(node, option, 1) or 0);
				GameTooltip:AddLine(option .. ". " .. (name or UNKNOWN), 1, 1, 1);
			end
		else
			GameTooltip:SetHyperlink("spell:" .. OptionSpell(node, ChosenOption(node) or 1, rank));
		end
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
	local minCol, maxCol;
	for _, node in pairs(CT.nodes) do
		if node.tree == treeId then
			table.insert(list, node);
			minCol = math.min(minCol or node.col, node.col);
			maxCol = math.max(maxCol or node.col, node.col);
		end
	end
	minCol, maxCol = minCol or 0, maxCol or 0;
	table.sort(list, function(a, b) return a.id < b.id; end);
	local spacing = column.spacing or NODE_SPACING;
	local width = column.Content:GetWidth();
	-- centered by the used columns (col may be fractional: 0.5 steps for the retail pyramid)
	local offsetX = (width - (maxCol - minCol) * spacing) / 2 - minCol * spacing;
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
		local shape = NodeShape(node);
		SetNodeIcon(button, node, rank, shape);
		button.Icon:SetDesaturated(state == "gray");
		button.Icon2:SetDesaturated(state == "gray");
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
				local active = RankOf(req) >= req.maxRank;
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

-- icon: an atlas name (retail hero icons, e.g. talents-heroclass-rogue-deathstalker) or a file path
local function RoundIcon(texture, icon)
	if icon and icon ~= "" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icon) then
		texture:SetTexCoord(0, 1, 0, 1);
		texture:SetAtlas(icon);
		return;
	end
	icon = icon ~= "" and icon or "Interface\\Icons\\INV_Misc_QuestionMark";
	SetPortraitToTexture(texture, icon);
end

-- retail HeroTalentsSelectionDialog: a window in the middle, one column per hero tree (name, icon, description,
-- the tree), "Activate" or "Active" at the bottom; the active column glows like the specialization tab
local CHOICE_COLUMN_WIDTH, CHOICE_HEIGHT = 300, 520;

local function CreateChoiceDialog(frame)
	-- the talents behind are dimmed; the window catches the mouse
	local shade = CreateFrame("Frame", nil, frame);
	shade:SetAllPoints(frame);
	shade:SetFrameLevel(frame:GetFrameLevel() + 50);
	shade:EnableMouse(true);
	local shadeTexture = shade:CreateTexture(nil, "BACKGROUND");
	shadeTexture:SetAllPoints();
	shadeTexture:SetTexture(0, 0, 0, 0.6);
	shade:SetScript("OnMouseUp", function() shade:Hide(); end);

	local dialog = CreateFrame("Frame", nil, shade);
	dialog:SetPoint("CENTER", frame, "CENTER", 0, 20);
	dialog:SetHeight(CHOICE_HEIGHT);
	dialog:EnableMouse(true);
	dialog:SetFrameLevel(shade:GetFrameLevel() + 1);
	dialog:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
	});
	dialog:SetBackdropColor(0.05, 0.05, 0.05, 1);
	dialog:SetBackdropBorderColor(0.5, 0.45, 0.35, 1);
	dialog.Background = dialog:CreateTexture(nil, "BACKGROUND", nil, 1);
	dialog.Background:SetPoint("TOPLEFT", 4, -4);
	dialog.Background:SetPoint("BOTTOMRIGHT", -4, 4);
	if not SetAtlasIfExists(dialog.Background, "spec-background") then
		dialog.Background:SetTexture(0.08, 0.08, 0.08, 1);
	end
	dialog.Close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton");
	dialog.Close:SetPoint("TOPRIGHT", 2, 2);
	dialog.Close:SetScript("OnClick", function() shade:Hide(); end);
	dialog.cards = {};
	shade.Dialog = dialog;
	shade:Hide();
	return shade;
end

-- the nodes of a hero tree with their edges; the chosen tree in its real state, another one gray (its root yellow)
local function PreviewTree(preview, treeId, chosen)
	local list, minCol, maxCol = {}, nil, nil;
	for _, node in pairs(CT.nodes) do
		if node.tree == treeId then
			table.insert(list, node);
			minCol = math.min(minCol or node.col, node.col);
			maxCol = math.max(maxCol or node.col, node.col);
		end
	end
	table.sort(list, function(a, b) return a.id < b.id; end);
	minCol, maxCol = minCol or 0, maxCol or 0;
	local spacing = preview.spacing;
	local offsetX = (preview.Content:GetWidth() - (maxCol - minCol) * spacing) / 2 - minCol * spacing;
	local centers, learned = {}, {};
	preview.lineCount = 0;
	for i, node in ipairs(list) do
		local button = preview.buttons[i];
		if not button then
			button = CreateFrame("Frame", nil, preview.Content);
			button:SetWidth(NODE_SIZE);
			button:SetHeight(NODE_SIZE);
			button:SetFrameLevel(preview.Content:GetFrameLevel() + 2);
			button.Icon = button:CreateTexture(nil, "ARTWORK");
			button.Icon:SetPoint("CENTER");
			button.Icon:SetWidth(ICON_SIZE);
			button.Icon:SetHeight(ICON_SIZE);
			button.Icon2 = button:CreateTexture(nil, "ARTWORK");
			button.Icon2:SetPoint("LEFT", button, "CENTER");
			button.Icon2:SetWidth(ICON_SIZE / 2);
			button.Icon2:SetHeight(ICON_SIZE);
			button.Ring = button:CreateTexture(nil, "OVERLAY");
			button.Ring:SetAllPoints();
			button.Rank = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline");
			button.Rank:SetPoint("CENTER", button, "BOTTOMRIGHT", -2, 4);
			button:EnableMouse(true);
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetHyperlink("spell:" .. self.spellID);
				GameTooltip:Show();
			end);
			button:SetScript("OnLeave", GameTooltip_Hide);
			preview.buttons[i] = button;
		end
		local x = offsetX + node.col * spacing;
		local y = preview.top + node.row * spacing;
		centers[node.id] = { x = x, y = y };
		local rank = chosen and RankOf(node) or (node.row == 0 and node.maxRank or 0);
		learned[node.id] = rank >= node.maxRank;
		button:ClearAllPoints();
		button:SetPoint("CENTER", preview.Content, "TOPLEFT", x, -y);
		button.spellID = OptionSpell(node, (chosen and ChosenOption(node)) or 1, rank) or 0;
		local shape = NodeShape(node);
		SetNodeIcon(button, node, chosen and rank or 0, shape);
		button.Icon:SetDesaturated(rank == 0);
		button.Icon2:SetDesaturated(rank == 0);
		button.Ring:SetAtlas(ATLAS[shape][rank > 0 and "yellow" or "gray"]);
		button.Rank:SetText(chosen and node.row > 0 and (rank .. "/" .. node.maxRank) or "");
		button:Show();
	end
	for i = #list + 1, #preview.buttons do
		preview.buttons[i]:Hide();
	end
	for _, node in ipairs(list) do
		for _, required in ipairs(node.requires) do
			local from, to = centers[required], centers[node.id];
			if from and to then
				DrawLine(preview, from.x, from.y, to.x, to.y, learned[required] and ATLAS.lineActive or ATLAS.lineLocked);
			end
		end
	end
	for i = preview.lineCount + 1, #preview.lines do
		preview.lines[i]:Hide();
	end
end

local function ShowChoiceDialog(frame)
	local shade = frame.HeroChoiceDialog;
	local dialog = shade.Dialog;
	local trees = TreesOfKind(1);
	dialog:SetWidth(math.max(1, #trees) * CHOICE_COLUMN_WIDTH + 8);
	for i, tree in ipairs(trees) do
		local card = dialog.cards[i];
		if not card then
			card = CreateFrame("Frame", nil, dialog);
			card:SetWidth(CHOICE_COLUMN_WIDTH);
			card:SetHeight(CHOICE_HEIGHT - 8);
			-- the active column: the yellow glow of the specialization tab
			card.Selected = card:CreateTexture(nil, "BACKGROUND", nil, 2);
			card.Selected:SetAllPoints();
			if not SetAtlasIfExists(card.Selected, "spec-selected-background1") then
				card.Selected:SetTexture(1, 0.82, 0, 0.08);
			end
			card.Selected:SetBlendMode("ADD");
			card.Selected:SetAlpha(0.35);
			if i > 1 then
				card.Divider = card:CreateTexture(nil, "ARTWORK");
				card.Divider:SetPoint("TOP", card, "TOPLEFT", 0, 0);
				card.Divider:SetPoint("BOTTOM", card, "BOTTOMLEFT", 0, 0);
				card.Divider:SetWidth(2);
				card.Divider:SetTexture(0, 0, 0, 0.6);
			end
			card.Name = card:CreateFontString(nil, "ARTWORK", _G.GameFontHighlightHuge and "GameFontHighlightHuge" or "GameFontHighlightLarge");
			card.Name:SetPoint("TOP", 0, -22);
			card.Icon = card:CreateTexture(nil, "ARTWORK");
			card.Icon:SetPoint("TOP", 0, -62);
			card.Icon:SetWidth(100);
			card.Icon:SetHeight(100);
			card.Border = card:CreateTexture(nil, "OVERLAY");
			card.Border:SetPoint("CENTER", card.Icon, "CENTER", 0, -2);
			card.Border:SetWidth(178);
			card.Border:SetHeight(178);
			SetAtlasIfExists(card.Border, "talents-heroclass-ring-mainpane");
			card.Description = card:CreateFontString(nil, "ARTWORK", "GameFontNormal");
			card.Description:SetPoint("TOP", card.Icon, "BOTTOM", 0, -18);
			card.Description:SetWidth(CHOICE_COLUMN_WIDTH - 40);
			card.Description:SetJustifyH("CENTER");
			card.Preview = { Content = CreateFrame("Frame", nil, card), buttons = {}, lines = {}, lineCount = 0, spacing = 46, top = 22 };
			card.Preview.Content:SetPoint("TOP", card, "TOP", 0, -250);
			card.Preview.Content:SetWidth(CHOICE_COLUMN_WIDTH - 20);
			card.Preview.Content:SetHeight(210);
			card.Button = CreateFrame("Button", nil, card, "UIPanelButtonTemplate");
			card.Button:SetWidth(150);
			card.Button:SetHeight(22);
			card.Button:SetPoint("BOTTOM", 0, 22);
			card.Active = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
			card.Active:SetPoint("BOTTOM", 0, 24);
			card.Active:SetTextColor(0.1, 1, 0.1);
			card.Active:SetText(SPEC_ACTIVE or "Активно");
			card.Locked = card:CreateFontString(nil, "ARTWORK", "GameFontDisable");
			card.Locked:SetPoint("BOTTOM", 0, 26);
			dialog.cards[i] = card;
		end
		card:ClearAllPoints();
		card:SetPoint("TOPLEFT", dialog, "TOPLEFT", 4 + (i - 1) * CHOICE_COLUMN_WIDTH, -4);
		local active = tree.id == CT.hero;
		card.Selected:SetShown(active);
		RoundIcon(card.Icon, tree.icon);
		card.Name:SetText(string.upper(tree.name));
		card.Description:SetText(tree.description);
		PreviewTree(card.Preview, tree.id, active);

		local levelOk = UnitLevel("player") >= tree.minLevel;
		card.Active:SetShown(active);
		card.Button:SetShown(not active and levelOk);
		card.Locked:SetShown(not active and not levelOk);
		card.Locked:SetText(string.format(UNIT_LEVEL_TEMPLATE or "Level %d", tree.minLevel));
		card.Button:SetText(TALENT_SPEC_ACTIVATE or "Активировать");
		card.Button:SetScript("OnClick", function()
			if CT.hero ~= 0 then
				StaticPopup_Show("CTAL_CHANGE_HERO", nil, nil, tree.id);
			else
				Send("CTAL_HERO", tree.id);
			end
			shade:Hide();
		end);
		card:Show();
	end
	for i = #trees + 1, #dialog.cards do
		dialog.cards[i]:Hide();
	end
	shade:Show();
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
	hero.top = 80; -- the root node below the ring
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
	if heroTree and not SpecAllowed(heroTree) then
		heroTree = nil; -- the hero tree of another specialization: choose again
	end
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
	Comm_Register("CTAL_TREE", function(id, kind, name, icon, minLevel, description, specMask)
		id = tonumber(id);
		if id then
			CT.trees[id] = { id = id, kind = tonumber(kind) or 0, name = name or "", icon = icon or "", minLevel = tonumber(minLevel) or 10, description = description or "", specMask = tonumber(specMask) or 0 };
		end
	end);
	Comm_Register("CTAL_NODE", function(id, tree, row, col, maxRank, spells, requires, minPoints, choice)
		id = tonumber(id);
		if id then
			CT.nodes[id] = {
				id = id, tree = tonumber(tree) or 0, row = tonumber(row) or 0, col = (tonumber(col) or 0) / 2, -- the server sends half steps
				maxRank = tonumber(maxRank) or 1, spells = SplitNumbers(spells, "/"), requires = SplitNumbers(requires, "/"),
				minPoints = tonumber(minPoints) or 0, choice = SplitNumbers(choice, "/"),
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
		wipe(CT.choices);
		for entry in string.gmatch(list or "", "[^,]+") do
			local node, rank, choice = strsplit("/", entry);
			node, rank = tonumber(node), tonumber(rank);
			if node and rank then
				CT.ranks[node] = rank;
				CT.choices[node] = tonumber(choice) or 1;
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
		-- the request from Setup (UI load) may go out before the comm is up
		Send("CTAL_GET");
	else
		-- the spells of the custom talents of the new spec
		Send("CTAL_SPEC");
	end
end);
