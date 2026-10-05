-- The retail (12.1.5) main action bar on 3.3.5.
-- The stock buttons stay (secure templates, bindings, pages, stances: ActionButton.lua, BonusActionBarFrame.lua);
-- here they get the retail button art (Blizzard_ActionBar\ActionButtonTemplate.xml, ActionButtonOverrides.lua)
-- and sit on MainActionBar (MainActionBar.xml). The stock stone bar art is hidden.

local BUTTON_SIZE = 45;
local BUTTON_PADDING = 2;
local NUM_BUTTONS = 12;

local function SetAtlasIf(texture, atlas, useSize)
	if texture and texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas, useSize);
		return true;
	end
	return false;
end

-- a nine slice atlas over a frame's rect (margins: the atlas' slice data in AtlasInfo)
local function SliceAtlas(frame, atlas, layer, subLevel, region)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas);
	local file = info and (info.filename or info.file);
	local u1, u2 = info and (info.leftTexCoord or info.left), info and (info.rightTexCoord or info.right);
	local v1, v2 = info and (info.topTexCoord or info.top), info and (info.bottomTexCoord or info.bottom);
	if not (file and u1 and u2 and v1 and v2 and info.width and info.width > 0) then
		return;
	end
	local left, top, right, bottom = 0, 0, 0, 0;
	local raw = AtlasInfo and AtlasInfo[file] and (AtlasInfo[file][atlas] or AtlasInfo[file][strlower(atlas)]);
	if info.sliceData then
		local slice = info.sliceData;
		left, top, right, bottom = slice.marginLeft, slice.marginTop, slice.marginRight, slice.marginBottom;
	elseif raw and raw.slice then
		left, top, right, bottom = raw.slice[1], raw.slice[2], raw.slice[3], raw.slice[4];
	end
	local du, dv = (u2 - u1) / info.width, (v2 - v1) / info.height;
	local cols = {
		{ u1, u1 + left * du, "LEFT", 0, "LEFT", left },
		{ u1 + left * du, u2 - right * du, "LEFT", left, "RIGHT", -right },
		{ u2 - right * du, u2, "RIGHT", -right, "RIGHT", 0 },
	};
	local rows = {
		{ v1, v1 + top * dv, "TOP", 0, "TOP", -top },
		{ v1 + top * dv, v2 - bottom * dv, "TOP", -top, "BOTTOM", bottom },
		{ v2 - bottom * dv, v2, "BOTTOM", bottom, "BOTTOM", 0 },
	};
	for _, row in ipairs(rows) do
		for _, col in ipairs(cols) do
			local piece = frame:CreateTexture(nil, layer);
			if subLevel and piece.SetDrawLayer then
				piece:SetDrawLayer(layer, subLevel);
			end
			piece:SetTexture(file);
			piece:SetTexCoord(col[1], col[2], row[1], row[2]);
			piece:SetPoint("TOPLEFT", region, row[3] .. col[3], col[4], row[4]);
			piece:SetPoint("BOTTOMRIGHT", region, row[5] .. col[5], col[6], row[6]);
		end
	end
end

---------------------------------------------------------------------------
-- the retail button art
---------------------------------------------------------------------------

-- the frame textures the stock code resets (ActionButton_Update sets UI-Quickslot / UI-Quickslot2 as the normal texture)
local function ActionButtonRetail_UpdateNormal(button)
	local normal = button:GetNormalTexture();
	if normal then
		SetAtlasIf(normal, "UI-HUD-ActionBar-IconFrame");
		normal:SetDrawLayer("OVERLAY");
		normal:ClearAllPoints();
		normal:SetPoint("TOPLEFT");
		normal:SetWidth(46);
		normal:SetHeight(45);
	end
end

local function ActionButtonRetail_UpdateHotkey(button)
	local hotkey = _G[button:GetName() .. "HotKey"];
	if hotkey then
		hotkey:ClearAllPoints();
		hotkey:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -5);
	end
end

local function FrameTexture(texture, atlas, layer)
	if not texture then
		return;
	end
	SetAtlasIf(texture, atlas);
	texture:ClearAllPoints();
	texture:SetPoint("TOPLEFT");
	texture:SetWidth(46);
	texture:SetHeight(45);
	if layer then
		texture:SetDrawLayer(layer);
	end
end

function ActionButtonRetail_Apply(button)
	if button.retailArt then
		return;
	end
	button.retailArt = true;
	local name = button:GetName();
	button:SetWidth(BUTTON_SIZE);
	button:SetHeight(BUTTON_SIZE);

	-- the icon: the whole button, its corners cut by the retail mask
	local icon = _G[name .. "Icon"];
	icon:ClearAllPoints();
	icon:SetAllPoints(button);
	if button.CreateMaskTexture then
		local mask = button:CreateMaskTexture(nil, "BACKGROUND");
		SetAtlasIf(mask, "UI-HUD-ActionBar-IconFrame-Mask");
		mask:SetWidth(64);
		mask:SetHeight(64);
		mask:SetPoint("CENTER", icon, "CENTER");
		icon:AddMaskTexture(mask);
		button.IconMask = mask;
	end

	ActionButtonRetail_UpdateNormal(button);
	FrameTexture(button:GetPushedTexture(), "UI-HUD-ActionBar-IconFrame-Down", "OVERLAY");
	FrameTexture(button:GetHighlightTexture(), "UI-HUD-ActionBar-IconFrame-Mouseover");
	FrameTexture(button:GetCheckedTexture(), "UI-HUD-ActionBar-IconFrame-Mouseover");
	FrameTexture(_G[name .. "Flash"], "UI-HUD-ActionBar-IconFrame-Flash", "ARTWORK");
	local border = _G[name .. "Border"];
	FrameTexture(border, "UI-HUD-ActionBar-IconFrame-Border", "OVERLAY");
	if border then
		border:SetBlendMode("BLEND");
	end

	local hotkey = _G[name .. "HotKey"];
	if hotkey then
		hotkey:SetWidth(32);
	end
	ActionButtonRetail_UpdateHotkey(button);
	local count = _G[name .. "Count"];
	if count then
		count:ClearAllPoints();
		count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 5);
	end
	local cooldown = _G[name .. "Cooldown"];
	if cooldown then
		cooldown:ClearAllPoints();
		cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", 3, -3);
		cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 3);
	end
end

hooksecurefunc("ActionButton_Update", function(self)
	if self.retailArt then
		ActionButtonRetail_UpdateNormal(self);
	end
end);

-- retail tints the icon, not the frame (the stock code turns the frame blue without mana)
hooksecurefunc("ActionButton_UpdateUsable", function(self)
	if self.retailArt then
		local normal = self:GetNormalTexture();
		if normal then
			normal:SetVertexColor(1, 1, 1);
		end
	end
end);

hooksecurefunc("ActionButton_UpdateHotkeys", function(self)
	if self.retailArt then
		ActionButtonRetail_UpdateHotkey(self);
	end
end);

---------------------------------------------------------------------------
-- the stance / form bar (BonusActionBarFrame): shown over the main buttons, no slide
---------------------------------------------------------------------------

-- replaces the stock slide (BonusActionBarFrame.lua): the bonus buttons sit right on the main ones
function BonusActionBar_OnUpdate(self)
	if self.mode == "show" then
		self:ClearAllPoints();
		self:SetAllPoints(MainActionBar);
		self.state = "top";
		self:Show();
	elseif self.mode == "hide" then
		self:ClearAllPoints();
		self:SetAllPoints(MainActionBar);
		self.state = "bottom";
		self:Hide();
	end
	self.completed = 1;
	self.mode = "none";
end

-- the main buttons under the bonus ones: invisible (alpha is not protected, stances change in combat)
local function MainActionBar_UpdateMainButtonsAlpha()
	local alpha = BonusActionBarFrame:IsShown() and 0 or 1;
	for i = 1, NUM_BUTTONS do
		_G["ActionButton" .. i]:SetAlpha(alpha);
	end
end

---------------------------------------------------------------------------
-- the bar
---------------------------------------------------------------------------

local function MainActionBar_UpdateEndCaps(self)
	local horde = UnitFactionGroup("player") == "Horde";
	SetAtlasIf(self.EndCaps.LeftEndCap, horde and "UI-HUD-ActionBar-Wyvern-Left" or "UI-HUD-ActionBar-Gryphon-Left");
	SetAtlasIf(self.EndCaps.RightEndCap, horde and "UI-HUD-ActionBar-Wyvern-Right" or "UI-HUD-ActionBar-Gryphon-Right");
end

local function MainActionBar_UpdatePage(self)
	self.ActionBarPageNumber.Text:SetText(GetActionBarPage());
end

local function MainActionBar_HideStockArt()
	for _, name in ipairs({ "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
		"MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarPageNumber", "ActionBarUpButton", "ActionBarDownButton",
		"BonusActionBarTexture0", "BonusActionBarTexture1" }) do
		local region = _G[name];
		if region then
			region:Hide();
		end
	end
	-- the stock bar was the stone strip under the buttons; now it holds only the experience bar, at the screen's bottom
	MainMenuBar:SetHeight(MainMenuExpBar:GetHeight());
end

function MainActionBar_OnLoad(self)
	-- under the buttons (MainMenuBarArtFrame's children); the gryphons and the page arrows over them
	local level = MainMenuBarArtFrame:GetFrameLevel();
	self:SetFrameLevel(level);
	self.EndCaps:SetFrameLevel(level + 5);
	self.ActionBarPageNumber:SetFrameLevel(level + 5);

	SliceAtlas(self, "UI-HUD-ActionBar-Frame", "BACKGROUND", -3, self.BorderArt);

	MainActionBar_HideStockArt();

	for i = 1, NUM_BUTTONS do
		local button = _G["ActionButton" .. i];
		ActionButtonRetail_Apply(button);
		button:ClearAllPoints();
		button:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (BUTTON_SIZE + BUTTON_PADDING), 0);

		local bonus = _G["BonusActionButton" .. i];
		ActionButtonRetail_Apply(bonus);
		bonus:ClearAllPoints();
		bonus:SetPoint("TOPLEFT", button, "TOPLEFT");
	end

	BonusActionBarFrame:ClearAllPoints();
	BonusActionBarFrame:SetAllPoints(self);
	BonusActionBarFrame:HookScript("OnShow", MainActionBar_UpdateMainButtonsAlpha);
	BonusActionBarFrame:HookScript("OnHide", MainActionBar_UpdateMainButtonsAlpha);
	MainActionBar_UpdateMainButtonsAlpha();

	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("ACTIONBAR_PAGE_CHANGED");
	self:RegisterEvent("UNIT_FACTION");
	MainActionBar_UpdatePage(self);
end

function MainActionBar_OnEvent(self, event, ...)
	if event == "ACTIONBAR_PAGE_CHANGED" then
		MainActionBar_UpdatePage(self);
	elseif event == "UNIT_FACTION" then
		if ... == "player" then
			MainActionBar_UpdateEndCaps(self);
		end
	else
		MainActionBar_UpdateEndCaps(self);
		MainActionBar_UpdatePage(self);
		MainActionBar_HideStockArt();
	end
end
