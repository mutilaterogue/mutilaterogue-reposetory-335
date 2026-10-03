-- Таланты 3.3.5 в виде Dragonflight (ретейл: Blizzard_SharedTalentUI, TalentButtonArt / TalentEdgeArrow).
-- Раскладку веток по-прежнему делает родной TalentFrame_Update; после него узлы перекрашиваются
-- в круги/квадраты ретейла, а классические ветки и стрелки заменяются линиями между узлами.
--   квадрат - талант, дающий способность (isExceptional), круг - пассивный
--   жёлтый - изучен полностью или частично, зелёный - можно вложить очко, серый - закрыт

PlayerSpellsTalentsDF = {};

-- ретейловские атласы (Interface/Talents); поменять здесь, если в клиенте другие имена
local ATLAS = {
	circle = { yellow = "talents-node-circle-yellow", green = "talents-node-circle-green", gray = "talents-node-circle-gray" },
	square = { yellow = "talents-node-square-yellow", green = "talents-node-square-green", gray = "talents-node-square-gray" },
	lineActive = "talents-arrow-line-yellow",
	lineLocked = "talents-arrow-line-gray",
};
local NODE_SIZE = 50;          -- рамка узла (кнопка 3.3.5 - 37)
local ICON_SIZE_CIRCLE = 45;   -- круглая иконка внутри кольца
local ICON_SIZE_SQUARE = 45;
local LINE_THICKNESS = 6;
local NODE_RADIUS = 18;        -- линии начинаются и заканчиваются у края узла
local POINTS_PER_TIER, PET_POINTS_PER_TIER = 5, 3;
-- retail "pyramid": the nodes of each tier centered (an odd tier stands between the nodes of an even one),
-- the edges diagonal. false - the 3.3.5 grid of Talent.dbc as is
local PYRAMID = true;
local PYRAMID_SPACING_X, PYRAMID_SPACING_Y, PYRAMID_TOP = 62, 62, 30;

local function AtlasCoords(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas);
	if not info then
		return nil;
	end
	return info.file, info.leftTexCoord or info.left, info.rightTexCoord or info.right, info.topTexCoord or info.top, info.bottomTexCoord or info.bottom;
end

---------------------------------------------------------------------------
-- линии
---------------------------------------------------------------------------
local function AcquireLine(tree)
	tree.dfLines = tree.dfLines or {};
	tree.dfLineCount = (tree.dfLineCount or 0) + 1;
	local line = tree.dfLines[tree.dfLineCount];
	if not line then
		line = tree.dfLineParent:CreateTexture(nil, "ARTWORK");
		tree.dfLines[tree.dfLineCount] = line;
	end
	line:Show();
	return line;
end

-- отрезок по горизонтали или вертикали (связи талантов 3.3.5 только такие); вертикальный - атлас повёрнут на 90°
local function DrawSegment(tree, x1, y1, x2, y2, atlas)
	if math.abs(x1 - x2) < 1 and math.abs(y1 - y2) < 1 then
		return;
	end
	local line = AcquireLine(tree);
	line:SetVertexColor(1, 1, 1, 1);
	local file, l, r, t, b = AtlasCoords(atlas);
	if file then
		line:SetTexture(file);
	else
		line:SetTexture(1, 0.82, 0, 0.8);
	end
	line:ClearAllPoints();
	if math.abs(y1 - y2) < 1 then
		local left = math.min(x1, x2);
		line:SetPoint("TOPLEFT", tree.dfLineParent, "TOPLEFT", left, -(y1 - LINE_THICKNESS / 2));
		line:SetWidth(math.abs(x2 - x1));
		line:SetHeight(LINE_THICKNESS);
		if file then
			line:SetTexCoord(l, r, t, b);
		end
	else
		local top = math.min(y1, y2);
		line:SetPoint("TOPLEFT", tree.dfLineParent, "TOPLEFT", x1 - LINE_THICKNESS / 2, -top);
		line:SetWidth(LINE_THICKNESS);
		line:SetHeight(math.abs(y2 - y1));
		if file then
			-- поворот на 90°: UL, LL, UR, LR
			line:SetTexCoord(l, b, r, b, l, t, r, t);
		end
	end
end

-- a line at any angle: the 3.3.5 TaxiFrame technique (a square line texture turned by tex coords), tinted
local LINE_TEXTURE = "Interface\\TaxiFrame\\UI-Taxi-Line";
local LINE_FACTOR_2 = (128 / 126) / 2;

local function DrawDiagonal(tree, x1, y1, x2, y2, active)
	local dx, dy = x2 - x1, y2 - y1;
	local full = math.sqrt(dx * dx + dy * dy);
	if full <= 2 * NODE_RADIUS + 1 then
		return;
	end
	local ux, uy = dx / full, dy / full;
	local sx, sy = x1 + ux * NODE_RADIUS, -(y1 + uy * NODE_RADIUS);
	local ex, ey = x2 - ux * NODE_RADIUS, -(y2 - uy * NODE_RADIUS);
	local line = AcquireLine(tree);
	line:SetTexture(LINE_TEXTURE);
	if active then
		line:SetVertexColor(1, 0.82, 0, 1);
	else
		line:SetVertexColor(0.45, 0.45, 0.45, 0.9);
	end
	line:ClearAllPoints();
	local w = 32;
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
	line:SetPoint("BOTTOMLEFT", tree.dfLineParent, "TOPLEFT", cx - bwid, cy - bhgt);
	line:SetPoint("TOPRIGHT", tree.dfLineParent, "TOPLEFT", cx + bwid, cy + bhgt);
end

local function Center(tree, button)
	local parent = tree.dfLineParent;
	local x = (button:GetLeft() or 0) - (parent:GetLeft() or 0) + button:GetWidth() / 2;
	local y = (parent:GetTop() or 0) - (button:GetTop() or 0) + button:GetHeight() / 2;
	return x, y;
end

---------------------------------------------------------------------------
-- узлы
---------------------------------------------------------------------------
local function HideClassicArt(button)
	local name = button:GetName();
	for _, suffix in ipairs({ "Slot", "RankBorder", "SlotShadow" }) do
		local region = _G[name .. suffix];
		if region then
			region:Hide();
			region:SetAlpha(0);
		end
	end
	local normal = button:GetNormalTexture();
	if normal then
		normal:SetAlpha(0);
	end
	local pushed = button:GetPushedTexture();
	if pushed then
		pushed:SetAlpha(0);
	end
end

local function SkinNode(button, shape, state, iconPath)
	HideClassicArt(button);
	local icon = _G[button:GetName() .. "IconTexture"];
	if icon and iconPath then
		-- иконка - внутри рамки узла (ретейл: маска круга/квадрата; в 3.3.5 масок нет - по размеру)
		local size = shape == "circle" and ICON_SIZE_CIRCLE or ICON_SIZE_SQUARE;
		icon:ClearAllPoints();
		icon:SetPoint("CENTER", button, "CENTER", 0, 0);
		icon:SetWidth(size);
		icon:SetHeight(size);
		if shape == "circle" then
			SetPortraitToTexture(icon, iconPath);
			icon:SetTexCoord(0, 1, 0, 1);
		else
			icon:SetTexture(iconPath);
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
		end
		icon:SetDesaturated(state == "gray");
		icon:SetVertexColor(1, 1, 1);
	end
	button.Node:SetAtlas(ATLAS[shape][state]);
	button.Node:SetWidth(NODE_SIZE);
	button.Node:SetHeight(NODE_SIZE);
	button.Node:Show();

	local rank = _G[button:GetName() .. "Rank"];
	if rank then
		rank:ClearAllPoints();
		rank:SetPoint("CENTER", button, "BOTTOMRIGHT", -2, 4);
		rank:SetFontObject(GameFontHighlightSmallOutline or GameFontHighlightSmall);
		if state == "green" then
			rank:SetTextColor(0.1, 1, 0.1);
		elseif state == "yellow" then
			rank:SetTextColor(1, 0.82, 0);
		else
			rank:SetTextColor(0.6, 0.6, 0.6);
		end
	end
end

-- после TalentFrame_Update(tree): узлы и линии в стиле DF
function PlayerSpellsTalentsDF.SkinTree(tree)
	local name = tree:GetName();
	local tab, pet, group = tree.selectedTab, tree.pet, tree.talentGroup;
	if not tab then
		return;
	end
	tree.dfLineParent = tree.dfLineParent or _G[name .. "ScrollChildFrame"];
	tree.dfLineCount = 0;

	-- классические ветки и стрелки - прочь
	for i = 1, 30 do
		local branch, arrow = _G[name .. "Branch" .. i], _G[name .. "Arrow" .. i];
		if branch then branch:Hide(); end
		if arrow then arrow:Hide(); end
	end

	local preview = GetCVarBool("previewTalents");
	local active = group == GetActiveTalentGroup(false, pet);
	local unspent = (GetUnspentTalentPoints(false, pet, group) or 0) - (GetGroupPreviewTalentPointsSpent(pet, group) or 0);
	local treePoints = (tree.pointsSpent or 0) + (preview and tree.previewPointsSpent or 0);
	local perTier = pet and PET_POINTS_PER_TIER or POINTS_PER_TIER;

	local byPosition, info = {}, {};
	local numTalents = GetNumTalents(tab, false, pet) or 0;
	for id = 1, numTalents do
		local button = _G[name .. "Talent" .. id];
		local talentName, iconPath, tier, column, rank, maxRank, isExceptional, meetsPrereq, previewRank, meetsPreviewPrereq = GetTalentInfo(tab, id, false, pet, group);
		if button and talentName and button:IsShown() then
			local shownRank = preview and previewRank or rank;
			local meets = preview and meetsPreviewPrereq or meetsPrereq;
			local tierUnlocked = treePoints >= (tier - 1) * perTier;
			local canAdd = active and meets and tierUnlocked and unspent > 0 and shownRank < maxRank;
			local state;
			if shownRank >= maxRank then
				state = "yellow";
			elseif canAdd then
				state = "green";
			elseif shownRank > 0 then
				state = "yellow";
			else
				state = "gray";
			end
			SkinNode(button, isExceptional and "square" or "circle", state, iconPath);
			byPosition[tier .. ":" .. column] = button;
			info[id] = { button = button, rank = shownRank, maxRank = maxRank, tier = tier, column = column };
		end
	end

	if PYRAMID then
		-- each tier centered in the tree by its column order
		local tiers = {};
		for _, data in pairs(info) do
			tiers[data.tier] = tiers[data.tier] or {};
			table.insert(tiers[data.tier], data);
		end
		local parent = tree.dfLineParent;
		local width = parent:GetWidth();
		for tier, list in pairs(tiers) do
			table.sort(list, function(a, b) return a.column < b.column; end);
			for k, data in ipairs(list) do
				local x = width / 2 + (k - (#list + 1) / 2) * PYRAMID_SPACING_X;
				local y = PYRAMID_TOP + (tier - 1) * PYRAMID_SPACING_Y;
				data.button:ClearAllPoints();
				data.button:SetPoint("CENTER", parent, "TOPLEFT", x, -y);
				data.button.dfX, data.button.dfY = x, y;
			end
		end
	end

	-- связи: от требуемого таланта - по горизонтали на его ряду, потом вниз
	for id, data in pairs(info) do
		local reqTier, reqColumn = GetTalentPrereqs(tab, id, false, pet, group);
		local from = reqTier and byPosition[reqTier .. ":" .. reqColumn];
		if from then
			local fromData;
			for _, other in pairs(info) do
				if other.button == from then
					fromData = other;
				end
			end
			local atlas = (data.rank > 0 or (fromData and fromData.rank >= fromData.maxRank)) and ATLAS.lineActive or ATLAS.lineLocked;
			local x1, y1 = Center(tree, from);
			local x2, y2 = Center(tree, data.button);
			if PYRAMID then
				x1, y1 = from.dfX, from.dfY;
				x2, y2 = data.button.dfX, data.button.dfY;
				DrawDiagonal(tree, x1, y1, x2, y2, atlas == ATLAS.lineActive);
			elseif math.abs(x1 - x2) < 1 then
				DrawSegment(tree, x1, y1 + NODE_RADIUS, x2, y2 - NODE_RADIUS, atlas);
			elseif math.abs(y1 - y2) < 1 then
				local dir = x2 > x1 and 1 or -1;
				DrawSegment(tree, x1 + dir * NODE_RADIUS, y1, x2 - dir * NODE_RADIUS, y2, atlas);
			else
				local dir = x2 > x1 and 1 or -1;
				DrawSegment(tree, x1 + dir * NODE_RADIUS, y1, x2, y1, atlas);
				DrawSegment(tree, x2, y1, x2, y2 - NODE_RADIUS, atlas);
			end
		end
	end

	for i = tree.dfLineCount + 1, #(tree.dfLines or {}) do
		tree.dfLines[i]:Hide();
	end
end
