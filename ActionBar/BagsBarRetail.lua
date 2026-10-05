-- The retail (12.1.5) bags bar on 3.3.5 (BagsBarRetail.xml): the stock bag buttons with the retail look
-- (MainMenuBarBagButtons.lua UpdateTextures, CircularItemButtonTemplate) and the retail layout (BagsBar.lua):
-- the backpack at BackpackFrame's right, the expand arrow, the bags leftwards. The bags collapse behind the arrow
-- (retail CVar expandBagBar, registered here).

local BAG_SLOTS = { "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot" };
local BAG_SIZE = 30;
local BACKPACK_SIZE = 48;
local TOGGLE_WIDTH = 10;

local function SetAtlasIf(texture, atlas)
	if texture and texture.SetAtlas and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas);
	end
end

-- the round icon (CircularItemButtonTemplate: TempPortraitAlphaMask inset 2 / 4)
local function AddCircleMask(button, left, top, right, bottom)
	local icon = _G[button:GetName() .. "IconTexture"];
	if not (icon and button.CreateMaskTexture) then
		return;
	end
	local mask = button:CreateMaskTexture(nil, "BORDER");
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask");
	mask:SetPoint("TOPLEFT", button, "TOPLEFT", left, top);
	mask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", right, bottom);
	icon:AddMaskTexture(mask);
	button.CircleMask = mask;
end

-- BaseBagSlotButtonMixin:UpdateTextures: the slot ring (empty without a bag), its highlight
local function UpdateTextures(button)
	local atlas, highlightAtlas;
	if button == MainMenuBarBackpackButton then
		atlas, highlightAtlas = "bag-main", "bag-main-highlight";
	else
		local hasBag = GetInventoryItemTexture("player", button:GetID()) ~= nil;
		atlas, highlightAtlas = hasBag and "bag-border" or "bag-border-empty", "bag-border-highlight";
	end
	for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture() }) do
		texture:ClearAllPoints();
		texture:SetAllPoints(button);
		SetAtlasIf(texture, atlas);
		texture:SetVertexColor(1, 1, 1);
	end
	local highlight = button:GetHighlightTexture();
	highlight:ClearAllPoints();
	highlight:SetAllPoints(button);
	SetAtlasIf(highlight, highlightAtlas);
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(0.4);
	-- the open bag: the highlight ring (retail SlotHighlightTexture), the stock check texture
	local checked = button:GetCheckedTexture();
	if checked then
		checked:ClearAllPoints();
		checked:SetAllPoints(button);
		SetAtlasIf(checked, highlightAtlas);
		checked:SetBlendMode("BLEND");
		checked:SetAlpha(1);
	end
end

local function ApplyButton(button, size)
	button:SetWidth(size);
	button:SetHeight(size);
	local icon = _G[button:GetName() .. "IconTexture"];
	if icon then
		icon:ClearAllPoints();
		icon:SetAllPoints(button);
	end
	UpdateTextures(button);
end

local function IsExpanded()
	return GetCVar("expandBagBar") ~= "0";
end

-- BagsBarMixin:Layout + the expand state
function BagsBarRetail_Layout()
	local expanded = IsExpanded();
	MainMenuBarBackpackButton:ClearAllPoints();
	MainMenuBarBackpackButton:SetPoint("RIGHT", BackpackFrame, "RIGHT");
	local previous = BagBarExpandToggle;
	for _, name in ipairs(BAG_SLOTS) do
		local button = _G[name];
		button:ClearAllPoints();
		button:SetPoint("RIGHT", previous, "LEFT");
		if expanded then
			button:Show();
		else
			button:Hide();
		end
		previous = button;
	end
	BackpackFrame:SetWidth(BACKPACK_SIZE + TOGGLE_WIDTH + #BAG_SLOTS * BAG_SIZE);
	BackpackFrame:SetHeight(BACKPACK_SIZE);

	-- the arrow points where the bags go: left to open them, right to put them away (the atlas points left)
	local info = C_Texture.GetAtlasInfo("bag-arrow");
	if info then
		local l, r = info.leftTexCoord or info.left, info.rightTexCoord or info.right;
		local t, b = info.topTexCoord or info.top, info.bottomTexCoord or info.bottom;
		for _, texture in ipairs({ BagBarExpandToggle:GetNormalTexture(), BagBarExpandToggle:GetPushedTexture(),
			BagBarExpandToggle:GetHighlightTexture() }) do
			if expanded then
				texture:SetTexCoord(r, l, t, b);
			else
				texture:SetTexCoord(l, r, t, b);
			end
		end
	end
end

function BagBarExpandToggle_OnClick()
	SetCVar("expandBagBar", IsExpanded() and "0" or "1");
	BagsBarRetail_Layout();
end

function BagsBarRetail_OnLoad(self)
	if GetCVar("expandBagBar") == nil and RegisterCVar then
		pcall(RegisterCVar, "expandBagBar", "1");
	end

	ApplyButton(MainMenuBarBackpackButton, BACKPACK_SIZE);
	AddCircleMask(MainMenuBarBackpackButton, 4, -4, -6, 6);
	local count = MainMenuBarBackpackButtonCount;
	if count then
		count:ClearAllPoints();
		count:SetPoint("CENTER", MainMenuBarBackpackButton, "CENTER", 0, -10);
	end
	for _, name in ipairs(BAG_SLOTS) do
		local button = _G[name];
		ApplyButton(button, BAG_SIZE);
		AddCircleMask(button, 2, -2, -4, 4);
	end

	-- the stock updates reset the slot texture (SetItemButtonTexture & co): the ring again after them
	hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
		if button.isBag and button.CircleMask then
			UpdateTextures(button);
		end
	end);

	BagsBarRetail_Layout();
end
