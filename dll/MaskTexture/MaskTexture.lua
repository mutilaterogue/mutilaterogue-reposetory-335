-- Retail mask texture methods on top of the WotLKExtensions MaskTexture patch (TextureAddMask & co).
--   frame:CreateMaskTexture([name, layer, inherits])  a Texture that is not drawn, only masks
--   texture:AddMaskTexture(mask) / RemoveMaskTexture(mask) / GetNumMaskTextures() / GetMaskTexture(index)
-- One mask per texture. A mask must stay shown (a hidden region is not laid out), it is not drawn anyway.
-- loaded early (FrameXML.toc snippets): no WorldFrame/UIParent yet
local helper = CreateFrame("Frame");
helper:Hide();

-- /masktest is registered even without the DLL functions: it says what is missing
local function MaskTestMissing()
	print("masktest: TextureAddMask =", TextureAddMask, "- the DLL functions are not registered (CustomLua::RegisterFunctions / OOBLUAFUNCTIONS_PATCH)");
end

if not TextureAddMask then
	helper:RegisterEvent("PLAYER_LOGIN");
	helper:SetScript("OnEvent", function()
		SLASH_MASKTEST1 = "/masktest";
		SlashCmdList["MASKTEST"] = MaskTestMissing;
	end);
	return;
end

local textureMethods = getmetatable(helper:CreateTexture()).__index;

function textureMethods:AddMaskTexture(mask)
	TextureAddMask(self, mask);
	self.maskTexture = mask;
end

function textureMethods:RemoveMaskTexture(mask)
	TextureRemoveMask(self, mask);
	if not mask or self.maskTexture == mask then
		self.maskTexture = nil;
	end
end

function textureMethods:GetNumMaskTextures()
	return self.maskTexture and 1 or 0;
end

function textureMethods:GetMaskTexture(index)
	if index == 1 then
		return self.maskTexture;
	end
end

local function CreateMaskTexture(self, name, layer, inherits, subLevel)
	local mask = self:CreateTexture(name, layer or "ARTWORK", inherits);
	TextureSetIsMask(mask, true);
	return mask;
end

-- every frame type has its own method table
local frameTypes = {
	"Frame", "Button", "CheckButton", "StatusBar", "Slider", "ScrollFrame", "EditBox", "Cooldown",
	"Model", "PlayerModel", "DressUpModel", "TabardModel", "MessageFrame", "ScrollingMessageFrame",
	"SimpleHTML", "ColorSelect", "GameTooltip",
};
for _, frameType in ipairs(frameTypes) do
	local ok, frame = pcall(CreateFrame, frameType);
	if ok and frame then
		getmetatable(frame).__index.CreateMaskTexture = CreateMaskTexture;
		frame:Hide();
	end
end

-- /masktest: a round question mark icon in the middle of the screen (again to hide it)
-- registered at login: SlashCmdList comes from ChatFrame, later in the toc
local function MaskTest()
	local f = MaskTestFrame;
	if f then
		if f:IsShown() then f:Hide(); else f:Show(); end
		return;
	end
	f = CreateFrame("Frame", "MaskTestFrame", UIParent);
	f:SetSize(128, 128);
	f:SetPoint("CENTER");
	local icon = f:CreateTexture(nil, "ARTWORK");
	icon:SetAllPoints();
	icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark");
	local mask = f:CreateMaskTexture();
	mask:SetAllPoints(icon);
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask");
	icon:AddMaskTexture(mask);
	-- the same icon without a mask on the right, for comparison
	local plain = f:CreateTexture(nil, "ARTWORK");
	plain:SetSize(128, 128);
	plain:SetPoint("LEFT", f, "RIGHT", 16, 0);
	plain:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark");
	print("masktest: TextureGetMask =", TextureGetMask(icon));
end

helper:RegisterEvent("PLAYER_LOGIN");
helper:SetScript("OnEvent", function()
	SLASH_MASKTEST1 = "/masktest";
	SlashCmdList["MASKTEST"] = MaskTest;
end);
